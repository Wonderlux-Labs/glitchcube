
🩸 ConversationModule - The God Class from Hell
This thing is doing EVERYTHING:

Session management
Tool registry & execution
LED feedback execution
LLM orchestration
Home Assistant calls
Logging
System prompt generation
AWTRIX display updates
Persona switching
Error handling
Conversation enhancements (sensor data, retry logic)

It's like someone took a Swiss Army knife and duct-taped a chainsaw to it.
🤷‍♂️ ConversationService - The Useless Wrapper
This is just... why does this exist? It's literally just:

Wrapping ConversationModule
Tracking interaction count
Basic context getters/setters

It adds ZERO value and just creates another indirection layer.
😎 HomeAssistantClient - Actually Not Bad!
Surprisingly, this one is reasonably well-designed! It has:

Clear single responsibility (HA API calls)
Good error handling with circuit breakers
Focused methods for specific HA domains
Proper logging

Verdict: Leave HomeAssistantClient mostly alone - it's doing its job well.

🔪 Surgery Plan for ConversationModule
Here's how to slice it up without breaking everything:
1. Extract Message Processing Pipeline
ruby# lib/conversation/message_processor.rb
class MessageProcessor
  def initialize(session_id, persona)
    @session_id = session_id
    @persona = persona
  end
  
  def process(message, context)
    # ONLY handles the core flow - no side effects
    session = load_session
    prompt = build_prompt(context)
    response = call_llm(message, prompt, session.messages)
    session.add_message(message, response)
    
    # Return structured result
    {
      response: response.response_text,
      session_id: @session_id,
      persona: @persona,
      llm_response: response
    }
  end
  
  private
  
  def load_session
    Services::ConversationSession.find_or_create(
      session_id: @session_id,
      context: { persona: @persona }
    )
  end
  
  def build_prompt(context)
    Services::SystemPromptService.new(
      character: @persona,
      context: context
    ).generate
  end
  
  def call_llm(message, prompt, history)
    Services::LLMService.complete_with_messages(
      messages: build_message_array(message, prompt, history),
      model: determine_model
    )
  end
end
2. Extract Side Effects into Separate Handlers
ruby# lib/conversation/side_effect_processor.rb
class SideEffectProcessor
  def process(result, context)
    # All the side effects that happen AFTER message processing
    execute_tools(result, context) if should_execute_tools?
    update_displays(result, context)
    execute_feedback(result, context)
    log_interaction(result, context)
  end
  
  private
  
  def execute_tools(result, context)
    return unless result[:llm_response].has_tool_calls?
    
    ToolOrchestrator.new.execute(
      result[:llm_response].tool_calls,
      context
    )
  end
  
  def update_displays(result, context)
    DisplayManager.new.update_all(
      message: context[:original_message],
      response: result[:response],
      persona: result[:persona]
    )
  end
  
  def execute_feedback(result, context)
    FeedbackManager.new.execute(
      result[:response],
      result[:persona]
    )
  end
  
  def log_interaction(result, context)
    Services::LoggerService.log_interaction(
      user_message: context[:original_message],
      ai_response: result[:response],
      persona: result[:persona],
      session_id: result[:session_id],
      context: context
    )
  end
end
3. Extract Tool Management
ruby# lib/conversation/tool_orchestrator.rb
class ToolOrchestrator
  def execute(tool_calls, context)
    # Pure tool execution logic
    tool_calls.map do |tool_call|
      execute_single_tool(tool_call, context)
    end
  end
  
  private
  
  def execute_single_tool(tool_call, context)
    Services::ToolExecutor.new.execute(
      tool_call,
      context
    )
  end
end
4. Extract Display Management
ruby# lib/conversation/display_manager.rb
class DisplayManager
  def update_all(message:, response:, persona:)
    # All display updates in one place
    update_awtrix(message, response, persona)
    update_kiosk(response, persona) if kiosk_enabled?
  end
  
  private
  
  def update_awtrix(message, response, persona)
    return unless awtrix_configured?
    
    color = persona_color(persona)
    display_text = truncate_for_display(response)
    
    ha_client.awtrix_display_text(display_text, color: color)
    ha_client.awtrix_mood_light(color)
  end
  
  def update_kiosk(response, persona)
    Services::KioskService.update_mood(persona)
    Services::KioskService.update_interaction(response)
  end
  
  def ha_client
    @ha_client ||= HomeAssistantClient.new
  end
end
5. New Simplified ConversationModule
ruby# lib/modules/conversation_module.rb
class ConversationModule
  def initialize(persona: 'buddy')
    @persona = persona
  end

  def call(message:, context: {}, persona: nil)
    effective_persona = persona || context[:persona] || @persona
    session_id = context[:session_id] || SecureRandom.uuid
    
    # Enrich context if needed
    enriched_context = enrich_context(context.merge(
      original_message: message,
      session_id: session_id,
      persona: effective_persona
    ))
    
    # Process the core message
    result = MessageProcessor.new(session_id, effective_persona)
                            .process(message, enriched_context)
    
    # Handle all side effects
    SideEffectProcessor.new.process(result, enriched_context)
    
    # Return clean result
    {
      response: result[:response],
      persona: result[:persona],
      session_id: result[:session_id],
      conversation_id: result[:session_id]
    }
  rescue StandardError => e
    handle_error(e, message, context)
  end
  
  private
  
  def enrich_context(context)
    # Only if needed
    if context[:include_sensors]
      context = ConversationEnhancements.enrich_context_with_sensors(context)
    end
    context
  end
  
  def handle_error(error, message, context)
    Services::LoggerService.track_error('ConversationModule', error.message)
    
    {
      response: "I encountered an issue processing that. Could you try again?",
      persona: 'neutral',
      error: 'general_error'
    }
  end
end
6. Kill ConversationService Entirely
Just delete it. Seriously. It adds nothing. If you need context management, do it in the calling code or create a proper ConversationManager that actually manages multiple conversations. But we dont have multiple convos at onve, its one cube one mic. KISS.

--


TIGHT REFACTOR PLAN 🎯
Chunk 1: Nuke AWTRIX Display Logic
DELETE:

update_awtrix_display method from ConversationEnhancements
All AWTRIX calls in ConversationModule (execute_display_tool, kiosk fallbacks)
Any AWTRIX-related tests

KEEP:

Basic conversation state feedback (listening/thinking/speaking)

Files to modify:
lib/modules/conversation_enhancements.rb - DELETE update_awtrix_display 
lib/modules/conversation_module.rb - DELETE execute_display_tool calls
spec/modules/conversation_module_enhanced_spec.rb - DELETE AWTRIX test sections
Test fix strategy: Remove AWTRIX expectations, keep basic conversation flow tests

Chunk 2: Simplify LED Feedback
REPLACE:
ruby# OLD - complex tool execution
execute_feedback_tool(:listening, context)

# NEW - direct service call  
Services::ConversationFeedbackService.new.set_state(:listening)
DELETE:

execute_feedback_tool method
LED tool execution logic
Persona color mapping (persona_to_color)

Files to modify:
lib/modules/conversation_module.rb - Replace feedback calls with direct service
spec/modules/conversation_module_spec.rb - Update expectations to ConversationFeedbackService

Chunk 3: Clean Up Tool Execution Methods
DELETE:

execute_speech_tool (replace with direct tool calls)
execute_tool_call helper
tool_available? helper
extract_tool_names_from_response

REPLACE with:

Direct Services::ToolExecutor.execute() calls where needed

Files to modify:
lib/modules/conversation_module.rb - Remove tool helper methods

Chunk 4: Remove ConversationEnhancements Include
DELETE:

include ConversationEnhancements
Any sensor enrichment calls (move to explicit context building)

Files to modify:
lib/modules/conversation_module.rb - Remove include, inline any needed logic
lib/modules/conversation_enhancements.rb - DELETE entire file  
spec/modules/conversation_enhancements_spec.rb - DELETE entire file

The Execution Order:
bash# Chunk 1 - Kill AWTRIX 
git checkout -b refactor/kill-awtrix
# Remove AWTRIX, fix tests, commit

# Chunk 2 - Simplify LEDs
git checkout -b refactor/simplify-leds  
# Replace LED logic, fix tests, commit

# Chunk 3 - Clean tool helpers
git checkout -b refactor/clean-tools
# Remove tool helpers, fix tests, commit

# Chunk 4 - Kill enhancements
git checkout -b refactor/kill-enhancements
# Remove include, delete file, fix tests, commit
Test Strategy Per Chunk:
Chunk 1: Remove AWTRIX test expectations, keep conversation flow
Chunk 2: Mock ConversationFeedbackService instead of tool execution
Chunk 3: Test direct ToolExecutor calls instead of helpers
Chunk 4: Move any needed sensor tests to integration level
Target End State:
rubyclass ConversationModule
  def call(message:, context: {}, persona: nil)
    # Simple state feedback
    Services::ConversationFeedbackService.new.set_state(:listening)
    
    # Core conversation logic
    result = process_conversation(message, context, persona)
    
    # State feedback
    Services::ConversationFeedbackService.new.set_state(:completed)
    
    result
  end
  
  private
  
  def process_conversation(message, context, persona)
    # Clean conversation processing - no display/LED logic
  end
end

BE RUTHLESS, THINK OF SANDI METZ, MOVE QUICKLY DELETE UNUSD CODE KEEP TESTS GREEN, DELETE TEST WE DONT NEED, FIX OTHER ONES

It's not a complicated refactor its just clean up! Tight loops so you don't get lost and ask zenchat for a codereview at any time to help you back on track.