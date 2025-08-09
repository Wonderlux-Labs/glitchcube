# frozen_string_literal: true

require_relative '../tools/speech_tool'
require_relative '../tools/display_tool'
require_relative '../tools/lighting_tool'

module Services
  # Simple tool registry service - just builds LLM schemas from tool metadata
  class ToolRegistryService
    # Persona to tool mapping
    PERSONA_TOOLS = {
      'buddy' => [SpeechTool, DisplayTool],
      'jax' => [SpeechTool, LightingTool],
      'lomi' => [SpeechTool, DisplayTool],
      'zorp' => [SpeechTool, LightingTool, DisplayTool]
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

      # Execute a tool directly (for admin testing)
      def execute_tool_directly(tool_name, parameters = {})
        Services::ToolExecutor.execute([{
                                         name: tool_name,
                                         arguments: parameters,
                                         id: "test_#{SecureRandom.hex(4)}"
                                       }]).first
      end
    end
  end
end
