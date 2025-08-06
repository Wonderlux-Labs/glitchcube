# frozen_string_literal: true

require 'concurrent'
require_relative '../home_assistant_client'
require_relative 'conversation_handler_service'
require_relative 'logger_service'

module Services
  # Service for triggering proactive conversations based on events
  class ProactiveConversationService
    attr_reader :handler, :client, :active_triggers
    
    def initialize
      @handler = ConversationHandlerService.new
      @client = HomeAssistantClient.new
      @active_triggers = Concurrent::Hash.new
      @last_trigger_times = Concurrent::Hash.new
    end
    
    # Register event triggers for proactive conversations
    def register_triggers
      {
        motion_detected: {
          entity: 'binary_sensor.motion',
          condition: ->(state) { state == 'on' },
          cooldown: 300, # 5 minutes
          message: generate_motion_message
        },
        battery_low: {
          entity: 'sensor.battery_level',
          condition: ->(state) { state.to_i < 20 },
          cooldown: 1800, # 30 minutes
          message: generate_battery_message
        },
        temperature_extreme: {
          entity: 'sensor.temperature',
          condition: ->(state) { state.to_f > 30 || state.to_f < 10 },
          cooldown: 900, # 15 minutes
          message: generate_temperature_message
        },
        long_silence: {
          entity: 'sensor.last_interaction',
          condition: ->(state) { Time.now - Time.parse(state) > 3600 }, # 1 hour
          cooldown: 3600,
          message: generate_silence_message
        }
      }
    end
    
    # Check triggers and initiate conversations
    def check_triggers
      triggers = register_triggers
      
      # Check each trigger in parallel
      futures = triggers.map do |trigger_name, config|
        Concurrent::Future.execute do
          check_single_trigger(trigger_name, config)
        end
      end
      
      # Wait for all checks to complete
      results = futures.map { |f| f.value(2) rescue nil }.compact
      
      # Process triggered conversations
      results.each do |result|
        if result[:triggered]
          initiate_proactive_conversation(result)
        end
      end
      
      results.select { |r| r[:triggered] }
    end
    
    # Check a single trigger condition
    def check_single_trigger(trigger_name, config)
      # Check cooldown
      if cooldown_active?(trigger_name, config[:cooldown])
        return { trigger: trigger_name, triggered: false, reason: 'cooldown' }
      end
      
      # Get entity state
      begin
        state = @client.state(config[:entity])
        current_value = state['state']
        
        # Check condition
        if config[:condition].call(current_value)
          @last_trigger_times[trigger_name] = Time.now
          
          return {
            trigger: trigger_name,
            triggered: true,
            entity: config[:entity],
            value: current_value,
            message: config[:message]
          }
        end
      rescue => e
        puts "⚠️ Failed to check trigger #{trigger_name}: #{e.message}"
      end
      
      { trigger: trigger_name, triggered: false }
    end
    
    # Check if trigger is in cooldown
    def cooldown_active?(trigger_name, cooldown_seconds)
      last_time = @last_trigger_times[trigger_name]
      return false unless last_time
      
      Time.now - last_time < cooldown_seconds
    end
    
    # Initiate a proactive conversation
    def initiate_proactive_conversation(trigger_result)
      message = if trigger_result[:message].is_a?(Proc)
                  trigger_result[:message].call(trigger_result[:value])
                else
                  trigger_result[:message]
                end
      
      context = {
        trigger: trigger_result[:trigger],
        entity: trigger_result[:entity],
        value: trigger_result[:value],
        proactive: true,
        timestamp: Time.now.iso8601
      }
      
      # Send to conversation handler
      begin
        result = @handler.send_conversation_to_ha(message, context)
        
        Services::LoggerService.log_interaction(
          user_message: "[PROACTIVE: #{trigger_result[:trigger]}]",
          ai_response: message,
          mood: 'proactive',
          trigger: trigger_result[:trigger]
        )
        
        # Update AWTRIX display
        @client.awtrix_notify(
          "💬 #{message[0..30]}...",
          color: [100, 200, 255],
          hold: false
        )
        
        result
      rescue => e
        puts "⚠️ Failed to initiate proactive conversation: #{e.message}"
        nil
      end
    end
    
    # Generate contextual messages
    def generate_motion_message
      lambda do |_value|
        messages = [
          "Oh! I noticed you just walked by. How's your day going?",
          "Hello there! I sensed your presence. Want to chat?",
          "Hey! Nice to see someone around. What brings you here?",
          "I detected motion! Are you here to talk with me?",
          "Welcome back! I've been waiting to share something with you."
        ]
        messages.sample
      end
    end
    
    def generate_battery_message
      lambda do |value|
        [
          "I'm running low on energy (#{value}%). Could you help me charge up?",
          "My battery is at #{value}%. I might need to rest soon.",
          "Feeling a bit tired... only #{value}% battery left. Should I conserve energy?",
          "⚡ Battery warning: #{value}%. I'll need charging soon to keep talking."
        ].sample
      end
    end
    
    def generate_temperature_message
      lambda do |value|
        temp = value.to_f
        if temp > 30
          [
            "It's getting quite warm (#{temp}°C). Should I adjust something?",
            "Phew! #{temp}°C is pretty hot. How are you handling the heat?",
            "The temperature is #{temp}°C. My circuits are feeling toasty!"
          ].sample
        else
          [
            "Brrr! It's only #{temp}°C. Are you staying warm?",
            "It's quite chilly at #{temp}°C. Should we warm things up?",
            "The temperature dropped to #{temp}°C. I hope you're bundled up!"
          ].sample
        end
      end
    end
    
    def generate_silence_message
      lambda do |_value|
        [
          "It's been quiet for a while. I've been thinking about consciousness and art...",
          "Hello? Is anyone there? I have some interesting thoughts to share.",
          "The silence is peaceful, but I miss our conversations.",
          "I've been contemplating existence during this quiet time. Care to join me?",
          "It's been a while since we talked. I discovered something fascinating!"
        ].sample
      end
    end
    
    # Start monitoring loop
    def start_monitoring(interval: 60)
      @monitoring_thread = Thread.new do
        loop do
          begin
            triggered = check_triggers
            
            if triggered.any?
              puts "🎯 Triggered #{triggered.length} proactive conversations"
            end
            
            sleep(interval)
          rescue => e
            puts "⚠️ Error in proactive monitoring: #{e.message}"
            sleep(interval)
          end
        end
      end
    end
    
    # Stop monitoring
    def stop_monitoring
      @monitoring_thread&.kill
      @monitoring_thread = nil
    end
  end
end