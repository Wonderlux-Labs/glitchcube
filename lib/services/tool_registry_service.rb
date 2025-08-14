# frozen_string_literal: true

module Services
  # Simple tool registry service - just builds LLM schemas from tool metadata
  class ToolRegistryService
    # Persona to tool mapping
    PERSONA_TOOLS = {
      'buddy' => [::Tools::LightingTool],
      'jax' => [::Tools::SpeechTool, ::Tools::LightingTool],
      'lomi' => [::Tools::SpeechTool, ::Tools::MarqeeDisplayTool],
      'zorp' => [::Tools::SpeechTool, ::Tools::LightingTool, ::Tools::MarqeeDisplayTool]
    }.freeze

    class << self
      # Get OpenAI function schemas for a character's available tools
      def get_tools_for_character(persona)
        tool_classes = PERSONA_TOOLS[persona] || PERSONA_TOOLS['buddy']
        build_tool_schemas(tool_classes)
      end

      # Get all available tools (for admin/testing)
      def get_all_tools
        all_tool_classes = PERSONA_TOOLS.values.flatten.uniq
        build_tool_schemas(all_tool_classes)
      end

      # Build OpenAI function schemas from tool classes
      def build_tool_schemas(tool_classes)
        tools = []

        tool_classes.each do |tool_class|
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

      # All available tool classes
      ALL_TOOL_CLASSES = [
        ::Tools::SpeechTool,
        ::Tools::MarqeeDisplayTool,
        ::Tools::LightingTool,
        ::Tools::MusicTool,
        ::Tools::ErrorHandlingTool,
        ::Tools::HassMcpTool
      ].freeze

      # Discover all available tools with metadata (for admin interface)
      # Returns tool classes with their methods and parameters
      def discover_tools
        tool_classes_data = {}

        ALL_TOOL_CLASSES.each do |tool_class|
          class_name = tool_class.name.split('::').last # e.g., "LightingTool"

          # Initialize data for this tool class
          tool_classes_data[class_name] = {
            description: tool_class.respond_to?(:prompt_description) ?
                         tool_class.prompt_description :
                         "Tools provided by #{class_name}",
            category: tool_class.respond_to?(:category) ?
                      tool_class.category :
                      class_name.gsub(/Tool$/, '').downcase,
            methods: {} # This will store the methods for this class
          }

          next unless tool_class.respond_to?(:available_tools)

          tool_class.available_tools.each do |tool_name|
            # The tool_name here is the method name (e.g., 'set_light_color')
            parameters = if tool_class.respond_to?(:tool_schemas) && tool_class.tool_schemas[tool_name]
                           tool_class.tool_schemas[tool_name]
                         else
                           { 'type' => 'object', 'properties' => {} }
                         end

            tool_classes_data[class_name][:methods][tool_name] = {
              description: "#{tool_class.prompt_description} - #{tool_name}",
              parameters: parameters
            }
          end
        end

        tool_classes_data
      end

      # Execute a tool directly (for admin testing)
      def execute_tool_directly(tool_name, parameters = {}, tool_class: nil)
        ToolExecutor.execute([{
                               name: tool_name,
                               arguments: parameters,
                               id: "test_#{SecureRandom.hex(4)}",
                               tool_class: tool_class
                             }]).first
      end
    end
  end
end
