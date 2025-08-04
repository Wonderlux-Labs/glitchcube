# Desiru Framework Developer Guide: Interactive Art Implementation

**Author:** Manus AI  
**Date:** August 3, 2025  
**Target Audience:** Senior Ruby Developers  

## Quick Start

```ruby
# Gemfile
gem 'desiru'
gem 'sinatra'
gem 'sidekiq'
gem 'redis'

# Install
bundle install

# Basic setup
require 'desiru'
require 'sinatra'

Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenRouter.new(
    api_key: ENV['OPENROUTER_API_KEY'],
    model: 'anthropic/claude-3-haiku-20240307'
  )
end
```

## Installation and Setup

### Dependencies

```ruby
# Gemfile
source 'https://rubygems.org'

gem 'desiru'
gem 'sinatra'
gem 'sidekiq'
gem 'redis'
gem 'rack'
gem 'rack-cors'  # For CORS if needed
gem 'puma'       # Web server

group :development, :test do
  gem 'rspec'
  gem 'rack-test'
  gem 'webmock'
end
```

### Environment Configuration

```bash
# .env
OPENROUTER_API_KEY=your_openrouter_key
REDIS_URL=redis://localhost:6379
RACK_ENV=development
```

### Basic Project Structure

```
/project_root
  /lib
    /modules          # Custom Desiru modules
    /tools           # Tool definitions
    /jobs            # Background job classes
  /config
    application.rb   # Main app configuration
  /spec
    /modules         # Module tests
    /tools          # Tool tests
    /integration    # API integration tests
  app.rb            # Main Sinatra application
  config.ru         # Rack configuration
```

## Type System and Signatures

Desiru uses a signature-based type system for defining module inputs and outputs. This provides runtime validation and clear interfaces.

### Basic Signatures

```ruby
# Simple signature
signature = Desiru::Signature.new(
  "input: string -> output: string"
)

# Complex signature with multiple types
signature = Desiru::Signature.new(
  "message: string, context: list[dict], user_id: string -> response: string, emotion: string, confidence: float"
)

# With descriptions for better documentation
signature = Desiru::Signature.new(
  "image_path: string, analysis_type: string -> analysis: dict, confidence: float",
  descriptions: {
    image_path: "Absolute path to the image file",
    analysis_type: "Type of analysis: 'basic', 'detailed', 'artistic'",
    analysis: "Structured analysis results including composition, colors, style",
    confidence: "Confidence score from 0.0 to 1.0"
  }
)
```

### Supported Types

```ruby
# Primitive types
"text: string"
"count: int" 
"score: float"
"active: bool"

# Collection types
"items: list[string]"
"metadata: dict"
"coordinates: list[float]"

# Literal types (enums)
"category: Literal['art', 'photo', 'sketch']"
"mood: Literal['happy', 'sad', 'neutral', 'excited']"

# Complex nested types
"results: list[dict]"
"analysis: dict[string, float]"
```

### Custom Module with Types

```ruby
class ImageAnalysisModule < Desiru::Module
  signature 'ImageAnalysis', 'Analyze uploaded images for artistic content'
  
  input 'image_path', type: 'string', desc: 'Path to image file'
  input 'analysis_depth', type: "Literal['basic', 'detailed', 'artistic']", desc: 'Analysis complexity level'
  input 'include_emotions', type: 'bool', desc: 'Whether to include emotional analysis'
  
  output 'composition', type: 'dict', desc: 'Composition analysis results'
  output 'colors', type: 'list[string]', desc: 'Dominant colors as hex codes'
  output 'style', type: 'string', desc: 'Detected artistic style'
  output 'emotions', type: 'list[string]', desc: 'Detected emotions (if requested)'
  output 'confidence', type: 'float', desc: 'Overall confidence score'

  def forward(image_path:, analysis_depth: 'detailed', include_emotions: false)
    # Implementation with proper return types
    {
      composition: analyze_composition(image_path, analysis_depth),
      colors: extract_colors(image_path),
      style: classify_style(image_path),
      emotions: include_emotions ? detect_emotions(image_path) : [],
      confidence: calculate_confidence
    }
  end

  private

  def analyze_composition(path, depth)
    # Returns dict with composition metrics
    case depth
    when 'basic'
      { balance: 0.8, focal_points: 2 }
    when 'detailed'
      { balance: 0.8, focal_points: 2, rule_of_thirds: true, symmetry: 0.3 }
    when 'artistic'
      { balance: 0.8, focal_points: 2, rule_of_thirds: true, symmetry: 0.3, 
        movement: 'diagonal', tension: 0.6, harmony: 0.7 }
    end
  end
end
```


## Error Handling

### Module-Level Error Handling

```ruby
class RobustImageModule < Desiru::Module
  signature 'RobustImageAnalysis', 'Image analysis with comprehensive error handling'
  
  input 'image_path', type: 'string'
  output 'result', type: 'dict'
  output 'error', type: 'string'
  output 'success', type: 'bool'

  def forward(image_path:)
    validate_input!(image_path)
    
    result = perform_analysis(image_path)
    
    {
      result: result,
      error: nil,
      success: true
    }
  rescue ValidationError => e
    {
      result: {},
      error: "Invalid input: #{e.message}",
      success: false
    }
  rescue ExternalServiceError => e
    Desiru.logger.error "External service failed: #{e.message}"
    {
      result: fallback_analysis(image_path),
      error: "Service degraded: #{e.message}",
      success: false
    }
  rescue StandardError => e
    Desiru.logger.error "Unexpected error in ImageModule: #{e.message}\n#{e.backtrace.join("\n")}"
    {
      result: {},
      error: "Analysis failed: #{e.message}",
      success: false
    }
  end

  private

  def validate_input!(path)
    raise ValidationError, "Path cannot be nil" if path.nil?
    raise ValidationError, "File does not exist: #{path}" unless File.exist?(path)
    raise ValidationError, "Not a valid image file" unless valid_image?(path)
  end

  def valid_image?(path)
    %w[.jpg .jpeg .png .gif .bmp].include?(File.extname(path).downcase)
  end

  def fallback_analysis(path)
    # Simple fallback when main analysis fails
    { basic_info: File.basename(path), size: File.size(path) }
  end
end

# Custom error classes
class ValidationError < StandardError; end
class ExternalServiceError < StandardError; end
```

### API-Level Error Handling

```ruby
# config/application.rb
require 'sinatra'
require 'desiru'
require 'json'

class ArtInstallationAPI < Sinatra::Base
  configure do
    set :show_exceptions, false  # Handle exceptions manually
    set :raise_errors, false
  end

  before do
    content_type :json
    
    # Request validation
    if request.content_length && request.content_length > 10_000_000  # 10MB limit
      halt 413, { error: "Request too large", max_size: "10MB" }.to_json
    end
  end

  # Global error handlers
  error JSON::ParserError do
    status 400
    { error: "Invalid JSON in request body" }.to_json
  end

  error ValidationError do |e|
    status 422
    { error: "Validation failed", details: e.message }.to_json
  end

  error ExternalServiceError do |e|
    status 503
    { error: "External service unavailable", details: e.message, retry_after: 30 }.to_json
  end

  error StandardError do |e|
    logger.error "Unhandled error: #{e.message}\n#{e.backtrace.join("\n")}"
    status 500
    { error: "Internal server error", request_id: request.env['REQUEST_ID'] }.to_json
  end

  # Timeout handling for long-running operations
  def with_timeout(seconds = 30)
    Timeout.timeout(seconds) do
      yield
    end
  rescue Timeout::Error
    halt 408, { error: "Request timeout", timeout: seconds }.to_json
  end
end
```

## Sinatra Implementation

### Basic Sinatra Setup with Desiru

```ruby
# app.rb
require 'sinatra'
require 'desiru'
require 'json'

# Configure Desiru
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenRouter.new(
    api_key: ENV['OPENROUTER_API_KEY'],
    model: 'anthropic/claude-3-haiku-20240307'
  )
  
  # Different models for different use cases
  config.conversation_model = Desiru::Models::OpenRouter.new(
    api_key: ENV['OPENROUTER_API_KEY'],
    model: 'openai/gpt-4-turbo-preview',
    temperature: 0.8
  )
  
  config.analysis_model = Desiru::Models::OpenRouter.new(
    api_key: ENV['OPENROUTER_API_KEY'],
    model: 'openai/gpt-4-vision-preview',
    temperature: 0.3
  )
end

class ArtInstallationAPI < Sinatra::Base
  configure do
    enable :logging
    set :port, ENV.fetch('PORT', 4567)
    set :bind, '0.0.0.0'  # Listen on all interfaces
  end

  before do
    content_type :json
    
    # Add CORS headers if needed
    headers 'Access-Control-Allow-Origin' => '*'
    headers 'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS'
    headers 'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
  end

  # Handle CORS preflight
  options '*' do
    200
  end

  # Health check
  get '/health' do
    {
      status: 'ok',
      timestamp: Time.now.iso8601,
      version: '1.0.0'
    }.to_json
  end
end
```

### Registering Desiru Modules as Endpoints

```ruby
# Load your custom modules
require_relative 'lib/modules/conversation_module'
require_relative 'lib/modules/image_analysis_module'

class ArtInstallationAPI < Sinatra::Base
  # Method 1: Manual endpoint registration
  post '/api/v1/conversation' do
    request_data = JSON.parse(request.body.read)
    
    conversation_module = ConversationModule.new
    result = conversation_module.call(
      message: request_data['message'],
      context: request_data['context'] || {},
      mood: request_data['mood'] || 'neutral'
    )
    
    result.to_json
  end

  # Method 2: Using Desiru's Sinatra integration
  def self.register_desiru_module(path, module_instance, description: nil)
    post path do
      request_data = JSON.parse(request.body.read)
      
      begin
        result = module_instance.call(**request_data.transform_keys(&:to_sym))
        {
          success: true,
          data: result,
          timestamp: Time.now.iso8601
        }.to_json
      rescue ArgumentError => e
        status 422
        {
          success: false,
          error: "Invalid parameters: #{e.message}",
          expected_params: module_instance.signature.inputs.keys
        }.to_json
      end
    end
  end

  # Register modules
  register_desiru_module '/api/v1/analyze_image', ImageAnalysisModule.new,
    description: 'Analyze uploaded images for artistic content'
  
  register_desiru_module '/api/v1/conversation', ConversationModule.new,
    description: 'Engage in artistic conversation'
end
```

### File Upload Handling

```ruby
# File upload endpoint
post '/api/v1/upload_image' do
  unless params[:image] && params[:image][:tempfile]
    halt 400, { error: "No image file provided" }.to_json
  end

  uploaded_file = params[:image][:tempfile]
  filename = params[:image][:filename]
  
  # Validate file type
  unless valid_image_type?(filename)
    halt 422, { error: "Invalid file type. Supported: jpg, png, gif" }.to_json
  end

  # Save uploaded file
  upload_dir = File.join(settings.root, 'uploads')
  FileUtils.mkdir_p(upload_dir)
  
  file_path = File.join(upload_dir, "#{SecureRandom.uuid}_#{filename}")
  File.open(file_path, 'wb') { |f| f.write(uploaded_file.read) }

  # Process with Desiru module
  analysis_module = ImageAnalysisModule.new
  result = analysis_module.call(
    image_path: file_path,
    analysis_depth: params[:depth] || 'detailed'
  )

  # Clean up uploaded file after processing
  File.delete(file_path) if File.exist?(file_path)

  {
    success: true,
    filename: filename,
    analysis: result
  }.to_json
end

private

def valid_image_type?(filename)
  return false unless filename
  ext = File.extname(filename).downcase
  %w[.jpg .jpeg .png .gif].include?(ext)
end
```

### Streaming Responses

```ruby
# Server-Sent Events for streaming
get '/api/v1/conversation/stream' do
  content_type 'text/event-stream'
  cache_control :no_cache
  
  stream :keep_open do |out|
    conversation_module = ConversationModule.new
    
    # This would need to be implemented in your module to support streaming
    conversation_module.call_streaming(
      message: params[:message],
      context: JSON.parse(params[:context] || '{}')
    ) do |chunk|
      out << "data: #{chunk.to_json}\n\n"
    end
    
    out << "data: [DONE]\n\n"
    out.close
  end
end

# WebSocket support (requires additional gems)
# gem 'sinatra-websocket'
get '/api/v1/websocket' do
  if !request.websocket?
    halt 400, { error: "WebSocket connection required" }.to_json
  end

  request.websocket do |ws|
    ws.onopen do
      ws.send({ type: 'connected', timestamp: Time.now }.to_json)
    end

    ws.onmessage do |msg|
      data = JSON.parse(msg)
      
      case data['type']
      when 'conversation'
        result = ConversationModule.new.call(
          message: data['message'],
          context: data['context'] || {}
        )
        ws.send({ type: 'response', data: result }.to_json)
      when 'ping'
        ws.send({ type: 'pong', timestamp: Time.now }.to_json)
      end
    end

    ws.onclose do
      puts "WebSocket connection closed"
    end
  end
end
```


## Tool and Function Calling

### Defining Tools

Tools in Desiru follow a simple pattern - they're Ruby classes with class methods for `name`, `description`, and `call`.

```ruby
# lib/tools/image_generation_tool.rb
class ImageGenerationTool
  def self.name
    "generate_image"
  end
  
  def self.description
    "Generate artistic images based on text descriptions. Args: prompt (string), style (string), size (string)"
  end
  
  def self.call(prompt:, style: 'artistic', size: '1024x1024')
    # Input validation
    raise ArgumentError, "Prompt cannot be empty" if prompt.nil? || prompt.strip.empty?
    
    valid_styles = %w[artistic photorealistic abstract minimalist]
    unless valid_styles.include?(style)
      raise ArgumentError, "Invalid style. Must be one of: #{valid_styles.join(', ')}"
    end

    valid_sizes = %w[512x512 1024x1024 1024x1792 1792x1024]
    unless valid_sizes.include?(size)
      raise ArgumentError, "Invalid size. Must be one of: #{valid_sizes.join(', ')}"
    end

    # Call external image generation service
    begin
      result = call_image_service(prompt, style, size)
      
      {
        success: true,
        image_url: result[:url],
        prompt_used: prompt,
        style: style,
        size: size,
        generation_time: result[:generation_time]
      }
    rescue ExternalServiceError => e
      {
        success: false,
        error: "Image generation failed: #{e.message}",
        fallback_suggestion: "Try a simpler prompt or different style"
      }
    end
  end

  private

  def self.call_image_service(prompt, style, size)
    # Implementation would call actual image generation API
    # This is a mock implementation
    {
      url: "https://example.com/generated/#{SecureRandom.uuid}.png",
      generation_time: rand(5..15)
    }
  end
end
```

### Complex Tools with State

```ruby
# lib/tools/collaborative_drawing_tool.rb
class CollaborativeDrawingTool
  def self.name
    "collaborative_draw"
  end
  
  def self.description
    "Add elements to a collaborative drawing canvas. Args: session_id (string), action (string), element (dict), position (dict)"
  end
  
  def self.call(session_id:, action:, element: {}, position: {})
    canvas = CanvasManager.get_or_create(session_id)
    
    case action
    when 'add_element'
      validate_element!(element)
      validate_position!(position)
      
      canvas.add_element(
        type: element['type'],
        properties: element['properties'],
        x: position['x'],
        y: position['y']
      )
      
    when 'modify_element'
      element_id = element['id']
      raise ArgumentError, "Element ID required for modification" unless element_id
      
      canvas.modify_element(element_id, element['properties'])
      
    when 'get_canvas'
      return canvas.to_hash
      
    when 'clear_canvas'
      canvas.clear
      
    else
      raise ArgumentError, "Invalid action: #{action}. Valid actions: add_element, modify_element, get_canvas, clear_canvas"
    end

    {
      success: true,
      canvas_state: canvas.to_hash,
      total_elements: canvas.element_count,
      last_modified: Time.now.iso8601
    }
  end

  private

  def self.validate_element!(element)
    required_keys = %w[type properties]
    missing_keys = required_keys - element.keys
    raise ArgumentError, "Missing required element keys: #{missing_keys.join(', ')}" unless missing_keys.empty?
    
    valid_types = %w[circle rectangle line text brush_stroke]
    unless valid_types.include?(element['type'])
      raise ArgumentError, "Invalid element type: #{element['type']}. Valid types: #{valid_types.join(', ')}"
    end
  end

  def self.validate_position!(position)
    %w[x y].each do |coord|
      unless position[coord].is_a?(Numeric)
        raise ArgumentError, "Position #{coord} must be a number"
      end
    end
  end
end

# Canvas manager for maintaining state
class CanvasManager
  @@canvases = {}

  def self.get_or_create(session_id)
    @@canvases[session_id] ||= Canvas.new(session_id)
  end

  def self.cleanup_old_canvases(max_age_hours = 24)
    cutoff = Time.now - (max_age_hours * 3600)
    @@canvases.reject! { |_, canvas| canvas.created_at < cutoff }
  end
end

class Canvas
  attr_reader :session_id, :created_at, :elements

  def initialize(session_id)
    @session_id = session_id
    @created_at = Time.now
    @elements = []
    @element_counter = 0
  end

  def add_element(type:, properties:, x:, y:)
    @element_counter += 1
    element = {
      id: @element_counter,
      type: type,
      properties: properties,
      position: { x: x, y: y },
      created_at: Time.now.iso8601
    }
    @elements << element
    element
  end

  def modify_element(element_id, new_properties)
    element = @elements.find { |e| e[:id] == element_id }
    raise ArgumentError, "Element not found: #{element_id}" unless element
    
    element[:properties].merge!(new_properties)
    element[:modified_at] = Time.now.iso8601
    element
  end

  def clear
    @elements.clear
  end

  def element_count
    @elements.size
  end

  def to_hash
    {
      session_id: @session_id,
      created_at: @created_at.iso8601,
      elements: @elements,
      element_count: element_count
    }
  end
end
```

### Using Tools with ReAct Pattern

```ruby
# lib/modules/artistic_agent.rb
class ArtisticAgent
  def initialize
    @tools = [
      ImageGenerationTool,
      CollaborativeDrawingTool,
      ColorPaletteTool,
      MoodAnalysisTool
    ]
    
    @agent = Desiru::Modules::ReAct.new(
      'visitor_input: string, context: dict, session_id: string -> response: string, actions_taken: list[dict], suggestions: list[string]',
      tools: @tools,
      max_iterations: 6
    )
  end

  def process_request(visitor_input:, context: {}, session_id: SecureRandom.uuid)
    result = @agent.call(
      visitor_input: visitor_input,
      context: context,
      session_id: session_id
    )
    
    # Log tool usage for analytics
    log_tool_usage(result.actions_taken, session_id)
    
    result
  end

  private

  def log_tool_usage(actions, session_id)
    actions.each do |action|
      Rails.logger.info "Tool used: #{action[:tool]} for session #{session_id}"
      # Could also send to analytics service
    end
  end
end

# Usage in Sinatra endpoint
post '/api/v1/artistic_agent' do
  request_data = JSON.parse(request.body.read)
  
  agent = ArtisticAgent.new
  result = agent.process_request(
    visitor_input: request_data['message'],
    context: request_data['context'] || {},
    session_id: request_data['session_id'] || SecureRandom.uuid
  )

  {
    response: result.response,
    actions_taken: result.actions_taken,
    suggestions: result.suggestions,
    session_id: request_data['session_id']
  }.to_json
end
```

## Background Jobs and Scheduling

### Basic Background Job Setup

```ruby
# config/application.rb
require 'sidekiq'
require 'redis'

# Configure Sidekiq
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379') }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379') }
end

# Configure Desiru for background processing
Desiru.configure do |config|
  config.redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379')
  config.default_model = Desiru::Models::OpenRouter.new(
    api_key: ENV['OPENROUTER_API_KEY'],
    model: 'anthropic/claude-3-haiku-20240307'
  )
end
```

### Creating Background Jobs

```ruby
# lib/jobs/artistic_evolution_job.rb
class ArtisticEvolutionJob < Desiru::Jobs::Base
  include Desiru::Jobs::Schedulable

  def perform(job_id = nil, analysis_period: '24h', evolution_type: 'gradual')
    logger.info "Starting artistic evolution job #{job_id} for period #{analysis_period}"
    
    # Gather interaction data
    interaction_data = gather_interaction_data(analysis_period)
    
    # Analyze patterns and trends
    insights = analyze_artistic_patterns(interaction_data)
    
    # Generate evolution recommendations
    evolution_plan = generate_evolution_plan(insights, evolution_type)
    
    # Apply changes gradually
    apply_evolution_changes(evolution_plan)
    
    # Store results
    results = {
      job_id: job_id,
      analysis_period: analysis_period,
      evolution_type: evolution_type,
      interactions_analyzed: interaction_data[:count],
      insights: insights,
      changes_applied: evolution_plan[:changes],
      timestamp: Time.now.iso8601,
      next_evolution_due: Time.now + parse_period(analysis_period)
    }
    
    store_result(job_id, results)
    
    # Schedule next evolution
    schedule_next_evolution(analysis_period, evolution_type)
    
    logger.info "Completed artistic evolution job #{job_id}"
    results
  end

  private

  def gather_interaction_data(period)
    # Query database for interaction data within the period
    cutoff_time = Time.now - parse_period(period)
    
    interactions = InteractionLog.where('created_at > ?', cutoff_time)
    
    {
      count: interactions.count,
      conversation_count: interactions.where(type: 'conversation').count,
      image_interactions: interactions.where(type: 'image').count,
      average_session_length: interactions.average(:session_duration),
      popular_themes: interactions.group(:theme).count,
      emotional_trends: interactions.group(:detected_emotion).count
    }
  end

  def analyze_artistic_patterns(data)
    # Use Desiru module to analyze patterns
    analysis_module = Desiru::Modules::ChainOfThought.new(
      "interaction_data: dict, current_themes: list[string] -> insights: dict, recommendations: list[string], confidence: float"
    )
    
    current_themes = ArtisticTheme.current.pluck(:name)
    
    analysis_module.call(
      interaction_data: data,
      current_themes: current_themes
    )
  end

  def generate_evolution_plan(insights, evolution_type)
    case evolution_type
    when 'gradual'
      generate_gradual_evolution(insights)
    when 'dramatic'
      generate_dramatic_evolution(insights)
    when 'seasonal'
      generate_seasonal_evolution(insights)
    else
      raise ArgumentError, "Unknown evolution type: #{evolution_type}"
    end
  end

  def apply_evolution_changes(plan)
    plan[:changes].each do |change|
      case change[:type]
      when 'theme_adjustment'
        adjust_artistic_theme(change[:theme], change[:adjustment])
      when 'color_palette_shift'
        shift_color_palette(change[:from_palette], change[:to_palette], change[:intensity])
      when 'interaction_style_change'
        update_interaction_style(change[:style_params])
      end
    end
  end

  def schedule_next_evolution(period, evolution_type)
    # Schedule the next evolution job
    self.class.perform_in(parse_period(period), nil, period, evolution_type)
  end

  def parse_period(period_string)
    case period_string
    when /(\d+)h/
      $1.to_i.hours
    when /(\d+)d/
      $1.to_i.days
    when /(\d+)w/
      $1.to_i.weeks
    else
      24.hours  # default
    end
  end
end
```

### Scheduling Jobs

```ruby
# Using Desiru's built-in scheduler
class ArtisticMaintenanceJob < Desiru::Jobs::Base
  include Desiru::Jobs::Schedulable

  def perform(job_id = nil, maintenance_type: 'routine')
    case maintenance_type
    when 'routine'
      perform_routine_maintenance
    when 'deep_clean'
      perform_deep_maintenance
    when 'analytics'
      generate_analytics_report
    end
  end

  private

  def perform_routine_maintenance
    # Clean up old sessions
    CanvasManager.cleanup_old_canvases(24)
    
    # Clear expired cache entries
    Rails.cache.cleanup
    
    # Update system metrics
    SystemMetrics.update_current_stats
  end
end

# Schedule jobs in initializer or application startup
# config/initializers/scheduled_jobs.rb

# Daily artistic evolution
ArtisticEvolutionJob.schedule(
  name: 'daily_evolution',
  cron: 'every 24 hours',
  args: ['24h', 'gradual']
)

# Weekly deep analysis
ArtisticEvolutionJob.schedule(
  name: 'weekly_analysis', 
  cron: '0 2 * * 0',  # Sunday at 2 AM
  args: ['7d', 'dramatic']
)

# Hourly maintenance
ArtisticMaintenanceJob.schedule(
  name: 'routine_maintenance',
  cron: 'every 1 hour',
  args: ['routine']
)

# Custom cron expressions
ArtisticMaintenanceJob.schedule(
  name: 'deep_maintenance',
  cron: '0 3 * * *',  # Daily at 3 AM
  args: ['deep_clean']
)
```

### Async Module Calls

```ruby
# Using async calls for long-running operations
class AsyncImageProcessor
  def self.process_image_async(image_path, processing_options = {})
    # Create processing module
    processor = ComplexImageProcessingModule.new
    
    # Call asynchronously
    job_result = processor.call_async(
      image_path: image_path,
      options: processing_options
    )
    
    {
      job_id: job_result.job_id,
      status: 'processing',
      estimated_completion: Time.now + 30.seconds
    }
  end

  def self.get_processing_status(job_id)
    # Check job status
    job_result = Desiru::Jobs::Result.find(job_id)
    
    if job_result.ready?
      {
        status: 'completed',
        result: job_result.wait,
        completed_at: job_result.completed_at
      }
    else
      {
        status: job_result.status,
        progress: job_result.progress,
        estimated_completion: job_result.estimated_completion
      }
    end
  end
end

# Sinatra endpoints for async processing
post '/api/v1/process_image_async' do
  uploaded_file = params[:image][:tempfile]
  processing_options = JSON.parse(params[:options] || '{}')
  
  # Save uploaded file temporarily
  temp_path = save_temp_file(uploaded_file, params[:image][:filename])
  
  # Start async processing
  result = AsyncImageProcessor.process_image_async(temp_path, processing_options)
  
  result.to_json
end

get '/api/v1/processing_status/:job_id' do
  job_id = params[:job_id]
  
  result = AsyncImageProcessor.get_processing_status(job_id)
  result.to_json
end
```


## Testing

### Testing Desiru Modules

```ruby
# spec/spec_helper.rb
require 'rspec'
require 'webmock/rspec'
require 'desiru'

RSpec.configure do |config|
  config.before(:suite) do
    # Configure Desiru for testing
    Desiru.configure do |config|
      config.default_model = MockModel.new  # Use mock model for tests
    end
  end

  config.before(:each) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end

# Mock model for testing
class MockModel
  def complete(prompt, **options)
    # Return predictable responses for testing
    case prompt
    when /analyze.*image/i
      { content: "analysis: This is a test image analysis response" }
    when /generate.*image/i
      { content: "result: Mock image generated successfully" }
    else
      { content: "response: Mock response for testing" }
    end
  end

  def to_config
    { type: 'mock', model: 'test-model' }
  end
end
```

### Module Testing

```ruby
# spec/modules/image_analysis_module_spec.rb
require 'spec_helper'
require_relative '../../lib/modules/image_analysis_module'

RSpec.describe ImageAnalysisModule do
  let(:module_instance) { described_class.new }
  let(:test_image_path) { File.join(__dir__, '../fixtures/test_image.jpg') }

  before do
    # Create test image file
    FileUtils.mkdir_p(File.dirname(test_image_path))
    File.write(test_image_path, 'fake image data') unless File.exist?(test_image_path)
  end

  describe '#forward' do
    context 'with valid inputs' do
      it 'returns analysis results' do
        result = module_instance.forward(
          image_path: test_image_path,
          analysis_depth: 'basic'
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key(:composition)
        expect(result).to have_key(:colors)
        expect(result).to have_key(:style)
        expect(result).to have_key(:confidence)
        expect(result[:confidence]).to be_a(Float)
        expect(result[:confidence]).to be_between(0.0, 1.0)
      end

      it 'handles different analysis depths' do
        basic_result = module_instance.forward(
          image_path: test_image_path,
          analysis_depth: 'basic'
        )
        
        detailed_result = module_instance.forward(
          image_path: test_image_path,
          analysis_depth: 'detailed'
        )

        expect(detailed_result[:composition].keys.size).to be > basic_result[:composition].keys.size
      end
    end

    context 'with invalid inputs' do
      it 'raises error for non-existent file' do
        expect {
          module_instance.forward(image_path: '/nonexistent/file.jpg')
        }.to raise_error(ValidationError, /File does not exist/)
      end

      it 'raises error for invalid file type' do
        text_file = File.join(__dir__, '../fixtures/test.txt')
        File.write(text_file, 'not an image')

        expect {
          module_instance.forward(image_path: text_file)
        }.to raise_error(ValidationError, /Not a valid image file/)
      end
    end
  end
end
```

### Tool Testing

```ruby
# spec/tools/image_generation_tool_spec.rb
require 'spec_helper'
require_relative '../../lib/tools/image_generation_tool'

RSpec.describe ImageGenerationTool do
  describe '.call' do
    context 'with valid parameters' do
      before do
        # Mock external service call
        allow(described_class).to receive(:call_image_service)
          .and_return({
            url: 'https://example.com/test.png',
            generation_time: 10
          })
      end

      it 'generates image successfully' do
        result = described_class.call(
          prompt: 'A beautiful sunset',
          style: 'artistic',
          size: '1024x1024'
        )

        expect(result[:success]).to be true
        expect(result[:image_url]).to eq('https://example.com/test.png')
        expect(result[:prompt_used]).to eq('A beautiful sunset')
      end

      it 'uses default parameters' do
        result = described_class.call(prompt: 'Test prompt')

        expect(result[:style]).to eq('artistic')
        expect(result[:size]).to eq('1024x1024')
      end
    end

    context 'with invalid parameters' do
      it 'raises error for empty prompt' do
        expect {
          described_class.call(prompt: '')
        }.to raise_error(ArgumentError, /Prompt cannot be empty/)
      end

      it 'raises error for invalid style' do
        expect {
          described_class.call(prompt: 'Test', style: 'invalid_style')
        }.to raise_error(ArgumentError, /Invalid style/)
      end
    end

    context 'when external service fails' do
      before do
        allow(described_class).to receive(:call_image_service)
          .and_raise(ExternalServiceError.new('Service unavailable'))
      end

      it 'returns error response' do
        result = described_class.call(prompt: 'Test prompt')

        expect(result[:success]).to be false
        expect(result[:error]).to include('Image generation failed')
        expect(result[:fallback_suggestion]).to be_present
      end
    end
  end
end
```

### API Integration Testing

```ruby
# spec/integration/api_spec.rb
require 'spec_helper'
require 'rack/test'
require_relative '../../app'

RSpec.describe 'Art Installation API' do
  include Rack::Test::Methods

  def app
    ArtInstallationAPI
  end

  describe 'GET /health' do
    it 'returns health status' do
      get '/health'

      expect(last_response.status).to eq(200)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['status']).to eq('ok')
      expect(response_data['timestamp']).to be_present
    end
  end

  describe 'POST /api/v1/conversation' do
    let(:request_data) do
      {
        message: 'Hello, I want to create some art',
        context: { mood: 'creative' },
        mood: 'excited'
      }
    end

    it 'processes conversation request' do
      post '/api/v1/conversation', request_data.to_json, 
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true
      expect(response_data['data']).to have_key('response')
    end

    it 'handles invalid JSON' do
      post '/api/v1/conversation', 'invalid json',
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['error']).to include('Invalid JSON')
    end
  end

  describe 'POST /api/v1/upload_image' do
    let(:test_image) do
      Rack::Test::UploadedFile.new(
        File.join(__dir__, '../fixtures/test_image.jpg'),
        'image/jpeg'
      )
    end

    it 'processes uploaded image' do
      post '/api/v1/upload_image', { image: test_image, depth: 'basic' }

      expect(last_response.status).to eq(200)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true
      expect(response_data['analysis']).to be_present
    end

    it 'rejects invalid file types' do
      text_file = Rack::Test::UploadedFile.new(
        StringIO.new('not an image'),
        'text/plain',
        original_filename: 'test.txt'
      )

      post '/api/v1/upload_image', { image: text_file }

      expect(last_response.status).to eq(422)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['error']).to include('Invalid file type')
    end
  end
end
```

### Background Job Testing

```ruby
# spec/jobs/artistic_evolution_job_spec.rb
require 'spec_helper'
require 'sidekiq/testing'
require_relative '../../lib/jobs/artistic_evolution_job'

RSpec.describe ArtisticEvolutionJob do
  before do
    Sidekiq::Testing.fake!  # Use fake mode for testing
  end

  after do
    Sidekiq::Worker.clear_all
  end

  describe '#perform' do
    let(:job_id) { SecureRandom.uuid }

    before do
      # Mock database interactions
      allow(InteractionLog).to receive(:where).and_return(double(
        count: 100,
        average: 300,
        group: double(count: { 'art' => 50, 'music' => 30 })
      ))
    end

    it 'completes successfully' do
      job = described_class.new
      result = job.perform(job_id, '24h', 'gradual')

      expect(result[:job_id]).to eq(job_id)
      expect(result[:analysis_period]).to eq('24h')
      expect(result[:evolution_type]).to eq('gradual')
      expect(result[:interactions_analyzed]).to eq(100)
    end

    it 'schedules next evolution' do
      expect {
        described_class.new.perform(job_id, '24h', 'gradual')
      }.to change(described_class.jobs, :size).by(1)
    end
  end

  describe 'scheduling' do
    it 'can be scheduled with cron expression' do
      expect {
        described_class.schedule(
          name: 'test_evolution',
          cron: 'every 1 hour',
          args: ['1h', 'test']
        )
      }.not_to raise_error
    end
  end
end
```

## OpenRouter Configuration

### Basic OpenRouter Setup

```ruby
# config/openrouter.rb
Desiru.configure do |config|
  # Basic configuration
  config.default_model = Desiru::Models::OpenRouter.new(
    api_key: ENV['OPENROUTER_API_KEY'],
    model: 'anthropic/claude-3-haiku-20240307',
    base_url: 'https://openrouter.ai/api/v1'
  )
end
```

### Multiple Model Configuration

```ruby
# config/models.rb
class ModelConfig
  def self.configure_models
    Desiru.configure do |config|
      # Fast model for quick responses
      config.conversation_model = Desiru::Models::OpenRouter.new(
        api_key: ENV['OPENROUTER_API_KEY'],
        model: 'openai/gpt-3.5-turbo',
        temperature: 0.8,
        max_tokens: 500,
        timeout: 10
      )

      # Powerful model for complex analysis
      config.analysis_model = Desiru::Models::OpenRouter.new(
        api_key: ENV['OPENROUTER_API_KEY'],
        model: 'anthropic/claude-3-opus-20240229',
        temperature: 0.3,
        max_tokens: 2000,
        timeout: 30
      )

      # Creative model for artistic tasks
      config.creative_model = Desiru::Models::OpenRouter.new(
        api_key: ENV['OPENROUTER_API_KEY'],
        model: 'openai/gpt-4-turbo-preview',
        temperature: 0.9,
        max_tokens: 1500,
        timeout: 20
      )

      # Vision model for image analysis
      config.vision_model = Desiru::Models::OpenRouter.new(
        api_key: ENV['OPENROUTER_API_KEY'],
        model: 'openai/gpt-4-vision-preview',
        temperature: 0.4,
        max_tokens: 1000
      )
    end
  end
end

# Call in application initialization
ModelConfig.configure_models
```

### Dynamic Model Selection

```ruby
# lib/services/model_selector.rb
class ModelSelector
  MODEL_PREFERENCES = {
    conversation: %w[
      openai/gpt-4-turbo-preview
      anthropic/claude-3-haiku-20240307
      openai/gpt-3.5-turbo
    ],
    analysis: %w[
      anthropic/claude-3-opus-20240229
      openai/gpt-4-turbo-preview
      anthropic/claude-3-sonnet-20240229
    ],
    creative: %w[
      openai/gpt-4-turbo-preview
      anthropic/claude-3-opus-20240229
      openai/gpt-3.5-turbo
    ],
    vision: %w[
      openai/gpt-4-vision-preview
      anthropic/claude-3-opus-20240229
    ]
  }.freeze

  def self.get_model_for_task(task_type, fallback_level: 0)
    models = MODEL_PREFERENCES[task_type.to_sym]
    raise ArgumentError, "Unknown task type: #{task_type}" unless models

    selected_model = models[fallback_level] || models.last
    
    Desiru::Models::OpenRouter.new(
      api_key: ENV['OPENROUTER_API_KEY'],
      model: selected_model,
      **model_params_for_task(task_type)
    )
  end

  def self.model_params_for_task(task_type)
    case task_type.to_sym
    when :conversation
      { temperature: 0.8, max_tokens: 500 }
    when :analysis
      { temperature: 0.3, max_tokens: 2000 }
    when :creative
      { temperature: 0.9, max_tokens: 1500 }
    when :vision
      { temperature: 0.4, max_tokens: 1000 }
    else
      { temperature: 0.7, max_tokens: 1000 }
    end
  end

  def self.with_fallback(task_type, max_retries: 2)
    retries = 0
    
    begin
      model = get_model_for_task(task_type, retries)
      yield model
    rescue OpenRouter::RateLimitError, OpenRouter::ServiceUnavailableError => e
      retries += 1
      if retries <= max_retries
        Rails.logger.warn "Model failed (#{e.class}), trying fallback #{retries}"
        retry
      else
        raise e
      end
    end
  end
end

# Usage in modules
class ConversationModule < Desiru::Module
  def forward(message:, context: {})
    ModelSelector.with_fallback(:conversation) do |model|
      # Use the selected model for this specific call
      temp_config = Desiru.configuration.dup
      temp_config.default_model = model
      
      Desiru.with_config(temp_config) do
        # Your module logic here
        super
      end
    end
  end
end
```

### Cost Monitoring and Optimization

```ruby
# lib/services/cost_monitor.rb
class CostMonitor
  COST_PER_1K_TOKENS = {
    'openai/gpt-4-turbo-preview' => { input: 0.01, output: 0.03 },
    'openai/gpt-3.5-turbo' => { input: 0.0015, output: 0.002 },
    'anthropic/claude-3-opus-20240229' => { input: 0.015, output: 0.075 },
    'anthropic/claude-3-haiku-20240307' => { input: 0.00025, output: 0.00125 }
  }.freeze

  def self.estimate_cost(model, input_tokens, output_tokens)
    rates = COST_PER_1K_TOKENS[model]
    return 0 unless rates

    input_cost = (input_tokens / 1000.0) * rates[:input]
    output_cost = (output_tokens / 1000.0) * rates[:output]
    
    input_cost + output_cost
  end

  def self.log_usage(model, input_tokens, output_tokens, task_type)
    cost = estimate_cost(model, input_tokens, output_tokens)
    
    Rails.logger.info "OpenRouter usage: #{model}, #{input_tokens}+#{output_tokens} tokens, $#{cost.round(4)}, task: #{task_type}"
    
    # Store in database for analytics
    ModelUsage.create!(
      model: model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      estimated_cost: cost,
      task_type: task_type,
      timestamp: Time.now
    )
  end
end
```

## Deployment

### Production Configuration

```ruby
# config/production.rb
require 'desiru'

# Production Desiru configuration
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenRouter.new(
    api_key: ENV.fetch('OPENROUTER_API_KEY'),
    model: ENV.fetch('DEFAULT_MODEL', 'anthropic/claude-3-haiku-20240307'),
    timeout: 30,
    max_retries: 3
  )
  
  config.redis_url = ENV.fetch('REDIS_URL')
  config.log_level = :info
  config.enable_caching = true
  config.cache_ttl = 3600  # 1 hour
end

# Sidekiq configuration for production
Sidekiq.configure_server do |config|
  config.redis = { 
    url: ENV.fetch('REDIS_URL'),
    network_timeout: 5,
    pool_timeout: 5
  }
  
  config.concurrency = ENV.fetch('SIDEKIQ_CONCURRENCY', 10).to_i
end

Sidekiq.configure_client do |config|
  config.redis = { 
    url: ENV.fetch('REDIS_URL'),
    network_timeout: 5,
    pool_timeout: 5
  }
end
```

### Docker Setup

```dockerfile
# Dockerfile
FROM ruby:3.1-alpine

RUN apk add --no-cache \
  build-base \
  postgresql-dev \
  redis \
  imagemagick \
  imagemagick-dev

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --deployment --without development test

COPY . .

EXPOSE 4567

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

```yaml
# docker-compose.yml
version: '3.8'

services:
  app:
    build: .
    ports:
      - "4567:4567"
    environment:
      - REDIS_URL=redis://redis:6379
      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
      - RACK_ENV=production
    depends_on:
      - redis
    volumes:
      - ./uploads:/app/uploads

  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data

  sidekiq:
    build: .
    command: bundle exec sidekiq
    environment:
      - REDIS_URL=redis://redis:6379
      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
    depends_on:
      - redis
    volumes:
      - ./uploads:/app/uploads

volumes:
  redis_data:
```

### Monitoring and Health Checks

```ruby
# lib/health_checker.rb
class HealthChecker
  def self.check_all
    {
      redis: check_redis,
      openrouter: check_openrouter,
      sidekiq: check_sidekiq,
      disk_space: check_disk_space,
      memory: check_memory
    }
  end

  def self.check_redis
    Redis.new(url: ENV['REDIS_URL']).ping == 'PONG'
  rescue => e
    { status: 'error', message: e.message }
  end

  def self.check_openrouter
    # Simple test call to OpenRouter
    model = Desiru::Models::OpenRouter.new(
      api_key: ENV['OPENROUTER_API_KEY'],
      model: 'openai/gpt-3.5-turbo'
    )
    
    response = model.complete('test', max_tokens: 1)
    response[:content].present?
  rescue => e
    { status: 'error', message: e.message }
  end

  def self.check_sidekiq
    Sidekiq::Stats.new.processed > 0
  rescue => e
    { status: 'error', message: e.message }
  end

  def self.check_disk_space
    stat = Sys::Filesystem.stat('/')
    free_gb = stat.bytes_free / (1024**3)
    
    if free_gb < 1
      { status: 'warning', free_gb: free_gb }
    else
      { status: 'ok', free_gb: free_gb }
    end
  end

  def self.check_memory
    # Simple memory check
    memory_info = `free -m`.lines[1].split
    used_mb = memory_info[2].to_i
    total_mb = memory_info[1].to_i
    usage_percent = (used_mb.to_f / total_mb * 100).round(1)
    
    {
      status: usage_percent > 90 ? 'warning' : 'ok',
      usage_percent: usage_percent,
      used_mb: used_mb,
      total_mb: total_mb
    }
  end
end

# Add to Sinatra app
get '/health/detailed' do
  health_status = HealthChecker.check_all
  overall_status = health_status.values.all? { |v| v != false && v[:status] != 'error' }
  
  status overall_status ? 200 : 503
  
  {
    overall: overall_status ? 'healthy' : 'unhealthy',
    timestamp: Time.now.iso8601,
    checks: health_status
  }.to_json
end
```

This developer guide provides practical, code-focused documentation for implementing an interactive art piece with the Desiru framework. It covers installation, type system usage, error handling, API implementation with Sinatra, tool/function calling, background jobs, testing strategies, OpenRouter configuration, and production deployment considerations.

