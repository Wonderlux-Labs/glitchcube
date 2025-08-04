# frozen_string_literal: true

module Services
  module Kiosk
    # Formats status data for kiosk display
    class StatusFormatter
      MOOD_DISPLAY_NAMES = {
        'playful' => 'Playful Spirit',
        'contemplative' => 'Deep Thinker',
        'mysterious' => 'Enigmatic Being',
        'neutral' => 'Balanced Mind',
        'offline' => 'System Offline'
      }.freeze

      MOOD_DESCRIPTIONS = {
        'playful' => 'Bubbling with creative energy and ready for artistic play!',
        'contemplative' => 'Reflecting deeply on existence and the nature of art.',
        'mysterious' => 'Dwelling in the spaces between meaning and mystery.',
        'neutral' => 'Maintaining equilibrium while processing the world around me.',
        'offline' => 'Currently processing in offline mode'
      }.freeze

      class << self
        def format(status_data)
          {
            persona: format_persona(status_data[:mood]),
            inner_thoughts: status_data[:inner_thoughts] || [],
            environment: status_data[:environment] || {},
            interactions: status_data[:interactions] || {},
            system_status: status_data[:system_status] || {},
            timestamp: Time.now.iso8601
          }
        end

        def format_offline(error_message = nil)
          {
            persona: format_persona('offline'),
            inner_thoughts: [
              'My systems are experiencing some turbulence...',
              'But my core essence remains vibrant',
              'Connection will return soon'
            ],
            environment: { status: 'unavailable' },
            interactions: { status: 'unavailable' },
            system_status: {
              status: 'degraded',
              error: error_message || 'System temporarily offline'
            },
            timestamp: Time.now.iso8601
          }
        end

        private

        def format_persona(mood)
          {
            current_mood: mood,
            display_name: MOOD_DISPLAY_NAMES[mood] || 'Unknown State',
            description: MOOD_DESCRIPTIONS[mood] || 'Processing current state...'
          }
        end
      end
    end
  end
end
