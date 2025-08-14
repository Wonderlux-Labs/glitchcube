# frozen_string_literal: true

module ::Services
  module Conversation
    module Errors
      class ToolExecutionError < StandardError
        attr_reader :tool_name, :original_error

        def initialize(message, tool_name:, original_error: nil)
          super(message)
          @tool_name = tool_name
          @original_error = original_error
        end
      end
    end
  end
end
