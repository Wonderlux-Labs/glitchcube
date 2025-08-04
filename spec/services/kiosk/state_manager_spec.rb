# frozen_string_literal: true

require 'spec_helper'
require 'services/kiosk/state_manager'

RSpec.describe Services::Kiosk::StateManager do
  before(:each) do
    described_class.reset!
  end

  describe 'class methods' do
    describe '.current_mood' do
      it 'defaults to neutral' do
        expect(described_class.current_mood).to eq('neutral')
      end
    end

    describe '.update_mood' do
      it 'updates the current mood' do
        described_class.update_mood('playful')
        expect(described_class.current_mood).to eq('playful')
      end

      it 'adds an inner thought about the mood change' do
        described_class.update_mood('contemplative')
        expect(described_class.inner_thoughts).to include('Mood shifted to contemplative')
      end
    end

    describe '.update_interaction' do
      let(:interaction_data) do
        {
          message: 'Hello!',
          response: 'Greetings, creative soul!'
        }
      end

      it 'stores the interaction with timestamp' do
        described_class.update_interaction(interaction_data)
        
        last = described_class.last_interaction
        expect(last[:message]).to eq('Hello!')
        expect(last[:response]).to eq('Greetings, creative soul!')
        expect(last[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it 'adds an inner thought about the conversation' do
        described_class.update_interaction(interaction_data)
        expect(described_class.inner_thoughts).to include('Just had an interesting conversation...')
      end
    end

    describe '.add_inner_thought' do
      it 'adds a thought to the list' do
        described_class.add_inner_thought('Processing the universe...')
        expect(described_class.inner_thoughts).to include('Processing the universe...')
      end

      it 'maintains only the last 5 thoughts' do
        6.times { |i| described_class.add_inner_thought("Thought #{i}") }
        
        expect(described_class.inner_thoughts.size).to eq(5)
        expect(described_class.inner_thoughts).not_to include('Thought 0')
        expect(described_class.inner_thoughts).to include('Thought 5')
      end

      it 'handles nil and empty arrays gracefully' do
        described_class.add_inner_thought(nil)
        expect(described_class.inner_thoughts).to be_empty

        described_class.add_inner_thought('Valid thought')
        expect(described_class.inner_thoughts).to eq(['Valid thought'])
      end
    end

    describe '.reset!' do
      it 'resets all state to defaults' do
        described_class.update_mood('playful')
        described_class.update_interaction(message: 'test', response: 'test')
        described_class.add_inner_thought('Test thought')

        described_class.reset!

        expect(described_class.current_mood).to eq('neutral')
        expect(described_class.last_interaction).to be_nil
        expect(described_class.inner_thoughts).to be_empty
      end
    end
  end
end