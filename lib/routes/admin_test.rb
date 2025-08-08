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
          
          erb :admin_test
        end

        # Handle conversation test form submission
        app.post '/admin/test/conversation' do
          begin
            message = params[:message]
            persona = params[:persona] || 'buddy'
            session_id = params[:session_id].to_s.strip
            session_id = nil if session_id.empty?

            # Call the main conversation endpoint
            conversation = ConversationModule.new(persona: persona)
            @conversation_response = conversation.call(
              message: message,
              context: { 
                session_id: session_id,
                source: 'admin_test'
              }
            )
            
            # Store session ID for next request
            @session_id = @conversation_response[:session_id]
            
          rescue StandardError => e
            @error = "Conversation failed: #{e.message}"
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
          
          erb :admin_test
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
          
          erb :admin_test
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
          require_relative '../services/tool_registry_service'
          @tools = ::Services::ToolRegistryService.discover_tools.map do |name, info|
            {
              name: name,
              description: info[:description],
              category: info[:category]
            }
          end
          
          erb :admin_test_tools
        end

        # Execute tool form submission
        app.post '/admin/test/tools/:tool_name' do
          tool_name = params[:tool_name]
          
          begin
            # Parse parameters from form
            tool_params = {}
            params.each do |key, value|
              next if ['tool_name', 'captures'].include?(key)
              tool_params[key.to_sym] = value unless value.to_s.strip.empty?
            end
            
            require_relative '../services/tool_registry_service'
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
          
          erb :admin_test_tools
        end
      end
    end
  end
end