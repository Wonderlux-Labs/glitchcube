# frozen_string_literal: true

module Services
  module Kiosk
    # Manages state for the kiosk display including mood, interactions, and inner thoughts
    class StateManager
      @current_mood = 'neutral'
      @last_interaction = nil
      @inner_thoughts = []

      class << self
        attr_accessor :current_mood, :last_interaction
        attr_reader :inner_thoughts

        def update_mood(new_mood)
          @current_mood = new_mood
          add_inner_thought("Mood shifted to #{new_mood}")
        end

        def update_interaction(interaction_data)
          @last_interaction = {
            message: interaction_data[:message],
            response: interaction_data[:response],
            timestamp: Time.now.iso8601
          }
          add_inner_thought('Just had an interesting conversation...')
        end

        def add_inner_thought(thought)
          @inner_thoughts = [@inner_thoughts, thought].flatten.compact.last(5)
        end

        def reset!
          @current_mood = 'neutral'
          @last_interaction = nil
          @inner_thoughts = []
        end
      end
    end
  end
end