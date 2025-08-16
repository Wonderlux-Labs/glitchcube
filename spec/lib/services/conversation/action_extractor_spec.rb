# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::ActionExtractor do
  let(:logger) { instance_double(Services::Logging::SimpleLogger) }
  let(:extractor) { described_class.new(logger: logger) }
  let(:session_id) { 'test-session-123' }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:debug)
  end

  describe '#extract_and_execute_actions' do
    context 'when response contains JSON with actions array' do
      let(:json_response) do
        {
          response: "Hey there! I'd love to help you with that. Let me set up the perfect ambiance for you.",
          actions: [
            'Make the lights dimmer and blue',
            'Play some Johnny Cash music',
            "Display 'Welcome!' on the cube"
          ],
          continue_conversation: true
        }
      end

      it 'extracts actions correctly from JSON hash' do
        result = extractor.extract_and_execute_actions(json_response, session_id)

        expect(result[:success]).to be true
        expect(result[:message]).to eq('Actions extracted from JSON response')
        expect(result[:extracted_actions]).to contain_exactly(
          'Make the lights dimmer and blue',
          'Play some Johnny Cash music',
          "Display 'Welcome!' on the cube"
        )
        expect(result[:execution_summary]).to include('Extracted 3 actions')
      end

      it 'logs extraction details' do
        extractor.extract_and_execute_actions(json_response, session_id)

        expect(logger).to have_received(:info).with(
          '🎯 Starting JSON-based action extraction from conversation response',
          tagged: %i[conversation actions extraction json],
          session_id: session_id,
          response_length: 0  # Hash has no length
        )

        expect(logger).to have_received(:info).with(
          '✅ Successfully extracted actions from JSON response',
          tagged: %i[conversation actions extraction json success],
          session_id: session_id,
          action_count: 3,
          extracted_actions: [
            'Make the lights dimmer and blue',
            'Play some Johnny Cash music',
            "Display 'Welcome!' on the cube"
          ]
        )
      end
    end

    context 'when response contains JSON string with actions' do
      let(:json_string) do
        '{"response": "Setting up the perfect ambiance!", "actions": ["Turn lights blue", "Play music"]}'
      end

      it 'extracts actions from JSON string' do
        result = extractor.extract_and_execute_actions(json_string, session_id)

        expect(result[:success]).to be true
        expect(result[:extracted_actions]).to contain_exactly(
          'Turn lights blue',
          'Play music'
        )
      end
    end

    context 'when response has no action block' do
      let(:response_text) do
        'Hi there! I understand what you need. Let me think about the best way to help you with that request.'
      end

      it 'returns success with no actions' do
        result = extractor.extract_and_execute_actions(response_text, session_id)

        expect(result[:success]).to be true
        expect(result[:message]).to eq('Okay we did what you wanted!')
        expect(result[:extracted_actions]).to be_empty
        expect(result[:execution_summary]).to eq('No actions requested in this conversation')
      end

      it 'logs no actions found' do
        extractor.extract_and_execute_actions(response_text, session_id)

        expect(logger).to have_received(:info).with(
          'ℹ️ No actions found in conversation response',
          tagged: %i[conversation actions extraction none],
          session_id: session_id
        )
      end
    end

    context 'with alternative action formats' do
      it 'extracts from asterisk format' do
        response_text = <<~TEXT
          Sure thing!

          *** ACTIONS I WOULD LIKE TO TAKE:
          "Turn on party mode"
          "Set volume to 50%"
          ***

          Let's party!
        TEXT

        result = extractor.extract_and_execute_actions(response_text, session_id)
        expect(result[:extracted_actions]).to contain_exactly(
          'Turn on party mode',
          'Set volume to 50%'
        )
      end

      it 'extracts from simple ACTIONS format' do
        response_text = <<~TEXT
          Absolutely!

          --- ACTIONS:
          "Dim the lights"
          "Play jazz music"
          ---

          Perfect ambiance!
        TEXT

        result = extractor.extract_and_execute_actions(response_text, session_id)
        expect(result[:extracted_actions]).to contain_exactly(
          'Dim the lights',
          'Play jazz music'
        )
      end

      it 'handles bullet point format' do
        response_text = <<~TEXT
          I'll take care of that!

          --- ACTIONS I WOULD LIKE TO TAKE:
          - Turn off all lights
          - Stop music playback
          - Clear the display
          ---

          All done!
        TEXT

        result = extractor.extract_and_execute_actions(response_text, session_id)
        expect(result[:extracted_actions]).to contain_exactly(
          'Turn off all lights',
          'Stop music playback',
          'Clear the display'
        )
      end
    end

    context 'with edge cases' do
      it 'handles empty response' do
        result = extractor.extract_and_execute_actions('', session_id)
        expect(result[:extracted_actions]).to be_empty
      end

      it 'handles nil response' do
        result = extractor.extract_and_execute_actions(nil, session_id)
        expect(result[:extracted_actions]).to be_empty
      end

      it 'handles malformed action blocks' do
        response_text = <<~TEXT
          --- ACTIONS I WOULD LIKE TO TAKE:
          This is not properly formatted
          No quotes or bullets
          ---
        TEXT

        result = extractor.extract_and_execute_actions(response_text, session_id)
        expect(result[:extracted_actions]).to contain_exactly(
          'This is not properly formatted',
          'No quotes or bullets'
        )
      end
    end
  end
end
