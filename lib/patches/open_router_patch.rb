# frozen_string_literal: true

# Patch for open_router gem to handle non-JSON responses gracefully
require 'open_router'

module OpenRouter
  class Client
    # Override the complete method to handle string responses
    alias_method :original_complete, :complete
    
    def complete(messages, model: "openrouter/auto", providers: [], transforms: [], extras: {}, stream: nil)
      parameters = { messages: messages }
      
      if model.is_a?(String)
        parameters[:model] = model
      elsif model.is_a?(Array)
        parameters[:models] = model
        parameters[:route] = "fallback"
      end
      
      parameters[:provider] = { provider: { order: providers } } if providers.any?
      parameters[:transforms] = transforms if transforms.any?
      parameters[:stream] = stream if stream
      parameters.merge!(extras)

      post(path: "/chat/completions", parameters: parameters).tap do |response|
        # Handle string responses (errors from API)
        if response.is_a?(String)
          # Try to parse as JSON
          begin
            parsed = JSON.parse(response)
            if parsed.is_a?(Hash) && parsed["error"]
              raise ServerError, parsed["error"]["message"] || parsed["error"].to_s
            end
          rescue JSON::ParserError
            # If it's not JSON, raise the string as the error
            raise ServerError, response
          end
        elsif response.is_a?(Hash) || response.respond_to?(:dig)
          # Original logic for hash responses
          if response.respond_to?(:dig) && response.dig("error", "message").present?
            raise ServerError, response.dig("error", "message")
          elsif response["error"] && response["error"]["message"]
            raise ServerError, response["error"]["message"]
          end
        end
        
        raise ServerError, "Empty response from OpenRouter. Might be worth retrying once or twice." if stream.blank? && response.blank?

        return response.with_indifferent_access if response.is_a?(Hash)
        return response # Return as-is if it's something else
      end
    end
  end
end