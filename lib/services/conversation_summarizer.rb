# frozen_string_literal: true

require 'desiru'

module Services
  class ConversationSummarizer
    def initialize
      @summarizer = create_summarizer
    end

    def summarize_conversation(messages, context = {})
      return nil if messages.empty?

      # Format conversation for summarization
      conversation_text = format_conversation(messages)

      # Generate summary
      result = @summarizer.call(
        text: conversation_text,
        max_points: 5
      )

      summary = {
        key_points: result[:key_points] || extract_fallback_points(messages),
        mood_progression: extract_mood_changes(messages),
        topics_discussed: extract_topics(conversation_text),
        duration: calculate_duration(messages),
        message_count: messages.length,
        context: context,
        timestamp: Time.now.iso8601
      }

      # Store summary if persistence is available
      store_summary(summary) if defined?(GlitchCube::Persistence)

      summary
    rescue StandardError => e
      puts "Summarization failed: #{e.message}"
      nil
    end

    def get_recent_summaries(limit: 10)
      return [] unless defined?(GlitchCube::Persistence)

      # Fetch from persistence layer
      GlitchCube::Persistence.get_conversation_summaries(limit: limit)
    rescue StandardError => e
      puts "Failed to fetch summaries: #{e.message}"
      []
    end

    private

    def create_summarizer
      # Use Predict module due to ChainOfThought bug in 0.2.0
      Desiru::Modules::Predict.new(
        'text: str, max_points: int -> key_points: list[str]'
      )
    end

    def format_conversation(messages)
      messages.map do |msg|
        role = msg[:role] || (msg[:from_user] ? 'User' : 'Glitch Cube')
        content = msg[:content] || msg[:message] || msg[:response]
        "#{role}: #{content}"
      end.join("\n\n")
    end

    def extract_fallback_points(messages)
      # Simple fallback if AI summarization fails
      points = []

      # First and last messages
      points << "Conversation started with: #{messages.first[:content] || messages.first[:message]}"
      points << "Ended with: #{messages.last[:content] || messages.last[:response]}" if messages.length > 1

      # Count questions
      question_count = messages.count { |m| m[:content]&.include?('?') || m[:message]&.include?('?') }
      points << "#{question_count} questions were asked" if question_count.positive?

      points
    end

    def extract_mood_changes(messages)
      moods = messages.map { |m| m[:mood] || m[:suggested_mood] }.compact.uniq
      moods.empty? ? ['neutral'] : moods
    end

    def extract_topics(text)
      # Simple keyword extraction
      keywords = %w[art consciousness creativity play mystery think wonder color light
                    experience perception reality dream imagine create explore feel]

      found_topics = keywords.select do |keyword|
        text.downcase.include?(keyword)
      end

      found_topics.take(5)
    end

    def calculate_duration(messages)
      return 0 if messages.length < 2

      first_time = parse_time(messages.first[:timestamp] || messages.first[:created_at])
      last_time = parse_time(messages.last[:timestamp] || messages.last[:created_at])

      return 0 unless first_time && last_time

      (last_time - first_time).to_i
    rescue StandardError
      0
    end

    def parse_time(time_value)
      case time_value
      when Time then time_value
      when String then Time.parse(time_value)
      end
    end

    def store_summary(summary)
      # Store in persistence layer if available
      GlitchCube::Persistence.store_conversation_summary(summary)
    rescue StandardError => e
      puts "Failed to store summary: #{e.message}"
    end
  end
end
