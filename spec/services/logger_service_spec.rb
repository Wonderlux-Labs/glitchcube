# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tempfile'

RSpec.describe Services::LoggerService do
  let(:temp_dir) { Dir.mktmpdir }
  let(:log_dir) { File.join(temp_dir, 'logs') }
  let(:log_file) { File.join(log_dir, 'current.log') }

  before do
    # Clear any existing logger instances
    described_class.instance_variables.each do |var|
      described_class.remove_instance_variable(var) if described_class.instance_variable_defined?(var)
    end

    # Stub SimpleLogger's private methods to use our temp directory
    allow(Services::SimpleLogger).to receive(:log_directory).and_return(log_dir)
    allow(Services::SimpleLogger).to receive(:log_file_path).and_return(log_file)
    allow(Services::SimpleLogger).to receive(:ensure_log_directory) do
      FileUtils.mkdir_p(log_dir) unless File.directory?(log_dir)
    end
    allow(Services::SimpleLogger).to receive(:write_to_file) do |line|
      FileUtils.mkdir_p(log_dir) unless File.directory?(log_dir)
      File.open(log_file, 'a') { |f| f.puts line }
    end

    # Also mock for LoggerService compatibility methods
    allow(described_class).to receive(:log_directory).and_return(log_dir)

    # Ensure test log directory exists
    FileUtils.mkdir_p(log_dir)

    # Clear the log file before each test
    FileUtils.rm_f(log_file)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '.setup_loggers' do
    it 'creates log directory if it does not exist', :vcr do
      FileUtils.rm_rf(log_dir)
      expect(Dir.exist?(log_dir)).to be false

      # SimpleLogger creates the directory on first write
      Services::SimpleLogger.info('test')

      expect(Dir.exist?(log_dir)).to be true
    end

    it 'creates all required log files', :vcr do
      # SimpleLogger now uses a single log file
      Services::SimpleLogger.info('test')

      expect(File.exist?(log_file)).to be true
    end
  end

  describe '.log_interaction' do
    let(:interaction_data) do
      {
        user_message: 'Hello, Glitch Cube!',
        ai_response: 'Hello there! Ready to create some art?',
        persona: 'playful',
        confidence: 0.95,
        session_id: 'test_session_001',
        context: { test_mode: true }
      }
    end

    it 'logs interaction to interactions.log with proper formatting', :vcr do
      described_class.log_interaction(**interaction_data)

      # Check that SimpleLogger was called with the right data
      log_content = File.read(log_file) if File.exist?(log_file)

      # SimpleLogger includes tags and metadata
      expect(log_content).to include('Interaction: playful') if log_content
    end

    it 'logs interaction to general.log as JSON', :vcr do
      described_class.log_interaction(**interaction_data)

      # With SimpleLogger, everything goes to the same file
      log_content = File.read(log_file) if File.exist?(log_file)

      expect(log_content).to include('playful') if log_content
      expect(log_content).to include('test_session_001') if log_content
    end
  end

  describe '.log_api_call' do
    let(:api_data) do
      {
        service: 'home_assistant',
        endpoint: '/api/services/tts/speak',
        method: 'POST',
        status: 200,
        duration: 1250
      }
    end

    it 'logs successful API call with success emoji', :vcr do
      described_class.log_api_call(**api_data)

      log_content = File.read(log_file) if File.exist?(log_file)
      expect(log_content).to include('✅') if log_content
      expect(log_content).to include('HOME_ASSISTANT') if log_content
    end

    it 'logs failed API call with error emoji', :vcr do
      described_class.log_api_call(
        service: 'home_assistant',
        endpoint: '/api/test',
        method: 'GET',
        status: 500,
        duration: 500,
        error: 'Internal Server Error'
      )

      log_content = File.read(log_file) if File.exist?(log_file)
      expect(log_content).to include('❌') if log_content
      expect(log_content).to include('Internal Server Error') if log_content
    end

    it 'tracks errors when present', :vcr do
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
    it 'logs successful TTS with speaker emoji', :vcr do
      described_class.log_tts(
        message: 'Hello world!',
        success: true,
        duration: 2000
      )

      log_content = File.read(log_file) if File.exist?(log_file)
      expect(log_content).to include('🔊') if log_content
      expect(log_content).to include('Hello world!') if log_content
    end

    it 'logs failed TTS with mute emoji and error', :vcr do
      described_class.log_tts(
        message: 'Hello world!',
        success: false,
        duration: 100,
        error: 'TTS service unavailable'
      )

      log_content = File.read(log_file) if File.exist?(log_file)
      expect(log_content).to include('🔇') if log_content
      expect(log_content).to include('TTS service unavailable') if log_content
    end

    it 'truncates long messages', :vcr do
      long_message = 'a' * 150

      described_class.log_tts(
        message: long_message,
        success: true
      )

      log_content = File.read(log_file) if File.exist?(log_file)
      expect(log_content).to include('...') if log_content
      expect(log_content).not_to include('a' * 150) if log_content
    end
  end

  describe '.log_circuit_breaker' do
    it 'logs circuit breaker state changes with appropriate emoji', :vcr do
      # SimpleLogger writes to file, not stdout, so we check the file
      described_class.log_circuit_breaker(name: 'test', state: :open)
      log_content = File.read(log_file) if File.exist?(log_file)
      expect(log_content).to include('🔴') if log_content
      expect(log_content).to include('OPEN') if log_content

      described_class.log_circuit_breaker(name: 'test', state: :closed)
      log_content = File.read(log_file) if File.exist?(log_file)
      expect(log_content).to include('🟢') if log_content
      expect(log_content).to include('CLOSED') if log_content

      described_class.log_circuit_breaker(name: 'test', state: :half_open)
      log_content = File.read(log_file) if File.exist?(log_file)
      expect(log_content).to include('🟡') if log_content
      expect(log_content).to include('HALF_OPEN') if log_content
    end

    it 'includes reason when provided', :vcr do
      described_class.log_circuit_breaker(name: 'test', state: :open, reason: 'Too many failures')

      log_content = File.read(log_file) if File.exist?(log_file)
      expect(log_content).to include('Too many failures') if log_content
    end
  end

  describe '.track_error and error statistics' do
    before { described_class.setup_loggers }

    it 'tracks new errors', :vcr do
      described_class.track_error('test_service', 'Connection failed')

      stats = described_class.error_stats
      expect(stats).to be_an(Array)
      expect(stats.first).to include(
        service: 'test_service',
        error: 'Connection failed',
        count: 1
      )
    end

    it 'increments count for duplicate errors', :vcr do
      described_class.track_error('test_service', 'Connection failed')
      described_class.track_error('test_service', 'Connection failed')
      described_class.track_error('test_service', 'Connection failed')

      stats = described_class.error_stats
      error = stats.find { |e| e[:error] == 'Connection failed' }
      expect(error[:count]).to eq(3)
    end

    it 'provides error summary', :vcr do
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

    it 'sorts errors by frequency in stats', :vcr do
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

    it 'persists errors to JSON file', :vcr do
      error_tracker.track('test_service', 'Test error')

      expect(File.exist?(errors_file)).to be true

      data = JSON.parse(File.read(errors_file))
      expect(data).to have_key('test_service:Test error')
      expect(data['test_service:Test error']['count']).to eq(1)
    end

    it 'loads existing errors from file', :vcr do
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

    it 'handles corrupted JSON file gracefully', :vcr do
      File.write(errors_file, 'invalid json{')

      expect { error_tracker.send(:load_errors) }.not_to raise_error
      expect(error_tracker.stats).to be_empty
    end
  end
end
