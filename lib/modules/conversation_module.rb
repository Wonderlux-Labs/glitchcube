# frozen_string_literal: true

require 'securerandom'
require 'concurrent'

class ConversationModule
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
    new(persona: 'buddy')
  end

  def initialize(persona: 'buddy')
    @default_persona = persona
  end

  def call(message:, context: {}, persona: nil)
    # Use persona from context or instance default
    persona_name = persona || context[:persona] || @default_persona

    # Create persona instance
    persona = Personas::BasePersona.create(persona_name, context)

    # Load persona-specific tools if not already provided
    if context[:tools].nil? || context[:tools].empty?
      context[:tools] = persona.tool_schemas
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

    system_prompt = build_system_prompt(persona, context)

    # Prepare structured output schema based on context
    response_schema = get_response_schema(context)

    begin
      start_time = Time.now

      # Build options including structured output support
      llm_options = {
        model: context[:model] || GlitchCube.config.ai.default_model,
        temperature: context[:temperature] || GlitchCube.config.conversation&.temperature || 0.8,
        max_tokens: context[:max_tokens] || GlitchCube.config.conversation&.max_tokens || 200,
        timeout: context[:timeout] || GlitchCube.config.conversation&.completion_timeout || 20
      }

      # Add structured output if schema is provided
      llm_options[:response_format] = GlitchCube::Schemas::ConversationResponseSchema.to_openrouter_format(response_schema) if response_schema

      # Configure tool support via tool handler
      llm_options = tool_handler.configure_llm_options(llm_options, context[:tools])

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
        **llm_options
      )

      Services::SimpleLogger.debug('LLM response received', tagged: %i[conversation llm], response_preview: llm_response.response_text&.[](0..50))

      response_time_ms = ((Time.now - start_time) * 1000).round

      # Check for and execute tool calls
      llm_response = tool_handler.handle_tool_calls(llm_response, messages, llm_options)
      tool_calls_made = tool_handler.last_tool_calls_made

      # Extract data from response object
      response_text = llm_response.response_text

      # Phase 3.5: Ultra-simple continuation logic with safe defaults
      # Let the LLM decide if conversation should continue
      # Default to ending conversation if unclear (safer for voice interactions)
      continue_conversation = llm_response.continue_conversation?

      # Safe default: if nil or unclear, end the conversation
      if continue_conversation.nil?
        Services::SimpleLogger.debug('No continuation signal from LLM, ending conversation', tagged: [:conversation])
        continue_conversation = false
      end

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
          tool_calls: tool_calls_made
        }
      )

      # Only use fallback if response_text is nil or empty
      response_text = persona.generate_fallback_response(message) if response_text.nil? || response_text.strip.empty?

      result = {
        response: response_text,
        conversation_id: session.session_id,
        session_id: session.session_id,
        persona: persona_name,
        model: llm_response.model,
        cost: cost,
        tokens: llm_response.usage,
        continue_conversation: continue_conversation,
        error: nil
      }

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

  def build_system_prompt(persona, context)
    # Build enriched context - include response_format flag if we have a schema
    enriched_context = context.merge(
      current_persona: persona.name,
      session_id: context[:session_id] || SecureRandom.uuid,
      interaction_count: context[:interaction_count] || 1,
      response_format: context[:response_format] || !get_response_schema(context).nil?
    )

    # Generate system prompt from persona
    base_prompt = persona.generate_system_prompt

    # Add relevant context and memories if available
    final_prompt = Services::ContextInjectionService.inject_context(base_prompt, enriched_context)

    Services::SimpleLogger.debug('System prompt generated', tagged: %i[conversation prompt], char_count: final_prompt.length)

    final_prompt
  end
end
