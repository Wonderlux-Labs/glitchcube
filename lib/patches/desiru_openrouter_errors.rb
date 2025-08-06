# frozen_string_literal: true

# Patch to fix missing error classes in Desiru OpenRouter model
# This addresses the issue where InvalidRequestError and APIError don't exist in Desiru
# UPDATED: Also routes through Helicone cloud service when configured

module Desiru
  module Models
    class OpenRouter < Base
      # Override initialize to use Helicone-aware client
      def initialize(api_key:, model: nil, **options)
        super

        # Check if Helicone cloud service is configured (from GlitchCube config)
        @client = if defined?(GlitchCube) && GlitchCube.config.helicone_api_key
                    # Route through Helicone cloud service for observability
                    ::OpenRouter::Client.new(
                      access_token: api_key,
                      uri_base: 'https://oai.helicone.ai',
                      extra_headers: {
                        'Helicone-Auth' => "Bearer #{GlitchCube.config.helicone_api_key}",
                        'Helicone-Target-URL' => 'https://openrouter.ai/api/v1'
                      }
                    )
                  else
                    # Direct OpenRouter connection (fallback)
                    ::OpenRouter::Client.new(access_token: api_key)
                  end
      end

      private

      # Override perform_completion to fix request structure for updated OpenRouter gem v0.3+
      def perform_completion(messages, options)
        model = options[:model] || @config[:model] || DEFAULT_MODEL
        temperature = options[:temperature] || @config[:temperature] || 0.7
        max_tokens = options[:max_tokens] || @config[:max_tokens] || 4096

        # Prepare parameters for open_router gem v0.3+
        # The gem expects messages as first param, other options as named params
        params = {
          model: model,
          extras: {
            temperature: temperature,
            max_tokens: max_tokens
          }
        }

        # Add provider-specific options if needed
        params[:providers] = [options[:provider]] if options[:provider]

        # Add response format if specified
        params[:extras][:response_format] = options[:response_format] if options[:response_format]

        # Add tools if provided (for models that support function calling)
        if options[:tools]
          params[:extras][:tools] = options[:tools]
          params[:extras][:tool_choice] = options[:tool_choice] if options[:tool_choice]
        end

        # Make API call with correct parameter structure for OpenRouter gem v0.3+
        response = @client.complete(messages, **params)

        # Format response
        format_response(response, model)
      rescue StandardError => e
        handle_api_error(e)
      end

      # Override the handle_api_error method to use correct Desiru error classes
      def handle_api_error(error)
        case error
        when ::Faraday::UnauthorizedError
          raise AuthenticationError, 'Invalid OpenRouter API key'
        when ::Faraday::BadRequestError
          raise ValidationError, "Invalid request: #{error.message}"
        when ::Faraday::TooManyRequestsError
          raise RateLimitError, 'OpenRouter API rate limit exceeded'
        when ::Faraday::ClientError
          # Handle specific client errors
          if error.response
            status = error.response[:status]
            case status
            when 402
              raise NetworkError, 'OpenRouter payment required - check your account balance'
            when 400
              raise ValidationError, "Bad request: #{error.message}"
            when 401
              raise AuthenticationError, 'Invalid API key'
            when 403
              raise AuthenticationError, 'Forbidden - check API permissions'
            when 429
              raise RateLimitError, 'Rate limit exceeded'
            else
              raise ValidationError, "Client error (#{status}): #{error.message}"
            end
          else
            raise ValidationError, "Client error: #{error.message}"
          end
        when ::OpenRouter::ServerError
          raise NetworkError, "OpenRouter server error: #{error.message}"
        else
          raise NetworkError, "OpenRouter API error: #{error.message}"
        end
      end

      # Format the response into standard Desiru format
      def format_response(response, model)
        # Handle string responses (some models return plain text)
        if response.is_a?(String)
          return {
            content: response,
            raw: response,
            model: model,
            usage: {
              prompt_tokens: 0,
              completion_tokens: 0,
              total_tokens: 0
            }
          }
        end

        # OpenRouter uses OpenAI-compatible response format
        content = response.dig('choices', 0, 'message', 'content') || ''
        usage = response['usage'] || {}

        {
          content: content,
          raw: response,
          model: model,
          usage: {
            prompt_tokens: usage['prompt_tokens'] || 0,
            completion_tokens: usage['completion_tokens'] || 0,
            total_tokens: (usage['prompt_tokens'] || 0) + (usage['completion_tokens'] || 0)
          }
        }
      end
    end
  end
end
