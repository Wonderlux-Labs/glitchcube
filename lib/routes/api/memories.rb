# frozen_string_literal: true

require 'json'

module Routes
  module Api
    module Memories
      def self.registered(app)
        # GET /api/v1/memories/recent - Get recent memories
        app.get '/api/v1/memories/recent' do
          content_type :json
          begin
            limit = (params[:limit] || 10).to_i
            limit = [limit, 50].min # Cap at 50

            memories = Memory.recent.limit(limit)

            result = memories.map do |memory|
              {
                id: memory.id,
                content: memory.content,
                category: memory.category,
                importance: memory.importance,
                created_at: memory.created_at&.iso8601,
                data: memory.data
              }
            end

            json({
                   success: true,
                   memories: result,
                   count: result.size,
                   timestamp: Time.now.iso8601
                 })
          rescue StandardError => e
            Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to get recent memories')
            status 500
            json({
                   success: false,
                   error: e.message,
                   timestamp: Time.now.iso8601
                 })
          end
        end

        # GET /api/v1/memories/search - Query memories
        app.get '/api/v1/memories/search' do
          content_type :json
          begin
            query = params[:q]
            unless query
              status 400
              return json({
                            success: false,
                            error: 'Missing query parameter (?q=search_term)',
                            timestamp: Time.now.iso8601
                          })
            end

            limit = (params[:limit] || 10).to_i
            limit = [limit, 50].min

            # Simple text search in content and context
            memories = Memory.where('content ILIKE ? OR data::text ILIKE ?', "%#{query}%", "%#{query}%")
                             .recent
                             .limit(limit)

            result = memories.map do |memory|
              {
                id: memory.id,
                content: memory.content,
                category: memory.category,
                importance: memory.importance,
                created_at: memory.created_at&.iso8601,
                data: memory.data
              }
            end

            json({
                   success: true,
                   query: query,
                   memories: result,
                   count: result.size,
                   timestamp: Time.now.iso8601
                 })
          rescue StandardError => e
            Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to search memories')
            status 500
            json({
                   success: false,
                   error: e.message,
                   timestamp: Time.now.iso8601
                 })
          end
        end

        # GET /api/v1/summaries/recent - Get recent summaries by type
        app.get '/api/v1/summaries/recent' do
          content_type :json
          begin
            limit = (params[:limit] || 10).to_i
            limit = [limit, 50].min

            # Get recent memories (no summary type filtering since that doesn't exist yet)
            memories = Memory.recent.limit(limit).to_a

            # Group by location or category for organization
            grouped = memories.group_by { |m| m.location || m.category || 'general' }

            result = grouped.transform_values do |memory_list|
              memory_list.map do |memory|
                {
                  id: memory.id,
                  content: memory.content,
                  location: memory.location,
                  category: memory.category,
                  tags: memory.tags,
                  created_at: memory.created_at&.iso8601,
                  story_value: memory.story_value
                }
              end
            end

            json({
                   success: true,
                   memories_by_location: result,
                   total_count: memories.size,
                   timestamp: Time.now.iso8601
                 })
          rescue StandardError => e
            Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to get recent summaries')
            status 500
            json({
                   success: false,
                   error: e.message,
                   timestamp: Time.now.iso8601
                 })
          end
        end
      end
    end
  end
end
