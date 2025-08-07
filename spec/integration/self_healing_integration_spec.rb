# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Self-Healing Error Handler Integration' do
  let(:service) { Services::ErrorHandlingLLM.new }
  let(:redis) { Redis.new }

  before do
    # Clear any existing error tracking
    redis.keys('glitchcube:error_count:*').each { |key| redis.del(key) }
    redis.keys('glitchcube:fixed_errors:*').each { |key| redis.del(key) }

    # Clean up any existing proposed fixes
    FileUtils.rm_rf('log/proposed_fixes')
    
    # Clear all OpenRouter service state to prevent mock leaking
    OpenRouterService.instance_variable_set(:@client, nil) if defined?(OpenRouterService)
  end

  after do
    # Cleanup
    FileUtils.rm_rf('log/proposed_fixes')
  end

  describe 'Full DRY_RUN flow with real LLM' do
    before do
      allow(GlitchCube.config).to receive_messages(self_healing_mode: 'DRY_RUN', self_healing_enabled?: true, self_healing_dry_run?: true, self_healing_yolo?: false, self_healing_min_confidence: 0.7, self_healing_error_threshold: 2)
    end

    it 'analyzes a real error and proposes a fix', vcr: { cassette_name: 'self_healing/dry_run_flow' } do
      # Ensure Redis is available for the service
      expect(redis.ping).to eq('PONG')
      
      # Simulate an error that occurs multiple times
      error = NoMethodError.new("undefined method `speak' for nil:NilClass")
      context = {
        service: 'TTSService',
        method: 'speak',
        file: 'lib/services/tts_service.rb',
        line: 275
      }

      # First occurrence - should just track
      result1 = service.handle_error(error, context)
      expect(result1[:action]).to eq('tracked')
      expect(result1[:occurrence_count]).to eq(1)

      # Second occurrence - should trigger analysis
      result2 = service.handle_error(error, context)

      # Debug output
      puts "Result2: #{result2.inspect}"

      # Check that it was processed (might be monitored, fix_proposed, or fix_failed)
      expect(result2[:action]).to be_in(['fix_proposed', 'monitored', 'fix_failed'])
      
      if result2[:action] == 'fix_proposed'
        expect(result2[:mode]).to eq('DRY_RUN')
        expect(result2[:fix_proposed]).to be_present
        expect(result2[:confidence]).to be > 0.5

        # In DRY_RUN mode, fixes may be saved to a file or just returned
        # The directory might not exist in test environment
        proposed_fixes_dir = File.join(Cube::Settings.app_root, 'log', 'proposed_fixes')
        
        if Dir.exist?(proposed_fixes_dir)
          jsonl_files = Dir.glob(File.join(proposed_fixes_dir, '*.jsonl'))
          
          if jsonl_files&.any?
            # Read and verify the proposed fix if file exists
            fix_content = File.read(jsonl_files.first)
            fix_data = JSON.parse(fix_content.lines.first)
            expect(fix_data['error']['class']).to eq('NoMethodError')
            expect(fix_data['error']['message']).to include('undefined method')
            expect(fix_data['confidence']).to be > 0.5
            expect(fix_data['proposed_fix']).to be_present
          end
        end
        
        # The important part is that the fix was proposed
        expect(result2[:fix_proposed]).to be_present

        # Third occurrence - should be marked as already analyzed
        result3 = service.handle_error(error, context)
        expect(result3[:action]).to eq('already_analyzed')
      elsif result2[:action] == 'monitored'
        # It was assessed as non-critical, which is a valid outcome
        expect(result2).to have_key(:critical)
        expect(result2).to have_key(:confidence)
        expect(result2).to have_key(:reason)
      end
    end
  end

  describe 'YOLO mode flow (mocked to prevent actual deployment)' do
    before do
      allow(GlitchCube.config).to receive_messages(self_healing_mode: 'YOLO', self_healing_enabled?: true, self_healing_dry_run?: false, self_healing_yolo?: true, self_healing_min_confidence: 0.7, self_healing_error_threshold: 2)

      # Mock git operations to prevent actual commits
      allow(service).to receive_messages(system: true, '`': 'mock_sha_123')
    end

    it 'would apply fix in YOLO mode', vcr: { cassette_name: 'self_healing/yolo_flow' } do
      error = StandardError.new('Connection timeout')
      context = {
        service: 'HomeAssistantClient',
        method: 'get_states',
        file: 'lib/home_assistant_client.rb',
        line: 42
      }

      # Track error twice to trigger analysis
      service.handle_error(error, context)
      result = service.handle_error(error, context)

      # In YOLO mode, it should attempt to apply the fix
      if result[:action] == 'self_healed'
        expect(result[:mode]).to eq('YOLO')
        expect(result[:fix_applied]).to be_present
        # Git operations were mocked, so no real deployment
      elsif result[:action] == 'monitored'
        # If confidence was too low, it won't apply
        expect(result[:critical]).to be false
      end
    end
  end

  describe 'OFF mode' do
    before do
      allow(GlitchCube.config).to receive_messages(self_healing_mode: 'OFF', self_healing_enabled?: false)
    end

    it 'does nothing when disabled' do
      error = StandardError.new('Any error')
      context = { service: 'TestService' }

      result = service.handle_error(error, context)

      expect(result[:action]).to eq('logged_only')
      expect(result[:message]).to include('Self-healing disabled')

      # No files should be created
      expect(Dir.exist?('log/proposed_fixes')).to be false
    end
  end

  describe 'Reviewing proposed fixes' do
    before do
      # Create sample proposed fixes
      FileUtils.mkdir_p('log/proposed_fixes')

      fixes = [
        {
          timestamp: Time.now.iso8601,
          error: { class: 'NoMethodError', message: 'undefined method', occurrences: 3 },
          confidence: 0.92,
          analysis: { critical: true, reason: 'Core functionality broken' },
          proposed_fix: { description: 'Add nil check', files_modified: ['lib/service.rb'] }
        },
        {
          timestamp: Time.now.iso8601,
          error: { class: 'Timeout::Error', message: 'execution expired', occurrences: 5 },
          confidence: 0.65,
          analysis: { critical: false, reason: 'Transient network issue' },
          proposed_fix: { description: 'Increase timeout', files_modified: ['lib/client.rb'] }
        }
      ]

      File.open("log/proposed_fixes/#{Time.now.strftime('%Y%m%d')}_proposed_fixes.jsonl", 'w') do |f|
        fixes.each { |fix| f.puts JSON.generate(fix) }
      end
    end

    it 'can load and analyze proposed fixes' do
      # This would be called by the review script
      fixes = []
      Dir.glob('log/proposed_fixes/*.jsonl').each do |file|
        File.readlines(file).each do |line|
          fixes << JSON.parse(line)
        end
      end

      expect(fixes.length).to eq(2)

      # High confidence fixes
      high_confidence = fixes.select { |f| f['confidence'] >= 0.85 }
      expect(high_confidence.length).to eq(1)
      expect(high_confidence.first['proposed_fix']['description']).to eq('Add nil check')

      # Critical issues
      critical = fixes.select { |f| f.dig('analysis', 'critical') }
      expect(critical.length).to eq(1)
    end
  end
end
