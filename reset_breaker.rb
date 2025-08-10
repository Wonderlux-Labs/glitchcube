#!/usr/bin/env ruby
# frozen_string_literal: true

cb = Services::CircuitBreakerService.openrouter_breaker
puts "State: #{cb.state}"
cb.send(:close!) if cb.state == :open
puts "New state: #{cb.state}"
