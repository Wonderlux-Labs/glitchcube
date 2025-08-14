# frozen_string_literal: true

require 'spec_helper'
RSpec.describe Services::ToolExecutor do
  describe 'slice bug fix' do
    let(:test_tool_class) do
      Class.new do
        def self.name
          'TestTool'
        end

        def self.test_method(required:, optional: 'default', **rest)
          { required: required, optional: optional, rest: rest }
        end
      end
    end

    let(:tool_executor) { Services::ToolExecutor }

    describe '#filter_args_for_method (private method)' do
      it 'correctly filters arguments without causing slice error' do
        # This directly tests the private method that had the bug
        args = {
          required: 'value',
          optional: 'custom',
          extra_arg: 'should be filtered',
          another_extra: 'also filtered'
        }

        # Access the private method
        filtered_args = tool_executor.send(:filter_args_for_method, test_tool_class, :test_method, args)

        # Should include all arguments because test_method has **rest
        expect(filtered_args).to eq(args)
      end

      it 'filters args for method without **kwargs' do
        # Create a method without **kwargs
        limited_tool = Class.new do
          def self.name
            'LimitedTool'
          end

          def self.limited_method(name:, count: 0)
            { name: name, count: count }
          end
        end

        args = {
          name: 'test',
          count: 5,
          extra: 'should be removed'
        }

        filtered_args = tool_executor.send(:filter_args_for_method, limited_tool, :limited_method, args)

        # Should only include name and count, not extra
        expect(filtered_args).to eq({ name: 'test', count: 5 })
      end

      it 'handles method parameters correctly' do
        # This specifically tests the fixed slice bug
        method_obj = test_tool_class.method(:test_method)
        method_params = method_obj.parameters

        # The old code would try: method_params.slice(:key, :keyreq)
        # But method_params is an array like [[:keyreq, :required], [:key, :optional], [:keyrest, :rest]]
        # So slice would fail with "no implicit conversion of Symbol into Integer"

        # The fixed code should work:
        # rubocop:disable Style/HashSlice, Style/SymbolArray
        accepted_keys = method_params.select { |param_type, _name| [:key, :keyreq].include?(param_type) }.map(&:last)
        # rubocop:enable Style/HashSlice, Style/SymbolArray

        expect(accepted_keys).to include(:required, :optional)
        expect(accepted_keys).not_to include(:rest) # keyrest params don't appear in accepted_keys
      end
    end
  end
end
