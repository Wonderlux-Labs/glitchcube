# frozen_string_literal: true

RSpec.describe TestModule do
  describe '.name' do
    it 'returns the module name' do
      expect(described_class.name).to eq('Test Module')
    end
  end

  describe '.description' do
    it 'returns the module description' do
      expect(described_class.description).to eq('A simple test module for Glitch Cube')
    end
  end

  describe '#handle_greeting' do
    let(:module_instance) { Object.new.extend(described_class) }

    it 'responds to hello' do
      response = module_instance.handle_greeting('Hello there!')
      expect(response).to include('Greetings from the Glitch Cube')
      expect(response).to include('sentient art installation')
    end

    it 'responds to hi' do
      response = module_instance.handle_greeting('Hi Glitch Cube')
      expect(response).to include('Greetings from the Glitch Cube')
    end

    it 'returns nil for non-greeting messages' do
      response = module_instance.handle_greeting('What is your status?')
      expect(response).to be_nil
    end
  end

  describe '#handle_status_check' do
    let(:module_instance) { Object.new.extend(described_class) }

    it 'responds to status inquiries' do
      response = module_instance.handle_status_check('What is your status?')
      expect(response).to include('All systems operational')
      expect(response).to include('Battery at optimal levels')
    end

    it 'responds to how are you' do
      response = module_instance.handle_status_check('How are you doing?')
      expect(response).to include('All systems operational')
    end

    it 'returns nil for non-status messages' do
      response = module_instance.handle_status_check('Hello there')
      expect(response).to be_nil
    end
  end

  describe '#process' do
    let(:module_instance) { Object.new.extend(described_class) }
    let(:assistant) { double('assistant') }
    let(:conversation) { double('conversation') }

    it 'processes greeting messages' do
      response = module_instance.process('Hello!', assistant, conversation)
      expect(response).to include('Greetings from the Glitch Cube')
    end

    it 'processes status check messages' do
      response = module_instance.process('What is your status?', assistant, conversation)
      expect(response).to include('All systems operational')
    end

    it 'returns nil for unhandled messages' do
      response = module_instance.process('Random message', assistant, conversation)
      expect(response).to be_nil
    end
  end
end
