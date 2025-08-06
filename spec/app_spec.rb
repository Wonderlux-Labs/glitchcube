# frozen_string_literal: true

RSpec.describe GlitchCubeApp do
  describe 'GET /' do
    it 'returns welcome message' do
      get '/'
      expect(last_response).to be_ok
      expect(last_response.content_type).to include('application/json')

      body = JSON.parse(last_response.body)
      expect(body['message']).to eq('Welcome to Glitch Cube!')
      expect(body['status']).to eq('online')
    end
  end

  describe 'GET /health' do
    it 'returns health status' do
      get '/health'
      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['status']).to eq('healthy')
      expect(body['timestamp']).not_to be_nil
      expect(body['circuit_breakers']).to be_an(Array)
    end
  end

  describe 'POST /api/v1/test' do
    context 'with valid message' do
      it 'processes the message through Desiru' do
        post '/api/v1/test',
             { message: 'Hello Glitch Cube!' }.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body['success']).to be true
        expect(body['response']).not_to be_nil
        expect(body['timestamp']).not_to be_nil
      end
    end

    context 'with empty body' do
      it 'uses default message' do
        post '/api/v1/test',
             {}.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response).to be_ok
        body = JSON.parse(last_response.body)
        expect(body['success']).to be true
      end
    end

    context 'with invalid JSON' do
      it 'returns error' do
        post '/api/v1/test',
             'invalid json',
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(500)
        body = JSON.parse(last_response.body)
        expect(body['success']).to be false
        expect(body['error']).not_to be_nil
      end
    end
  end

  describe 'POST /api/v1/conversation' do
    it 'processes conversation with AI module' do
      post '/api/v1/conversation',
           { message: 'Test conversation' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['data']).to be_a(Hash)
      expect(body['data']['response']).not_to be_nil
      expect(body['data']['suggested_mood']).not_to be_nil
      expect(body['data']['confidence']).to be_a(Float)
    end
  end

  describe '404 handling' do
    it 'returns JSON error for unknown routes' do
      get '/unknown'
      expect(last_response.status).to eq(404)

      body = JSON.parse(last_response.body)
      expect(body['error']).to eq('Not found')
      expect(body['status']).to eq(404)
    end
  end
end
