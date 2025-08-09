# frozen_string_literal: true

require_relative 'base_persona'
require_relative 'buddy_persona'
require_relative 'jax_persona'
require_relative 'lomi_persona'
require_relative 'zorp_persona'

module Personas
  class PersonaFactory
    PERSONA_MAP = {
      'buddy' => BuddyPersona,
      'jax' => JaxPersona,
      'lomi' => LomiPersona,
      'zorp' => ZorpPersona
    }.freeze

    DEFAULT_PERSONA = 'default'

    # Register all personas on load
    def self.register_all
      PERSONA_MAP.each do |name, klass|
        BasePersona.register_persona(name, klass)
      end
    end

    # Maintain backward compatibility
    class << self
      def create(persona_name, context = {})
        BasePersona.create(persona_name, context)
      end

      def available_personas
        BasePersona.available_personas
      end

      def persona_exists?(persona_name)
        BasePersona.persona_exists?(persona_name)
      end
    end
  end
end

# Auto-register personas on load
Personas::PersonaFactory.register_all
