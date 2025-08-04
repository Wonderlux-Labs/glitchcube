# Comprehensive Conversation Flow Architecture

**Author:** Manus AI  
**Date:** August 3, 2025  
**Purpose:** Multi-turn conversation system between Desiru app and Home Assistant voice assistant  

## Overview

This architecture defines a complete conversation flow system that seamlessly handles multi-turn dialogue between visitors and the interactive art installation. The system coordinates between the Desiru application (providing AI intelligence and artistic responses) and Home Assistant (managing voice interface and physical interactions) to create natural, continuous conversations that can span multiple exchanges while maintaining context and artistic coherence.

## Flow Architecture Diagram

```
[Conversation Trigger] 
    ↓ (reason: user_initiated, motion_detected, scheduled, etc.)
[Desiru: Start Conversation Endpoint]
    ↓ (create session, initialize context)
[Desiru: Generate Initial Response + Tools]
    ↓ (response + continue_listening flag)
[HASS: Speak Response]
    ↓ (TTS or MP3 playback)
[HASS: Auto-reactivate Voice Assistant] ← (if continue_listening = true)
    ↓ (listening for next input)
[HASS: STT → New Input]
    ↓ (send to Desiru with session_id)
[Desiru: Continue Conversation]
    ↓ (process input, call tools, generate response)
[Decision Point: Continue or End?]
    ↓ (based on AI decision + conversation analysis)
[If Continue: Loop back to HASS Speak]
[If End: Store Conversation Log + Cleanup]
```

## Desiru Application Side

### Conversation Session Management

```ruby
# lib/models/conversation_session.rb
class ConversationSession
  include ActiveModel::Model
  include ActiveModel::Attributes
  
  attribute :session_id, :string
  attribute :initiated_by, :string  # 'user_initiated', 'motion_detected', 'scheduled', etc.
  attribute :started_at, :datetime
  attribute :last_activity_at, :datetime
  attribute :status, :string  # 'active', 'paused', 'ended'
  attribute :context, :hash, default: {}
  attribute :conversation_log, :array, default: []
  attribute :tool_calls, :array, default: []
  attribute :visitor_profile, :hash, default: {}
  
  def initialize(attributes = {})
    super
    self.session_id ||= SecureRandom.uuid
    self.started_at ||= Time.current
    self.last_activity_at ||= Time.current
    self.status ||= 'active'
  end
  
  def add_exchange(role:, content:, metadata: {})
    exchange = {
      role: role,  # 'visitor', 'assistant', 'system', 'tool'
      content: content,
      timestamp: Time.current.iso8601,
      metadata: metadata
    }
    
    self.conversation_log << exchange
    self.last_activity_at = Time.current
    exchange
  end
  
  def add_tool_call(tool_name:, parameters:, result:, execution_time: nil)
    tool_call = {
      tool_name: tool_name,
      parameters: parameters,
      result: result,
      timestamp: Time.current.iso8601,
      execution_time: execution_time
    }
    
    self.tool_calls << tool_call
    tool_call
  end
  
  def should_continue_conversation?
    return false if status != 'active'
    return false if conversation_log.empty?
    return false if Time.current - last_activity_at > 5.minutes
    
    # AI-based decision logic would go here
    # For now, simple heuristics
    recent_exchanges = conversation_log.last(4)
    
    # Continue if visitor seems engaged
    return true if recent_exchanges.any? { |ex| ex[:role] == 'visitor' && ex[:content].length > 10 }
    
    # Continue if we asked a question
    last_assistant_message = conversation_log.reverse.find { |ex| ex[:role] == 'assistant' }
    return true if last_assistant_message&.dig(:content)&.include?('?')
    
    # Default to ending after reasonable exchange
    conversation_log.count { |ex| ex[:role] == 'visitor' } < 8
  end
  
  def conversation_summary
    {
      session_id: session_id,
      duration: Time.current - started_at,
      exchange_count: conversation_log.count { |ex| ex[:role] == 'visitor' },
      tool_calls_count: tool_calls.length,
      initiated_by: initiated_by,
      final_status: status,
      key_topics: extract_key_topics,
      visitor_sentiment: analyze_sentiment
    }
  end
  
  private
  
  def extract_key_topics
    # Simple keyword extraction - could be enhanced with NLP
    all_text = conversation_log
      .select { |ex| ex[:role] == 'visitor' }
      .map { |ex| ex[:content] }
      .join(' ')
      
    # Basic topic extraction
    topics = []
    topics << 'art' if all_text.match?(/\b(art|paint|draw|create|artistic)\b/i)
    topics << 'music' if all_text.match?(/\b(music|song|sound|audio)\b/i)
    topics << 'color' if all_text.match?(/\b(color|red|blue|green|yellow|purple)\b/i)
    topics << 'emotion' if all_text.match?(/\b(feel|emotion|happy|sad|excited|calm)\b/i)
    topics
  end
  
  def analyze_sentiment
    # Simple sentiment analysis - could be enhanced with ML
    visitor_messages = conversation_log
      .select { |ex| ex[:role] == 'visitor' }
      .map { |ex| ex[:content] }
      .join(' ')
      
    positive_words = %w[love like enjoy beautiful amazing wonderful great fantastic]
    negative_words = %w[hate dislike boring ugly terrible awful bad horrible]
    
    positive_count = positive_words.count { |word| visitor_messages.match?(/\b#{word}\b/i) }
    negative_count = negative_words.count { |word| visitor_messages.match?(/\b#{word}\b/i) }
    
    if positive_count > negative_count
      'positive'
    elsif negative_count > positive_count
      'negative'
    else
      'neutral'
    end
  end
end
```

### Conversation Controller and Endpoints

```ruby
# app/controllers/conversation_controller.rb
class ConversationController < ApplicationController
  before_action :authenticate_api_key
  
  # POST /api/v1/conversation/start
  def start
    session = ConversationSession.new(
      initiated_by: params[:reason] || 'unknown',
      context: build_initial_context
    )
    
    # Store session in Redis for quick access
    store_session(session)
    
    # Generate initial response
    response = generate_initial_response(session)
    
    render json: {
      success: true,
      session_id: session.session_id,
      response: response[:content],
      response_type: response[:type],
      continue_listening: response[:continue_listening],
      suggested_tools: response[:suggested_tools],
      metadata: {
        initiated_by: session.initiated_by,
        timestamp: session.started_at.iso8601
      }
    }
  rescue StandardError => e
    Rails.logger.error "Conversation start error: #{e.message}"
    render json: { success: false, error: e.message }, status: 500
  end
  
  # POST /api/v1/conversation/continue
  def continue
    session_id = params[:session_id]
    visitor_input = params[:message]
    
    session = load_session(session_id)
    return render json: { success: false, error: 'Session not found' }, status: 404 unless session
    
    # Add visitor input to conversation log
    session.add_exchange(
      role: 'visitor',
      content: visitor_input,
      metadata: {
        source: 'voice_assistant',
        confidence: params[:confidence],
        duration: params[:duration]
      }
    )
    
    # Process input and generate response
    response = process_conversation_turn(session, visitor_input)
    
    # Update session
    store_session(session)
    
    render json: {
      success: true,
      session_id: session.session_id,
      response: response[:content],
      response_type: response[:type],
      continue_listening: response[:continue_listening],
      tool_results: response[:tool_results],
      conversation_should_end: !session.should_continue_conversation?,
      metadata: {
        exchange_count: session.conversation_log.count { |ex| ex[:role] == 'visitor' },
        last_activity: session.last_activity_at.iso8601
      }
    }
  rescue StandardError => e
    Rails.logger.error "Conversation continue error: #{e.message}"
    render json: { success: false, error: e.message }, status: 500
  end
  
  # POST /api/v1/conversation/end
  def end_conversation
    session_id = params[:session_id]
    reason = params[:reason] || 'natural_end'
    
    session = load_session(session_id)
    return render json: { success: false, error: 'Session not found' }, status: 404 unless session
    
    session.status = 'ended'
    
    # Generate final response if needed
    final_response = generate_final_response(session, reason)
    
    # Store conversation log
    conversation_log = store_conversation_log(session)
    
    # Cleanup session from Redis
    cleanup_session(session_id)
    
    render json: {
      success: true,
      final_response: final_response,
      conversation_summary: session.conversation_summary,
      log_id: conversation_log.id
    }
  rescue StandardError => e
    Rails.logger.error "Conversation end error: #{e.message}"
    render json: { success: false, error: e.message }, status: 500
  end
  
  private
  
  def build_initial_context
    {
      installation_status: get_installation_status,
      time_of_day: Time.current.strftime('%H:%M'),
      ambient_conditions: get_ambient_conditions,
      recent_interactions: get_recent_interaction_summary,
      current_artistic_theme: get_current_artistic_theme
    }
  end
  
  def generate_initial_response(session)
    # Use appropriate Desiru module based on initiation reason
    case session.initiated_by
    when 'motion_detected'
      generate_motion_greeting(session)
    when 'user_initiated'
      generate_user_greeting(session)
    when 'scheduled'
      generate_scheduled_interaction(session)
    else
      generate_default_greeting(session)
    end
  end
  
  def generate_motion_greeting(session)
    greeting_module = MotionGreetingModule.new
    result = greeting_module.call(
      context: session.context,
      time_of_day: Time.current.strftime('%H:%M'),
      recent_visitors: get_recent_visitor_count
    )
    
    session.add_exchange(
      role: 'assistant',
      content: result.greeting,
      metadata: { type: 'motion_greeting', tools_available: result.suggested_tools }
    )
    
    {
      content: result.greeting,
      type: 'text',
      continue_listening: true,
      suggested_tools: result.suggested_tools
    }
  end
  
  def process_conversation_turn(session, visitor_input)
    # Use ReAct agent for conversation processing
    conversation_agent = ConversationAgent.new(
      session: session,
      available_tools: get_available_tools
    )
    
    result = conversation_agent.process_input(visitor_input)
    
    # Add assistant response to log
    session.add_exchange(
      role: 'assistant',
      content: result.response,
      metadata: {
        tools_used: result.tools_used,
        confidence: result.confidence,
        reasoning: result.reasoning
      }
    )
    
    # Add any tool calls to session
    result.tool_calls.each do |tool_call|
      session.add_tool_call(
        tool_name: tool_call[:name],
        parameters: tool_call[:parameters],
        result: tool_call[:result],
        execution_time: tool_call[:execution_time]
      )
    end
    
    {
      content: result.response,
      type: result.response_type,
      continue_listening: result.continue_conversation,
      tool_results: result.tool_results
    }
  end
  
  def store_session(session)
    Redis.current.setex(
      "conversation_session:#{session.session_id}",
      30.minutes.to_i,
      session.to_json
    )
  end
  
  def load_session(session_id)
    data = Redis.current.get("conversation_session:#{session_id}")
    return nil unless data
    
    ConversationSession.new(JSON.parse(data))
  end
  
  def store_conversation_log(session)
    ConversationLog.create!(
      session_id: session.session_id,
      initiated_by: session.initiated_by,
      started_at: session.started_at,
      ended_at: Time.current,
      exchange_count: session.conversation_log.count { |ex| ex[:role] == 'visitor' },
      conversation_data: session.conversation_log,
      tool_calls: session.tool_calls,
      summary: session.conversation_summary,
      visitor_profile: session.visitor_profile
    )
  end
end
```

### Conversation Agent with Tool Calling

```ruby
# lib/agents/conversation_agent.rb
class ConversationAgent
  def initialize(session:, available_tools: [])
    @session = session
    @available_tools = available_tools
    @react_agent = build_react_agent
  end
  
  def process_input(visitor_input)
    # Analyze input for intent and context
    input_analysis = analyze_input(visitor_input)
    
    # Use ReAct agent to process and respond
    agent_result = @react_agent.call(
      visitor_input: visitor_input,
      conversation_history: format_conversation_history,
      session_context: @session.context,
      input_analysis: input_analysis,
      available_tools: @available_tools.map(&:name)
    )
    
    # Process any tool calls
    tool_results = execute_tool_calls(agent_result.tool_calls)
    
    # Determine if conversation should continue
    continue_conversation = should_continue_based_on_response(agent_result, tool_results)
    
    ConversationResult.new(
      response: agent_result.response,
      response_type: determine_response_type(agent_result),
      continue_conversation: continue_conversation,
      tools_used: agent_result.tool_calls.map { |tc| tc[:name] },
      tool_calls: agent_result.tool_calls,
      tool_results: tool_results,
      confidence: agent_result.confidence,
      reasoning: agent_result.reasoning
    )
  end
  
  private
  
  def build_react_agent
    Desiru::Modules::ReAct.new(
      'visitor_input: string, conversation_history: list[dict], session_context: dict, input_analysis: dict, available_tools: list[string] -> response: string, tool_calls: list[dict], confidence: float, reasoning: string',
      tools: @available_tools,
      max_iterations: 6
    )
  end
  
  def analyze_input(input)
    analysis_module = InputAnalysisModule.new
    analysis_module.call(
      text: input,
      conversation_context: @session.context,
      previous_exchanges: @session.conversation_log.last(3)
    )
  end
  
  def format_conversation_history
    @session.conversation_log.map do |exchange|
      {
        role: exchange[:role],
        content: exchange[:content],
        timestamp: exchange[:timestamp]
      }
    end
  end
  
  def execute_tool_calls(tool_calls)
    tool_calls.map do |tool_call|
      tool = @available_tools.find { |t| t.name == tool_call[:name] }
      next nil unless tool
      
      start_time = Time.current
      result = tool.call(**tool_call[:parameters].symbolize_keys)
      execution_time = Time.current - start_time
      
      {
        tool_name: tool_call[:name],
        parameters: tool_call[:parameters],
        result: result,
        execution_time: execution_time,
        success: result[:success] != false
      }
    end.compact
  end
  
  def should_continue_based_on_response(agent_result, tool_results)
    # Check if agent explicitly indicated continuation
    return false if agent_result.response.match?(/goodbye|farewell|see you|that's all/i)
    return true if agent_result.response.include?('?')  # Asked a question
    
    # Check if tools suggest continuation
    return true if tool_results.any? { |tr| tr[:result][:continue_conversation] }
    
    # Default based on session state
    @session.should_continue_conversation?
  end
  
  def determine_response_type(agent_result)
    # Could be enhanced to detect if response should be audio, text, etc.
    'text'
  end
end

# Result object for conversation processing
class ConversationResult
  include ActiveModel::Model
  include ActiveModel::Attributes
  
  attribute :response, :string
  attribute :response_type, :string
  attribute :continue_conversation, :boolean
  attribute :tools_used, :array, default: []
  attribute :tool_calls, :array, default: []
  attribute :tool_results, :array, default: []
  attribute :confidence, :float
  attribute :reasoning, :string
end
```


## Home Assistant Side Implementation

### Voice Assistant Conversation Coordination

```yaml
# automations.yaml - Conversation Flow Management
- id: start_conversation_motion
  alias: "Start Conversation - Motion Detected"
  description: "Initiate conversation when motion is detected"
  trigger:
    - platform: state
      entity_id: binary_sensor.motion_sensor
      to: "on"
  condition:
    - condition: state
      entity_id: input_boolean.conversation_active
      state: "off"
    - condition: state
      entity_id: rest.desiru_app_health
      state: "ok"
  action:
    - service: script.start_conversation
      data:
        reason: "motion_detected"
        trigger_data:
          sensor: "{{ trigger.entity_id }}"
          timestamp: "{{ trigger.to_state.last_updated }}"

- id: start_conversation_voice_wake
  alias: "Start Conversation - Voice Wake"
  description: "Initiate conversation when voice assistant is activated"
  trigger:
    - platform: event
      event_type: voice_assistant_wake_word_detected
      event_data:
        assistant_id: art_installation_assistant
  condition:
    - condition: state
      entity_id: rest.desiru_app_health
      state: "ok"
  action:
    - service: script.start_conversation
      data:
        reason: "user_initiated"
        trigger_data:
          wake_word: "{{ trigger.event.data.wake_word }}"
          confidence: "{{ trigger.event.data.confidence }}"

- id: process_voice_input_in_conversation
  alias: "Process Voice Input During Conversation"
  description: "Handle voice input when conversation is active"
  trigger:
    - platform: event
      event_type: voice_assistant_speech_finished
      event_data:
        assistant_id: art_installation_assistant
  condition:
    - condition: state
      entity_id: input_boolean.conversation_active
      state: "on"
  action:
    - service: script.continue_conversation
      data:
        speech_text: "{{ trigger.event.data.speech_text }}"
        session_id: "{{ states('input_text.current_session_id') }}"
        speech_metadata:
          confidence: "{{ trigger.event.data.confidence | default(0.8) }}"
          duration: "{{ trigger.event.data.duration | default(0) }}"

- id: conversation_timeout
  alias: "Conversation Timeout"
  description: "End conversation after timeout period"
  trigger:
    - platform: event
      event_type: timer.finished
      event_data:
        entity_id: timer.conversation_timeout
  condition:
    - condition: state
      entity_id: input_boolean.conversation_active
      state: "on"
  action:
    - service: script.end_conversation
      data:
        reason: "timeout"
        session_id: "{{ states('input_text.current_session_id') }}"
```

### Conversation Management Scripts

```yaml
# scripts.yaml - Conversation Flow Scripts
start_conversation:
  alias: "Start New Conversation"
  description: "Initialize conversation with Desiru app"
  fields:
    reason:
      description: "Reason for starting conversation"
      example: "motion_detected"
    trigger_data:
      description: "Additional trigger information"
      default: {}
  sequence:
    - service: input_boolean.turn_on
      target:
        entity_id: input_boolean.conversation_active
    
    - service: timer.start
      target:
        entity_id: timer.conversation_timeout
      data:
        duration: "{{ states('input_number.conversation_timeout_minutes') | int * 60 }}"
    
    # Call Desiru app to start conversation
    - service: rest_command.start_conversation_desiru
      data:
        reason: "{{ reason }}"
        trigger_data: "{{ trigger_data | tojson }}"
        context:
          location: "art_installation"
          ambient_conditions: "{{ get_ambient_conditions() }}"
          time_of_day: "{{ now().strftime('%H:%M') }}"
    
    # Wait for response
    - wait_template: "{{ states('sensor.desiru_conversation_response') != 'unknown' }}"
      timeout: "00:00:15"
      continue_on_timeout: true
    
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ wait.completed }}"
          sequence:
            - service: script.handle_conversation_response
              data:
                response_data: "{{ state_attr('sensor.desiru_conversation_response', 'response_data') }}"
                is_initial: true
      default:
        - service: script.handle_conversation_error
          data:
            error_type: "start_timeout"
            message: "Timeout waiting for conversation start response"

continue_conversation:
  alias: "Continue Existing Conversation"
  description: "Send visitor input to continue conversation"
  fields:
    speech_text:
      description: "Transcribed speech from visitor"
    session_id:
      description: "Current conversation session ID"
    speech_metadata:
      description: "Metadata about the speech input"
      default: {}
  sequence:
    # Reset conversation timeout
    - service: timer.start
      target:
        entity_id: timer.conversation_timeout
      data:
        duration: "{{ states('input_number.conversation_timeout_minutes') | int * 60 }}"
    
    # Log the input
    - service: notify.conversation_log
      data:
        message: "Visitor input: {{ speech_text }}"
    
    # Send to Desiru app
    - service: rest_command.continue_conversation_desiru
      data:
        session_id: "{{ session_id }}"
        message: "{{ speech_text }}"
        metadata: "{{ speech_metadata | tojson }}"
        context:
          timestamp: "{{ now().isoformat() }}"
    
    # Wait for response
    - wait_template: "{{ states('sensor.desiru_conversation_response') != states('sensor.desiru_conversation_response') }}"
      timeout: "00:00:20"
      continue_on_timeout: true
    
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ wait.completed }}"
          sequence:
            - service: script.handle_conversation_response
              data:
                response_data: "{{ state_attr('sensor.desiru_conversation_response', 'response_data') }}"
                is_initial: false
      default:
        - service: script.handle_conversation_error
          data:
            error_type: "continue_timeout"
            message: "Timeout waiting for conversation continue response"

handle_conversation_response:
  alias: "Handle Conversation Response from Desiru"
  description: "Process response and manage voice assistant state"
  fields:
    response_data:
      description: "Response data from Desiru app"
    is_initial:
      description: "Whether this is the initial response"
      default: false
  sequence:
    # Store session ID if this is initial response
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ is_initial }}"
          sequence:
            - service: input_text.set_value
              target:
                entity_id: input_text.current_session_id
              data:
                value: "{{ response_data.session_id }}"
    
    # Log the response
    - service: notify.conversation_log
      data:
        message: "Assistant response: {{ response_data.response }}"
    
    # Handle different response types
    - choose:
        # Text response - use TTS
        - conditions:
            - condition: template
              value_template: "{{ response_data.response_type == 'text' }}"
          sequence:
            - service: script.speak_response_and_listen
              data:
                message: "{{ response_data.response }}"
                continue_listening: "{{ response_data.continue_listening }}"
                should_end: "{{ response_data.conversation_should_end | default(false) }}"
        
        # Audio response - play file
        - conditions:
            - condition: template
              value_template: "{{ response_data.response_type == 'audio' }}"
          sequence:
            - service: script.play_audio_and_listen
              data:
                audio_url: "{{ response_data.audio_url }}"
                continue_listening: "{{ response_data.continue_listening }}"
                should_end: "{{ response_data.conversation_should_end | default(false) }}"
        
        # Tool execution results
        - conditions:
            - condition: template
              value_template: "{{ response_data.tool_results is defined and response_data.tool_results | length > 0 }}"
          sequence:
            - service: script.handle_tool_results
              data:
                tool_results: "{{ response_data.tool_results }}"
                main_response: "{{ response_data.response }}"
                continue_listening: "{{ response_data.continue_listening }}"
    
    # Check if conversation should end
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ response_data.conversation_should_end | default(false) }}"
          sequence:
            - service: script.end_conversation
              data:
                reason: "natural_end"
                session_id: "{{ response_data.session_id }}"

speak_response_and_listen:
  alias: "Speak Response and Manage Listening State"
  description: "Speak the response and optionally reactivate voice assistant"
  fields:
    message:
      description: "Message to speak"
    continue_listening:
      description: "Whether to continue listening after speaking"
    should_end:
      description: "Whether conversation should end"
      default: false
  sequence:
    # Speak the response
    - service: tts.google_say
      data:
        message: "{{ message }}"
        cache: false
    
    # Wait for TTS to complete (estimate based on message length)
    - delay: "{{ (message | length / 10) | round(0, 'ceil') | int }}"
    
    # Decide next action based on flags
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ should_end }}"
          sequence:
            - service: script.end_conversation
              data:
                reason: "natural_end"
                session_id: "{{ states('input_text.current_session_id') }}"
        - conditions:
            - condition: template
              value_template: "{{ continue_listening }}"
          sequence:
            - service: script.reactivate_voice_assistant
      default:
        # Default to ending if no clear continuation signal
        - service: script.end_conversation
          data:
            reason: "no_continuation_signal"
            session_id: "{{ states('input_text.current_session_id') }}"

reactivate_voice_assistant:
  alias: "Reactivate Voice Assistant for Continued Listening"
  description: "Restart voice assistant to listen for next input"
  sequence:
    # Brief pause to ensure TTS has finished
    - delay: "00:00:01"
    
    # Restart voice assistant in listening mode
    - service: voice_assistant.start_listening
      target:
        entity_id: voice_assistant.art_installation_assistant
      data:
        timeout: "{{ states('input_number.listening_timeout_seconds') | int }}"
        wake_word_detection: false  # Skip wake word, go straight to listening
    
    # Update status
    - service: input_text.set_value
      target:
        entity_id: input_text.conversation_status
      data:
        value: "listening_for_response"
    
    # Log the reactivation
    - service: notify.conversation_log
      data:
        message: "Voice assistant reactivated for continued conversation"

end_conversation:
  alias: "End Current Conversation"
  description: "Properly terminate conversation and cleanup"
  fields:
    reason:
      description: "Reason for ending conversation"
    session_id:
      description: "Session ID to end"
  sequence:
    # Notify Desiru app of conversation end
    - service: rest_command.end_conversation_desiru
      data:
        session_id: "{{ session_id }}"
        reason: "{{ reason }}"
        timestamp: "{{ now().isoformat() }}"
    
    # Stop any active voice assistant listening
    - service: voice_assistant.stop_listening
      target:
        entity_id: voice_assistant.art_installation_assistant
    
    # Update conversation state
    - service: input_boolean.turn_off
      target:
        entity_id: input_boolean.conversation_active
    
    - service: timer.cancel
      target:
        entity_id: timer.conversation_timeout
    
    - service: input_text.set_value
      target:
        entity_id: input_text.current_session_id
      data:
        value: ""
    
    - service: input_text.set_value
      target:
        entity_id: input_text.conversation_status
      data:
        value: "idle"
    
    # Log conversation end
    - service: notify.conversation_log
      data:
        message: "Conversation ended - Reason: {{ reason }}, Session: {{ session_id }}"
    
    # Optional: Speak farewell if natural end
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ reason == 'natural_end' }}"
          sequence:
            - service: tts.google_say
              data:
                message: "Thank you for visiting our interactive art installation. Feel free to explore more!"

handle_conversation_error:
  alias: "Handle Conversation Errors"
  description: "Manage errors during conversation flow"
  fields:
    error_type:
      description: "Type of error encountered"
    message:
      description: "Error message"
  sequence:
    - service: notify.conversation_log
      data:
        message: "Conversation error [{{ error_type }}]: {{ message }}"
    
    # Attempt recovery based on error type
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ error_type in ['start_timeout', 'continue_timeout'] }}"
          sequence:
            - service: tts.google_say
              data:
                message: "I'm having trouble processing your request. Let me try again."
            - delay: "00:00:02"
            - service: script.reactivate_voice_assistant
        
        - conditions:
            - condition: template
              value_template: "{{ error_type == 'desiru_app_error' }}"
          sequence:
            - service: tts.google_say
              data:
                message: "I'm experiencing technical difficulties. Please try again in a moment."
            - service: script.end_conversation
              data:
                reason: "technical_error"
                session_id: "{{ states('input_text.current_session_id') }}"
      
      default:
        - service: script.end_conversation
          data:
            reason: "unknown_error"
            session_id: "{{ states('input_text.current_session_id') }}"
```

### REST Commands for Conversation API

```yaml
# configuration.yaml - Conversation REST Commands
rest_command:
  start_conversation_desiru:
    url: "{{ states('input_text.desiru_app_url') }}/api/v1/conversation/start"
    method: POST
    headers:
      Content-Type: "application/json"
      Authorization: "Bearer {{ states('input_text.desiru_api_key') }}"
    payload: >
      {
        "reason": "{{ reason }}",
        "trigger_data": {{ trigger_data }},
        "context": {{ context | tojson }},
        "installation_id": "{{ states('input_text.installation_id') }}"
      }
    timeout: 15

  continue_conversation_desiru:
    url: "{{ states('input_text.desiru_app_url') }}/api/v1/conversation/continue"
    method: POST
    headers:
      Content-Type: "application/json"
      Authorization: "Bearer {{ states('input_text.desiru_api_key') }}"
    payload: >
      {
        "session_id": "{{ session_id }}",
        "message": "{{ message }}",
        "metadata": {{ metadata }},
        "context": {{ context | tojson }}
      }
    timeout: 20

  end_conversation_desiru:
    url: "{{ states('input_text.desiru_app_url') }}/api/v1/conversation/end"
    method: POST
    headers:
      Content-Type: "application/json"
      Authorization: "Bearer {{ states('input_text.desiru_api_key') }}"
    payload: >
      {
        "session_id": "{{ session_id }}",
        "reason": "{{ reason }}",
        "timestamp": "{{ timestamp }}"
      }
    timeout: 10
```

### Input Helpers and Configuration

```yaml
# configuration.yaml - Input helpers for conversation management
input_boolean:
  conversation_active:
    name: "Conversation Active"
    initial: false
    icon: mdi:account-voice

input_text:
  current_session_id:
    name: "Current Session ID"
    max: 100
    initial: ""
  
  conversation_status:
    name: "Conversation Status"
    max: 50
    initial: "idle"
  
  desiru_app_url:
    name: "Desiru App URL"
    max: 200
    initial: "http://your-desiru-app.com:4567"
  
  desiru_api_key:
    name: "Desiru API Key"
    max: 100
    initial: !secret desiru_api_key
  
  installation_id:
    name: "Installation ID"
    max: 50
    initial: "art_installation_001"

input_number:
  conversation_timeout_minutes:
    name: "Conversation Timeout (minutes)"
    min: 1
    max: 30
    step: 1
    initial: 5
    unit_of_measurement: "min"
  
  listening_timeout_seconds:
    name: "Listening Timeout (seconds)"
    min: 5
    max: 60
    step: 5
    initial: 30
    unit_of_measurement: "s"

# Timer for conversation timeout
timer:
  conversation_timeout:
    name: "Conversation Timeout"
    restore: true

# Notification for conversation logging
notify:
  - platform: file
    name: conversation_log
    filename: /config/logs/conversations.log
    timestamp: true
```

### Sensors for Conversation State

```yaml
# configuration.yaml - Conversation state sensors
sensor:
  - platform: template
    sensors:
      conversation_state:
        friendly_name: "Conversation State"
        value_template: >
          {% if is_state('input_boolean.conversation_active', 'on') %}
            {% if states('input_text.conversation_status') == 'listening_for_response' %}
              Listening
            {% else %}
              Active
            {% endif %}
          {% else %}
            Idle
          {% endif %}
        icon_template: >
          {% if is_state('input_boolean.conversation_active', 'on') %}
            {% if states('input_text.conversation_status') == 'listening_for_response' %}
              mdi:microphone
            {% else %}
              mdi:account-voice
            {% endif %}
          {% else %}
            mdi:sleep
          {% endif %}
      
      current_session_duration:
        friendly_name: "Current Session Duration"
        value_template: >
          {% if is_state('input_boolean.conversation_active', 'on') %}
            {% set start_time = state_attr('timer.conversation_timeout', 'started_at') %}
            {% if start_time %}
              {{ (as_timestamp(now()) - as_timestamp(start_time)) | round(0) }}
            {% else %}
              0
            {% endif %}
          {% else %}
            0
          {% endif %}
        unit_of_measurement: "seconds"

# RESTful sensor to monitor Desiru conversation responses
rest:
  - resource: "{{ states('input_text.desiru_app_url') }}/api/v1/conversation/status"
    method: GET
    name: "Desiru Conversation Response"
    headers:
      Authorization: "Bearer {{ states('input_text.desiru_api_key') }}"
    value_template: "{{ value_json.status }}"
    json_attributes:
      - response_data
      - timestamp
    scan_interval: 5  # Check every 5 seconds during active conversations
```

## Tool Integration Framework

### Available Tools Definition

```ruby
# lib/tools/art_installation_tools.rb

# Image capture tool
class ImageCaptureToolArt
  def self.name
    "capture_image"
  end
  
  def self.description
    "Capture image from installation camera. Args: camera_id (string), purpose (string)"
  end
  
  def self.call(camera_id: 'main', purpose: 'conversation')
    # This would trigger HASS to capture and upload image
    request_id = SecureRandom.uuid
    
    # Send request to HASS via webhook or API
    HassApiClient.capture_image(
      camera_id: camera_id,
      request_id: request_id,
      purpose: purpose
    )
    
    {
      success: true,
      request_id: request_id,
      message: "Image capture initiated",
      continue_conversation: true
    }
  end
end

# Lighting control tool
class LightingControlTool
  def self.name
    "control_lighting"
  end
  
  def self.description
    "Control installation lighting. Args: action (string), color (string), brightness (int), duration (int)"
  end
  
  def self.call(action:, color: nil, brightness: nil, duration: 10)
    lighting_command = {
      type: 'lighting',
      action: action,
      parameters: {
        color: color,
        brightness: brightness,
        duration: duration
      }
    }
    
    # Send to HASS for execution
    HassApiClient.control_environment([lighting_command])
    
    {
      success: true,
      message: "Lighting #{action} applied",
      continue_conversation: true
    }
  end
end

# Ambient sound tool
class AmbientSoundTool
  def self.name
    "play_ambient_sound"
  end
  
  def self.description
    "Play ambient sound. Args: sound_type (string), volume (float), duration (int)"
  end
  
  def self.call(sound_type:, volume: 0.3, duration: 30)
    audio_command = {
      type: 'audio',
      action: 'play_ambient',
      parameters: {
        sound_type: sound_type,
        volume: volume,
        duration: duration
      }
    }
    
    HassApiClient.control_environment([audio_command])
    
    {
      success: true,
      message: "Playing #{sound_type} ambient sound",
      continue_conversation: true
    }
  end
end

# Visitor analytics tool
class VisitorAnalyticsTool
  def self.name
    "get_visitor_analytics"
  end
  
  def self.description
    "Get current visitor analytics and patterns. Args: time_period (string)"
  end
  
  def self.call(time_period: 'today')
    analytics = VisitorAnalytics.for_period(time_period)
    
    {
      success: true,
      data: analytics,
      message: "Retrieved visitor analytics for #{time_period}",
      continue_conversation: true
    }
  end
end
```

## Conversation Logging and Analytics

### Database Models

```ruby
# app/models/conversation_log.rb
class ConversationLog < ApplicationRecord
  validates :session_id, presence: true, uniqueness: true
  validates :initiated_by, presence: true
  
  scope :recent, -> { where('started_at > ?', 1.week.ago) }
  scope :by_initiation_type, ->(type) { where(initiated_by: type) }
  
  def duration
    return 0 unless ended_at && started_at
    ended_at - started_at
  end
  
  def visitor_messages
    conversation_data.select { |msg| msg['role'] == 'visitor' }
  end
  
  def assistant_messages
    conversation_data.select { |msg| msg['role'] == 'assistant' }
  end
  
  def tools_used
    tool_calls.map { |tc| tc['tool_name'] }.uniq
  end
  
  def engagement_score
    # Simple engagement scoring based on exchange count and duration
    base_score = [exchange_count * 10, 100].min
    duration_bonus = [duration / 60, 20].min  # Up to 20 points for duration
    tool_bonus = [tools_used.length * 5, 30].min  # Up to 30 points for tool usage
    
    base_score + duration_bonus + tool_bonus
  end
end

# Migration
class CreateConversationLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :conversation_logs do |t|
      t.string :session_id, null: false, index: { unique: true }
      t.string :initiated_by, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :exchange_count, default: 0
      t.json :conversation_data, default: []
      t.json :tool_calls, default: []
      t.json :summary, default: {}
      t.json :visitor_profile, default: {}
      t.float :engagement_score
      t.timestamps
    end
    
    add_index :conversation_logs, :initiated_by
    add_index :conversation_logs, :started_at
    add_index :conversation_logs, :engagement_score
  end
end
```

### Analytics and Reporting

```ruby
# lib/services/conversation_analytics.rb
class ConversationAnalytics
  def self.daily_summary(date = Date.current)
    conversations = ConversationLog.where(
      started_at: date.beginning_of_day..date.end_of_day
    )
    
    {
      date: date,
      total_conversations: conversations.count,
      by_initiation_type: conversations.group(:initiated_by).count,
      average_duration: conversations.average(:duration)&.round(2) || 0,
      average_exchanges: conversations.average(:exchange_count)&.round(1) || 0,
      total_tool_calls: conversations.sum { |c| c.tool_calls.length },
      popular_tools: popular_tools_for_conversations(conversations),
      engagement_distribution: engagement_distribution(conversations),
      peak_hours: peak_conversation_hours(conversations)
    }
  end
  
  def self.conversation_trends(days = 7)
    end_date = Date.current
    start_date = end_date - days.days
    
    (start_date..end_date).map do |date|
      daily_summary(date)
    end
  end
  
  private
  
  def self.popular_tools_for_conversations(conversations)
    tool_usage = Hash.new(0)
    
    conversations.each do |conv|
      conv.tool_calls.each do |tool_call|
        tool_usage[tool_call['tool_name']] += 1
      end
    end
    
    tool_usage.sort_by { |_, count| -count }.first(5).to_h
  end
  
  def self.engagement_distribution(conversations)
    scores = conversations.map(&:engagement_score).compact
    
    {
      low: scores.count { |s| s < 30 },
      medium: scores.count { |s| s >= 30 && s < 70 },
      high: scores.count { |s| s >= 70 }
    }
  end
  
  def self.peak_conversation_hours(conversations)
    hourly_counts = Hash.new(0)
    
    conversations.each do |conv|
      hour = conv.started_at.hour
      hourly_counts[hour] += 1
    end
    
    hourly_counts.sort_by { |_, count| -count }.first(3).to_h
  end
end
```

This comprehensive conversation flow architecture provides a complete system for managing multi-turn conversations between visitors and the interactive art installation, with automatic voice assistant re-activation, tool calling capabilities, and comprehensive logging and analytics.


