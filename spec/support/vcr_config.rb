# frozen_string_literal: true

# Zero-Leak VCR Configuration
# Bulletproof VCR setup that prevents API leaks while keeping usage simple
module ZeroLeakVCR
  class << self
    def configure!
      VCR.configure do |config|
        # Core settings
        config.cassette_library_dir = 'spec/vcr_cassettes'
        config.hook_into :webmock
        config.configure_rspec_metadata!

        # SECURITY: Never allow HTTP connections without cassettes by default
        config.allow_http_connections_when_no_cassette = false
        config.ignore_localhost = false # Record localhost calls too for completeness

        # Smart defaults for all cassettes
        config.default_cassette_options = {
          # Recording mode based on environment
          record: recording_mode,
          # Match on method, URI, and body for deterministic matching
          match_requests_on: %i[method uri],
          # Allow same request multiple times in a test
          allow_playback_repeats: true,
          # UTF-8 encoding for consistency
          serialize_with: :yaml,
          preserve_exact_body_bytes: true,
          # Decode compressed responses for readability
          decode_compressed_response: true
        }

        # Filter all sensitive data
        filter_sensitive_data!(config)

        # Set up request handling based on environment
        setup_request_handling!(config)

        # Log VCR activity appropriately
        setup_logging!(config)
      end

      puts vcr_mode_message
    end

    private

    def recording_mode
      if ci_mode? || vcr_none_mode?
        :none # Never record in CI or when VCR_NONE is set
      elsif vcr_override_mode?
        :new_episodes # Re-record everything when VCR_OVERRIDE is set
      else
        :once # Development default: record once if missing, replay if exists
      end
    end

    def ci_mode?
      ENV['CI'] == 'true'
    end

    def vcr_override_mode?
      # Check for environment variable only (RSpec doesn't like custom args)
      ENV['VCR_OVERRIDE'] == 'true'
    end

    def vcr_none_mode?
      # Check for environment variable only (emulate CI behavior)
      ENV['VCR_NONE'] == 'true'
    end

    def filter_sensitive_data!(config)
      # Filter environment-based secrets
      config.filter_sensitive_data('<OPENROUTER_API_KEY>') { ENV.fetch('OPENROUTER_API_KEY', nil) }
      config.filter_sensitive_data('<HOME_ASSISTANT_TOKEN>') { ENV.fetch('HOME_ASSISTANT_TOKEN', nil) }
      config.filter_sensitive_data('<GITHUB_TOKEN>') { ENV.fetch('GITHUB_TOKEN', nil) }
      config.filter_sensitive_data('<ANTHROPIC_API_KEY>') { ENV.fetch('ANTHROPIC_API_KEY', nil) }
      config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV.fetch('OPENAI_API_KEY', nil) }

      # Filter headers and request/response bodies
      config.before_record do |interaction|
        # Handle Authorization headers (both string and array)
        filter_header(interaction, 'Authorization', /Bearer .+/, 'Bearer <TOKEN>')
        filter_header(interaction, 'X-Api-Key', /.+/, '<API_KEY>')
        filter_header(interaction, 'Anthropic-Version', /.+/, '<VERSION>')
        filter_header(interaction, 'OpenAI-Organization', /.+/, '<ORG_ID>')

        # Filter Home Assistant specific data
        filter_ha_sensitive_data!(interaction)

        # Filter LLM API request/response bodies
        filter_llm_sensitive_data!(interaction)

        # Validate no raw secrets leaked
        validate_no_secrets!(interaction)
      end
    end

    def filter_header(interaction, header_name, pattern, replacement)
      header = interaction.request.headers[header_name]
      return unless header

      if header.is_a?(Array)
        interaction.request.headers[header_name] = header.map { |h| h.gsub(pattern, replacement) }
      elsif header.is_a?(String)
        interaction.request.headers[header_name] = header.gsub(pattern, replacement)
      end
    end

    def setup_request_handling!(config)
      if ci_mode?
        setup_ci_mode!(config)
      else
        setup_development_mode!(config)
      end
    end

    def setup_ci_mode!(config)
      # In CI: Fail fast if trying to record
      config.before_record do |interaction|
        raise build_ci_recording_error(interaction)
      end

      # Block any external requests without cassettes
      config.before_http_request do |request|
        next if localhost_request?(request)
        next if VCR.current_cassette

        raise build_missing_cassette_error(request)
      end
    end

    def setup_development_mode!(config)
      # Development: Block external requests without cassettes, provide helpful errors
      config.before_http_request do |request|
        next if localhost_request?(request)
        next if VCR.current_cassette

        # Log the unhandled request
        log_unhandled_request(request)

        raise build_missing_cassette_error(request)
      end
    end

    def localhost_request?(request)
      host = extract_host(request)
      host&.match?(/\A(localhost|127\.0\.0\.1|::1)\z/)
    end

    def extract_host(request)
      uri = request.uri
      uri = URI.parse(uri.to_s) unless uri.respond_to?(:host)
      uri.host
    end

    def log_unhandled_request(request)
      log_file = File.join('logs', 'vcr_unhandled_requests.log')
      FileUtils.mkdir_p(File.dirname(log_file))

      File.open(log_file, 'a') do |f|
        f.puts "❌ UNHANDLED REQUEST: #{Time.now.iso8601}"
        f.puts "   Test: #{current_test_description}"
        f.puts "   Location: #{current_test_location}"
        f.puts "   Request: #{request.method.upcase} #{request.uri}"
        f.puts "   Fix: VCR_RECORD=true bundle exec rspec #{current_test_location}"
        f.puts '-' * 80
      end
    end

    def current_test_description
      RSpec.current_example&.full_description || 'Unknown test'
    end

    def current_test_location
      RSpec.current_example&.location || 'Unknown location'
    end

    def setup_logging!(config)
      return if ci_mode?

      if vcr_override_mode?
        setup_recording_logs!(config)
      elsif ENV['VCR_DEBUG'] == 'true'
        setup_debug_logs!(config)
      end
    end

    def setup_recording_logs!(config)
      logged_requests = Set.new

      config.before_record do |interaction|
        uri = URI.parse(interaction.request.uri.to_s)
        request_key = "#{interaction.request.method.upcase} #{uri.host}#{uri.path}"

        unless logged_requests.include?(request_key)
          puts "🎥 Recording: #{request_key}"
          logged_requests.add(request_key)
        end
      end
    end

    def setup_debug_logs!(config)
      config.before_playback do |interaction|
        puts "▶️  Playing: #{interaction.request.method.upcase} #{interaction.request.uri}"
      end
    end

    def build_ci_recording_error(interaction)
      <<~ERROR
        ❌ VCR TRIED TO RECORD IN CI!

        Request: #{interaction.request.method.upcase} #{interaction.request.uri}

        This should never happen in CI. Cassettes must be recorded locally and committed.
        The test is missing a cassette or the cassette doesn't match the request.

        Fix by recording locally:
        VCR_RECORD=true bundle exec rspec #{current_test_location}
      ERROR
    end

    def build_missing_cassette_error(request)
      host = extract_host(request)

      <<~ERROR
        ❌ NO VCR CASSETTE FOR EXTERNAL REQUEST

        Request: #{request.method.upcase} #{request.uri}
        Host: #{host}
        Test: #{current_test_location}

        CRITICAL: All external HTTP requests MUST go through VCR!

        Quick fix:
        1. Record the cassette: VCR_RECORD=true bundle exec rspec #{current_test_location}
        2. Commit the cassette in spec/vcr_cassettes/
        3. Re-run the test

        For new tests, add: vcr: true to your test
      ERROR
    end

    def filter_ha_sensitive_data!(interaction)
      # Filter Home Assistant URLs and IPs with VALID URI placeholders
      uri_string = interaction.request.uri.to_s
      if uri_string.include?('glitch.local') || uri_string.match?(/\d+\.\d+\.\d+\.\d+/)
        # Use VALID hostnames as placeholders that won't break URI parsing
        new_uri = interaction.request.uri.to_s
                             .gsub('glitch.local', 'test-homeassistant.local')
                             .gsub(/\d+\.\d+\.\d+\.\d+/, '127.0.0.1')
        interaction.request.uri = new_uri
      end

      # Filter sensitive Home Assistant data in response bodies
      return unless interaction.response.body

      body = interaction.response.body
      # Filter GPS coordinates (latitude/longitude)
      body.gsub!(/("latitude":\s*)-?\d+\.\d+/, '\1<LATITUDE>')
      body.gsub!(/("longitude":\s*)-?\d+\.\d+/, '\1<LONGITUDE>')
      # Filter device identifiers
      body.gsub!(/("device_id":\s*")[^"]+/, '\1<DEVICE_ID>')
      body.gsub!(/("entity_id":\s*"device_tracker\.)[^"]+/, '\1<DEVICE_TRACKER>')
    end

    def filter_llm_sensitive_data!(interaction)
      return unless interaction.request.body

      # Parse request body to filter LLM prompts that might contain sensitive data
      begin
        if interaction.request.headers['Content-Type']&.include?('application/json')
          body_text = interaction.request.body

          # Filter system prompts that might contain location data
          body_text.gsub!(/latitude[:\s]+[\d.-]+/i, 'latitude: <LATITUDE>')
          body_text.gsub!(/longitude[:\s]+[\d.-]+/i, 'longitude: <LONGITUDE>')
          body_text.gsub!(/gps[:\s]+[\d.-]+,\s*[\d.-]+/i, 'gps: <GPS_COORDS>')

          # Filter any API keys that might be in prompts
          body_text.gsub!(/[a-z0-9]{32,}/i) do |match|
            # Only filter if it looks like a key (long alphanumeric string)
            match.length > 20 ? '<FILTERED_KEY>' : match
          end

          interaction.request.body = body_text
        end
      rescue StandardError
        # If we can't parse, just continue - don't break the test
      end
    end

    def validate_no_secrets!(interaction)
      # List of patterns that should never appear in cassettes
      secret_patterns = [
        /sk-[a-zA-Z0-9]{32,}/, # OpenAI API keys
        /[a-f0-9]{64}/, # Long hex strings (potential tokens)
        /eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+/, # JWT tokens
        /Bearer [a-zA-Z0-9_-]{20,}/ # Long bearer tokens
      ]

      # Check request and response for secret patterns
      all_text = [
        interaction.request.uri.to_s,
        interaction.request.body.to_s,
        interaction.response.body.to_s,
        interaction.request.headers.to_s
      ].join(' ')

      secret_patterns.each do |pattern|
        if all_text.match?(pattern)
          log_secret_leak_warning(pattern, interaction)
        end
      end
    end

    def log_secret_leak_warning(pattern, interaction)
      warning_msg = <<~WARNING
        ⚠️  POTENTIAL SECRET DETECTED IN VCR CASSETTE!

        Pattern: #{pattern}
        URL: #{interaction.request.uri}
        Test: #{current_test_description}

        This might be a security issue. Please verify the cassette is safe to commit.
      WARNING

      puts warning_msg

      # Log to file for later review
      log_file = File.join('logs', 'vcr_security_warnings.log')
      FileUtils.mkdir_p(File.dirname(log_file))
      File.open(log_file, 'a') do |f|
        f.puts "#{Time.now.iso8601}: #{warning_msg}"
        f.puts '-' * 80
      end
    end

    def vcr_mode_message
      if ci_mode?
        '🔒 CI Mode: VCR will only replay existing cassettes (no recording allowed)'
      elsif vcr_none_mode?
        '🛡️ VCR_NONE Mode: Emulating CI - will only replay existing cassettes'
      elsif vcr_override_mode?
        '🔄 Override Mode: VCR will re-record all cassettes - remember to commit!'
      else
        '📼 Development Mode: VCR will record missing cassettes once, replay existing'
      end
    end
  end
end
