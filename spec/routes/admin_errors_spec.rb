# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin Errors Page' do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  describe 'GET /admin/errors' do
    it 'always renders the page successfully' do
      get '/admin/errors'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('Error Tracking')
      expect(last_response.body).to include('Self-Healing')
    end

    it 'displays current self-healing mode' do
      get '/admin/errors'
      mode = GlitchCube.config.self_healing_mode
      expect(last_response.body).to include("MODE: #{mode}")
    end

    context 'UI resilience with data' do
      it 'displays no errors message when no errors exist' do
        get '/admin/errors'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('No errors tracked yet')
        expect(last_response.body).to include('running smoothly')
      end
    end

    context 'when service error handling fails' do
      before do
        allow(Services::ErrorHandlingLLM).to receive(:new).and_raise(StandardError, 'Service unavailable')
      end

      it 'gracefully handles service errors and shows fallback UI' do
        get '/admin/errors'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Error Tracking')
        # UI should still render even when error service fails
      end
    end

    context 'different self-healing modes' do
      it 'shows DRY_RUN mode indicator' do
        allow(GlitchCube.config).to receive(:self_healing_mode).and_return('DRY_RUN')
        get '/admin/errors'
        expect(last_response.body).to include('MODE: DRY_RUN')
      end

      it 'shows YOLO mode indicator' do
        allow(GlitchCube.config).to receive(:self_healing_mode).and_return('YOLO')
        get '/admin/errors'
        expect(last_response.body).to include('MODE: YOLO')
      end

      it 'shows OFF mode when disabled' do
        allow(GlitchCube.config).to receive(:self_healing_mode).and_return('OFF')
        get '/admin/errors'
        expect(last_response.body).to include('MODE: OFF')
      end
    end
  end
end
