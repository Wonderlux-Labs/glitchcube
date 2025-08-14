# frozen_string_literal: true

module Services
  module Conversation
    class HistoryManager
      def initialize(logger: Logging::SimpleLogger)
        @logger = logger
      end

      def get_conversation_context(session, limit: nil)
        @logger.debug('Retrieving conversation context', tagged: %i[conversation history], session_id: session.session_id, limit: limit || 'none')
        llm_messages = session.messages_for_llm(limit: limit)
        @logger.debug("Retrieved #{llm_messages.count} messages for LLM context", tagged: %i[conversation history], session_id: session.session_id)
        llm_messages
      end

      # Saves a message to the conversation session
      # This method delegates to the ConversationSession model for actual storage
      def save_message(conversation_id, message_data)
        @logger.info('Saving message to conversation', tagged: %i[conversation history], conversation_id: conversation_id, role: message_data[:role])

        # Find or create the conversation session
        session = ConversationSession.find_or_create(
          session_id: conversation_id,
          context: {}
        )

        # Add the message to the session
        session.add_message(
          role: message_data[:role],
          content: message_data[:content],
          timestamp: message_data[:timestamp] || Time.now.utc.iso8601,
          metadata: message_data[:context] || {}
        )

        @logger.info('Message saved successfully', tagged: %i[conversation history], conversation_id: conversation_id, message_id: session.messages.last&.id)
      rescue StandardError => e
        @logger.log_error(error: e, message: 'Failed to save message', conversation_id: conversation_id, role: message_data[:role])
        raise
      end

      def truncate_or_summarize_history(messages, session_id, max_messages: 50)
        @logger.debug("Processing history truncation/summarization for session #{session_id}", tagged: %i[conversation history], session_id: session_id, message_count: messages.count, max_messages: max_messages)

        # If messages are within limit, return as-is
        if messages.count <= max_messages
          @logger.debug("Message count (#{messages.count}) within limit (#{max_messages}), no truncation needed", tagged: %i[conversation history], session_id: session_id)
          return messages
        end

        # Calculate how many messages to keep recent vs summarize
        recent_messages_to_keep = max_messages / 2 # Keep recent half
        messages_to_summarize_count = messages.count - recent_messages_to_keep

        @logger.info('Truncating conversation history', tagged: %i[conversation history], session_id: session_id,
                                                        total_messages: messages.count,
                                                        messages_to_summarize: messages_to_summarize_count,
                                                        recent_messages_to_keep: recent_messages_to_keep)

        # Split messages into groups
        messages_to_summarize = messages.first(messages_to_summarize_count)
        recent_messages = messages.last(recent_messages_to_keep)

        # Generate summary of older messages
        summary = generate_conversation_summary(messages_to_summarize, session_id)

        # Create summary message
        summary_message = {
          role: 'system',
          content: "[Conversation Summary] #{summary}",
          timestamp: messages_to_summarize.last&.fetch(:timestamp, Time.now.iso8601)
        }

        # Return summary + recent messages
        truncated_messages = [summary_message] + recent_messages

        @logger.info('Conversation history truncated successfully', tagged: %i[conversation history], session_id: session_id,
                                                                    original_count: messages.count,
                                                                    truncated_count: truncated_messages.count)

        truncated_messages
      end

      private

      # Generate a concise summary of conversation messages
      def generate_conversation_summary(messages, session_id)
        return 'Previous conversation occurred but no messages to summarize.' if messages.empty?

        # Extract key information from messages
        user_messages = messages.select { |msg| msg[:role] == 'user' }
        assistant_messages = messages.select { |msg| msg[:role] == 'assistant' }

        # Create a concise summary
        topics_mentioned = extract_topics_from_messages(messages)

        summary_parts = []
        summary_parts << "Previous conversation with #{user_messages.count} user messages and #{assistant_messages.count} responses"

        if topics_mentioned.any?
          summary_parts << "Topics discussed: #{topics_mentioned.join(', ')}"
        end

        # Include timestamp range if available
        first_timestamp = messages.first&.fetch(:timestamp, nil)
        last_timestamp = messages.last&.fetch(:timestamp, nil)

        if first_timestamp && last_timestamp
          summary_parts << "Time range: #{format_timestamp_for_summary(first_timestamp)} to #{format_timestamp_for_summary(last_timestamp)}"
        end

        summary = "#{summary_parts.join('. ')}."

        @logger.debug('Generated conversation summary', tagged: %i[conversation history summary], session_id: session_id,
                                                        summary_length: summary.length,
                                                        topics_count: topics_mentioned.count)

        summary
      end

      # Extract potential topics from message content
      def extract_topics_from_messages(messages)
        topics = Set.new

        messages.each do |message|
          content = message[:content]&.downcase || ''

          # Look for common nouns and topic indicators
          # This is a simple keyword-based approach - could be enhanced with NLP
          topic_keywords = %w[
            art music installation light color sound
            movement sensor battery weather time space
            interaction experience emotion creativity technology
          ]

          topic_keywords.each do |keyword|
            topics.add(keyword) if content.include?(keyword)
          end

          # Look for questions (topics of inquiry)
          next unless content.include?('?')

          # Extract simple question topics
          question_indicators = %w[what how when where why who]
          question_indicators.each do |indicator|
            if content.include?(indicator)
              topics.add("#{indicator} questions")
              break
            end
          end
        end

        topics.to_a.first(5) # Limit to top 5 topics to keep summary concise
      end

      # Format timestamp for summary display
      def format_timestamp_for_summary(timestamp)
        return 'unknown time' unless timestamp

        begin
          time = timestamp.is_a?(String) ? Time.parse(timestamp) : timestamp
          time.strftime('%H:%M')
        rescue StandardError
          'unknown time'
        end
      end
    end
  end
end
