require 'spec_helper'
require 'fileutils'

RSpec.describe Services::UnifiedLoggerService do
  let(:test_log_dir) { File.join(Dir.pwd, 'logs', 'test') }
  
  before do
    # Clean up any existing loggers
    described_class.reset!
    
    # Ensure test log directory exists
    FileUtils.mkdir_p(test_log_dir)
  end

  after do
    # Clean up test logs
    FileUtils.rm_rf(Dir.glob(File.join(test_log_dir, '*'))) if Dir.exist?(test_log_dir)
    described_class.reset!
  end

  describe '.setup!' do
    it 'initializes the logger successfully' do
      expect { described_class.setup! }.not_to raise_error
      expect(described_class.logger).not_to be_nil
    end
  end

  describe '.info, .warn, .error, .debug' do
    before { described_class.setup! }

    it 'logs messages with appropriate levels' do
      expect { described_class.info('Test info message') }.not_to raise_error
      expect { described_class.warn('Test warning') }.not_to raise_error
      expect { described_class.error('Test error') }.not_to raise_error
      expect { described_class.debug('Test debug') }.not_to raise_error
    end
  end

  describe 'contextual logging' do
    before { described_class.setup! }

    it 'supports context blocks' do
      expect do
        described_class.with_context(request_id: 'req-123', user: 'test') do
          described_class.info('Processing request')
          described_class.error('Something went wrong')
        end
      end.not_to raise_error
    end

    it 'supports nested contexts' do
      expect do
        described_class.with_context(session_id: 'sess-456') do
          described_class.info('Starting session')
          
          described_class.with_context(conversation_id: 'conv-789') do
            described_class.info('Processing conversation')
          end
        end
      end.not_to raise_error
    end
  end

  describe 'structured logging methods' do
    before { described_class.setup! }

    it 'logs API calls with structured data' do
      expect do
        described_class.api_call(
          service: 'openrouter',
          method: 'POST',
          endpoint: '/chat/completions',
          status: 200,
          duration: 1500,
          tokens: { input: 100, output: 50 }
        )
      end.not_to raise_error
    end

    it 'logs conversations with metadata' do
      expect do
        described_class.conversation(
          user_message: 'Hello',
          ai_response: 'Hi there!',
          mood: 'friendly',
          confidence: 0.85,
          model: 'claude-3-haiku'
        )
      end.not_to raise_error
    end

    it 'logs system events' do
      expect do
        described_class.system_event(
          event: 'battery_low',
          level: 25,
          action: 'requesting_charge'
        )
      end.not_to raise_error
    end
  end
end