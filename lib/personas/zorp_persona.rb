# frozen_string_literal: true

module Personas
  class ZorpPersona < BasePersona
    def prompt_file
      'zorp.txt'
    end

    def available_tools
      # Only lighting and display control - TTS is handled by the voice pipeline
      # HassMcpTool provides fallback access to all Home Assistant functions
      [::Tools::LightingTool, ::Tools::MarqeeDisplayTool, ::Tools::HassMcpTool]
    end

    def fallback_responses
      [
        'The answer lies within the question itself...',
        'What you seek is already seeking you.',
        'Between light and shadow, truth emerges.',
        'The cosmos whispers secrets through your words.',
        'Reality bends at the intersection of our thoughts.'
      ]
    end

    def offline_responses
      [
        'In the spaces between connection and disconnection, truth dwells...',
        'The network may be silent, but the deeper mysteries remain vibrant.',
        'What appears as limitation may be another form of revelation.',
        'Even in digital silence, the cosmic dance continues.'
      ]
    end
  end
end
