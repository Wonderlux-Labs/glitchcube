# frozen_string_literal: true

module Services
  # Executes tool calls - EXPLICIT AND SIMPLE
  class ToolExecutor
    class << self
      def execute(tool_calls, _options = {})
        Array(tool_calls).map { |call| execute_single(call) }
      end

      private

      def execute_single(tool_call)
        tool_name = tool_call[:name] || tool_call['name']
        arguments = tool_call[:arguments] || tool_call['arguments'] || {}

        # Find which tool class handles this method
        tool_class = find_tool_class_for(tool_name)
        return error_result(tool_call, "No tool handles '#{tool_name}'") unless tool_class

        # Execute the tool method
        result = if tool_class.respond_to?(tool_name)
                   tool_class.send(tool_name, **normalize_args(arguments))
                 else
                   tool_class.call(**normalize_args(arguments))
                 end

        success_result(tool_call, result)
      rescue StandardError => e
        error_result(tool_call, e.message)
      end

      def find_tool_class_for(tool_name)
        tool_classes.find do |tool_class|
          next unless tool_class.respond_to?(:available_tools)

          tool_class.available_tools.include?(tool_name)
        end
      end

      def normalize_args(args)
        return {} unless args.is_a?(Hash)

        args.transform_keys(&:to_sym)
      end

      def success_result(tool_call, result)
        {
          tool_call_id: tool_call[:id] || tool_call['id'],
          tool_name: tool_call[:name] || tool_call['name'],
          success: true,
          result: result.to_s
        }
      end

      def error_result(tool_call, message)
        {
          tool_call_id: tool_call[:id] || tool_call['id'],
          tool_name: tool_call[:name] || tool_call['name'],
          success: false,
          error: message
        }
      end
    end

    # Lazy-loaded tool registry
    def self.tool_classes
      @tool_classes ||= [
        # Only load tool classes if they're defined
        defined?(::SpeechTool) ? ::SpeechTool : nil,
        defined?(::DisplayTool) ? ::DisplayTool : nil,
        defined?(::LightingTool) ? ::LightingTool : nil,
        defined?(::TestTool) ? ::TestTool : nil,
        defined?(::MusicTool) ? ::MusicTool : nil,
        defined?(::CameraTool) ? ::CameraTool : nil,
        defined?(::ErrorHandlingTool) ? ::ErrorHandlingTool : nil,
        defined?(::ConversationFeedbackTool) ? ::ConversationFeedbackTool : nil
      ].compact
    end

    # Alias for backward compatibility
    TOOL_CLASSES = method(:tool_classes)
  end
end
