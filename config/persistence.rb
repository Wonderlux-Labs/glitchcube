# frozen_string_literal: true

# Persistence configuration for Desiru
# This file configures Desiru's persistence layer for tracking module executions,
# performance metrics, and optimization history.

require 'desiru'

module GlitchCube
  module Persistence
    class << self
      def configure!
        # For now, we'll use SQLite for simplicity and portability
        # This can be changed to PostgreSQL later if needed:
        # postgres://username:password@localhost/glitchcube

        database_url = if GlitchCube.config.database_url && !GlitchCube.config.database_url.empty?
                         # Production: Use PostgreSQL if DATABASE_URL is set
                         GlitchCube.config.database_url
                       elsif GlitchCube.config.test?
                         # Test: Use in-memory SQLite
                         'sqlite::memory:'
                       else
                         # Development: Use local SQLite file
                         'sqlite://data/glitchcube.db'
                       end

        # Configure Desiru persistence
        Desiru::Persistence.database_url = database_url
        Desiru::Persistence.connect!

        # Run migrations to create necessary tables
        Desiru::Persistence.migrate!

        puts "✅ Desiru persistence configured with: #{database_url.split('@').last}"
      rescue StandardError => e
        puts "⚠️  Warning: Desiru persistence not configured: #{e.message}"
        puts '   Running without persistence - module history will not be tracked'
      end

      def track_conversation(module_name, input, output, metadata = {})
        return unless persistence_enabled?

        execution = Desiru::Persistence[:module_executions].create_for_module(
          module_name,
          input
        )

        Desiru::Persistence[:module_executions].complete(
          execution.id,
          output,
          metadata
        )
      rescue StandardError => e
        puts "Failed to track conversation: #{e.message}"
      end

      def get_conversation_history(limit: 10)
        return [] unless persistence_enabled?

        Desiru::Persistence[:module_executions]
          .recent(limit)
          .map { |exec| format_execution(exec) }
      rescue StandardError => e
        puts "Failed to get conversation history: #{e.message}"
        []
      end

      def get_module_analytics(module_name)
        return {} unless persistence_enabled?

        {
          total_executions: count_executions(module_name),
          success_rate: calculate_success_rate(module_name),
          avg_response_time: average_response_time(module_name),
          recent_errors: recent_errors(module_name)
        }
      rescue StandardError => e
        puts "Failed to get module analytics: #{e.message}"
        {}
      end

      def store_conversation_summary(summary_data)
        return unless persistence_enabled?

        # For now, track conversation summaries as a special type of execution
        # This allows us to query them later and maintain consistency with existing structure
        execution = Desiru::Persistence[:module_executions].create_for_module(
          'conversation_summarizer',
          summary_data[:key_points] || 'Summary generation'
        )

        Desiru::Persistence[:module_executions].complete(
          execution.id,
          summary_data.to_json,
          {
            session_id: summary_data[:session_id],
            summary_type: 'conversation',
            interaction_count: summary_data[:interaction_count]
          }
        )

        puts "Conversation summary stored for session #{summary_data[:session_id]}"
      rescue StandardError => e
        puts "Failed to store summary: #{e.message}"
      end

      def get_conversation_summaries(limit: 10)
        return [] unless persistence_enabled?

        Desiru::Persistence[:module_executions]
          .where(module_name: 'conversation_summarizer')
          .order(Sequel.desc(:created_at))
          .limit(limit)
          .map { |exec| JSON.parse(exec[:output]) rescue exec[:output] }
      rescue StandardError => e
        puts "Failed to get conversation summaries: #{e.message}"
        []
      end

      private

      def persistence_enabled?
        defined?(Desiru::Persistence::Database) && Desiru::Persistence::Database.connected?
      rescue StandardError
        false
      end

      def format_execution(execution)
        {
          id: execution[:id],
          module: execution[:module_name],
          input: execution[:input],
          output: execution[:output],
          created_at: execution[:created_at],
          duration_ms: execution[:duration_ms],
          success: execution[:success]
        }
      end

      def count_executions(module_name)
        Desiru::Persistence[:module_executions]
          .where(module_name: module_name)
          .count
      end

      def calculate_success_rate(module_name)
        executions = Desiru::Persistence[:module_executions]
          .where(module_name: module_name)
          .select(:success)

        return 0.0 if executions.empty?

        success_count = executions.count { |e| e[:success] }
        (success_count.to_f / executions.count * 100).round(2)
      end

      def average_response_time(module_name)
        times = Desiru::Persistence[:module_executions]
          .where(module_name: module_name)
          .where { duration_ms.positive? }
          .select_map(:duration_ms)

        return 0 if times.empty?

        (times.sum.to_f / times.count).round(2)
      end

      def recent_errors(module_name, limit: 5)
        Desiru::Persistence[:module_executions]
          .where(module_name: module_name, success: false)
          .order(Sequel.desc(:created_at))
          .limit(limit)
          .map { |e| format_execution(e) }
      end
    end
  end
end
