# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::ErrorHandlingLLM, 'dry-run mode' do
  let(:service) { described_class.new }
  let(:redis) { Redis.new }
  let(:error) { StandardError.new('Test error') }
  let(:context) do
    {
      service: 'TestService',
      method: 'test_method',
      file: 'lib/test_service.rb',
      line: 42,
      occurrence_count: 3
    }
  end

  before do
    allow(Redis).to receive(:new).and_return(redis)
    allow(redis).to receive(:expire)
    allow(redis).to receive(:set)
    allow(redis).to receive_messages(incr: 3, get: nil, exists?: false)
    allow(GlitchCube.config).to receive_messages(self_healing_mode: 'DRY_RUN', self_healing_enabled?: true, self_healing_dry_run?: true, self_healing_yolo?: false, self_healing_min_confidence: 0.85, self_healing_error_threshold: 2, rack_env: 'development')
  end

  describe 'dry-run behavior' do
    context 'when fix is proposed' do
      before do
        allow(service).to receive_messages(assess_criticality: {
                                             critical: true,
                                             confidence: 0.9,
                                             reason: 'Critical error'
                                           }, analyze_and_fix_code: {
                                             success: true,
                                             description: 'Added nil check',
                                             files_modified: ['lib/test_service.rb']
                                           })
      end

      it 'saves proposed fix instead of applying it' do
        expect(service).to receive(:save_proposed_fix).with(
          error,
          hash_including(occurrence_count: 3),
          hash_including(critical: true),
          hash_including(success: true)
        )

        expect(service).not_to receive(:apply_and_deploy_fix)

        result = service.handle_error(error, context)
        expect(result[:action]).to eq('fix_proposed')
        expect(result[:mode]).to eq('DRY_RUN')
      end

      it 'marks error as analyzed in Redis' do
        expect(redis).to receive(:set).with(/fixed_errors/, 'proposed', ex: 604_800)

        service.handle_error(error, context)
      end
    end

    context 'when error already analyzed' do
      before do
        allow(redis).to receive(:exists?).with(/fixed_errors/).and_return(true)
      end

      it 'does not re-analyze the error' do
        expect(service).not_to receive(:assess_criticality)

        result = service.handle_error(error, context)
        expect(result[:action]).to eq('already_analyzed')
      end
    end

    context 'when in YOLO mode' do
      before do
        allow(GlitchCube.config).to receive_messages(self_healing_mode: 'YOLO', self_healing_dry_run?: false, self_healing_yolo?: true)

        allow(service).to receive_messages(assess_criticality: {
                                             critical: true,
                                             confidence: 0.9,
                                             reason: 'Critical error'
                                           }, analyze_and_fix_code: {
                                             success: true,
                                             description: 'Added nil check',
                                             files_modified: ['lib/test_service.rb']
                                           }, apply_and_deploy_fix: {
                                             deployed: true,
                                             commit_sha: 'abc123'
                                           })
      end

      it 'applies fix immediately' do
        expect(service).not_to receive(:save_proposed_fix)
        expect(service).to receive(:apply_and_deploy_fix)

        result = service.handle_error(error, context)
        expect(result[:action]).to eq('self_healed')
        expect(result[:mode]).to eq('YOLO')
      end
    end
  end

  describe '#save_proposed_fix' do
    let(:analysis) do
      {
        critical: true,
        confidence: 0.9,
        reason: 'Critical error',
        suggested_fix: 'Add validation'
      }
    end

    let(:fix_result) do
      {
        description: 'Added nil check',
        files_modified: ['lib/test_service.rb'],
        changes: [{ file: 'lib/test_service.rb', diff: '+ return unless value' }]
      }
    end

    context 'when database is available' do
      before do
        mock_class = Class.new do
          def self.create!(_attrs)
            true
          end
        end
        stub_const('ProposedFix', mock_class)
      end

      it 'saves to database' do
        expect(ProposedFix).to receive(:create!).with(
          hash_including(
            error_class: 'StandardError',
            error_message: 'Test error',
            confidence: 0.9,
            critical: true,
            status: 'pending'
          )
        )

        service.send(:save_proposed_fix, error, context, analysis, fix_result)
      end
    end

    context 'when database is not available' do
      before do
        hide_const('ProposedFix')
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:open)
      end

      it 'logs to file' do
        expect(FileUtils).to receive(:mkdir_p).with('log/proposed_fixes')
        expect(File).to receive(:open).with(/proposed_fixes\.jsonl/, 'a')

        service.send(:save_proposed_fix, error, context, analysis, fix_result)
      end
    end
  end
end
