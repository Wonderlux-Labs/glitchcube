#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'config/initializers/config'
require_relative 'lib/services/circuit_breaker_service'

cb = Services::CircuitBreakerService.openrouter_breaker
puts "State: #{cb.state}"
cb.send(:close!) if cb.state == :open
puts "New state: #{cb.state}"
