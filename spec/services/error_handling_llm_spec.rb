# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::ErrorHandlingLLM do
  let(:service) { described_class.new }
  let(:redis) { instance_double(Redis) }
  let(:logger) { Services::LoggerService }

  before do
    allow(Redis).to receive(:new).and_return(redis)
    allow(redis).to receive(:expire)
    allow(redis).to receive_messages(incr: 1, get: nil, set: true, del: true, ping: 'PONG')
    allow(redis).to receive_messages(keys: [], exists?: false)
    allow(logger).to receive(:log_api_call)
  end

  describe '#initialize' do
    context 'when Redis is available' do
      it 'initializes with Redis connection' do
        expect(service.instance_variable_get(:@redis)).to eq(redis)
      end
    end

    context 'when Redis is unavailable' do
      before do
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError, 'Connection refused')
      end

      it 'handles Redis connection error gracefully' do
        service = described_class.new
        expect(service.instance_variable_get(:@redis)).to be_nil
      end

      it 'logs the Redis connection failure' do
        expect(logger).to receive(:log_api_call).with(
          hash_including(
            service: 'ErrorHandlingLLM',
            endpoint: 'initialize',
            error: /Redis unavailable/
          )
        )
        described_class.new
      end
    end
  end

  describe '#handle_error' do
    let(:error) { StandardError.new('Connection refused') }
    let(:context) { { service: 'TTSService', method: 'speak', file: 'lib/services/tts_service.rb', line: 42 } }

    context 'when self-healing is disabled' do
      before do
        allow(GlitchCube.config).to receive_messages(
          self_healing_mode: 'OFF',
          self_healing_enabled?: false
        )
      end

      it 'logs the error but does not attempt to fix' do
        expect(logger).to receive(:log_api_call).with(
          hash_including(
            service: 'ErrorHandlingLLM',
            endpoint: 'handle_error',
            self_healing: false
          )
        )

        result = service.handle_error(error, context)
        expect(result[:action]).to eq('logged_only')
        expect(result[:message]).to eq('Self-healing disabled')
      end
    end

    context 'when self-healing is enabled' do
      before do
        allow(GlitchCube.config).to receive_messages(
          self_healing_mode: 'DRY_RUN',
          self_healing_enabled?: true,
          self_healing_dry_run?: true,
          self_healing_yolo?: false,
          self_healing_error_threshold: 3,
          self_healing_min_confidence: 0.7
        )
      end

      context 'when error has already been analyzed' do
        before do
          allow(redis).to receive(:exists?).with(/fixed_errors/).and_return(true)
        end

        it 'returns already_analyzed status' do
          result = service.handle_error(error, context)
          expect(result[:action]).to eq('already_analyzed')
          expect(result[:message]).to include('Fix already proposed')
        end
      end

      context 'with first occurrence of error' do
        it 'tracks the error but does not attempt fix' do
          expect(redis).to receive(:incr).with(/error_count/).and_return(1)
          expect(redis).to receive(:expire).with(/error_count/, 3600)

          result = service.handle_error(error, context)
          expect(result[:action]).to eq('tracked')
          expect(result[:occurrence_count]).to eq(1)
        end
      end

      context 'with recurring error below threshold' do
        before do
          allow(redis).to receive(:incr).and_return(2)
        end

        it 'tracks but does not fix' do
          result = service.handle_error(error, context)
          expect(result[:action]).to eq('tracked')
          expect(result[:occurrence_count]).to eq(2)
        end
      end

      context 'with recurring error at threshold' do
        before do
          allow(redis).to receive(:incr).and_return(3)
        end

        it 'assesses criticality of the error' do
          expect(service).to receive(:assess_criticality).and_return({ critical: false, confidence: 0.5 })

          service.handle_error(error, context)
        end

        context 'when error is critical with high confidence' do
          before do
            allow(service).to receive(:assess_criticality).and_return({
                                                                        critical: true,
                                                                        confidence: 0.9,
                                                                        reason: 'Service unavailable affecting core functionality'
                                                                      })
          end

          it 'attempts self-healing in DRY_RUN mode' do
            expect(service).to receive(:attempt_self_healing).and_return({
                                                                           action: 'fix_proposed',
                                                                           success: true,
                                                                           mode: 'DRY_RUN',
                                                                           fix_proposed: 'Added retry logic with exponential backoff'
                                                                         })

            result = service.handle_error(error, context)
            expect(result[:action]).to eq('fix_proposed')
          end
        end

        context 'when error is non-critical' do
          before do
            allow(service).to receive(:assess_criticality).and_return({
                                                                        critical: false,
                                                                        confidence: 0.8,
                                                                        reason: 'Temporary network issue, will self-resolve'
                                                                      })
          end

          it 'monitors but does not attempt fix' do
            expect(service).not_to receive(:attempt_self_healing)

            result = service.handle_error(error, context)
            expect(result[:action]).to eq('monitored')
            expect(result[:reason]).to include('Temporary network issue')
          end
        end

        context 'when error is critical but low confidence' do
          before do
            allow(service).to receive(:assess_criticality).and_return({
                                                                        critical: true,
                                                                        confidence: 0.4,
                                                                        reason: 'Possibly critical but unclear'
                                                                      })
          end

          it 'monitors but does not attempt fix' do
            expect(service).not_to receive(:attempt_self_healing)

            result = service.handle_error(error, context)
            expect(result[:action]).to eq('monitored')
          end
        end
      end

      context 'when Redis is unavailable' do
        before do
          allow(service.instance_variable_get(:@redis)).to receive(:incr)
            .and_raise(Redis::BaseError, 'Connection lost')
          service.instance_variable_set(:@redis, redis)
        end

        it 'falls back to in-memory tracking' do
          result = service.handle_error(error, context)
          expect(result[:action]).to eq('tracked')
          expect(result[:occurrence_count]).to eq(1)
        end
      end
    end

    context 'error handling' do
      before do
        allow(GlitchCube.config).to receive(:self_healing_enabled?).and_raise('Unexpected error')
      end

      it 'handles unexpected errors gracefully' do
        result = service.handle_error(error, context)
        expect(result[:action]).to eq('handler_failed')
        expect(result[:error]).to include('Unexpected error')
      end
    end
  end

  describe '#assess_criticality' do
    let(:error) { StandardError.new("undefined method 'speak' for nil:NilClass") }
    let(:context) { { service: 'TTSService', occurrence_count: 5 } }

    context 'when rate limit is not exceeded' do
      before do
        allow(service).to receive(:rate_limit_exceeded?).and_return(false)
      end

      it 'uses LLM to analyze error criticality' do
        expect(OpenRouterService).to receive(:complete).with(
          anything,
          model: 'openai/gpt-4o-mini',
          response_format: { type: 'json_object' }
        ).and_return(JSON.generate({
                                     'critical' => true,
                                     'confidence' => 0.85,
                                     'reason' => 'Null pointer exception in core service',
                                     'suggested_fix' => 'Add nil check before method call',
                                     'affects_core_functionality' => true,
                                     'can_self_heal' => true
                                   }))

        result = service.assess_criticality(error, context)
        expect(result[:critical]).to be true
        expect(result[:confidence]).to eq(0.85)
        expect(result[:suggested_fix]).to eq('Add nil check before method call')
      end

      it 'handles malformed JSON response' do
        expect(OpenRouterService).to receive(:complete).and_return('not json')

        result = service.assess_criticality(error, context)
        expect(result[:critical]).to be false
        expect(result[:confidence]).to eq(0)
        expect(result[:reason]).to eq('Unknown')
      end

      it 'handles LLM errors gracefully' do
        expect(OpenRouterService).to receive(:complete).and_raise('API Error')

        result = service.assess_criticality(error, context)
        expect(result[:critical]).to be false
        expect(result[:confidence]).to eq(0)
        expect(result[:reason]).to include('Failed to assess')
      end
    end

    context 'when rate limit is exceeded' do
      before do
        allow(service).to receive(:rate_limit_exceeded?).and_return(true)
      end

      it 'returns low confidence without calling LLM' do
        expect(OpenRouterService).not_to receive(:complete)

        result = service.assess_criticality(error, context)
        expect(result[:critical]).to be false
        expect(result[:confidence]).to eq(0)
        expect(result[:reason]).to include('Rate limit exceeded')
      end
    end
  end

  describe '#attempt_self_healing' do
    let(:error) { StandardError.new('Connection timeout') }
    let(:context) do
      {
        service: 'HomeAssistantClient',
        file: 'lib/home_assistant_client.rb',
        line: 42
      }
    end
    let(:analysis) do
      {
        critical: true,
        suggested_fix: 'Increase timeout and add retry logic',
        confidence: 0.92
      }
    end

    before do
      allow(GlitchCube.config).to receive(:self_healing_min_confidence).and_return(0.7)
    end

    context 'when confidence is high enough' do
      context 'in DRY_RUN mode' do
        before do
          allow(GlitchCube.config).to receive(:self_healing_yolo?).and_return(false)
          allow(service).to receive(:analyze_and_fix_code).and_return({
                                                                        success: true,
                                                                        description: 'Added timeout configuration',
                                                                        changes: ['Added timeout configuration', 'Implemented retry with backoff'],
                                                                        files_modified: ['lib/home_assistant_client.rb']
                                                                      })
        end

        it 'proposes fix without applying' do
          expect(service).to receive(:save_proposed_fix)
          expect(service).not_to receive(:apply_and_deploy_fix)

          result = service.attempt_self_healing(error, context, analysis)
          expect(result[:action]).to eq('fix_proposed')
          expect(result[:mode]).to eq('DRY_RUN')
          expect(result[:success]).to be true
        end
      end

      context 'in YOLO mode' do
        before do
          allow(GlitchCube.config).to receive(:self_healing_yolo?).and_return(true)
          allow(service).to receive(:analyze_and_fix_code).and_return({
                                                                        success: true,
                                                                        description: 'Added timeout configuration',
                                                                        changes: ['Added timeout configuration', 'Implemented retry with backoff'],
                                                                        files_modified: ['lib/home_assistant_client.rb']
                                                                      })
        end

        it 'applies the fix and deploys' do
          expect(service).to receive(:apply_and_deploy_fix).and_return({
                                                                         deployed: true,
                                                                         commit_sha: 'abc123'
                                                                       })

          result = service.attempt_self_healing(error, context, analysis)
          expect(result[:action]).to eq('self_healed')
          expect(result[:mode]).to eq('YOLO')
          expect(result[:success]).to be true
        end
      end

      context 'when fix generation fails' do
        before do
          allow(service).to receive(:analyze_and_fix_code).and_return({
                                                                        success: false,
                                                                        error: 'Could not parse file'
                                                                      })
        end

        it 'returns fix_failed' do
          result = service.attempt_self_healing(error, context, analysis)
          expect(result[:action]).to eq('fix_failed')
          expect(result[:success]).to be false
          expect(result[:reason]).to eq('Could not parse file')
        end
      end
    end

    context 'when confidence is too low' do
      let(:analysis) do
        {
          critical: true,
          suggested_fix: 'Maybe try something',
          confidence: 0.4
        }
      end

      it 'does not attempt fix' do
        expect(service).not_to receive(:analyze_and_fix_code)

        result = service.attempt_self_healing(error, context, analysis)
        expect(result[:success]).to be false
        expect(result[:reason]).to include('Confidence too low')
      end
    end
  end

  describe '#analyze_and_fix_code' do
    let(:error) { StandardError.new('undefined method') }
    let(:context) { { file: 'lib/services/tts_service.rb', line: 30 } }

    context 'when Task agent is available' do
      before do
        stub_const('Task', Class.new do
          def call(_params)
            {
              success: true,
              fix: {
                description: 'Added defensive nil check',
                changes: [
                  {
                    file: 'lib/services/tts_service.rb',
                    diff: '+ return unless client',
                    line: 29
                  }
                ]
              }
            }.to_json
          end
        end)
      end

      it 'uses Task agent to analyze and fix code' do
        result = service.analyze_and_fix_code(error, context)
        expect(result[:success]).to be true
        expect(result[:description]).to eq('Added defensive nil check')
        expect(result[:files_modified]).to eq(['lib/services/tts_service.rb'])
      end
    end

    context 'when Task agent is not available' do
      before do
        hide_const('Task')
      end

      it 'falls back to direct LLM call' do
        expect(OpenRouterService).to receive(:complete).and_return(
          JSON.generate({
                          success: true,
                          fix: {
                            description: 'Added nil check',
                            changes: [
                              { file: 'lib/services/tts_service.rb', diff: '+ return unless client', line: 29 }
                            ]
                          }
                        })
        )

        result = service.analyze_and_fix_code(error, context)
        expect(result[:success]).to be true
      end
    end

    context 'when agent returns error' do
      before do
        stub_const('Task', Class.new do
          def call(_params)
            raise 'Agent error'
          end
        end)
      end

      it 'handles agent errors gracefully' do
        result = service.analyze_and_fix_code(error, context)
        expect(result[:success]).to be false
        expect(result[:error]).to include('Agent error')
      end
    end
  end

  describe '#apply_and_deploy_fix' do
    let(:fix) do
      {
        description: 'Added nil check',
        files_modified: ['lib/services/tts_service.rb'],
        changes: ['Added nil check'],
        commit_message: '[AUTO-FIX] Handle nil client in TTSService',
        confidence: 0.85,
        error_class: 'NoMethodError'
      }
    end

    context 'when git operations succeed' do
      before do
        allow(service).to receive_messages(system: true, '`': 'abc123def')
      end

      it 'creates a feature branch and pushes the fix' do
        expect(service).to receive(:system).with(%r{git checkout -b auto-fix/}).and_return(true)
        expect(service).to receive(:system).with('git add lib/services/tts_service.rb').and_return(true)
        expect(service).to receive(:system).with(/git commit/).and_return(true)
        expect(service).to receive(:system).with(%r{git push origin auto-fix/}).and_return(true)
        expect(service).to receive(:system).with('git checkout main').and_return(true)

        result = service.apply_and_deploy_fix(fix)
        expect(result[:deployed]).to be true
        expect(result[:branch]).to match(%r{^auto-fix/})
      end

      it 'stores rollback information' do
        expect(redis).to receive(:set).with('glitchcube:rollback_sha', 'abc123def')
        expect(redis).to receive(:expire).with('glitchcube:rollback_sha', 86_400)

        service.apply_and_deploy_fix(fix)
      end

      context 'when gh CLI is available' do
        before do
          allow(service).to receive(:system).with('which gh > /dev/null 2>&1').and_return(true)
          allow(service).to receive(:`).with(/gh pr create/).and_return('https://github.com/user/repo/pull/123')
        end

        it 'creates a pull request' do
          result = service.apply_and_deploy_fix(fix)
          expect(result[:pr_url]).to eq('https://github.com/user/repo/pull/123')
        end
      end

      context 'when gh CLI is not available' do
        before do
          allow(service).to receive(:system).with('which gh > /dev/null 2>&1').and_return(false)
        end

        it 'skips PR creation' do
          result = service.apply_and_deploy_fix(fix)
          expect(result[:pr_url]).to be_nil
          expect(result[:deployed]).to be true
        end
      end
    end

    context 'when git operations fail' do
      before do
        allow(service).to receive(:system).and_return(false)
      end

      it 'returns failure without pushing' do
        result = service.apply_and_deploy_fix(fix)
        expect(result[:deployed]).to be false
        expect(result[:error]).to include('Failed to create branch')
      end
    end

    context 'when push fails' do
      before do
        allow(service).to receive(:system).with(/git checkout -b/).and_return(true)
        allow(service).to receive(:system).with(/git add/).and_return(true)
        allow(service).to receive(:system).with(/git commit/).and_return(true)
        allow(service).to receive(:system).with(/git push/).and_return(false)
        allow(service).to receive(:system).with('git checkout main').and_return(true)
        allow(service).to receive(:system).with(/git branch -D/).and_return(true)
      end

      it 'cleans up branch and returns failure' do
        expect(service).to receive(:system).with(/git branch -D auto-fix/)

        result = service.apply_and_deploy_fix(fix)
        expect(result[:deployed]).to be false
        expect(result[:error]).to include('Failed to push')
      end
    end
  end

  describe '#rollback_last_fix' do
    context 'when rollback SHA exists' do
      before do
        allow(redis).to receive(:get).with('glitchcube:rollback_sha').and_return('abc123')
        allow(service).to receive(:system).and_return(true)
      end

      it 'reverts to previous commit' do
        expect(service).to receive(:system).with('git revert --no-edit abc123').and_return(true)
        expect(service).to receive(:system).with('git push origin main').and_return(true)
        expect(redis).to receive(:del).with('glitchcube:rollback_sha')

        result = service.rollback_last_fix
        expect(result[:success]).to be true
        expect(result[:reverted_to]).to eq('abc123')
      end
    end

    context 'when no rollback SHA exists' do
      before do
        allow(redis).to receive(:get).and_return(nil)
      end

      it 'returns error' do
        result = service.rollback_last_fix
        expect(result[:success]).to be false
        expect(result[:error]).to include('No recent fix to rollback')
      end
    end

    context 'when Redis is not available' do
      before do
        service.instance_variable_set(:@redis, nil)
      end

      it 'returns error' do
        result = service.rollback_last_fix
        expect(result[:success]).to be false
        expect(result[:error]).to include('Redis not available')
      end
    end
  end

  describe 'rate limiting' do
    context 'with Redis available' do
      it 'tracks rate limits in Redis' do
        expect(redis).to receive(:incr).with('glitchcube:llm_rate_limit').and_return(1)
        expect(redis).to receive(:expire).with('glitchcube:llm_rate_limit', 60)

        expect(service.send(:rate_limit_exceeded?)).to be false
      end

      it 'detects when rate limit is exceeded' do
        expect(redis).to receive(:incr).with('glitchcube:llm_rate_limit').and_return(11)

        expect(service.send(:rate_limit_exceeded?)).to be true
      end
    end

    context 'with Redis unavailable' do
      before do
        allow(redis).to receive(:incr).and_raise(Redis::BaseError)
      end

      it 'falls back to in-memory rate limiting' do
        # First 10 calls should be allowed
        10.times do
          expect(service.send(:rate_limit_exceeded?)).to be false
        end

        # 11th call should be rate limited
        expect(service.send(:rate_limit_exceeded?)).to be true
      end
    end
  end

  describe 'proposed fix logging' do
    let(:error) { StandardError.new('Test error') }
    let(:context) { { service: 'TestService', occurrence_count: 3 } }
    let(:analysis) { { confidence: 0.8, critical: true, reason: 'Test' } }
    let(:fix_result) { { description: 'Test fix' } }

    context 'when database model is available' do
      before do
        stub_const('ProposedFix', Class.new do
          def self.create!(params)
            params
          end
        end)
      end

      it 'saves to database' do
        expect(ProposedFix).to receive(:create!).with(
          hash_including(
            error_class: 'StandardError',
            error_message: 'Test error',
            confidence: 0.8
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

      it 'falls back to file logging' do
        expect(FileUtils).to receive(:mkdir_p).with(end_with('log/proposed_fixes'))
        expect(File).to receive(:open).with(/proposed_fixes\.jsonl/, 'a')

        service.send(:save_proposed_fix, error, context, analysis, fix_result)
      end
    end

    it 'marks error as fixed in Redis' do
      expect(redis).to receive(:set).with(/fixed_errors/, 'proposed', ex: 604_800)

      service.send(:save_proposed_fix, error, context, analysis, fix_result)
    end
  end
end
