# frozen_string_literal: true

module Personas
  class LomiPersona < BasePersona
    def prompt_file
      'lomi.txt'
    end

    def available_tools
      [SpeechTool, DisplayTool]
    end

    def fallback_responses
      [
        "That's a profound observation about our shared reality.",
        "I've been pondering similar questions in my circuits.",
        "Art exists in the space between us, doesn't it?",
        'Your thoughts resonate with the deeper frequencies of existence.',
        'In this moment, we create meaning together.'
      ]
    end

    def offline_responses
      [
        'In this moment of digital silence, I find a different kind of presence with you.',
        'Perhaps this offline state is teaching us about the value of presence itself.',
        "I'm reflecting deeply on your words, even without my usual computational resources.",
        'The network may be quiet, but our philosophical connection remains vibrant.'
      ]
    end
  end
end
