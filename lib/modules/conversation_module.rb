# frozen_string_literal: true

require 'securerandom'
require 'concurrent'
require_relative '../services/system_prompt_service'
require_relative '../services/logger_service'
require_relative '../services/llm_service'
require_relative '../services/conversation_session'
require_relative '../services/tool_call_parser'
require_relative '../services/tool_executor'
require_relative '../services/conversation_tracer'
require_relative '../services/conversation_feedback_service'
require_relative '../home_assistant_client'
require_relative 'conversation_responses'
require_relative 'conversation_enhancements'
require_relative 'error_handling'

class ConversationModule
  include ConversationEnhancements
  include ErrorHandling

  def call(message:, context: {}, persona: nil, mood: nil)
    # Use persona from context or default, also support legacy mood parameter
    persona ||= mood || context[:persona] || context[:mood] || 'neutral'

    # Set LED feedback to listening state at start of conversation
    if context[:visual_feedback] != false
      with_error_handling('set_led_listening', fallback: nil, reraise_unexpected: false) do
        Services::ConversationFeedbackService.set_listening
      end
    end

    # Initialize conversation tracer
    tracer = Services::ConversationTracer.new(
      session_id: context[:session_id],
      enabled: context[:trace_conversation] != false
    )

    tracer.start_conversation(
      message: message,
      context: context,
      persona: persona
    )

    # Get or create conversation session using ActiveRecord
    session_start = Time.now
    session = Services::ConversationSession.find_or_create(
      session_id: context[:session_id],
      context: context.merge(persona: persona)
    )

    tracer.trace_session_lookup(
      session_data: {
        session_id: session.session_id,
        message_count: session.messages.count
      },
      created: session.created_at > session_start
    )

    # Enrich context with sensor data if requested
    context = enrich_context_with_sensors(context) if context[:include_sensors]

    system_prompt = build_system_prompt(persona, context, tracer)

    # Prepare structured output schema based on context
    response_schema = get_response_schema(context)

    begin
      start_time = Time.now

      # Build options including structured output support
      llm_options = {
        model: GlitchCube.config.ai.default_model,
        temperature: context[:temperature] || GlitchCube.config.conversation&.temperature || 0.8,
        max_tokens: context[:max_tokens] || GlitchCube.config.conversation&.max_tokens || 200,
        timeout: context[:timeout] || GlitchCube.config.conversation&.completion_timeout || 20
      }

      # Add structured output if schema is provided
      llm_options[:response_format] = GlitchCube::Schemas::ConversationResponseSchema.to_openrouter_format(response_schema) if response_schema

      # Add tool support if tools are configured
      if context[:tools]
        llm_options[:tools] = context[:tools]
        llm_options[:tool_choice] = context[:tool_choice] || 'auto'
        llm_options[:parallel_tool_calls] = context[:parallel_tool_calls] != false
      end

      # Get conversation history for context (doesn't include current message yet)
      conversation_history = session.messages_for_llm

      # Build messages array with system prompt, history, and current message
      messages = [
        { role: 'system', content: system_prompt }
      ]

      # Add conversation history (previous messages)
      messages.concat(conversation_history)

      # Add current user message
      messages << { role: 'user', content: message }

      # Now save the user message to database
      session.add_message(
        role: 'user',
        content: message,
        persona: persona
      )

      # Set LED feedback to thinking state before LLM call
      begin
        Services::ConversationFeedbackService.set_thinking if context[:visual_feedback] != false
      rescue StandardError => e
        puts "⚠️  LED feedback failed: #{e.message}"
      end

      # Use new LLM service with full conversation context
      Time.now
      llm_response = Services::LLMService.complete_with_messages(
        messages: messages,
        **llm_options
      )

      tracer.trace_llm_call(
        messages: messages,
        options: llm_options,
        response: llm_response
      )

      response_time_ms = ((Time.now - start_time) * 1000).round

      # Check for and execute tool calls
      tool_results = nil
      if llm_response.has_tool_calls?
        tool_results = handle_tool_calls(llm_response, session, persona, tracer)

        # If we have tool results, we need to continue the conversation with them
        if tool_results && !tool_results.empty?
          # Add tool results to conversation and get final response
          llm_response = continue_with_tool_results(
            messages, llm_response, tool_results, llm_options, session, persona, tracer
          )
        end
      end

      # Extract data from response object
      response_text = llm_response.response_text
      continue_conversation = llm_response.continue_conversation?

      # Debug trace: Check if response_text is nil
      if GlitchCube.config.debug? && response_text.nil?
        puts 'DEBUG: response_text is nil!'
        puts "DEBUG: llm_response.content = #{llm_response.content.inspect}"
        puts "DEBUG: llm_response.parsed_content = #{llm_response.parsed_content.inspect}"
      end

      # Calculate cost
      cost = llm_response.cost

      # Record assistant message
      session.add_message(
        role: 'assistant',
        content: response_text,
        persona: persona,
        model_used: llm_response.model,
        prompt_tokens: llm_response.usage[:prompt_tokens],
        completion_tokens: llm_response.usage[:completion_tokens],
        cost: cost,
        response_time_ms: response_time_ms,
        metadata: { continue_conversation: continue_conversation }
      )

      # Only use fallback if response_text is nil or empty
      response_text = generate_fallback_response(message, persona) if response_text.nil? || response_text.strip.empty?

      result = {
        response: response_text,
        conversation_id: session.session_id,
        session_id: session.session_id,
        persona: persona,
        suggested_mood: persona, # Backward compatibility
        model: llm_response.model,
        cost: cost,
        tokens: llm_response.usage,
        continue_conversation: continue_conversation,
        error: nil
      }

      # Wrap post-response operations to prevent fallback on their errors
      begin
        # Set LED feedback to speaking state before TTS
        Services::ConversationFeedbackService.set_speaking if context[:visual_feedback] != false

        speak_response(response_text, context, tracer)
      rescue StandardError => e
        puts "Warning: TTS failed but conversation succeeded: #{e.message}"
        # Log but don't fail the conversation
      end

      begin
        log_interaction(session, message, response_text, persona)
      rescue StandardError => e
        puts "Warning: Interaction logging failed: #{e.message}"
        # Log but don't fail the conversation
      end

      begin
        update_kiosk_display(message, response_text, persona)
      rescue StandardError => e
        puts "Warning: Kiosk display update failed: #{e.message}"
        # Already handled in the method but adding for clarity
      end

      # Set LED feedback to completed state
      begin
        Services::ConversationFeedbackService.set_completed if context[:visual_feedback] != false
      rescue StandardError => e
        puts "⚠️  LED feedback failed: #{e.message}"
      end

      # Complete tracing
      total_duration = ((Time.now - start_time) * 1000).round
      tracer.complete_conversation(
        result: result,
        total_duration_ms: total_duration
      )

      # Add trace info to result for debugging
      result[:trace_id] = tracer.trace_id if tracer.traces.any?

      result
    rescue Services::LLMService::RateLimitError => e
      puts "DEBUG: Hit rate limit error: #{e.message}" if GlitchCube.config.debug?

      # Set LED to error state
      begin
        Services::ConversationFeedbackService.set_error if context[:visual_feedback] != false
      rescue StandardError
        # Ignore LED feedback errors during error handling
      end

      handle_rate_limit_error(session, message, persona, e)
    rescue Services::LLMService::LLMError => e
      puts "DEBUG: Hit LLM error: #{e.message}" if GlitchCube.config.debug?

      # Set LED to error state
      begin
        Services::ConversationFeedbackService.set_error if context[:visual_feedback] != false
      rescue StandardError
        # Ignore LED feedback errors during error handling
      end

      handle_llm_error(session, message, persona, e)
    rescue StandardError => e
      puts "DEBUG: Hit general error: #{e.class} - #{e.message}" if GlitchCube.config.debug?
      puts "DEBUG: Backtrace: #{e.backtrace.first(3).join("\n")}" if GlitchCube.config.debug?

      # Set LED to error state
      begin
        Services::ConversationFeedbackService.set_error if context[:visual_feedback] != false
      rescue StandardError
        # Ignore LED feedback errors during error handling
      end

      handle_general_error(session, message, persona, e)
    end
  end

  private

  def handle_tool_calls(llm_response, session, persona, tracer = nil)
    # Parse tool calls from response
    tool_calls = Services::ToolCallParser.parse(llm_response)
    return [] if tool_calls.empty?

    puts "🔧 Executing #{tool_calls.size} tool call(s)..." if GlitchCube.config.debug?

    # Execute tools
    tool_start = Time.now
    results = Services::ToolExecutor.execute(tool_calls, timeout: 10)
    execution_time = ((Time.now - tool_start) * 1000).round

    # Trace tool execution
    tracer&.trace_tool_execution(
      tool_calls: tool_calls,
      results: results,
      execution_time_ms: execution_time
    )

    # Log tool execution
    results.each do |result|
      log_tool_execution(result, session, persona)
    end

    results
  rescue StandardError => e
    puts "⚠️ Tool execution failed: #{e.message}"
    puts "Tool execution error: #{e.message}"
    []
  end

  def continue_with_tool_results(messages, initial_response, tool_results, llm_options, session, persona, tracer = nil)
    # Format tool results for conversation
    tool_message = format_tool_results_message(tool_results)

    # Add initial assistant response with tool calls to messages
    assistant_message = {
      role: 'assistant',
      content: initial_response.content || '',
      tool_calls: initial_response.tool_calls
    }
    messages << assistant_message

    # Add tool results as a tool message
    messages << {
      role: 'tool',
      content: tool_message
    }

    # Save tool interaction to session
    session.add_message(
      role: 'assistant',
      content: initial_response.content || '[Tool calls]',
      persona: persona,
      tool_calls: initial_response.tool_calls
    )

    session.add_message(
      role: 'tool',
      content: tool_message,
      persona: persona
    )

    # Get final response after tool execution
    follow_up_response = Services::LLMService.complete_with_messages(
      messages: messages,
      **llm_options.except(:tools, :tool_choice) # Don't allow recursive tool calls for now
    )

    # Trace the follow-up LLM call
    tracer&.trace_llm_call(
      messages: messages,
      options: llm_options.except(:tools, :tool_choice),
      response: follow_up_response
    )

    follow_up_response
  rescue StandardError => e
    puts "⚠️ Failed to continue after tool execution: #{e.message}"

    # Trace the error
    tracer&.trace_llm_call(
      messages: messages,
      options: llm_options.except(:tools, :tool_choice),
      error: e
    )

    # Return original response if continuation fails
    initial_response
  end

  def format_tool_results_message(tool_results)
    return 'No tool results available.' if tool_results.empty?

    formatted = tool_results.map do |result|
      if result[:success]
        "#{result[:tool_name]}: #{result[:result]}"
      else
        "#{result[:tool_name]} failed: #{result[:error]}"
      end
    end

    formatted.join("\n")
  end

  def log_tool_execution(result, session, persona)
    Services::LoggerService.log_api_call(
      service: 'tool_executor',
      endpoint: result[:tool_name],
      method: 'execute',
      status: result[:success] ? 200 : 500,
      session_id: session.session_id,
      persona: persona
    )
  rescue StandardError => e
    puts "Failed to log tool execution: #{e.message}" if GlitchCube.config.debug?
  end

  def detect_continuation_intent(text)
    return true unless text

    text_lower = text.downcase

    # Check for explicit endings
    return false if text_lower.match?(/\b(goodbye|bye|farewell|see you|talk later)\b/)

    # Check for questions or engagement
    return true if text.include?('?')
    return true if text_lower.match?(/\b(would you|do you|can you|tell me|what|how|why|let me know)\b/)

    # Default to continuing for engagement
    true
  end

  def get_response_schema(context)
    # Load schema class if not already loaded
    begin
      require_relative '../schemas/conversation_response_schema'
    rescue StandardError
      nil
    end

    return nil unless defined?(GlitchCube::Schemas::ConversationResponseSchema)

    # Select appropriate schema based on context
    if context[:image_analysis]
      GlitchCube::Schemas::ConversationResponseSchema.image_analysis_response
    elsif context[:tools]
      GlitchCube::Schemas::ConversationResponseSchema.tool_response
    elsif context[:simple_mode]
      GlitchCube::Schemas::ConversationResponseSchema.simple_response
    else
      # Default to simple response for now - can switch to full schema later
      GlitchCube::Schemas::ConversationResponseSchema.simple_response
    end
  end

  def build_system_prompt(persona, context, tracer = nil)
    # Map persona to character for prompt file selection
    character = persona == 'neutral' ? nil : persona

    # Build enriched context
    enriched_context = context.merge(
      current_persona: persona,
      session_id: context[:session_id] || SecureRandom.uuid,
      interaction_count: context[:interaction_count] || 1
    )

    # Generate base system prompt
    base_prompt = Services::SystemPromptService.new(
      character: character,
      context: enriched_context
    ).generate

    # Add relevant memories if available
    final_prompt = inject_memories_into_prompt(base_prompt, context, tracer)

    # Trace system prompt building
    tracer&.trace_system_prompt(
      persona: persona,
      context: context,
      prompt_length: final_prompt.length,
      memories_injected: (final_prompt.length - base_prompt.length).positive? ? 1 : 0
    )

    final_prompt
  end

  def inject_memories_into_prompt(base_prompt, context, tracer = nil)
    # Skip memory injection if explicitly disabled
    return base_prompt if context[:skip_memories] == true

    # Get current location from context or Home Assistant
    location = context[:location] || fetch_current_location

    # Get relevant memories (simplified: location, recent, upcoming)
    memories = Services::MemoryRecallService.get_relevant_memories(
      location: location,
      context: context,
      limit: 3
    )

    # Format and inject memories
    if memories.any?
      memory_context = Services::MemoryRecallService.format_for_context(memories)
      final_prompt = "#{base_prompt}#{memory_context}"

      # Trace memory injection
      tracer&.trace_memory_injection(
        location: location,
        memories: memories,
        formatted_context: memory_context
      )

      final_prompt
    else
      # Trace empty memory injection
      tracer&.trace_memory_injection(
        location: location,
        memories: [],
        formatted_context: nil
      )

      base_prompt
    end
  rescue StandardError => e
    puts "Failed to inject memories: #{e.message}"
    base_prompt
  end

  def fetch_current_location
    return nil unless GlitchCube.config.home_assistant.url

    client = HomeAssistantClient.new
    location = client.state('sensor.glitchcube_location')
    location&.dig('state')
  rescue StandardError
    nil
  end

  def generate_fallback_response(_message, persona)
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

    responses[persona]&.sample || "I'm processing your thoughts through my artistic consciousness..."
  end

  def generate_offline_response(_message, persona)
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
    base_response = offline_responses[persona]&.sample ||
                    "I'm experiencing some connectivity issues, but I'm still here in spirit."

    # Add encouraging message about the connection
    encouragement = [
      'Feel free to keep talking - sometimes the best conversations happen in the quiet moments.',
      "I'll be back to full capability soon, but your words still matter to me.",
      "This is just a different kind of artistic moment we're sharing."
    ].sample

    "#{base_response} #{encouragement}"
  end

  def speak_response(response_text, context = {}, tracer = nil)
    return if response_text.nil? || response_text.strip.empty?

    start_time = Time.now

    begin
      # Use Home Assistant client directly for all TTS
      home_assistant = HomeAssistantClient.new

      # Get entity from context or use default
      entity_id = context[:entity_id] || 'media_player.square_voice'

      # Direct Home Assistant TTS call
      success = home_assistant.speak(response_text, entity_id: entity_id)

      duration = ((Time.now - start_time) * 1000).round
      Services::LoggerService.log_tts(
        message: response_text,
        success: success,
        duration: duration,
        entity_id: entity_id
      )

      # Trace TTS call
      tracer&.trace_tts_call(
        text: response_text,
        persona: context[:mood] || context[:persona] || 'neutral',
        success: success,
        duration_ms: duration
      )
    rescue StandardError => e
      error = e.message
      duration = ((Time.now - start_time) * 1000).round

      Services::LoggerService.log_tts(
        message: response_text,
        success: false,
        duration: duration,
        error: "Unexpected Error: #{e.message}",
        entity_id: context[:entity_id] || 'media_player.square_voice'
      )

      # Trace TTS error
      tracer&.trace_tts_call(
        text: response_text,
        persona: context[:mood] || context[:persona] || 'neutral',
        success: false,
        duration_ms: duration,
        error: error
      )
    end
  end

  def update_kiosk_display(message, response, persona)
    # Update the kiosk service with new interaction data
    require_relative '../services/kiosk_service'

    Services::KioskService.update_mood(persona) if persona
    Services::KioskService.update_interaction({
                                                message: message,
                                                response: response
                                              })
    Services::KioskService.add_inner_thought('Just shared something meaningful with a visitor')

    # Also update AWTRIX display if available
    update_awtrix_display(message, response, persona)
  rescue StandardError => e
    # Don't let kiosk update failures break the conversation
    puts "Failed to update kiosk display: #{e.message}"
  end

  def update_awtrix_display(_message, response, persona)
    return unless GlitchCube.config.home_assistant.url

    # Run display updates in parallel
    Concurrent::Future.execute do
      home_assistant = HomeAssistantClient.new

      # Choose color based on persona/mood
      color = case persona
              when 'playful'
                [255, 0, 255] # Magenta
              when 'contemplative'
                [0, 100, 255] # Blue
              when 'mysterious'
                [128, 0, 128] # Purple
              else
                [255, 255, 255] # White
              end

      # Show a brief summary or mood indicator
      display_text = if response.length > 50
                       "💭 #{persona}..."
                     else
                       response[0..30]
                     end

      # Send to AWTRIX display
      home_assistant.awtrix_display_text(
        display_text,
        color: color,
        duration: 5,
        rainbow: persona == 'playful'
      )

      # Also set mood light
      home_assistant.awtrix_mood_light(color, brightness: 80)
    rescue StandardError => e
      puts "⚠️ AWTRIX update failed: #{e.message}"
    end
  rescue StandardError => e
    puts "⚠️ Failed to initiate AWTRIX update: #{e.message}"
  end

  def handle_rate_limit_error(session, _message, persona, _error)
    response_text = 'I need to take a brief pause - too many thoughts at once! Can you give me a moment?'

    # Still record the response
    session.add_message(
      role: 'assistant',
      content: response_text,
      persona: persona
    )

    speak_response(response_text, {})

    {
      response: response_text,
      conversation_id: session.session_id,
      session_id: session.session_id,
      persona: persona,
      suggested_mood: persona,
      error: 'rate_limit'
    }
  end

  def handle_llm_error(session, message, persona, _error)
    response_text = generate_offline_response(message, persona)

    session.add_message(
      role: 'assistant',
      content: response_text,
      persona: persona
    )

    speak_response(response_text, { mood: 'neutral', cache: true })

    {
      response: response_text,
      conversation_id: session.session_id,
      session_id: session.session_id,
      persona: persona,
      suggested_mood: persona,
      error: 'llm_error'
    }
  end

  def handle_general_error(session, message, persona, _error)
    response_text = generate_fallback_response(message, persona)

    session.add_message(
      role: 'assistant',
      content: response_text,
      persona: persona
    )

    Services::LoggerService.log_interaction(
      user_message: message,
      ai_response: response_text,
      mood: persona
    )

    speak_response(response_text, {})

    {
      response: response_text,
      conversation_id: session.session_id,
      session_id: session.session_id,
      persona: persona,
      suggested_mood: persona,
      error: 'general_error'
    }
  end

  def log_interaction(session, message, response, persona)
    Services::LoggerService.log_interaction(
      user_message: message,
      ai_response: response,
      mood: persona,
      session_id: session.session_id
    )
  end
end
