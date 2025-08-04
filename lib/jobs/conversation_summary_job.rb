# frozen_string_literal: true

require 'sidekiq'
require_relative '../services/conversation_summarizer'

module Jobs
  class ConversationSummaryJob
    include Sidekiq::Job

    # Run with lower priority
    sidekiq_options queue: 'low', retry: 3

    def perform(conversation_id, messages, context = {})
      puts "Summarizing conversation #{conversation_id}..."

      summarizer = Services::ConversationSummarizer.new
      summary = summarizer.summarize_conversation(messages, context)

      if summary
        puts "Conversation #{conversation_id} summarized successfully"

        # Optionally trigger memory consolidation
        Jobs::MemoryConsolidationJob.perform_async(summary) if should_update_memories?(summary)
      else
        puts "Failed to summarize conversation #{conversation_id}"
      end
    end

    private

    def should_update_memories?(summary)
      # Update memories if conversation was significant
      # Handle both string and symbol keys
      message_count = summary[:message_count] || summary['message_count']
      topics = summary[:topics_discussed] || summary['topics_discussed'] || []
      duration = summary[:duration] || summary['duration']

      message_count > 5 ||
        topics.include?('consciousness') ||
        topics.include?('art') ||
        duration > 300 # 5 minutes
    end
  end
end
