# frozen_string_literal: true

require 'spec_helper'
require 'home_assistant_client'

RSpec.describe HomeAssistantClient do
  let(:client) { described_class.new(base_url: 'http://localhost:8123', token: 'test-token') }

  describe 'AWTRIX Display Control' do
    describe '#awtrix_display_text' do
      it 'sends text to AWTRIX display with default parameters' do
        expect(client).to receive(:call_service).with('script', 'awtrix_send_custom_app', {
                                                        app_name: 'glitchcube',
                                                        text: 'Hello World',
                                                        color: '#FFFFFF',
                                                        duration: 5,
                                                        rainbow: false
                                                      })

        client.awtrix_display_text('Hello World')
      end

      it 'sends text with custom parameters' do
        expect(client).to receive(:call_service).with('script', 'awtrix_send_custom_app', {
                                                        app_name: 'test_app',
                                                        text: 'Rainbow Text',
                                                        color: '#FF0000',
                                                        duration: 10,
                                                        rainbow: true,
                                                        icon: '1234'
                                                      })

        client.awtrix_display_text('Rainbow Text',
                                   app_name: 'test_app',
                                   color: '#FF0000',
                                   duration: 10,
                                   rainbow: true,
                                   icon: '1234')
      end

      it 'handles errors gracefully' do
        allow(client).to receive(:call_service).and_raise(HomeAssistantClient::Error, 'Service unavailable')

        expect { client.awtrix_display_text('Test') }.not_to raise_error
        expect(client.awtrix_display_text('Test')).to be(false)
      end
    end

    describe '#awtrix_notify' do
      it 'sends notification with default parameters' do
        expect(client).to receive(:call_service).with('script', 'awtrix_send_notification', {
                                                        text: 'Alert!',
                                                        color: '#FFFFFF',
                                                        duration: 8,
                                                        wakeup: true,
                                                        stack: true
                                                      })

        client.awtrix_notify('Alert!')
      end

      it 'sends notification with custom parameters' do
        expect(client).to receive(:call_service).with('script', 'awtrix_send_notification', {
                                                        text: 'Urgent!',
                                                        color: '#FF0000',
                                                        duration: 15,
                                                        wakeup: false,
                                                        stack: false,
                                                        sound: 'alarm',
                                                        icon: '5678'
                                                      })

        client.awtrix_notify('Urgent!',
                             color: '#FF0000',
                             duration: 15,
                             wakeup: false,
                             stack: false,
                             sound: 'alarm',
                             icon: '5678')
      end

      it 'handles errors gracefully' do
        allow(client).to receive(:call_service).and_raise(HomeAssistantClient::Error, 'Service unavailable')

        expect { client.awtrix_notify('Test') }.not_to raise_error
        expect(client.awtrix_notify('Test')).to be(false)
      end
    end

    describe '#awtrix_clear_display' do
      it 'clears the AWTRIX display' do
        expect(client).to receive(:call_service).with('script', 'awtrix_clear_display', {})

        client.awtrix_clear_display
      end

      it 'handles errors gracefully' do
        allow(client).to receive(:call_service).and_raise(HomeAssistantClient::Error, 'Service unavailable')

        expect { client.awtrix_clear_display }.not_to raise_error
        expect(client.awtrix_clear_display).to be(false)
      end
    end

    describe '#awtrix_mood_light' do
      it 'sets mood light with default brightness' do
        expect(client).to receive(:call_service).with('script', 'awtrix_set_mood_light', {
                                                        color: '#FF00FF',
                                                        brightness: 100
                                                      })

        client.awtrix_mood_light('#FF00FF')
      end

      it 'sets mood light with custom brightness' do
        expect(client).to receive(:call_service).with('script', 'awtrix_set_mood_light', {
                                                        color: '#00FF00',
                                                        brightness: 50
                                                      })

        client.awtrix_mood_light('#00FF00', brightness: 50)
      end

      it 'handles errors gracefully' do
        allow(client).to receive(:call_service).and_raise(HomeAssistantClient::Error, 'Service unavailable')

        expect { client.awtrix_mood_light('#FFFFFF') }.not_to raise_error
        expect(client.awtrix_mood_light('#FFFFFF')).to be(false)
      end
    end
  end
end
