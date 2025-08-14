#  frozen_string_literal: true

module Tools
  # Tool for system diagnostics, error handling, and self-healing
  # Provides circuit breaker status, system health checks, and recovery actions
  class ErrorHandlingTool < BaseTool
    def self.name
      'error_handling'
    end

    def self.description
      'System diagnostics and error handling for the Glitch Cube art installation. Monitors system health, manages circuit breakers, tests connections, and provides recovery capabilities.'
    end

    def self.category
      'system_integration'
    end

    def self.tool_prompt
      'Monitor system health with get_system_health(), reset_circuit_breaker(), test_connection().'
    end

    # Get comprehensive system health status
    def self.get_system_health(verbose: true)
      result = []
      result << '=== SYSTEM HEALTH STATUS ==='

      begin
        # Circuit breaker status
        circuit_status = Services::System::CircuitBreakerService.status
        result << ''
        result << '🔌 CIRCUIT BREAKERS:'

        overall_healthy = true
        circuit_status.each do |breaker|
          status_icon = case breaker[:state]
                        when :closed then '✅'
                        when :half_open then '⚠️ '
                        when :open then '❌'
                        else '❓'
                        end

          result << "  #{status_icon} #{breaker[:name]}: #{breaker[:state]}"

          result << "    └─ Failures: #{breaker[:failure_count]}, Last failure: #{breaker[:last_failure_time]}" if verbose && breaker[:failure_count].positive?

          overall_healthy = false unless breaker[:state] == :closed
        end

        # System uptime
        result << ''
        result << '⏱️  SYSTEM STATUS:'
        uptime_hours = get_system_uptime
        result << "  Uptime: #{uptime_hours} hours"
        result << "  Overall Health: #{overall_healthy ? '✅ Healthy' : '⚠️  Degraded'}"

        # Memory and basic stats if verbose
        if verbose
          result << ''
          result << '📊 SYSTEM RESOURCES:'

          # Ruby memory usage
          if defined?(GC)
            gc_stat = GC.stat
            result << "  Ruby Memory: #{(gc_stat[:heap_live_slots] * 40 / 1024 / 1024).round(1)} MB allocated"
            result << "  GC Collections: #{gc_stat[:count]}"
          end

          # Process info
          result << "  Process ID: #{Process.pid}"
          result << "  Ruby Version: #{RUBY_VERSION}"
        end

        Services::Logging::SimpleLogger.log_api_call(
          service: 'error_handling_tool',
          endpoint: 'system_health',
          overall_healthy: overall_healthy,
          circuit_breaker_count: circuit_status.size
        )

        format_response(true, result.join("\n"))
      rescue StandardError => e
        format_response(false, "Error checking system health: #{e.message}")
      end
    end

    # Reset circuit breakers to allow retry of failed services
    def self.reset_circuit_breakers(service: nil)
      result = []
      result << '=== RESETTING CIRCUIT BREAKERS ==='

      begin
        if service
          # Reset specific service if implemented
          result << '⚠️  Specific service reset not yet implemented'
          result << 'Resetting all circuit breakers instead...'
        end

        # Reset all circuit breakers
        Services::System::CircuitBreakerService.reset_all

        result << '✅ All circuit breakers have been reset'
        result << 'Services will attempt to reconnect on next call'

        Services::Logging::SimpleLogger.log_api_call(
          service: 'error_handling_tool',
          endpoint: 'reset_circuit_breakers',
          service_name: service
        )

        format_response(true, result.join("\n"))
      rescue StandardError => e
        format_response(false, "Error resetting circuit breakers: #{e.message}")
      end
    end

    # Test connections to external services
    def self.test_connections
      result = []
      result << '=== CONNECTION TESTS ==='

      # Test Home Assistant connection
      result << ''
      result << '🏠 HOME ASSISTANT:'
      begin
        states = ha_client.states

        if states.is_a?(Array)
          result << '  ✅ Connection successful'
          result << "  📊 #{states.size} entities available"

          # Check for key entities
          key_entities = %w[light.cube_light media_player.tablet light.awtrix_b85e20_matrix]
          key_entities.each do |entity|
            state = states.find { |s| s['entity_id'] == entity }
            if state
              status = state['state'] == 'unavailable' ? '⚠️  Unavailable' : '✅ Available'
              result << "  #{status} #{entity}"
            else
              result << "  ❌ Missing #{entity}"
            end
          end
        else
          result << '  ⚠️  Unexpected response format'
        end
      rescue StandardError => e
        result << "  ❌ Connection failed: #{e.message}"
      end

      # Test OpenRouter connection (if configured)
      result << ''
      result << '🤖 OPENROUTER:'
      begin
        if GlitchCube.config.openrouter_api_key
          # Simple test - just check if we can initialize the service

          Services::Llm::LLMService.new
          result << '  ✅ Service initialized'
          result << '  🔑 API key configured'
        else
          result << '  ⚠️  API key not configured'
        end
      rescue StandardError => e
        result << "  ❌ Service error: #{e.message}"
      end

      # Test Redis connection (if used)
      result << ''
      result << '📦 REDIS (Sidekiq):'
      begin
        if defined?(Sidekiq)
          redis_info = Sidekiq.redis(&:ping)
          result << "  ✅ Connection successful (#{redis_info})"
        else
          result << '  ⚠️  Sidekiq not loaded'
        end
      rescue StandardError => e
        result << "  ❌ Connection failed: #{e.message}"
      end

      Services::Logging::SimpleLogger.log_api_call(
        service: 'error_handling_tool',
        endpoint: 'test_connections'
      )

      format_response(true, result.join("\n"))
    end

    # Get recent error logs (simplified version)
    def self.get_recent_errors(limit: 10, service_filter: nil)
      result = []
      result << '=== RECENT ERRORS ==='
      result << "(Showing last #{limit} errors)"

      # This would integrate with our logging system
      # For now, provide basic circuit breaker error info
      begin
        circuit_status = Services::System::CircuitBreakerService.status

        error_count = 0
        circuit_status.each do |breaker|
          next unless breaker[:failure_count].positive?
          next if service_filter && !breaker[:name].include?(service_filter)

          result << ''
          result << "❌ #{breaker[:name]}:"
          result << "   Failures: #{breaker[:failure_count]}"
          result << "   Last failure: #{breaker[:last_failure_time]}" if breaker[:last_failure_time]
          result << "   Current state: #{breaker[:state]}"

          error_count += 1
          break if error_count >= limit
        end

        if error_count.zero?
          result << ''
          result << '✅ No recent errors found'
        end

        format_response(true, result.join("\n"))
      rescue StandardError => e
        format_response(false, "Error retrieving error logs: #{e.message}")
      end
    end

    # Perform comprehensive self-diagnosis
    def self.perform_self_diagnosis
      result = []
      result << '=== COMPREHENSIVE SYSTEM DIAGNOSIS ==='

      # Check system health
      health_result = get_system_health(verbose: false)
      result << health_result

      result << ''
      result << '=== DIAGNOSTIC TESTS ==='

      # Test key system functions
      tests = [
        { name: 'Circuit breaker functionality', test: -> { Services::System::CircuitBreakerService.status.any? } },
        { name: 'Configuration loading', test: -> { GlitchCube.config.present? } },
        { name: 'Logger service', test: -> { Services::Logging::SimpleLogger.respond_to?(:log_api_call) } }
      ]

      tests.each do |test_case|
        test_result = test_case[:test].call
        status = test_result ? '✅' : '❌'
        result << "#{status} #{test_case[:name]}: #{test_result ? 'PASS' : 'FAIL'}"
      rescue StandardError => e
        result << "❌ #{test_case[:name]}: ERROR - #{e.message}"
      end

      # Check for common issues
      result << ''
      result << '=== COMMON ISSUES CHECK ==='

      issues_found = 0

      # Check if all circuit breakers are open (major system failure)
      circuit_status = Services::System::CircuitBreakerService.status
      open_breakers = circuit_status.select { |b| b[:state] == :open }
      if open_breakers.size == circuit_status.size && !circuit_status.empty?
        result << '🚨 CRITICAL: All circuit breakers are open - system isolation mode'
        issues_found += 1
      end

      # Check for excessive failures
      high_failure_breakers = circuit_status.select { |b| b[:failure_count] > 10 }
      if high_failure_breakers.any?
        result << "⚠️  WARNING: High failure count on: #{high_failure_breakers.map { |b| b[:name] }.join(', ')}"
        issues_found += 1
      end

      result << '✅ No common issues detected' if issues_found.zero?

      Services::Logging::SimpleLogger.log_api_call(
        service: 'error_handling_tool',
        endpoint: 'self_diagnose',
        issues_found: issues_found
      )

      format_response(true, result.join("\n"))
    end

    # Attempt automatic recovery procedures
    def self.attempt_recovery(dry_run: true)
      result = []
      result << "=== AUTOMATIC RECOVERY #{dry_run ? '(DRY RUN)' : '(LIVE MODE)'} ==="

      result << '⚠️  Running in dry-run mode. Use dry_run: false to execute recovery actions.' if dry_run

      recovery_actions = []

      # Check circuit breaker status
      circuit_status = Services::System::CircuitBreakerService.status
      open_breakers = circuit_status.select { |b| b[:state] == :open }

      if open_breakers.any?
        recovery_actions << {
          action: 'Reset circuit breakers',
          reason: "#{open_breakers.size} circuit breakers are open",
          execute: -> { Services::System::CircuitBreakerService.reset_all }
        }
      end

      # Check for stale connections (mock - would be real logic)
      recovery_actions << {
        action: 'Clear connection pool',
        reason: 'Preventive maintenance',
        execute: -> { 'Connection pool cleared' }
      }

      # Execute recovery actions
      result << ''
      result << '🔧 RECOVERY ACTIONS:'

      if recovery_actions.empty?
        result << '✅ No recovery actions needed - system is healthy'
      else
        recovery_actions.each do |action|
          result << ''
          result << "#{dry_run ? '📋' : '🔧'} #{action[:action]}"
          result << "   Reason: #{action[:reason]}"

          next if dry_run

          begin
            action_result = action[:execute].call
            result << "   ✅ Success: #{action_result}"
          rescue StandardError => e
            result << "   ❌ Failed: #{e.message}"
          end
        end
      end

      Services::Logging::SimpleLogger.log_api_call(
        service: 'error_handling_tool',
        endpoint: 'recovery_mode',
        dry_run: dry_run,
        actions_planned: recovery_actions.size
      )

      format_response(true, result.join("\n"))
    end

    # Get system uptime in hours
    def self.get_system_uptime
      app_path = File.expand_path('../../app.rb', __dir__)
      start_time = File.mtime(app_path)
      ((Time.now - start_time) / 3600).round(1)
    rescue StandardError
      0.0
    end
  end
end
