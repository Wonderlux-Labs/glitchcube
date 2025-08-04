# Desiru Framework Technical Notes

Based on analysis of the Desiru gem source code and examples.

## Tool Definition Pattern

Tools for Desiru's ReAct module should follow this pattern:

```ruby
class MyTool
  def self.name
    "tool_name"  # Used to identify the tool in prompts
  end

  def self.description
    "Tool description. Args: param1 (type), param2 (type)"  # Human-readable description
  end

  def self.call(param1:, param2:)
    # Tool implementation
    # Must accept keyword arguments matching the description
    # Return a string describing the result
  end
end
```

Key points:
- Tools are classes with three class methods: `name`, `description`, and `call`
- The `call` method must accept keyword arguments
- Tools should return strings that describe their results
- No need for OpenAI-style parameter schemas

## ReAct Module Usage

```ruby
# Create agent with tools
agent = Desiru::Modules::ReAct.new(
  'input_signature -> output_signature',  # DSPy-style signature
  tools: [Tool1, Tool2, Tool3],          # Array of tool classes
  max_iterations: 5                       # Optional: max reasoning steps
)

# Call the agent
result = agent.call(input_field: "value")
```

## Sinatra Integration Patterns

### Option 1: Manual Integration (Current Approach)
```ruby
class MyApp < Sinatra::Base
  helpers do
    def my_module
      @my_module ||= Desiru::Modules::MyModule.new("signature")
    end
  end

  post '/endpoint' do
    result = my_module.call(params)
    json result
  end
end
```

### Option 2: Desiru API Builder
```ruby
api = Desiru::API.sinatra do
  register_module '/qa', qa_module, description: 'Q&A endpoint'
  register_module '/summarize', summarizer, description: 'Summarization'
end
```

Benefits of API builder:
- Built-in CORS support
- Automatic async handling
- Standardized error responses
- Request/response logging

## Error Handling

Desiru has a comprehensive error hierarchy:
- `Desiru::Error` - Base error class
- `Desiru::ModelError` - Model/LLM errors
- `Desiru::AuthenticationError` - Auth failures
- `Desiru::RateLimitError` - Rate limiting
- `Desiru::NetworkError` - Network issues
- `Desiru::TimeoutError` - Timeouts
- `Desiru::ValidationError` - Input validation

The framework handles model-specific errors internally and converts them to appropriate Desiru errors.

## Background Jobs with Sidekiq

```ruby
# Configure Redis
Desiru.configure do |config|
  config.redis_url = 'redis://localhost:6379'
end

# Async module call
result = module.call_async(input: "value")
# Returns immediately with job ID

# Check status
status = Desiru::Jobs.status(result[:job_id])
# => { status: 'processing', progress: 0.5 }

# Get result when ready
if status[:status] == 'completed'
  final_result = Desiru::Jobs.result(result[:job_id])
end
```

## Database Persistence

Desiru supports ActiveRecord for persistence:

```ruby
# In module
class MyModule < Desiru::Module
  persist_results_to :my_results_table
  
  def call(input)
    # Results automatically saved to database
  end
end
```

## Custom Tool Patterns

Tools can also be lambdas or hashes:

```ruby
# Lambda tool
my_tool = lambda do |param:|
  "Result for #{param}"
end

# Hash format
tool_hash = {
  name: "tool_name",
  function: my_tool
}

# Use in ReAct
agent = Desiru::Modules::ReAct.new(
  "signature",
  tools: [ClassTool, tool_hash]
)
```

## Key Differences from OpenAI Function Calling

1. **No JSON Schema**: Tools don't need parameter schemas
2. **Simple Interface**: Just name, description, and call methods
3. **String Returns**: Tools should return descriptive strings
4. **Keyword Arguments**: Tools must accept keyword args
5. **Framework Handles Orchestration**: ReAct module manages the tool selection and calling

## Our Implementation Issues

1. **TestTool**: Our implementation is correct after removing the unnecessary `parameters` method
2. **OpenRouter Adapter Bug**: Desiru's OpenRouter adapter incorrectly calls `@client.complete(params)` with a hash, but the open_router gem expects `complete(messages, **options)`
3. **Function Calling Endpoint**: Removed - Desiru uses ReAct pattern, not OpenAI-style function calling
4. **Testing**: Fixed to use real integration tests with VCR instead of mocking

## Patches Applied to Forked Desiru

We've forked Desiru to https://github.com/estiens/desiru and applied the following fixes:

1. **OpenRouter Adapter Fix**: The adapter was incorrectly calling `@client.complete(params)` with a hash, but the open_router gem expects `complete(messages, **options)`
2. **ReAct Module Tool Descriptions**: Tool descriptions weren't being included in the system prompt sent to the AI
3. **ReAct Module Class-based Tools**: The module didn't properly handle Class-based tools (it expected Methods/Procs)

The comprehensive patch is available at `/desiru_comprehensive_fixes.patch` and includes:
- Correct parameter structure for open_router gem API calls
- Proper error handling mapping to Desiru error classes
- Custom ReActChainOfThought class to include tool descriptions in system prompts
- Support for Class-based tools in execute_tool method