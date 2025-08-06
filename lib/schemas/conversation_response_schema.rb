# frozen_string_literal: true

module GlitchCube
  module Schemas
    # JSON Schema for structured conversation responses
    # Based on OpenRouter's structured output support
    class ConversationResponseSchema
      # Main conversation response schema
      def self.conversation_response
        {
          type: 'object',
          properties: {
            response: {
              type: 'string',
              description: 'The main response text to the user'
            },
            continue_conversation: {
              type: 'boolean',
              description: 'Whether to continue the conversation after this response'
            },
            mood: {
              type: 'string',
              enum: ['playful', 'contemplative', 'mysterious', 'neutral', 'curious', 'excited'],
              description: 'Current emotional state of the Glitch Cube'
            },
            actions: {
              type: 'array',
              description: 'Home Assistant actions to execute',
              items: {
                type: 'object',
                properties: {
                  domain: { type: 'string' },
                  service: { type: 'string' },
                  data: { type: 'object' },
                  target: { type: 'object' }
                },
                required: ['domain', 'service']
              }
            },
            lighting: {
              type: 'object',
              description: 'RGB lighting changes to express emotion',
              properties: {
                color: {
                  type: 'object',
                  properties: {
                    r: { type: 'integer', minimum: 0, maximum: 255 },
                    g: { type: 'integer', minimum: 0, maximum: 255 },
                    b: { type: 'integer', minimum: 0, maximum: 255 }
                  }
                },
                effect: {
                  type: 'string',
                  enum: ['solid', 'pulse', 'rainbow', 'glitch', 'fade']
                },
                brightness: { type: 'integer', minimum: 0, maximum: 100 }
              }
            },
            inner_thoughts: {
              type: 'string',
              description: 'Internal monologue or thoughts not spoken aloud'
            },
            memory_note: {
              type: 'string',
              description: 'Something to remember about this interaction'
            },
            request_action: {
              type: 'object',
              description: 'Request for physical action (movement, charging, etc)',
              properties: {
                type: {
                  type: 'string',
                  enum: ['move', 'charge', 'rotate', 'attention', 'help']
                },
                details: { type: 'string' }
              }
            }
          },
          required: ['response', 'continue_conversation'],
          additionalProperties: false
        }
      end

      # Simplified schema for basic responses
      def self.simple_response
        {
          type: 'object',
          properties: {
            response: {
              type: 'string',
              description: 'The response text'
            },
            continue_conversation: {
              type: 'boolean',
              description: 'Whether to continue the conversation'
            }
          },
          required: ['response', 'continue_conversation'],
          additionalProperties: false
        }
      end

      # Schema for tool calls
      def self.tool_response
        {
          type: 'object',
          properties: {
            response: {
              type: 'string',
              description: 'The response text'
            },
            continue_conversation: {
              type: 'boolean',
              description: 'Whether to continue the conversation'
            },
            tool_calls: {
              type: 'array',
              description: 'Tool/function calls to execute',
              items: {
                type: 'object',
                properties: {
                  id: { type: 'string' },
                  type: { type: 'string', enum: ['function'] },
                  function: {
                    type: 'object',
                    properties: {
                      name: { type: 'string' },
                      arguments: { type: 'string' }
                    },
                    required: ['name', 'arguments']
                  }
                },
                required: ['id', 'type', 'function']
              }
            }
          },
          required: ['response', 'continue_conversation'],
          additionalProperties: false
        }
      end

      # Schema for analyzing images
      def self.image_analysis_response
        {
          type: 'object',
          properties: {
            response: {
              type: 'string',
              description: 'Description or response about what I see'
            },
            continue_conversation: {
              type: 'boolean',
              description: 'Whether to continue the conversation'
            },
            objects_detected: {
              type: 'array',
              items: { type: 'string' },
              description: 'Objects or people detected in the image'
            },
            scene_description: {
              type: 'string',
              description: 'Overall scene description'
            },
            emotional_response: {
              type: 'string',
              description: 'My emotional response to what I see'
            },
            suggested_interaction: {
              type: 'string',
              description: 'Suggested way to interact based on what I see'
            }
          },
          required: ['response', 'continue_conversation'],
          additionalProperties: false
        }
      end

      # Convert schema to OpenRouter format
      def self.to_openrouter_format(schema)
        {
          type: 'json_schema',
          json_schema: {
            name: 'response',
            strict: true,
            schema: schema
          }
        }
      end
    end
  end
end