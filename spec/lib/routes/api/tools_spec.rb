# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

RSpec.describe GlitchCube::Routes::Api::Tools do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  let(:conversation_handler_service) { instance_double(Services::ConversationHandlerService) }
  let(:tool_agent) { double('tool_agent') }
  let(:ha_agent) { double('home_assistant_agent') }

  before do
    allow(Services::ConversationHandlerService).to receive(:new).and_return(conversation_handler_service)
    allow(conversation_handler_service).to receive(:tool_agent).and_return(tool_agent)
    allow(conversation_handler_service).to receive(:home_assistant_agent).and_return(ha_agent)
  end

  describe 'POST /api/v1/tool_test' do
    let(:tool_response) do
      {
        answer: 'Battery level is at 85%. System temperature is 72°F. All sensors are functioning normally.'
      }
    end

    before do
      allow(tool_agent).to receive(:call).and_return(tool_response)
    end

    it 'processes tool test requests using ReAct pattern' do
      post '/api/v1/tool_test',
           { message: 'Tell me about the battery status' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok
      expect(last_response.content_type).to include('application/json')

      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['response']).to eq('Battery level is at 85%. System temperature is 72°F. All sensors are functioning normally.')
      expect(body).to have_key('timestamp')
    end

    it 'uses default message when none provided' do
      post '/api/v1/tool_test',
           {}.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok

      expect(tool_agent).to have_received(:call).with(
        question: 'Tell me about the battery status'
      )
    end

    it 'passes custom messages to tool agent' do
      custom_message = 'What is the current temperature and humidity?'
      
      post '/api/v1/tool_test',
           { message: custom_message }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(tool_agent).to have_received(:call).with(
        question: custom_message
      )
    end

    it 'handles tool agent errors gracefully' do
      allow(tool_agent).to receive(:call).and_raise(StandardError, 'Tool execution failed')

      post '/api/v1/tool_test',
           { message: 'Test message' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(500)

      body = JSON.parse(last_response.body)
      expect(body['success']).to be false
      expect(body['error']).to eq('Tool execution failed')
      expect(body).to have_key('backtrace')
      expect(body['backtrace']).to be_an(Array)
    end

    it 'includes limited backtrace in error responses' do
      backtrace = (1..10).map { |i| "line #{i}" }
      error = StandardError.new('Test error')
      allow(error).to receive(:backtrace).and_return(backtrace)
      
      allow(tool_agent).to receive(:call).and_raise(error)

      post '/api/v1/tool_test',
           { message: 'Test' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      body = JSON.parse(last_response.body)
      expect(body['backtrace'].length).to eq(6) # Limited to first 6 lines
    end
  end

  describe 'POST /api/v1/home_assistant' do
    let(:ha_response) do
      {
        response: 'I have checked the sensors. Battery is at 85%, temperature is 72°F. I have set the light to blue at 50% brightness.'
      }
    end

    before do
      allow(ha_agent).to receive(:call).and_return(ha_response)
    end

    it 'processes Home Assistant integration requests' do
      post '/api/v1/home_assistant',
           { message: 'Check all sensors and set the light to blue' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok
      expect(last_response.content_type).to include('application/json')

      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['response']).to include('checked the sensors')
      expect(body['response']).to include('light to blue')
      expect(body).to have_key('timestamp')
    end

    it 'uses default message when none provided' do
      post '/api/v1/home_assistant',
           {}.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok

      expect(ha_agent).to have_received(:call).with(
        request: 'Check all sensors and set the light to blue'
      )
    end

    it 'handles sensor status requests' do
      sensor_message = 'What are all the current sensor readings?'
      
      post '/api/v1/home_assistant',
           { message: sensor_message }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(ha_agent).to have_received(:call).with(
        request: sensor_message
      )
    end

    it 'handles device control requests' do
      control_message = 'Turn the RGB light to red and increase brightness to 80%'
      
      post '/api/v1/home_assistant',
           { message: control_message }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(ha_agent).to have_received(:call).with(
        request: control_message
      )
    end

    it 'handles Home Assistant agent errors gracefully' do
      allow(ha_agent).to receive(:call).and_raise(StandardError, 'HA connection failed')

      post '/api/v1/home_assistant',
           { message: 'Turn on lights' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(500)

      body = JSON.parse(last_response.body)
      expect(body['success']).to be false
      expect(body['error']).to eq('HA connection failed')
      expect(body['backtrace']).to be_an(Array)
    end

    it 'can handle multiple simultaneous requests' do
      complex_message = 'Check battery level, if below 20% turn light red and speak a low battery warning, otherwise turn light green'
      
      post '/api/v1/home_assistant',
           { message: complex_message }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok
      expect(ha_agent).to have_received(:call).with(
        request: complex_message
      )
    end
  end
end