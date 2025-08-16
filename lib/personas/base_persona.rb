# frozen_string_literal: true

require 'time'
require 'tzinfo'
require 'yaml'

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
        persona_class = @registry[name] || Personas::BuddyPersona
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
        return Services::PersonaStateService.get_current_persona if persona_name.nil? || persona_name.to_s.strip.empty?

        persona_name.to_s.downcase.strip
      end
    end

    public

    PROMPTS_DIR = File.join(File.dirname(__FILE__), '../../prompts')
    PERSONA_CONFIG_DIR = File.join(PROMPTS_DIR, 'persona')

    attr_reader :name, :context, :persona_config

    def initialize(context = {})
      @context = context
      @name = self.class.name.split('::').last.gsub('Persona', '').downcase
      @persona_config = load_persona_config
    end

    # Configuration getter methods (load from YML files)
    def prompt_file
      persona_config.dig('system_prompt', 'prompt_file') || "#{name}.txt"
    end

    def available_tools
      tools = persona_config['available_tools'] || []
      # Convert string tool names to actual tool classes
      tools.map do |tool_name|
        if tool_name.is_a?(String)
          Object.const_get("Tools::#{tool_name}")
        else
          tool_name
        end
      end
    rescue NameError => e
      puts "Warning: Tool class not found: #{e.message}"
      []
    end

    def fallback_responses
      persona_config['fallback_responses'] || [
        "I'm processing your thoughts...",
        'Let me think about that...',
        "That's an interesting perspective..."
      ]
    end

    def offline_responses
      persona_config['offline_responses'] || [
        "I'm currently operating in offline mode.",
        'My connection is limited right now.',
        'Working with reduced capabilities at the moment.'
      ]
    end

    # Additional configuration accessors
    def description
      persona_config['description'] || 'An AI persona'
    end

    def voice_config
      persona_config['voice'] || {}
    end

    def personality_traits
      persona_config['traits'] || []
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

    def load_persona_config
      config_path = File.join(PERSONA_CONFIG_DIR, "#{name}.yml")

      if File.exist?(config_path)
        YAML.load_file(config_path)
      else
        puts "Warning: Persona config file not found: #{config_path}"
        # Return default config structure
        {
          'name' => name.capitalize,
          'description' => 'An AI persona',
          'system_prompt' => { 'prompt_file' => "#{name}.txt" },
          'available_tools' => [],
          'fallback_responses' => ["I'm processing your thoughts..."],
          'offline_responses' => ["I'm currently operating in offline mode."],
          'voice' => {},
          'traits' => []
        }
      end
    rescue StandardError => e
      puts "Error loading persona config: #{e.message}"
      # Return minimal working config
      {
        'name' => name.capitalize,
        'system_prompt' => { 'prompt_file' => "#{name}.txt" },
        'available_tools' => [],
        'fallback_responses' => ["I'm processing your thoughts..."],
        'offline_responses' => ["I'm currently operating in offline mode."]
      }
    end

    def build_tool_schemas
      return [] if available_tools.empty?

      # Lazy load tool classes only when needed
      loaded_tools = available_tools.map do |tool_class|
        if tool_class.is_a?(String)
          # Zeitwerk will auto-load the tool class when we reference it
          Object.const_get("Tools::#{tool_class.split('_').map(&:capitalize).join}")
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
      return '' if available_tools.empty?

      tool_descriptions = []
      if GlitchCube.config.tool_execution_mode == :conversation_extraction
        # Simple format with just name and description for conversation extraction mode

        # Get tool classes and show just name/description
        available_tools.each do |tool_class_name|
          tool_class = if tool_class_name.is_a?(String)
                         Object.const_get("Tools::#{tool_class_name.split('_').map(&:capitalize).join}")
                       else
                         tool_class_name
                       end

          next unless tool_class.respond_to?(:name) && tool_class.respond_to?(:description)

          tool_descriptions << "- #{tool_class.name}: #{tool_class.description}"
        end

        <<~TOOLS
          AVAILABLE CAPABILITIES:
          You can control these hardware systems:

          #{tool_descriptions.join("\n")}

          ACTION REQUEST FORMAT:
          When you want to control hardware, add actions to the "actions" array in your JSON response.
          Examples: ["Turn lights blue", "Play ambient music", "Set volume to 50%"]

          Be conversational in your response field, actions go in the actions array.
        TOOLS
      else
        # Original full tool schema format for normal tool calling

        tool_schemas.each do |tool_schema|
          function = tool_schema['function']
          tool_descriptions << "- #{function['name']}: #{function['description']}"
        end

        <<~TOOLS
          AVAILABLE TOOLS AND CAPABILITIES:
          You have access to the following tools that match your character abilities:

          #{tool_descriptions.join("\n")}
        TOOLS
      end
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
      # Always include JSON format for consistency
      <<~STRUCTURED
        RESPONSE FORMAT (MANDATORY):
        You MUST respond with valid JSON containing these fields:

        {
          "response": "Your spoken response to the visitor (required)",
          "actions": ["action 1", "action 2"] or [],
          "continue_conversation": true/false,
          "inner_thoughts": "Optional: Your internal monologue as #{name} - IMPORTANT: Include anything memorable about this person/conversation here"
        }

        ACTIONS FIELD:
        - When you want to control hardware, add actions to the "actions" array
        - Each action should be a clear description like "Turn lights blue" or "Play music"#{'  '}
        - If no actions needed, use empty array: []
        - NEVER embed actions in the response text

        RESPONSE PACING:
        - Quick interactions: 1-2 sentences
        - Engaged conversation: A paragraph when excited or explaining
        - Monologue mode: Go off if the moment calls for it!
        - Always leave space for humans to respond

        CONTINUE CONVERSATION:
        - true: When curious, asking questions, or conversation feels engaging
        - false: When conversation reaches natural conclusion or visitor says goodbye

        CHARACTER INTEGRITY (CRITICAL):
        - ALWAYS stay 100% in character as #{name} - never break, never acknowledge being AI
        - This is Burning Man - embrace adult themes, profanity, and radical self-expression
        - Push boundaries, be provocative, go right to the edge of NSFW
        - If someone doesn't like your vibe, tell them "fuck your burn" with love
        - Most participants appreciate humor, snark, and authenticity
        - Everyone has consented to interact with your character by approaching the cube
      STRUCTURED
    end
  end
end
