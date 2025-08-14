# frozen_string_literal: true

require 'json'

module Tools
  # Base class for all Glitch Cube tools
  # Provides standardized interface and common functionality
  class BaseTool
    class ToolError < StandardError; end
    class ValidationError < ToolError; end
    class ExecutionError < ToolError; end

    class << self
      # Tool identification
      def name
        # Default implementation: derive from class name
        # e.g., Tools::LightingTool -> lighting_tool, Tools::BaseTool -> base_tool
        class_name = to_s

        # Remove module namespace prefix (e.g., Tools::BaseTool -> BaseTool)
        class_name = class_name.split('::').last

        # Convert CamelCase to snake_case
        class_name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                  .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                  .downcase

        # Don't remove 'tool' suffix for base classes
      end

      def description
        raise NotImplementedError, 'Tool must implement .description method'
      end

      # Tool execution - must be implemented by each tool
      def call(**args)
        raise NotImplementedError, 'Tool must implement .call method'
      end

      # Optional: Define parameter schema for validation
      def parameters
        {}
      end

      # Optional: Define required parameters
      def required_parameters
        []
      end

      # Optional: Define usage examples
      def examples
        []
      end

      # Optional: Define tool category
      def category
        'general'
      end

      # Optional: Define tool prompt for LLM context
      def tool_prompt
        description
      end
    end

    protected

    # Helper: Get Home Assistant client with error handling
    def self.ha_client
      @ha_client ||= begin
        return mock_ha_client if use_mock_ha?

        raise ToolError, 'Home Assistant not configured. Set HOME_ASSISTANT_URL in .env' unless GlitchCube.config.home_assistant.url

        HomeAssistantClient.new
      end
    rescue StandardError => e
      raise ToolError, "Failed to connect to Home Assistant: #{e.message}"
    end

    # Helper: Call HA service with consistent error handling
    def self.call_ha_service(domain, service, data = {}, return_response: false, validate: false)
      # Optional validation (non-blocking) - mainly for development/debugging
      validate_ha_service_call(domain, service, data) if validate

      result = ha_client.call_service(domain, service, data, return_response: return_response)

      # If return_response is true, return the actual result
      return result if return_response && result

      # Otherwise return status message
      if result
        "✅ Service #{domain}.#{service} executed successfully"
      else
        "❌ Service #{domain}.#{service} failed"
      end
    rescue HomeAssistantClient::Error => e
      # Enhanced HA error reporting with specific error details
      error_context = {
        domain: domain,
        service: service,
        data: data,
        error_class: e.class.name,
        error_message: e.message
      }

      Services::Logging::SimpleLogger.error('Home Assistant service call failed',
                                            tagged: %i[tool home_assistant error],
                                            **error_context)

      "❌ HA Service Error (#{domain}.#{service}): #{e.message}"
    rescue StandardError => e
      # Generic error handling
      Services::Logging::SimpleLogger.error('Tool service call failed',
                                            tagged: %i[tool error],
                                            domain: domain,
                                            service: service,
                                            error_class: e.class.name,
                                            error_message: e.message)

      "❌ HA Service Error: #{e.message}"
    end

    # Helper: Call HA script with consistent error handling
    def self.call_ha_script(script_name, variables = {})
      result = ha_client.call_service('script', script_name, variables)

      if result
        "✅ Script #{script_name} executed successfully"
      else
        "❌ Script #{script_name} failed"
      end
    rescue StandardError => e
      "❌ HA Script Error: #{e.message}"
    end

    # Helper: Get HA state with error handling
    def self.get_ha_state(entity_id)
      state = ha_client.state(entity_id)
      return "Entity #{entity_id} not found" unless state

      {
        entity_id: entity_id,
        state: state['state'],
        attributes: state['attributes'] || {}
      }
    rescue StandardError => e
      "❌ State Error: #{e.message}"
    end

    # Helper: Validate required parameters
    def self.validate_required_params(params, required)
      missing = required.select { |param| params[param].nil? }
      return if missing.empty?

      raise ValidationError, "Missing required parameters: #{missing.join(', ')}"
    end

    # Helper: Parse JSON params safely
    def self.parse_json_params(params)
      return params if params.is_a?(Hash)
      return {} if params.nil? || params == ''

      JSON.parse(params.to_s)
    rescue JSON::ParserError => e
      raise ValidationError, "Invalid JSON parameters: #{e.message}"
    end

    # Helper: Format response consistently
    def self.format_response(success, message, data = nil)
      response = success ? "✅ #{message}" : "❌ #{message}"
      response += "\nData: #{data}" if data
      response
    end

    # Helper: Validate HA service call parameters (non-blocking)
    def self.validate_ha_service_call(domain, service, data)
      return unless defined?(Services::HAServiceValidator)

      begin
        validation = Services::HAServiceValidator.validate_service_call(domain, service, data, ha_client: ha_client)
        unless validation[:valid]
          Services::Logging::SimpleLogger.warn('HA service validation warnings',
                                               tagged: %i[tool ha_validation],
                                               service: "#{domain}.#{service}",
                                               warnings: validation[:errors])
        end
      rescue StandardError => e
        Services::Logging::SimpleLogger.debug('HA service validation failed (non-blocking)',
                                              tagged: %i[tool ha_validation],
                                              service: "#{domain}.#{service}",
                                              error: e.message)
      end
    end

    private

    # Check if we should use mock HA (for testing)
    def self.use_mock_ha?
      GlitchCube.config.home_assistant.mock_enabled
    end

    # Mock HA client for testing
    def self.mock_ha_client
      @mock_ha_client ||= MockHomeAssistantClient.new
    end
  end

  # Simple mock HA client for testing
  class MockHomeAssistantClient
    def call_service(domain, service, data = {})
      puts "🧪 Mock HA: #{domain}.#{service} with #{data.inspect}"
      true
    end

    def state(entity_id)
      {
        'state' => 'mock_state',
        'attributes' => { 'friendly_name' => "Mock #{entity_id}" }
      }
    end

    def speak(message, entity_id: 'media_player.mock')
      puts "🧪 Mock TTS: '#{message}' on #{entity_id}"
      true
    end
  end
end
