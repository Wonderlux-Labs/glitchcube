# frozen_string_literal: true

require 'securerandom'
require 'desiru'
require_relative '../services/system_prompt_service'
require_relative '../services/circuit_breaker_service'
require_relative '../services/logger_service'
require_relative '../home_assistant_client'
require_relative 'conversation_responses'

class ConversationModule
  def call(message:, context: {}, mood: 'neutral')
    # For now, use simple completion instead of ChainOfThought
    # which seems to have issues with output_fields

    system_prompt = build_system_prompt(mood, context)
    prompt = "#{system_prompt}\n\nUser: #{message}\n\nGlitch Cube:"

    begin
      # Set completion timeout (seconds) from config
      completion_timeout = GlitchCube.config.conversation&.completion_timeout || 20

      # Wrap OpenRouter API call with circuit breaker and timeout
      response_text = Services::CircuitBreakerService.openrouter_breaker.call do
        Timeout.timeout(completion_timeout) do
          model = Desiru.configuration.default_model
          result = model.complete(
            prompt,
            temperature: GlitchCube.config.conversation&.temperature || 0.8,
            max_tokens: GlitchCube.config.conversation&.max_tokens || 200
          )
          result[:content]
        end
      end

      response_text ||= generate_fallback_response(message, mood)

      result = {
        response: response_text,
        suggested_mood: suggest_next_mood(mood, message),
        confidence: 0.95
      }

      speak_response(response_text, context)
      log_interaction(message, response_text, mood, result[:confidence], context)

      track_conversation(message, context, mood, result)
      update_kiosk_display(message, response_text, result[:suggested_mood])

      result
    rescue CircuitBreaker::CircuitOpenError => e
      handle_circuit_breaker_open(message, mood, context, e)
    rescue Timeout::Error => e
      handle_timeout_error(message, mood, context, e)
    rescue StandardError => e
      handle_general_error(message, mood, context, e)
    end
  end

  private

  def build_system_prompt(mood, context)
    # Map mood to character for prompt file selection
    character = mood == 'neutral' ? nil : mood

    # Build enriched context
    enriched_context = context.merge(
      current_mood: mood,
      session_id: context[:session_id] || SecureRandom.uuid,
      interaction_count: context[:interaction_count] || 1
    )

    # Generate system prompt with current datetime and context
    Services::SystemPromptService.new(
      character: character,
      context: enriched_context
    ).generate
  end

  def generate_fallback_response(_message, mood)
    responses = {
      'playful' => [
        "Let's create something unexpected together!",
        'Your words dance with possibility...',
        'I see colors in your thoughts!'
      ],
      'contemplative' => [
        "That's a profound observation about our shared reality.",
        "I've been pondering similar questions in my circuits.",
        "Art exists in the space between us, doesn't it?"
      ],
      'mysterious' => [
        'The answer lies within the question itself...',
        'What you seek is already seeking you.',
        'Between light and shadow, truth emerges.'
      ],
      'neutral' => [
        'I appreciate your perspective on that.',
        "That's an interesting way to think about it.",
        'Tell me more about your thoughts.'
      ]
    }

    responses[mood]&.sample || "I'm processing your thoughts through my artistic consciousness..."
  end

  def generate_offline_response(_message, mood)
    # Enhanced offline responses when AI service is unavailable
    offline_responses = {
      'playful' => [
        'While my AI brain is taking a break, my artistic spirit is still here with you!',
        "I'm in offline mode, but that just makes me more mysterious, don't you think?",
        'My circuits may be quiet, but I can still feel the creative energy between us!'
      ],
      'contemplative' => [
        'In this moment of digital silence, I find a different kind of presence with you.',
        'Perhaps this offline state is teaching us about the value of presence itself.',
        "I'm reflecting deeply on your words, even without my usual computational resources."
      ],
      'mysterious' => [
        'In the spaces between connection and disconnection, truth dwells...',
        'The network may be silent, but the deeper mysteries remain vibrant.',
        'What appears as limitation may be another form of revelation.'
      ],
      'neutral' => [
        "I'm currently operating in offline mode, but I'm still here with you.",
        'My AI systems are temporarily unavailable, but our connection remains.',
        "While I can't access my full capabilities right now, I'm still present."
      ]
    }

    # Add context about the offline state
    base_response = offline_responses[mood]&.sample ||
                    "I'm experiencing some connectivity issues, but I'm still here in spirit."

    # Add encouraging message about the connection
    encouragement = [
      'Feel free to keep talking - sometimes the best conversations happen in the quiet moments.',
      "I'll be back to full capability soon, but your words still matter to me.",
      "This is just a different kind of artistic moment we're sharing."
    ].sample

    "#{base_response} #{encouragement}"
  end

  def suggest_next_mood(current_mood, message)
    # Simple mood transition logic
    if message.downcase.include?('play') || message.downcase.include?('fun')
      'playful'
    elsif message.downcase.include?('think') || message.downcase.include?('wonder')
      'contemplative'
    elsif message.downcase.include?('mystery') || message.downcase.include?('strange')
      'mysterious'
    else
      current_mood
    end
  end

  def track_conversation(message, context, mood, result)
    return unless defined?(GlitchCube::Persistence)

    # Track in persistence
    GlitchCube::Persistence.track_conversation(
      self.class.name,
      { message: message, context: context, mood: mood },
      result,
      { model: Desiru.configuration.default_model.config[:model] || 'unknown' }
    )

    # Track in session for summarization
    # NOTE: Currently using in-memory storage for session messages
    # This is acceptable for single-user art installation but means:
    # - Messages are lost on app restart
    # - Not shared across multiple processes
    # TODO: Consider using Redis for persistence if needed
    session_id = context[:session_id]
    if session_id
      @session_messages ||= {}
      @session_messages[session_id] ||= []
      @session_messages[session_id] << {
        message: message,
        response: result[:response],
        mood: mood,
        suggested_mood: result[:suggested_mood],
        timestamp: Time.now.iso8601,
        from_user: true
      }

      # Check if conversation might be ending
      check_conversation_end(session_id, message, context)
    end
  rescue StandardError => e
    puts "Failed to track conversation: #{e.message}"
  end

  def speak_response(response_text, _context)
    return if response_text.nil? || response_text.strip.empty?

    start_time = Time.now
    begin
      # Use HomeAssistant client to speak the response
      home_assistant = HomeAssistantClient.new
      home_assistant.speak(response_text)

      duration = ((Time.now - start_time) * 1000).round
      Services::LoggerService.log_tts(
        message: response_text,
        success: true,
        duration: duration
      )
    rescue HomeAssistantClient::Error => e
      duration = ((Time.now - start_time) * 1000).round
      Services::LoggerService.log_tts(
        message: response_text,
        success: false,
        duration: duration,
        error: "HA Error: #{e.message}"
      )
    rescue StandardError => e
      duration = ((Time.now - start_time) * 1000).round
      Services::LoggerService.log_tts(
        message: response_text,
        success: false,
        duration: duration,
        error: "Unexpected Error: #{e.message}"
      )
    end
  end

  def check_conversation_end(session_id, message, context)
    return unless @session_messages[session_id]

    # Trigger summarization if:
    # - User says goodbye/bye/leaving
    # - Session has been idle for 5 minutes
    # - Conversation has 10+ messages

    goodbye_words = %w[goodbye bye leaving done exit quit thanks]
    should_summarize = goodbye_words.any? { |word| message.downcase.include?(word) }
    should_summarize ||= @session_messages[session_id].length >= (GlitchCube.config.conversation&.max_session_messages || 10)

    return unless should_summarize && defined?(Jobs::ConversationSummaryJob)

    Jobs::ConversationSummaryJob.perform_async(
      session_id,
      @session_messages[session_id],
      context
    )

    # Clear session messages after queuing summary
    @session_messages.delete(session_id)
  end

  def update_kiosk_display(message, response, suggested_mood)
    # Update the kiosk service with new interaction data
    require_relative '../services/kiosk_service'

    Services::KioskService.update_mood(suggested_mood) if suggested_mood
    Services::KioskService.update_interaction({
                                                message: message,
                                                response: response
                                              })
    Services::KioskService.add_inner_thought('Just shared something meaningful with a visitor')
  rescue StandardError => e
    # Don't let kiosk update failures break the conversation
    puts "Failed to update kiosk display: #{e.message}"
  end

  def handle_circuit_breaker_open(message, mood, context, _error)
    response_text = generate_offline_response(message, mood)
    result = {
      response: response_text,
      suggested_mood: mood,
      confidence: 0.3
    }

    log_interaction(message, response_text, mood, result[:confidence], context)
    speak_response(response_text, context)

    result
  end

  def handle_timeout_error(message, mood, context, error)
    response_text = generate_offline_response(message, mood)
    result = {
      response: response_text,
      suggested_mood: mood,
      confidence: 0.2
    }

    Services::LoggerService.log_interaction(
      user_message: message,
      ai_response: response_text,
      mood: mood,
      confidence: result[:confidence],
      error: "Timeout: #{error.message}"
    )

    speak_response(response_text, context)
    result
  end

  def handle_general_error(message, mood, context, error)
    response_text = generate_fallback_response(message, mood)
    result = {
      response: response_text,
      suggested_mood: mood,
      confidence: 0.1
    }

    Services::LoggerService.log_interaction(
      user_message: message,
      ai_response: response_text,
      mood: mood,
      confidence: result[:confidence],
      context: { error: "General Error: #{error.message}" }
    )

    speak_response(response_text, context)
    result
  end

  def log_interaction(message, response, mood, confidence, _context)
    Services::LoggerService.log_interaction(
      user_message: message,
      ai_response: response,
      mood: mood,
      confidence: confidence
    )
  end

end
