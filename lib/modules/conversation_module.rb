# frozen_string_literal: true

require 'securerandom'
require_relative '../services/system_prompt_service'

class ConversationModule
  def call(message:, context: {}, mood: 'neutral')
    # For now, use simple completion instead of ChainOfThought
    # which seems to have issues with output_fields

    system_prompt = build_system_prompt(mood, context)
    prompt = "#{system_prompt}\n\nUser: #{message}\n\nGlitch Cube:"

    begin
      model = Desiru.configuration.default_model
      result = model.complete(prompt,
                              temperature: GlitchCube.config.conversation.temperature,
                              max_tokens: GlitchCube.config.conversation.max_tokens)

      response_text = result[:content] || generate_fallback_response(message, mood)

      result = {
        response: response_text,
        suggested_mood: suggest_next_mood(mood, message),
        confidence: 0.95
      }

      # Track conversation in persistence layer if available
      track_conversation(message, context, mood, result)

      result
    rescue StandardError => e
      # Log error if logger is available
      puts "ConversationModule error: #{e.message}" if defined?(Rails)

      {
        response: generate_fallback_response(message, mood),
        suggested_mood: mood,
        confidence: 0.5
      }
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
      'ConversationModule',
      { message: message, context: context, mood: mood },
      result,
      { model: Desiru.configuration.default_model.config[:model] || 'unknown' }
    )

    # Track in session for summarization
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

  def check_conversation_end(session_id, message, context)
    return unless @session_messages[session_id]

    # Trigger summarization if:
    # - User says goodbye/bye/leaving
    # - Session has been idle for 5 minutes
    # - Conversation has 10+ messages

    goodbye_words = %w[goodbye bye leaving done exit quit thanks]
    should_summarize = goodbye_words.any? { |word| message.downcase.include?(word) }
    should_summarize ||= @session_messages[session_id].length >= GlitchCube.config.conversation.max_session_messages

    return unless should_summarize && defined?(Jobs::ConversationSummaryJob)

    Jobs::ConversationSummaryJob.perform_async(
      session_id,
      @session_messages[session_id],
      context
    )

    # Clear session messages after queuing summary
    @session_messages.delete(session_id)
  end
end
