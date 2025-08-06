# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require_relative '../../../lib/helpers/deployment_helper'

RSpec.describe 'Deploy Route' do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  describe 'POST /deploy' do
    context 'when MAC_MINI_DEPLOYMENT is true' do
      before do
        allow(GlitchCube.config.deployment).to receive(:mac_mini).and_return(true)
        # Re-register the route since it's conditional
        GlitchCubeApp.register GlitchCube::Routes::Deploy if defined?(GlitchCube::Routes::Deploy)
      end

      it 'accepts deployment webhook' do
        post '/deploy', { ref: 'refs/heads/main' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(202)
        expect(JSON.parse(last_response.body)['status']).to eq('accepted')
      end

      it 'ignores non-main branch pushes' do
        post '/deploy', { ref: 'refs/heads/feature' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response).to be_ok
        expect(JSON.parse(last_response.body)['status']).to eq('ignored')
      end

      context 'with webhook signature verification' do
        let(:webhook_secret) { 'test-secret' }
        let(:payload) { { ref: 'refs/heads/main' }.to_json }
        let(:signature) do
          'sha256=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), webhook_secret, payload)
        end

        before do
          ENV['GITHUB_WEBHOOK_SECRET'] = webhook_secret
        end

        after do
          ENV.delete('GITHUB_WEBHOOK_SECRET')
        end

        it 'accepts valid signature' do
          post '/deploy', payload, 
               'CONTENT_TYPE' => 'application/json',
               'HTTP_X_HUB_SIGNATURE_256' => signature
          expect(last_response.status).to eq(202)
        end

        it 'rejects invalid signature' do
          post '/deploy', payload, 
               'CONTENT_TYPE' => 'application/json',
               'HTTP_X_HUB_SIGNATURE_256' => 'sha256=invalid'
          expect(last_response.status).to eq(401)
        end
      end
    end

    context 'when MAC_MINI_DEPLOYMENT is false' do
      it 'route would not be registered at startup' do
        # Since routes are registered at app startup based on config,
        # we can't dynamically test this without reloading the app.
        # Instead, we'll test that the deployment helper returns false
        allow(GlitchCube.config.deployment).to receive(:mac_mini).and_return(false)
        expect(GlitchCube::Helpers::DeploymentHelper.mac_mini_deployment?).to be false
        expect(GlitchCube::Helpers::DeploymentHelper.docker_deployment?).to be true
      end
    end
  end
end