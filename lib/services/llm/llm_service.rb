# frozen_string_literal: true

require 'open_router'
require_relative 'llm_response'
require_relative 'components/response_parser'
require_relative 'components/error_handler'
require_relative 'components/retry_handler'

module Services
  # Clean LLM wrapper service using OpenRouter gem directly
  # Handles all AI model interactions with proper logging and error handling
  class LLMService
    class LLMError < StandardError; end
    class RateLimitError < LLMError; end
    class AuthenticationError < LLMError; end
    class ModelNotFoundError < LLMError; end

    class << self
      # Simple completion with system prompt and user message
      def complete(system_prompt:, user_message:, model: nil, **)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user', content: user_message }
        ]

        complete_with_messages(messages: messages, model: model, **)
      end

      # Completion with full message history
      def complete_with_messages(messages:, model: nil, **options)
        model ||= GlitchCube.config.ai.default_model

        # Validate model isn't blacklisted
        validate_model!(model)

        # Build request parameters
        params = build_params(messages, model, options)

        # Make API call with circuit breaker and retry logic
        response = with_retry_logic(model: model, max_attempts: 3) do
          with_circuit_breaker do
            with_timeout(options[:timeout] || 30) do
              make_api_call(params)
            end
          end
        end

        # Parse and return response
        parse_response(response, model, options)
      rescue StandardError => e
        if GlitchCube.config.debug?
          Services::Logging::SimpleLogger.debug(
            'LLM error details',
            tagged: %i[llm error debug],
            error_class: e.class.name,
            error_message: e.message,
            backtrace: e.backtrace&.first(3)
          )
        end
        handle_error(e)
      end

      # Define convenience methods for common model presets
      # Using explicit method definitions for better RSpec compatibility
      def complete_cheap_tools(prompt, **options)
        model = GlitchCube::ModelPresets.get_model(:cheap_tools)
        if options[:user_message]
          complete(system_prompt: prompt, user_message: options.delete(:user_message), model: model, **options)
        else
          complete(system_prompt: prompt, user_message: '', model: model, **options)
        end
      end

      def complete_cheap_no_tools(prompt, **options)
        model = GlitchCube::ModelPresets.get_model(:cheap_no_tools)
        if options[:user_message]
          complete(system_prompt: prompt, user_message: options.delete(:user_message), model: model, **options)
        else
          complete(system_prompt: prompt, user_message: '', model: model, **options)
        end
      end

      def complete_conversation(prompt, **options)
        model = GlitchCube::ModelPresets.get_model(:conversation)
        if options[:user_message]
          complete(system_prompt: prompt, user_message: options.delete(:user_message), model: model, **options)
        else
          complete(system_prompt: prompt, user_message: '', model: model, **options)
        end
      end

      def complete_premium(prompt, **options)
        model = GlitchCube::ModelPresets.get_model(:premium)
        if options[:user_message]
          complete(system_prompt: prompt, user_message: options.delete(:user_message), model: model, **options)
        else
          complete(system_prompt: prompt, user_message: '', model: model, **options)
        end
      end

      def analyze_image(prompt, **options)
        model = GlitchCube::ModelPresets.get_model(:multimodel)
        if options[:user_message]
          complete(system_prompt: prompt, user_message: options.delete(:user_message), model: model, **options)
        else
          complete(system_prompt: prompt, user_message: '', model: model, **options)
        end
      end

      # Get available models (cached)
      def available_models
        @models_cache ||= {}
        cache_key = 'available_models'

        # Return cached if fresh (1 hour)
        return @models_cache[cache_key][:data] if @models_cache[cache_key] && @models_cache[cache_key][:expires_at] > Time.now

        # Fetch fresh models
        models = with_circuit_breaker do
          client.models
        end

        # Cache the result
        @models_cache[cache_key] = {
          data: models,
          expires_at: Time.now + 3600
        }

        models
      rescue StandardError => e
        handle_error(e)
      end

      # Clear model cache
      def clear_cache!
        @models_cache = {}
      end

      private

      def client
        # Configure OpenRouter with proper settings
        if GlitchCube.config.helicone_api_key
          # When using Helicone, we need to set the base URL without /v1
          # The gem will add /v1 in the uri method
          ::OpenRouter.configure do |config|
            config.access_token = GlitchCube.config.openrouter_api_key
            config.uri_base = 'https://openrouter.helicone.ai/api'
            config.api_version = 'v1'
            config.extra_headers = {
              'Helicone-Auth' => "Bearer #{GlitchCube.config.helicone_api_key}"
            }
          end
        else
          # Standard OpenRouter configuration
          ::OpenRouter.configure do |config|
            config.access_token = GlitchCube.config.openrouter_api_key
            # Use defaults for uri_base and api_version
            config.extra_headers = {}
          end
        end

        @client ||= ::OpenRouter::Client.new
      end

      def build_params(messages, model, options)
        extras = {
          temperature: options[:temperature] || GlitchCube.config.ai.temperature,
          max_tokens: options[:max_tokens] || GlitchCube.config.ai.max_tokens,
          top_p: options[:top_p],
          frequency_penalty: options[:frequency_penalty],
          presence_penalty: options[:presence_penalty],
          stop: options[:stop],
          seed: options[:seed],
          stream: options[:stream] || false
        }.compact

        # Add structured output support
        extras[:response_format] = options[:response_format] if options[:response_format]

        # Add tool/function calling support
        if options[:tools]
          extras[:tools] = options[:tools]
          extras[:tool_choice] = options[:tool_choice] || 'auto'
        end

        # Add parallel tool calls support (OpenAI models)
        extras[:parallel_tool_calls] = options[:parallel_tool_calls] unless options[:parallel_tool_calls].nil?

        # Add provider-specific options
        extras[:provider] = options[:provider] if options[:provider]

        # Add transforms for cost optimization
        extras[:transforms] = options[:transforms] if options[:transforms]

        # Add reasoning tokens support (OpenRouter)
        extras[:reasoning] = options[:reasoning] if options[:reasoning]

        {
          messages: messages,
          model: model,
          extras: extras
        }
      end

      def make_api_call(params)
        start_time = Time.now

        # Log the request
        log_api_request(params)

        # Consolidated request logging
        if GlitchCube.config.debug?
          Services::Logging::SimpleLogger.debug(
            'LLM API REQUEST',
            tagged: %i[llm api_request],
            model: params[:model],
            message_count: params[:messages].size,
            extras: params[:extras]
          )
        end

        # Detailed request logging for debugging (only when debug mode is on)
        if GlitchCube.config.debug?
          request_payload = {
            messages: params[:messages],
            model: params[:model],
            **params[:extras]
          }

          Services::Logging::SimpleLogger.debug(
            'RAW HTTP REQUEST',
            tagged: %i[llm raw_request],
            url: 'https://openrouter.ai/api/v1/chat/completions',
            model: params[:model],
            payload: request_payload
          )
        end

        # Make the actual API call using the gem's signature:
        # complete(messages, model: 'model', extras: { all other params })
        response = client.complete(
          params[:messages],
          model: params[:model],
          extras: params[:extras]
        )

        # Detailed response logging for debugging (only when debug mode is on)
        if GlitchCube.config.debug?
          Services::Logging::SimpleLogger.debug(
            'RAW HTTP RESPONSE',
            tagged: %i[llm raw_response],
            status: 200,
            response_class: response.class.name,
            full_response: response
          )
        end

        # Consolidated response logging
        if GlitchCube.config.debug? && response.respond_to?(:[]) && response[:choices]
          choice = response[:choices]&.first
          if choice
            Services::Logging::SimpleLogger.debug(
              'LLM RESPONSE DETAILS',
              tagged: %i[llm api_response],
              finish_reason: choice[:finish_reason],
              has_content: !choice.dig(:message, :content).nil?,
              content_length: (choice.dig(:message, :content) || '').length,
              has_tool_calls: !choice.dig(:message, :tool_calls).nil?,
              tool_calls_count: (choice.dig(:message, :tool_calls) || []).size
            )
          end
        end

        # Log the response
        duration = ((Time.now - start_time) * 1000).round
        log_api_response(response, params[:model], duration)

        response
      end

      def parse_response(response, model, options = {})
        # Delegate to ResponseParser for cleaner separation of concerns
        LLM::ResponseParser.parse(response, model, options)
      end

      def validate_model!(model)
        # Check against blacklist if ModelPresets is available
        return unless defined?(GlitchCube::ModelPresets)

        GlitchCube::ModelPresets.validate_model!(model)
      end

      def with_circuit_breaker(&)
        # Bypass circuit breaker in test environment unless explicitly testing circuit breakers
        return yield if GlitchCube.config.test? && !GlitchCube.config.enable_circuit_breakers

        Services::CircuitBreakerService.openrouter_breaker.call(&)
      rescue CircuitBreaker::CircuitOpenError => e
        raise LLMError, "OpenRouter service temporarily unavailable: #{e.message}"
      end

      def with_timeout(seconds, &)
        Timeout.timeout(seconds, &)
      rescue Timeout::Error
        raise LLMError, "Request timed out after #{seconds} seconds"
      end

      def with_retry_logic(model:, max_attempts: 3, &)
        # Delegate to RetryHandler component for cleaner separation of concerns
        LLM::RetryHandler.with_retry_logic(model: model, max_attempts: max_attempts, &)
      end

      def handle_error(error)
        # Delegate to ErrorHandler for cleaner separation of concerns
        LLM::ErrorHandler.handle_error(error)
      end

      # Removed - delegated to ErrorHandler component

      # Removed - delegated to ErrorHandler component

      def log_api_request(params)
        Services::LoggerService.log_api_call(
          service: 'openrouter',
          endpoint: '/chat/completions',
          method: 'POST',
          model: params[:model],
          message_count: params[:messages].size,
          temperature: params[:extras][:temperature],
          max_tokens: params[:extras][:max_tokens],
          full_request_payload: params  # Log the complete request to see what we're sending
        )
      end

      def log_api_response(response, model, duration)
        # Extract usage and content using safe extraction
        usage = safe_extract(response) do |r|
          usage_data = r[:usage] || r['usage'] || {}
          {
            prompt_tokens: usage_data[:prompt_tokens] || usage_data['prompt_tokens'] || 0,
            completion_tokens: usage_data[:completion_tokens] || usage_data['completion_tokens'] || 0,
            total_tokens: usage_data[:total_tokens] || usage_data['total_tokens'] || 0
          }
        end

        content = safe_extract(response) do |r|
          if r.respond_to?(:dig)
            r.dig(:choices, 0, :message, :content) ||
              r.dig('choices', 0, 'message', 'content') ||
              r[:content] || r['content'] || ''
          else
            ''
          end
        end

        Services::LoggerService.log_api_call(
          service: 'openrouter',
          endpoint: '/chat/completions',
          method: 'POST',
          status: 200,
          duration: duration,
          model: safe_extract(response) { |r| r[:model] || r['model'] } || model,
          usage: usage,
          response_length: content.to_s.length
        )
      end

      # Safe extraction helper that handles any response type
      def safe_extract(response)
        # If it's already a hash-like object, use it
        if response.respond_to?(:[]) && response.respond_to?(:dig)
          yield(response)
        # If it's a string, try to parse as JSON
        elsif response.is_a?(String)
          begin
            parsed = JSON.parse(response)
            yield(parsed)
          rescue JSON::ParserError
            # If parsing fails, yield the string itself
            yield(response)
          end
        else
          # For any other type, convert to string and yield
          yield(response.to_s)
        end
      rescue StandardError => e
      end

      # Safe dig that works with both symbol and string keys
      def safe_dig(hash, *keys)
        return nil unless hash.respond_to?(:dig)

        # Try with the keys as given
        result = hash.dig(*keys)
        return result if result

        # If keys are symbols, try with strings
        if keys.all? { |k| k.is_a?(Symbol) }
          string_keys = keys.map(&:to_s)
          result = hash.dig(*string_keys)
          return result if result
        end

        # If keys are strings, try with symbols
        if keys.all? { |k| k.is_a?(String) }
          symbol_keys = keys.map(&:to_sym)
          result = hash.dig(*symbol_keys)
          return result if result
        end

        nil
      rescue StandardError
        nil
      end
    end
  end
end
