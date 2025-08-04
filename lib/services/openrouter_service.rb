# frozen_string_literal: true

require_relative 'logger_service'
require_relative '../../config/model_presets'

# Abstracted OpenRouter service for direct API calls with context management
class OpenRouterService
  class << self
    # Simple completion without context
    def complete(prompt, model: default_model, **options)
      # Validate model isn't blacklisted
      GlitchCube::ModelPresets.validate_model!(model)

      request_params = {
        model: model,
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 500,
        temperature: 0.7
      }.merge(options)

      make_api_call(request_params)
    end

    # Completion with conversation context
    def complete_with_context(messages, model: default_model, **options)
      # Validate model isn't blacklisted
      GlitchCube::ModelPresets.validate_model!(model)

      # Ensure messages is an array of message objects
      formatted_messages = format_messages(messages)

      request_params = {
        model: model,
        messages: formatted_messages,
        max_tokens: 500,
        temperature: 0.7
      }.merge(options)

      make_api_call(request_params)
    end

    # Streaming completion (for future use)
    def stream_complete(prompt, model: default_model, **options, &block)
      # Validate model isn't blacklisted
      GlitchCube::ModelPresets.validate_model!(model)

      request_params = {
        model: model,
        messages: [{ role: 'user', content: prompt }],
        stream: true,
        max_tokens: 500,
        temperature: 0.7
      }.merge(options)

      # NOTE: Streaming calls are not logged the same way due to their nature
      client.complete(request_params, &block)
    end

    # Get available models (cached for 1 hour)
    def available_models
      @models_cache ||= {}
      cache_key = :models

      return @models_cache[cache_key][:data] if @models_cache[cache_key] && @models_cache[cache_key][:expires] > Time.now

      models = client.models
      @models_cache[cache_key] = {
        data: models,
        expires: Time.now + 3600 # 1 hour
      }

      models
    end

    # Clear model cache
    def clear_cache!
      @models_cache = {}
    end

    # Convenience methods for common model presets
    def complete_cheap(prompt, **options)
      model = GlitchCube::ModelPresets.get_model(:small_cheapest)
      complete(prompt, model: model, **options)
    end

    def complete_conversation(prompt, **options)
      model = GlitchCube::ModelPresets.get_model(:conversation_small)
      complete(prompt, model: model, **options)
    end

    def complete_premium(prompt, **options)
      model = GlitchCube::ModelPresets.get_model(:conversation_default)
      complete(prompt, model: model, **options)
    end

    def analyze_image(prompt, **options)
      model = GlitchCube::ModelPresets.get_model(:image_classification)
      complete(prompt, model: model, **options)
    end

    private

    def make_api_call(request_params)
      start_time = Time.now

      begin
        response = client.complete(request_params)
        duration = ((Time.now - start_time) * 1000).round

        # Log successful API call with detailed context
        Services::LoggerService.log_api_call(
          service: 'openrouter',
          endpoint: 'chat/completions',
          method: 'POST',
          status: 200,
          duration: duration,
          model: request_params[:model],
          request_size: calculate_request_size(request_params),
          response_size: calculate_response_size(response),
          tokens_used: extract_token_usage(response),
          temperature: request_params[:temperature],
          max_tokens: request_params[:max_tokens]
        )

        response
      rescue StandardError => e
        duration = ((Time.now - start_time) * 1000).round

        # Log failed API call with context
        Services::LoggerService.log_api_call(
          service: 'openrouter',
          endpoint: 'chat/completions',
          method: 'POST',
          status: 500,
          duration: duration,
          error: e.message,
          model: request_params[:model],
          request_size: calculate_request_size(request_params),
          temperature: request_params[:temperature],
          max_tokens: request_params[:max_tokens]
        )

        raise e
      end
    end

    def client
      # Use Helicone cloud service for observability if API key is configured
      @client ||= if GlitchCube.config.helicone_api_key
                    # Route through Helicone cloud service for observability
                    OpenRouter::Client.new(
                      access_token: GlitchCube.config.openrouter_api_key,
                      uri_base: 'https://oai.helicone.ai/v1',
                      extra_headers: {
                        'Helicone-Auth' => "Bearer #{GlitchCube.config.helicone_api_key}",
                        'Helicone-Target-URL' => 'https://openrouter.ai/api/v1'
                      }
                    )
                  else
                    # Direct OpenRouter connection
                    OpenRouter::Client.new(access_token: GlitchCube.config.openrouter_api_key)
                  end
    end

    def default_model
      GlitchCube.config.default_ai_model
    end

    def calculate_request_size(params)
      # Estimate request size based on message content
      message_content = params[:messages]&.map { |m| m[:content] }&.join(' ') || ''
      message_content.bytesize
    end

    def calculate_response_size(response)
      # Estimate response size
      content = response.dig('choices', 0, 'message', 'content') || ''
      content.bytesize
    end

    def extract_token_usage(response)
      usage = response['usage']
      return nil unless usage

      {
        prompt_tokens: usage['prompt_tokens'],
        completion_tokens: usage['completion_tokens'],
        total_tokens: usage['total_tokens']
      }
    end

    def format_messages(messages)
      case messages
      when String
        [{ role: 'user', content: messages }]
      when Array
        messages.map do |msg|
          case msg
          when String
            { role: 'user', content: msg }
          when Hash
            msg
          else
            { role: 'user', content: msg.to_s }
          end
        end
      when Hash
        [messages]
      else
        [{ role: 'user', content: messages.to_s }]
      end
    end
  end
end
