# frozen_string_literal: true

require 'securerandom'
require 'concurrent'
require_relative '../services/system_prompt_service'
require_relative '../services/logger_service'
require_relative '../services/llm_service'
require_relative '../home_assistant_client'
require_relative 'conversation_responses'
require_relative 'conversation_enhancements'

class ConversationModule
  include ConversationEnhancements
  
  def call(message:, context: {}, persona: nil)
    # Use persona from context or default
    persona ||= context[:persona] || 'neutral'
    
    # Get or create conversation
    conversation = find_or_create_conversation(context)
    
    # Record user message
    conversation.add_message(
      role: 'user',
      content: message,
      persona: persona
    )
    
    system_prompt = build_system_prompt(persona, context)
    
    # Prepare structured output schema based on context
    response_schema = get_response_schema(context)
    
    begin
      start_time = Time.now
      
      # Build options including structured output support
      llm_options = {
        model: GlitchCube.config.ai.default_model,
        temperature: GlitchCube.config.conversation&.temperature || 0.8,
        max_tokens: GlitchCube.config.conversation&.max_tokens || 200,
        timeout: GlitchCube.config.conversation&.completion_timeout || 20
      }
      
      # Add structured output if schema is provided
      if response_schema
        llm_options[:response_format] = GlitchCube::Schemas::ConversationResponseSchema.to_openrouter_format(response_schema)
      end
      
      # Add tool support if tools are configured
      if context[:tools]
        llm_options[:tools] = context[:tools]
        llm_options[:tool_choice] = context[:tool_choice] || 'auto'
        llm_options[:parallel_tool_calls] = context[:parallel_tool_calls] != false
      end
      
      # Use new LLM service with structured outputs
      llm_response = Services::LLMService.complete(
        system_prompt: system_prompt,
        user_message: message,
        **llm_options
      )
      
      response_time_ms = ((Time.now - start_time) * 1000).round
      
      # Extract data from response object
      response_text = llm_response.response_text
      continue_conversation = llm_response.continue_conversation?
      
      # Calculate cost
      cost = llm_response.cost
      
      # Record assistant message
      conversation.add_message(
        role: 'assistant',
        content: response_text,
        persona: persona,
        model_used: llm_response.model,
        prompt_tokens: llm_response.usage[:prompt_tokens],
        completion_tokens: llm_response.usage[:completion_tokens],
        cost: cost,
        response_time_ms: response_time_ms,
        metadata: { 
          continue_conversation: continue_conversation
        }.compact
      )
      
      # Update conversation totals
      conversation.update_totals!

      response_text ||= generate_fallback_response(message, persona)

      result = {
        response: response_text,
        conversation_id: conversation.id,
        session_id: conversation.session_id,
        persona: persona,
        model: llm_response.model,
        cost: cost,
        tokens: llm_response.usage,
        continue_conversation: continue_conversation
      }

      speak_response(response_text, context)
      log_interaction(conversation, message, response_text, persona)
      update_kiosk_display(message, response_text, persona)

      result
    rescue Services::LLMService::RateLimitError => e
      handle_rate_limit_error(conversation, message, persona, e)
    rescue Services::LLMService::LLMError => e
      handle_llm_error(conversation, message, persona, e)
    rescue StandardError => e
      handle_general_error(conversation, message, persona, e)
    end
  end

  private

  def parse_llm_response(content)
    # Try to parse as JSON for structured response
    begin
      if content.is_a?(String)
        # Clean content - sometimes the response has markdown json blocks
        cleaned = content.strip
        cleaned = cleaned.gsub(/^```json\s*/, '').gsub(/\s*```$/, '') if cleaned.include?('```')
        
        if cleaned.start_with?('{')
          parsed = JSON.parse(cleaned)
          result = {
            response: parsed['response'] || parsed['text'] || content,
            continue_conversation: parsed['continue_conversation'] != false # Default to true
          }
          
          # Extract additional structured data if present
          result[:actions] = parsed['actions'] if parsed['actions']
          result[:lighting] = parsed['lighting'] if parsed['lighting']
          result[:inner_thoughts] = parsed['inner_thoughts'] if parsed['inner_thoughts']
          result[:memory_note] = parsed['memory_note'] if parsed['memory_note']
          result[:request_action] = parsed['request_action'] if parsed['request_action']
          result[:tool_calls] = parsed['tool_calls'] if parsed['tool_calls']
          
          result
        else
          # Fallback to simple text response with smart continuation detection
          {
            response: content,
            continue_conversation: detect_continuation_intent(content)
          }
        end
      else
        # Fallback to simple text response with smart continuation detection
        {
          response: content.to_s,
          continue_conversation: detect_continuation_intent(content.to_s)
        }
      end
    rescue JSON::ParserError => e
      # If JSON parsing fails, treat as plain text
      Rails.logger.warn "Failed to parse LLM JSON response: #{e.message}" if defined?(Rails)
      {
        response: content,
        continue_conversation: detect_continuation_intent(content)
      }
    end
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
    require_relative '../schemas/conversation_response_schema' rescue nil
    
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

  def find_or_create_conversation(context)
    session_id = context[:session_id] || SecureRandom.uuid
    
    # Find active conversation or create new one
    Conversation.active.find_by(session_id: session_id) ||
      Conversation.create!(
        session_id: session_id,
        source: context[:source] || 'api',
        started_at: Time.current,
        metadata: context.except(:session_id, :source)
      )
  end
  
  def calculate_message_cost(response)
    return 0.0 unless response[:usage] && response[:model]
    
    GlitchCube::ModelPricing.calculate_cost(
      response[:model],
      response[:usage][:prompt_tokens],
      response[:usage][:completion_tokens]
    )
  end

  def build_system_prompt(persona, context)
    # Map persona to character for prompt file selection
    character = persona == 'neutral' ? nil : persona

    # Build enriched context
    enriched_context = context.merge(
      current_persona: persona,
      session_id: context[:session_id] || SecureRandom.uuid,
      interaction_count: context[:interaction_count] || 1
    )

    # Generate system prompt with current datetime and context
    Services::SystemPromptService.new(
      character: character,
      context: enriched_context
    ).generate
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
  
  def update_awtrix_display(message, response, persona)
    return unless GlitchCube.config.home_assistant.url
    
    # Run display updates in parallel
    Concurrent::Future.execute do
      begin
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
        
      rescue => e
        puts "⚠️ AWTRIX update failed: #{e.message}"
      end
    end
  rescue => e
    puts "⚠️ Failed to initiate AWTRIX update: #{e.message}"
  end

  def handle_rate_limit_error(conversation, message, persona, error)
    response_text = "I need to take a brief pause - too many thoughts at once! Can you give me a moment?"
    
    # Still record the response
    conversation.add_message(
      role: 'assistant',
      content: response_text,
      persona: persona,
      metadata: { error: error.message }
    )
    
    speak_response(response_text, {})
    
    {
      response: response_text,
      conversation_id: conversation.id,
      session_id: conversation.session_id,
      persona: persona,
      error: 'rate_limit'
    }
  end

  def handle_llm_error(conversation, message, persona, error)
    response_text = generate_offline_response(message, persona)
    
    conversation.add_message(
      role: 'assistant',
      content: response_text,
      persona: persona,
      metadata: { error: error.message }
    )
    
    speak_response(response_text, {})
    
    {
      response: response_text,
      conversation_id: conversation.id,
      session_id: conversation.session_id,
      persona: persona,
      error: 'llm_error'
    }
  end

  def handle_general_error(conversation, message, persona, error)
    response_text = generate_fallback_response(message, persona)
    
    conversation.add_message(
      role: 'assistant',
      content: response_text,
      persona: persona,
      metadata: { error: error.message }
    )
    
    Services::LoggerService.log_interaction(
      user_message: message,
      ai_response: response_text,
      persona: persona,
      error: error.message
    )
    
    speak_response(response_text, {})
    
    {
      response: response_text,
      conversation_id: conversation.id,
      session_id: conversation.session_id,
      persona: persona,
      error: 'general_error'
    }
  end

  def log_interaction(conversation, message, response, persona)
    Services::LoggerService.log_interaction(
      user_message: message,
      ai_response: response,
      persona: persona,
      conversation_id: conversation.id,
      session_id: conversation.session_id
    )
  end

  def extract_content_from_response(response)
    # Handle different response formats from OpenRouter
    if response.is_a?(Hash) || response.is_a?(HashWithIndifferentAccess)
      # Standard OpenAI format response (with indifferent access)
      choices = response[:choices] || response['choices']
      if choices && choices.is_a?(Array) && !choices.empty?
        message = choices[0][:message] || choices[0]['message']
        message[:content] || message['content'] || ''
      # Alternative format with direct content
      elsif response[:content] || response['content']
        response[:content] || response['content']
      else
        ''
      end
    elsif response.is_a?(String)
      # Direct string response
      response
    else
      ''
    end
  end
  

end
