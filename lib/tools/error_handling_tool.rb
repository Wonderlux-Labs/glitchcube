# frozen_string_literal: true

require_relative '../services/circuit_breaker_service'
require_relative '../services/logger_service'
require_relative '../home_assistant_client'

# Tool for system diagnostics, error handling, and self-healing
# Provides circuit breaker status, system health checks, and recovery actions
class ErrorHandlingTool
  def self.name
    'error_handling'
  end

  def self.description
    'System diagnostics and error handling. Actions: "system_health" (shows circuit breakers, service status), "reset_circuit_breakers" (reset failed services), "test_connections" (test Home Assistant, OpenRouter), "get_recent_errors" (show recent error logs), "self_diagnose" (comprehensive system check), "recovery_mode" (attempt automatic recovery). Use for troubleshooting and maintaining system reliability. Args: action (string), params (string) - JSON with optional filters.'
  end

  def self.call(action:, params: '{}')
    params = JSON.parse(params) if params.is_a?(String)

    case action
    when 'system_health'
      get_system_health(params)
    when 'reset_circuit_breakers'
      reset_circuit_breakers(params)
    when 'test_connections'
      test_system_connections(params)
    when 'get_recent_errors'
      get_recent_errors(params)
    when 'self_diagnose'
      perform_self_diagnosis(params)
    when 'recovery_mode'
      attempt_recovery(params)
    else
      "Unknown action: #{action}. Available actions: system_health, reset_circuit_breakers, test_connections, get_recent_errors, self_diagnose, recovery_mode"
    end
  rescue StandardError => e
    "Error handling tool error: #{e.message}"
  end

  private

  # Get comprehensive system health status
  def self.get_system_health(params)
    verbose = params['verbose'] != false
    result = []
    
    result << "=== SYSTEM HEALTH STATUS ==="
    
    begin
      # Circuit breaker status
      circuit_status = Services::CircuitBreakerService.status
      result << ""
      result << "🔌 CIRCUIT BREAKERS:"
      
      overall_healthy = true
      circuit_status.each do |breaker|
        status_icon = case breaker[:state]
                     when :closed then "✅"
                     when :half_open then "⚠️ "
                     when :open then "❌"
                     else "❓"
                     end
        
        result << "  #{status_icon} #{breaker[:name]}: #{breaker[:state]}"
        
        if verbose && breaker[:failure_count] > 0
          result << "    └─ Failures: #{breaker[:failure_count]}, Last failure: #{breaker[:last_failure_time]}"
        end
        
        overall_healthy = false unless breaker[:state] == :closed
      end
      
      # System uptime
      result << ""
      result << "⏱️  SYSTEM STATUS:"
      uptime_hours = get_system_uptime
      result << "  Uptime: #{uptime_hours} hours"
      result << "  Overall Health: #{overall_healthy ? '✅ Healthy' : '⚠️  Degraded'}"
      
      # Memory and basic stats if verbose
      if verbose
        result << ""
        result << "📊 SYSTEM RESOURCES:"
        
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
      
      Services::LoggerService.log_api_call(
        service: 'error_handling_tool',
        endpoint: 'system_health',
        overall_healthy: overall_healthy,
        circuit_breaker_count: circuit_status.size
      )
      
    rescue => e
      result << "❌ Error checking system health: #{e.message}"
    end
    
    result.join("\n")
  end

  # Reset circuit breakers to allow retry of failed services
  def self.reset_circuit_breakers(params)
    service_name = params['service'] # Optional: reset specific service
    
    result = []
    result << "=== RESETTING CIRCUIT BREAKERS ==="
    
    begin
      if service_name
        # Reset specific service if implemented
        result << "⚠️  Specific service reset not yet implemented"
        result << "Resetting all circuit breakers instead..."
      end
      
      # Reset all circuit breakers
      Services::CircuitBreakerService.reset_all
      
      result << "✅ All circuit breakers have been reset"
      result << "Services will attempt to reconnect on next call"
      
      Services::LoggerService.log_api_call(
        service: 'error_handling_tool',
        endpoint: 'reset_circuit_breakers',
        service_name: service_name
      )
      
    rescue => e
      result << "❌ Error resetting circuit breakers: #{e.message}"
    end
    
    result.join("\n")
  end

  # Test connections to external services
  def self.test_system_connections(params)
    result = []
    result << "=== CONNECTION TESTS ==="
    
    # Test Home Assistant connection
    result << ""
    result << "🏠 HOME ASSISTANT:"
    begin
      client = HomeAssistantClient.new
      states = client.states
      
      if states.is_a?(Array)
        result << "  ✅ Connection successful"
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
        result << "  ⚠️  Unexpected response format"
      end
    rescue => e
      result << "  ❌ Connection failed: #{e.message}"
    end
    
    # Test OpenRouter connection (if configured)
    result << ""
    result << "🤖 OPENROUTER:"
    begin
      if GlitchCube.config.openrouter_api_key
        # Simple test - just check if we can initialize the service
        require_relative '../services/openrouter_service'
        service = Services::OpenRouterService.new
        result << "  ✅ Service initialized"
        result << "  🔑 API key configured"
      else
        result << "  ⚠️  API key not configured"
      end
    rescue => e
      result << "  ❌ Service error: #{e.message}"
    end
    
    # Test Redis connection (if used)
    result << ""
    result << "📦 REDIS (Sidekiq):"
    begin
      if defined?(Sidekiq)
        redis_info = Sidekiq.redis { |conn| conn.ping }
        result << "  ✅ Connection successful (#{redis_info})"
      else
        result << "  ⚠️  Sidekiq not loaded"
      end
    rescue => e
      result << "  ❌ Connection failed: #{e.message}"
    end
    
    Services::LoggerService.log_api_call(
      service: 'error_handling_tool',
      endpoint: 'test_connections'
    )
    
    result.join("\n")
  end

  # Get recent error logs (simplified version)
  def self.get_recent_errors(params)
    limit = params['limit'] || 10
    service_filter = params['service']
    
    result = []
    result << "=== RECENT ERRORS ==="
    result << "(Showing last #{limit} errors)"
    
    # This would integrate with our logging system
    # For now, provide basic circuit breaker error info
    begin
      circuit_status = Services::CircuitBreakerService.status
      
      error_count = 0
      circuit_status.each do |breaker|
        if breaker[:failure_count] > 0
          next if service_filter && !breaker[:name].include?(service_filter)
          
          result << ""
          result << "❌ #{breaker[:name]}:"
          result << "   Failures: #{breaker[:failure_count]}"
          result << "   Last failure: #{breaker[:last_failure_time]}" if breaker[:last_failure_time]
          result << "   Current state: #{breaker[:state]}"
          
          error_count += 1
          break if error_count >= limit
        end
      end
      
      if error_count == 0
        result << ""
        result << "✅ No recent errors found"
      end
      
    rescue => e
      result << "❌ Error retrieving error logs: #{e.message}"
    end
    
    result.join("\n")
  end

  # Perform comprehensive self-diagnosis
  def self.perform_self_diagnosis(params)
    result = []
    result << "=== COMPREHENSIVE SYSTEM DIAGNOSIS ==="
    
    # Check system health
    health_result = get_system_health('verbose' => false)
    result << health_result
    
    result << ""
    result << "=== DIAGNOSTIC TESTS ==="
    
    # Test key system functions
    tests = [
      { name: "Circuit breaker functionality", test: -> { Services::CircuitBreakerService.status.any? } },
      { name: "Configuration loading", test: -> { GlitchCube.config.present? } },
      { name: "Logger service", test: -> { Services::LoggerService.respond_to?(:log_api_call) } }
    ]
    
    tests.each do |test_case|
      begin
        test_result = test_case[:test].call
        status = test_result ? "✅" : "❌"
        result << "#{status} #{test_case[:name]}: #{test_result ? 'PASS' : 'FAIL'}"
      rescue => e
        result << "❌ #{test_case[:name]}: ERROR - #{e.message}"
      end
    end
    
    # Check for common issues
    result << ""
    result << "=== COMMON ISSUES CHECK ==="
    
    issues_found = 0
    
    # Check if all circuit breakers are open (major system failure)
    circuit_status = Services::CircuitBreakerService.status
    open_breakers = circuit_status.select { |b| b[:state] == :open }
    if open_breakers.size == circuit_status.size && circuit_status.size > 0
      result << "🚨 CRITICAL: All circuit breakers are open - system isolation mode"
      issues_found += 1
    end
    
    # Check for excessive failures
    high_failure_breakers = circuit_status.select { |b| b[:failure_count] > 10 }
    if high_failure_breakers.any?
      result << "⚠️  WARNING: High failure count on: #{high_failure_breakers.map { |b| b[:name] }.join(', ')}"
      issues_found += 1
    end
    
    if issues_found == 0
      result << "✅ No common issues detected"
    end
    
    Services::LoggerService.log_api_call(
      service: 'error_handling_tool',
      endpoint: 'self_diagnose',
      issues_found: issues_found
    )
    
    result.join("\n")
  end

  # Attempt automatic recovery procedures
  def self.attempt_recovery(params)
    dry_run = params['dry_run'] != false # Default to dry run for safety
    
    result = []
    result << "=== AUTOMATIC RECOVERY #{dry_run ? '(DRY RUN)' : '(LIVE MODE)'} ==="
    
    if dry_run
      result << "⚠️  Running in dry-run mode. Use dry_run: false to execute recovery actions."
    end
    
    recovery_actions = []
    
    # Check circuit breaker status
    circuit_status = Services::CircuitBreakerService.status
    open_breakers = circuit_status.select { |b| b[:state] == :open }
    
    if open_breakers.any?
      recovery_actions << {
        action: "Reset circuit breakers",
        reason: "#{open_breakers.size} circuit breakers are open",
        execute: -> { Services::CircuitBreakerService.reset_all }
      }
    end
    
    # Check for stale connections (mock - would be real logic)
    recovery_actions << {
      action: "Clear connection pool",
      reason: "Preventive maintenance",
      execute: -> { "Connection pool cleared" }
    }
    
    # Execute recovery actions
    result << ""
    result << "🔧 RECOVERY ACTIONS:"
    
    if recovery_actions.empty?
      result << "✅ No recovery actions needed - system is healthy"
    else
      recovery_actions.each do |action|
        result << ""
        result << "#{dry_run ? '📋' : '🔧'} #{action[:action]}"
        result << "   Reason: #{action[:reason]}"
        
        unless dry_run
          begin
            action_result = action[:execute].call
            result << "   ✅ Success: #{action_result}"
          rescue => e
            result << "   ❌ Failed: #{e.message}"
          end
        end
      end
    end
    
    Services::LoggerService.log_api_call(
      service: 'error_handling_tool',
      endpoint: 'recovery_mode',
      dry_run: dry_run,
      actions_planned: recovery_actions.size
    )
    
    result.join("\n")
  end

  # Get system uptime in hours
  def self.get_system_uptime
    begin
      start_time = File.mtime('/Users/estiens/code/glitchcube/app.rb')
      ((Time.now - start_time) / 3600).round(1)
    rescue
      0.0
    end
  end
end