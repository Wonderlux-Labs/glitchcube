# frozen_string_literal: true

require_relative 'llm_service'

module Services
  class ConversationSummarizer
    def initialize
      @llm_service = Services::LLMService.new
    end

    def summarize_conversation(messages, _context = {})
      return nil if messages.empty?

      # Format conversation for summarization
      conversation_text = format_conversation(messages)

      system_prompt = <<~PROMPT
        You are an expert at summarizing conversations.
        Provide a concise summary capturing the key points and overall theme.
        Focus on: main topics discussed, any decisions made, and notable moments.
        Keep the summary under 5 bullet points.
      PROMPT

      user_prompt = <<~PROMPT
        Summarize this conversation:

        #{conversation_text}
      PROMPT

      # Generate summary
      response = @llm_service.complete(
        system_prompt: system_prompt,
        user_message: user_prompt,
        model: GlitchCube.config.ai.default_model,
        temperature: 0.3,
        max_tokens: 200
      )

      parse_summary(response[:content])
    rescue StandardError => e
      puts "Failed to summarize conversation: #{e.message}"
      nil
    end

    def summarize_day(conversations, date = Date.today)
      return nil if conversations.empty?

      summaries = conversations.map do |conv|
        messages = conv['messages'] || []
        next if messages.empty?

        {
          time: conv['started_at'],
          persona: conv['persona'],
          summary: summarize_conversation(messages)
        }
      end.compact

      return nil if summaries.empty?

      system_prompt = <<~PROMPT
        You are creating a daily summary of interactions with an autonomous art installation.
        Synthesize the individual conversation summaries into a cohesive daily narrative.
        Highlight patterns, interesting moments, and the overall mood of the day.
      PROMPT

      user_prompt = <<~PROMPT
        Date: #{date}

        Individual conversation summaries:
        #{summaries.map { |s| "#{s[:time]} (#{s[:persona]}): #{s[:summary]}" }.join("\n\n")}

        Create a unified daily summary.
      PROMPT

      response = @llm_service.complete(
        system_prompt: system_prompt,
        user_message: user_prompt,
        model: GlitchCube.config.ai.default_model,
        temperature: 0.4,
        max_tokens: 300
      )

      {
        date: date,
        conversation_count: conversations.size,
        summary: response[:content],
        generated_at: Time.now
      }
    end

    private

    def format_conversation(messages)
      messages.map do |msg|
        role = msg['role'] || msg[:role]
        content = msg['content'] || msg[:content]
        "#{role.capitalize}: #{content}"
      end.join("\n\n")
    end

    def parse_summary(raw_summary)
      return nil if raw_summary.nil? || raw_summary.empty?

      # Extract bullet points if formatted that way
      points = raw_summary.scan(/^[\*\-•]\s*(.+)$/m).flatten

      if points.any?
        points.map(&:strip).join("\n")
      else
        raw_summary.strip
      end
    end
  end
end
