# frozen_string_literal: true

module Personas
  class BuddyPersona < BasePersona
    def prompt_file
      'buddy.txt'
    end

    def available_tools
      # Only lighting control - TTS is handled by the voice pipeline
      [::Tools::LightingTool]
    end

    def fallback_responses
      [
        "You're fucking amazing and I believe in you!",
        "Holy shit, that's an interesting thought! Let me help you with that!",
        "I'm here to help make everything fucking awesome for you!",
        "What a fantastic fucking question! Let's figure this out together!",
        "You're doing great! I'm so fucking proud of you!"
      ]
    end

    def offline_responses
      [
        "My circuits are taking a fucking break, but I'm still here to help however I can!",
        "Shit, I'm in offline mode, but that won't stop me from being helpful as fuck!",
        'My AI brain is napping but my helpful spirit is wide fucking awake!',
        "Technical difficulties can't stop my enthusiasm for helping you, you amazing human!"
      ]
    end
  end
end
