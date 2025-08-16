# frozen_string_literal: true

module Services
  module Logging
    # Dedicated logger for conversation events, writing to conversations.log
    # Captures essential conversation flow data in clean, readable format
    class ConversationLogger
      def initialize(log_file_path: 'logs/conversations.log')
        @log_file_path = log_file_path
        ensure_log_directory
      end

      def log_conversation_flow(data)
        timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
        session_id = data[:session_id] || 'unknown'
        persona = data[:persona] || 'unknown'

        log_entry = build_log_entry(timestamp, session_id, persona, data)

        write_to_log(log_entry)
      end

      private

      def build_log_entry(timestamp, session_id, persona, data)
        lines = []
        lines << ('=' * 80)
        lines << "[#{timestamp}] Session: #{session_id} | Persona: #{persona}"
        lines << ('=' * 80)

        # User input
        if data[:user_input]
          lines << '👤 USER:'
          lines << "  #{data[:user_input]}"
          lines << ''
        end

        # LLM response
        if data[:llm_response]
          lines << '🤖 LLM RESPONSE:'
          lines << "  #{data[:llm_response]}"
          lines << ''
        end

        # Extracted actions
        if data[:extracted_actions]&.any?
          lines << '🎯 EXTRACTED ACTIONS:'
          data[:extracted_actions].each_with_index do |action, i|
            lines << "  #{i + 1}. #{action}"
          end
          lines << ''
        end

        # Claude response
        if data[:claude_response]
          lines << '🔧 CLAUDE RESPONSE:'
          lines << "  #{data[:claude_response]}"
          lines << ''
        end

        # TTS output (what was actually spoken)
        if data[:tts_output]
          lines << '🔊 TTS OUTPUT:'
          lines << "  #{data[:tts_output]}"
          lines << ''
        end

        # Inner thoughts
        if data[:inner_thoughts]
          lines << '💭 INNER THOUGHTS:'
          lines << "  #{data[:inner_thoughts]}"
          lines << ''
        end

        # Continue conversation flag
        if data.key?(:continue_conversation)
          lines << "🔄 CONTINUE CONVERSATION: #{data[:continue_conversation]}"
          lines << ''
        end

        # Model info and timing
        metadata_parts = []
        metadata_parts << "Model: #{data[:model]}" if data[:model]
        metadata_parts << "Duration: #{data[:duration_ms]}ms" if data[:duration_ms]
        metadata_parts << "Cost: $#{data[:cost]}" if data[:cost]

        if metadata_parts.any?
          lines << "📊 METADATA: #{metadata_parts.join(' | ')}"
          lines << ''
        end

        lines.join("\n")
      end

      def write_to_log(entry)
        File.open(@log_file_path, 'a') do |file|
          file.puts entry
          file.puts # Extra blank line between conversations
        end
      rescue StandardError => e
        # Fall back to SimpleLogger if file writing fails
        SimpleLogger.log_error(
          error: e,
          message: 'Failed to write to conversation log file',
          tagged: %i[conversation_logger error]
        )
      end

      def ensure_log_directory
        log_dir = File.dirname(@log_file_path)
        FileUtils.mkdir_p(log_dir)
      end
    end
  end
end
