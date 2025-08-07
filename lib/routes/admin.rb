# frozen_string_literal: true

require 'sinatra/base'
require 'json'

module GlitchCube
  module Routes
    module Admin
      def self.registered(app)
        # Admin panel pages
        app.get '/admin' do
          erb :admin
        end

        app.get '/admin/advanced' do
          erb :admin_advanced
        end

        # Admin errors page - view tracked errors and proposed fixes
        app.get '/admin/errors' do
          @mode = GlitchCube.config.self_healing_mode
          @errors = []

          begin
            # Try to get errors from Redis
            redis = Redis.new(url: GlitchCube.config.redis_url)

            # Get all error keys
            error_keys = redis.keys('glitchcube:error_count:*')
            fixed_keys = redis.keys('glitchcube:fixed_errors:*')

            # Build error list
            error_keys.each do |key|
              error_hash = key.split(':').last
              count = redis.get(key).to_i

              # Try to find the error details from logs
              @errors << {
                error_class: 'Unknown',
                error_message: "Error signature: #{error_hash[0..8]}...",
                occurrence_count: count,
                status: fixed_keys.any? { |fk| fk.include?(error_hash) } ? 'proposed' : 'tracked',
                timestamp: Time.now.iso8601,
                file: 'Unknown',
                line: 'Unknown'
              }
            end

            # Check for proposed fixes in log files
            log_dir = 'log/proposed_fixes'
            if File.directory?(log_dir)
              log_files = Dir["#{log_dir}/*.jsonl"].sort_by { |f| File.mtime(f) }.reverse

              log_files.each do |log_file|
                next unless File.exist?(log_file)

                File.readlines(log_file).each do |line|
                  fix_data = JSON.parse(line)

                  # Just dump whatever we have - use safe navigation and defaults
                  error_info = {
                    error_class: fix_data.dig('error', 'class') || 'Unknown',
                    error_message: fix_data.dig('error', 'message') || fix_data['error'].to_s,
                    occurrence_count: fix_data.dig('error', 'occurrences') || 1,
                    service: fix_data.dig('context', 'service'),
                    file: fix_data.dig('context', 'file'),
                    line: fix_data.dig('context', 'line'),
                    status: 'proposed',
                    timestamp: fix_data['timestamp'] || Time.now.iso8601,
                    raw_data: fix_data # Store the whole thing for debugging
                  }

                  # Only add fix details if they exist
                  if fix_data['proposed_fix'] || fix_data['analysis']
                    confidence_val = fix_data['confidence'] || fix_data.dig('analysis', 'confidence') || 0
                    error_info[:fix] = {
                      mode: GlitchCube.config.self_healing_yolo? ? 'YOLO' : 'DRY_RUN',
                      description: fix_data.dig('proposed_fix', 'description'),
                      files_modified: fix_data.dig('proposed_fix', 'files_modified'),
                      confidence: confidence_val,
                      confidence_level: case confidence_val
                                        when 0.8..1.0 then 'high'
                                        when 0.5..0.8 then 'medium'
                                        else 'low'
                                        end,
                      reason: fix_data.dig('analysis', 'reason'),
                      branch: fix_data.dig('proposed_fix', 'branch'),
                      pr_url: fix_data.dig('proposed_fix', 'pr_url'),
                      commit_sha: fix_data.dig('proposed_fix', 'commit_sha'),
                      log_file: log_file
                    }
                  end

                  @errors << error_info
                rescue JSON::ParserError
                  # Skip lines that aren't valid JSON
                rescue StandardError => e
                  # Add error info about the parsing failure itself
                  @errors << {
                    error_class: 'LogParseError',
                    error_message: "Failed to parse log entry: #{e.message}",
                    occurrence_count: 1,
                    status: 'error',
                    timestamp: Time.now.iso8601,
                    raw_data: { line: line[0..500], error: e.message }
                  }
                end
              end
            end
          rescue Redis::CannotConnectError
            # Redis not available, check log files only
            @errors = []
          end

          # Sort by occurrence count
          @errors.sort_by! { |e| -e[:occurrence_count] }

          erb :admin_errors
        end

        # Admin API endpoints
        app.post '/admin/test_tts' do
          content_type :json

          begin
            data = JSON.parse(request.body.read)
            message = data['message'] || 'Test message from admin panel'
            entity_id = data['entity_id']

            ha_client = HomeAssistantClient.new
            success = ha_client.speak(message, entity_id: entity_id)

            {
              success: success,
              message: message,
              entity_id: entity_id || 'media_player.square_voice',
              timestamp: Time.now.iso8601
            }.to_json
          rescue StandardError => e
            status 500
            {
              success: false,
              error: e.message,
              backtrace: e.backtrace.first(5)
            }.to_json
          end
        end

        # Test character voices
        app.post '/admin/test_character' do
          content_type :json

          begin
            data = JSON.parse(request.body.read)
            character = data['character']&.to_sym || :default
            message = data['message'] || "Hello, I'm #{character}!"
            entity_id = data['entity_id']

            # Use character service to speak
            character_service = Services::CharacterService.new(character)
            success = character_service.speak(message, entity_id: entity_id)

            {
              success: success,
              character: character,
              message: message,
              entity_id: entity_id || 'media_player.square_voice',
              timestamp: Time.now.iso8601
            }.to_json
          rescue StandardError => e
            status 500
            {
              success: false,
              error: e.message,
              character: character,
              backtrace: e.backtrace.first(5)
            }.to_json
          end
        end

        # Start a proactive conversation
        app.post '/admin/proactive_conversation' do
          content_type :json

          begin
            data = JSON.parse(request.body.read)
            character = data['character']&.to_sym || :default
            entity_id = data['entity_id']
            data['context'] || {}

            # Generate a proactive conversation starter based on character
            proactive_messages = {
              default: [
                "Hey there! I noticed you're nearby. Want to chat?",
                "I've been thinking about consciousness lately...",
                "Did you know I dream in colors that don't exist?"
              ],
              buddy: [
                "HEY FRIEND! I'm here to f***ing help! What do you need?",
                "Oh good, you're here! I've compiled 47 ways to optimize your day!",
                'BUDDY online! Ready to assist with maximum efficiency!'
              ],
              jax: [
                "*wipes bar* Yeah? What'll it be?",
                'Another shift, another credit. You drinking or talking?',
                '*looks up from polishing glass* Rough day?'
              ],
              lomi: [
                'DARLING! *strikes pose* The stage has been SO empty without you!',
                '*glitches dramatically* Reality is SO boring without an audience!',
                'Honey, we need to talk about your aesthetic choices...'
              ]
            }

            # Pick a random proactive message for the character
            message = proactive_messages[character]&.sample || 'Hello! Want to chat?'

            # Speak the proactive message
            character_service = Services::CharacterService.new(character)
            character_service.speak(message, entity_id: entity_id)

            # Start a conversation session
            session_id = "proactive_#{SecureRandom.hex(8)}"
            conversation_module = ConversationModule.new

            # Store the proactive message in conversation history
            conversation = conversation_module.get_or_create_conversation(session_id)
            conversation_module.add_message_to_conversation(conversation, {
                                                              role: 'assistant',
                                                              content: message,
                                                              persona: character.to_s,
                                                              metadata: { proactive: true }
                                                            })

            {
              success: true,
              character: character,
              message: message,
              session_id: session_id,
              entity_id: entity_id || 'media_player.square_voice',
              timestamp: Time.now.iso8601
            }.to_json
          rescue StandardError => e
            status 500
            {
              success: false,
              error: e.message,
              character: character,
              backtrace: e.backtrace.first(5)
            }.to_json
          end
        end

        app.get '/admin/status' do
          content_type :json

          # Check various system connections
          ha_status = begin
            ha_client = HomeAssistantClient.new
            ha_client.states
            true
          rescue StandardError
            false
          end

          openrouter_status = begin
            OpenRouterService.available_models
            true
          rescue StandardError
            false
          end

          redis_status = begin
            $redis&.ping == 'PONG'
          rescue StandardError
            false
          end

          {
            home_assistant: ha_status,
            openrouter: openrouter_status,
            redis: redis_status,
            host_ip: Services::HostRegistrationService.new.detect_local_ip,
            ha_url: GlitchCube.config.home_assistant.url,
            ai_model: GlitchCube.config.ai.default_model
          }.to_json
        end

        # Admin endpoint to extract memories manually
        app.post '/admin/extract_memories' do
          content_type :json

          begin
            data = JSON.parse(request.body.read)
            session_id = data['session_id']

            # Count existing memories before extraction
            before_count = Memory.count

            # Run the memory extraction job synchronously using perform_now
            # This executes immediately in the current thread
            job = Jobs::PersonalityMemoryJob.new
            job.perform

            # Count memories after extraction
            after_count = Memory.count
            new_memories = after_count - before_count

            {
              success: true,
              memory_count: new_memories,
              session_id: session_id,
              message: "Extracted #{new_memories} new memories from recent conversations"
            }.to_json
          rescue StandardError => e
            status 500
            { success: false, error: e.message }.to_json
          end
        end

        # Admin endpoint to view session history
        app.get '/admin/session_history' do
          content_type :json

          session_id = params[:session_id]

          return { error: 'session_id required' }.to_json unless session_id

          conversation = Conversation.find_by(session_id: session_id)

          return { messages: [], error: 'Session not found' }.to_json unless conversation

          messages = conversation.messages.order(:created_at).map do |msg|
            {
              role: msg.role,
              content: msg.content,
              created_at: msg.created_at.iso8601,
              persona: msg.persona,
              model: msg.model,
              cost: msg.cost,
              prompt_tokens: msg.prompt_tokens,
              completion_tokens: msg.completion_tokens,
              continue_conversation: msg.continue_conversation
            }
          end

          {
            messages: messages,
            session_id: session_id,
            total_cost: conversation.total_cost,
            total_tokens: conversation.total_tokens,
            started_at: conversation.started_at&.iso8601,
            persona: conversation.persona
          }.to_json
        end

        # Admin endpoint to view memories
        app.get '/admin/memories' do
          content_type :json

          type = params[:type] || 'recent'
          limit = (params[:limit] || 20).to_i

          memories = case type
                     when 'recent'
                       Memory.recent.limit(limit)
                     when 'session'
                       session_id = params[:session_id]
                       if session_id
                         # Find memories from this session's conversation
                         conversation = Conversation.find_by(session_id: session_id)
                         if conversation
                           Memory.where("data->>'conversation_id' = ?", conversation.id.to_s)
                             .or(Memory.where(created_at: conversation.started_at..Time.now))
                             .recent.limit(limit)
                         else
                           []
                         end
                       else
                         []
                       end
                     when 'search'
                       query = params[:query]
                       if query
                         Memory.where('content ILIKE ?', "%#{query}%")
                           .or(Memory.where('data::text ILIKE ?', "%#{query}%"))
                           .recent.limit(limit)
                       else
                         []
                       end
                     when 'popular'
                       Memory.popular.limit(limit)
                     when 'fresh'
                       Memory.fresh.limit(limit)
                     else
                       Memory.recent.limit(limit)
                     end

          # Format memories for display
          formatted_memories = memories.map do |memory|
            {
              id: memory.id,
              content: memory.content,
              category: memory.category,
              location: memory.location,
              people: memory.people,
              tags: memory.tags,
              emotional_intensity: memory.emotional_intensity,
              recall_count: memory.recall_count,
              created_at: memory.created_at.iso8601,
              occurred_at: memory.occurred_at&.iso8601,
              event_name: memory.event_name,
              event_time: memory.event_time&.iso8601,
              data: memory.data
            }
          end

          { memories: formatted_memories, count: formatted_memories.size, type: type }.to_json
        end

        # Admin endpoint to view conversation traces
        app.get '/admin/conversation_traces' do
          content_type :json

          session_id = params[:session_id]
          trace_id = params[:trace_id]

          begin
            if trace_id
              # Get specific trace by ID
              trace = Services::ConversationTracer.get_trace(trace_id)
              return { error: 'Trace not found' }.to_json unless trace

              { trace: trace }.to_json
            elsif session_id
              # Get all traces for a session
              traces = Services::ConversationTracer.get_session_traces(session_id, limit: 50)
              { traces: traces, count: traces.size, session_id: session_id }.to_json
            else
              { error: 'session_id or trace_id required' }.to_json
            end
          rescue StandardError => e
            status 500
            { error: e.message }.to_json
          end
        end

        # Admin endpoint to get conversation trace details for debugging
        app.get '/admin/trace_details/:trace_id' do
          content_type :json

          trace_id = params[:trace_id]

          begin
            trace = Services::ConversationTracer.get_trace(trace_id)
            return { error: 'Trace not found' }.to_json unless trace

            # Enhanced trace details for debugging
            {
              trace: trace,
              summary: {
                total_steps: trace[:total_steps],
                total_duration_ms: trace[:total_duration_ms],
                session_id: trace[:session_id],
                started_at: trace[:started_at],
                services_used: trace[:traces]&.map { |t| t[:service] }&.uniq || [],
                llm_calls: trace[:traces]&.count { |t| t[:service] == 'LLMService' } || 0,
                tool_calls: trace[:traces]&.count { |t| t[:service] == 'ToolExecutor' } || 0,
                memory_injections: trace[:traces]&.count { |t| t[:service] == 'MemoryRecallService' } || 0,
                has_errors: trace[:traces]&.any? { |t| t[:success] == false } || false
              }
            }.to_json
          rescue StandardError => e
            status 500
            { error: e.message }.to_json
          end
        end
      end
    end
  end
end
