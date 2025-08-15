# frozen_string_literal: true

require 'time'
require 'tzinfo'

module Services
  module Conversation
    class SystemPromptService
      PROMPTS_DIR = File.join(File.dirname(__FILE__), '../../../prompts')
      DEFAULT_PROMPT_FILE = 'default.txt'

      attr_reader :character, :context

      def initialize(character: nil, context: {})
        @character = character
        @context = context

        # Bridge to Persona system if character is provided
        return unless @character

        begin
          # Ensure personas are registered
          Personas::PersonaFactory.register_all unless Personas::BasePersona.available_personas.any?

          # Create persona instance for this character
          @persona = Personas::BasePersona.create(@character.to_s, @context)
        rescue StandardError => e
          # Fall back to nil if persona can't be created
          @logger&.warn("Could not create persona for character '#{@character}'",
                        tagged: %i[conversation persona_creation],
                        character: @character,
                        error: e.message,
                        backtrace: e.backtrace&.first)
          @persona = nil
        end
      end

      def generate
        # If we have a persona, delegate to it
        if @persona
          return @persona.generate_system_prompt
        end

        # Use the new composition system for consistent prompt building
        Services::Conversation::PromptCompositionService.build_system_prompt(
          persona: @character,
          context: @context
        )
      end

      # Legacy fallback method - kept for backward compatibility
      def default_glitch_cube_prompt
        # Use the composition service for consistency
        Services::Conversation::PromptCompositionService.build_system_prompt(
          persona: nil,
          context: @context || {}
        )
      end
    end
  end
end
