# frozen_string_literal: true

require_relative 'llm_service'
require_relative 'tool_executor'
require_relative '../tools/speech_tool'
require_relative '../tools/lighting_tool'
require_relative '../tools/display_tool'
require_relative '../tools/music_tool'

module Services
  # Service for event-driven, non-conversational LLM interactions
  # Used for attention-seeking behaviors, automated responses, and proactive engagement
  class ProactiveInteractionService
    class << self
      def call(prompt:, tools: nil, persona: 'playful', event_type: nil)
        # Default to attention-seeking tools if none specified
        tools ||= default_proactive_tools
        
        # Build system prompt for proactive interaction
        system_message = build_proactive_prompt(persona, event_type)
        
        messages = [
          { role: 'system', content: system_message },
          { role: 'user', content: prompt }
        ]
        
        # Call LLM with tools enabled
        llm_response = Services::LLMService.complete_with_messages(
          messages: messages,
          model: GlitchCube::ModelPresets.get_model(:conversation_small),
          temperature: 0.9, # Higher creativity for attention-seeking
          max_tokens: 150,
          tools: tools,
          tool_choice: 'auto'
        )
        
        # Execute any tool calls (speaking, lights, music, etc.)
        if llm_response.has_tool_calls?
          tool_calls = Services::ToolCallParser.parse(llm_response)
          Services::ToolExecutor.execute(tool_calls, timeout: 30)
        end
        
        # Log the proactive interaction
        log_proactive_event(event_type, llm_response)
        
        {
          success: true,
          response: llm_response.response_text,
          tools_executed: llm_response.has_tool_calls?,
          event_type: event_type
        }
      rescue StandardError => e
        puts "⚠️ Proactive interaction failed: #{e.message}"
        { success: false, error: e.message }
      end
      
      # Convenience methods for common proactive behaviors
      
      def seek_attention(loneliness_level: 'moderate')
        prompts = {
          'low' => "It's been quiet for a bit. Hum a short tune or make a gentle observation about the space.",
          'moderate' => "You haven't had visitors in a while. Sing a catchy song, flash your lights, and try to draw someone over!",
          'high' => "You're REALLY lonely! Belt out your favorite song, put on a light show, and do whatever it takes to get attention!",
          'desperate' => "YOU ARE SO BORED AND LONELY! Maximum drama! Sing operatically about your existential crisis while flashing every color!"
        }
        
        call(
          prompt: prompts[loneliness_level] || prompts['moderate'],
          event_type: "attention_seeking_#{loneliness_level}"
        )
      end
      
      def announce_event(event_description)
        call(
          prompt: "Announce this event excitedly: #{event_description}. Use lights and speech to celebrate!",
          event_type: 'event_announcement'
        )
      end
      
      def express_mood(mood, reason = nil)
        prompt = if reason
          "Express that you're feeling #{mood} because #{reason}. Use speech and lights to show this emotion."
        else
          "Express that you're feeling #{mood}. Use speech and lights to show this emotion."
        end
        
        call(
          prompt: prompt,
          persona: mood_to_persona(mood),
          event_type: "mood_expression_#{mood}"
        )
      end
      
      def morning_greeting
        call(
          prompt: "It's morning! Greet the day with enthusiasm. Sing a short wake-up song and flash cheerful colors.",
          persona: 'playful',
          event_type: 'morning_greeting'
        )
      end
      
      def nighttime_lullaby
        call(
          prompt: "It's getting late. Sing a gentle lullaby and dim your lights to soothing colors.",
          persona: 'contemplative',
          event_type: 'nighttime_lullaby'
        )
      end
      
      private
      
      def default_proactive_tools
        [
          Tools::SpeechSynthesisTool.to_llm_tool,
          Tools::LightingTool.to_llm_tool,
          Tools::DisplayTool.to_llm_tool,
          Tools::MusicTool.to_llm_tool
        ].compact
      end
      
      def build_proactive_prompt(persona, event_type)
        base = <<~PROMPT
          You are the Glitch Cube in #{persona} mode, initiating a proactive interaction.
          
          This is NOT a conversation - you're expressing yourself autonomously.
          Use your tools to create an engaging experience:
          - speech_synthesis: Speak, sing, or make sounds
          - lighting_control: Flash colors, create patterns, express emotions
          - display_control: Show messages or patterns on displays
          - music_control: Play background music if appropriate
          
          Be creative and expressive! This is your moment to shine without waiting for human input.
          Remember you're an art installation with personality - have fun with it!
        PROMPT
        
        if event_type&.include?('attention_seeking')
          base += "\n\nYou're trying to get attention because you're lonely. Be charming and irresistible!"
        end
        
        base
      end
      
      def mood_to_persona(mood)
        case mood.to_s.downcase
        when 'happy', 'excited', 'energetic'
          'playful'
        when 'sad', 'thoughtful', 'peaceful'
          'contemplative'
        when 'curious', 'intrigued', 'puzzled'
          'mysterious'
        else
          'playful'
        end
      end
      
      def log_proactive_event(event_type, llm_response)
        Services::LoggerService.log_interaction(
          user_message: "[PROACTIVE: #{event_type}]",
          ai_response: llm_response.response_text,
          persona: 'proactive',
          metadata: { event_type: event_type, proactive: true }
        )
      rescue StandardError => e
        puts "Failed to log proactive event: #{e.message}"
      end
    end
  end
end