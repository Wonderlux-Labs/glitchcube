# frozen_string_literal: true

module Services
  # Centralized service for conversation processing and Home Assistant integration
  # Handles conversation continuation logic, action extraction, and proactive messaging
  class ConversationHandlerService
    def initialize
      @conversation_module = nil
      @tool_agent = nil
      @home_assistant_agent = nil
    end

    # Get or create conversation module instance
    def conversation_module
      @conversation_module ||= ConversationModule.new
    end

    # Get or create tool agent - deprecated, use ConversationModule directly instead
    def tool_agent
      # Desiru removed - use ConversationModule directly
      nil
    end

    # Get or create home assistant agent - deprecated, use ConversationModule directly instead
    def home_assistant_agent
      # Desiru removed - use ConversationModule directly
      nil
    end

    # Determine if conversation should continue based on response content
    def should_continue_conversation?(result)
      # First check if the LLM explicitly indicated continuation
      return true if result[:continue_conversation] == true

      return false unless result[:response]

      response_text = result[:response].downcase

      # Check for question indicators
      return true if response_text.include?('?')

      # Check for confirmation requests or engagement phrases
      continuation_phrases = [
        'do you want', 'would you like', 'should i', 'can i', 'shall i',
        'tell me', 'what about', 'how about', 'let me know', 'interested in',
        'shall we', 'want to hear', 'curious about', 'wondering if'
      ]
      return true if continuation_phrases.any? { |phrase| response_text.include?(phrase) }

      # Check for explicit conversation enders
      ending_phrases = ['goodbye', 'bye', 'see you', 'talk to you later', 'nice talking']
      return false if ending_phrases.any? { |phrase| response_text.include?(phrase) }

      # Default to continuing for art installation engagement
      true
    end

    # Extract Home Assistant actions from conversation result
    def extract_ha_actions(result)
      actions = []

      # Check if result contains explicit HA actions
      actions.concat(result[:ha_actions]) if result[:ha_actions]

      # Parse natural language for common actions
      response_text = result[:response]&.downcase || ''

      # Light controls
      if response_text.match(/turn.*on.*light/)
        actions << {
          domain: 'light',
          service: 'turn_on',
          target: { entity_id: 'light.glitch_cube' }
        }
      elsif response_text.match(/turn.*off.*light/)
        actions << {
          domain: 'light',
          service: 'turn_off',
          target: { entity_id: 'light.glitch_cube' }
        }
      end

      # TODO: Add more sophisticated action extraction
      # Could use NLP or pattern matching for more complex commands

      actions
    end

    # Extract media actions for NON-SPEECH audio (sound effects, music, etc.)
    def extract_media_actions(result)
      media_actions = []

      # Check if result contains explicit media actions
      media_actions.concat(result[:media_actions]) if result[:media_actions]

      # DEPRECATED: TTS should use main 'response' field instead
      if result[:tts_message]
        media_actions << {
          type: 'tts',
          message: result[:tts_message],
          entity_id: 'media_player.square_voice',
          deprecated: true
        }
      end

      # Sound effects and background audio
      if result[:sound_effect_url]
        media_actions << {
          type: 'sound_effect',
          url: result[:sound_effect_url],
          entity_id: 'media_player.square_voice'
        }
      end

      # Music or ambient audio playback
      if result[:audio_url]
        media_actions << {
          type: 'audio',
          url: result[:audio_url],
          entity_id: 'media_player.square_voice'
        }
      end

      media_actions
    end

    # Generate contextual conversation starters based on triggers
    def generate_proactive_message(trigger_type, context)
      case trigger_type
      when 'motion_detected'
        'Hey there! I noticed you just walked in. How are you doing?'
      when 'battery_low'
        "I'm running a bit low on battery. Should I ask someone to help charge me?"
      when 'weather_change'
        "The weather is changing - it looks like #{context[:weather_description]}. Anything you'd like me to adjust?"
      when 'timer_finished'
        "Your #{context[:timer_name] || 'timer'} is done! What would you like to do next?"
      when 'interaction_timeout'
        "It's been a while since we last talked. I've been thinking about #{context[:topic] || 'art and existence'}. What's on your mind?"
      when 'new_person'
        'I sense someone new nearby. Should I introduce myself?'
      when 'system_alert'
        "I need to let you know about something: #{context[:alert_message]}. How should we handle this?"
      else
        'I have something to share with you. Are you available to chat?'
      end
    end

    # Send proactive conversation to Home Assistant voice system
    def send_conversation_to_ha(message, context)
      home_assistant = HomeAssistantClient.new

      begin
        # Start conversation via HA's conversation service
        response = home_assistant.call_service(
          'conversation',
          'process',
          {
            text: message,
            conversation_id: context[:conversation_id],
            device_id: context[:device_id] || 'glitchcube',
            language: context[:language] || 'en'
          }
        )

        {
          status: 'sent',
          ha_conversation_id: response['conversation_id'] || context[:conversation_id],
          message: message,
          device_id: context[:device_id] || 'glitchcube',
          timestamp: Time.now.iso8601
        }
      rescue StandardError => e
        # Fallback response if HA conversation service is unavailable
        {
          status: 'fallback',
          message: message,
          device_id: context[:device_id] || 'glitchcube',
          timestamp: Time.now.iso8601,
          error: e.message
        }
      end
    end

    # Continue an existing Home Assistant conversation
    def continue_ha_conversation(conversation_id, message, context = {})
      home_assistant = HomeAssistantClient.new

      begin
        response = home_assistant.call_service(
          'conversation',
          'process',
          {
            text: message,
            conversation_id: conversation_id,
            device_id: context[:device_id] || 'glitchcube',
            language: context[:language] || 'en'
          }
        )

        {
          status: 'continued',
          ha_conversation_id: conversation_id,
          response: response,
          timestamp: Time.now.iso8601
        }
      rescue StandardError => e
        {
          status: 'error',
          error: e.message,
          timestamp: Time.now.iso8601
        }
      end
    end

    # Sync conversation with Home Assistant
    def sync_with_ha(conversation, ha_conversation_id, device_id = nil)
      return unless conversation.respond_to?(:update!)

      conversation.update!(
        ha_conversation_id: ha_conversation_id,
        ha_device_id: device_id || 'glitchcube',
        metadata: (conversation.metadata || {}).merge(
          ha_synced_at: Time.now.iso8601,
          ha_conversation_active: true
        )
      )
    rescue StandardError => e
      Rails.logger.error "Failed to sync with HA: #{e.message}" if defined?(Rails)
      puts "Failed to sync with HA: #{e.message}"
    end

    # Process a conversation request with full context enhancement
    def process_conversation(message:, context: {})
      result = conversation_module.call(
        message: message,
        context: context
      )

      # Sync with HA if conversation IDs are present
      if context[:ha_conversation_id] && result[:conversation_id]
        conversation = Conversation.find_by(id: result[:conversation_id])
        sync_with_ha(conversation, context[:ha_conversation_id], context[:device_id]) if conversation
      end

      # Enhance response for Home Assistant voice integration if needed
      if context[:voice_interaction]
        enhanced_result = {
          response: result[:response],
          continue_conversation: should_continue_conversation?(result),
          actions: extract_ha_actions(result),
          media_actions: extract_media_actions(result),
          conversation_id: result[:conversation_id],
          session_id: result[:session_id]
        }

        # Add HA conversation ID if present
        enhanced_result[:ha_conversation_id] = context[:ha_conversation_id] if context[:ha_conversation_id]

        enhanced_result
      else
        result
      end
    end
  end
end
