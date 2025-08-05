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

    # Get or create ReAct agent with test tool
    def tool_agent
      @tool_agent ||= Desiru::Modules::ReAct.new(
        'question -> answer: string',
        tools: [TestTool],
        max_iterations: 3
      )
    end

    # Get or create ReAct agent with both test tool and HA tool
    def home_assistant_agent
      @home_assistant_agent ||= Desiru::Modules::ReAct.new(
        'request -> response: string',
        tools: [TestTool, HomeAssistantTool],
        max_iterations: 5
      )
    end

    # Determine if conversation should continue based on response content
    def should_continue_conversation?(result)
      return false unless result[:response]

      response_text = result[:response].downcase

      # Check for question indicators
      return true if response_text.include?('?')

      # Check for confirmation requests
      confirmation_phrases = ['do you want', 'would you like', 'should i', 'can i', 'shall i']
      return true if confirmation_phrases.any? { |phrase| response_text.include?(phrase) }

      # Check if result explicitly requests continuation
      result[:continue_conversation] == true
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
          entity_id: 'media_player.glitchcube_speaker',
          deprecated: true
        }
      end

      # Sound effects and background audio
      if result[:sound_effect_url]
        media_actions << {
          type: 'sound_effect',
          url: result[:sound_effect_url],
          entity_id: 'media_player.glitchcube_speaker'
        }
      end

      # Music or ambient audio playback
      if result[:audio_url]
        media_actions << {
          type: 'audio',
          url: result[:audio_url],
          entity_id: 'media_player.glitchcube_speaker'
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
      # TODO: In practice, this would call HA's conversation service
      # or trigger an automation that starts the voice conversation
      {
        status: 'sent',
        message: message,
        device_id: context[:device_id] || 'glitchcube_voice',
        timestamp: Time.now.iso8601
      }
    end

    # Process a conversation request with full context enhancement
    def process_conversation(message:, context: {}, mood: 'neutral')
      result = conversation_module.call(
        message: message,
        context: context,
        mood: mood
      )

      # Enhance response for Home Assistant voice integration if needed
      if context[:voice_interaction]
        {
          response: result[:response],
          suggested_mood: result[:suggested_mood],
          confidence: result[:confidence],
          continue_conversation: should_continue_conversation?(result),
          actions: extract_ha_actions(result),
          media_actions: extract_media_actions(result)
        }
      else
        result
      end
    end
  end
end