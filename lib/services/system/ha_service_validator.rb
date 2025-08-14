# frozen_string_literal: true

module Services::System
  # Validates Home Assistant service calls against actual service schemas
  # Provides real-time validation and schema comparison for tools
  class HAServiceValidator
    class << self
      # Cache for HA service schemas to avoid repeated API calls
      @schema_cache = {}
      @cache_expiry = {}

      # Cache duration in seconds (5 minutes)
      CACHE_DURATION = 300

      def validate_service_call(domain, service, data, ha_client: nil)
        ha_client ||= HomeAssistantClient.new

        begin
          validation_result = ha_client.validate_service_call(domain, service, data)

          # Log validation results
          if validation_result[:valid]
            SimpleLogger.debug('HA service validation passed',
                               tagged: %i[ha_validator validation],
                               service: "#{domain}.#{service}",
                               data: data)
          else
            SimpleLogger.warn('HA service validation failed',
                              tagged: %i[ha_validator validation],
                              service: "#{domain}.#{service}",
                              errors: validation_result[:errors],
                              data: data)
          end

          validation_result
        rescue StandardError => e
          SimpleLogger.error('HA service validation error',
                             tagged: %i[ha_validator error],
                             service: "#{domain}.#{service}",
                             error: e.message)

          # Return permissive result on validation failure
          { valid: true, errors: [], validation_failed: true, error: e.message }
        end
      end

      def get_cached_schema(domain, service, ha_client: nil)
        cache_key = "#{domain}.#{service}"

        # Check if cached schema is still valid
        if @schema_cache[cache_key] &&
           @cache_expiry[cache_key] &&
           Time.now < @cache_expiry[cache_key]
          return @schema_cache[cache_key]
        end

        # Fetch fresh schema
        ha_client ||= HomeAssistantClient.new
        schema = ha_client.get_service_schema(domain, service)

        if schema
          @schema_cache[cache_key] = schema
          @cache_expiry[cache_key] = Time.now + CACHE_DURATION
        end

        schema
      rescue StandardError => e
        SimpleLogger.warn('Failed to fetch HA service schema',
                          tagged: %i[ha_validator schema_fetch],
                          service: "#{domain}.#{service}",
                          error: e.message)
        nil
      end

      def compare_tool_schema_to_ha(tool_class, tool_method)
        return { status: :no_tool_schema } unless tool_class.respond_to?(:tool_schemas)

        tool_schema = tool_class.tool_schemas[tool_method]
        return { status: :no_tool_schema } unless tool_schema

        # Try to infer HA service from tool method name and class
        ha_services = infer_ha_services(tool_class, tool_method)

        comparisons = ha_services.map do |domain, service|
          ha_schema = get_cached_schema(domain, service)
          next { domain: domain, service: service, status: :ha_schema_unavailable } unless ha_schema

          compare_schemas(tool_schema, ha_schema, domain, service)
        end.compact

        {
          status: :compared,
          tool_schema: tool_schema,
          comparisons: comparisons
        }
      end

      def clear_schema_cache!
        @schema_cache.clear
        @cache_expiry.clear
        SimpleLogger.info('Cleared HA service schema cache',
                          tagged: %i[ha_validator cache])
      end

      private

      def infer_ha_services(tool_class, _tool_method)
        # Map tool classes to their primary HA services
        service_mappings = {
          'LightingTool' => [%w[light turn_on], %w[light turn_off]],
          'SpeechTool' => [%w[tts cloud_say], %w[tts speak]],
          'DisplayTool' => [%w[awtrix push_app_data], %w[notify awtrix_bedroom]],
          'MusicTool' => [%w[music_assistant play], %w[music_assistant search]],
          'CameraTool' => [%w[camera snapshot]]
        }

        class_name = tool_class.name.split('::').last
        service_mappings[class_name] || []
      end

      def compare_schemas(tool_schema, ha_schema, domain, service)
        mismatches = []
        suggestions = []

        tool_properties = tool_schema['properties'] || {}
        ha_fields = ha_schema[:fields] || {}

        # Check for missing parameters in tool schema
        ha_fields.each do |ha_field, ha_config|
          next if tool_properties.key?(ha_field)

          if ha_config['required']
            mismatches << "Missing required HA field: #{ha_field}"
          else
            suggestions << "Consider adding optional HA field: #{ha_field}"
          end
        end

        # Check for extra parameters in tool schema
        tool_properties.each_key do |tool_field|
          next if ha_fields.key?(tool_field.to_s)

          suggestions << "Tool field #{tool_field} not found in HA schema - may need custom handling"
        end

        # Check type compatibility for matching fields
        tool_properties.each do |tool_field, tool_config|
          ha_config = ha_fields[tool_field.to_s]
          next unless ha_config

          type_match = compare_field_types(tool_config, ha_config)
          mismatches << "Type mismatch for #{tool_field}: #{type_match}" if type_match
        end

        {
          domain: domain,
          service: service,
          status: mismatches.empty? ? :compatible : :mismatched,
          mismatches: mismatches,
          suggestions: suggestions,
          ha_schema: ha_schema
        }
      end

      def compare_field_types(tool_config, ha_config)
        tool_type = tool_config['type']

        # HA uses selectors instead of direct types
        selector = ha_config['selector']
        return nil unless selector

        selector_type = selector.keys.first

        # Basic type compatibility checks
        case tool_type
        when 'string'
          return "Expected string but HA uses #{selector_type}" unless %w[text select color].include?(selector_type)
        when 'integer', 'number'
          return "Expected number but HA uses #{selector_type}" unless selector_type == 'number'
        when 'boolean'
          return "Expected boolean but HA uses #{selector_type}" unless selector_type == 'boolean'
        when 'array'
          # Arrays are usually handled as special selectors in HA
          return "Array type may need special handling with HA selector #{selector_type}"
        end

        nil
      end
    end
  end
end
