# Enforce per-request timeout to prevent resource exhaustion from long-running LLM calls
if defined?(Rack::Timeout)
  Rack::Timeout.timeout = 20 # seconds
end
