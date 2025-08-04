# frozen_string_literal: true

require_relative '../home_assistant_client'
require_relative 'circuit_breaker_service'

module Services
  class KioskService
    # Current mood state - in production this would come from session/persistence
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
        add_inner_thought("Just had an interesting conversation...")
      end

      def add_inner_thought(thought)
        @inner_thoughts = [@inner_thoughts, thought].flatten.compact.last(5)
      end
    end

    def initialize
      @home_assistant = HomeAssistantClient.new
    end

    def get_status
      {
        persona: {
          current_mood: self.class.current_mood,
          display_name: mood_display_name(self.class.current_mood),
          description: mood_description(self.class.current_mood)
        },
        inner_thoughts: generate_inner_thoughts,
        environment: get_environmental_data,
        interactions: get_recent_interactions,
        system_status: get_system_status,
        timestamp: Time.now.iso8601
      }
    rescue StandardError => e
      # Fallback data if services are unavailable
      {
        persona: {
          current_mood: 'offline',
          display_name: 'System Offline',
          description: 'Currently processing in offline mode'
        },
        inner_thoughts: [
          'My systems are experiencing some turbulence...',
          'But my core essence remains vibrant',
          'Connection will return soon'
        ],
        environment: { status: 'unavailable' },
        interactions: { status: 'unavailable' },
        system_status: { 
          status: 'degraded',
          error: e.message 
        },
        timestamp: Time.now.iso8601
      }
    end

    private

    def mood_display_name(mood)
      case mood
      when 'playful'
        'Playful Spirit'
      when 'contemplative'
        'Deep Thinker'
      when 'mysterious'
        'Enigmatic Being'
      when 'neutral'
        'Balanced Mind'
      else
        'Unknown State'
      end
    end

    def mood_description(mood)
      case mood
      when 'playful'
        'Bubbling with creative energy and ready for artistic play!'
      when 'contemplative'
        'Reflecting deeply on existence and the nature of art.'
      when 'mysterious'
        'Dwelling in the spaces between meaning and mystery.'
      when 'neutral'
        'Maintaining equilibrium while processing the world around me.'
      else
        'Processing current state...'
      end
    end

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
      begin
        states = Services::CircuitBreakerService.home_assistant_breaker.call do
          @home_assistant.states
        end

        # Extract relevant sensor data
        {
          battery_level: extract_sensor_value(states, 'sensor.battery_level', '%'),
          temperature: extract_sensor_value(states, 'sensor.temperature', '°C'),
          motion_detected: extract_binary_sensor(states, 'binary_sensor.motion'),
          lighting_status: extract_light_status(states, 'light.glitch_cube'),
          last_updated: Time.now.iso8601
        }
      rescue CircuitBreaker::CircuitOpenError
        { status: 'circuit_open', message: 'Home Assistant temporarily unavailable' }
      rescue StandardError => e
        { status: 'error', message: e.message }
      end
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
        circuit_breakers: circuit_status.map { |cb| 
          { name: cb[:name], status: cb[:state] }
        },
        uptime: get_uptime,
        version: GlitchCube.config&.app&.version || 'v1.0.0'
      }
    end

    def extract_sensor_value(states, entity_id, unit = nil)
      entity = states.find { |s| s['entity_id'] == entity_id }
      return nil unless entity

      value = entity['state']
      unit ? "#{value}#{unit}" : value
    end

    def extract_binary_sensor(states, entity_id)
      entity = states.find { |s| s['entity_id'] == entity_id }
      return nil unless entity

      entity['state'] == 'on'
    end

    def extract_light_status(states, entity_id)
      entity = states.find { |s| s['entity_id'] == entity_id }
      return nil unless entity

      {
        state: entity['state'],
        brightness: entity.dig('attributes', 'brightness'),
        color: entity.dig('attributes', 'rgb_color')
      }
    end

    def get_uptime
      # Simple uptime calculation - in production might track from app start
      start_time = File.mtime('/Users/estiens/code/glitchcube/app.rb') rescue Time.now
      ((Time.now - start_time) / 3600).round(1) # hours
    end
  end
end