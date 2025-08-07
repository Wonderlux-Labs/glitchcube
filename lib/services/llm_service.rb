# frozen_string_literal: true

require 'open_router'
require_relative 'logger_service'
require_relative 'circuit_breaker_service'
require_relative 'llm_response'

module Services
  # Clean LLM wrapper service using OpenRouter gem directly
  # Handles all AI model interactions with proper logging and error handling
  class LLMService
    class LLMError < StandardError; end
    class RateLimitError < LLMError; end
    class AuthenticationError < LLMError; end
    class ModelNotFoundError < LLMError; end

    DEFAULT_MODEL = 'openrouter/auto'
    DEFAULT_TEMPERATURE = 0.7
    DEFAULT_MAX_TOKENS = 500

    class << self
      # Simple completion with system prompt and user message
      def complete(system_prompt:, user_message:, model: nil, **options)
        messages = [
          { role: 'system', content: system_prompt },
          { role: 'user', content: user_message }
        ]

        complete_with_messages(messages: messages, model: model, **options)
      end

      # Completion with full message history
      def complete_with_messages(messages:, model: nil, **options)
        model ||= GlitchCube.config.ai.default_model || DEFAULT_MODEL

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
        parse_response(response, model)
      rescue StandardError => e
        puts "DEBUG: Original error class: #{e.class}" if GlitchCube.config.debug?
        puts "DEBUG: Original error message: #{e.message}" if GlitchCube.config.debug?
        puts "DEBUG: Original error backtrace: #{e.backtrace.first(3).join("\n")}" if GlitchCube.config.debug?
        handle_error(e)
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
          temperature: options[:temperature] || DEFAULT_TEMPERATURE,
          max_tokens: options[:max_tokens] || DEFAULT_MAX_TOKENS,
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

        puts "DEBUG: Calling complete with model: #{params[:model]}" if GlitchCube.config.debug?
        puts "DEBUG: Extras: #{params[:extras].inspect}" if GlitchCube.config.debug?

        # Make the actual API call using the gem's signature:
        # complete(messages, model: 'model', extras: { all other params })
        response = client.complete(
          params[:messages],
          model: params[:model],
          extras: params[:extras]
        )

        puts "DEBUG: Response class: #{response.class}" if GlitchCube.config.debug?
        puts "DEBUG: Response: #{response.inspect[0..500]}" if GlitchCube.config.debug?

        # Log the response
        duration = ((Time.now - start_time) * 1000).round
        log_api_response(response, params[:model], duration)

        response
      end

      def parse_response(response, model)
        # Safely extract model from response
        response_model = safe_extract(response) { |r| r[:model] || r['model'] } || model

        # Return LLMResponse object for cleaner API
        LLMResponse.new(
          raw_response: response,
          model: response_model,
          content: extract_content(response),
          usage: extract_usage(response),
          tool_calls: extract_tool_calls(response)
        )
      end

      def extract_content(response)
        safe_extract(response) do |r|
          return r if r.is_a?(String)

          # Try standard OpenAI format
          if r[:choices].is_a?(Array) && !r[:choices].empty?
            choice = r[:choices].first
            if choice.is_a?(Hash)
              safe_dig(choice, :message, :content) || safe_dig(choice, 'message', 'content') || ''
            else
              ''
            end
          else
            # Fallback for direct content
            r[:content] || r['content'] || ''
          end
        end
      end

      def extract_usage(response)
        safe_extract(response) do |r|
          return { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 } if r.is_a?(String)

          usage = r[:usage] || r['usage'] || {}

          {
            prompt_tokens: usage[:prompt_tokens] || usage['prompt_tokens'] || 0,
            completion_tokens: usage[:completion_tokens] || usage['completion_tokens'] || 0,
            total_tokens: usage[:total_tokens] || usage['total_tokens'] || 0
          }
        end
      end

      def extract_tool_calls(response)
        safe_extract(response) do |r|
          return nil if r.is_a?(String)
          return nil unless r[:choices].is_a?(Array)

          choice = r[:choices].first
          return nil unless choice.is_a?(Hash)

          message = choice[:message] || choice['message']
          return nil unless message

          tool_calls = message[:tool_calls] || message['tool_calls']
          return nil unless tool_calls.is_a?(Array)

          # Format tool calls for easier consumption
          tool_calls.map do |tool_call|
            func = tool_call[:function] || tool_call['function']
            next unless func

            {
              id: tool_call[:id] || tool_call['id'],
              type: tool_call[:type] || tool_call['type'] || 'function',
              function: {
                name: func[:name] || func['name'],
                arguments: func[:arguments] || func['arguments']
              }
            }
          end.compact
        end
      end

      def validate_model!(model)
        # Check against blacklist if ModelPresets is available
        return unless defined?(GlitchCube::ModelPresets)

        GlitchCube::ModelPresets.validate_model!(model)
      end

      def with_circuit_breaker(&block)
        # Bypass circuit breaker in test environment unless explicitly testing circuit breakers
        return yield if GlitchCube.config.test? && !ENV['ENABLE_CIRCUIT_BREAKERS']
        
        Services::CircuitBreakerService.openrouter_breaker.call(&block)
      rescue CircuitBreaker::CircuitOpenError => e
        raise LLMError, "OpenRouter service temporarily unavailable: #{e.message}"
      end

      def with_timeout(seconds, &)
        Timeout.timeout(seconds, &)
      rescue Timeout::Error
        raise LLMError, "Request timed out after #{seconds} seconds"
      end

      def with_retry_logic(model:, max_attempts: 3)
        # Disable retries in test environment unless explicitly testing retries
        max_attempts = 1 if GlitchCube.config.test? && !ENV['ENABLE_RETRIES']
        
        attempt = 0
        delay = 1.0
        last_error = nil

        begin
          attempt += 1
          puts "🔄 LLM API attempt #{attempt}/#{max_attempts} for model: #{model}" if attempt > 1

          result = yield

          puts "✅ LLM API call succeeded on attempt #{attempt}" if attempt > 1
          return result
        rescue RateLimitError => e
          last_error = e
          if attempt < max_attempts
            # Longer wait for rate limits
            wait_time = delay * 2
            puts "⏳ Rate limited - waiting #{wait_time}s before retry..."
            sleep(wait_time)
            delay *= 2
            retry
          end
        rescue AuthenticationError => e
          # Never retry authentication errors
          last_error = e
          puts '❌ Authentication failed - not retrying'
        rescue LLMError => e
          last_error = e
          if attempt < max_attempts
            puts "⏳ LLM error - waiting #{delay}s before retry..."
            sleep(delay)
            delay *= 2 # Exponential backoff
            retry
          end
        rescue StandardError => e
          last_error = e
          if attempt < max_attempts
            puts "⏳ Unexpected error - waiting #{delay}s before retry..."
            sleep(delay)
            delay *= 2
            retry
          end
        end

        # All retries exhausted
        puts "❌ LLM API failed after #{attempt} attempts"
        raise last_error
      end

      def handle_error(error)
        case error
        when ::OpenRouter::ServerError
          handle_openrouter_error(error)
        when Faraday::UnauthorizedError
          raise AuthenticationError, 'Invalid OpenRouter API key'
        when Faraday::TooManyRequestsError
          raise RateLimitError, 'Rate limit exceeded - please try again later'
        when Faraday::ClientError
          handle_client_error(error)
        else
          # Handle any other error type - error might be a String or other object
          error_message = error.respond_to?(:message) ? error.message : error.to_s
          raise LLMError, "Unexpected error: #{error_message}"
        end
      end

      def handle_openrouter_error(error)
        # OpenRouter::ServerError may be raised with just a string message
        error_msg = error.respond_to?(:message) ? error.message : error.to_s

        if error_msg.include?('rate limit')
          raise RateLimitError, error_msg
        elsif error_msg.include?('model not found')
          raise ModelNotFoundError, error_msg
        else
          raise LLMError, "OpenRouter error: #{error_msg}"
        end
      end

      def handle_client_error(error)
        return unless error.response

        status = error.response[:status]
        case status
        when 402
          raise LLMError, 'Payment required - check your OpenRouter account balance'
        when 404
          raise ModelNotFoundError, 'Model not found'
        when 429
          raise RateLimitError, 'Rate limit exceeded'
        else
          raise LLMError, "API error (#{status}): #{error.message}"
        end
      end

      def log_api_request(params)
        Services::LoggerService.log_api_call(
          service: 'openrouter',
          endpoint: '/chat/completions',
          method: 'POST',
          model: params[:model],
          message_count: params[:messages].size,
          temperature: params[:extras][:temperature],
          max_tokens: params[:extras][:max_tokens]
        )
      end

      def log_api_response(response, model, duration)
        usage = extract_usage(response)
        content = extract_content(response)

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
        # If anything goes wrong, return empty string
        Rails.logger.error "Failed to extract from response: #{e.message}" if defined?(Rails)
        ''
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
