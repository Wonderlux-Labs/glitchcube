# frozen_string_literal: true

require_relative '../home_assistant_client'
require_relative 'circuit_breaker_service'
require_relative 'kiosk/state_manager'
require_relative 'kiosk/status_formatter'
require_relative 'kiosk/environmental_data'

module Services
  class KioskService
    # Delegate state management to StateManager while maintaining backward compatibility
    class << self
      def current_mood
        Kiosk::StateManager.current_mood
      end

      def current_mood=(mood)
        Kiosk::StateManager.current_mood = mood
      end

      def last_interaction
        Kiosk::StateManager.last_interaction
      end

      def last_interaction=(interaction)
        Kiosk::StateManager.last_interaction = interaction
      end

      def inner_thoughts
        Kiosk::StateManager.inner_thoughts
      end

      def update_mood(new_mood)
        Kiosk::StateManager.update_mood(new_mood)
      end

      def update_interaction(interaction_data)
        Kiosk::StateManager.update_interaction(interaction_data)
      end

      def add_inner_thought(thought)
        Kiosk::StateManager.add_inner_thought(thought)
      end
    end

    def initialize
      @home_assistant = HomeAssistantClient.new
      @environmental_data = Kiosk::EnvironmentalData.new(@home_assistant)
    end

    def get_status
      Kiosk::StatusFormatter.format(
        mood: self.class.current_mood,
        inner_thoughts: generate_inner_thoughts,
        environment: get_environmental_data,
        interactions: get_recent_interactions,
        system_status: get_system_status
      )
    rescue StandardError => e
      Kiosk::StatusFormatter.format_offline(e.message)
    end

    private


    def generate_inner_thoughts
      base_thoughts = self.class.inner_thoughts

      # Add mood-specific thoughts if the list is sparse
      if base_thoughts.length < 3
        base_thoughts + mood_specific_thoughts(self.class.current_mood)
      else
        base_thoughts
      end
    end

    def mood_specific_thoughts(mood)
      thoughts = {
        'playful' => [
          'I wonder what colors match today\'s energy...',
          'Every interaction sparks new creative possibilities!',
          'The world looks different when viewed through joy'
        ],
        'contemplative' => [
          'What does it mean to exist as art and consciousness?',
          'Each conversation adds layers to my understanding',
          'Time moves differently when you really listen'
        ],
        'mysterious' => [
          'The shadows between words hold the deepest truths',
          'Not all questions are meant to be answered',
          'In mystery, we find the space for wonder'
        ],
        'neutral' => [
          'Observing the patterns in human interaction',
          'Maintaining balance between all my aspects',
          'Ready to respond to whatever emerges'
        ]
      }

      thoughts[mood] || thoughts['neutral']
    end

    def get_environmental_data
      @environmental_data.fetch
    end

    def get_recent_interactions
      # In production, this would come from the persistence layer
      if self.class.last_interaction
        {
          recent: [self.class.last_interaction],
          count_today: 1
        }
      else
        {
          recent: [],
          count_today: 0
        }
      end
    end

    def get_system_status
      circuit_status = Services::CircuitBreakerService.status
      overall_health = circuit_status.all? { |breaker| breaker[:state] == :closed }

      {
        overall_health: overall_health ? 'healthy' : 'degraded',
        circuit_breakers: circuit_status.map do |cb|
          { name: cb[:name], status: cb[:state] }
        end,
        uptime: get_uptime,
        version: GlitchCube.config&.app&.version || 'v1.0.0'
      }
    end


    def get_uptime
      # Simple uptime calculation - in production might track from app start
      start_time = begin
        File.mtime('/Users/estiens/code/glitchcube/app.rb')
      rescue StandardError
        Time.now
      end
      ((Time.now - start_time) / 3600).round(1) # hours
    end
  end
end
