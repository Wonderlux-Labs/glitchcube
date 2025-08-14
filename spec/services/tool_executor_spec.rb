# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/tool_executor'

RSpec.describe Services::ToolExecutor do
  describe '.execute' do
    context 'with argument filtering' do
      # Create a test tool class
      let(:test_tool_class) do
        Class.new do
          def self.name
            'TestTool'
          end

          def self.test_method(required_param:, optional_param: nil)
            { required: required_param, optional: optional_param }
          end

          def self.method_with_kwargs(name:, **kwargs)
            { name: name, extras: kwargs }
          end

          def self.mixed_params(required:, optional: 'default', **rest)
            { required: required, optional: optional, rest: rest }
          end
        end
      end

      before do
        # Mock the internal method that finds tool classes
        allow(Services::ToolExecutor).to receive(:find_tool_class_for).and_return(test_tool_class)
        allow(Services::Logging::SimpleLogger).to receive(:info)
        allow(Services::Logging::SimpleLogger).to receive(:warn)
      end

      it 'filters arguments to match method signature' do
        tool_call = {
          name: 'test_method',
          arguments: {
            required_param: 'value1',
            optional_param: 'value2',
            extra_param: 'should be filtered out'
          }
        }

        result = Services::ToolExecutor.execute([tool_call])

        expect(result.first).to include(
          success: true,
          tool_name: 'test_method'
        )
        # The actual return value is stringified in the result field
        expect(result.first[:result]).to include('value1')
        expect(result.first[:result]).to include('value2')
      end

      it 'accepts all arguments when method has **kwargs' do
        tool_call = {
          name: 'method_with_kwargs',
          arguments: {
            name: 'test',
            extra1: 'value1',
            extra2: 'value2'
          }
        }

        result = Services::ToolExecutor.execute([tool_call])

        expect(result.first).to include(
          success: true,
          tool_name: 'method_with_kwargs'
        )
        expect(result.first[:result]).to include('test')
        expect(result.first[:result]).to include('value1')
        expect(result.first[:result]).to include('value2')
      end

      it 'handles mixed parameter types correctly' do
        tool_call = {
          name: 'mixed_params',
          arguments: {
            required: 'required_value',
            optional: 'optional_value',
            extra_key: 'extra_value',
            another_extra: 'another_value'
          }
        }

        result = Services::ToolExecutor.execute([tool_call])

        expect(result.first).to include(
          success: true,
          tool_name: 'mixed_params'
        )
        expect(result.first[:result]).to include('required_value')
        expect(result.first[:result]).to include('optional_value')
        expect(result.first[:result]).to include('extra_value')
      end

      it 'handles missing required parameters gracefully' do
        tool_call = {
          name: 'test_method',
          arguments: {
            optional_param: 'value'
            # missing required_param
          }
        }

        result = Services::ToolExecutor.execute([tool_call])

        # Should return error result
        expect(result.first).to include(:error)
        expect(result.first[:error]).to include('required_param')
      end

      it 'works with no arguments' do
        # Define a no-arg method on the test class
        def test_tool_class.no_arg_method
          { success: true }
        end

        tool_call = {
          name: 'no_arg_method',
          arguments: {}
        }

        result = Services::ToolExecutor.execute([tool_call])

        expect(result.first).to include(success: true, tool_name: 'no_arg_method')
      end

      it 'handles array of tool calls' do
        tool_calls = [
          { name: 'test_method', arguments: { required_param: 'value1' } },
          { name: 'method_with_kwargs', arguments: { name: 'test2', extra: 'data' } }
        ]

        results = Services::ToolExecutor.execute(tool_calls)

        expect(results.length).to eq(2)
        expect(results[0]).to include(success: true, tool_name: 'test_method')
        expect(results[1]).to include(success: true, tool_name: 'method_with_kwargs')
      end
    end

    context 'error handling' do
      it 'returns error result for unknown tool' do
        allow(Services::ToolExecutor).to receive(:find_tool_class_for).and_return(nil)

        tool_call = { name: 'unknown_tool', arguments: {} }
        result = Services::ToolExecutor.execute([tool_call])

        expect(result.first).to include(:error)
        expect(result.first[:error]).to include("No tool handles 'unknown_tool'")
      end

      it 'handles exceptions during tool execution' do
        error_tool = Class.new do
          def self.name
            'ErrorTool'
          end

          def self.failing_method
            raise StandardError, 'Tool execution failed'
          end
        end

        allow(Services::ToolExecutor).to receive(:find_tool_class_for).and_return(error_tool)
        allow(Services::Logging::SimpleLogger).to receive(:error)

        tool_call = { name: 'failing_method', arguments: {} }
        result = Services::ToolExecutor.execute([tool_call])

        expect(result.first).to include(:error)
        expect(result.first[:error]).to include('Tool execution failed')
      end
    end
  end
end
