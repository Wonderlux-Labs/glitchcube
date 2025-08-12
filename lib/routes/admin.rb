# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require_relative 'admin/scenarios'
require_relative 'admin/benchmarks'

module GlitchCube
  module Routes
    module Admin
      def self.registered(app)
        # Main admin interface
        app.get '/admin' do
          # Get current GPS location for display
          begin
            gps_service = Services::GpsTrackingService.new
            @current_location = gps_service.current_location
          rescue StandardError => e
            @current_location = { error: e.message }
          end

          # Security check: GPS spoofing only available in development/test
          @show_gps_spoofing = %w[development test].include?(ENV.fetch('RACK_ENV', nil))

          erb :admin
        end

        # Comprehensive conversation show view for debugging
        app.get '/admin/conversations/:session_id' do
          @session_id = params[:session_id]
          erb :admin_conversation_show
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
            character = data['character']&.to_sym || :default

            # Use CharacterService for consistent TTS path
            character_service = Services::CharacterService.new(character: character)
            success = character_service.speak(message, entity_id: entity_id)

            {
              success: success,
              message: message,
              character: character,
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
            character_service = Services::CharacterService.new(character: character)
            success = character_service.speak(message, entity_id: entity_id)

            # Log if it failed
            unless success

              LogHelper.error("TTS failed for character #{character}: message='#{message}', entity_id='#{entity_id}'")
            end

            {
              success: success,
              character: character,
              message: message,
              entity_id: entity_id || 'media_player.square_voice',
              timestamp: Time.now.iso8601,
              debug: success ? nil : 'Check server logs for details'
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
            character_service = Services::CharacterService.new(character: character)
            character_service.speak(message, entity_id: entity_id)

            # Start a conversation session using standard ActiveRecord system
            session_id = "proactive_#{SecureRandom.hex(8)}"

            # Create new conversation session with ActiveRecord
            session = ::Services::ConversationSession.find_or_create(
              session_id: session_id,
              context: {
                source: 'admin_proactive',
                persona: character.to_s,
                proactive: true
              }
            )

            # Add the proactive message to conversation history
            session.add_message(
              role: 'assistant',
              content: message,
              metadata: { proactive: true, character: character.to_s }
            )

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

          # Initialize all statuses to false, then try to check each
          response = {
            home_assistant: false,
            openrouter: false,
            redis: false,
            host_ip: 'localhost',
            ha_url: 'Not configured',
            ai_model: 'Not configured'
          }

          # Check HA - but don't let it break everything
          begin
            ha_client = HomeAssistantClient.new
            # Just check if we can initialize - don't call states yet
            response[:home_assistant] = true
            response[:ha_url] = ha_client.base_url || 'http://glitch.local:8123'
          rescue StandardError => e
            ::Services::SimpleLogger.error('HA status check error', tagged: %i[admin status error], error: e.message)
          end

          # Check OpenRouter - simple API key check
          begin
            response[:openrouter] = !ENV['OPENROUTER_API_KEY'].nil? && ENV['OPENROUTER_API_KEY'].length > 10
          rescue StandardError => e
            ::Services::SimpleLogger.error('OpenRouter status check error', tagged: %i[admin status error], error: e.message)
          end

          # Check Redis
          begin
            if defined?($redis) && $redis
              response[:redis] = begin
                $redis.ping == 'PONG'
              rescue StandardError
                false
              end
            else
              redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379')
              response[:redis] = redis.ping == 'PONG'
            end
          rescue StandardError => e
            ::Services::SimpleLogger.error('Redis status check error', tagged: %i[admin status error], error: e.message)
          end

          # Get other config safely
          begin
            response[:host_ip] = '192.168.0.56' # From your logs
            response[:ai_model] = GlitchCube.config.ai.default_model || DEFAULT_AI_MODEL || 'google/gemini-2.5-flash'
          rescue StandardError => e
            ::Services::SimpleLogger.error('Config check error', tagged: %i[admin status error], error: e.message)
          end

          response.to_json
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
              model: msg.model_used,
              cost: msg.cost,
              prompt_tokens: msg.prompt_tokens,
              completion_tokens: msg.completion_tokens,
              metadata: msg.metadata || {}
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

        # Simple conversation listing for admin
        app.get '/admin/api/conversations' do
          content_type :json

          limit = (params[:limit] || 20).to_i
          offset = (params[:offset] || 0).to_i

          conversations = Conversation.order(created_at: :desc)
                                      .limit(limit)
                                      .offset(offset)
                                      .includes(:messages)

          formatted_conversations = conversations.map do |conv|
            {
              session_id: conv.session_id,
              persona: conv.persona,
              message_count: conv.message_count,
              started_at: conv.started_at&.iso8601,
              last_message: conv.messages.last&.created_at&.iso8601,
              total_cost: conv.total_cost,
              total_tokens: conv.total_tokens
            }
          end

          {
            conversations: formatted_conversations,
            count: formatted_conversations.size,
            total_count: Conversation.count
          }.to_json
        end

        # Tool testing and isolation interface
        app.get '/admin/tools' do
          erb :admin_tools
        end

        # Log viewer interface
        app.get '/admin/logs' do
          erb :admin_logs
        end

        # API endpoint to fetch log data
        app.get '/admin/api/logs' do
          content_type :json

          lines = (params[:lines] || 100).to_i
          lines = [lines, 1000].min # Cap at 1000 lines for performance

          log_file = ::Services::SimpleLogger.log_file_path

          if File.exist?(log_file)
            # Read last N lines efficiently
            logs = `tail -n #{lines} #{log_file}`.split("\n")

            # Parse log entries
            parsed_logs = logs.map do |line|
              # SimpleLogger format: [HH:MM:SS.mmm] [LEVEL] [ENV] message #tag1 #tag2 (caller) key=value
              if line =~ /^\[(\d{2}:\d{2}:\d{2}\.\d{3})\] \[(\w+)\] \[(\w+)\]\s*(.+)$/
                timestamp = $1
                level = $2
                env = $3
                rest = $4

                # Extract message and tags from the rest
                message = rest
                tags = []

                # Extract tags (format: #tag1 #tag2)
                if rest =~ /^(.+?)\s+(#\w+.*)$/
                  message = $1
                  tag_part = $2
                  tags = tag_part.scan(/#(\w+)/).flatten
                end

                # Extract metadata if present
                metadata = {}
                if message =~ /^(.+?) \{(.+)\}$/
                  message = $1
                  begin
                    metadata = JSON.parse("{#{$2}}")
                  rescue StandardError
                    # Ignore malformed metadata
                  end
                end

                {
                  timestamp: timestamp,
                  level: level.downcase,
                  tags: tags,
                  message: message,
                  metadata: metadata,
                  raw: line
                }
              else
                # Unparsed line
                {
                  timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S.%L'),
                  level: 'info',
                  tags: [],
                  message: line,
                  metadata: {},
                  raw: line
                }
              end
            end

            {
              logs: parsed_logs.reverse, # Most recent first
              total_lines: logs.size,
              log_file: log_file
            }.to_json
          else
            {
              logs: [],
              total_lines: 0,
              error: 'Log file not found',
              log_file: log_file
            }.to_json
          end
        rescue StandardError => e
          {
            logs: [],
            error: e.message,
            backtrace: e.backtrace.first(3)
          }.to_json
        end

        # Tool discovery and listing endpoint
        app.get '/admin/api/tools' do
          content_type :json

          begin
            tool_classes = ::Services::ToolRegistryService.discover_tools

            # Return tool classes for left panel
            formatted_tools = tool_classes.map do |class_name, class_info|
              {
                name: class_name,
                display_name: class_name.gsub(/Tool$/, ''),
                description: class_info[:description],
                category: class_info[:category],
                methods: class_info[:methods],
                examples: [],
                class_name: class_name
              }
            end

            {
              success: true,
              tools: formatted_tools,
              count: formatted_tools.size
            }.to_json
          rescue StandardError => e
            # Log the full error for debugging
            ::Services::SimpleLogger.error('Tool API Error',
                                           tagged: %i[admin tool error],
                                           error_class: e.class.name,
                                           error: e.message,
                                           backtrace: ENV['RACK_ENV'] == 'development' ? e.backtrace.first(5) : nil)

            status 500
            {
              success: false,
              error: e.message,
              error_type: e.class.to_s,
              backtrace: ENV['RACK_ENV'] == 'development' ? e.backtrace.first(5) : nil
            }.compact.to_json
          end
        end

        # Tool execution endpoint for testing
        app.post '/admin/api/tools/:tool_name/execute' do
          content_type :json
          tool_name = params[:tool_name]

          begin
            data = JSON.parse(request.body.read)
            parameters = data['parameters'] || {}

            start_time = Time.now
            # Get the tool class context from the method name
            tool_classes_data = ::Services::ToolRegistryService.discover_tools
            target_tool_class = nil

            tool_classes_data.each do |class_name, class_info|
              if class_info[:methods] && class_info[:methods][tool_name]
                target_tool_class = class_name
                break
              end
            end

            result = ::Services::ToolRegistryService.execute_tool_directly(tool_name, parameters, tool_class: target_tool_class)
            execution_time = ((Time.now - start_time) * 1000).round

            # Use the tool executor result directly, just add debug info
            enhanced_result = result.dup
            enhanced_result[:parameters] = parameters
            enhanced_result[:execution_time_ms] = execution_time
            enhanced_result[:timestamp] = Time.now.iso8601
            # Get recent HA service call logs for debugging
            recent_ha_logs = Admin.get_recent_ha_logs(5) # Get last 5 HA calls

            enhanced_result[:debug_info] = {
              ha_circuit_breaker_open: false, # TODO: Get actual circuit breaker status
              recent_ha_calls: recent_ha_logs,
              ha_url: ENV['HOME_ASSISTANT_URL'] || ENV['HA_URL'] || 'Not configured',
              tool_class_context: target_tool_class
            }

            enhanced_result.to_json
          rescue JSON::ParserError => e
            status 400
            { success: false, error: "Invalid JSON: #{e.message}" }.to_json
          rescue StandardError => e
            ::Services::SimpleLogger.error('Tool Execution Error',
                                           tagged: %i[admin tool error],
                                           error_class: e.class.name,
                                           error: e.message,
                                           backtrace: ENV['RACK_ENV'] == 'development' ? e.backtrace.first(5) : nil)

            status 500
            {
              success: false,
              error: e.message,
              error_type: e.class.to_s,
              backtrace: ENV['RACK_ENV'] == 'development' ? e.backtrace.first(5) : nil
            }.compact.to_json
          end
        end

        # Get all tool methods as individual functions
        app.get '/admin/api/tools/methods' do
          content_type :json

          begin
            tool_names = params[:tools]&.split(',')&.map(&:strip)

            functions = ::Services::ToolRegistryService.get_tool_methods_as_functions(tool_names)

            {
              success: true,
              functions: functions,
              count: functions.size,
              tool_names: tool_names
            }.to_json
          rescue StandardError => e
            status 500
            { success: false, error: e.message }.to_json
          end
        end

        # Get OpenAI function specifications for tools
        app.get '/admin/api/tools/openai-functions' do
          content_type :json

          begin
            character = params[:character]
            tool_names = params[:tools]&.split(',')&.map(&:strip)

            functions = if character
                          ::Services::ToolRegistryService.get_tools_for_character(character)
                        else
                          ::Services::ToolRegistryService.get_openai_functions(tool_names)
                        end

            {
              success: true,
              functions: functions,
              character: character,
              tool_names: tool_names
            }.to_json
          rescue StandardError => e
            status 500
            { success: false, error: e.message }.to_json
          end
        end

        # Comprehensive conversation debugging endpoint
        app.get '/admin/api/conversations/:session_id' do
          content_type :json
          session_id = params[:session_id]

          begin
            # Get conversation and messages
            conversation = Conversation.find_by(session_id: session_id)
            return { error: 'Conversation not found' }.to_json unless conversation

            messages = conversation.messages.order(:created_at).map do |msg|
              {
                id: msg.id,
                role: msg.role,
                content: msg.content,
                created_at: msg.created_at.iso8601,
                persona: msg.persona,
                model: msg.model_used,
                cost: msg.cost,
                prompt_tokens: msg.prompt_tokens,
                completion_tokens: msg.completion_tokens,
                continue_conversation: msg.respond_to?(:continue_conversation) ? msg.continue_conversation : nil,
                metadata: msg.metadata || {}
              }
            end

            # Simple debugging info instead of complex traces
            debug_info = {
              messages_with_tools: messages.count { |m| m[:metadata]&.dig('tool_calls')&.any? },
              total_duration: conversation.started_at ? (Time.now - conversation.started_at).to_i : 0
            }

            # Get memories related to this session
            memories = begin
              # Find memories from around the time of this conversation
              Memory.where(created_at: conversation.started_at..Time.now)
                    .or(Memory.where("data->>'session_id' = ?", session_id))
                    .or(Memory.where("data->>'conversation_id' = ?", conversation.id.to_s))
                    .recent.limit(50).map do |memory|
                {
                  id: memory.id,
                  content: memory.content,
                  category: memory.category,
                  created_at: memory.created_at.iso8601,
                  data: memory.data
                }
              end
            rescue StandardError
              []
            end

            # Calculate totals
            total_cost = messages.sum { |m| m[:cost] || 0 }
            total_prompt_tokens = messages.sum { |m| m[:prompt_tokens] || 0 }
            total_completion_tokens = messages.sum { |m| m[:completion_tokens] || 0 }

            {
              success: true,
              conversation: {
                session_id: session_id,
                id: conversation.id,
                started_at: conversation.started_at&.iso8601,
                persona: conversation.persona,
                metadata: conversation.metadata || {}
              },
              messages: messages,
              debug_info: debug_info,
              memories: memories,
              analytics: {
                total_messages: messages.length,
                total_cost: total_cost,
                total_prompt_tokens: total_prompt_tokens,
                total_completion_tokens: total_completion_tokens,
                total_tokens: total_prompt_tokens + total_completion_tokens,
                avg_cost_per_message: messages.length.positive? ? total_cost / messages.length : 0,
                conversation_duration: conversation.started_at ? (Time.now - conversation.started_at).to_i : 0
              }
            }.to_json
          rescue StandardError => e
            status 500
            { error: e.message, backtrace: e.backtrace.first(5) }.to_json
          end
        end

        # GPS Spoofing endpoints (development only)

        # Get list of landmarks for typeahead
        app.get '/admin/landmarks' do
          content_type :json

          # Block GPS spoofing in production for security
          unless ENV['RACK_ENV'] == 'development'
            status 403
            return { success: false, error: 'GPS spoofing is only available in development environment' }.to_json
          end

          begin
            landmarks = Landmark.active.order(:name).limit(100).map do |landmark|
              {
                id: landmark.id,
                name: landmark.name,
                latitude: landmark.latitude.to_f,
                longitude: landmark.longitude.to_f,
                landmark_type: landmark.landmark_type,
                description: landmark.description
              }
            end

            { success: true, landmarks: landmarks }.to_json
          rescue StandardError => e
            status 500
            { success: false, error: e.message }.to_json
          end
        end

        # Set spoofed GPS location
        app.post '/admin/spoof_gps' do
          content_type :json

          # Block GPS spoofing in production for security
          unless ENV['RACK_ENV'] == 'development'
            status 403
            return { success: false, error: 'GPS spoofing is only available in development environment' }.to_json
          end

          begin
            data = JSON.parse(request.body.read)
            latitude = data['latitude']&.to_f
            longitude = data['longitude']&.to_f
            name = data['name'] || 'Custom Location'

            unless latitude && longitude
              status 400
              return { success: false, error: 'Latitude and longitude are required' }.to_json
            end

            # Store in Redis like the simulation system does
            require 'redis'
            redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')

            location_data = {
              lat: latitude,
              lng: longitude,
              timestamp: Time.now.iso8601,
              source: 'admin_spoof',
              name: name
            }

            redis.set('current_cube_location', location_data.to_json)

            # Enable simulation mode if not already enabled
            redis.set('cube_simulate_movement', 'true')

            Services::LoggerService.log_api_call(
              service: 'admin',
              endpoint: 'spoof_gps',
              method: 'POST',
              latitude: latitude,
              longitude: longitude,
              name: name,
              success: true
            )

            {
              success: true,
              message: "GPS spoofed to #{name} (#{latitude}, #{longitude})",
              location: location_data
            }.to_json
          rescue StandardError => e
            status 500
            {
              success: false,
              error: e.message,
              backtrace: e.backtrace.first(3)
            }.to_json
          end
        end

        # Clear GPS spoofing (return to real GPS)
        app.delete '/admin/spoof_gps' do
          content_type :json

          # Block GPS spoofing in production for security
          unless ENV['RACK_ENV'] == 'development'
            status 403
            return { success: false, error: 'GPS spoofing is only available in development environment' }.to_json
          end

          begin
            require 'redis'
            redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')

            redis.del('current_cube_location')
            redis.set('cube_simulate_movement', 'false')

            Services::LoggerService.log_api_call(
              service: 'admin',
              endpoint: 'clear_gps_spoof',
              method: 'DELETE',
              success: true
            )

            { success: true, message: 'GPS spoofing cleared, returning to real GPS' }.to_json
          rescue StandardError => e
            status 500
            { success: false, error: e.message }.to_json
          end
        end

        # Get current GPS location (for display) - works in all environments
        app.get '/admin/current_location' do
          content_type :json

          begin
            gps_service = Services::GpsTrackingService.new
            location = gps_service.current_location

            { success: true, location: location }.to_json
          rescue StandardError => e
            status 500
            { success: false, error: e.message }.to_json
          end
        end
      end

      # Get recent Home Assistant service call logs for debugging
      def self.get_recent_ha_logs(limit = 5)
        log_file = ::Services::SimpleLogger.log_file_path
        return [] unless File.exist?(log_file)

        begin
          # Read recent logs and filter for HA service calls
          recent_logs = `tail -n 100 #{log_file}`.split("\n")
          ha_logs = []

          recent_logs.reverse.each do |line|
            break if ha_logs.size >= limit

            # Look for HA-related log entries
            # Parse the log line
            next unless (line.include?('#home_assistant') || line.include?('HA Service') || line.include?('Home Assistant')) && (line =~ /^\[([\d:\.]+)\] \[(\w+)\] \[(\w+)\](.+)$/)

            timestamp = $1
            level = $2.downcase
            message = $4.strip

            ha_logs << {
              timestamp: timestamp,
              level: level,
              message: message,
              raw: line
            }
          end

          ha_logs.reverse # Return in chronological order
        rescue StandardError => e
          [{ error: "Failed to read HA logs: #{e.message}" }]
        end
      end
    end
  end
end
