# frozen_string_literal: true

module Services
  module Conversation
    class StateManager
      def initialize(logger: Logging::SimpleLogger)
        @logger = logger
      end

      def create_or_get_session(session_id, context)
        @logger.info('Creating or getting session', tagged: %i[conversation session], session_id: session_id)
        session = ConversationSession.find_or_create(
          session_id: session_id,
          context: context
        )
        @logger.info("Session initialized. New session: #{session.conversation.new_record?}", tagged: %i[conversation session], session_id: session.session_id, message_count: session.messages.count)
        session
      end

      def record_message(session:, role:, content:, persona:, model_used: nil, prompt_tokens: nil, completion_tokens: nil, cost: nil, response_time_ms: nil, metadata: {})
        @logger.debug("Recording message for session #{session.session_id}", tagged: %i[conversation session], session_id: session.session_id, role: role, persona: persona, content_length: content.to_s.length)
        session.add_message(
          role: role,
          content: content,
          persona: persona,
          model_used: model_used,
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          cost: cost,
          response_time_ms: response_time_ms,
          metadata: metadata
        )
        @logger.info("Message recorded for session #{session.session_id}", tagged: %i[conversation session], session_id: session.session_id, role: role, new_message_count: session.messages.count)
      end

      def get_conversation_analytics(session_id)
        @logger.debug('Retrieving conversation analytics', tagged: %i[conversation analytics], session_id: session_id)

        begin
          # Find the session and conversation
          session = ConversationSession.find(session_id)
          return nil unless session

          conversation = session.conversation
          messages = session.messages

          # Calculate basic metrics
          analytics = {
            session_id: session_id,
            conversation_id: conversation&.id,
            created_at: conversation&.created_at,
            updated_at: conversation&.updated_at,

            # Message statistics
            total_messages: messages.count,
            user_messages: messages.where(role: 'user').count,
            assistant_messages: messages.where(role: 'assistant').count,
            system_messages: messages.where(role: 'system').count,

            # Conversation duration
            duration_minutes: calculate_conversation_duration(messages),

            # Cost and token usage
            total_cost: calculate_total_cost(messages),
            total_prompt_tokens: messages.sum(:prompt_tokens) || 0,
            total_completion_tokens: messages.sum(:completion_tokens) || 0,

            # Performance metrics
            average_response_time_ms: calculate_average_response_time(messages),
            models_used: extract_models_used(messages),

            # Content analysis
            topics_discussed: extract_conversation_topics(messages),
            question_count: count_questions(messages),

            # Engagement metrics
            conversation_turns: calculate_conversation_turns(messages),
            last_activity: messages.maximum(:created_at),

            # Metadata
            personas_used: extract_personas_used(messages),
            session_metadata: session.metadata || {}
          }

          @logger.info('Generated conversation analytics', tagged: %i[conversation analytics],
                                                           session_id: session_id,
                                                           total_messages: analytics[:total_messages],
                                                           duration_minutes: analytics[:duration_minutes],
                                                           total_cost: analytics[:total_cost])

          analytics
        rescue StandardError => e
          @logger.error('Failed to generate conversation analytics', tagged: %i[conversation analytics error],
                                                                     session_id: session_id, error: e.message)
          {
            session_id: session_id,
            error: e.message,
            generated_at: Time.now.iso8601
          }
        end
      end

      # Generate aggregated analytics across multiple sessions or time periods
      def get_aggregated_analytics(filters = {})
        @logger.debug('Retrieving aggregated conversation analytics', tagged: %i[conversation analytics aggregated], filters: filters)

        begin
          # Build query based on filters
          conversations_scope = Conversation.all

          if filters[:start_date]
            conversations_scope = conversations_scope.where('created_at >= ?', Time.parse(filters[:start_date].to_s))
          end

          if filters[:end_date]
            conversations_scope = conversations_scope.where('created_at <= ?', Time.parse(filters[:end_date].to_s))
          end

          if filters[:persona]
            # Filter by messages with specific persona
            conversation_ids = Message.where(persona: filters[:persona]).distinct.pluck(:conversation_id)
            conversations_scope = conversations_scope.where(id: conversation_ids)
          end

          conversations = conversations_scope.includes(:messages)

          # Calculate aggregated metrics
          total_conversations = conversations.count
          total_messages = conversations.joins(:messages).count

          analytics = {
            period: {
              start_date: filters[:start_date],
              end_date: filters[:end_date] || Time.now.to_date
            },

            # Conversation metrics
            total_conversations: total_conversations,
            total_messages: total_messages,
            average_messages_per_conversation: total_conversations.positive? ? (total_messages.to_f / total_conversations).round(2) : 0,

            # Cost analysis
            total_cost: conversations.joins(:messages).sum('messages.cost') || 0.0,
            average_cost_per_conversation: 0, # Will calculate below

            # Token usage
            total_prompt_tokens: conversations.joins(:messages).sum('messages.prompt_tokens') || 0,
            total_completion_tokens: conversations.joins(:messages).sum('messages.completion_tokens') || 0,

            # Time analysis
            conversations_by_hour: analyze_conversations_by_hour(conversations),
            average_conversation_duration: calculate_average_duration(conversations),

            # Popular topics and models
            top_topics: extract_top_topics(conversations),
            models_usage: analyze_model_usage(conversations),
            personas_usage: analyze_persona_usage(conversations),

            # Generated timestamp
            generated_at: Time.now.iso8601
          }

          # Calculate average cost per conversation
          analytics[:average_cost_per_conversation] = total_conversations.positive? ? (analytics[:total_cost] / total_conversations).round(4) : 0

          @logger.info('Generated aggregated analytics', tagged: %i[conversation analytics aggregated],
                                                         total_conversations: total_conversations,
                                                         total_messages: total_messages,
                                                         total_cost: analytics[:total_cost])

          analytics
        rescue StandardError => e
          @logger.error('Failed to generate aggregated analytics', tagged: %i[conversation analytics aggregated error],
                                                                   filters: filters, error: e.message)
          {
            error: e.message,
            generated_at: Time.now.iso8601
          }
        end
      end

      private

      # Calculate conversation duration in minutes
      def calculate_conversation_duration(messages)
        return 0 if messages.empty?

        first_message = messages.minimum(:created_at)
        last_message = messages.maximum(:created_at)

        return 0 unless first_message && last_message

        ((last_message - first_message) / 60.0).round(2)
      end

      # Calculate total cost from all messages
      def calculate_total_cost(messages)
        messages.sum(:cost) || 0.0
      end

      # Calculate average response time
      def calculate_average_response_time(messages)
        response_times = messages.where.not(response_time_ms: nil).pluck(:response_time_ms)
        return 0 if response_times.empty?

        (response_times.sum.to_f / response_times.count).round(2)
      end

      # Extract unique models used
      def extract_models_used(messages)
        messages.where.not(model_used: nil).distinct.pluck(:model_used)
      end

      # Extract conversation topics (simplified version)
      def extract_conversation_topics(messages)
        topics = Set.new

        messages.where(role: %w[user assistant]).find_each do |message|
          content = message.content&.downcase || ''

          # Use same topic extraction as in history manager
          topic_keywords = %w[
            art music installation light color sound
            movement sensor battery weather time space
            interaction experience emotion creativity technology
          ]

          topic_keywords.each do |keyword|
            topics.add(keyword) if content.include?(keyword)
          end
        end

        topics.to_a.first(10)
      end

      # Count questions in conversation
      def count_questions(messages)
        messages.where(role: 'user').where('content LIKE ?', '%?%').count
      end

      # Calculate conversation turns (back-and-forth exchanges)
      def calculate_conversation_turns(messages)
        # A turn is a pair of user message followed by assistant response
        user_messages = messages.where(role: 'user').count
        assistant_messages = messages.where(role: 'assistant').count

        [user_messages, assistant_messages].min
      end

      # Extract personas used in conversation
      def extract_personas_used(messages)
        messages.where.not(persona: nil).distinct.pluck(:persona)
      end

      # Additional helper methods for aggregated analytics

      def analyze_conversations_by_hour(conversations)
        conversations.group('EXTRACT(hour FROM created_at)').count
      end

      def calculate_average_duration(conversations)
        durations = conversations.map { |conv| calculate_conversation_duration(conv.messages) }
        durations.empty? ? 0 : (durations.sum.to_f / durations.count).round(2)
      end

      def extract_top_topics(conversations)
        all_topics = []

        conversations.includes(:messages).each do |conversation|
          topics = extract_conversation_topics(conversation.messages)
          all_topics.concat(topics)
        end

        # Count frequency and return top 10
        topic_counts = all_topics.tally
        topic_counts.sort_by { |_topic, count| -count }.first(10).to_h
      end

      def analyze_model_usage(conversations)
        conversations.joins(:messages)
                     .where.not(messages: { model_used: nil })
                     .group('messages.model_used')
                     .count
      end

      def analyze_persona_usage(conversations)
        conversations.joins(:messages)
                     .where.not(messages: { persona: nil })
                     .group('messages.persona')
                     .count
      end
    end
  end
end
