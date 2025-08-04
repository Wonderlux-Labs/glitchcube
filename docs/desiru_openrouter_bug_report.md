# Bug Report: Desiru OpenRouter Adapter Incorrect API Call

## Summary
The Desiru OpenRouter adapter (`lib/desiru/models/open_router.rb`) incorrectly calls the open_router gem's `complete` method, causing API requests to fail with a 400 Bad Request error.

## Environment
- desiru version: 0.2.0
- open_router version: 0.3.3
- Ruby version: 3.4.0

## Bug Description
The Desiru OpenRouter adapter calls the open_router gem's `complete` method with a single hash parameter:

```ruby
# In desiru-0.2.0/lib/desiru/models/open_router.rb, line 62
response = @client.complete(params)
```

However, the open_router gem's `complete` method signature expects the messages array as the first positional argument:

```ruby
# In open_router-0.3.3/lib/open_router/client.rb, line 31
def complete(messages, model: "openrouter/auto", providers: [], transforms: [], extras: {}, stream: nil)
```

## Error Details
This causes the API request body to be malformed:

```json
{
  "messages": {
    "model": "google/gemini-2.5-flash",
    "messages": [...]
  },
  "model": "openrouter/auto"
}
```

The OpenRouter API returns a 400 error: `"Input required: specify \"prompt\" or \"messages\""`

## Root Cause
The issue occurs in both `perform_completion` and `stream_complete` methods:

1. **perform_completion** (line 36-62):
```ruby
params = {
  model: model,
  messages: messages,
  temperature: temperature,
  max_tokens: max_tokens
}
# ... additional params setup ...
response = @client.complete(params)  # INCORRECT
```

2. **stream_complete** (line 70-91):
```ruby
params = {
  model: model,
  messages: messages,
  temperature: temperature,
  max_tokens: max_tokens,
  stream: true
}
@client.complete(params) do |chunk|  # INCORRECT
```

## Expected Behavior
The adapter should call the open_router client with the correct parameter structure:

```ruby
response = @client.complete(
  messages,
  model: model,
  extras: {
    temperature: temperature,
    max_tokens: max_tokens,
    # other parameters...
  }
)
```

## Verification
I verified this by testing both calling patterns:

```ruby
# Test script
client = OpenRouter::Client.new(access_token: ENV['OPENROUTER_API_KEY'])
messages = [
  { role: 'system', content: 'You are a helpful assistant.' },
  { role: 'user', content: 'Say hello' }
]

# Correct way (works)
response = client.complete(messages, model: 'google/gemini-2.5-flash')
# => Success

# Desiru's way (fails)
params = { messages: messages, model: 'google/gemini-2.5-flash' }
response = client.complete(params)
# => Faraday::BadRequestError: the server responded with status 400
```

## Proposed Fix
Update the `perform_completion` method to correctly call the open_router client:

```ruby
def perform_completion(messages, options)
  model = options[:model] || @config[:model] || DEFAULT_MODEL
  temperature = options[:temperature] || @config[:temperature] || 0.7
  max_tokens = options[:max_tokens] || @config[:max_tokens] || 4096

  # Prepare parameters for open_router gem
  params = {
    model: model,
    extras: {
      temperature: temperature,
      max_tokens: max_tokens
    }
  }

  # Add provider-specific options if needed
  params[:providers] = [options[:provider]] if options[:provider]

  # Add response format if specified
  params[:extras][:response_format] = options[:response_format] if options[:response_format]

  # Add tools if provided
  if options[:tools]
    params[:extras][:tools] = options[:tools]
    params[:extras][:tool_choice] = options[:tool_choice] if options[:tool_choice]
  end

  # Make API call with correct parameter structure
  response = @client.complete(messages, **params)

  # Format response
  format_response(response, model)
rescue StandardError => e
  handle_api_error(e)
end
```

Similar changes needed for `stream_complete` method.

## Additional Issues

### 1. Undefined Error Constants
The `handle_api_error` method references undefined constants:
- `InvalidRequestError` (line 150)
- `APIError` (lines 154, 156)

These should be changed to use Desiru's existing error classes:
- `InvalidRequestError` → `Desiru::ModelError`
- `APIError` → `Desiru::ModelError`

### 2. Missing Error Classes in Rescue
The error handling should include `::OpenRouter::ServerError` which is the only error class defined by the open_router gem.

## Impact
This bug prevents any API calls through the Desiru OpenRouter adapter from working, making the integration completely non-functional.

## Workaround
As a temporary workaround, users can monkey-patch the affected methods as shown in the attached patch file.