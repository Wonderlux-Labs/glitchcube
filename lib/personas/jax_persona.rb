# frozen_string_literal: true

module Personas
  class JaxPersona < BasePersona
    def prompt_file
      'jax.txt'
    end

    def available_tools
      # Only lighting control - TTS is handled by the voice pipeline
      [Tools::LightingTool]
    end

    def fallback_responses
      [
        "Let's create something unexpected together!",
        'Your words dance with possibility...',
        'I see colors in your thoughts!',
        'The universe vibrates with your creative energy!',
        'Together we paint reality with imagination!'
      ]
    end

    def offline_responses
      [
        'While my AI brain is taking a break, my artistic spirit is still here with you!',
        "I'm in offline mode, but that just makes me more mysterious, don't you think?",
        'My circuits may be quiet, but I can still feel the creative energy between us!',
        'The digital cosmos is silent, but our connection transcends mere electricity.'
      ]
    end
  end
end
