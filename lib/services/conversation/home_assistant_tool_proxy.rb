# frozen_string_literal: true

module Services
  module Conversation
    # Proxies tool execution through Home Assistant's conversation agent
    class HomeAssistantToolProxy
      def initialize(ha_client: Core::HomeAssistantClient.new, logger: Logging::SimpleLogger)
        @ha_client = ha_client
        @logger = logger
      end

      def execute_via_hass(llm_response, session_id)
        start_time = Time.now
        @logger.info('🏠 Starting UNIFIED tool execution via Home Assistant Claude agent',
                     tagged: %i[conversation tools hass_proxy unified],
                     session_id: session_id,
                     tool_count: llm_response.tool_calls.count,
                     architecture: 'back_to_hass')

        # Format ALL tool calls as single natural language request
        formatted_request = format_tool_calls_as_text(llm_response)

        @logger.info('📤 Sending unified tool request to HA Claude agent',
                     tagged: %i[conversation tools hass_proxy unified],
                     session_id: session_id,
                     formatted_request: formatted_request,
                     requested_tools: llm_response.tool_calls.map { |tc| tc[:function][:name] })

        begin
          # Send to Home Assistant Claude conversation agent
          agent_id = 'conversation.claude_conversation'

          @logger.info("🤖 Using HA Claude agent: #{agent_id}",
                       tagged: %i[conversation tools hass_proxy unified],
                       session_id: session_id)

          ha_response = @ha_client.process_voice_command(
            formatted_request,
            agent_id: agent_id,
            conversation_id: session_id,
            return_response: true
          )

          @logger.info('✅ Successfully received response from HA Claude agent',
                       tagged: %i[conversation tools hass_proxy unified],
                       session_id: session_id)

          # 🚨 COMPREHENSIVE LOGGING OF ENTIRE HA RESPONSE STRUCTURE
          @logger.info('📊 COMPLETE HA RESPONSE ANALYSIS',
                       tagged: %i[conversation tools hass_proxy response_analysis],
                       session_id: session_id,
                       response_class: ha_response.class.name,
                       response_full_inspect: ha_response.inspect,
                       response_size_bytes: ha_response.to_s.bytesize)

          if ha_response.is_a?(Hash)
            @logger.info('📋 HA RESPONSE HASH STRUCTURE',
                         tagged: %i[conversation tools hass_proxy response_analysis],
                         session_id: session_id,
                         top_level_keys: ha_response.keys,
                         response_key_exists: ha_response.key?('response'),
                         response_content: ha_response['response']&.inspect)

            if ha_response['response'].is_a?(Hash)
              @logger.info('🎯 HA RESPONSE NESTED STRUCTURE',
                           tagged: %i[conversation tools hass_proxy response_analysis],
                           session_id: session_id,
                           response_keys: ha_response['response'].keys,
                           speech_exists: ha_response.dig('response', 'speech')&.inspect,
                           text_exists: ha_response.dig('response', 'text')&.inspect)
            end
          end

          # Extract the complete response text from HA Claude agent
          response_text = extract_response_text(ha_response)

          @logger.info('📝 EXTRACTED RESPONSE TEXT FROM HA CLAUDE AGENT',
                       tagged: %i[conversation tools hass_proxy unified extracted],
                       session_id: session_id,
                       response_text_length: response_text.length,
                       response_text_preview: response_text[0..200],
                       response_text_full: response_text)

          # Create SINGLE unified tool result containing HA Claude agent's complete response
          unified_result = create_unified_tool_result(response_text, llm_response, session_id)

          duration_ms = ((Time.now - start_time) * 1000).round
          @logger.info("🏁 Finished UNIFIED HA tool execution in #{duration_ms}ms",
                       tagged: %i[conversation tools hass_proxy unified complete],
                       session_id: session_id,
                       duration_ms: duration_ms,
                       unified_response_created: true)

          unified_result
        rescue StandardError => e
          puts '🚨 ACTUAL ERROR IN HOME ASSISTANT TOOL PROXY:'
          puts "  Error class: #{e.class}"
          puts "  Error message: #{e.message}"
          puts '  Backtrace:'
          puts e.backtrace.first(10).map { |line| "    #{line}" }.join("\n")

          @logger.log_error(error: e,
                            message: '❌ Error in Home Assistant tool proxy',
                            session_id: session_id,
                            architecture: 'back_to_hass')

          # Fallback to error results
          create_error_results(llm_response, e.message)
        end
      end

      private

      def format_tool_calls_as_text(llm_response)
        tool_descriptions = []

        llm_response.tool_calls.each_with_index do |_tool_call, index|
          function_call = llm_response.function_calls[index]
          function_name = function_call[:name]

          begin
            arguments = llm_response.function_arguments_for(function_name)
            description = format_tool_description(function_name, arguments)
            tool_descriptions << description
          rescue StandardError => e
            @logger.warn("Could not format tool call #{function_name}: #{e.message}",
                         tagged: %i[conversation tools hass_proxy formatting])
            tool_descriptions << "Execute #{function_name} (with unparseable arguments)"
          end
        end

        if tool_descriptions.any?
          "We have a request from a user to:\n" +
            tool_descriptions.map.with_index { |desc, i| "#{i + 1}. #{desc}" }.join("\n") +
            "\n\nDo your best to make it happen and return to us in TEXT ONLY (you are a background agent) your results of successes and failures."
        else
          'We have a request from a user to execute some tools. Do your best to make it happen and return to us in TEXT ONLY (you are a background agent) your results of successes and failures.'
        end
      end

      def format_tool_description(function_name, arguments)
        case function_name
        when 'turn_on_light', 'turn_off_light', 'set_light_brightness', 'set_light_color'
          format_light_tool(function_name, arguments)
        when 'speak', 'tts'
          format_speech_tool(function_name, arguments)
        when 'display_text', 'display_notification'
          format_display_tool(function_name, arguments)
        when 'play_music', 'pause_music', 'set_volume'
          format_media_tool(function_name, arguments)
        else
          # Generic formatting
          args_str = arguments&.map { |k, v| "#{k}: #{v}" }&.join(', ') || ''
          "#{function_name.humanize}#{" (#{args_str})" unless args_str.empty?}"
        end
      end

      def format_light_tool(function_name, arguments)
        case function_name
        when 'turn_on_light'
          "Turn on #{arguments['entity_id'] || 'the lights'}"
        when 'turn_off_light'
          "Turn off #{arguments['entity_id'] || 'the lights'}"
        when 'set_light_brightness'
          "Set #{arguments['entity_id'] || 'the lights'} brightness to #{arguments['brightness']}"
        when 'set_light_color'
          "Set #{arguments['entity_id'] || 'the lights'} color to #{arguments['color'] || arguments['rgb_color']}"
        end
      end

      def format_speech_tool(_function_name, arguments)
        message = arguments['message'] || arguments['text']
        voice = arguments['voice']
        voice_info = voice ? " in #{voice} voice" : ''
        "Say \"#{message}\"#{voice_info}"
      end

      def format_display_tool(_function_name, arguments)
        text = arguments['text'] || arguments['message']
        "Display \"#{text}\" on the cube"
      end

      def format_media_tool(function_name, arguments)
        case function_name
        when 'play_music'
          "Play #{arguments['query'] || arguments['song'] || 'music'}"
        when 'pause_music'
          'Pause music'
        when 'set_volume'
          "Set volume to #{arguments['volume'] || arguments['level']}"
        end
      end

      def create_unified_tool_result(response_text, original_llm_response, session_id)
        @logger.info('🔨 Creating UNIFIED tool result from HA Claude agent response',
                     tagged: %i[conversation tools hass_proxy unified creation],
                     session_id: session_id,
                     original_tool_count: original_llm_response.tool_calls.count)

        # Extract all the tool names that were requested
        requested_tools = original_llm_response.tool_calls.map { |tc| tc[:function][:name] }

        # Create comprehensive tool result that represents ALL tool execution
        unified_tool_result = {
          success: true,
          message: response_text.strip,
          executed_via: 'home_assistant_claude_conversation_agent',
          executed_tools: requested_tools,
          execution_summary: "Home Assistant Claude agent executed #{requested_tools.count} tools: #{requested_tools.join(', ')}"
        }

        @logger.info('📦 UNIFIED TOOL RESULT CREATED',
                     tagged: %i[conversation tools hass_proxy unified result],
                     session_id: session_id,
                     unified_result_size: unified_tool_result.to_json.bytesize,
                     executed_tools: requested_tools,
                     result_preview: unified_tool_result.to_json[0..200])

        # Return in expected format with SINGLE comprehensive result
        {
          tool_results: [{
            tool_call_id: 'hass_unified_execution',
            role: 'tool',
            name: 'home_assistant_tool_execution',
            content: unified_tool_result.to_json
          }],
          last_tool_calls: [{
            tool_name: 'home_assistant_tool_execution',
            arguments: {
              formatted_request: format_tool_calls_as_text(original_llm_response),
              requested_tools: requested_tools
            },
            result: unified_tool_result
          }],
          failed_tool_calls: [] # HA Claude agent handles retries internally
        }
      end

      def extract_response_text(ha_response)
        @logger.debug('Extracting response text from HA response',
                      tagged: %i[conversation tools hass_proxy parsing],
                      ha_response_structure: ha_response.class,
                      ha_response_keys: ha_response.is_a?(Hash) ? ha_response.keys : 'N/A',
                      ha_response_full: ha_response.inspect)

        case ha_response
        when Hash
          # Home Assistant conversation responses have a nested structure
          # For Claude conversation agent, the speech is in service_response
          text = ha_response.dig('service_response', 'response', 'speech', 'plain', 'speech') ||
                 ha_response.dig('response', 'speech', 'plain', 'speech') ||
                 ha_response.dig('response', 'text') ||
                 ha_response['text'] ||
                 ha_response['response'] ||
                 ha_response.to_s

          @logger.debug('Extracted text from HA response',
                        tagged: %i[conversation tools hass_proxy parsing],
                        extracted_text: text)
          text
        when String
          ha_response
        else
          ha_response.to_s
        end
      end

      def extract_tool_result_from_response(response_text, _function_name, _index)
        # The Claude conversation agent has already executed tools and returned a natural language response
        # We just need to return this response as the "result" of our tool execution
        # This is much simpler than trying to parse individual tool results

        {
          success: true,
          message: response_text.strip,
          note: 'Executed via Home Assistant Claude conversation agent'
        }
      end

      def create_error_results(llm_response, error_message)
        tool_results = []
        last_tool_calls = []

        llm_response.tool_calls.each_with_index do |tool_call, index|
          function_call = llm_response.function_calls[index]
          function_name = function_call[:name]

          error_result = { success: false, error: error_message }

          tool_results << {
            tool_call_id: tool_call[:id],
            role: 'tool',
            name: function_name,
            content: error_result.to_json
          }

          # Extract arguments safely
          begin
            arguments = llm_response.function_arguments_for(function_name)
          rescue StandardError
            arguments = {}
          end

          last_tool_calls << {
            tool_name: function_name,
            arguments: arguments,
            result: error_result
          }
        end

        {
          tool_results: tool_results,
          last_tool_calls: last_tool_calls,
          failed_tool_calls: last_tool_calls.map do |tc|
            {
              tool_call: { id: SecureRandom.uuid },
              function_name: tc[:tool_name],
              arguments: tc[:arguments],
              error: error_message
            }
          end
        }
      end
    end
  end
end
