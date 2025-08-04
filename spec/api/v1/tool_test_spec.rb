# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'POST /api/v1/tool_test' do
  let(:valid_headers) { { 'CONTENT_TYPE' => 'application/json' } }

  describe 'with tool-triggering message', :vcr do
    it 'uses Desiru ReAct module to call test_tool for battery information' do
      request_body = { message: 'What is the current battery status?' }.to_json

      post '/api/v1/tool_test', request_body, valid_headers

      expect(last_response.status).to eq(200)

      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true
      expect(response_data['response']).to be_a(String)
      expect(response_data['timestamp']).to be_a(String)

      # The ReAct module should have used the tool and included battery info in response
      expect(response_data['response'].downcase).to match(/battery|power|charge|87%/)
    end

    it 'uses Desiru ReAct module for sensor information' do
      request_body = { message: 'What are the current sensor readings? Please check all sensors.' }.to_json

      post '/api/v1/tool_test', request_body, valid_headers

      expect(last_response.status).to eq(200)

      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true

      # Should mention sensor data in response
      expect(response_data['response'].downcase).to match(/sensor|temperature|humidity|22°c|45%/)
    end

    it 'uses Desiru ReAct module for location information' do
      request_body = { message: 'Where are you currently located? I need your exact location.' }.to_json

      post '/api/v1/tool_test', request_body, valid_headers

      expect(last_response.status).to eq(200)

      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true

      # Should mention location in response
      expect(response_data['response'].downcase).to match(/location|gallery|art gallery|coordinates/)
    end

    it 'uses Desiru ReAct module with all system info request' do
      request_body = { message: 'Give me all system information including battery, sensors, and location.' }.to_json

      post '/api/v1/tool_test', request_body, valid_headers

      expect(last_response.status).to eq(200)

      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true

      # Should have comprehensive info
      response = response_data['response'].downcase
      expect(response).to match(/battery|power/)
      expect(response).to match(/sensor|temperature/)
      expect(response).to match(/location|gallery/)
    end
  end

  describe 'with non-tool message', :vcr do
    it 'responds without necessarily using tools for general conversation' do
      request_body = { message: 'Hello, tell me about yourself as an art installation.' }.to_json

      post '/api/v1/tool_test', request_body, valid_headers

      expect(last_response.status).to eq(200)

      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true
      expect(response_data['response']).to be_a(String)
      # Should talk about being an art installation
      expect(response_data['response'].downcase).to match(/art|installation|creative|interactive/)
    end
  end

  describe 'with missing message', :vcr do
    it 'uses default message and attempts to get battery status' do
      request_body = {}.to_json

      post '/api/v1/tool_test', request_body, valid_headers

      expect(last_response.status).to eq(200)

      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true
      # Default message asks about battery
      expect(response_data['response'].downcase).to match(/battery|power|charge/)
    end
  end

  describe 'error handling' do
    it 'returns error for invalid JSON' do
      post '/api/v1/tool_test', 'invalid json', valid_headers

      expect(last_response.status).to eq(500)

      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be false
      expect(response_data['error']).to match(/unexpected (token|character)/)
    end

    context 'with invalid API key' do
      around do |example|
        original_key = ENV.fetch('OPENROUTER_API_KEY', nil)
        ENV['OPENROUTER_API_KEY'] = 'invalid-key-test'

        # Force reload to pick up new env
        Object.send(:remove_const, :GlitchCubeApp) if defined?(GlitchCubeApp)
        load File.expand_path('../../../app.rb', __dir__)

        example.run

        # Restore
        ENV['OPENROUTER_API_KEY'] = original_key
        Object.send(:remove_const, :GlitchCubeApp) if defined?(GlitchCubeApp)
        load File.expand_path('../../../app.rb', __dir__)
      end

      it 'handles API authentication errors gracefully' do
        request_body = { message: 'Test message' }.to_json
        post '/api/v1/tool_test', request_body, valid_headers

        expect(last_response.status).to eq(500)

        response_data = JSON.parse(last_response.body)
        expect(response_data['success']).to be false
        expect(response_data['error']).to be_a(String)
      end
    end
  end
end
