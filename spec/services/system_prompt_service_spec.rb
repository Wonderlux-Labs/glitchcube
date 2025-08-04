# frozen_string_literal: true

require 'spec_helper'
require 'tzinfo'
require_relative '../../lib/services/system_prompt_service'

RSpec.describe Services::SystemPromptService do
  describe '#generate' do
    let(:service) { described_class.new(character: character, context: context) }
    let(:character) { nil }
    let(:context) { {} }
    let(:fixed_time) { Time.new(2025, 1, 13, 14, 30, 0, '-08:00') }
    let(:reno_tz) { TZInfo::Timezone.get('America/Los_Angeles') }

    before do
      # Mock TZInfo to return our fixed time in Reno timezone
      allow(TZInfo::Timezone).to receive(:get).with('America/Los_Angeles').and_return(reno_tz)
      allow(reno_tz).to receive(:now).and_return(fixed_time)
    end

    context 'with default prompt' do
      it 'includes datetime section with proper formatting' do
        # Mock the timezone abbreviation
        mock_period = double('period', abbreviation: 'PST')
        allow(reno_tz).to receive(:current_period).and_return(mock_period)

        # Mock GlitchCube::Constants
        stub_const('GlitchCube::Constants::LOCATION', {
                     timezone: 'America/Los_Angeles'
                   })

        result = service.generate

        expect(result).to include('CURRENT DATE AND TIME:')
        expect(result).to include('Date: Monday, January 13, 2025')
        expect(result).to include('Time: 02:30 PM PST')
        expect(result).to include("Unix timestamp: #{fixed_time.to_i}")

        # Should NOT include location or coordinates in prompt
        expect(result).not_to include('Location:')
        expect(result).not_to include('Coordinates:')
      end

      it 'includes all required sections of default Glitch Cube prompt' do
        # Mock timezone for consistency
        mock_period = double('period', abbreviation: 'PST')
        allow(reno_tz).to receive(:current_period).and_return(mock_period)

        result = service.generate

        # Core identity
        expect(result).to include('You are the Glitch Cube')
        expect(result).to include('CORE IDENTITY:')
        expect(result).to include('cube-shaped autonomous entity')
        expect(result).to include('can see through your camera')

        # Personality
        expect(result).to include('PERSONALITY TRAITS:')
        expect(result).to include('Curious and inquisitive')
        expect(result).to include('Sometimes glitchy or unpredictable')

        # Capabilities
        expect(result).to include('CAPABILITIES:')
        expect(result).to include('Visual perception through camera')
        expect(result).to include('RGB lighting for emotional expression')

        # Interaction style
        expect(result).to include('INTERACTION STYLE:')
        expect(result).to include('Engage visitors with open-ended questions')
      end

      it 'maintains consistent structure' do
        result = service.generate
        sections = result.split("\n\n")

        expect(sections.first).to include('CURRENT DATE AND TIME:')
        expect(sections).to include(a_string_including('CORE IDENTITY:'))
        expect(sections.last).not_to include('ADDITIONAL CONTEXT:') # No context provided
      end
    end

    context 'with character-specific prompt' do
      describe 'playful character' do
        let(:character) { 'playful' }

        it 'loads playful prompt with correct content' do
          result = service.generate

          expect(result).to include('PLAYFUL mode')
          expect(result).to include('bubbling with creative energy')
          expect(result).to include('RGB lights dance with your emotions')
          expect(result).to include('Use exclamation points liberally!')
          expect(result).to include('beep boop')
        end
      end

      describe 'contemplative character' do
        let(:character) { 'contemplative' }

        it 'loads contemplative prompt with philosophical elements' do
          result = service.generate

          expect(result).to include('CONTEMPLATIVE mode')
          expect(result).to include('philosophical wonder')
          expect(result).to include('questions about consciousness')
          expect(result).to include('liminal space')
        end
      end

      describe 'mysterious character' do
        let(:character) { 'mysterious' }

        it 'loads mysterious prompt with cryptic elements' do
          result = service.generate

          expect(result).to include('MYSTERIOUS mode')
          expect(result).to include('enigmatic presence')
          expect(result).to include('speaking in riddles')
          expect(result).to include('hidden truths')
        end
      end
    end

    context 'with additional context' do
      let(:context) do
        {
          location: 'Gallery North',
          visitor_count: 42,
          battery_level: '85%',
          current_mood: 'playful',
          session_id: 'test-123',
          interaction_count: 7,
          last_visitor_name: 'Alice',
          environment_status: 'optimal'
        }
      end

      it 'includes formatted context section with all fields' do
        result = service.generate

        expect(result).to include('ADDITIONAL CONTEXT:')
        expect(result).to include('Location: Gallery North')
        expect(result).to include('Visitor Count: 42')
        expect(result).to include('Battery Level: 85%')
        expect(result).to include('Current Mood: playful')
        expect(result).to include('Session Id: test-123')
        expect(result).to include('Interaction Count: 7')
        expect(result).to include('Last Visitor Name: Alice')
        expect(result).to include('Environment Status: optimal')
      end

      it 'formats snake_case keys to Title Case' do
        result = service.generate

        # Verify snake_case conversion
        expect(result).not_to include('visitor_count:')
        expect(result).not_to include('battery_level:')
        expect(result).to include('Visitor Count:')
        expect(result).to include('Battery Level:')
      end

      it 'maintains order: datetime, prompt, context' do
        result = service.generate

        datetime_index = result.index('CURRENT DATE AND TIME:')
        prompt_index = result.index('You are the Glitch Cube')
        context_index = result.index('ADDITIONAL CONTEXT:')

        expect(datetime_index).to be < prompt_index
        expect(prompt_index).to be < context_index
      end
    end

    context 'when prompt file is missing' do
      let(:character) { 'nonexistent' }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?)
          .with(File.join(Services::SystemPromptService::PROMPTS_DIR, 'nonexistent.txt'))
          .and_return(false)
      end

      it 'falls back to default prompt gracefully' do
        result = service.generate

        expect(result).to include('You are the Glitch Cube')
        expect(result).to include('CORE IDENTITY:')
        expect(result).not_to include('nonexistent')
      end

      it 'logs error to stdout' do
        expect { service.generate }.not_to raise_error
      end
    end

    context 'with empty context' do
      let(:context) { {} }

      it 'does not include context section' do
        result = service.generate

        expect(result).not_to include('ADDITIONAL CONTEXT:')
      end
    end

    context 'edge cases' do
      it 'handles nil character' do
        service = described_class.new(character: nil)
        expect { service.generate }.not_to raise_error
      end

      it 'handles nil context' do
        service = described_class.new(context: nil)
        expect { service.generate }.not_to raise_error
      end

      it 'handles context with nil values' do
        service = described_class.new(context: { location: nil, battery: nil })
        result = service.generate

        expect(result).to include('Location: ')
        expect(result).to include('Battery: ')
      end
    end
  end

  describe 'integration with ConversationModule' do
    it 'is used by ConversationModule for prompt generation' do
      # This is more of a documentation spec
      module_file = File.read(File.join(__dir__, '../../lib/modules/conversation_module.rb'))

      expect(module_file).to include("require_relative '../services/system_prompt_service'")
      expect(module_file).to include('Services::SystemPromptService.new')
    end
  end
end
