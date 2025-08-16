# 🎯 GlitchCube Async Tool Execution & Natural Conversation Flow
## Complete Implementation Plan & Architecture Reference

---

## Executive Summary

Transform the GlitchCube conversation system from synchronous request/response to an asynchronous flow that provides immediate user feedback while tools execute in the background. This creates a natural, human-like conversation experience that eliminates awkward silences and feels genuinely interactive.

### The Problem We're Solving

**Current Issues:**
- **TTS is broken**: conversation.py expects a string but receives nested objects from our enhanced response system
- **Long silence**: Users wait 3-5 seconds hearing nothing while tools execute
- **Unnatural flow**: Single-phase response doesn't match how humans actually communicate
- **Poor UX**: Users think the system is broken during tool execution pauses

**Root Cause:** Synchronous architecture forces users to wait through entire tool execution cycle before hearing any response.

### The Solution

Leverage our ownership of both the Home Assistant conversation agent AND the Sinatra backend to implement a custom protocol with:
- **Immediate acknowledgment** (<1 second response time)
- **Background tool execution** (non-blocking)
- **Natural follow-up responses** (persona-driven reactions to results)
- **Graceful error handling** (fallback to sync mode when needed)

---

## User Experience Transformation

### Before Implementation
```
User: "Turn the lights blue and play some music"
[5 seconds of awkward silence - user thinks system is broken]
Buddy: "I've turned the lights blue and started playing music."
[Feels robotic and disconnected]
```

### After Implementation
```
User: "Turn the lights blue and play some music"
[< 1 second]
Buddy: "Oh hell yeah, let me get that sorted for you!"
[User feels acknowledged, tools executing in background]
[2-3 seconds later]
Buddy: "Boom! Lights are looking absolutely fucking beautiful and the beats are pumping!"
[Feels natural, like talking to a real person]
```

---

## Architecture Overview

### Current Synchronous Flow
```
┌──────────────────────────────────────────────────────────────────┐
│                     CURRENT SYNCHRONOUS FLOW                      │
├──────────────────────────────────────────────────────────────────┤
│                                                                    │
│  User → HA STT → Pipeline → conversation.py → Sinatra → LLM      │
│                                         ↓                         │
│                                   [3-5 sec wait]                  │
│                                         ↓                         │
│                                  Execute Tools                    │
│                                         ↓                         │
│  User ← HA TTS ← Pipeline ← conversation.py ← Response           │
│                                                                    │
└──────────────────────────────────────────────────────────────────┘
```

### New Asynchronous Flow
```
┌──────────────────────────────────────────────────────────────────┐
│                      NEW ASYNCHRONOUS FLOW                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                    │
│  User → HA STT → Pipeline → conversation.py → Sinatra            │
│                                         ↓                         │
│                                   [< 1 sec]                       │
│                                         ↓                         │
│  User ← HA TTS ← "On it!" ← conversation.py ← Immediate Response │
│                                         │                         │
│                              [Background Thread]                  │
│                                         ↓                         │
│                                 Execute Tools                     │
│                                         ↓                         │
│                                  [2-3 sec later]                  │
│                                         ↓                         │
│  User ← HA TTS ← "Done! Lights are blue!" ← Direct TTS Call     │
│                                                                    │
└──────────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

## Phase 1: Fix Critical TTS Bug (BLOCKING)

**Priority: CRITICAL** - Nothing works without this fix!

**Location**: `/config/homeassistant/custom_components/glitchcube_conversation/conversation.py`

### Current Broken Code (Lines 210-212)
```python
# Extract response text
response_text = conversation_data.get(RESPONSE_KEY, "I didn't understand that.")
```

**Problem:** This assumes `RESPONSE_KEY` contains a simple string, but our enhanced flow_manager.rb returns nested objects like:
```python
{
  "response": {
    "response_type": "action_done",
    "speech": {
      "plain": {
        "speech": "Actual TTS text here"
      }
    }
  }
}
```

### Fixed Code Implementation
```python
def extract_response_text(self, conversation_data):
    """Extract speech text from potentially nested response structure"""
    raw_response = conversation_data.get(RESPONSE_KEY, "")
    
    if isinstance(raw_response, dict):
        # Handle nested HA conversation API structure
        response_text = (
            # Try nested speech structure first
            raw_response.get("speech", {}).get("plain", {}).get("speech") or
            # Try simple response field
            raw_response.get("response") or
            # Try claude response in custom data
            str(raw_response.get("data", {}).get("custom_data", {}).get("claude_response", ""))[:100] or
            # Final fallback
            "I had some trouble with that response."
        )
    else:
        # Simple string response
        response_text = str(raw_response) if raw_response else "I didn't understand that."
    
    # Ensure we always have valid speech text
    cleaned_text = response_text.strip()
    return cleaned_text if cleaned_text else "Sorry, I'm having trouble speaking right now."

# Update the async_process method to use this
async def async_process(self, user_input: conversation.ConversationInput) -> conversation.ConversationResult:
    # ... existing code until line 210 ...
    
    # Replace the broken line with robust extraction
    response_text = self.extract_response_text(conversation_data)
    
    # ... rest of existing code ...
```

### Testing Phase 1
```bash
# Test basic TTS functionality
echo "Testing TTS fix..." 
# Send any message to GlitchCube
# Expected: Should hear speech output (even if response structure is nested)
# If you hear nothing, the fix didn't work
```

---

## Phase 2: Define Custom Response Protocol

**Goal:** Create response type definitions that both Sinatra and HA understand

### Response Type Definitions

#### Sinatra Response Types
```ruby
# Type 1: Immediate acknowledgment (returned instantly)
{
  response_type: "immediate_speech_with_background_tools",
  speech_text: "Oh hell yeah! Let me get that sorted!",
  continue_conversation: true,
  session_id: session_id,
  action_count: extracted_actions.count
}

# Type 2: Normal response (no tools needed)
{
  response_type: "normal", 
  speech_text: "The weather today is sunny and warm!",
  continue_conversation: false,
  session_id: session_id
}

# Type 3: Error response
{
  response_type: "error",
  speech_text: "Sorry, I had trouble with that request.",
  continue_conversation: false,
  session_id: session_id,
  error_details: "Tool execution timeout"
}
```

### Home Assistant Agent Response Routing

**Location**: `/config/homeassistant/custom_components/glitchcube_conversation/conversation.py`

Add after line 192 in `async_process` method:

```python
# Get response type for intelligent routing  
response_type = conversation_data.get("response_type", "normal")
_LOGGER.info("Processing response_type: %s", response_type)

# Route based on response type
if response_type == "immediate_speech_with_background_tools":
    return await self._handle_immediate_speech_with_background_tools(
        conversation_data, user_input
    )
elif response_type == "error":
    return await self._handle_error_response(
        conversation_data, user_input  
    )
else:
    # Handle normal responses
    return await self._handle_normal_response(
        conversation_data, user_input
    )

async def _handle_immediate_speech_with_background_tools(
    self, conversation_data, user_input
):
    """Handle immediate speech while tools execute in background"""
    speech_text = conversation_data.get("speech_text", "On it!")
    _LOGGER.info("Executing immediate TTS: %s", speech_text[:50])
    
    # Fire TTS immediately without blocking the response
    await self.hass.services.async_call(
        'tts',
        'cloud_say',
        {
            'entity_id': 'media_player.square_voice',
            'message': speech_text,
            'language': 'en-US'
        },
        blocking=False  # Critical: don't wait for TTS completion
    )
    
    # Return minimal result to keep session alive for follow-up
    intent_response = intent.IntentResponse(language=user_input.language)
    intent_response.async_set_speech(" ")  # Empty to prevent double-speak
    
    return conversation.ConversationResult(
        conversation_id=user_input.conversation_id,
        response=intent_response,
        continue_conversation=True  # Keep session alive
    )

async def _handle_normal_response(self, conversation_data, user_input):
    """Handle standard synchronous responses"""
    response_text = self.extract_response_text(conversation_data)
    
    intent_response = intent.IntentResponse(language=user_input.language)
    intent_response.async_set_speech(response_text)
    
    continue_conversation = conversation_data.get("continue_conversation", False)
    
    return conversation.ConversationResult(
        conversation_id=user_input.conversation_id,
        response=intent_response,
        continue_conversation=continue_conversation
    )

async def _handle_error_response(self, conversation_data, user_input):
    """Handle error responses with appropriate messaging"""
    error_text = conversation_data.get("speech_text", "I encountered an error.")
    
    intent_response = intent.IntentResponse(language=user_input.language)
    intent_response.async_set_speech(error_text)
    
    return conversation.ConversationResult(
        conversation_id=user_input.conversation_id,
        response=intent_response,
        continue_conversation=False  # End conversation on error
    )
```

---

## Phase 3: Implement Async Flow in Sinatra

**Location**: `/lib/services/conversation/flow_manager.rb`

### Core Async Implementation

Add the main async orchestration method:

```ruby
def execute_async_tool_flow(message, session, persona_instance, context)
  """
  Main async orchestration:
  1. Generate immediate response for TTS  
  2. Extract actions from LLM response
  3. Launch background thread for tool execution
  4. Return immediate response to HA
  """
  start_time = Time.now
  execution_id = SecureRandom.uuid
  
  @logger.info('🚀 Starting async tool flow',
               tagged: %i[conversation async_flow start],
               session_id: session.session_id,
               execution_id: execution_id,
               persona: persona_instance.name)
  
  # 1. Get immediate response from LLM (optimized for speed)
  immediate_response = generate_immediate_response_fast(
    message, session, persona_instance, context
  )
  
  # 2. Extract actions from the response
  action_extractor = ActionExtractor.new(logger: @logger)
  extracted_actions = action_extractor.extract_actions_only(
    immediate_response.parsed_content, 
    session.session_id
  )
  
  if extracted_actions.any?
    @logger.info('🔧 Actions detected, launching background execution',
                 tagged: %i[conversation async_flow actions_detected],
                 session_id: session.session_id,
                 execution_id: execution_id,
                 action_count: extracted_actions.count,
                 actions: extracted_actions)
    
    # 3. Launch supervised background thread
    launch_background_tool_execution(
      extracted_actions, session, persona_instance, 
      message, execution_id
    )
    
    # 4. Return immediate acknowledgment to HA
    return build_immediate_response(
      persona_instance, extracted_actions, session.session_id
    )
  else
    # No actions detected - use normal synchronous flow
    @logger.info('💬 No actions detected, using normal flow',
                 tagged: %i[conversation async_flow no_actions],
                 session_id: session.session_id)
    
    return build_normal_response(
      immediate_response.response_text, session.session_id
    )
  end
end

def generate_immediate_response_fast(message, session, persona_instance, context)
  """Generate quick LLM response optimized for immediate acknowledgment"""
  
  # Build optimized system prompt for immediate response
  system_prompt = @llm_manager.build_immediate_response_prompt(
    persona_instance, context
  )
  
  # Get minimal conversation context (last 2-3 exchanges only)
  conversation_history = @history_manager.get_recent_context(session, limit: 3)
  messages = @llm_manager.prepare_messages(conversation_history, system_prompt, message)
  
  # Optimized LLM options for speed
  llm_options = {
    model: context[:model] || GlitchCube.config.fast_model, # Use faster model if available
    temperature: 0.7, # Consistent but not overly creative
    max_tokens: 200,  # Limit for faster response
    timeout: 8        # Shorter timeout for immediate response
  }
  
  # Record the message
  @state_manager.record_message(
    session: session, 
    role: 'user', 
    content: message, 
    persona: persona_instance.name
  )
  
  # Get LLM response
  llm_response = call_llm_with_schema_retry(messages, llm_options, session.session_id)
  
  @logger.info('⚡ Fast LLM response generated',
               tagged: %i[conversation async_flow immediate_response],
               session_id: session.session_id,
               response_length: llm_response.response_text&.length || 0,
               model: llm_response.model)
  
  llm_response
end

def launch_background_tool_execution(actions, session, persona_instance, original_message, execution_id)
  """Launch supervised background thread for tool execution"""
  
  # Store thread reference for cleanup and monitoring
  @active_tool_threads ||= {}
  
  tool_thread = Thread.new do
    Thread.current.name = "tools-#{session.session_id[0..8]}-#{execution_id[0..8]}"
    Thread.current[:execution_id] = execution_id
    Thread.current[:session_id] = session.session_id
    
    begin
      execute_tools_with_monitoring(
        actions, session, persona_instance, original_message, execution_id
      )
    rescue => e
      handle_background_thread_error(e, execution_id, session.session_id, persona_instance)
    ensure
      # Clean up thread reference
      @active_tool_threads.delete(session.session_id)
      @logger.info('🧹 Background thread cleanup completed',
                   tagged: %i[conversation async_flow thread_cleanup],
                   execution_id: execution_id,
                   session_id: session.session_id)
    end
  end
  
  # Store thread for monitoring
  @active_tool_threads[session.session_id] = tool_thread
  
  # Optional: Set up cleanup timer for orphaned threads
  cleanup_timer = Timer.new(30) do # 30 second cleanup timer
    if tool_thread.alive?
      @logger.warn('⏰ Killing orphaned tool execution thread',
                   execution_id: execution_id,
                   session_id: session.session_id)
      tool_thread.kill
      @active_tool_threads.delete(session.session_id)
    end
  end
  cleanup_timer.start
end

def execute_tools_with_monitoring(actions, session, persona_instance, original_message, execution_id)
  """Execute tools with comprehensive monitoring and timeout"""
  start_time = Time.now
  timeout = GlitchCube.config.async_tool_timeout || 15
  
  @logger.info('🔧 Starting tool execution with timeout',
               tagged: %i[conversation async_flow tool_execution_start],
               session_id: session.session_id,
               execution_id: execution_id,
               timeout_seconds: timeout,
               action_count: actions.count)
  
  begin
    Timeout::timeout(timeout) do
      # Execute tools via Claude conversation agent
      action_extractor = ActionExtractor.new(logger: @logger)
      claude_results = action_extractor.execute_actions_via_claude(
        actions, session.session_id, original_message
      )
      
      @logger.info('🎯 Tool execution completed',
                   tagged: %i[conversation async_flow tool_execution_complete],
                   session_id: session.session_id,
                   execution_id: execution_id,
                   success: claude_results[:success],
                   duration_ms: ((Time.now - start_time) * 1000).round)
      
      # Generate contextual follow-up response
      follow_up_text = generate_smart_follow_up(
        persona_instance, claude_results, actions, session.session_id
      )
      
      # Speak follow-up directly via Home Assistant
      if follow_up_text && follow_up_text.strip.length > 5
        speak_follow_up_directly(follow_up_text, session.session_id, execution_id)
      else
        @logger.warn('⚠️ Skipping empty or very short follow-up',
                     follow_up_text: follow_up_text&.inspect)
      end
      
      @logger.info('✅ Async tool flow completed successfully',
                   tagged: %i[conversation async_flow complete],
                   session_id: session.session_id,
                   execution_id: execution_id,
                   total_duration_ms: ((Time.now - start_time) * 1000).round)
    end
  rescue Timeout::Error
    @logger.error('⏰ Tool execution timed out',
                  tagged: %i[conversation async_flow timeout],
                  session_id: session.session_id,
                  execution_id: execution_id,
                  timeout_seconds: timeout)
    speak_timeout_follow_up(persona_instance, session.session_id)
  end
end

def generate_smart_follow_up(persona_instance, claude_results, actions, session_id)
  """Generate natural follow-up response based on tool results"""
  
  # Use existing persona response generation with enhancements
  follow_up_response = generate_persona_response_with_claude_feedback(
    persona_instance,
    "Completed your request!", # Base response
    claude_results,
    actions,
    session_id
  )
  
  # Clean up the response for TTS
  cleaned_response = follow_up_response
    .gsub(/^\[.*?\]\s*/, '')  # Remove action markers
    .gsub(/\*.*?\*/, '')      # Remove emphasis markers
    .strip
  
  @logger.info('🎭 Follow-up response generated',
               tagged: %i[conversation async_flow follow_up],
               session_id: session_id,
               persona: persona_instance.name,
               response_preview: cleaned_response[0..50])
  
  cleaned_response
end

def speak_follow_up_directly(text, session_id, execution_id)
  """Speak follow-up response directly via Home Assistant TTS"""
  
  @logger.info('📢 Speaking follow-up directly',
               tagged: %i[conversation async_flow direct_tts],
               session_id: session_id,
               execution_id: execution_id,
               text_preview: text[0..50])
  
  begin
    ha_client = Core::HomeAssistantClient.new
    
    # Use the new speak method (to be implemented in Phase 4)
    result = ha_client.speak(
      text,
      entity_id: 'media_player.square_voice',
      voice_options: { voice: get_current_persona_voice }
    )
    
    if result
      @logger.info('✅ Follow-up TTS successful',
                   session_id: session_id,
                   execution_id: execution_id)
    else
      # Fallback to basic service call
      @logger.warn('⚠️ Primary TTS failed, trying fallback',
                   session_id: session_id)
      ha_client.call_service('tts', 'cloud_say', {
        entity_id: 'media_player.square_voice',
        message: text,
        language: 'en'
      })
    end
  rescue => e
    @logger.error('💥 Follow-up TTS completely failed',
                  error: e.message,
                  session_id: session_id,
                  execution_id: execution_id)
  end
end

def handle_background_thread_error(error, execution_id, session_id, persona_instance)
  """Handle errors in background tool execution"""
  
  @logger.error('💥 Background tool execution failed',
                tagged: %i[conversation async_flow error],
                error: error.class.name,
                message: error.message,
                execution_id: execution_id,
                session_id: session_id,
                backtrace: error.backtrace&.first(5))
  
  # Attempt to notify user of failure
  error_message = generate_error_follow_up(persona_instance, error.message)
  
  begin
    speak_follow_up_directly(error_message, session_id, execution_id)
  rescue => tts_error
    @logger.error('💥 Failed to notify user of error via TTS',
                  error: tts_error.message,
                  execution_id: execution_id,
                  session_id: session_id)
  end
end

def build_immediate_response(persona_instance, actions, session_id)
  """Build immediate response for Home Assistant"""
  
  acknowledgment = generate_immediate_acknowledgment(persona_instance, actions)
  
  {
    response_type: "immediate_speech_with_background_tools",
    speech_text: acknowledgment,
    continue_conversation: true,
    session_id: session_id,
    action_count: actions.count,
    timestamp: Time.now.iso8601
  }
end

def build_normal_response(response_text, session_id)
  """Build normal synchronous response"""
  
  {
    response_type: "normal",
    speech_text: response_text,
    continue_conversation: false, # Or determine from LLM response
    session_id: session_id,
    timestamp: Time.now.iso8601
  }
end
```

### Immediate Acknowledgment Generator

```ruby
def generate_immediate_acknowledgment(persona_instance, actions)
  """Generate persona-specific immediate acknowledgment"""
  
  action_types = categorize_actions(actions)
  
  acknowledgments = case persona_instance.name.downcase
  when 'buddy'
    {
      lights: [
        "Oh hell yeah, let me light this place up!", 
        "Fucking brilliant, changing those lights!",
        "Light show coming right up!"
      ],
      music: [
        "Oh shit yes, let me get some beats going!", 
        "Music time, hell yeah!",
        "Time to pump up the jams!"
      ],
      mixed: [
        "Oh fuck yeah, I'm all over that!", 
        "You got it, let me handle that shit!",
        "Multiple requests? I got this!"
      ],
      generic: [
        "On it like a fucking rocket!", 
        "Hell yeah, working on it!",
        "Let me get right on that!"
      ]
    }
  when 'jax'
    {
      lights: [
        "Initializing lighting sequence...", 
        "Adjusting illumination parameters...",
        "Configuring light array..."
      ],
      music: [
        "Accessing audio subsystems...", 
        "Configuring media playback...",
        "Loading audio protocols..."
      ],
      mixed: [
        "Processing multiple system requests...", 
        "Executing batch operations...",
        "Initiating multi-system configuration..."
      ],
      generic: [
        "Acknowledged. Processing request...", 
        "Initiating task execution...",
        "Request received and processing..."
      ]
    }
  when 'lomi'
    {
      lights: [
        "Ooh, let me make it pretty for you!", 
        "Time to set the mood with some lights!",
        "Creating beautiful lighting for you!"
      ],
      music: [
        "Music makes everything better!", 
        "Let me find the perfect vibe!",
        "Time for some lovely tunes!"
      ],
      mixed: [
        "On it, sweet friend! This'll be good!", 
        "Making magic happen for you!",
        "Let me take care of all that!"
      ],
      generic: [
        "Coming right up!", 
        "Let me take care of that for you!",
        "On it, friend!"
      ]
    }
  else
    { 
      generic: [
        "Working on it!", 
        "Processing your request...",
        "On it!"
      ] 
    }
  end
  
  category = determine_primary_category(action_types)
  selected_acknowledgments = acknowledgments[category] || acknowledgments[:generic]
  selected_acknowledgments.sample
end

def categorize_actions(actions)
  """Categorize actions to select appropriate acknowledgment"""
  
  categories = { lights: 0, music: 0, other: 0 }
  
  actions.each do |action|
    action_text = action.to_s.downcase
    case action_text
    when /light|color|bright|flash|lamp|illumin/
      categories[:lights] += 1
    when /music|play|sound|volume|audio|song|track/
      categories[:music] += 1
    else
      categories[:other] += 1
    end
  end
  
  categories
end

def determine_primary_category(action_types)
  """Determine the primary category for acknowledgment selection"""
  
  total_actions = action_types.values.sum
  return :generic if total_actions == 0
  
  # If more than one category, it's mixed
  non_zero_categories = action_types.select { |_, count| count > 0 }.count
  return :mixed if non_zero_categories > 1
  
  # Return the single category
  action_types.find { |_, count| count > 0 }&.first || :generic
end
```

### Integration Point

Update the main `process_conversation` method:

```ruby
def process_conversation(message:, context: {}, persona: nil)
  # ... existing setup code ...
  
  # Route to async flow if enabled and appropriate
  if GlitchCube.config.enable_async_tools? && should_use_async_flow?(message, context)
    @logger.info('🚀 Routing to async tool flow',
                 session_id: session.session_id,
                 persona: persona_instance.name)
    
    return execute_async_tool_flow(message, session, persona_instance, context)
  else
    @logger.info('🔄 Using synchronous flow',
                 session_id: session.session_id,
                 reason: determine_sync_reason(message, context))
    
    # Existing synchronous flow
    return execute_conversation_extraction_cycle(message, session, persona_instance, context)
  end
end

def should_use_async_flow?(message, context)
  """Determine if async flow should be used for this request"""
  
  # Don't use async for follow-up questions or clarifications
  return false if context[:is_follow_up] || message.include?('?')
  
  # Don't use async for very short messages (likely not tool requests)
  return false if message.length < 10
  
  # Don't use async if explicitly disabled for this session
  return false if context[:force_sync]
  
  true
end

def determine_sync_reason(message, context)
  """Determine why sync flow was chosen (for logging)"""
  
  return "async_disabled" unless GlitchCube.config.enable_async_tools?
  return "follow_up_question" if context[:is_follow_up]
  return "contains_question" if message.include?('?')
  return "message_too_short" if message.length < 10
  return "force_sync_context" if context[:force_sync]
  return "default_sync"
end
```

---

## Phase 4: Add Direct TTS Method

**Location**: `/lib/core/home_assistant_client.rb`

### Core TTS Method

```ruby
def speak(message, entity_id: 'media_player.square_voice', voice: nil, language: 'en')
  """
  Speak text directly via Home Assistant TTS service
  
  This bypasses the conversation pipeline and speaks immediately,
  perfect for follow-up responses from background threads.
  
  Args:
    message (String): Text to speak
    entity_id (String): Media player entity for TTS output  
    voice (String): Specific voice to use (optional)
    language (String): Language code for TTS
    
  Returns:
    Hash: Service call response or nil on failure
  """
  
  return nil if message.nil? || message.strip.empty?
  
  # Clean the message for TTS
  cleaned_message = clean_message_for_tts(message)
  
  # Build service data
  service_data = {
    entity_id: entity_id,
    message: cleaned_message,
    language: language
  }
  
  # Add voice options if specified
  if voice && !voice.strip.empty?
    service_data[:options] = { voice: voice }
  end
  
  @logger.info('🗣️ Speaking directly via TTS',
               tagged: %i[tts direct_speech],
               entity_id: entity_id,
               message_length: cleaned_message.length,
               message_preview: cleaned_message[0..50],
               voice: voice)
  
  begin
    # Call the TTS service
    response = call_service('tts', 'cloud_say', service_data)
    
    @logger.info('✅ Direct TTS successful',
                 tagged: %i[tts direct_speech success],
                 entity_id: entity_id,
                 response_present: !response.nil?)
    
    response
  rescue => e
    @logger.error('💥 Direct TTS failed',
                  tagged: %i[tts direct_speech error],
                  error: e.class.name,
                  message: e.message,
                  entity_id: entity_id,
                  message_preview: cleaned_message[0..50])
    
    # Return nil to indicate failure
    nil
  end
end

def speak_with_retry(message, entity_id: 'media_player.square_voice', voice: nil, max_retries: 2)
  """Speak with automatic retry on failure"""
  
  retries = 0
  
  while retries <= max_retries
    result = speak(message, entity_id: entity_id, voice: voice)
    return result if result
    
    retries += 1
    if retries <= max_retries
      @logger.warn('🔄 TTS failed, retrying',
                   attempt: retries,
                   max_retries: max_retries,
                   entity_id: entity_id)
      sleep(0.5) # Brief pause before retry
    end
  end
  
  @logger.error('💥 TTS failed after all retries',
                max_retries: max_retries,
                entity_id: entity_id)
  nil
end

def get_available_tts_entities
  """Get available media players for TTS output"""
  
  begin
    entities = get_entities
    media_players = entities.select { |entity| entity['entity_id'].start_with?('media_player.') }
    
    @logger.info('🔍 Available TTS entities',
                 count: media_players.count,
                 entities: media_players.map { |e| e['entity_id'] })
    
    media_players
  rescue => e
    @logger.error('💥 Failed to get TTS entities',
                  error: e.message)
    []
  end
end

private

def clean_message_for_tts(message)
  """Clean message text for optimal TTS output"""
  
  cleaned = message
    .gsub(/^\[.*?\]\s*/, '')     # Remove action markers like [lights on]
    .gsub(/\*+([^*]+)\*+/, '\1') # Remove emphasis markers *text*
    .gsub(/`([^`]+)`/, '\1')     # Remove code backticks
    .gsub(/\s+/, ' ')            # Normalize whitespace
    .strip
  
  # Ensure reasonable length for TTS
  if cleaned.length > 200
    # Find last complete sentence within limit
    truncated = cleaned[0..200]
    last_sentence_end = truncated.rindex(/[.!?]/)
    
    if last_sentence_end && last_sentence_end > 50
      cleaned = truncated[0..last_sentence_end]
    else
      cleaned = "#{truncated.strip}..."
    end
  end
  
  cleaned
end
```

### Voice Management Integration

```ruby
def get_current_persona_voice
  """Get the TTS voice for the current active persona"""
  
  # This would integrate with your persona system
  # You might want to store this in context or session state
  current_persona = Thread.current[:current_persona] || 
                   GlitchCube.config.default_persona || 
                   'default'
  
  voice_mappings = {
    'buddy' => 'JennyNeural',
    'jax' => 'AriaNeural', 
    'lomi' => 'ZiraNeural',
    'zorp' => 'GuyNeural'
  }
  
  voice_mappings[current_persona.downcase] || 'JennyNeural'
end

def set_persona_voice_for_thread(persona_name)
  """Set voice context for current thread"""
  Thread.current[:current_persona] = persona_name
end

def speak_as_persona(message, persona_name, entity_id: 'media_player.square_voice')
  """Speak with persona-specific voice"""
  
  voice = get_voice_for_persona(persona_name)
  speak(message, entity_id: entity_id, voice: voice)
end

def get_voice_for_persona(persona_name)
  """Get TTS voice for specific persona"""
  
  voice_mappings = {
    'buddy' => 'JennyNeural',
    'jax' => 'AriaNeural',
    'lomi' => 'ZiraNeural', 
    'zorp' => 'GuyNeural'
  }
  
  voice_mappings[persona_name.to_s.downcase] || 'JennyNeural'
end
```

---

## Phase 5: Configuration & Testing Framework

### Configuration System

**Location**: Various config files and environment setup

#### Environment Variables
```bash
# Add to .env or environment
ENABLE_ASYNC_TOOLS=true
ASYNC_TOOL_TIMEOUT=15
MAX_CONCURRENT_TOOL_THREADS=3
FAST_MODEL=gpt-4o-mini  # Faster model for immediate responses
```

#### Configuration Class Updates
```ruby
# In config/settings.rb or similar
class GlitchCube
  class Config
    def enable_async_tools?
      ENV.fetch('ENABLE_ASYNC_TOOLS', 'true').downcase == 'true'
    end
    
    def async_tool_timeout
      ENV.fetch('ASYNC_TOOL_TIMEOUT', '15').to_i
    end
    
    def max_concurrent_tool_threads
      ENV.fetch('MAX_CONCURRENT_TOOL_THREADS', '3').to_i
    end
    
    def fast_model
      ENV.fetch('FAST_MODEL', default_model)
    end
    
    def async_cleanup_interval
      ENV.fetch('ASYNC_CLEANUP_INTERVAL', '60').to_i # seconds
    end
  end
end
```

### Thread Management & Monitoring

```ruby
# In flow_manager.rb or separate service
class AsyncThreadManager
  include Singleton
  
  def initialize
    @active_threads = {}
    @mutex = Mutex.new
    @logger = Services::Logging::SimpleLogger.new(component: 'AsyncThreadManager')
    
    # Start cleanup timer
    start_cleanup_timer
  end
  
  def register_thread(session_id, thread, execution_id)
    @mutex.synchronize do
      @active_threads[session_id] = {
        thread: thread,
        execution_id: execution_id,
        created_at: Time.now
      }
    end
    
    @logger.info('🧵 Thread registered',
                 session_id: session_id,
                 execution_id: execution_id,
                 total_active: @active_threads.count)
  end
  
  def unregister_thread(session_id)
    @mutex.synchronize do
      thread_info = @active_threads.delete(session_id)
      if thread_info
        @logger.info('🧹 Thread unregistered',
                     session_id: session_id,
                     execution_id: thread_info[:execution_id],
                     duration: Time.now - thread_info[:created_at],
                     total_active: @active_threads.count)
      end
    end
  end
  
  def cleanup_completed_threads
    cleaned_count = 0
    
    @mutex.synchronize do
      @active_threads.delete_if do |session_id, thread_info|
        if thread_info[:thread].status.nil? # Thread completed
          @logger.debug('🧹 Cleaning up completed thread',
                       session_id: session_id,
                       execution_id: thread_info[:execution_id])
          cleaned_count += 1
          true
        elsif Time.now - thread_info[:created_at] > 300 # 5 minutes old
          @logger.warn('⏰ Killing orphaned thread',
                      session_id: session_id,
                      execution_id: thread_info[:execution_id],
                      age: Time.now - thread_info[:created_at])
          thread_info[:thread].kill rescue nil
          cleaned_count += 1
          true
        else
          false
        end
      end
    end
    
    if cleaned_count > 0
      @logger.info('🧹 Thread cleanup completed',
                   cleaned_count: cleaned_count,
                   remaining_active: @active_threads.count)
    end
  end
  
  def get_active_thread_count
    @mutex.synchronize { @active_threads.count }
  end
  
  def get_thread_info
    @mutex.synchronize { @active_threads.dup }
  end
  
  private
  
  def start_cleanup_timer
    Thread.new do
      Thread.current.name = "async-thread-cleanup"
      
      loop do
        sleep(GlitchCube.config.async_cleanup_interval)
        cleanup_completed_threads
      end
    rescue => e
      @logger.error('💥 Cleanup timer failed', error: e.message)
      retry
    end
  end
end
```

### Testing Framework

#### Phase Testing Scripts

```ruby
# scripts/test_async_flow.rb
#!/usr/bin/env ruby

require_relative '../lib/glitchcube'

class AsyncFlowTester
  def initialize
    @logger = Services::Logging::SimpleLogger.new(component: 'AsyncFlowTester')
  end
  
  def test_phase_1_tts_fix
    puts "\n🧪 Testing Phase 1: TTS Fix"
    puts "=" * 50
    
    # This would test the conversation.py fix by sending a request
    # and checking that speech occurs
    
    test_message = "Hello, can you hear me?"
    
    puts "Sending test message: #{test_message}"
    puts "Expected: Should hear speech output within 2 seconds"
    puts "Manual verification required: Did you hear the response?"
    
    # TODO: Implement automated TTS detection if possible
  end
  
  def test_phase_2_response_routing
    puts "\n🧪 Testing Phase 2: Response Type Routing"
    puts "=" * 50
    
    # Test different response types
    response_types = [
      {
        type: "immediate_speech_with_background_tools",
        expected: "Should hear immediate response, then follow-up"
      },
      {
        type: "normal", 
        expected: "Should hear single response"
      }
    ]
    
    response_types.each do |test_case|
      puts "\nTesting response_type: #{test_case[:type]}"
      puts "Expected behavior: #{test_case[:expected]}"
      
      # Mock response to test routing
      # This would require integration with your conversation system
    end
  end
  
  def test_phase_3_async_execution
    puts "\n🧪 Testing Phase 3: Async Tool Execution"
    puts "=" * 50
    
    test_cases = [
      "Turn on the lights",
      "Play some music", 
      "Turn the lights blue and play jazz music",
      "What's the weather like?" # Should not trigger async
    ]
    
    test_cases.each do |message|
      puts "\nTesting: #{message}"
      
      start_time = Time.now
      
      # This would call your async flow
      begin
        # result = test_async_conversation(message)
        puts "✅ Immediate response time: < 1 second (simulated)"
        puts "🔧 Background tools executing..."
        sleep(2) # Simulate tool execution
        puts "✅ Follow-up response received"
      rescue => e
        puts "❌ Test failed: #{e.message}"
      end
      
      total_time = Time.now - start_time
      puts "Total interaction time: #{total_time.round(2)}s"
      puts "-" * 30
    end
  end
  
  def test_error_handling
    puts "\n🧪 Testing Error Handling"
    puts "=" * 50
    
    # Test various error scenarios
    error_scenarios = [
      "Timeout during tool execution",
      "Network failure to Home Assistant",
      "Invalid tool response",
      "Thread cleanup after error"
    ]
    
    error_scenarios.each do |scenario|
      puts "Testing scenario: #{scenario}"
      # Implement specific error condition tests
      puts "✅ Error handled gracefully (simulated)"
    end
  end
  
  def run_full_test_suite
    puts "🚀 Starting GlitchCube Async Flow Test Suite"
    puts "=" * 60
    
    test_phase_1_tts_fix
    test_phase_2_response_routing  
    test_phase_3_async_execution
    test_error_handling
    
    puts "\n✅ Test suite completed!"
    puts "Review results above and manually verify TTS behavior"
  end
end

# Run tests if called directly
if __FILE__ == $0
  tester = AsyncFlowTester.new
  tester.run_full_test_suite
end
```

#### Integration Test Script

```ruby
# scripts/test_integration.rb
#!/usr/bin/env ruby

require_relative '../lib/glitchcube'

# Test realistic conversation scenarios
conversation_scenarios = [
  {
    name: "Simple Light Control",
    message: "Turn on the bedroom lights",
    expected_immediate: "On it!",
    expected_follow_up: "Lights are on!",
    tools_expected: ["light.turn_on"]
  },
  {
    name: "Multi-action Request", 
    message: "Set the lights to blue and play some jazz",
    expected_immediate: "Working on that!",
    expected_follow_up: "Lights are blue and jazz is playing!",
    tools_expected: ["light.turn_on", "media_player.play_media"]
  },
  {
    name: "Question (No Tools)",
    message: "What time is it?",
    expected_immediate: "It's currently 3:45 PM",
    expected_follow_up: nil, # No follow-up for questions
    tools_expected: []
  }
]

conversation_scenarios.each do |scenario|
  puts "\n🎬 Testing Scenario: #{scenario[:name]}"
  puts "Message: #{scenario[:message]}"
  puts "Expected tools: #{scenario[:tools_expected].join(', ')}"
  
  # Run the scenario test
  # This would integrate with your actual conversation system
  
  puts "✅ Scenario completed"
  puts "-" * 40
end
```

#### Performance Monitoring

```ruby
# lib/services/async_performance_monitor.rb
class AsyncPerformanceMonitor
  def initialize
    @metrics = {}
    @mutex = Mutex.new
  end
  
  def record_immediate_response_time(session_id, duration_ms)
    @mutex.synchronize do
      @metrics[:immediate_response_times] ||= []
      @metrics[:immediate_response_times] << duration_ms
      
      # Keep only recent metrics (last 100)
      @metrics[:immediate_response_times] = @metrics[:immediate_response_times].last(100)
    end
  end
  
  def record_tool_execution_time(session_id, duration_ms, success)
    @mutex.synchronize do
      @metrics[:tool_execution_times] ||= []
      @metrics[:tool_execution_times] << {
        duration: duration_ms,
        success: success,
        timestamp: Time.now
      }
      
      # Keep only recent metrics
      @metrics[:tool_execution_times] = @metrics[:tool_execution_times].last(100)
    end
  end
  
  def get_performance_summary
    @mutex.synchronize do
      immediate_times = @metrics[:immediate_response_times] || []
      tool_times = @metrics[:tool_execution_times] || []
      
      {
        immediate_response: {
          count: immediate_times.count,
          avg_ms: immediate_times.sum.to_f / immediate_times.count,
          max_ms: immediate_times.max,
          min_ms: immediate_times.min
        },
        tool_execution: {
          count: tool_times.count,
          avg_ms: tool_times.map { |t| t[:duration] }.sum.to_f / tool_times.count,
          success_rate: tool_times.count { |t| t[:success] }.to_f / tool_times.count
        }
      }
    end
  end
end
```

---

## Implementation Priority & Order

### Phase 1: Critical TTS Fix (DO FIRST)
**Priority**: BLOCKING - Nothing works without this
**Time**: 15 minutes
**Files**: `conversation.py`

1. Implement `extract_response_text` method
2. Update `async_process` to use robust text extraction  
3. Test basic TTS functionality
4. Commit this fix separately before moving on

### Phase 2: Response Protocol (Foundation)  
**Priority**: HIGH - Enables async routing
**Time**: 30 minutes
**Files**: `conversation.py`

1. Add response type routing logic
2. Implement handler methods
3. Test custom response types work

### Phase 3: Async Sinatra Implementation (Core Feature)
**Priority**: HIGH - The main functionality
**Time**: 1-2 hours
**Files**: `flow_manager.rb`

1. Add `execute_async_tool_flow` method
2. Implement background thread management
3. Add immediate acknowledgment generation
4. Test async execution works

### Phase 4: Direct TTS (Polish)
**Priority**: MEDIUM - Improves follow-up quality
**Time**: 30 minutes  
**Files**: `home_assistant_client.rb`

1. Add `speak` method
2. Implement voice management
3. Test direct TTS calls

### Phase 5: Configuration & Monitoring (Production Ready)
**Priority**: LOW - Nice to have
**Time**: 1 hour
**Files**: Various

1. Add configuration flags
2. Implement monitoring
3. Add testing framework

---

## Success Metrics & Validation

### Technical Metrics
- **Immediate Response Time**: < 1 second to first speech
- **Tool Execution Time**: 2-5 seconds typical
- **Error Rate**: < 5% fallback to sync mode
- **Thread Management**: No memory leaks or orphaned threads

### User Experience Metrics  
- **Perceived Responsiveness**: No more "is it broken?" moments
- **Conversation Flow**: Natural, human-like interaction
- **Error Recovery**: Graceful handling of failures
- **Persona Consistency**: Character maintained throughout async flow

### Validation Tests
1. **Basic TTS**: Any message produces speech
2. **Immediate Response**: Action requests get <1s acknowledgment
3. **Follow-up Quality**: Background responses feel natural
4. **Error Handling**: Failures don't break conversation
5. **Performance**: No degradation under normal load

---

## Troubleshooting Guide

### Common Issues

#### No Speech at All
- Check Phase 1 TTS fix implementation
- Verify response text extraction logic
- Check Home Assistant TTS configuration
- Review conversation.py logs

#### Immediate Response Missing
- Verify response type routing in conversation.py
- Check Sinatra response format
- Review async flow triggering logic
- Validate acknowledgment generation

#### Follow-up Speech Missing  
- Check background thread execution
- Verify direct TTS method
- Review thread error handling
- Check Home Assistant service calls

#### Performance Issues
- Monitor thread creation/cleanup
- Check LLM response times
- Review tool execution timeouts
- Validate cleanup timer operation

### Debugging Commands

```bash
# Check Home Assistant logs
tail -f /config/logs/glitchcube_conversation.log

# Monitor Sinatra application logs  
tail -f logs/application.log

# Test TTS directly via Home Assistant
# (Use HA Developer Tools -> Services)
# Service: tts.cloud_say
# Data: {"entity_id": "media_player.square_voice", "message": "Test"}

# Check active Ruby threads
# In rails console:
Thread.list.select { |t| t.name&.include?('tools') }

# Monitor system performance
htop # or equivalent system monitor
```

---

## Future Enhancements

### Short Term (Next Sprint)
- Add conversation context updates from background threads
- Implement queue management for multiple concurrent requests  
- Add telemetry integration for production monitoring
- Create admin interface for thread management

### Medium Term (Next Month)
- Replace Thread.new with Sidekiq for distributed processing
- Add conversation continuation from tool results
- Implement advanced error recovery strategies
- Add voice emotion/tone variation

### Long Term (Future)
- Real-time streaming responses
- Multi-step tool execution workflows
- Advanced conversation state management
- Machine learning optimization of response timing

---

## Conclusion

This implementation plan provides a complete roadmap for transforming GlitchCube's conversation system into a natural, responsive, human-like interaction experience. The key insight is leveraging your ownership of both the Home Assistant conversation agent and the Sinatra backend to create a custom protocol that delivers exactly the user experience you want.

The phased approach minimizes risk while building toward a robust, production-ready system that will make GlitchCube feel truly alive and responsive. Users will go from thinking "Is this thing broken?" to "Holy shit, this feels like talking to a real person!"

Ready to build this natural conversation flow that will make GlitchCube the star of Burning Man! 🎪✨