# frozen_string_literal: true

# OpenRouter model presets for Glitch Cube
# Generated on 2025-08-04 from live OpenRouter API data
# 
# Pricing is per 1M tokens (average of prompt + completion costs)
# All models tested and categorized for art installation use

module GlitchCube
  class ModelPresets
    # Ultra-cheap models for basic tasks (under $0.05/1M tokens)
    SMALL_CHEAPEST = {
      primary: 'meta-llama/llama-3.2-3b-instruct',          # $0.01/1M, 20k context
      alternatives: [
        'meta-llama/llama-3.2-1b-instruct',                # $0.01/1M, 131k context  
        'liquid/lfm-7b'                                     # $0.01/1M, 32k context
      ]
    }.freeze

    # Efficient small models with good context ($0.05-0.20/1M tokens)
    SMALL = {
      primary: 'qwen/qwen-2.5-7b-instruct',                 # $0.07/1M, 65k context
      alternatives: [
        'cognitivecomputations/dolphin3.0-mistral-24b',    # $0.06/1M, 32k context
        'thedrummer/skyfall-36b-v2'                        # $0.07/1M, 32k context
      ]
    }.freeze

    # Good conversation models with reasoning ($0.10-2.00/1M tokens)  
    CONVERSATION_SMALL = {
      primary: 'qwen/qwen3-235b-a22b-thinking-2507',        # $0.12/1M, 262k context
      alternatives: [
        'deepseek/deepseek-r1-distill-qwen-32b',           # $0.12/1M, 131k context
        'qwen/qwen3-235b-a22b-2507'                        # $0.12/1M, 262k context
      ]
    }.freeze

    # Default conversation models with high performance ($1-15/1M tokens)
    CONVERSATION_DEFAULT = {
      primary: 'deepseek/deepseek-r1',                       # $1.20/1M, 163k context
      alternatives: [  
        'aion-labs/aion-1.0-mini',                          # $1.05/1M, 131k context
        'mistralai/devstral-medium'                         # $1.20/1M, 131k context
      ]
    }.freeze

    # Vision/image analysis models (under $20/1M tokens)
    IMAGE_CLASSIFICATION = {
      primary: 'qwen/qwen2.5-vl-72b-instruct:free',         # Free, 32k context, vision
      alternatives: [
        'moonshotai/kimi-vl-a3b-thinking:free',            # Free, 131k context, vision + reasoning
        'qwen/qwen2.5-vl-32b-instruct:free'                # Free, 8k context, vision
      ]
    }.freeze

    # Premium provider alternatives ($0.50-8/1M tokens)
    CONVERSATION_ALTERNATE = {
      primary: 'anthropic/claude-3-haiku',                   # $0.75/1M, 200k context
      alternatives: [
        'openai/gpt-4.1-mini',                             # $1.00/1M, 1M context
        'anthropic/claude-3-haiku:beta'                    # $0.75/1M, 200k context
      ]
    }.freeze

    # Free models for development/testing
    FREE_MODELS = [
      'meta-llama/llama-3.1-405b-instruct:free',           # 65k context
      'deepseek/deepseek-r1-0528:free',                    # 163k context
      'mistralai/mistral-nemo:free',                       # 131k context
      'qwen/qwen3-coder:free',                             # 262k context
      'moonshotai/kimi-k2:free',                           # 32k context
      'openrouter/horizon-beta'                            # 256k context
    ].freeze

    # DANGEROUS: Models that can bankrupt you (over $50/1M tokens)
    # These should NEVER be used in production without explicit approval
    BLACKLISTED_EXPENSIVE = [
      'openai/o1-pro',                                      # $375/1M - BANKRUPTCY RISK!
      'openai/o3-pro',                                      # High cost reasoning model
      'openai/o1',                                          # High cost reasoning model  
      'anthropic/claude-3-opus',                           # Premium model
      'anthropic/claude-opus-4',                           # Latest premium model
      'openai/gpt-4'                                        # Legacy expensive model
    ].freeze

    # Get model for specific use case
    def self.get_model(preset_name, fallback_index: 0)
      preset = const_get(preset_name.to_s.upcase)
      
      if preset.is_a?(Hash)
        return preset[:primary] if fallback_index == 0
        return preset[:alternatives][fallback_index - 1] if preset[:alternatives]&.[](fallback_index - 1)
        preset[:primary] # Fallback to primary
      else
        preset[fallback_index] || preset.first
      end
    end

    # Check if model is blacklisted
    def self.blacklisted?(model_id)
      BLACKLISTED_EXPENSIVE.include?(model_id)
    end

    # Get all available presets
    def self.preset_names
      constants.select { |c| const_get(c).is_a?(Hash) && c != :FREE_MODELS && c != :BLACKLISTED_EXPENSIVE }
    end

    # Validate model choice against blacklist
    def self.validate_model!(model_id)
      if blacklisted?(model_id)
        raise ArgumentError, "Model #{model_id} is blacklisted due to high cost (>$50/1M tokens). Use a different model preset."
      end
      model_id
    end
  end
end