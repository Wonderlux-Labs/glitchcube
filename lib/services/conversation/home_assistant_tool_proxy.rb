# frozen_string_literal: true

module Services
  module Conversation
    # Proxies tool execution through Home Assistant's conversation agent
    class HomeAssistantToolProxy
      def initialize(ha_client: Core::HomeAssistantClient.new, logger: Logging::SimpleLogger)
        @ha_client = ha_client
        @logger = logger
      end

      # Execute action array directly via Home Assistant Claude agent
      def execute_actions_as_request(actions, session_id, user_message = nil)
        start_time = Time.now
        @logger.info('🎯 Executing extracted actions via Home Assistant Claude agent',
                     tagged: %i[conversation actions hass_proxy],
                     session_id: session_id,
                     action_count: actions.count,
                     actions: actions,
                     user_message: user_message)

        # Format actions as natural language request for Claude
        formatted_request = format_actions_for_claude(actions, user_message)

        @logger.warn('📤 SENDING TO CLAUDE - FULL REQUEST',
                     tagged: %i[conversation actions hass_proxy debug],
                     session_id: session_id,
                     action_count: actions.count,
                     actions_being_sent: actions,
                     formatted_request_full: formatted_request)

        begin
          # Send to Home Assistant Claude conversation agent
          agent_id = 'conversation.claude_conversation'

          ha_response = @ha_client.process_voice_command(
            formatted_request,
            agent_id: agent_id,
            conversation_id: session_id,
            return_response: true
          )

          @logger.info('✅ Successfully received action execution response from HA Claude agent',
                       tagged: %i[conversation actions hass_proxy],
                       session_id: session_id)

          # Extract the response text from Claude
          response_text = extract_response_text(ha_response)

          @logger.warn('🤖 CLAUDE ACTION EXECUTION RESULTS',
                       tagged: %i[conversation actions claude results],
                       session_id: session_id,
                       actions_requested: actions,
                       claude_response: response_text)

          duration_ms = ((Time.now - start_time) * 1000).round
          @logger.info("🏁 Finished action execution via Claude in #{duration_ms}ms",
                       tagged: %i[conversation actions hass_proxy complete],
                       session_id: session_id,
                       duration_ms: duration_ms)

          {
            success: true,
            message: response_text.strip,
            executed_actions: actions,
            executed_via: 'home_assistant_claude_conversation_agent',
            execution_summary: "Claude executed #{actions.count} actions: #{actions.join(', ')}"
          }
        rescue StandardError => e
          @logger.log_error(error: e,
                            message: '❌ Error executing actions via Claude',
                            session_id: session_id,
                            actions: actions)

          {
            success: false,
            message: "Failed to execute actions: #{e.message}",
            executed_actions: [],
            error: e.message
          }
        end
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

          @logger.debug('🔥 ABOUT TO CALL process_voice_command',
                        tagged: %i[conversation tools hass_proxy debug],
                        session_id: session_id,
                        agent_id: agent_id,
                        formatted_request_preview: formatted_request[0..200])

          ha_response = @ha_client.process_voice_command(
            formatted_request,
            agent_id: agent_id,
            conversation_id: session_id,
            return_response: true
          )

          @logger.debug('🔥 RETURNED FROM process_voice_command',
                        tagged: %i[conversation tools hass_proxy debug],
                        session_id: session_id,
                        response_class: ha_response.class.name)

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

      def format_actions_for_claude(actions, user_message = nil)
        action_descriptions = actions.map.with_index { |action, i| "#{i + 1}. #{action}" }

        user_context = user_message ? "Original user request: \"#{user_message}\"\n\n" : ''

        <<~REQUEST
          BACKGROUND AGENT REQUEST - DO NOT SPEAK OUT LOUD OR USE TTS:

          #{user_context}We have a request from a user to:
          #{action_descriptions.join("\n")}

          IMPORTANT: You are a background agent. Do your best to make it happen and return to us in TEXT ONLY.
          DO NOT speak out loud, DO NOT use text-to-speech, DO NOT broadcast messages.
          Only perform the requested actions silently and report back your results of successes and failures in text format.
        REQUEST
      end

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
          "BACKGROUND AGENT REQUEST - DO NOT SPEAK OUT LOUD OR USE TTS:\n\n" \
          "We have a request from a user to:\n" +
            tool_descriptions.map.with_index { |desc, i| "#{i + 1}. #{desc}" }.join("\n") +
            "\n\nIMPORTANT: You are a background agent. Do your best to make it happen and return to us in TEXT ONLY. " \
            'DO NOT speak out loud, DO NOT use text-to-speech, DO NOT broadcast messages. ' \
            'Only perform the requested actions silently and report back your results of successes and failures in text format.'
        else
          'BACKGROUND AGENT REQUEST - DO NOT SPEAK OUT LOUD OR USE TTS:\n\n' \
            'We have a request from a user to execute some tools. You are a background agent. ' \
            'Do your best to make it happen and return to us in TEXT ONLY. ' \
            'DO NOT speak out loud, DO NOT use text-to-speech, DO NOT broadcast messages. ' \
            'Only perform the requested actions silently and report back your results in text format.'
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

      # Enhanced extraction with comprehensive autohealing
      def extract_response_text(ha_response)
        @logger.debug('Starting enhanced response extraction with autohealing',
                      tagged: %i[conversation tools hass_proxy parsing enhanced],
                      ha_response_structure: ha_response.class,
                      ha_response_keys: ha_response.is_a?(Hash) ? ha_response.keys : 'N/A')

        # First, get the raw text through standard extraction
        raw_text = extract_raw_text(ha_response)

        # TEMPORARILY DISABLE AUTOHEALING - IT'S BEING TOO AGGRESSIVE
        @logger.warn('⚠️ AUTOHEALING DISABLED - USING RAW CLAUDE RESPONSE',
                     tagged: %i[conversation tools hass_proxy parsing debug],
                     raw_text_length: raw_text.length,
                     raw_text_full: raw_text)

        raw_text
      end

      private

      def extract_raw_text(ha_response)
        case ha_response
        when Hash
          # Try multiple extraction paths for HA conversation responses
          text = ha_response.dig('service_response', 'response', 'speech', 'plain', 'speech') ||
                 ha_response.dig('response', 'speech', 'plain', 'speech') ||
                 ha_response.dig('response', 'text') ||
                 ha_response.dig('response', 'speech') ||
                 ha_response['text'] ||
                 ha_response['response'] ||
                 ha_response['message'] ||
                 ha_response['content'] ||
                 ha_response.to_s
        when String
          ha_response
        else
          ha_response.to_s
        end
      end

      def autoheal_response_text(text)
        return '' if text.nil? || text.strip.empty?

        original_text = text.dup
        current_text = text.dup
        confidence_score = 0.0
        strategy_used = 'none'

        @logger.debug('🔧 Starting autohealing pipeline',
                      tagged: %i[conversation tools hass_proxy autohealing],
                      input_length: text.length,
                      has_json_markers: text.include?('```'),
                      has_json_braces: text.include?('{'))

        # Strategy 1: Extract from JSON code blocks (markdown style)
        if (extracted = extract_from_json_blocks(current_text))
          current_text = extracted
          confidence_score = 0.9
          strategy_used = 'json_block'
        elsif (extracted = extract_from_pure_json(current_text))
          # Strategy 2: Parse as pure JSON if it looks like JSON
          current_text = extracted
          confidence_score = 0.8
          strategy_used = 'pure_json'
        elsif (extracted = extract_meaningful_content(current_text))
          # Strategy 3: Extract from mixed content (status + actual response)
          current_text = extracted
          confidence_score = 0.6
          strategy_used = 'meaningful_extraction'
        else
          # Strategy 4: Just clean up artifacts
          current_text = clean_response_artifacts(current_text)
          confidence_score = 0.3
          strategy_used = 'artifact_cleanup'
        end

        # Strategy 5: Final validation and fallback
        current_text = validate_and_fallback(current_text, original_text)

        log_autohealing_result(original_text, current_text, confidence_score, strategy_used)

        current_text
      end

      def extract_from_json_blocks(text)
        # Handle multiple JSON block formats
        json_patterns = [
          /```json\s*\n(.*?)\n```/m,           # Standard markdown JSON
          /```\s*\n(.*?)\n```/m,               # Generic code block
          /~~~json\s*\n(.*?)\n~~~/m,           # Alternative markdown
          %r{<json>(.*?)</json>}m               # XML-style JSON tags
        ]

        json_patterns.each do |pattern|
          match = text.match(pattern)
          next unless match

          json_string = match[1].strip
          extracted = try_parse_json_response(json_string)

          next unless extracted

          @logger.info('🔧 Autohealing: Extracted from JSON block',
                       tagged: %i[conversation tools hass_proxy autohealing success],
                       strategy: 'json_block',
                       pattern: pattern.inspect)
          return extracted
        end

        nil
      end

      def extract_from_pure_json(text)
        # Try to parse the entire text as JSON
        return nil unless text.strip.match?(/^\s*[{\[]/)

        # Clean up common JSON formatting issues
        cleaned = text.strip
                      .gsub(/^[^{\[]*([{\[].*[}\]])[^}\]]*$/m, '\1')  # Extract JSON from surrounding text
                      .gsub(/\n\s*/, ' ')                            # Collapse whitespace
                      .gsub(/,\s*[}\]]/, '}')                        # Fix trailing commas

        extracted = try_parse_json_response(cleaned)

        if extracted
          @logger.info('🔧 Autohealing: Extracted from pure JSON',
                       tagged: %i[conversation tools hass_proxy autohealing success],
                       strategy: 'pure_json')
          return extracted
        end

        nil
      end

      def try_parse_json_response(json_string)
        return nil if json_string.nil? || json_string.strip.empty?

        begin
          parsed = JSON.parse(json_string)

          # Try multiple field names that might contain the actual response
          response_fields = %w[
            response text message content speech answer result output
            reply data body value description summary
          ]

          # Look for the most meaningful response field
          response_fields.each do |field|
            if parsed[field] && !parsed[field].to_s.strip.empty?
              return parsed[field].to_s.strip
            end
          end

          # If no standard field found, try to extract from nested structures
          if parsed.is_a?(Hash)
            # Look for nested response objects
            parsed.each_value do |value|
              next unless value.is_a?(Hash)

              response_fields.each do |field|
                if value[field] && !value[field].to_s.strip.empty?
                  return value[field].to_s.strip
                end
              end
            end

            # If still nothing, return the longest string value
            string_values = parsed.values.select { |v| v.is_a?(String) && v.length > 10 }
            return string_values.max_by(&:length) if string_values.any?
          end
        rescue JSON::ParserError => e
          @logger.debug('🔧 JSON parsing failed during autohealing',
                        tagged: %i[conversation tools hass_proxy autohealing json_error],
                        error: e.message,
                        json_preview: json_string[0..100])
        end

        nil
      end

      def extract_meaningful_content(text)
        lines = text.split(/\r?\n/).map(&:strip).reject(&:empty?)
        return nil if lines.length <= 1

        # Filter out status/system lines
        noise_patterns = [
          /^(Tool|Action|Command|Successfully|Executed|Completed|Error|Debug|Info)/i,
          /^[A-Z_]+:/,                          # Log prefixes like "INFO:"
          /^\[.*\].*:/,                         # Timestamp/level prefixes
          /^[🎯🔧📝✅❌🏠📤]/,                    # Emoji prefixes (common in logs)
          /```/,                                # Markdown artifacts
          /^\s*[{}"']\s*$/,                     # Lone JSON artifacts
          /^(null|undefined|true|false)$/i,     # JSON literals
          /^\d{4}-\d{2}-\d{2}/,                 # Timestamps
          /executing|processing|starting|finished/i
        ]

        meaningful_lines = lines.reject do |line|
          line.length < 5 ||
            noise_patterns.any? { |pattern| line.match?(pattern) }
        end

        if meaningful_lines.any?
          # Prefer longer, more substantive lines
          best_line = meaningful_lines.max_by do |line|
            # Score based on length and content quality
            length_score = line.length
            quality_score = line.count('a-zA-Z') # Favor actual words over symbols
            punctuation_bonus = line.match?(/[.!?]$/) ? 10 : 0

            length_score + quality_score + punctuation_bonus
          end

          if best_line && best_line.length >= 10
            @logger.info('🔧 Autohealing: Extracted meaningful content',
                         tagged: %i[conversation tools hass_proxy autohealing success],
                         strategy: 'meaningful_extraction',
                         total_lines: lines.length,
                         meaningful_lines: meaningful_lines.length,
                         selected_line_preview: best_line[0..50])
            return best_line
          end
        end

        nil
      end

      def clean_response_artifacts(text)
        return text unless text.is_a?(String)

        cleaned = text.dup

        # Remove markdown artifacts
        cleaned = cleaned.gsub(/```\w*/, '')
                         .gsub(/~~~\w*/, '')
                         .gsub(/^\s*[|>]\s*/, '')     # Quote markers

        # Remove JSON artifacts
        cleaned = cleaned.gsub(/^\s*[{}"']\s*$/, '')
                         .gsub(/^\s*null\s*$/i, '')
                         .gsub(/^\s*(true|false)\s*$/i, '')

        # Remove common status prefixes
        cleaned = cleaned.gsub(/^(OK|SUCCESS|DONE|COMPLETE)[:\s-]*/i, '')
                         .gsub(/^(ERROR|FAILED|INVALID)[:\s-]*/i, '')

        # Clean up whitespace
        cleaned = cleaned.strip
                         .gsub(/\s+/, ' ')            # Collapse multiple spaces
                         .gsub(/\n\s*\n/, "\n")       # Remove empty lines

        # Remove surrounding quotes if they wrap the entire content
        if cleaned.match?(/^".*"$/) || cleaned.match?(/^'.*'$/)
          cleaned = cleaned[1..-2]
        end

        cleaned.strip
      end

      def validate_and_fallback(current_text, original_text)
        # Ensure we have something meaningful
        if current_text.nil? || current_text.strip.empty? || current_text.length < 3
          @logger.warn('🔧 Autohealing: Processed text too short, using original',
                       tagged: %i[conversation tools hass_proxy autohealing fallback],
                       processed_length: current_text&.length || 0,
                       original_length: original_text.length)
          return original_text.strip
        end

        # If we ended up with just punctuation or symbols, fall back
        if current_text.match?(/^[^a-zA-Z0-9]*$/)
          @logger.warn('🔧 Autohealing: Processed text contains no alphanumeric, using original',
                       tagged: %i[conversation tools hass_proxy autohealing fallback],
                       processed_text: current_text)
          return original_text.strip
        end

        # Looks good!
        current_text
      end

      def log_autohealing_result(original_text, final_text, confidence_score, strategy_used)
        if final_text == original_text
          @logger.debug('🔧 Autohealing: No transformation needed',
                        tagged: %i[conversation tools hass_proxy autohealing complete unchanged])
        else
          @logger.info('🔧 Autohealing: Successfully transformed response',
                       tagged: %i[conversation tools hass_proxy autohealing complete success],
                       original_preview: original_text[0..100],
                       final_preview: final_text[0..100],
                       size_change: "#{original_text.length} → #{final_text.length}",
                       transformation_ratio: (final_text.length.to_f / [original_text.length, 1].max).round(2),
                       confidence_score: confidence_score,
                       strategy_used: strategy_used)
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
