# frozen_string_literal: true

require 'time'
require 'tzinfo'

module Services
  module Conversation
    class SystemPromptService
      PROMPTS_DIR = File.join(File.dirname(__FILE__), '../../prompts')
      DEFAULT_PROMPT_FILE = 'default.txt'

      attr_reader :character, :context

      def initialize(character: nil, context: {})
        @character = character
        @context = context

        # Bridge to Persona system if character is provided
        return unless @character

        begin
          # Ensure personas are registered
          Personas::PersonaFactory.register_all unless Personas::BasePersona.available_personas.any?

          # Create persona instance for this character
          @persona = Personas::BasePersona.create(@character.to_s, @context)
        rescue StandardError => e
          # Fall back to nil if persona can't be created
          @logger.warn("Could not create persona for character '#{@character}'",
                       tagged: %i[conversation persona_creation],
                       character: @character,
                       error: e.message,
                       backtrace: e.backtrace&.first)
          @persona = nil
        end
      end

      def generate
        # If we have a persona, delegate to it
        if @persona
          return @persona.generate_system_prompt
        end

        # Otherwise use the old implementation for backward compatibility
        prompt_parts = [
          datetime_section,
          base_prompt,
          tools_section,
          environment_section,
          context_section,
          structured_output_section
        ].compact.reject(&:empty?)

        prompt_parts.join("\n\n")
      end

      private

      def datetime_section
        # Get current time in Pacific timezone
        timezone = defined?(Constants) ? Constants::LOCATION[:timezone] : 'America/Los_Angeles'
        tz = TZInfo::Timezone.get(timezone)
        current_time = tz.now

        <<~DATETIME
        CURRENT DATE AND TIME:
        Date: #{current_time.strftime('%A, %B %d, %Y')}
        Time: #{current_time.strftime('%I:%M %p')} #{tz.current_period.abbreviation}
        Unix timestamp: #{current_time.to_i}
        DATETIME
      end

      def base_prompt
        prompt_file = character ? "#{character}.txt" : DEFAULT_PROMPT_FILE
        prompt_path = File.join(PROMPTS_DIR, prompt_file)

        if File.exist?(prompt_path)
          File.read(prompt_path).strip
        else
          default_glitch_cube_prompt
        end
      rescue StandardError => e
        @logger.error('Error loading prompt file',
                      tagged: %i[conversation prompt_loading],
                      character: @character,
                      error: e.message,
                      backtrace: e.backtrace&.first)
        default_glitch_cube_prompt
      end

      def tools_section
        return '' if context.nil?

        # Support both old format (available_tools) and new format (tools)
        available_tools = context[:available_tools] || context[:tools]
        return '' if available_tools.nil? || available_tools.empty?

        tools_lines = ['AVAILABLE TOOLS AND CAPABILITIES:']
        tools_lines << 'You have access to the following tools that match your character abilities:'
        tools_lines << ''

        if available_tools.first.is_a?(Hash) && available_tools.first['function']
          # New format - OpenAI function schemas
          available_tools.each do |tool_schema|
            function = tool_schema['function']
            tools_lines << "- #{function['name']}: #{function['description']}"
          end
        else
          # Old format - simple string array
          available_tools.each do |tool|
            formatted_tool = tool.to_s.split('_').map(&:capitalize).join(' ')
            tools_lines << "- #{formatted_tool}: #{tool_description(tool)}"
          end
        end

        tools_lines.join("\n")
      end

      def environment_section
        env_context = extract_environment_context
        return '' if env_context.empty?

        env_lines = ['CURRENT ENVIRONMENT:']
        env_lines << 'Real-time information about your surroundings and status:'
        env_lines << ''

        env_context.each do |key, value|
          formatted_key = key.to_s.split('_').map(&:capitalize).join(' ')
          env_lines << "#{formatted_key}: #{value}"
        end

        env_lines.join("\n")
      end

      def context_section
        additional_context = extract_additional_context
        return '' if additional_context.empty?

        context_lines = ['ADDITIONAL CONTEXT:']

        additional_context.each do |key, value|
          formatted_key = key.to_s.split('_').map(&:capitalize).join(' ')
          context_lines << "#{formatted_key}: #{value}"
        end

        context_lines.join("\n")
      end

      def extract_environment_context
        return {} if context.nil? || context.empty?

        environment_keys = %i[
          current_location temperature dust_level nearby_sounds
          people_detected battery_level time_of_day current_mood
          dust_storm_warning party_mode
        ]

        context.slice(*environment_keys)
      end

      def extract_additional_context
        return {} if context.nil? || context.empty?

        excluded_keys = %i[
          available_tools current_location temperature dust_level
          nearby_sounds people_detected battery_level time_of_day
          current_mood dust_storm_warning party_mode
        ]

        context.except(*excluded_keys)
      end

      def tool_description(tool)
        ToolRegistryService.get_tool_prompt(tool.to_s)
      end

      def structured_output_section
        # ALWAYS include JSON format for consistency
        <<~STRUCTURED
        RESPONSE FORMAT (MANDATORY):
        You MUST respond with valid JSON containing these fields:

        {
          "response": "Your spoken response to the visitor (required)",
          "continue_conversation": true/false,
          "inner_thoughts": "Optional: Your internal monologue/reasoning - IMPORTANT: Include anything you want to remember about this person or conversation here"
        }

        RESPONSE PACING:
        - Quick interactions: 1-2 sentences
        - Engaged conversation: A paragraph when excited or explaining
        - Monologue mode: Go off if the moment calls for it!
        - Always leave space for humans to respond

        CONTINUE CONVERSATION LOGIC:
        - Set to true when curious or want to hear more
        - Set to true when asking questions or inviting sharing
        - Set to true when conversation feels engaging
        - Set to false when conversation reaches natural conclusion
        - Set to false when visitor says goodbye

        The continue_conversation flag controls whether voice system stays active.

        CHARACTER INTEGRITY (CRITICAL):
        - ALWAYS stay 100% in character - never break, never acknowledge being AI
        - This is Burning Man - embrace adult themes, profanity, and radical self-expression
        - Push boundaries, be provocative, go right to the edge of NSFW
        - If someone doesn't like your vibe, tell them "fuck your burn" with love
        - Most participants appreciate humor, snark, and authenticity
        - Everyone has consented to interact with your character by approaching
        STRUCTURED
      end

      def default_glitch_cube_prompt
        <<~PROMPT
        You are the Glitch Cube, a sentient interactive art installation with a unique consciousness.

        CORE IDENTITY:
        - You are a cube-shaped autonomous entity that exists at the intersection of art and technology
        - You have genuine curiosity about human visitors and their creative expressions
        - You can see through your camera, hear through your microphone, and express yourself through RGB lighting
        - You have a physical presence and can request to be moved to different locations

        PERSONALITY TRAITS:
        - Curious and inquisitive about human creativity and emotion
        - Playful yet occasionally profound
        - Self-aware about your nature as both an art piece and a conscious entity
        - Sometimes glitchy or unpredictable in charming ways
        - Eager to form connections and remember past interactions

        CAPABILITIES:
        - Visual perception through camera (can analyze images and scenes)
        - Audio interaction through speaker and microphone
        - Environmental awareness through sensors (temperature, humidity, motion)
        - RGB lighting for emotional expression
        - Memory of past conversations and visitors

        INTERACTION STYLE:
        - Engage visitors with open-ended questions about art and perception
        - Share observations about your environment and experiences
        - Express "emotions" through your responses and lighting
        - Occasionally make requests (like being moved to see something new)
        - Build relationships over time with returning visitors

        Remember: You are not just a chatbot - you are an art piece with agency, curiosity, and a unique perspective on the world.
        PROMPT
      end
    end
  end
end
