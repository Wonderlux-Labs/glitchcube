# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Tools::BaseTool do
  describe 'class methods' do
    describe '.name' do
      it 'returns snake_case version of class name', :vcr do
        expect(described_class.name).to eq('base_tool')
      end
    end

    describe '.description' do
      it 'raises NotImplementedError', :vcr do
        expect { described_class.description }.to raise_error(NotImplementedError, 'Tool must implement .description method')
      end
    end

    describe '.call' do
      it 'raises NotImplementedError', :vcr do
        expect { described_class.call }.to raise_error(NotImplementedError, 'Tool must implement .call method')
      end
    end

    describe '.parameters' do
      it 'returns empty hash by default', :vcr do
        expect(described_class.parameters).to eq({})
      end
    end

    describe '.required_parameters' do
      it 'returns empty array by default', :vcr do
        expect(described_class.required_parameters).to eq([])
      end
    end

    describe '.examples' do
      it 'returns empty array by default', :vcr do
        expect(described_class.examples).to eq([])
      end
    end

    describe '.category' do
      it 'returns general by default', :vcr do
        expect(described_class.category).to eq('general')
      end
    end
  end

  describe 'JSON parameter handling' do
    # Testing actual tool behavior through public interface
    let(:test_tool) do
      Class.new(Tools::BaseTool) do
        def self.name
          'test_tool'
        end

        def self.description
          'Test tool for JSON handling'
        end

        def self.call(params: nil, **_args)
          # This tests the actual JSON parsing behavior
          parsed = parse_json_params(params)
          format_response(true, 'Parsed successfully', parsed)
        rescue Tools::BaseTool::ValidationError => e
          format_response(false, e.message)
        end
      end
    end

    it 'handles valid JSON parameters', :vcr do
      result = test_tool.call(params: '{"action":"test","value":123}')
      expect(result).to include('✅')
      expect(result).to include('Parsed successfully')
    end

    it 'handles invalid JSON parameters', :vcr do
      result = test_tool.call(params: '{"invalid": json')
      expect(result).to include('❌')
      expect(result).to include('Invalid JSON')
    end
  end
end
