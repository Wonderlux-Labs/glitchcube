# frozen_string_literal: true

# OpenRouter model presets for Glitch Cube
# Generated on 2025-08-04 from live OpenRouter API data
#
# Pricing is per 1M tokens (average of prompt + completion costs)

module GlitchCube
  class ModelPresets
    # Blacklisted models that should never be used due to high cost
    # - openai/o1-pro: $375/1M - BANKRUPTCY RISK!
    # - openai/o3-pro: High cost reasoning model
    # - openai/o1: High cost reasoning model
    # - anthropic/claude-3-opus: Premium model
    # - anthropic/claude-opus-4: Latest premium model
    # - openai/gpt-4: $30/$60, 8,191 context
    # - openai/gpt-4-0314: $30/$60, 8,191 context
    # - openai/gpt-4-turbo: $10/$30, 128,000 context
    # - openai/gpt-4-turbo-preview: $10/$30, 128,000 context
    BLACKLISTED_MODELS = [
      'openai/o1-pro',
      'openai/o3-pro',
      'openai/o1',
      'anthropic/claude-3-opus',
      'anthropic/claude-opus-4',
      'openai/gpt-4',
      'openai/gpt-4-0314',
      'openai/gpt-4-turbo',
      'openai/gpt-4-turbo-preview'
    ].freeze

    # Ultra-cheap models for basic tasks (under $0.05/1M tokens)
    # - meta-llama/llama-3.2-3b-instruct: $0.01/1M, 20k context
    # - meta-llama/llama-3.2-1b-instruct: $0.01/1M, 131k context
    # - liquid/lfm-7b: $0.01/1M, 32k context
    # - qwen/qwen-2.5-7b-instruct: $0.07/1M, 65k context
    # - cognitivecomputations/dolphin3.0-mistral-24b: $0.06/1M, 32k context
    # - thedrummer/skyfall-36b-v2: $0.07/1M, 32k context
    CHEAP_MODELS = [
      'meta-llama/llama-3.2-3b-instruct',
      'meta-llama/llama-3.2-1b-instruct',
      'liquid/lfm-7b',
      'qwen/qwen-2.5-7b-instruct',
      'cognitivecomputations/dolphin3.0-mistral-24b',
      'thedrummer/skyfall-36b-v2'
    ].freeze

    # Cheap models with tool usage capabilities
    # - qwen/qwen3-235b-a22b-thinking-2507: $0.12/1M, 262k context
    # - deepseek/deepseek-r1-distill-qwen-32b: $0.12/1M, 131k context
    # - qwen/qwen3-235b-a22b-2507: $0.12/1M, 262k context
    CHEAP_TOOLS_MODELS = [
      'qwen/qwen3-235b-a22b-thinking-2507',
      'deepseek/deepseek-r1-distill-qwen-32b',
      'qwen/qwen3-235b-a22b-2507'
    ].freeze

    # Cheap models without tool usage
    # - meta-llama/llama-3.2-3b-instruct: $0.01/1M, 20k context
    # - meta-llama/llama-3.2-1b-instruct: $0.01/1M, 131k context
    # - liquid/lfm-7b: $0.01/1M, 32k context
    CHEAP_NO_TOOLS_MODELS = [
      'meta-llama/llama-3.2-3b-instruct',
      'meta-llama/llama-3.2-1b-instruct',
      'liquid/lfm-7b'
    ].freeze

    # Conversation models with reasoning capabilities
    # - qwen/qwen3-235b-a22b-thinking-2507: $0.12/1M, 262k context
    # - deepseek/deepseek-r1-distill-qwen-32b: $0.12/1M, 131k context
    # - qwen/qwen3-235b-a22b-2507: $0.12/1M, 262k context
    # - deepseek/deepseek-chat-v3-0324: $1.20/1M, 163k context
    # - openai/gpt-oss-120b: $1.05/1M, 131k context
    # - cohere/command-r: $1.20/1M, 131k context
    # - anthropic/claude-3-haiku: $0.75/1M, 200k context
    # - openai/gpt-4.1-mini: $1.00/1M, 1M context
    # - anthropic/claude-3-haiku:beta: $0.75/1M, 200k context
    CONVERSATION_MODELS = [
      'qwen/qwen3-235b-a22b-thinking-2507',
      'deepseek/deepseek-r1-distill-qwen-32b',
      'qwen/qwen3-235b-a22b-2507',
      'deepseek/deepseek-chat-v3-0324',
      'openai/gpt-oss-120b',
      'cohere/command-r',
      'anthropic/claude-3-haiku',
      'openai/gpt-4.1-mini',
      'anthropic/claude-3-haiku:beta'
    ].freeze

    # Vision/image analysis models
    # - qwen/qwen2.5-vl-72b-instruct:free: Free, 32k context, vision
    # - moonshotai/kimi-vl-a3b-thinking:free: Free, 131k context, vision + reasoning
    # - qwen/qwen2.5-vl-32b-instruct:free: Free, 8k context, vision
    VISION_MODELS = [
      'qwen/qwen2.5-vl-72b-instruct:free',
      'moonshotai/kimi-vl-a3b-thinking:free',
      'qwen/qwen2.5-vl-32b-instruct:free'
    ].freeze

    # Free models for development/testing
    # - meta-llama/llama-3.1-405b-instruct:free: 65k context
    # - deepseek/deepseek-r1-0528:free: 163k context
    # - mistralai/mistral-nemo:free: 131k context
    # - qwen/qwen3-coder:free: 262k context
    # - moonshotai/kimi-k2:free: 32k context
    # - openrouter/horizon-beta: 256k context
    FREE_MODELS = [
      'meta-llama/llama-3.1-405b-instruct:free',
      'deepseek/deepseek-r1-0528:free',
      'mistralai/mistral-nemo:free',
      'qwen/qwen3-coder:free',
      'moonshotai/kimi-k2:free'
    ].freeze

    # Premium models
    # - deepseek/deepseek-chat-v3-0324: $1.20/1M, 163k context
    # - openai/gpt-oss-120b: $1.05/1M, 131k context
    # - cohere/command-r: $1.20/1M, 131k context
    # - anthropic/claude-3-haiku: $0.75/1M, 200k context
    # - openai/gpt-4.1-mini: $1.00/1M, 1M context
    # - anthropic/claude-3-haiku:beta: $0.75/1M, 200k context
    PREMIUM_MODELS = [
      'deepseek/deepseek-chat-v3-0324',
      'openai/gpt-oss-120b',
      'cohere/command-r',
      'anthropic/claude-3-haiku',
      'openai/gpt-4.1-mini',
      'anthropic/claude-3-haiku:beta'
    ].freeze

    # Default model to use when none specified
    DEFAULT_MODEL = 'qwen/qwen3-coder:free'

    # Get model for specific use case
    # Accepts either a specific model ID or a type (:free, :cheap_tools, :cheap_no_tools, :conversation, :premium, :multimodel)
    # If both are nil, returns the DEFAULT_MODEL
    def self.get_model(type = nil)
      # If type is nil, return default model
      return DEFAULT_MODEL if type.nil?

      # Get model from the appropriate constant based on type
      preset = case type
               when :free
                 FREE_MODELS
               when :cheap_tools
                 CHEAP_TOOLS_MODELS
               when :cheap_no_tools
                 CHEAP_NO_TOOLS_MODELS
               when :conversation
                 CONVERSATION_MODELS
               when :premium
                 PREMIUM_MODELS
               when :multimodel
                 VISION_MODELS
               else
                 raise ArgumentError, "Invalid model type: #{type}. Valid types are :free, :cheap_tools, :cheap_no_tools, :conversation, :premium, :multimodel"
               end

      # Return first non-blacklisted model from the preset
      available_model = preset.find { |m| !blacklisted?(m) }
      return available_model if available_model

      # Fallback to default model
      DEFAULT_MODEL
    end

    # Check if model is blacklisted
    def self.blacklisted?(model_id)
      BLACKLISTED_MODELS.include?(model_id)
    end

    # Get all available preset types
    def self.preset_types
      %i[free cheap_tools cheap_no_tools conversation premium multimodel]
    end

    # Validate model choice against blacklist
    def self.validate_model!(model_id)
      raise ArgumentError, "Model #{model_id} is blacklisted due to high cost (>$50/1M tokens). Use a different model preset." if blacklisted?(model_id)

      model_id
    end
  end
end
