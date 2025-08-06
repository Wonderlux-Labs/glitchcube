# frozen_string_literal: true

require 'concurrent'
require_relative 'tts_service'
require_relative '../home_assistant_client'
require_relative 'logger_service'

module Services
  # Enhanced TTS service with parallel fallback and race conditions
  class ParallelTTSService < TTSService
    # Speak using fastest available provider (race multiple providers)
    def speak_race(
      message,
      providers: [:cloud, :google, :piper],
      **options
    )
      return false if message.nil? || message.strip.empty?
      
      start_time = Time.now
      
      # Create futures for each provider
      futures = providers.map do |provider|
        Concurrent::Future.execute do
          begin
            # Try this provider
            speak_with_provider(message, provider, **options)
          rescue => e
            { success: false, provider: provider, error: e.message }
          end
        end
      end
      
      # Wait for first success or all failures
      result = wait_for_first_success(futures, providers, timeout: 5)
      
      duration = ((Time.now - start_time) * 1000).round
      
      if result[:success]
        Services::LoggerService.log_tts(
          message: truncate_message(message),
          success: true,
          duration: duration,
          provider: result[:provider].to_s,
          mode: 'race'
        )
        true
      else
        Services::LoggerService.log_tts(
          message: truncate_message(message),
          success: false,
          duration: duration,
          error: 'All providers failed',
          mode: 'race'
        )
        false
      end
    end
    
    # Speak with cascading fallback (try providers in sequence with parallel preparation)
    def speak_cascade(
      message,
      providers: [:cloud, :google, :piper, :elevenlabs],
      **options
    )
      return false if message.nil? || message.strip.empty?
      
      start_time = Time.now
      success = false
      successful_provider = nil
      
      # Pre-warm all providers in parallel
      warm_up_providers(providers)
      
      # Try each provider with exponential backoff
      providers.each_with_index do |provider, index|
        begin
          # Add delay between attempts (exponential backoff)
          sleep(index * 0.5) if index > 0
          
          result = speak_with_provider(message, provider, **options)
          
          if result
            success = true
            successful_provider = provider
            break
          end
        rescue => e
          puts "⚠️ Provider #{provider} failed: #{e.message}"
          next
        end
      end
      
      duration = ((Time.now - start_time) * 1000).round
      
      Services::LoggerService.log_tts(
        message: truncate_message(message),
        success: success,
        duration: duration,
        provider: successful_provider&.to_s,
        mode: 'cascade'
      )
      
      success
    end
    
    # Speak with redundancy (send to multiple providers for reliability)
    def speak_redundant(
      message,
      providers: [:cloud, :google],
      **options
    )
      return false if message.nil? || message.strip.empty?
      
      start_time = Time.now
      
      # Send to all providers in parallel
      futures = providers.map do |provider|
        Concurrent::Future.execute do
          speak_with_provider(message, provider, **options)
        end
      end
      
      # Wait for all to complete (with timeout)
      results = []
      futures.each_with_index do |future, index|
        begin
          result = future.value(3) # 3 second timeout
          results << { provider: providers[index], success: result }
        rescue => e
          results << { provider: providers[index], success: false, error: e.message }
        end
      end
      
      # Success if any provider succeeded
      success = results.any? { |r| r[:success] }
      successful_providers = results.select { |r| r[:success] }.map { |r| r[:provider] }
      
      duration = ((Time.now - start_time) * 1000).round
      
      Services::LoggerService.log_tts(
        message: truncate_message(message),
        success: success,
        duration: duration,
        provider: successful_providers.join(','),
        mode: 'redundant'
      )
      
      success
    end
    
    # Intelligent speak that chooses strategy based on priority
    def speak_intelligent(
      message,
      priority: :normal,
      **options
    )
      case priority
      when :critical
        # Use redundancy for critical messages
        speak_redundant(message, providers: [:cloud, :google, :piper], **options)
      when :fast
        # Use race for fastest response
        speak_race(message, providers: [:cloud, :google], **options)
      when :reliable
        # Use cascade with all providers
        speak_cascade(message, providers: [:cloud, :google, :piper, :elevenlabs], **options)
      else
        # Normal priority - try cloud then fallback
        speak(message, provider: :cloud, **options) ||
          speak(message, provider: :google, **options)
      end
    end
    
    private
    
    def speak_with_provider(message, provider, **options)
      # Use parent class method with specific provider
      speak(message, provider: provider, **options.except(:providers))
    end
    
    def wait_for_first_success(futures, providers, timeout: 5)
      end_time = Time.now + timeout
      
      while Time.now < end_time
        futures.each_with_index do |future, index|
          if future.fulfilled?
            result = future.value
            if result.is_a?(Hash) && !result[:success]
              next # This one failed
            else
              # This one succeeded!
              return { success: true, provider: providers[index], result: result }
            end
          end
        end
        
        # Check if all have failed
        if futures.all? { |f| f.rejected? || (f.fulfilled? && f.value.is_a?(Hash) && !f.value[:success]) }
          break
        end
        
        sleep(0.1) # Small delay before checking again
      end
      
      # All failed or timed out
      { success: false, providers: providers }
    end
    
    def warm_up_providers(providers)
      # Pre-warm providers in parallel (just check availability)
      Concurrent::Future.execute do
        providers.each do |provider|
          begin
            # Just check if provider is available
            provider_id = PROVIDERS[provider]
            next unless provider_id
            
            # Could ping the service here if needed
          rescue => e
            puts "⚠️ Provider #{provider} not available for warm-up: #{e.message}"
          end
        end
      end
    end
  end
end