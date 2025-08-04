# frozen_string_literal: true

require_relative 'logger_service'
require_relative '../../config/model_presets'
require_relative 'openrouter/model_cache'
require_relative 'openrouter/request_handler'

# Abstracted OpenRouter service for direct API calls with context management
class OpenRouterService
  @model_cache = Services::OpenRouter::ModelCache.new
  
  class << self
    attr_reader :model_cache

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

      request_handler.make_api_call(request_params)
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

      request_handler.make_api_call(request_params)
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
      model_cache.available_models(client)
    end

    # Clear model cache
    def clear_cache!
      model_cache.clear!
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

    def request_handler
      @request_handler ||= Services::OpenRouter::RequestHandler.new(client)
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