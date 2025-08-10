# frozen_string_literal: true

require 'time'
require 'tzinfo'

module Personas
  class BasePersona
    class PersonaNotFoundError < StandardError; end

    # Registry for persona classes
    @registry = {}

    class << self
      # Register a persona class
      def register_persona(name, persona_class)
        @registry[name.to_s.downcase] = persona_class
      end

      # Factory method to create personas
      def create(persona_name, context = {})
        name = normalize_persona_name(persona_name)
        persona_class = @registry[name]

        # Default to BuddyPersona if persona not found or 'default' is requested
        if !persona_class || name == 'default'
          require_relative 'buddy_persona'
          persona_class = Personas::BuddyPersona
        end

        persona_class.new(context)
      end

      def available_personas
        @registry.keys
      end

      def persona_exists?(persona_name)
        @registry.key?(normalize_persona_name(persona_name))
      end

      private

      def normalize_persona_name(persona_name)
        return 'default' if persona_name.nil? || persona_name.to_s.strip.empty?

        name = persona_name.to_s.downcase.strip
        name == 'default' ? 'default' : name
      end
    end

    public

    PROMPTS_DIR = File.join(File.dirname(__FILE__), '../../prompts')

    attr_reader :name, :context

    def initialize(context = {})
      @context = context
      @name = self.class.name.split('::').last.gsub('Persona', '').downcase
    end

    # Abstract methods that subclasses must implement
    def prompt_file
      raise NotImplementedError, "#{self.class} must implement prompt_file"
    end

    def available_tools
      raise NotImplementedError, "#{self.class} must implement available_tools"
    end

    def fallback_responses
      raise NotImplementedError, "#{self.class} must implement fallback_responses"
    end

    def offline_responses
      raise NotImplementedError, "#{self.class} must implement offline_responses"
    end

    # Generate system prompt for this persona
    def generate_system_prompt
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

    # Get a fallback response when LLM fails
    def generate_fallback_response(_message = nil)
      responses = fallback_responses
      responses.sample || "I'm processing your thoughts..."
    end

    # Get an offline response when AI service is unavailable
    def generate_offline_response(_message = nil)
      base_responses = offline_responses
      base_response = base_responses.sample || "I'm currently operating in offline mode."

      encouragement = [
        'Feel free to keep talking - sometimes the best conversations happen in the quiet moments.',
        "I'll be back to full capability soon, but your words still matter to me.",
        "This is just a different kind of artistic moment we're sharing."
      ].sample

      "#{base_response} #{encouragement}"
    end

    # Get tool schemas for this persona (lazy loaded)
    def tool_schemas
      @tool_schemas ||= build_tool_schemas
    end

    private

    def build_tool_schemas
      return [] if available_tools.empty?

      # Lazy load tool classes only when needed
      loaded_tools = available_tools.map do |tool_class|
        if tool_class.is_a?(String)
          require_relative "../tools/#{tool_class}"
          Object.const_get(tool_class.split('_').map(&:capitalize).join)
        else
          tool_class
        end
      end

      tools = []
      loaded_tools.each do |tool_class|
        next unless tool_class.respond_to?(:available_tools)

        tool_class.available_tools.each do |tool_name|
          tools << {
            'type' => 'function',
            'function' => {
              'name' => tool_name,
              'description' => "#{tool_class.prompt_description} - #{tool_name}",
              'parameters' => tool_class.tool_schemas[tool_name] || { 'type' => 'object', 'properties' => {} }
            }
          }
        end
      end

      tools
    end

    public

    private

    def datetime_section
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
      prompt_path = File.join(PROMPTS_DIR, prompt_file)

      if File.exist?(prompt_path)
        File.read(prompt_path).strip
      else
        default_prompt
      end
    rescue StandardError => e
      puts "Error loading prompt file: #{e.message}"
      default_prompt
    end

    def default_prompt
      "You are #{name.capitalize}, an AI assistant."
    end

    def tools_section
      return '' if tool_schemas.empty?

      tools_lines = ['AVAILABLE TOOLS AND CAPABILITIES:']
      tools_lines << 'You have access to the following tools that match your character abilities:'
      tools_lines << ''

      tool_schemas.each do |tool_schema|
        function = tool_schema['function']
        tools_lines << "- #{function['name']}: #{function['description']}"
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

    def extract_environment_context
      return {} unless context

      env_keys = %i[
        temperature humidity light_level motion_detected
        sound_level time_of_day weather location
        interaction_count session_duration last_interaction
      ]

      context.slice(*env_keys)
    end

    def context_section
      return '' unless context&.dig(:additional_context)

      context_lines = ['ADDITIONAL CONTEXT:']
      context_lines << context[:additional_context]
      context_lines.join("\n")
    end

    def structured_output_section
      return '' unless context&.dig(:response_format)

      <<~STRUCTURED
        RESPONSE FORMAT:
        You must structure your response according to the provided schema.
        Ensure all required fields are included and properly formatted.
      STRUCTURED
    end
  end
end
