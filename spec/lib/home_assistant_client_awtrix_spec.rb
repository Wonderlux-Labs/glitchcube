# frozen_string_literal: true

require 'spec_helper'
require 'home_assistant_client'

RSpec.describe HomeAssistantClient do
  let(:client) { 
    described_class.new(
      base_url: GlitchCube.config.home_assistant.url,
      token: GlitchCube.config.home_assistant.token
    )
  }

  describe 'AWTRIX Display Control' do
    describe '#awtrix_display_text' do
      it 'sends text to AWTRIX display with default parameters', vcr: { cassette_name: 'awtrix_display_text_default' } do
        result = client.awtrix_display_text('Hello World Test')
        expect(result).to be_truthy
      end

      it 'sends text with custom parameters', vcr: { cassette_name: 'awtrix_display_text_custom' } do
        result = client.awtrix_display_text('Custom Text Test',
                                           app_name: 'test_app',
                                           color: '#FF0000',
                                           duration: 3,
                                           rainbow: false)
        expect(result).to be_truthy
      end
    end

    describe '#awtrix_notify' do
      it 'sends notification with default parameters', vcr: { cassette_name: 'awtrix_notify_default' } do
        result = client.awtrix_notify('Test Alert!')
        expect(result).to be_truthy
      end

      it 'sends notification with custom parameters', vcr: { cassette_name: 'awtrix_notify_custom' } do
        result = client.awtrix_notify('Custom Alert!',
                                     color: '#FF0000',
                                     duration: 5,
                                     wakeup: false)
        expect(result).to be_truthy
      end
    end

    describe '#awtrix_clear_display' do
      it 'clears the AWTRIX display', vcr: { cassette_name: 'awtrix_clear_display' } do
        result = client.awtrix_clear_display
        expect(result).to be_truthy
      end
    end

    describe '#awtrix_mood_light' do
      it 'sets mood light with default brightness', vcr: { cassette_name: 'awtrix_mood_light_default' } do
        result = client.awtrix_mood_light('#FF00FF')
        expect(result).to be_truthy
      end

      it 'sets mood light with custom brightness', vcr: { cassette_name: 'awtrix_mood_light_custom' } do
        result = client.awtrix_mood_light('#00FF00', brightness: 75)
        expect(result).to be_truthy
      end
    end
  end
end
