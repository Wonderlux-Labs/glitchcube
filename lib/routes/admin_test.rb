# frozen_string_literal: true

require 'sinatra/base'

module GlitchCube
  module Routes
    module AdminTest
      def self.registered(app)
        # Simple test interface - no JavaScript required
        app.get '/admin/test' do
          # Load recent conversations for display
          @recent_conversations = Conversation.order(created_at: :desc)
                                              .limit(5)
                                              .map do |conv|
            {
              session_id: conv.session_id,
              persona: conv.persona,
              message_count: conv.message_count,
              started_at: conv.started_at&.strftime('%Y-%m-%d %H:%M'),
              total_cost: conv.total_cost&.round(4) || 0
            }
          end

          erb :admin_test_improved
        end

        # Continuous conversation flow tester
        app.get '/admin/test/flow' do
          erb :admin_test_flow
        end

        # Handle conversation test form submission
        app.post '/admin/test/conversation' do
          begin
            message = params[:message]
            persona = params[:persona] || 'buddy'
            session_id = params[:session_id].to_s.strip
            session_id = nil if session_id.empty?

            # Get model selection from params or session
            selected_model = params[:model].to_s.strip
            if !selected_model.empty?
              # Store the selected model in the session for persistence
              session[:selected_model] = selected_model
              Services::SimpleLogger.debug('Storing model in session', tagged: %i[admin_test model], model: selected_model) if GlitchCube.config.debug?
            elsif session[:selected_model]
              # Use previously selected model from session
              selected_model = session[:selected_model]
              Services::SimpleLogger.debug('Using model from session', tagged: %i[admin_test model], model: selected_model) if GlitchCube.config.debug?
            else
              selected_model = nil
              Services::SimpleLogger.debug('Using default model', tagged: %i[admin_test model]) if GlitchCube.config.debug?
            end

            # Call the main conversation endpoint with tool tracking
            conversation = ConversationModule.new(persona: persona)

            # Enable verbose logging for admin testing
            start_time = Time.now

            # Build context with optional model override
            conversation_context = {
              session_id: session_id,
              source: 'admin_test',
              include_tool_calls: true, # Request tool call info
              verbose: true # Enable verbose mode
            }

            # Add model override if selected
            conversation_context[:model] = selected_model if selected_model

            @conversation_response = conversation.call(
              message: message,
              context: conversation_context
            )

            # Store session ID and other details for next request
            @session_id = @conversation_response[:session_id]
            @selected_persona = persona
            @last_message = message
            @selected_model = selected_model

            # Calculate response time
            @response_time = ((Time.now - start_time) * 1000).round
          rescue StandardError => e
            @error = "Conversation failed: #{e.message}"
            Services::SimpleLogger.error('ERROR in conversation',
                                         tagged: %i[admin_test conversation error],
                                         error: e.message,
                                         backtrace: GlitchCube.config.debug? ? e.backtrace.first(5) : nil)
          end

          # Reload recent conversations
          @recent_conversations = Conversation.order(created_at: :desc).limit(5).map do |conv|
            {
              session_id: conv.session_id,
              persona: conv.persona,
              message_count: conv.message_count,
              started_at: conv.started_at&.strftime('%Y-%m-%d %H:%M'),
              total_cost: conv.total_cost&.round(4) || 0
            }
          end

          erb :admin_test_improved
        end

        # Handle TTS test form submission
        app.post '/admin/test/tts' do
          begin
            message = params[:message]
            character = params[:character]&.to_sym || :buddy

            character_service = ::Services::CharacterService.new(character: character)
            success = character_service.speak(message)

            @tts_result = {
              success: success,
              character: character,
              message: message
            }
          rescue StandardError => e
            @tts_result = {
              success: false,
              error: e.message
            }
          end

          erb :admin_test_improved
        end

        # View session details
        app.get '/admin/test/sessions/:session_id' do
          @session_id = params[:session_id]
          @conversation = Conversation.find_by(session_id: @session_id)

          if @conversation
            @messages = @conversation.messages.order(:created_at).map do |msg|
              {
                role: msg.role,
                content: msg.content,
                created_at: msg.created_at.strftime('%H:%M:%S'),
                persona: msg.persona,
                cost: msg.cost&.round(4),
                metadata: msg.metadata
              }
            end

            @total_cost = @conversation.total_cost&.round(4) || 0
            @total_tokens = @conversation.total_tokens || 0
          else
            @error = "Session not found: #{@session_id}"
          end

          erb :admin_test_session
        end

        # List all sessions
        app.get '/admin/test/sessions' do
          @conversations = Conversation.order(created_at: :desc)
                                       .limit(20)
                                       .map do |conv|
            {
              session_id: conv.session_id,
              persona: conv.persona,
              message_count: conv.message_count,
              started_at: conv.started_at&.strftime('%Y-%m-%d %H:%M'),
              last_message: conv.messages.last&.created_at&.strftime('%Y-%m-%d %H:%M'),
              total_cost: conv.total_cost&.round(4) || 0
            }
          end

          erb :admin_test_sessions
        end

        # View memories
        app.get '/admin/test/memories' do
          @memories = Memory.recent.limit(20).map do |memory|
            {
              id: memory.id,
              content: memory.content,
              category: memory.category,
              location: memory.location,
              emotional_intensity: (memory.emotional_intensity * 100).round,
              recall_count: memory.recall_count,
              created_at: memory.created_at.strftime('%Y-%m-%d %H:%M')
            }
          end

          erb :admin_test_memories
        end

        # Test tools
        app.get '/admin/test/tools' do
          @tools = ::Services::ToolRegistryService.discover_tools.map do |name, info|
            {
              name: name,
              description: info[:description],
              category: info[:category]
            }
          end

          # Redirect to the main tools explorer
          redirect '/admin/tools'
        end

        # Execute tool form submission
        app.post '/admin/test/tools/:tool_name' do
          tool_name = params[:tool_name]

          begin
            # Parse parameters from form
            tool_params = {}
            params.each do |key, value|
              next if %w[tool_name captures].include?(key)

              tool_params[key.to_sym] = value unless value.to_s.strip.empty?
            end

            @tool_result = ::Services::ToolRegistryService.execute_tool_directly(tool_name, tool_params)
          rescue StandardError => e
            @tool_result = { success: false, error: e.message }
          end

          # Reload tools list
          @tools = ::Services::ToolRegistryService.discover_tools.map do |name, info|
            {
              name: name,
              description: info[:description],
              category: info[:category]
            }
          end

          # Redirect to the main tools explorer
          redirect '/admin/tools'
        end
      end
    end
  end
end
