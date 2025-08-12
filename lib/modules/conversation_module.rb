# frozen_string_literal: true

require 'securerandom'
require 'concurrent'

class ConversationModule
  include ErrorHandling

  # Convenience class methods for each persona
  # Class method to switch persona programmatically
  # This updates Redis state and syncs with Home Assistant
  def self.switch_persona(persona_name)
    Services::PersonaStateService.set_current_persona(persona_name)
  end

  # Get the current active persona
  def self.current_persona
    Services::PersonaStateService.get_current_persona
  end

  # These convenience methods set the persona and return a new instance
  def self.buddy
    switch_persona('buddy')
    new
  end

  def self.jax
    switch_persona('jax')
    new
  end

  def self.lomi
    switch_persona('lomi')
    new
  end

  def self.zorp
    switch_persona('zorp')
    new
  end

  def self.default
    new
  end

  def initialize
    # No longer need to store default persona - we get it from PersonaStateService
  end

  def call(message:, context: {}, persona: nil)
    # Use persona from parameters, context, or get from PersonaStateService
    persona_name = persona || context[:persona] || Services::PersonaStateService.get_current_persona

    # Create persona instance (keep persona_name separate from persona object)
    persona_instance = Personas::BasePersona.create(persona_name, context)

    # Load persona-specific tools if not already provided
    if context[:tools].nil? || context[:tools].empty?
      context[:tools] = persona_instance.tool_schemas
      Services::SimpleLogger.debug('Auto-loaded tools for persona', tagged: [:tools], persona: persona_name, count: context[:tools]&.size || 0)
    end

    # Set LED feedback to listening state at start of conversation
    Services::ConversationFeedbackService.new.set_state(:listening) if context[:visual_feedback] != false

    # Simple logging instead of complex tracing
    Services::SimpleLogger.debug('Conversation started', tagged: [:conversation], persona: persona_name, message_preview: message[0..100])

    # Phase 3.5: Ultra-simple Session Management
    # Just use whatever session_id is provided (HA provides voice_conversation_id)
    # If no session_id, generate one (for non-voice interactions)
    Time.now

    # Ensure we have a session_id
    context[:session_id] ||= SecureRandom.uuid

    session = Services::ConversationSession.find_or_create(
      session_id: context[:session_id],
      context: context.merge(persona: persona_name)
    )

    # Update tool handler with session
    tool_handler = Services::ConversationToolHandler.new(session: session, persona: persona_name)

    Services::SimpleLogger.debug('Session initialized', tagged: [:conversation], session_id: session.session_id, message_count: session.messages.count)

    # Enrich context with sensor data and defaults
    context = Services::ContextEnrichmentService.enrich(context)

    system_prompt = build_system_prompt(persona_instance, context)

    # Prepare structured output schema based on context
    response_schema = get_response_schema(context)

    begin
      start_time = Time.now

      # Build options including structured output support
      llm_options = {
        model: context[:model] || GlitchCube.config.ai.default_model,
        temperature: context[:temperature] || GlitchCube.config.conversation&.temperature || 0.8,
        max_tokens: context[:max_tokens] || GlitchCube.config.conversation&.max_tokens || GlitchCube.config.ai.max_tokens,
        timeout: context[:timeout] || GlitchCube.config.conversation&.completion_timeout || 20
      }

      # CRITICAL FIX: Check for tools FIRST, as we can't use both tools and structured output together
      using_tools = context[:tools].present? && !context[:tools].empty?

      if using_tools
        # Native tool calling - Use tools model for better tool handling
        llm_options[:model] = context[:tools_model] || GlitchCube.config.ai.default_tools_model
        llm_options[:tools] = context[:tools]
        llm_options[:tool_choice] = 'auto'
        # Use higher token limit for tool calls to allow multiple tool calls
        llm_options[:max_tokens] = context[:max_tokens] || GlitchCube.config.ai.max_tool_tokens

        # Enhanced logging for model split testing
        Services::SimpleLogger.info('🔧 TOOLS CALL - Using tools-optimized model',
                                    tagged: %i[conversation tools model_split],
                                    model: llm_options[:model],
                                    max_tokens: llm_options[:max_tokens])
        puts "🔧 TOOLS CALL: Using model #{llm_options[:model]} for tool execution" if GlitchCube.config.debug?

        # DO NOT set response_format when using tools!
      elsif response_schema
        # Structured output - only when NOT using tools
        llm_options[:response_format] = GlitchCube::Schemas::ConversationResponseSchema.to_openrouter_format(response_schema)
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
        persona: persona_name
      )

      # Set LED feedback to thinking state before LLM call
      Services::ConversationFeedbackService.new.set_state(:thinking) if context[:visual_feedback] != false

      # Use new LLM service with full conversation context
      Time.now
      llm_response = Services::LLMService.complete_with_messages(
        messages: messages,
        model: llm_options[:model],
        **llm_options.except(:model)
      )

      Services::SimpleLogger.debug('LLM response received', tagged: %i[conversation llm], response_preview: llm_response.response_text&.[](0..50))

      response_time_ms = ((Time.now - start_time) * 1000).round

      # Check for and execute tool calls using LLMResponse helpers
      if llm_response.tool_calls?
        Services::SimpleLogger.info('🛠️ Tool calls detected from LLM',
                                    tagged: %i[conversation tools],
                                    count: llm_response.function_calls.size,
                                    tools: llm_response.function_calls.map { |fc| fc[:name] })
        llm_response = handle_native_tool_response(llm_response, messages, llm_options, response_schema, _session: session)
        tool_calls_made = @last_tool_calls || []
        Services::SimpleLogger.info('✅ All tools executed',
                                    tagged: %i[conversation tools],
                                    tool_count: tool_calls_made&.size,
                                    tools_executed: tool_calls_made.map { |tc| tc[:tool_name] })
      else
        Services::SimpleLogger.info('💭 No tools called - direct response',
                                    tagged: %i[conversation tools])
        tool_calls_made = []
      end

      # Pass the entire LLMResponse object to validation
      # This trusts the abstraction and lets validate_response use all helpers
      validated_response = validate_response(llm_response, persona_instance)

      # validated_response returns an indifferent hash, use symbol access
      response_text = validated_response[:response]
      continue_conversation = validated_response[:continue_conversation]
      inner_thoughts = validated_response[:inner_thoughts]

      # Debug trace: Check if response_text is nil
      if response_text.nil?
        Services::SimpleLogger.debug('Response text is nil',
                                     tagged: %i[conversation debug],
                                     content: llm_response.content.inspect,
                                     parsed_content: llm_response.parsed_content.inspect)
      end

      # Calculate cost
      cost = llm_response.cost

      # Record assistant message with tool calls
      session.add_message(
        role: 'assistant',
        content: response_text,
        persona: persona_name,
        model_used: llm_response.model,
        prompt_tokens: llm_response.usage[:prompt_tokens],
        completion_tokens: llm_response.usage[:completion_tokens],
        cost: cost,
        response_time_ms: response_time_ms,
        metadata: {
          continue_conversation: continue_conversation,
          tool_calls: tool_calls_made,
          inner_thoughts: inner_thoughts
        }
      )

      # Only use fallback if response_text is nil or empty
      response_text = persona_instance.generate_fallback_response(message) if response_text.nil? || response_text.strip.empty?

      # For assist satellites, TTS is handled by the pipeline
      # We don't need to call TTS explicitly here
      tts_handled = false
      if context[:voice_interaction]
        # Check if speech_synthesis tool was already called by the LLM
        # (This would be for non-satellite voice interactions)
        tts_handled = tool_calls_made.any? do |call|
          call[:tool_name]&.include?('speech_synthesis') ||
            call[:tool_name]&.include?('speak')
        end

        Services::SimpleLogger.debug('Voice interaction detected',
                                     tagged: %i[conversation voice],
                                     tts_handled_by_tools: tts_handled,
                                     response_length: response_text&.length || 0)
      end

      # Get the TTS voice for this persona
      character_service = Services::CharacterService.new(character: persona_name.to_sym)
      tts_config = character_service.tts_config

      result = {
        response: response_text,
        conversation_id: session.session_id,
        session_id: session.session_id,
        persona: persona_name,
        model: llm_response.model,
        cost: cost,
        tokens: llm_response.usage,
        continue_conversation: continue_conversation,
        tts_handled: tts_handled,  # Flag for conversation agent
        voice_interaction: context[:voice_interaction] || false,
        error: nil
      }

      # NOTE: For assist satellites, TTS is handled by pipeline configuration per persona
      # Voice switching is managed by the HA conversation agent via pipeline selection
      if context[:voice_interaction] || context['voice_interaction']
        Services::SimpleLogger.debug('Voice interaction - TTS handled by pipeline',
                                     tagged: %i[conversation voice],
                                     requested_voice: tts_config[:voice],
                                     requested_provider: tts_config[:provider])
      end

      # Handle all post-response side effects
      Services::ConversationSideEffectHandler.new(
        result: result,
        context: context,
        session: session,
        user_message: message
      ).execute

      # Simple completion logging
      total_duration = ((Time.now - start_time) * 1000).round
      Services::SimpleLogger.info('Conversation completed', tagged: [:conversation], duration_ms: total_duration)

      result
    rescue Services::LLMService::RateLimitError, Services::LLMService::LLMError, StandardError => e
      Services::SimpleLogger.log_error(error: e, message: 'Conversation error occurred', tagged: %i[conversation error])

      Services::ConversationErrorHandler.handle(
        e,
        session: session,
        message: message,
        persona: persona_name,
        context: context
      )
    end
  end

  private

  def handle_native_tool_response(llm_response, messages, llm_options, response_schema, _session: nil)
    @last_tool_calls = []
    tool_results = []

    # Use LLMResponse helpers for clean tool call handling
    Services::SimpleLogger.debug('Processing tool calls', tagged: %i[conversation tools], tool_count: llm_response.function_calls.size)

    # Process each tool call using the standardized data from LLMResponse
    llm_response.tool_calls.each_with_index do |tool_call, index|
      function_call = llm_response.function_calls[index]
      function_name = function_call[:name]

      # Use the pre-parsed arguments from LLMResponse
      arguments = llm_response.function_arguments_for(function_name)

      if arguments.nil?
        Services::SimpleLogger.warn(
          'Could not parse arguments for tool call, skipping',
          tagged: %i[conversation tools json_parse],
          tool: function_name
        )
        next # Skip this tool call
      end

      Services::SimpleLogger.info('📋 Tool call details',
                                  tagged: %i[conversation tools],
                                  tool: function_name,
                                  arguments: arguments,
                                  tool_call_id: tool_call[:id])

      # Execute the tool
      tool_call_hash = { name: function_name, arguments: arguments }
      results = Services::ToolExecutor.execute([tool_call_hash])
      result = results.first

      # Track what we called
      @last_tool_calls << {
        tool_name: function_name,
        arguments: arguments,
        result: result
      }

      Services::SimpleLogger.info('📊 Tool execution result',
                                  tagged: %i[conversation tools],
                                  tool: function_name,
                                  success: result[:success] || (result.is_a?(String) && !result.include?('error')),
                                  result_preview: result.to_s[0..200])

      # Collect results in OpenAI tool result format
      tool_content = if result.is_a?(Hash)
                       result.to_json  # Convert hash to JSON string for OpenAI format
                     else
                       result.to_s
                     end

      tool_result = {
        tool_call_id: tool_call[:id],
        role: 'tool',
        name: function_name,
        content: tool_content
      }
      tool_results << tool_result
    end

    # PROPER TWO-STEP PATTERN as identified by zen chat:
    # Step 1: Tools executed ✅
    # Step 2: Make second LLM call with FULL conversation history including tool results

    # Build the updated conversation history for the second LLM call
    updated_messages = messages.dup

    # Check if model supports structured output ONCE and reuse
    model_supports_structured = GlitchCube::ModelPresets.supports_structured_output?(llm_options[:model])

    # Enhance system prompt to ALWAYS ask for JSON response
    # This ensures we get structured data even without response_format
    json_instruction = if model_supports_structured && response_schema
                         # Model supports structured output, just remind it
                         "\n\nIMPORTANT: Respond with valid JSON."
                       else
                         # Model doesn't support structured output, be explicit but concise
                         "\n\nRespond ONLY with JSON: {\"response\": \"your message acknowledging the tool actions and continuing naturally with the conversation\", \"continue_conversation\": true/false based on context}"
                       end

    # Enhance the system message with JSON instruction
    if updated_messages.first[:role] == 'system'
      updated_messages[0] = {
        role: 'system',
        content: updated_messages[0][:content] + json_instruction
      }
    end

    # Add the assistant's message with tool_calls to conversation history
    updated_messages << llm_response.message_data

    # Add all tool results to conversation history
    tool_results.each do |tool_result|
      updated_messages << tool_result
    end

    Services::SimpleLogger.debug('Updated conversation for second call',
                                 tagged: %i[conversation tools],
                                 message_count: updated_messages.size)

    # Second call options - Use default model for conversation response
    # This allows us to use a cheaper/faster model for tools, but better model for conversation
    second_call_options = {
      model: GlitchCube.config.ai.default_model,  # Switch back to default conversation model
      temperature: llm_options[:temperature],
      max_tokens: GlitchCube.config.ai.max_tool_tokens,  # Use config value
      reasoning: { max_tokens: 1000 }  # Balanced for speed with limited tools
      # Only use response_format if model supports it AND we have a schema
      # Some models (like older Claude) don't support structured output
      # CRITICAL: No tools in second call - we want conversational response, not more tool calls
    }

    # Reuse the model check from above - no need to check again
    if model_supports_structured && response_schema
      second_call_options[:response_format] = response_schema
    end

    # Enhanced logging for model split testing
    Services::SimpleLogger.info('💬 CONVERSATION CALL - Using conversation-optimized model',
                                tagged: %i[conversation tools model_split],
                                model: second_call_options[:model],
                                max_tokens: second_call_options[:max_tokens],
                                has_reasoning: second_call_options[:reasoning].present?)
    puts "💬 CONVERSATION CALL: Using model #{second_call_options[:model]} for response generation" if GlitchCube.config.debug?

    begin
      # Log the complete request being sent
      Services::SimpleLogger.debug('Second LLM call request',
                                   tagged: %i[conversation tools llm_request],
                                   message_count: updated_messages.size,
                                   options: second_call_options)

      # Second LLM call with complete context - this is where BUDDY becomes context-aware
      follow_up_response = Services::LLMService.complete_with_messages(
        messages: updated_messages,
        model: second_call_options[:model],
        **second_call_options.except(:model)
      )

      # Log the complete response received
      Services::SimpleLogger.debug('Second LLM call response',
                                   tagged: %i[conversation tools llm_response],
                                   response_preview: follow_up_response.content&.[](0..100),
                                   usage: follow_up_response.usage,
                                   model: follow_up_response.model)

      follow_up_response
    rescue StandardError => e
      Services::SimpleLogger.error('Context-aware follow-up LLM call failed in handle_native_tool_response',
                                   tagged: %i[conversation tools error],
                                   error: e.message,
                                   backtrace: e.backtrace.first(3))
      raise e  # Re-raise so it gets handled by the main error handler
    end
  end

  def summarize_tool_results(tool_results)
    # Simple summary of what was accomplished
    if tool_results.any?
      # Extract the content from each tool result
      tool_summaries = tool_results.map { |result| result[:content] || 'completed successfully' }
      tool_summaries.join(', ')
    else
      'completed some actions'
    end
  end

  def get_response_schema(context)
    # Load schema class if not already loaded
    begin
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

  def build_system_prompt(persona_instance, context)
    # Build enriched context - include response_format flag if we have a schema
    enriched_context = context.merge(
      current_persona: persona_instance.name,
      session_id: context[:session_id] || SecureRandom.uuid,
      interaction_count: context[:interaction_count] || 1,
      response_format: context[:response_format] || !get_response_schema(context).nil?
    )

    # Generate system prompt from persona
    base_prompt = persona_instance.generate_system_prompt

    # Add relevant context and memories if available
    final_prompt = Services::ContextInjectionService.inject_context(base_prompt, enriched_context)

    # CRITICAL: Always add JSON formatting instructions for non-tool responses
    # This ensures consistent response format for Home Assistant voice pipeline
    unless context[:tools].present? && !context[:tools].empty?
      json_instruction = "\n\nIMPORTANT: Your response MUST be valid JSON in this exact format:\n" \
                         '{"response": "your complete message here", "continue_conversation": true/false, "inner_thoughts": "optional internal thoughts"}'
      final_prompt += json_instruction
    end

    Services::SimpleLogger.debug('System prompt generated', tagged: %i[conversation prompt], char_count: final_prompt.length)

    final_prompt
  end

  def recover_json_response(malformed_json)
    return nil unless malformed_json.is_a?(String) && !malformed_json.strip.empty?

    begin
      # Use a small, fast model to fix the JSON
      recovery_prompt = <<~PROMPT
        Fix this malformed JSON and return ONLY valid JSON, no explanation:

        #{malformed_json}

        Return ONLY the corrected JSON object with these keys: response, continue_conversation, inner_thoughts
      PROMPT

      recovery_response = Services::LLMService.complete(
        system_prompt: 'You are a JSON fixer. Return only valid JSON with no explanation.',
        user_message: recovery_prompt,
        model: 'meta-llama/llama-3.2-3b-instruct',  # Ultra cheap model
        temperature: 0,
        max_tokens: 4000
      )

      recovered_content = if recovery_response.is_a?(Services::LLMResponse)
                            recovery_response.content
                          else
                            recovery_response[:content] || recovery_response['content']
                          end

      # Clean any markdown or extra text
      recovered_content = recovered_content.strip
      recovered_content = recovered_content.gsub(/^```json\s*/, '').gsub(/\s*```$/, '') if recovered_content.include?('```')

      # Try to parse the recovered JSON
      JSON.parse(recovered_content)
    rescue StandardError => e
      Services::SimpleLogger.debug('JSON recovery failed',
                                   tagged: %i[conversation json_recovery],
                                   error: e.message)
      nil
    end
  end

  def validate_response(llm_response, persona_instance)
    # Rely on the enhanced LLMResponse helpers to correctly interpret the output.
    response_text = llm_response.response_text
    continue_conversation = llm_response.continue_conversation?
    inner_thoughts = llm_response.inner_thoughts

    # If response_text is nil or empty, use the persona's fallback.
    # This correctly handles cases where JSON was valid but missing the 'response' key,
    # or where a plain text response was empty.
    if response_text.nil? || response_text.strip.empty?
      Services::SimpleLogger.warn('Response text was nil/empty, using fallback.',
                                  tagged: %i[conversation validation])
      response_text = persona_instance.generate_fallback_response('I understand.')
    end

    # The response from the LLM is now validated and structured.
    # We return a consistent hash for downstream processing.
    validated = {
      response: response_text,
      continue_conversation: continue_conversation,
      inner_thoughts: inner_thoughts
    }.with_indifferent_access # Keep for consistency with consumers

    # Optional: Keep length validation if needed.
    if validated[:response].length > 500
      Services::SimpleLogger.warn('Response very long, might need truncation',
                                  tagged: %i[conversation validation],
                                  length: validated[:response].length)
    end

    validated
  end
end
