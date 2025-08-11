# frozen_string_literal: true

require 'mcp_client'

module Services
  # Service to connect to Home Assistant via MCP (Model Context Protocol)
  # Uses Server-Sent Events (SSE) for real-time communication
  class McpConnectorService
    include Singleton

    class McpError < StandardError; end
    class ConnectionError < McpError; end
    class ExecutionError < McpError; end

    attr_reader :client, :connected, :available_tools

    def initialize
      @connected = false
      @available_tools = []
      @client = nil
      @mutex = Mutex.new
    end

    # Connect to MCP server
    def connect!
      return true if connected?

      @mutex.synchronize do
        return true if @connected

        begin
          @client = create_client
          @client.connect if @client.respond_to?(:connect)

          # Fetch available tools and convert to hash format
          tools = @client.list_tools
          @available_tools = tools.map do |tool|
            {
              'name' => tool.name,
              'description' => tool.description,
              'inputSchema' => tool.schema || {}
            }
          end
          @connected = true

          Services::SimpleLogger.info('MCP connected successfully',
                                      tagged: %i[mcp connection],
                                      tool_count: @available_tools.size)
          true
        rescue StandardError => e
          @connected = false
          Services::SimpleLogger.error('MCP connection failed',
                                       tagged: %i[mcp connection error],
                                       error: e.message)
          raise ConnectionError, "Failed to connect to MCP: #{e.message}"
        end
      end
    end

    # Check if connected
    def connected?
      @connected
    end

    # List available MCP tools
    def list_tools
      connect! unless connected?
      @available_tools
    end

    # Find a specific tool by name
    def find_tool(name)
      connect! unless connected?
      @available_tools.find { |tool| tool['name'] == name.to_s }
    end

    # Execute an MCP tool
    def execute_tool(tool_name, parameters = {})
      connect! unless connected?

      Services::SimpleLogger.info('Executing MCP tool',
                                  tagged: %i[mcp tool_execution],
                                  tool: tool_name,
                                  params: parameters)

      begin
        result = @client.call_tool(tool_name.to_s, parameters)

        Services::SimpleLogger.info('MCP tool executed successfully',
                                    tagged: %i[mcp tool_execution],
                                    tool: tool_name)

        format_result(result)
      rescue StandardError => e
        Services::SimpleLogger.error('MCP tool execution failed',
                                     tagged: %i[mcp tool_execution error],
                                     tool: tool_name,
                                     error: e.message)
        raise ExecutionError, "Failed to execute MCP tool #{tool_name}: #{e.message}"
      end
    end

    # Execute multiple tools in batch
    def execute_tools(tool_calls)
      connect! unless connected?

      results = []
      tool_calls.each do |call|
        result = execute_tool(call[:name], call[:parameters] || {})
        results << { name: call[:name], result: result }
      end
      results
    end

    # Get tool schema/description
    def get_tool_schema(tool_name)
      tool = find_tool(tool_name)
      return nil unless tool

      {
        name: tool['name'],
        description: tool['description'],
        parameters: tool.dig('inputSchema', 'properties') || {},
        required: tool.dig('inputSchema', 'required') || []
      }
    end

    # Disconnect from MCP
    def disconnect!
      @mutex.synchronize do
        if @client.respond_to?(:cleanup)
          @client.cleanup
        end
        @connected = false
        @available_tools = []
        @client = nil
      end
    end

    # Reconnect to MCP
    def reconnect!
      disconnect!
      connect!
    end

    private

    def create_client
      # Get MCP configuration from GlitchCube config
      base_url = GlitchCube.config.mcp_url || "#{GlitchCube.config.home_assistant.url}/mcp_server/sse"
      token = GlitchCube.config.home_assistant.token

      # Create STDIO client configuration using mcp-proxy (like Claude does)
      config = MCPClient.stdio_config(
        command: 'uvx mcp-proxy',
        env: {
          'SSE_URL' => base_url,
          'API_ACCESS_TOKEN' => token
        }
      )

      # Create the client
      MCPClient.create_client(mcp_server_configs: [config])
    end

    def format_result(result)
      case result
      when Hash
        # Handle MCP response format
        if result['content']
          # Extract text from content array
          content = result['content'].find { |c| c['type'] == 'text' }
          if content && content['text']
            # Parse the JSON response from HA MCP
            begin
              parsed = JSON.parse(content['text'])
              return format_ha_response(parsed)
            rescue JSON::ParserError
              return content['text']
            end
          end
        end

        # Handle structured responses
        if result['success'] == false
          raise ExecutionError, result['error'] || 'Unknown error'
        end

        # Extract relevant data from response
        data = result['data'] || result['result'] || result

        # Format based on response type
        if result['response_type'] == 'action_done'
          format_action_response(data)
        elsif result['speech']
          format_speech_response(result['speech'])
        else
          data
        end
      when String
        result
      when NilClass
        { success: true, message: 'Command executed' }
      else
        result.to_s
      end
    end

    def format_ha_response(parsed)
      if parsed['success'] == false
        raise ExecutionError, parsed['error'] || 'Command failed'
      end

      # Return the parsed response for HA MCP format
      {
        success: parsed['success'] || true,
        message: parsed['result'] || parsed['message'] || 'Command executed',
        details: parsed['data']
      }
    end

    def format_action_response(data)
      success_count = data['success']&.size || 0
      failed_count = data['failed']&.size || 0

      message = []
      message << "✅ #{success_count} successful" if success_count.positive?
      message << "❌ #{failed_count} failed" if failed_count.positive?

      {
        success: failed_count.zero?,
        message: message.join(', '),
        details: data
      }
    end

    def format_speech_response(speech)
      {
        success: true,
        message: 'Speech command sent',
        speech: speech
      }
    end
  end
end
