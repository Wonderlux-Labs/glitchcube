# frozen_string_literal: true

module Services
  # ConversationTracer tracks detailed flow through the conversation system
  # Provides debugging insights into service interactions, timings, and data transformations
  class ConversationTracer
    attr_reader :trace_id, :session_id, :traces

    def initialize(session_id: nil, enabled: true)
      @session_id = session_id
      @trace_id = SecureRandom.hex(8)
      @enabled = enabled && (GlitchCube.config.environment == 'development' || GlitchCube.config.conversation_tracing_enabled?)
      @traces = []
      @current_step = 0
      @start_time = Time.now
      @mutex = Mutex.new
    end

    # Start tracing a conversation flow
    def start_conversation(message:, context:, persona:)
      return unless @enabled

      add_trace(
        step: next_step,
        service: 'ConversationModule',
        action: 'start_conversation',
        timestamp: Time.now,
        data: {
          message: truncate_for_log(message),
          context: sanitize_context(context),
          persona: persona
        },
        metadata: {
          session_id: @session_id,
          trace_id: @trace_id
        }
      )
    end

    # Trace session lookup/creation
    def trace_session_lookup(session_data:, created:)
      return unless @enabled

      add_trace(
        step: next_step,
        service: 'ConversationSession',
        action: created ? 'create_session' : 'find_session',
        timestamp: Time.now,
        data: {
          session_id: session_data[:session_id],
          conversation_count: session_data[:message_count] || 0,
          created: created
        },
        timing: timing_since_start
      )
    end

    # Trace system prompt building
    def trace_system_prompt(persona:, context:, prompt_length:, memories_injected: 0)
      return unless @enabled

      add_trace(
        step: next_step,
        service: 'SystemPromptService',
        action: 'build_prompt',
        timestamp: Time.now,
        data: {
          persona: persona,
          prompt_length: prompt_length,
          memories_injected: memories_injected,
          has_location: !context[:location].nil?,
          context_keys: context.keys.sort
        },
        timing: timing_since_start
      )
    end

    # Trace memory injection process
    def trace_memory_injection(location:, memories:, formatted_context:)
      return unless @enabled

      add_trace(
        step: next_step,
        service: 'MemoryRecallService',
        action: 'inject_memories',
        timestamp: Time.now,
        data: {
          location: location,
          memories_found: memories&.size || 0,
          memory_details: memories&.map do |mem|
            {
              id: mem.id,
              category: mem.category,
              emotional_intensity: mem.emotional_intensity,
              recall_count: mem.recall_count,
              content_preview: truncate_for_log(mem.content, 100)
            }
          end || [],
          context_length: formatted_context&.length || 0
        },
        timing: timing_since_start
      )
    end

    # Trace LLM service call
    def trace_llm_call(messages:, options:, response: nil, error: nil)
      return unless @enabled

      step_start = Time.now

      trace_data = {
        message_count: messages&.size || 0,
        model: options[:model],
        temperature: options[:temperature],
        max_tokens: options[:max_tokens],
        has_tools: !options[:tools].nil?,
        has_structured_output: !options[:response_format].nil?
      }

      if response
        trace_data.merge!(
          response_length: response.response_text&.length || 0,
          model_used: response.model,
          usage: response.usage,
          cost: response.cost,
          has_tool_calls: response.has_tool_calls?,
          continue_conversation: response.continue_conversation?
        )
      end

      if error
        trace_data.merge!(
          error_class: error.class.name,
          error_message: error.message
        )
      end

      add_trace(
        step: next_step,
        service: 'LLMService',
        action: 'complete_with_messages',
        timestamp: step_start,
        data: trace_data,
        timing: timing_since_start,
        success: error.nil?
      )
    end

    # Trace tool execution
    def trace_tool_execution(tool_calls:, results:, execution_time_ms:)
      return unless @enabled

      add_trace(
        step: next_step,
        service: 'ToolExecutor',
        action: 'execute_tools',
        timestamp: Time.now,
        data: {
          tool_count: tool_calls&.size || 0,
          tools_called: tool_calls&.map { |call| call[:function][:name] } || [],
          results: results&.map do |result|
            {
              tool_name: result[:tool_name],
              success: result[:success],
              result_length: result[:result]&.to_s&.length || 0,
              error: result[:error]
            }
          end || [],
          execution_time_ms: execution_time_ms
        },
        timing: timing_since_start
      )
    end

    # Trace TTS call
    def trace_tts_call(text:, persona:, success:, duration_ms:, error: nil)
      return unless @enabled

      add_trace(
        step: next_step,
        service: 'TTSService',
        action: 'speak',
        timestamp: Time.now,
        data: {
          text_length: text&.length || 0,
          persona: persona,
          success: success,
          duration_ms: duration_ms,
          error: error
        },
        timing: timing_since_start
      )
    end

    # Trace database operations
    def trace_db_operation(operation:, model:, details:, duration_ms:)
      return unless @enabled

      add_trace(
        step: next_step,
        service: 'Database',
        action: operation,
        timestamp: Time.now,
        data: {
          model: model,
          details: details,
          duration_ms: duration_ms
        },
        timing: timing_since_start
      )
    end

    # Trace Home Assistant integration
    def trace_ha_integration(action:, success:, entity_id: nil, response: nil, error: nil)
      return unless @enabled

      add_trace(
        step: next_step,
        service: 'HomeAssistantClient',
        action: action,
        timestamp: Time.now,
        data: {
          entity_id: entity_id,
          success: success,
          response_keys: response&.keys || [],
          error: error
        },
        timing: timing_since_start
      )
    end

    # Mark conversation completion
    def complete_conversation(result:, total_duration_ms:)
      return unless @enabled

      add_trace(
        step: next_step,
        service: 'ConversationModule',
        action: 'complete_conversation',
        timestamp: Time.now,
        data: {
          response_length: result[:response]&.length || 0,
          persona: result[:persona],
          cost: result[:cost],
          tokens: result[:tokens],
          continue_conversation: result[:continue_conversation],
          has_error: !result[:error].nil?,
          total_duration_ms: total_duration_ms
        },
        timing: timing_since_start
      )

      # Store trace in Redis for later retrieval
      store_trace if @enabled
    end

    # Get formatted trace for display
    def formatted_trace
      return {} unless @enabled

      {
        trace_id: @trace_id,
        session_id: @session_id,
        started_at: @start_time.iso8601,
        total_steps: @traces.size,
        total_duration_ms: ((Time.now - @start_time) * 1000).round,
        traces: @traces
      }
    end

    # Class method to retrieve trace by ID
    def self.get_trace(trace_id)
      return nil unless GlitchCube.config.environment == 'development' || GlitchCube.config.conversation_tracing_enabled?

      redis = Redis.new(url: GlitchCube.config.redis_url)
      data = redis.get("conversation_trace:#{trace_id}")
      return nil unless data

      JSON.parse(data, symbolize_names: true)
    rescue Redis::CannotConnectError, JSON::ParserError
      nil
    end

    # Class method to get traces for a session
    def self.get_session_traces(session_id, limit: 10)
      return [] unless GlitchCube.config.environment == 'development' || GlitchCube.config.conversation_tracing_enabled?

      redis = Redis.new(url: GlitchCube.config.redis_url)
      trace_keys = redis.keys('conversation_trace:*')

      traces = []
      trace_keys.each do |key|
        data = redis.get(key)
        next unless data

        trace = JSON.parse(data, symbolize_names: true)
        traces << trace if trace[:session_id] == session_id
      rescue JSON::ParserError
        next
      end

      traces.sort_by { |t| t[:started_at] }.reverse.first(limit)
    rescue Redis::CannotConnectError
      []
    end

    private

    def add_trace(step:, service:, action:, timestamp:, data:, timing: nil, success: true, metadata: {})
      @mutex.synchronize do
        @traces << {
          step: step,
          service: service,
          action: action,
          timestamp: timestamp.iso8601(3),
          data: data,
          timing_ms: timing || timing_since_start, # Default to timing since start if not provided
          success: success,
          metadata: metadata
        }
      end
    end

    def next_step
      @current_step += 1
    end

    def timing_since_start
      ((Time.now - @start_time) * 1000).round
    end

    def truncate_for_log(text, limit = 200)
      return nil unless text
      return text if text.length <= limit

      "#{text[0..(limit - 4)]}..."
    end

    def sanitize_context(context)
      # Remove sensitive data from context for logging
      sanitized = context.dup
      sanitized.delete(:api_key)
      sanitized.delete(:token)
      sanitized.delete(:password)
      sanitized
    end

    def store_trace
      return unless @enabled

      begin
        redis = Redis.new(url: GlitchCube.config.redis_url)
        redis.setex(
          "conversation_trace:#{@trace_id}",
          3600, # 1 hour TTL
          formatted_trace.to_json
        )
      rescue Redis::CannotConnectError => e
        puts "Warning: Could not store conversation trace: #{e.message}"
      end
    end
  end
end
