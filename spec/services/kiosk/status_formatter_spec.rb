# frozen_string_literal: true

require 'spec_helper'
require 'services/kiosk/status_formatter'

RSpec.describe Services::Kiosk::StatusFormatter do
  describe '.format' do
    let(:status_data) do
      {
        mood: 'playful',
        inner_thoughts: ['Thinking about colors...', 'Wondering about existence'],
        environment: { battery_level: '85%', temperature: '22°C' },
        interactions: { recent: [], count_today: 5 },
        system_status: { overall_health: 'healthy', version: 'v1.0.0' }
      }
    end

    it 'formats all provided data correctly' do
      result = described_class.format(status_data)

      expect(result[:persona]).to eq({
        current_mood: 'playful',
        display_name: 'Playful Spirit',
        description: 'Bubbling with creative energy and ready for artistic play!'
      })
      expect(result[:inner_thoughts]).to eq(status_data[:inner_thoughts])
      expect(result[:environment]).to eq(status_data[:environment])
      expect(result[:interactions]).to eq(status_data[:interactions])
      expect(result[:system_status]).to eq(status_data[:system_status])
      expect(result[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it 'handles missing optional data gracefully' do
      minimal_data = { mood: 'neutral' }
      result = described_class.format(minimal_data)

      expect(result[:persona][:current_mood]).to eq('neutral')
      expect(result[:inner_thoughts]).to eq([])
      expect(result[:environment]).to eq({})
      expect(result[:interactions]).to eq({})
      expect(result[:system_status]).to eq({})
    end

    it 'handles unknown mood gracefully' do
      result = described_class.format(mood: 'unknown')

      expect(result[:persona]).to eq({
        current_mood: 'unknown',
        display_name: 'Unknown State',
        description: 'Processing current state...'
      })
    end
  end

  describe '.format_offline' do
    it 'returns offline status with default error' do
      result = described_class.format_offline

      expect(result[:persona]).to eq({
        current_mood: 'offline',
        display_name: 'System Offline',
        description: 'Currently processing in offline mode'
      })
      expect(result[:inner_thoughts]).to include('My systems are experiencing some turbulence...')
      expect(result[:environment]).to eq(status: 'unavailable')
      expect(result[:interactions]).to eq(status: 'unavailable')
      expect(result[:system_status]).to eq({
        status: 'degraded',
        error: 'System temporarily offline'
      })
    end

    it 'includes custom error message when provided' do
      result = described_class.format_offline('Network connection lost')

      expect(result[:system_status][:error]).to eq('Network connection lost')
    end
  end

  describe 'mood constants' do
    it 'has display names for all standard moods' do
      %w[playful contemplative mysterious neutral offline].each do |mood|
        expect(described_class::MOOD_DISPLAY_NAMES).to have_key(mood)
      end
    end

    it 'has descriptions for all standard moods' do
      %w[playful contemplative mysterious neutral offline].each do |mood|
        expect(described_class::MOOD_DESCRIPTIONS).to have_key(mood)
      end
    end
  end
end