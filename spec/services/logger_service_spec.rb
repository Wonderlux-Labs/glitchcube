# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tempfile'

RSpec.describe Services::LoggerService do
  let(:temp_dir) { Dir.mktmpdir }
  let(:log_dir) { File.join(temp_dir, 'logs') }

  before do
    # Clear any existing logger instances
    described_class.instance_variables.each do |var|
      described_class.remove_instance_variable(var) if described_class.instance_variable_defined?(var)
    end

    # Mock the log directory to use our temp directory
    allow(described_class).to receive(:log_directory).and_return(log_dir)
    
    # Ensure test log directory exists
    FileUtils.mkdir_p(log_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '.setup_loggers' do
    it 'creates log directory if it does not exist' do
      FileUtils.rm_rf(log_dir)
      expect(Dir.exist?(log_dir)).to be false

      described_class.setup_loggers

      expect(Dir.exist?(log_dir)).to be true
    end

    it 'creates all required log files' do
      described_class.setup_loggers

      log_files = Dir.glob(File.join(log_dir, '*'))
      expect(log_files).to include(
        File.join(log_dir, 'general.log'),
        File.join(log_dir, 'interactions.log'),
        File.join(log_dir, 'api_calls.log'),
        File.join(log_dir, 'tts.log')
      )
    end
  end

  describe '.log_interaction' do
    before { described_class.setup_loggers }

    let(:interaction_data) do
      {
        user_message: "Hello, Glitch Cube!",
        ai_response: "Hello there! Ready to create some art?",
        mood: "playful",
        confidence: 0.95,
        session_id: "test_session_001",
        context: { test_mode: true }
      }
    end

    it 'logs interaction to interactions.log with proper formatting' do
      described_class.log_interaction(**interaction_data)

      interactions_content = File.read(File.join(log_dir, 'interactions.log'))
      
      expect(interactions_content).to include("👤 USER: Hello, Glitch Cube!")
      expect(interactions_content).to include("🎲 GLITCH CUBE: Hello there! Ready to create some art?")
      expect(interactions_content).to include("Session: test_session_001")
      expect(interactions_content).to include("Mood: playful")
      expect(interactions_content).to include("Confidence: 95%")
    end

    it 'logs interaction to general.log as JSON' do
      described_class.general # Initialize general logger
      
      described_class.log_interaction(**interaction_data)

      general_content = File.read(File.join(log_dir, 'general.log'))
      expect(general_content).to include("INTERACTION:")
      expect(general_content).to include(interaction_data[:user_message])
      expect(general_content).to include(interaction_data[:ai_response])
    end
  end

  describe '.log_api_call' do
    before { described_class.setup_loggers }

    let(:api_data) do
      {
        service: 'home_assistant',
        endpoint: '/api/services/tts/speak',
        method: 'POST',
        status: 200,
        duration: 1250
      }
    end

    it 'logs successful API call with success emoji' do
      described_class.log_api_call(**api_data)

      api_content = File.read(File.join(log_dir, 'api_calls.log'))
      expect(api_content).to include("✅ HOME_ASSISTANT POST /api/services/tts/speak 200 (1250ms)")
    end

    it 'logs failed API call with error emoji' do
      described_class.log_api_call(
        service: 'home_assistant',
        endpoint: '/api/test',
        method: 'GET',
        status: 500,
        duration: 500,
        error: 'Internal Server Error'
      )

      api_content = File.read(File.join(log_dir, 'api_calls.log'))
      expect(api_content).to include("❌ HOME_ASSISTANT GET /api/test 500 (500ms) - Internal Server Error")
    end

    it 'tracks errors when present' do
      allow(described_class).to receive(:track_error)

      described_class.log_api_call(
        service: 'test_service',
        endpoint: '/test',
        method: 'GET',
        error: 'Connection failed'
      )

      expect(described_class).to have_received(:track_error).with('test_service', 'Connection failed')
    end
  end

  describe '.log_tts' do
    before { described_class.setup_loggers }

    it 'logs successful TTS with speaker emoji' do
      described_class.log_tts(
        message: 'Hello world!',
        success: true,
        duration: 2000
      )

      tts_content = File.read(File.join(log_dir, 'tts.log'))
      expect(tts_content).to include('🔊 "Hello world!"')
    end

    it 'logs failed TTS with mute emoji and error' do
      described_class.log_tts(
        message: 'Hello world!',
        success: false,
        duration: 100,
        error: 'TTS service unavailable'
      )

      tts_content = File.read(File.join(log_dir, 'tts.log'))
      expect(tts_content).to include('🔇 "Hello world!" - TTS service unavailable')
    end

    it 'truncates long messages' do
      long_message = 'a' * 150
      
      described_class.log_tts(
        message: long_message,
        success: true
      )

      tts_content = File.read(File.join(log_dir, 'tts.log'))
      expect(tts_content).to include('...')
      expect(tts_content).not_to include('a' * 150)
    end
  end

  describe '.log_circuit_breaker' do
    before { described_class.setup_loggers }

    it 'logs circuit breaker state changes with appropriate emoji' do
      expect { described_class.log_circuit_breaker(name: 'test', state: :open) }
        .to output(/🔴.*test.*OPEN/).to_stdout

      expect { described_class.log_circuit_breaker(name: 'test', state: :closed) }
        .to output(/🟢.*test.*CLOSED/).to_stdout

      expect { described_class.log_circuit_breaker(name: 'test', state: :half_open) }
        .to output(/🟡.*test.*HALF_OPEN/).to_stdout
    end

    it 'includes reason when provided' do
      expect { described_class.log_circuit_breaker(name: 'test', state: :open, reason: 'Too many failures') }
        .to output(/OPEN.*Too many failures/).to_stdout
    end
  end

  describe '.track_error and error statistics' do
    before { described_class.setup_loggers }

    it 'tracks new errors' do
      described_class.track_error('test_service', 'Connection failed')

      stats = described_class.error_stats
      expect(stats).to be_an(Array)
      expect(stats.first).to include(
        service: 'test_service',
        error: 'Connection failed',
        count: 1
      )
    end

    it 'increments count for duplicate errors' do
      described_class.track_error('test_service', 'Connection failed')
      described_class.track_error('test_service', 'Connection failed')
      described_class.track_error('test_service', 'Connection failed')

      stats = described_class.error_stats
      error = stats.find { |e| e[:error] == 'Connection failed' }
      expect(error[:count]).to eq(3)
    end

    it 'provides error summary' do
      described_class.track_error('service_a', 'Error 1')
      described_class.track_error('service_a', 'Error 1')
      described_class.track_error('service_b', 'Error 2')

      summary = described_class.error_summary
      
      expect(summary[:total_errors]).to eq(3)
      expect(summary[:unique_errors]).to eq(2)
      expect(summary[:by_service]).to eq({
        'service_a' => 2,
        'service_b' => 1
      })
    end

    it 'sorts errors by frequency in stats' do
      described_class.track_error('service_a', 'Common error')
      described_class.track_error('service_a', 'Common error')
      described_class.track_error('service_a', 'Common error')
      described_class.track_error('service_b', 'Rare error')

      stats = described_class.error_stats
      expect(stats.first[:count]).to be > stats.last[:count]
    end
  end

  describe 'ErrorTracker' do
    let(:errors_file) { File.join(log_dir, 'errors.json') }
    let(:error_tracker) do
      # Create tracker with proper directory setup
      tracker = described_class::ErrorTracker.new
      tracker.instance_variable_set(:@error_file, errors_file)
      tracker.instance_variable_set(:@errors, {})
      tracker
    end

    before do
      # Ensure the log directory exists for error tracking
      FileUtils.mkdir_p(log_dir)
    end

    it 'persists errors to JSON file' do
      error_tracker.track('test_service', 'Test error')

      expect(File.exist?(errors_file)).to be true
      
      data = JSON.parse(File.read(errors_file))
      expect(data).to have_key('test_service:Test error')
      expect(data['test_service:Test error']['count']).to eq(1)
    end

    it 'loads existing errors from file' do
      # Create initial error file
      initial_data = {
        'service:error' => {
          'service' => 'service',
          'error' => 'error',
          'count' => 5,
          'first_occurrence' => '2023-01-01T00:00:00Z',
          'last_occurrence' => '2023-01-01T00:00:00Z'
        }
      }
      File.write(errors_file, JSON.pretty_generate(initial_data))

      # Create new tracker instance (should load existing data)
      new_tracker = described_class::ErrorTracker.new
      new_tracker.instance_variable_set(:@error_file, errors_file)
      new_tracker.send(:load_errors)

      stats = new_tracker.stats
      expect(stats.first[:count]).to eq(5)
    end

    it 'handles corrupted JSON file gracefully' do
      File.write(errors_file, 'invalid json{')

      expect { error_tracker.send(:load_errors) }.not_to raise_error
      expect(error_tracker.stats).to be_empty
    end
  end
end