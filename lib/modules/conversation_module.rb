# frozen_string_literal: true

require 'securerandom'
require 'concurrent'
require_relative '../services/system_prompt_service'
require_relative '../services/logger_service'
require_relative '../services/llm_service'
require_relative '../services/conversation_session'
require_relative '../services/tool_call_parser'
require_relative '../services/tool_executor'
require_relative '../services/conversation_feedback_service'
require_relative '../services/memory_recall_service'
require_relative '../home_assistant_client'
require_relative 'conversation_responses'
require_relative 'conversation_enhancements'
require_relative 'error_handling'

class ConversationModule
  include ConversationEnhancements
  include ErrorHandling

  # Convenience class methods for each persona
  def self.buddy
    new(persona: 'buddy')
  end

  def self.jax
    new(persona: 'jax')
  end

  def self.lomi
    new(persona: 'lomi')
  end

  def self.zorp
    new(persona: 'zorp')
  end

  def self.default
    new(persona: 'default')
  end

  def initialize(persona: 'buddy')
    @default_persona = persona
  end

  def call(message:, context: {}, persona: nil)
    # Use persona from context or instance default
    persona ||= context[:persona] || @default_persona

    # Load persona-specific tools if not already provided
    if context[:tools].nil? || context[:tools].empty?
      require_relative '../services/tool_registry_service'
      context[:tools] = Services::ToolRegistryService.get_tools_for_character(persona)
      puts "🔧 Auto-loaded #{context[:tools]&.size || 0} tools for persona '#{persona}'" if GlitchCube.config.debug?
    end

    # Set LED feedback to listening state at start of conversation
    execute_feedback_tool(:listening, context)

    # Simple logging instead of complex tracing
    puts "💬 [#{persona}] User: #{message[0..100]}..." if GlitchCube.config.debug?

    # Phase 3.5: Ultra-simple Session Management
    # Just use whatever session_id is provided (HA provides voice_conversation_id)
    # If no session_id, generate one (for non-voice interactions)
    session_start = Time.now
    
    # Ensure we have a session_id
    context[:session_id] ||= SecureRandom.uuid
    
    session = Services::ConversationSession.find_or_create(
      session_id: context[:session_id],
      context: context.merge(persona: persona)
    )

    puts "📝 Session #{session.session_id} (#{session.messages.count} messages)" if GlitchCube.config.debug?

    # Enrich context with sensor data if requested
    context = enrich_context_with_sensors(context) if context[:include_sensors]

    system_prompt = build_system_prompt(persona, context)

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
      execute_feedback_tool(:thinking, context)

      # Use new LLM service with full conversation context
      Time.now
      llm_response = Services::LLMService.complete_with_messages(
        messages: messages,
        **llm_options
      )

      puts "🤖 LLM Response: #{llm_response.response_text&.[](0..50)}..." if GlitchCube.config.debug?

      response_time_ms = ((Time.now - start_time) * 1000).round

      # Check for and execute tool calls
      tool_calls_made = []
      if llm_response.has_tool_calls?
        tool_results = handle_tool_calls(llm_response, session, persona)
        tool_calls_made = extract_tool_names_from_response(llm_response)

        # If we have tool results, we need to continue the conversation with them
        if tool_results && !tool_results.empty?
          # Add tool results to conversation and get final response
          llm_response = continue_with_tool_results(
            messages, llm_response, tool_results, llm_options, session, persona
          )
        end
      end

      # Extract data from response object
      response_text = llm_response.response_text
      
      # Phase 3.5: Ultra-simple continuation logic with safe defaults
      # Let the LLM decide if conversation should continue
      # Default to ending conversation if unclear (safer for voice interactions)
      continue_conversation = llm_response.continue_conversation?
      
      # Safe default: if nil or unclear, end the conversation
      if continue_conversation.nil?
        puts "⚠️ No continuation signal from LLM, defaulting to end conversation" if GlitchCube.config.debug?
        continue_conversation = false
      end

      # Debug trace: Check if response_text is nil
      if GlitchCube.config.debug? && response_text.nil?
        puts 'DEBUG: response_text is nil!'
        puts "DEBUG: llm_response.content = #{llm_response.content.inspect}"
        puts "DEBUG: llm_response.parsed_content = #{llm_response.parsed_content.inspect}"
      end

      # Calculate cost
      cost = llm_response.cost

      # Record assistant message with tool calls
      session.add_message(
        role: 'assistant',
        content: response_text,
        persona: persona,
        model_used: llm_response.model,
        prompt_tokens: llm_response.usage[:prompt_tokens],
        completion_tokens: llm_response.usage[:completion_tokens],
        cost: cost,
        response_time_ms: response_time_ms,
        metadata: {
          continue_conversation: continue_conversation,
          tool_calls: tool_calls_made
        }
      )

      # Only use fallback if response_text is nil or empty
      response_text = generate_fallback_response(message, persona) if response_text.nil? || response_text.strip.empty?

      result = {
        response: response_text,
        conversation_id: session.session_id,
        session_id: session.session_id,
        persona: persona,
        model: llm_response.model,
        cost: cost,
        tokens: llm_response.usage,
        continue_conversation: continue_conversation,
        error: nil
      }

      # Wrap post-response operations to prevent fallback on their errors
      begin
        # Set LED feedback to speaking state before TTS
        execute_feedback_tool(:speaking, context)

        execute_speech_tool(response_text, context, persona)
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
        execute_display_tool(message, response_text, persona, context)
      rescue StandardError => e
        puts "Warning: Display update failed: #{e.message}"
        # Already handled in the method but adding for clarity
      end

      # Set LED feedback to completed state
      execute_feedback_tool(:completed, context)

      # Simple completion logging
      total_duration = ((Time.now - start_time) * 1000).round
      puts "✅ Conversation completed in #{total_duration}ms" if GlitchCube.config.debug?

      result
    rescue Services::LLMService::RateLimitError => e
      puts "DEBUG: Hit rate limit error: #{e.message}" if GlitchCube.config.debug?

      # Set LED to error state
      execute_feedback_tool(:error, context)

      handle_rate_limit_error(session, message, persona, e)
    rescue Services::LLMService::LLMError => e
      puts "DEBUG: Hit LLM error: #{e.message}" if GlitchCube.config.debug?

      # Set LED to error state
      execute_feedback_tool(:error, context)

      handle_llm_error(session, message, persona, e)
    rescue StandardError => e
      puts "DEBUG: Hit general error: #{e.class} - #{e.message}" if GlitchCube.config.debug?
      puts "DEBUG: Backtrace: #{e.backtrace.first(3).join("\n")}" if GlitchCube.config.debug?

      # Set LED to error state
      execute_feedback_tool(:error, context)

      handle_general_error(session, message, persona, e)
    end
  end

  private

  def handle_tool_calls(llm_response, session, persona)
    # Parse tool calls from response
    tool_calls = Services::ToolCallParser.parse(llm_response)
    return [] if tool_calls.empty?

    puts "🔧 Executing #{tool_calls.size} tool call(s)..." if GlitchCube.config.debug?

    # Execute tools
    tool_start = Time.now
    results = Services::ToolExecutor.execute(tool_calls, timeout: 10)
    execution_time = ((Time.now - tool_start) * 1000).round

    puts "🔧 Executed #{tool_calls.size} tool calls in #{execution_time}ms" if GlitchCube.config.debug?

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

  def continue_with_tool_results(messages, initial_response, tool_results, llm_options, session, persona)
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

    puts "🤖 Follow-up LLM call completed" if GlitchCube.config.debug?

    follow_up_response
  rescue StandardError => e
    puts "⚠️ Failed to continue after tool execution: #{e.message}"

    puts "⚠️ Follow-up LLM call failed: #{e.message}" if GlitchCube.config.debug?

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

  def build_system_prompt(persona, context)
    # Map persona to character for prompt file selection
    character = persona == 'neutral' ? nil : persona

    # Build enriched context - include response_format flag if we have a schema
    enriched_context = context.merge(
      current_persona: persona,
      session_id: context[:session_id] || SecureRandom.uuid,
      interaction_count: context[:interaction_count] || 1,
      response_format: context[:response_format] || !get_response_schema(context).nil?
    )

    # Generate base system prompt
    base_prompt = Services::SystemPromptService.new(
      character: character,
      context: enriched_context
    ).generate

    # Add relevant memories if available
    final_prompt = inject_memories_into_prompt(base_prompt, context)

    puts "🧠 System prompt: #{final_prompt.length} chars" if GlitchCube.config.debug?

    final_prompt
  end

  def inject_memories_into_prompt(base_prompt, context)
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

      puts "📝 Injected #{memories.size} memories" if GlitchCube.config.debug?

      final_prompt
    else
      puts "📝 No memories to inject" if GlitchCube.config.debug?

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

    execute_speech_tool(response_text, {}, persona)

    {
      response: response_text,
      conversation_id: session.session_id,
      session_id: session.session_id,
      persona: persona,
      error: 'rate_limit',
      continue_conversation: false  # End on rate limit to be safe
    }
  end

  def handle_llm_error(session, message, persona, _error)
    response_text = generate_offline_response(message, persona)

    session.add_message(
      role: 'assistant',
      content: response_text,
      persona: persona
    )

    execute_speech_tool(response_text, {}, persona)

    {
      response: response_text,
      conversation_id: session.session_id,
      session_id: session.session_id,
      persona: persona,
      error: 'llm_error',
      continue_conversation: false  # End on LLM error to be safe
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
      persona: persona
    )

    execute_speech_tool(response_text, {}, persona)

    {
      response: response_text,
      conversation_id: session.session_id,
      session_id: session.session_id,
      persona: persona,
      error: 'general_error',
      continue_conversation: false  # End on general error to be safe
    }
  end

  def log_interaction(session, message, response, persona)
    Services::LoggerService.log_interaction(
      user_message: message,
      ai_response: response,
      persona: persona,
      session_id: session.session_id
    )
  end

  # Tool-based hardware operation helpers - standardized execution
  # These methods execute operations via tools only, no fallbacks

  def execute_feedback_tool(state, context = {})
    return unless context[:visual_feedback] != false

    # Execute via tool system only - no fallbacks
    if context[:tools] && tool_available?(context[:tools], 'conversation_feedback')
      execute_tool_call('conversation_feedback', 'set_state', { state: state.to_s })
      puts "🔧 LED feedback via tool: #{state}" if GlitchCube.config.debug?
    else
      puts "⚠️ LED feedback skipped - no conversation_feedback tool available" if GlitchCube.config.debug?
    end
  end

  def execute_speech_tool(text, context = {}, persona = nil)
    return if text.nil? || text.strip.empty?

    # Execute via tool system only - no fallbacks
    if context[:tools] && tool_available?(context[:tools], 'speech_synthesis')
      entity_id = context[:entity_id] || 'media_player.square_voice'
      result = execute_tool_call('speech_synthesis', 'speak_text', {
                                   text: text,
                                   entity_id: entity_id
                                 })

      puts "🔊 TTS via tool: #{result&.include?('Spoke:') ? 'success' : 'failed'}" if GlitchCube.config.debug?
    else
      puts "⚠️ TTS skipped - no speech_synthesis tool available" if GlitchCube.config.debug?
    end
  rescue StandardError => e
    puts "⚠️ Tool-based TTS failed: #{e.message}" if GlitchCube.config.debug?
  end

  def execute_display_tool(message, response, persona, context = {})
    # Execute via tool system only - no dual execution
    if context[:tools] && tool_available?(context[:tools], 'display_control')
      # Use display tool for conversation update
      execute_tool_call('display_control', 'show_display_text', {
                          text: response.length > 50 ? response[0..47] + '...' : response,
                          color: persona_to_color(persona),
                          duration: 8
                        })
      puts "📺 Display update via tool" if GlitchCube.config.debug?
    else
      # Fallback to direct kiosk update only if no tool available
      begin
        update_kiosk_display(message, response, persona)
        puts "📺 Display update via direct kiosk" if GlitchCube.config.debug?
      rescue StandardError => e
        puts "⚠️ Kiosk display update failed: #{e.message}"
      end
    end
  end

  # Helper methods

  def extract_tool_names_from_response(llm_response)
    return [] unless llm_response.has_tool_calls?

    tool_calls = Services::ToolCallParser.parse(llm_response)
    tool_calls.map { |call| call.dig(:function, :name) }.compact
  rescue StandardError => e
    puts "Warning: Failed to extract tool names: #{e.message}"
    []
  end

  def tool_available?(tools, tool_name)
    return false unless tools.is_a?(Array)

    tools.any? { |tool| tool.is_a?(Hash) && tool.dig('function', 'name') == tool_name }
  end

  def execute_tool_call(tool_name, method_name, params = {})
    # Simple tool execution - in a full implementation, this would go through ToolExecutor
    require_relative '../services/tool_executor'

    # Format as tool call
    tool_calls = [{
      id: SecureRandom.hex(8),
      type: 'function',
      function: {
        name: tool_name,
        arguments: { action: method_name, params: params }.to_json
      }
    }]

    results = Services::ToolExecutor.execute(tool_calls, timeout: 10)
    results.first&.dig(:result)
  rescue StandardError => e
    puts "Tool execution failed: #{e.message}"
    nil
  end

  def persona_to_color(persona)
    case persona
    when 'playful'
      '#FF00FF'  # Magenta
    when 'contemplative'
      '#0064FF'  # Blue
    when 'mysterious'
      '#8000FF'  # Purple
    else
      '#FFFFFF'  # White
    end
  end
end
