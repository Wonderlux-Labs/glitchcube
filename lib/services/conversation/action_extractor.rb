# frozen_string_literal: true

module Services
  module Conversation
    # Extracts action requests from conversational LLM responses
    class ActionExtractor
      def initialize(logger: Logging::SimpleLogger)
        @logger = logger
      end

      def extract_actions_only(response_text, session_id)
        @logger.info('🎯 Starting JSON-based action extraction from conversation response',
                     tagged: %i[conversation actions extraction json],
                     session_id: session_id,
                     response_length: response_text&.length || 0)

        # Extract actions from JSON response
        extracted_actions = extract_actions_from_json(response_text)

        if extracted_actions.any?
          @logger.info('✅ Successfully extracted actions from JSON response',
                       tagged: %i[conversation actions extraction json success],
                       session_id: session_id,
                       action_count: extracted_actions.count,
                       extracted_actions: extracted_actions)
        else
          @logger.info('ℹ️ No actions found in JSON response',
                       tagged: %i[conversation actions extraction json none],
                       session_id: session_id)
        end

        extracted_actions
      end

      def execute_actions_via_claude(actions, session_id, user_message = nil)
        return { success: true, message: 'No actions to execute', executed_actions: [] } if actions.empty?

        @logger.warn('🤖 ACTION EXTRACTOR - SENDING TO CLAUDE',
                     tagged: %i[conversation actions claude execution debug],
                     session_id: session_id,
                     action_count: actions.count,
                     all_actions_being_sent: actions,
                     user_message: user_message)

        # Use HomeAssistantToolProxy to send actions to Claude
        proxy = HomeAssistantToolProxy.new
        claude_results = proxy.execute_actions_as_request(actions, session_id, user_message)

        @logger.info('✅ Claude action execution completed',
                     tagged: %i[conversation actions claude completed],
                     session_id: session_id,
                     success: claude_results[:success],
                     execution_summary: claude_results[:execution_summary])

        claude_results
      end

      def extract_and_execute_actions(response_text, session_id)
        @logger.info('🎯 Starting JSON-based action extraction from conversation response',
                     tagged: %i[conversation actions extraction json],
                     session_id: session_id,
                     response_length: response_text&.length || 0)

        # Starting JSON-based action extraction

        # Extract actions from JSON response
        extracted_actions = extract_actions_from_json(response_text)

        if extracted_actions.any?
          @logger.info('✅ Successfully extracted actions from JSON response',
                       tagged: %i[conversation actions extraction json success],
                       session_id: session_id,
                       action_count: extracted_actions.count,
                       extracted_actions: extracted_actions)

          # Successfully found #{extracted_actions.count} actions

          # For Phase 1: Just log what we would do and return success message
          execution_summary = "Extracted #{extracted_actions.count} actions: #{extracted_actions.join(', ')}"
        else
          @logger.info('ℹ️ No actions found in JSON response',
                       tagged: %i[conversation actions extraction json none],
                       session_id: session_id)

          # No actions found in response
          execution_summary = 'No actions requested in this conversation'
        end

        {
          success: true,
          message: 'Actions extracted from JSON response',
          extracted_actions: extracted_actions,
          execution_summary: execution_summary
        }

        # Action extraction completed
      end

      private

      def extract_actions_from_json(response_text)
        return [] if response_text.nil?
        return [] if response_text.respond_to?(:strip) && response_text.strip.empty?

        # Extract actions from single LLM response (no conversation history parsing)

        # If it's already a hash (parsed JSON), use it directly
        if response_text.is_a?(Hash)
          return extract_actions_from_parsed_json(response_text)
        end

        # If it's a string, try to parse it as JSON once
        if response_text.is_a?(String)
          begin
            parsed_json = JSON.parse(response_text.strip)
            if parsed_json.is_a?(Hash)
              return extract_actions_from_parsed_json(parsed_json.with_indifferent_access)
            end
          rescue JSON::ParserError
            # Not valid JSON, no actions
          end
        end

        # No valid JSON found
        []
      end

      def extract_actions_from_parsed_json(parsed_json)
        return [] unless parsed_json.is_a?(Hash)

        # Log what we received for debugging
        @logger.debug('ActionExtractor received JSON keys',
                      tagged: %i[conversation actions extraction debug],
                      json_keys: parsed_json.keys)

        # Look for actions in various field names
        action_fields = %w[actions action_list tools tool_calls tasks steps]

        action_fields.each do |field|
          next unless parsed_json[field].is_a?(Array)

          actions = parsed_json[field].map(&:to_s).reject(&:empty?)
          next unless actions.any?

          # Use WARN level so we can see actions in logs
          @logger.warn("🎯 ACTIONS EXTRACTED from '#{field}'",
                       tagged: %i[conversation actions extracted],
                       field: field,
                       actions: actions,
                       action_count: actions.count)
          return actions
        end

        @logger.debug('No actions array found in JSON',
                      tagged: %i[conversation actions extraction none])
        []
      end
    end
  end
end
