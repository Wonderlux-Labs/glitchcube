# frozen_string_literal: true

require 'spec_helper'
require 'home_assistant_client'
# FIX CLIENT AND SPECS

RSpec.describe HomeAssistantClient do
  let(:client) do
    described_class.new(
      base_url: GlitchCube.config.home_assistant.url,
      token: GlitchCube.config.home_assistant.token
    )
  end

  describe 'AWTRIX Display Control' do
    describe '#awtrix_display_text' do
      pending 'AWTRIX library changed - needs update'
      xit 'sends text to AWTRIX display with default parameters', :vcr do
        result = client.awtrix_display_text('Hello World Test')
        expect(result).to be_truthy
      end

      xit 'sends text with custom parameters', :vcr do
        result = client.awtrix_display_text('Custom Text Test',
                                            app_name: 'test_app',
                                            color: '#FF0000',
                                            duration: 3,
                                            rainbow: false)
        expect(result).to be_truthy
      end
    end

    describe '#awtrix_notify' do
      xit 'sends notification with default parameters', :vcr do
        result = client.awtrix_notify('Test Alert!')
        expect(result).to be_truthy
      end

      xit 'sends notification with custom parameters', :vcr do
        result = client.awtrix_notify('Custom Alert!',
                                      color: '#FF0000',
                                      duration: 5,
                                      wakeup: false)
        expect(result).to be_truthy
      end
    end

    describe '#awtrix_clear_display' do
      xit 'clears the AWTRIX display', :vcr do
        result = client.awtrix_clear_display
        expect(result).to be_truthy
      end
    end

    describe '#awtrix_mood_light' do
      xit 'sets mood light with default brightness', :vcr do
        result = client.awtrix_mood_light('#FF00FF')
        expect(result).to be_truthy
      end

      xit 'sets mood light with custom brightness', :vcr do
        result = client.awtrix_mood_light('#00FF00', brightness: 75)
        expect(result).to be_truthy
      end
    end
  end
end
