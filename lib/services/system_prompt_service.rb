# frozen_string_literal: true

require 'time'
require 'tzinfo'

module Services
  class SystemPromptService
    PROMPTS_DIR = File.join(File.dirname(__FILE__), '../../prompts')
    DEFAULT_PROMPT_FILE = 'default.txt'

    attr_reader :character, :context

    def initialize(character: nil, context: {})
      @character = character
      @context = context
    end

    def generate
      prompt_parts = [
        datetime_section,
        base_prompt,
        context_section
      ].compact.reject(&:empty?)

      prompt_parts.join("\n\n")
    end

    private

    def datetime_section
      # Get current time in Pacific timezone
      timezone = defined?(GlitchCube::Constants) ? GlitchCube::Constants::LOCATION[:timezone] : 'America/Los_Angeles'
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
      puts "Error loading prompt file: #{e.message}"
      default_glitch_cube_prompt
    end

    def context_section
      return '' if context.nil? || context.empty?

      context_lines = ['ADDITIONAL CONTEXT:']

      context.each do |key, value|
        formatted_key = key.to_s.split('_').map(&:capitalize).join(' ')
        context_lines << "#{formatted_key}: #{value}"
      end

      context_lines.join("\n")
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
