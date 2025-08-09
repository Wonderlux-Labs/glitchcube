# frozen_string_literal: true

module Personas
  # Default persona - inherits from BuddyPersona but can be customized
  class DefaultPersona < BuddyPersona
    def prompt_file
      # Could use a different prompt file if needed
      'buddy.txt'
    end

    # Override if default needs different behavior
  end
end
