#  frozen_string_literal: true

module Tools
  # Tool for executing Home Assistant commands via MCP (Model Context Protocol)
  # Provides flexible access to all MCP-exposed HA functions
  class HassMcpTool < BaseTool
    class << self
      def name
        'hass_mcp'
      end

      def description
        'Execute Home Assistant commands through MCP protocol - supports lights, switches, scenes, media players, and more'
      end

      def parameters
        {
          mcp_function: {
            type: 'string',
            description: 'The MCP function to call (e.g., HassTurnOn, HassTurnOff, HassLightSet, GetLiveContext)',
            required: true
          },
          mcp_params: {
            type: 'object',
            description: 'Parameters for the MCP function (varies by function)',
            required: false
          }
        }
      end

      def required_parameters
        [:mcp_function]
      end

      def examples
        [
          {
            description: 'Turn on a light',
            params: {
              mcp_function: 'HassTurnOn',
              mcp_params: { name: 'Cube Light' }
            }
          },
          {
            description: 'Set light brightness and color',
            params: {
              mcp_function: 'HassLightSet',
              mcp_params: {
                name: 'Cube Light',
                brightness: 80,
                color: 'blue'
              }
            }
          },
          {
            description: 'Get current state of all devices',
            params: {
              mcp_function: 'GetLiveContext',
              mcp_params: {}
            }
          },
          {
            description: 'Play media',
            params: {
              mcp_function: 'HassMediaSearchAndPlay',
              mcp_params: {
                search_query: 'relaxing music',
                name: 'Square Voice Media Player'
              }
            }
          }
        ]
      end

      def category
        'home_automation'
      end

      def tool_prompt
        <<~PROMPT
        Use the hass_mcp tool to control Home Assistant devices through MCP (Model Context Protocol).

        DISCOVERING AVAILABLE FUNCTIONS:
        The MCP server exposes all available functions dynamically. To discover them:
        - Call with mcp_function: "list_available_functions" to see all available MCP functions
        - This uses the standard MCP list_tools() method to get the current capabilities

        Common Home Assistant MCP functions:
        - HassTurnOn/HassTurnOff: Control lights, switches, and other devices
        - HassLightSet: Adjust brightness, color, and temperature
        - GetLiveContext: Get current state of all devices
        - HassMediaPause/HassMediaUnpause: Control media playback
        - HassSetVolume: Adjust volume levels
        - HassBroadcast: Send messages through the home
        - HassMediaSearchAndPlay: Play specific media
        - HassCancelAllTimers: Cancel all active timers

        Always check GetLiveContext first to see available devices.
        The MCP server may expose additional functions - use list_available_functions to discover them all.
        PROMPT
      end

      def call(mcp_function:, mcp_params: {})
        # Special case: list available functions
        if mcp_function == 'list_available_functions'
          functions = list_available_functions
          return format_response(true, 'Available MCP functions:', functions)
        end

        # Validate required parameters
        validate_required_params({ mcp_function: mcp_function }, required_parameters)

        # Parse params if they're a string
        params = parse_json_params(mcp_params)

        # Get MCP connector instance
        connector = Services::McpConnectorService.instance

        # Execute the MCP function
        begin
          result = connector.execute_tool(mcp_function, params)

          # Format the response
          format_mcp_response(mcp_function, result)
        rescue Services::McpConnectorService::McpError => e
          format_response(false, "MCP Error: #{e.message}")
        rescue StandardError => e
          Services::Logging::SimpleLogger.error('MCP tool execution failed',
                                                tagged: %i[tool mcp error],
                                                function: mcp_function,
                                                error: e.message)
          format_response(false, "Error executing MCP function: #{e.message}")
        end
      end

      # Helper to list available MCP functions
      def list_available_functions
        connector = Services::McpConnectorService.instance
        tools = connector.list_tools

        tools.map do |tool|
          {
            name: tool['name'],
            description: tool['description']
          }
        end
      rescue StandardError => e
        Services::Logging::SimpleLogger.error('Failed to list MCP functions',
                                              tagged: %i[tool mcp error],
                                              error: e.message)
        []
      end

      # Helper to get function schema
      def get_function_schema(function_name)
        connector = Services::McpConnectorService.instance
        connector.get_tool_schema(function_name)
      rescue StandardError => e
        Services::Logging::SimpleLogger.error('Failed to get MCP function schema',
                                              tagged: %i[tool mcp error],
                                              function: function_name,
                                              error: e.message)
        nil
      end

      private

      def format_mcp_response(function_name, result)
        case result
        when Hash
          if result[:success] == false
            format_response(false, result[:message] || "#{function_name} failed", result[:details])
          else
            message = result[:message] || "#{function_name} executed successfully"
            format_response(true, message, result[:details])
          end
        when String
          # Simple string response
          format_response(true, result)
        else
          # Unknown response format
          format_response(true, "#{function_name} executed", result)
        end
      end
    end
  end
end
