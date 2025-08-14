# frozen_string_literal: true

require 'sinatra/base'
require 'json'

module GlitchCube
  module Routes
    module Api
      module LLM
        def self.registered(app)
          # Simple LLM completion endpoint for Home Assistant
          app.post '/api/v1/llm/complete' do
            content_type :json

            begin
              # Parse request body
              data = JSON.parse(request.body.read)

              # Extract parameters
              prompt = data['prompt']
              model = data['model'] # Optional - will use default if not provided
              options = data['options'] || {} # Optional parameters like temperature, max_tokens, etc.

              # Validate required parameters
              return { error: 'Prompt is required' }.to_json if prompt.nil? || prompt.empty?

              # Build options hash
              llm_options = {
                model: model || GlitchCube.config.ai.default_model,
                temperature: options['temperature'] || 0.7,
                max_tokens: options['max_tokens'] || 500
              }

              # Add any other options that were passed
              llm_options[:top_p] = options['top_p'] if options['top_p']
              llm_options[:frequency_penalty] = options['frequency_penalty'] if options['frequency_penalty']
              llm_options[:presence_penalty] = options['presence_penalty'] if options['presence_penalty']

              # Log the request if debug mode
              if GlitchCube.config.debug?
                LogHelper.info('LLM API Request', {
                                 model: llm_options[:model],
                                 prompt_length: prompt.length,
                                 options: llm_options
                               })
              end

              # Call the LLM service with a simple system prompt
              system_prompt = options['system_prompt'] || "You are a helpful AI assistant. Respond concisely and directly to the user's request."

              response = ::Services::Llm::LLMService.complete(
                system_prompt: system_prompt,
                user_message: prompt,
                **llm_options
              )

              # Return the response
              {
                success: true,
                text: response.content,
                model: response.model,
                usage: {
                  prompt_tokens: response.prompt_tokens,
                  completion_tokens: response.completion_tokens,
                  total_tokens: response.total_tokens
                },
                cost: response.cost
              }.to_json
            rescue JSON::ParserError => e
              status 400
              { error: "Invalid JSON: #{e.message}" }.to_json
            rescue ::Services::Llm::LLMService::RateLimitError => e
              status 429
              { error: "Rate limit exceeded: #{e.message}" }.to_json
            rescue ::Services::Llm::LLMService::AuthenticationError => e
              status 401
              { error: "Authentication failed: #{e.message}" }.to_json
            rescue ::Services::Llm::LLMService::ModelNotFoundError => e
              status 404
              { error: "Model not found: #{e.message}" }.to_json
            rescue StandardError => e
              LogHelper.error('LLM API Error', {
                                error: e.message,
                                backtrace: e.backtrace.first(5)
                              })
              status 500
              { error: "Internal server error: #{e.message}" }.to_json
            end
          end

          # GET endpoint to list available models
          app.get '/api/v1/llm/models' do
            content_type :json

            # Define available models with their descriptions
            models = {
              'openrouter/auto' => 'Automatic model selection',
              'google/gemini-2.5-flash' => 'Fast and efficient for most tasks',
              'anthropic/claude-3.5-haiku' => 'Quick Claude model',
              'anthropic/claude-4-sonnet' => 'Balanced Claude model',
              'openai/gpt-4.1-mini' => 'Cost-effective GPT model',
              'deepseek/deepseek-chat-v3-0324' => 'DeepSeek Chat v3',
              'openai/gpt-oss-120b' => 'Open source GPT 120B'
            }

            {
              default_model: GlitchCube.config.ai.default_model || 'openai/gpt-4.1-mini',
              available_models: models
            }.to_json
          end
        end
      end
    end
  end
end
