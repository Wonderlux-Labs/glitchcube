# frozen_string_literal: true

module Services
  # Executes tool calls - EXPLICIT AND SIMPLE
  class ToolExecutor
    class << self
      def execute(tool_calls, _options = {})
        tool_calls.map { |call| execute_single(call) }
      end

      private

      def execute_single(tool_call)
        tool_name = tool_call[:name] || tool_call['name']
        arguments = tool_call[:arguments] || tool_call['arguments'] || {}
        preferred_tool_class = tool_call[:tool_class] || tool_call['tool_class']

        # Find which tool class handles this method
        tool_class = if preferred_tool_class
                       find_specific_tool_class(preferred_tool_class, tool_name)
                     else
                       find_tool_class_for(tool_name)
                     end
        return error_result(tool_call, "No tool handles '#{tool_name}'") unless tool_class

        # Normalize and filter arguments to match method signature
        normalized_args = normalize_args(arguments)

        # Log tool execution with full details
        Services::Logging::SimpleLogger.info('🔧 Executing tool method',
                                             tagged: %i[tool_executor execution],
                                             tool_class: tool_class.name,
                                             tool_name: tool_name,
                                             arguments: normalized_args,
                                             arg_count: normalized_args.size,
                                             arg_keys: normalized_args.keys.join(', '))

        # Execute the tool method
        result = if tool_class.respond_to?(tool_name)
                   # Filter arguments to match method signature to prevent keyword argument errors
                   filtered_args = filter_args_for_method(tool_class, tool_name, normalized_args)

                   Services::Logging::SimpleLogger.debug('Method signature filtering',
                                                         tagged: %i[tool_executor signature],
                                                         method: "#{tool_class.name}.#{tool_name}",
                                                         original_args: normalized_args.keys,
                                                         filtered_args: filtered_args.keys)

                   tool_class.send(tool_name, **filtered_args)
                 else
                   tool_class.call(**normalized_args)
                 end

        # Log successful execution
        Services::Logging::SimpleLogger.info('✅ Tool executed successfully',
                                             tagged: %i[tool_executor success],
                                             tool_class: tool_class.name,
                                             tool_name: tool_name,
                                             result_type: result.class.name,
                                             result_preview: result.to_s[0..100])

        success_result(tool_call, result)
      rescue StandardError => e
        Services::Logging::SimpleLogger.error('❌ Tool execution failed',
                                              tagged: %i[tool_executor error],
                                              tool_class: tool_class&.name || 'Unknown',
                                              tool_name: tool_name,
                                              arguments: normalized_args,
                                              error_class: e.class.name,
                                              error_message: e.message,
                                              backtrace: e.backtrace&.first(3))
        error_result(tool_call, e.message)
      end

      # Filter arguments to only include those that the method can accept
      def filter_args_for_method(tool_class, method_name, args)
        return args unless tool_class.respond_to?(method_name)

        method_obj = tool_class.method(method_name)
        method_params = method_obj.parameters

        # Get the parameter names that the method accepts
        # [:keyreq, :name] = required keyword arg
        # [:key, :name] = optional keyword arg
        # [:keyrest, :kwargs] = **kwargs (accepts any)
        # rubocop:disable Style/HashSlice, Style/SymbolArray
        # method_params is an Array, not a Hash - slice doesn't work here
        accepted_keys = method_params.select { |param_type, _name| [:key, :keyreq].include?(param_type) }.map(&:last)
        # rubocop:enable Style/HashSlice, Style/SymbolArray

        # If method has **kwargs, accept all arguments
        has_keyrest = method_params.any? { |param_type, _name| param_type == :keyrest }
        return args if has_keyrest

        # Log which arguments are being filtered out
        rejected_keys = args.keys - accepted_keys
        if rejected_keys.any?
          Services::Logging::SimpleLogger.warn('🚫 Filtering out unknown arguments',
                                               tagged: %i[tool_executor signature_filter],
                                               method: "#{tool_class.name}.#{method_name}",
                                               accepted_params: accepted_keys,
                                               rejected_params: rejected_keys,
                                               rejected_values: args.slice(*rejected_keys))
        end

        # Otherwise, filter to only accepted keys
        args.slice(*accepted_keys)
      rescue StandardError => e
        Services::Logging::SimpleLogger.warn('Failed to filter method args, using all',
                                             tagged: %i[tool_executor signature_filter],
                                             method: "#{tool_class.name}.#{method_name}",
                                             error: e.message)
        args
      end

      def find_specific_tool_class(preferred_class_name, tool_name)
        tool_class = tool_classes.find { |tc| tc.name.split('::').last == preferred_class_name }
        return nil unless tool_class
        return nil unless tool_class.respond_to?(:available_tools)
        return nil unless tool_class.available_tools.include?(tool_name)

        tool_class
      end

      def find_tool_class_for(tool_name)
        Services::Logging::SimpleLogger.debug('🔍 Searching for tool class',
                                              tagged: %i[tool_executor discovery],
                                              tool_name: tool_name,
                                              available_classes: tool_classes.map(&:name))

        found_class = tool_classes.find do |tool_class|
          next unless tool_class.respond_to?(:available_tools)

          available = tool_class.available_tools
          Services::Logging::SimpleLogger.debug("Checking #{tool_class.name}",
                                                tagged: %i[tool_executor discovery],
                                                available_tools: available,
                                                matches: available.include?(tool_name))

          available.include?(tool_name)
        end

        if found_class
          Services::Logging::SimpleLogger.debug('✅ Found tool class',
                                                tagged: %i[tool_executor discovery],
                                                tool_name: tool_name,
                                                tool_class: found_class.name)
        else
          Services::Logging::SimpleLogger.warn('❌ No tool class found',
                                               tagged: %i[tool_executor discovery],
                                               tool_name: tool_name)
        end

        found_class
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
      @tool_classes ||= begin
        classes = [
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

        Services::Logging::SimpleLogger.info('🧰 Tool classes loaded at startup',
                                             tagged: %i[tool_executor initialization],
                                             tool_classes: classes.map(&:name),
                                             tool_count: classes.size,
                                             available_methods: classes.flat_map { |tc| tc.respond_to?(:available_tools) ? tc.available_tools : [] })

        classes
      end
    end

    # Alias for backward compatibility
    TOOL_CLASSES = method(:tool_classes)
  end
end
