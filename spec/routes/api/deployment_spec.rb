# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'openssl'
require_relative '../../../lib/routes/api/deployment'

RSpec.describe 'Deployment API', type: :request, :failing do
  let(:app) { GlitchCubeApp.new }
  
  # Mock GitHub webhook payload
  let(:github_payload) do
    {
      ref: 'refs/heads/main',
      after: 'abc123def456',
      repository: { full_name: 'user/glitchcube' },
      commits: [
        {
          id: 'abc123def456',
          message: 'Fix deployment webhook',
          committer: { name: 'Developer' }
        }
      ]
    }.to_json
  end
  
  let(:webhook_secret) { 'test_secret_123' }
  let(:api_key) { 'test_api_key_456' }
  
  before do
    # Mock configuration
    allow(GlitchCube.config.deployment).to receive(:github_webhook_secret).and_return(webhook_secret)
    allow(GlitchCube.config.deployment).to receive(:api_key).and_return(api_key)
    
    # Mock system calls
    allow_any_instance_of(Object).to receive(:system).and_return(true)
    allow_any_instance_of(Object).to receive(:`).and_return('main')
    
    # Mock services
    allow(Services::LoggerService).to receive(:log_api_call)
    allow(HomeAssistantClient).to receive(:new).and_return(double(states: []))
  end
  
  describe 'POST /api/v1/deploy/webhook' do
    context 'with valid GitHub webhook signature' do
      let(:signature) do
        "sha256=#{OpenSSL::HMAC.hexdigest('sha256', webhook_secret, github_payload)}"
      end
      
      it 'processes deployment successfully' do
        post '/api/v1/deploy/webhook',
             github_payload,
             { 'CONTENT_TYPE' => 'application/json',
               'HTTP_X_HUB_SIGNATURE_256' => signature }
        
        expect(last_response.status).to eq(200)
        
        response_body = JSON.parse(last_response.body)
        expect(response_body['message']).to eq('Deployment initiated successfully')
        expect(response_body['webhook_processed']).to be true
        expect(response_body['deployment']['branch']).to eq('main')
        expect(response_body['deployment']['commit_sha']).to eq('abc123def456')
      end
      
      it 'logs deployment request' do
        expect(Services::LoggerService).to receive(:log_api_call).with(
          hash_including(
            service: 'github_webhook',
            endpoint: '/deploy/webhook',
            method: 'POST'
          )
        )
        
        post '/api/v1/deploy/webhook',
             github_payload,
             { 'CONTENT_TYPE' => 'application/json',
               'HTTP_X_HUB_SIGNATURE_256' => signature }
      end
    end
    
    context 'with invalid signature' do
      it 'rejects webhook with 401' do
        post '/api/v1/deploy/webhook',
             github_payload,
             { 'CONTENT_TYPE' => 'application/json',
               'HTTP_X_HUB_SIGNATURE_256' => 'sha256=invalid_signature' }
        
        expect(last_response.status).to eq(401)
        
        response_body = JSON.parse(last_response.body)
        expect(response_body['error']).to eq('Webhook signature validation failed')
        expect(response_body['webhook_processed']).to be false
      end
    end
    
    context 'with missing signature header' do
      it 'rejects webhook with 401' do
        post '/api/v1/deploy/webhook',
             github_payload,
             { 'CONTENT_TYPE' => 'application/json' }
        
        expect(last_response.status).to eq(401)
        
        response_body = JSON.parse(last_response.body)
        expect(response_body['error']).to eq('Webhook signature validation failed')
        expect(response_body['message']).to include('Missing GitHub signature header')
      end
    end
    
    context 'with non-main branch push' do
      let(:feature_payload) do
        {
          ref: 'refs/heads/feature-branch',
          after: 'def456abc123',
          repository: { full_name: 'user/glitchcube' },
          commits: []
        }.to_json
      end
      
      let(:signature) do
        "sha256=#{OpenSSL::HMAC.hexdigest('sha256', webhook_secret, feature_payload)}"
      end
      
      it 'skips deployment for non-main branch' do
        post '/api/v1/deploy/webhook',
             feature_payload,
             { 'CONTENT_TYPE' => 'application/json',
               'HTTP_X_HUB_SIGNATURE_256' => signature }
        
        expect(last_response.status).to eq(200)
        
        response_body = JSON.parse(last_response.body)
        expect(response_body['message']).to eq('Ignoring non-main branch push')
        expect(response_body['ref']).to eq('refs/heads/feature-branch')
        expect(response_body['skipped']).to be true
      end
    end
    
    context 'with invalid JSON payload' do
      it 'returns 400 for malformed JSON' do
        post '/api/v1/deploy/webhook',
             'invalid json',
             { 'CONTENT_TYPE' => 'application/json',
               'HTTP_X_HUB_SIGNATURE_256' => 'sha256=whatever' }
        
        expect(last_response.status).to eq(400)
        
        response_body = JSON.parse(last_response.body)
        expect(response_body['error']).to eq('Invalid JSON payload')
      end
    end
    
    context 'when deployment fails' do
      it 'handles system errors gracefully' do
        signature = "sha256=#{OpenSSL::HMAC.hexdigest('sha256', webhook_secret, github_payload)}"
        
        # Mock system failure
        allow_any_instance_of(GlitchCube::Routes::Api::Deployment).to receive(:execute_deployment)
          .and_raise(StandardError, 'Deployment script failed')
        
        post '/api/v1/deploy/webhook',
             github_payload,
             { 'CONTENT_TYPE' => 'application/json',
               'HTTP_X_HUB_SIGNATURE_256' => signature }
        
        expect(last_response.status).to eq(500)
        
        response_body = JSON.parse(last_response.body)
        expect(response_body['error']).to eq('Deployment failed')
        expect(response_body['message']).to include('Deployment script failed')
      end
    end
  end
  
  describe 'POST /api/v1/deploy/manual' do
    context 'with valid API key' do
      it 'executes manual deployment' do
        post '/api/v1/deploy/manual',
             { api_key: api_key, message: 'Manual deployment test', branch: 'main' }
        
        expect(last_response.status).to eq(200)
        
        response_body = JSON.parse(last_response.body)
        expect(response_body['message']).to eq('Manual deployment completed')
        expect(response_body['deployment']['commit_message']).to eq('Manual deployment test')
        expect(response_body['deployment']['branch']).to eq('main')
      end
      
      it 'accepts API key in header' do
        post '/api/v1/deploy/manual',
             { message: 'Header auth test' },
             { 'HTTP_X_API_KEY' => api_key }
        
        expect(last_response.status).to eq(200)
      end
    end
    
    context 'with invalid API key' do
      it 'rejects with 401' do
        post '/api/v1/deploy/manual',
             { api_key: 'wrong_key', message: 'Should fail' }
        
        expect(last_response.status).to eq(401)
        
        response_body = JSON.parse(last_response.body)
        expect(response_body['error']).to eq('Invalid API key')
      end
    end
    
    context 'with missing API key' do
      it 'rejects with 401' do
        post '/api/v1/deploy/manual',
             { message: 'Should fail' }
        
        expect(last_response.status).to eq(401)
      end
    end
  end
  
  describe 'GET /api/v1/deploy/status' do
    before do
      allow_any_instance_of(Object).to receive(:`).with('git rev-parse --abbrev-ref HEAD 2>/dev/null').and_return('main')
      allow_any_instance_of(Object).to receive(:`).with('git rev-parse HEAD 2>/dev/null').and_return('abc123def456789')
      allow_any_instance_of(Object).to receive(:`).with('git log -1 --pretty=%B 2>/dev/null').and_return('Latest commit message')
      allow_any_instance_of(Object).to receive(:`).with('git rev-list HEAD..origin/main --count 2>/dev/null').and_return('0')
    end
    
    it 'returns deployment status information' do
      get '/api/v1/deploy/status'
      
      expect(last_response.status).to eq(200)
      
      response_body = JSON.parse(last_response.body)
      expect(response_body['current_branch']).to eq('main')
      expect(response_body['current_commit']).to eq('abc123d')
      expect(response_body['last_commit_message']).to eq('Latest commit message')
      expect(response_body['commits_behind']).to eq(0)
      expect(response_body['needs_update']).to be false
      expect(response_body).to have_key('home_assistant_status')
      expect(response_body).to have_key('last_check')
    end
    
    it 'indicates when updates are needed' do
      allow_any_instance_of(Object).to receive(:`).with('git rev-list HEAD..origin/main --count 2>/dev/null').and_return('3')
      
      get '/api/v1/deploy/status'
      
      expect(last_response.status).to eq(200)
      
      response_body = JSON.parse(last_response.body)
      expect(response_body['commits_behind']).to eq(3)
      expect(response_body['needs_update']).to be true
    end
  end
  
  describe 'deployment execution' do
    let(:deployment_info) do
      {
        repository: 'test/repo',
        branch: 'main',
        commit_sha: 'abc123',
        commit_message: 'Test commit',
        committer: 'Test User'
      }
    end
    
    before do
      # Stub system calls to avoid actual execution during tests
      allow_any_instance_of(Object).to receive(:system).and_call_original
      allow_any_instance_of(Object).to receive(:system).with('git pull origin main').and_return(true)
      allow_any_instance_of(Object).to receive(:system).with('bundle exec rake config:push').and_return(true)
      allow_any_instance_of(Object).to receive(:system).with('ssh root@glitch.local "ha core restart"').and_return(true)
    end
    
    it 'executes all deployment steps in order' do
      expect_any_instance_of(Object).to receive(:system).with('git pull origin main').and_return(true).ordered
      expect_any_instance_of(Object).to receive(:system).with('bundle exec rake config:push').and_return(true).ordered
      expect_any_instance_of(Object).to receive(:system).with('ssh root@glitch.local "ha core restart"').and_return(true).ordered
      
      result = GlitchCube::Routes::Api::Deployment.send(:execute_deployment, deployment_info)
      
      expect(result).to be_an(Array)
      expect(result.length).to be >= 3
      expect(result.map { |r| r[:success] }).to all(be_truthy)
    end
    
    it 'handles git pull failure' do
      expect_any_instance_of(Object).to receive(:system).with('git pull origin main').and_return(false)
      
      result = GlitchCube::Routes::Api::Deployment.send(:execute_deployment, deployment_info)
      
      git_result = result.find { |r| r[:step] == 'git_pull' }
      expect(git_result[:success]).to be false
      expect(git_result[:message]).to eq('Git pull failed')
    end
    
    it 'skips HA restart when config sync fails' do
      expect_any_instance_of(Object).to receive(:system).with('git pull origin main').and_return(true)
      expect_any_instance_of(Object).to receive(:system).with('bundle exec rake config:push').and_return(false)
      expect_any_instance_of(Object).not_to receive(:system).with('ssh root@glitch.local "ha core restart"')
      
      result = GlitchCube::Routes::Api::Deployment.send(:execute_deployment, deployment_info)
      
      ha_restart_result = result.find { |r| r[:step] == 'ha_restart' }
      expect(ha_restart_result[:success]).to be false
      expect(ha_restart_result[:message]).to eq('Skipped due to config sync failure')
    end
  end
end