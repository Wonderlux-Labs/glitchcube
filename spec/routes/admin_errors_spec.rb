# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin Errors Page' do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  describe 'GET /admin/errors' do
    context 'when no errors are tracked' do
      before do
        # Clear any existing error keys in Redis

        if defined?(Redis)
          redis = Redis.new(url: GlitchCube.config.redis_url)
          redis.keys('glitchcube:error_count:*').each { |key| redis.del(key) }
          redis.keys('glitchcube:fixed_errors:*').each { |key| redis.del(key) }
        end
      rescue Redis::CannotConnectError
        # Redis not available, that's ok for test
      end

      it 'returns 200 and renders the errors page' do
        get '/admin/errors'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Error Tracking')
        expect(last_response.body).to include('Self-Healing')
      end

      it 'shows the current self-healing mode' do
        get '/admin/errors'
        mode = GlitchCube.config.self_healing_mode
        expect(last_response.body).to include("MODE: #{mode}")
      end

      it 'displays no errors message when empty' do
        get '/admin/errors'
        expect(last_response.body).to include('No errors tracked yet')
      end
    end

    context 'when errors are tracked in Redis' do
      let(:redis) { Redis.new(url: GlitchCube.config.redis_url) }
      let(:error_key) { 'glitchcube:error_count:abc123def456' }

      before do
        skip 'Redis not available' unless redis_available?

        # Track a sample error
        redis.set(error_key, 5)
        redis.expire(error_key, 3600)
      end

      after do
        redis.del(error_key) if redis_available?
      end

      it 'displays tracked errors from Redis' do
        get '/admin/errors'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('abc123')
        expect(last_response.body).to include('5 times')
      end
    end

    context 'when proposed fixes exist in log files' do
      let(:log_dir) { 'log/proposed_fixes' }
      let(:log_file) { "#{log_dir}/test_proposed_fixes.jsonl" }
      let(:fix_data) do
        {
          timestamp: Time.now.iso8601,
          error: {
            class: 'NoMethodError',
            message: "undefined method 'speak' for nil:NilClass",
            occurrences: 3
          },
          context: {
            service: 'TTSService',
            file: 'lib/services/tts_service.rb',
            line: 42
          },
          analysis: {
            critical: true,
            confidence: 0.92,
            reason: 'Nil client causing service failure'
          },
          proposed_fix: {
            description: 'Added nil check before method call',
            files_modified: ['lib/services/tts_service.rb'],
            branch: 'auto-fix/20250106_120000_nil_check'
          },
          confidence: 0.92
        }
      end

      before do
        FileUtils.mkdir_p(log_dir)
        File.open(log_file, 'w') { |f| f.puts JSON.generate(fix_data) }
      end

      after do
        FileUtils.rm_f(log_file)
      end

      it 'displays proposed fixes from log files' do
        get '/admin/errors'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('NoMethodError')
        expect(last_response.body).to include("undefined method 'speak'")
        expect(last_response.body).to include('TTSService')
      end

      it 'shows fix details when available' do
        get '/admin/errors'
        expect(last_response.body).to include('Proposed Fix')
        expect(last_response.body).to include('Added nil check')
        expect(last_response.body).to include('92%') # confidence
      end

      it 'displays the branch name for fixes' do
        get '/admin/errors'
        expect(last_response.body).to include('auto-fix/20250106')
      end
    end

    context 'when Redis is not available' do
      before do
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)
      end

      it 'gracefully handles Redis connection errors' do
        get '/admin/errors'
        expect(last_response.status).to eq(200)
        # Should still work and check log files
        expect(last_response.body).to include('Error Tracking')
      end
    end

    context 'with malformed log entries' do
      let(:log_dir) { 'log/proposed_fixes' }
      let(:log_file) { "#{log_dir}/malformed.jsonl" }

      before do
        FileUtils.mkdir_p(log_dir)
        File.open(log_file, 'w') do |f|
          f.puts 'not valid json'
          f.puts '{"partial": "json'
          f.puts JSON.generate({ valid: 'but incomplete data' })
        end
      end

      after do
        FileUtils.rm_f(log_file)
      end

      it 'handles malformed JSON gracefully' do
        get '/admin/errors'
        expect(last_response.status).to eq(200)
        # Should not crash, might show parse errors if in dev mode
      end
    end

    context 'DRY_RUN vs YOLO mode display' do
      it 'shows DRY_RUN mode indicator when configured' do
        allow(GlitchCube.config).to receive(:self_healing_mode).and_return('DRY_RUN')
        get '/admin/errors'
        expect(last_response.body).to include('MODE: DRY_RUN')
      end

      it 'shows YOLO mode indicator when configured' do
        allow(GlitchCube.config).to receive_messages(self_healing_mode: 'YOLO', self_healing_yolo?: true)
        get '/admin/errors'
        expect(last_response.body).to include('MODE: YOLO')
      end
    end
  end

  private

  def redis_available?
    Redis.new(url: GlitchCube.config.redis_url).ping == 'PONG'
  rescue StandardError
    false
  end
end
