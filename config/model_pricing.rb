# frozen_string_literal: true

module GlitchCube
  module ModelPricing
    # Pricing per 1M tokens (as of 2025)
    # Format: { input_cost, output_cost } in USD
    PRICING = {
      # OpenRouter Auto
      'openrouter/auto' => { input: 0.0, output: 0.0 }, # Variable pricing

      # Anthropic
      'anthropic/claude-3.5-sonnet' => { input: 3.0, output: 15.0 },
      'anthropic/claude-3.5-sonnet:beta' => { input: 3.0, output: 15.0 },
      'anthropic/claude-3.5-haiku' => { input: 0.25, output: 1.25 },
      'anthropic/claude-3-opus' => { input: 15.0, output: 75.0 },

      # OpenAI
      'openai/gpt-4o' => { input: 5.0, output: 15.0 },
      'openai/gpt-4o-mini' => { input: 0.15, output: 0.60 },
      'openai/gpt-4-turbo' => { input: 10.0, output: 30.0 },
      'openai/gpt-3.5-turbo' => { input: 0.50, output: 1.50 },
      'openai/o1' => { input: 15.0, output: 60.0 },
      'openai/o1-mini' => { input: 3.0, output: 12.0 },

      # Google
      'google/gemini-pro-1.5' => { input: 3.5, output: 10.5 },
      'google/gemini-flash-1.5' => { input: 0.075, output: 0.30 },

      # Meta
      'meta-llama/llama-3.1-405b-instruct' => { input: 3.0, output: 3.0 },
      'meta-llama/llama-3.1-70b-instruct' => { input: 0.88, output: 0.88 },
      'meta-llama/llama-3.1-8b-instruct' => { input: 0.11, output: 0.11 },

      # Mistral
      'mistralai/mistral-large' => { input: 3.0, output: 9.0 },
      'mistralai/mistral-medium' => { input: 2.7, output: 8.1 },
      'mistralai/mistral-small' => { input: 0.20, output: 0.60 },
      'mistralai/mixtral-8x7b-instruct' => { input: 0.27, output: 0.27 },

      # Qwen
      'qwen/qwen-2.5-72b-instruct' => { input: 0.35, output: 0.40 },
      'qwen/qwen-2.5-7b-instruct' => { input: 0.05, output: 0.05 },

      # DeepSeek
      'deepseek/deepseek-coder' => { input: 0.14, output: 0.28 },
      'deepseek/deepseek-chat' => { input: 0.14, output: 0.28 },

      # Default fallback
      'default' => { input: 1.0, output: 2.0 }
    }.freeze

    class << self
      # Calculate cost for tokens
      def calculate_cost(model, prompt_tokens, completion_tokens)
        pricing = PRICING[model] || PRICING['default']

        input_cost = (prompt_tokens / 1_000_000.0) * pricing[:input]
        output_cost = (completion_tokens / 1_000_000.0) * pricing[:output]

        (input_cost + output_cost).round(6)
      end

      # Get pricing for a model
      def pricing_for(model)
        PRICING[model] || PRICING['default']
      end

      # Check if model has free tier
      def free?(model)
        pricing = PRICING[model]
        pricing && pricing[:input] == 0.0 && pricing[:output] == 0.0
      end
    end
  end
end
