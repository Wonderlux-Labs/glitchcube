# frozen_string_literal: true

module Services
  module Conversation
    class PromptCompositionService
      PROMPTS_DIR = File.join(File.dirname(__FILE__), '../../../prompts')
      SHARED_DIR = File.join(PROMPTS_DIR, 'shared')

      def self.build_system_prompt(persona: nil, context: {})
        new(persona: persona, context: context).build
      end

      def initialize(persona: nil, context: {})
        @persona = persona
        @context = context
      end

      def build
        components = [
          datetime_section,
          base_identity,
          persona_content,
          tool_integration,
          burning_man_attitude,
          tools_section,
          environment_section,
          context_section,
          response_format
        ].compact.reject(&:empty?)

        components.join("\n\n")
      end

      private

      def datetime_section
        # Get current time in Pacific timezone
        timezone = defined?(Constants) ? Constants::LOCATION[:timezone] : 'America/Los_Angeles'
        tz = TZInfo::Timezone.get(timezone)
        current_time = tz.now

        <<~DATETIME
        --
        Date: #{current_time.strftime('%A, %B %d, %Y')}
        Time: #{current_time.strftime('%I:%M %p')} #{tz.current_period.abbreviation}
        --
        DATETIME
      end

      def base_identity
        load_shared_component('base_identity.txt')
      end

      def persona_content
        return '' unless @persona

        persona_file = "#{@persona}.txt"
        persona_path = File.join(PROMPTS_DIR, persona_file)

        if File.exist?(persona_path)
          File.read(persona_path).strip
        else
          ''
        end
      rescue StandardError => e
        Rails.logger&.error("Error loading persona file: #{e.message}")
        ''
      end

      def tool_integration
        load_shared_component('tool_integration.txt')
      end

      def burning_man_attitude
        load_shared_component('burning_man_attitude.txt')
      end

      def response_format
        load_shared_component('response_format.txt')
      end

      def tools_section
        return '' if @context.nil?

        # Support both old format (available_tools) and new format (tools)
        available_tools = @context[:available_tools] || @context[:tools]
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
            description = tool_description(tool)
            tools_lines << "- #{formatted_tool}: #{description}"
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
        return {} if @context.nil? || @context.empty?

        environment_keys = %i[
          current_location temperature dust_level nearby_sounds
          people_detected battery_level time_of_day current_mood
          dust_storm_warning party_mode
        ]

        @context.slice(*environment_keys)
      end

      def extract_additional_context
        return {} if @context.nil? || @context.empty?

        excluded_keys = %i[
          available_tools tools current_location temperature dust_level
          nearby_sounds people_detected battery_level time_of_day
          current_mood dust_storm_warning party_mode
        ]

        @context.except(*excluded_keys)
      end

      def tool_description(tool)
        # Try to get description from ToolRegistryService if available
        if defined?(ToolRegistryService)
          ToolRegistryService.get_tool_prompt(tool.to_s)
        else
          "Control #{tool.to_s.humanize.downcase}"
        end
      end

      def load_shared_component(filename)
        component_path = File.join(SHARED_DIR, filename)
        return '' unless File.exist?(component_path)

        File.read(component_path).strip
      rescue StandardError => e
        Rails.logger&.error("Error loading shared component #{filename}: #{e.message}")
        ''
      end
    end
  end
end
