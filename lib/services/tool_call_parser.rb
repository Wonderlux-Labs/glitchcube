# frozen_string_literal: true

require 'json'

module Services
  # Parses tool calls from LLM responses and formats them for execution
  class ToolCallParser
    class ParseError < StandardError; end

    class << self
      # Parse tool calls from an LLMResponse object
      #
      # @param llm_response [Services::LLMResponse] The response from LLM
      # @return [Array<Hash>] Array of parsed tool calls ready for execution
      def parse(llm_response)
        return [] unless llm_response.has_tool_calls?

        tool_calls = llm_response.tool_calls
        parsed_calls = []

        tool_calls.each do |tool_call|
          parsed_call = parse_single_tool_call(tool_call)
          parsed_calls << parsed_call if parsed_call
        end

        parsed_calls
      end

      # Parse a single tool call
      #
      # @param tool_call [Hash] A single tool call from the LLM
      # @return [Hash, nil] Parsed tool call or nil if invalid
      def parse_single_tool_call(tool_call)
        return nil unless tool_call.is_a?(Hash)

        function = tool_call[:function] || tool_call['function']
        return nil unless function

        {
          id: tool_call[:id] || tool_call['id'] || generate_tool_id,
          type: tool_call[:type] || tool_call['type'] || 'function',
          name: extract_function_name(function),
          arguments: parse_arguments(function)
        }
      rescue StandardError => e
        Rails.logger.warn "Failed to parse tool call: #{e.message}" if defined?(Rails)
        nil
      end

      # Extract function name from function data
      #
      # @param function [Hash] Function data from tool call
      # @return [String] The function name
      def extract_function_name(function)
        name = function[:name] || function['name']
        raise ParseError, 'Tool call missing function name' unless name

        name.to_s
      end

      # Parse arguments from function data
      #
      # @param function [Hash] Function data from tool call
      # @return [Hash] Parsed arguments
      def parse_arguments(function)
        args = function[:arguments] || function['arguments']

        # Handle different argument formats
        case args
        when Hash
          # Already a hash, use as-is
          args
        when String
          # Try to parse as JSON
          parse_json_arguments(args)
        when NilClass
          # No arguments
          {}
        else
          # Convert to string and try to parse
          parse_json_arguments(args.to_s)
        end
      end

      # Parse JSON string arguments
      #
      # @param args_string [String] JSON string of arguments
      # @return [Hash] Parsed arguments
      def parse_json_arguments(args_string)
        return {} if args_string.nil? || args_string.strip.empty?

        parsed = JSON.parse(args_string)
        # Convert to symbol keys for consistency
        symbolize_keys(parsed)
      rescue JSON::ParserError => e
        Rails.logger.warn "Failed to parse tool arguments as JSON: #{e.message}" if defined?(Rails)
        # Try to extract key-value pairs as fallback
        extract_fallback_arguments(args_string)
      end

      # Recursively symbolize hash keys
      #
      # @param hash [Hash] Hash to symbolize
      # @return [Hash] Hash with symbol keys
      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)
        
        hash.transform_keys(&:to_sym).transform_values do |value|
          value.is_a?(Hash) ? symbolize_keys(value) : value
        end
      end

      # Extract arguments using fallback pattern matching
      #
      # @param args_string [String] Arguments string that failed JSON parsing
      # @return [Hash] Extracted arguments
      def extract_fallback_arguments(args_string)
        # Look for patterns like key: "value" or key: value
        args = {}
        
        # Match patterns like: action: "get_sensors", params: "{}"
        args_string.scan(/(\w+):\s*"([^"]*)"/).each do |key, value|
          args[key.to_sym] = value
        end

        # Also match unquoted values
        args_string.scan(/(\w+):\s*([^,\s}]+)/).each do |key, value|
          args[key.to_sym] = value unless args.key?(key.to_sym)
        end

        args
      end

      # Generate a unique tool call ID
      #
      # @return [String] Generated ID
      def generate_tool_id
        "tool_#{SecureRandom.hex(8)}"
      end

      # Check if a tool name is available for execution
      #
      # @param tool_name [String] Name of the tool
      # @return [Boolean] True if tool is available
      def tool_available?(tool_name)
        # Check if tool class exists
        tool_class = find_tool_class(tool_name)
        !tool_class.nil?
      end

      # Find the tool class by name
      #
      # @param tool_name [String] Name of the tool
      # @return [Class, nil] The tool class or nil
      def find_tool_class(tool_name)
        # Try to find tool class
        # Convention: tool_name -> ToolNameTool
        class_name = "#{tool_name.split('_').map(&:capitalize).join}Tool"
        
        # Try to constantize
        if Object.const_defined?(class_name)
          Object.const_get(class_name)
        else
          # Try with explicit namespace
          namespaced_name = "Tools::#{class_name}"
          Object.const_get(namespaced_name) if Object.const_defined?(namespaced_name)
        end
      rescue NameError
        nil
      end

      # Format tool calls for logging
      #
      # @param tool_calls [Array<Hash>] Array of parsed tool calls
      # @return [String] Formatted string for logging
      def format_for_logging(tool_calls)
        return 'No tool calls' if tool_calls.empty?

        tool_calls.map do |call|
          "#{call[:name]}(#{call[:arguments].inspect})"
        end.join(', ')
      end
    end
  end
end