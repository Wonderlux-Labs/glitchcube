# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Home Assistant API endpoint' do
  def app
    GlitchCubeApp
  end
  describe 'POST /api/v1/home_assistant' do
    context 'with mock Home Assistant' do
      before do
        # Enable mock HA for tests
        ENV['MOCK_HOME_ASSISTANT'] = 'true'
      end

      after do
        ENV['MOCK_HOME_ASSISTANT'] = nil
      end

      it 'can check sensor status' do
        VCR.use_cassette('home_assistant_check_sensors') do
          post '/api/v1/home_assistant',
               { message: 'What are the current sensor readings?' }.to_json,
               { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response.status).to eq(200)

          body = JSON.parse(last_response.body)
          expect(body['success']).to be true
          expect(body['response']).to be_a(String)
          expect(body['response']).to include('Battery Level')
          expect(body['response']).to include('Temperature')
        end
      end

      it 'can control lights' do
        VCR.use_cassette('home_assistant_control_lights') do
          post '/api/v1/home_assistant',
               { message: 'Turn the light blue at 50% brightness' }.to_json,
               { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response.status).to eq(200)

          body = JSON.parse(last_response.body)
          expect(body['success']).to be true
          expect(body['response']).to be_a(String)
          expect(body['response']).to match(/light|brightness|color|blue/i)
        end
      end

      it 'can speak messages' do
        VCR.use_cassette('home_assistant_speak') do
          post '/api/v1/home_assistant',
               { message: 'Say hello to our visitors' }.to_json,
               { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response.status).to eq(200)

          body = JSON.parse(last_response.body)
          expect(body['success']).to be true
          expect(body['response']).to be_a(String)
          expect(body['response']).to match(/speak|hello|visitors/i)
        end
      end

      it 'can combine multiple actions' do
        VCR.use_cassette('home_assistant_multiple_actions') do
          post '/api/v1/home_assistant',
               { message: 'Check the battery level and if it\'s below 20%, turn the light red' }.to_json,
               { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response.status).to eq(200)

          body = JSON.parse(last_response.body)
          expect(body['success']).to be true
          expect(body['response']).to be_a(String)
          # Should mention battery and potentially light control
          expect(body['response']).to match(/battery/i)
        end
      end

      it 'handles errors gracefully' do
        VCR.use_cassette('home_assistant_error_handling') do
          # Temporarily break the HA configuration
          original_url = ENV.fetch('HOME_ASSISTANT_URL', nil)
          ENV.delete('HOME_ASSISTANT_URL')

          post '/api/v1/home_assistant',
               { message: 'Turn on the lights' }.to_json,
               { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response.status).to eq(200)

          body = JSON.parse(last_response.body)
          expect(body['success']).to be true
          # Should still get a response even if HA is not configured
          expect(body['response']).to be_a(String)

          # Restore configuration
          ENV['HOME_ASSISTANT_URL'] = original_url if original_url
        end
      end
    end
  end
end
