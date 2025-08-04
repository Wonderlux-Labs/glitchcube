# frozen_string_literal: true

# Patch to fix missing error classes in Desiru OpenRouter model
# This addresses the issue where InvalidRequestError and APIError don't exist in Desiru
# UPDATED: Also routes through AI Gateway when configured

module Desiru
  module Models
    class OpenRouter < Base
      # Override initialize to use gateway-aware client
      def initialize(api_key:, model: nil, **options)
        super(api_key: api_key, model: model, **options)
        
        # Use gateway-aware client configuration
        client_options = { access_token: api_key }
        
        # Check if AI Gateway is configured (from GlitchCube config)
        if defined?(GlitchCube) && GlitchCube.config.ai_gateway_url
          # Route through Helicone AI Gateway for observability
          # Uses direct OpenRouter endpoint: /openrouter/v1/chat/completions
          @client = ::OpenRouter::Client.new(
            client_options.merge(
              uri_base: "#{GlitchCube.config.ai_gateway_url}/openrouter"
            )
          )
        else
          # Direct OpenRouter connection (fallback)
          @client = ::OpenRouter::Client.new(client_options)
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
        when ::Faraday::PaymentRequiredError
          raise NetworkError, 'OpenRouter payment required - check your account balance'
        when ::OpenRouter::ServerError
          raise NetworkError, "OpenRouter server error: #{error.message}"
        else
          raise NetworkError, "OpenRouter API error: #{error.message}"
        end
      end
    end
  end
end
