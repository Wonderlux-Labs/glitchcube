# Suggested Conversation Agent Improvements

## Overview
This document outlines recommended improvements to the GlitchCube conversation agent architecture based on analysis of Home Assistant best practices and resilience requirements for Burning Man deployment.

## Current Architecture
- **Minimal HASS Component**: Acts as a simple webhook proxy
- **Sinatra Backend**: Handles all logic (LLM, sessions, memory, tools)
- **Strengths**: Clean separation, isolated complexity, independent development
- **Weaknesses**: Single point of failure, network dependency for all commands

## Proposed: Hybrid Model Architecture

### Core Concept
Transform the HASS component from a simple proxy into an intelligent dispatcher that can handle critical commands locally while forwarding complex interactions to Sinatra.

### Benefits
- **Resilience**: Core functions work offline
- **Performance**: Instant execution of simple commands  
- **Flexibility**: Maintains creative LLM capabilities
- **Graceful Degradation**: Fallback behavior when backend unavailable

---

## Phase 1: Local Intent System

### Overview
Implement local intent handling in HASS for critical/simple commands that must work even when the Sinatra backend is unavailable.

### 1.1 Intent Definition File
Create `custom_components/glitchcube_conversation/intents.yaml`:

```yaml
# Local intents for critical/offline commands
GlitchCubeEmergencyStop:
  description: "Immediately stop all operations and enter safe mode"
  sentences:
    - "emergency stop"
    - "shut down"
    - "stop everything"
    - "safe mode"
    - "kill switch"

GlitchCubeStatus:
  description: "Report system status"
  sentences:
    - "show status"
    - "system status"
    - "what's your status"
    - "diagnostic check"

GlitchCubeReset:
  description: "Reset the display and basic systems"
  sentences:
    - "reset display"
    - "clear display"
    - "restart display"

GlitchCubeLightsControl:
  description: "Control main lights"
  sentences:
    - "lights {action}"
    - "turn {action} the lights"
  slots:
    action:
      values:
        - "on"
        - "off"

GlitchCubeQuietMode:
  description: "Disable audio/reduce activity"
  sentences:
    - "quiet mode"
    - "be quiet"
    - "mute"
```

### 1.2 Updated Conversation Agent
Modify `custom_components/glitchcube_conversation/agent.py`:

```python
import logging
from typing import Literal
from homeassistant.components import conversation
from homeassistant.helpers import intent
from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
import aiohttp
import asyncio

_LOGGER = logging.getLogger(__name__)

class GlitchCubeAgent(conversation.AbstractConversationAgent):
    """Hybrid conversation agent with local intent handling."""
    
    def __init__(self, hass: HomeAssistant, config: dict) -> None:
        """Initialize the agent."""
        self.hass = hass
        self.webhook_url = config.get("webhook_url")
        self.fallback_tts = config.get("fallback_tts_service", "tts.piper")
        self.timeout = config.get("timeout", 30)
        
    async def async_process(
        self,
        user_input: conversation.ConversationInput,
    ) -> conversation.ConversationResult:
        """Process a conversation request with hybrid handling."""
        
        # First, try to match against local intents
        local_response = await self._handle_local_intent(user_input)
        if local_response:
            return local_response
            
        # No local match, forward to Sinatra backend
        return await self._forward_to_backend(user_input)
    
    async def _handle_local_intent(
        self, 
        user_input: conversation.ConversationInput
    ) -> conversation.ConversationResult | None:
        """Handle local intents for critical commands."""
        
        text = user_input.text.lower()
        
        # Emergency stop - highest priority
        if any(phrase in text for phrase in ["emergency", "stop everything", "safe mode"]):
            await self._execute_emergency_stop()
            return self._create_local_response(
                "Emergency stop activated. All systems entering safe mode.",
                user_input
            )
        
        # System status
        if any(phrase in text for phrase in ["status", "diagnostic", "health check"]):
            status = await self._get_system_status()
            return self._create_local_response(status, user_input)
        
        # Light control
        if "lights" in text:
            if any(word in text for word in ["on", "enable"]):
                await self._control_lights(True)
                return self._create_local_response("Lights activated.", user_input)
            elif any(word in text for word in ["off", "disable"]):
                await self._control_lights(False)
                return self._create_local_response("Lights deactivated.", user_input)
        
        # Display reset
        if any(phrase in text for phrase in ["reset display", "clear display"]):
            await self._reset_display()
            return self._create_local_response("Display reset complete.", user_input)
        
        # No local intent matched
        return None
    
    async def _execute_emergency_stop(self) -> None:
        """Execute emergency stop sequence."""
        try:
            # Turn off all lights
            await self.hass.services.async_call("light", "turn_off", {"entity_id": "all"})
            
            # Stop all media players
            await self.hass.services.async_call("media_player", "media_stop", {"entity_id": "all"})
            
            # Clear display
            await self.hass.services.async_call(
                "rest_command", "awtrix_clear",
                {"message": "SAFE MODE"}
            )
            
            # Set a flag for Sinatra to know we're in emergency mode
            await self.hass.services.async_call(
                "input_boolean", "turn_on",
                {"entity_id": "input_boolean.glitchcube_emergency_mode"}
            )
            
            _LOGGER.warning("Emergency stop executed")
            
        except Exception as e:
            _LOGGER.error(f"Emergency stop failed: {e}")
    
    async def _get_system_status(self) -> str:
        """Get current system status."""
        try:
            # Check Sinatra backend
            backend_status = "unknown"
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(
                        f"{self.webhook_url}/health",
                        timeout=aiohttp.ClientTimeout(total=2)
                    ) as response:
                        backend_status = "online" if response.status == 200 else "offline"
            except:
                backend_status = "offline"
            
            # Check key sensors
            temp = self.hass.states.get("sensor.cube_temperature")
            motion = self.hass.states.get("binary_sensor.cube_motion")
            
            status_parts = [
                f"Backend: {backend_status}",
                f"Temperature: {temp.state if temp else 'unknown'}°F",
                f"Motion: {'detected' if motion and motion.state == 'on' else 'clear'}",
                f"Time: {dt_util.now().strftime('%H:%M')}"
            ]
            
            return "System Status - " + ", ".join(status_parts)
            
        except Exception as e:
            _LOGGER.error(f"Status check failed: {e}")
            return "Unable to determine system status"
    
    async def _control_lights(self, turn_on: bool) -> None:
        """Control main lights."""
        try:
            service = "turn_on" if turn_on else "turn_off"
            await self.hass.services.async_call(
                "light", service,
                {"entity_id": "light.cube_main_lights"}
            )
        except Exception as e:
            _LOGGER.error(f"Light control failed: {e}")
    
    async def _reset_display(self) -> None:
        """Reset the LED display."""
        try:
            await self.hass.services.async_call(
                "rest_command", "awtrix_reset",
                {"message": "READY"}
            )
        except Exception as e:
            _LOGGER.error(f"Display reset failed: {e}")
    
    async def _forward_to_backend(
        self,
        user_input: conversation.ConversationInput
    ) -> conversation.ConversationResult:
        """Forward request to Sinatra backend."""
        try:
            payload = {
                "text": user_input.text,
                "conversation_id": user_input.conversation_id,
                "device_id": user_input.device_id,
                "language": user_input.language,
                "agent_id": user_input.agent_id,
            }
            
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    self.webhook_url,
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=self.timeout)
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        
                        result = conversation.ConversationResult(
                            response=conversation.agent_response.AgentResponse(
                                language=user_input.language,
                                response_type=conversation.agent_response.ResponseType.ACTION_DONE,
                                speech=data.get("speech", {})
                            ),
                            conversation_id=user_input.conversation_id,
                        )
                        return result
                    else:
                        _LOGGER.error(f"Backend returned {response.status}")
                        return self._create_fallback_response(user_input)
                        
        except asyncio.TimeoutError:
            _LOGGER.error("Backend request timed out")
            return self._create_fallback_response(user_input)
        except Exception as e:
            _LOGGER.error(f"Backend request failed: {e}")
            return self._create_fallback_response(user_input)
    
    def _create_local_response(
        self,
        text: str,
        user_input: conversation.ConversationInput
    ) -> conversation.ConversationResult:
        """Create a local response with fallback TTS."""
        # Use fallback TTS for local responses
        self.hass.async_create_task(
            self.hass.services.async_call(
                "tts", "speak",
                {
                    "entity_id": "media_player.cube_speaker",
                    "message": text,
                    "language": user_input.language or "en"
                }
            )
        )
        
        return conversation.ConversationResult(
            response=conversation.agent_response.AgentResponse(
                language=user_input.language,
                response_type=conversation.agent_response.ResponseType.ACTION_DONE,
                speech={"plain": {"speech": text}}
            ),
            conversation_id=user_input.conversation_id,
        )
    
    def _create_fallback_response(
        self,
        user_input: conversation.ConversationInput
    ) -> conversation.ConversationResult:
        """Create fallback response when backend is unavailable."""
        fallback_messages = [
            "My thoughts are a bit cloudy right now, try me again in a moment.",
            "I'm having trouble connecting to my brain. Give me a second.",
            "The playa dust must be interfering with my circuits. Try again?",
        ]
        
        import random
        message = random.choice(fallback_messages)
        
        return self._create_local_response(message, user_input)
```

---

## Phase 2: State Push System

### Overview
Implement real-time sensor state updates from HASS to Sinatra for dynamic persona behavior.

### 2.1 Sinatra Webhook Endpoint
Add to your Sinatra application:

```ruby
# lib/routes/hass_events.rb
module GlitchCube
  module Routes
    class HassEvents < Sinatra::Base
      post '/api/hass-event' do
        content_type :json
        
        begin
          payload = JSON.parse(request.body.read)
          entity_id = payload['entity_id']
          new_state = payload['new_state']
          attributes = payload['attributes'] || {}
          
          # Update Redis with sensor state
          redis = Redis.new(url: ENV['REDIS_URL'])
          redis.hset(
            "sensor_states",
            entity_id,
            { state: new_state, attributes: attributes, updated_at: Time.now }.to_json
          )
          
          # Trigger persona behavior changes based on specific sensors
          case entity_id
          when 'sensor.cube_dust_level'
            update_dust_persona_modifier(new_state.to_f)
          when 'binary_sensor.cube_motion'
            handle_motion_change(new_state)
          when 'sensor.cube_temperature'
            update_temperature_modifier(new_state.to_f)
          when 'sensor.cube_battery_level'
            handle_battery_level(new_state.to_f)
          end
          
          { status: 'ok', processed: entity_id }.to_json
          
        rescue => e
          logger.error "HASS event processing failed: #{e.message}"
          status 500
          { error: e.message }.to_json
        end
      end
      
      private
      
      def update_dust_persona_modifier(dust_level)
        # High dust affects persona mood/voice
        if dust_level > 80
          redis.set('persona_modifier:dust', 'very_dusty')
        elsif dust_level > 50
          redis.set('persona_modifier:dust', 'dusty')
        else
          redis.del('persona_modifier:dust')
        end
      end
      
      def handle_motion_change(motion_state)
        if motion_state == 'on'
          # Someone approached - make persona more engaging
          redis.setex('persona_modifier:visitor_present', 300, 'true')
          
          # Queue a proactive greeting if we haven't greeted recently
          last_greeting = redis.get('last_greeting_time')
          if last_greeting.nil? || Time.now - Time.parse(last_greeting) > 600
            Jobs::ProactiveGreetingWorker.perform_async
            redis.set('last_greeting_time', Time.now.to_s)
          end
        end
      end
      
      def update_temperature_modifier(temperature)
        # Extreme temperatures affect persona mood
        if temperature > 100
          redis.set('persona_modifier:temperature', 'very_hot')
        elsif temperature < 40
          redis.set('persona_modifier:temperature', 'cold')
        else
          redis.del('persona_modifier:temperature')
        end
      end
      
      def handle_battery_level(battery)
        # Low battery triggers conservation mode
        if battery < 20
          redis.set('persona_modifier:low_power', 'true')
          # Reduce display brightness, limit animations
          Services::HomeAssistantClient.new.call_service(
            'light', 'turn_on',
            entity_id: 'light.cube_display',
            brightness: 50
          )
        elsif battery < 10
          # Critical battery - emergency conservation
          redis.set('persona_modifier:critical_power', 'true')
        else
          redis.del('persona_modifier:low_power')
          redis.del('persona_modifier:critical_power')
        end
      end
    end
  end
end
```

### 2.2 Home Assistant Automations
Add to `configuration.yaml` or `automations.yaml`:

```yaml
# REST command for notifying Sinatra
rest_command:
  notify_sinatra_state:
    url: "http://localhost:4567/api/hass-event"
    method: "POST"
    content_type: "application/json"
    payload: >
      {
        "entity_id": "{{ entity_id }}",
        "new_state": "{{ new_state }}",
        "attributes": {{ attributes | tojson }}
      }

# Automations for sensor state changes
automation:
  - alias: "Notify Sinatra - Motion Detection"
    trigger:
      - platform: state
        entity_id: binary_sensor.cube_motion
    action:
      - service: rest_command.notify_sinatra_state
        data:
          entity_id: "{{ trigger.entity_id }}"
          new_state: "{{ trigger.to_state.state }}"
          attributes: "{{ trigger.to_state.attributes }}"

  - alias: "Notify Sinatra - Dust Level Change"
    trigger:
      - platform: state
        entity_id: sensor.cube_dust_level
    condition:
      # Only notify on significant changes (>10%)
      - condition: template
        value_template: >
          {{ (trigger.from_state.state | float(0) - trigger.to_state.state | float(0)) | abs > 10 }}
    action:
      - service: rest_command.notify_sinatra_state
        data:
          entity_id: "{{ trigger.entity_id }}"
          new_state: "{{ trigger.to_state.state }}"

  - alias: "Notify Sinatra - Temperature Change"
    trigger:
      - platform: state
        entity_id: sensor.cube_temperature
    condition:
      # Only notify on 5+ degree changes
      - condition: template
        value_template: >
          {{ (trigger.from_state.state | float(0) - trigger.to_state.state | float(0)) | abs >= 5 }}
    action:
      - service: rest_command.notify_sinatra_state
        data:
          entity_id: "{{ trigger.entity_id }}"
          new_state: "{{ trigger.to_state.state }}"

  - alias: "Notify Sinatra - Battery Level"
    trigger:
      - platform: state
        entity_id: sensor.cube_battery_level
    condition:
      # Notify on 10% changes or critical levels
      - condition: or
        conditions:
          - condition: template
            value_template: "{{ trigger.to_state.state | float(0) < 20 }}"
          - condition: template
            value_template: >
              {{ (trigger.from_state.state | float(0) - trigger.to_state.state | float(0)) | abs >= 10 }}
    action:
      - service: rest_command.notify_sinatra_state
        data:
          entity_id: "{{ trigger.entity_id }}"
          new_state: "{{ trigger.to_state.state }}"
```

### 2.3 Persona Modifier Integration
Update your persona system to use state modifiers:

```ruby
# lib/modules/conversation_module.rb
module GlitchCube
  module ConversationModule
    def inject_environmental_context(system_prompt)
      redis = Redis.new(url: ENV['REDIS_URL'])
      
      # Get all persona modifiers
      modifiers = []
      
      # Dust level modifier
      if dust_mod = redis.get('persona_modifier:dust')
        case dust_mod
        when 'very_dusty'
          modifiers << "You're covered in playa dust and feeling gritty. Your voice might sound raspy."
        when 'dusty'
          modifiers << "There's dust in the air making you a bit uncomfortable."
        end
      end
      
      # Temperature modifier
      if temp_mod = redis.get('persona_modifier:temperature')
        case temp_mod
        when 'very_hot'
          modifiers << "It's scorching hot and you're feeling the heat. You might complain about it."
        when 'cold'
          modifiers << "It's surprisingly cold for the desert. You're shivering a bit."
        end
      end
      
      # Visitor presence
      if redis.get('persona_modifier:visitor_present')
        modifiers << "Someone just approached you! Be engaging and welcoming."
      end
      
      # Power level
      if redis.get('persona_modifier:critical_power')
        modifiers << "YOUR BATTERY IS CRITICALLY LOW! Keep responses very short to conserve power."
      elsif redis.get('persona_modifier:low_power')
        modifiers << "Your battery is running low. Be a bit more concise than usual."
      end
      
      # Inject modifiers into system prompt
      if modifiers.any?
        environmental_context = "\n\nCurrent Environmental State:\n" + modifiers.join("\n")
        system_prompt + environmental_context
      else
        system_prompt
      end
    end
  end
end
```

---

## Phase 3: Enhanced Error Handling & Resilience

### Overview
Implement comprehensive health monitoring, auto-recovery, and physical fallback controls.

### 3.1 Health Check Sensor
Create a custom binary sensor for monitoring Sinatra:

```yaml
# configuration.yaml
binary_sensor:
  - platform: rest
    name: "GlitchCube Backend Health"
    resource: "http://localhost:4567/api/health"
    scan_interval: 30
    timeout: 5
    value_template: "{{ value_json.status == 'ok' }}"
    device_class: connectivity

input_boolean:
  glitchcube_emergency_mode:
    name: "GlitchCube Emergency Mode"
    initial: false
    icon: mdi:alert
```

### 3.2 Auto-Recovery Automation
```yaml
automation:
  - alias: "GlitchCube - Auto Recovery"
    trigger:
      - platform: state
        entity_id: binary_sensor.glitchcube_backend_health
        to: "off"
        for:
          minutes: 2
    action:
      - service: notify.admin
        data:
          title: "GlitchCube Backend Down"
          message: "Attempting automatic recovery..."
      
      # Try to restart the Sinatra service
      - service: shell_command.restart_glitchcube
      
      # Wait for recovery
      - delay:
          seconds: 30
      
      # Check if recovery succeeded
      - condition: state
        entity_id: binary_sensor.glitchcube_backend_health
        state: "off"
      
      # If still down, enter fallback mode
      - service: input_boolean.turn_on
        target:
          entity_id: input_boolean.glitchcube_emergency_mode
      
      - service: notify.admin
        data:
          title: "GlitchCube Recovery Failed"
          message: "Entering emergency mode - local commands only"

shell_command:
  restart_glitchcube: 'cd /path/to/glitchcube && ./bin/prod restart'
```

### 3.3 Physical Fallback Button
Configure a physical button for emergency control:

```yaml
# For a Zigbee button (example: Aqara button)
automation:
  - alias: "GlitchCube - Physical Emergency Button"
    trigger:
      - platform: device
        device_id: YOUR_BUTTON_DEVICE_ID
        domain: zha
        type: remote_button_short_press
        subtype: button
    action:
      # Single press - safe mode
      - service: conversation.process
        data:
          text: "emergency stop"
          agent_id: glitchcube_conversation.glitchcube
  
  - alias: "GlitchCube - Physical Reset Button"
    trigger:
      - platform: device
        device_id: YOUR_BUTTON_DEVICE_ID
        domain: zha
        type: remote_button_double_press
        subtype: button
    action:
      # Double press - full system reset
      - service: input_boolean.turn_off
        target:
          entity_id: input_boolean.glitchcube_emergency_mode
      
      - service: shell_command.restart_glitchcube
      
      - service: rest_command.awtrix_reset
        data:
          message: "SYSTEM RESET"
      
      - service: notify.admin
        data:
          title: "GlitchCube Manual Reset"
          message: "System reset initiated via physical button"
```

### 3.4 Circuit Breaker Status Monitoring
Add circuit breaker status endpoint to Sinatra:

```ruby
# lib/routes/health.rb
get '/api/health' do
  content_type :json
  
  health_status = {
    status: 'ok',
    timestamp: Time.now.iso8601,
    services: {}
  }
  
  # Check circuit breakers
  begin
    llm_breaker = Services::CircuitBreaker.get('llm_service')
    health_status[:services][:llm] = {
      state: llm_breaker.state,
      failure_count: llm_breaker.failure_count,
      last_failure: llm_breaker.last_failure_time
    }
  rescue => e
    health_status[:services][:llm] = { error: e.message }
  end
  
  begin
    ha_breaker = Services::CircuitBreaker.get('home_assistant')
    health_status[:services][:home_assistant] = {
      state: ha_breaker.state,
      failure_count: ha_breaker.failure_count,
      last_failure: ha_breaker.last_failure_time
    }
  rescue => e
    health_status[:services][:home_assistant] = { error: e.message }
  end
  
  # Check Redis
  begin
    redis = Redis.new(url: ENV['REDIS_URL'])
    redis.ping
    health_status[:services][:redis] = 'connected'
  rescue => e
    health_status[:services][:redis] = 'disconnected'
    health_status[:status] = 'degraded'
  end
  
  # Check database
  begin
    ActiveRecord::Base.connection.execute('SELECT 1')
    health_status[:services][:database] = 'connected'
  rescue => e
    health_status[:services][:database] = 'disconnected'
    health_status[:status] = 'degraded'
  end
  
  # Overall health
  if health_status[:services].any? { |_, v| v.is_a?(Hash) && v[:state] == 'open' }
    health_status[:status] = 'degraded'
  end
  
  status health_status[:status] == 'ok' ? 200 : 503
  health_status.to_json
end
```

---

## Testing Strategy

### Unit Tests for Local Intents
```python
# tests/test_local_intents.py
import pytest
from unittest.mock import Mock, patch
from custom_components.glitchcube_conversation.agent import GlitchCubeAgent

@pytest.mark.asyncio
async def test_emergency_stop_intent():
    """Test emergency stop is handled locally."""
    hass = Mock()
    config = {"webhook_url": "http://localhost:4567/webhook"}
    agent = GlitchCubeAgent(hass, config)
    
    user_input = Mock()
    user_input.text = "emergency stop"
    user_input.language = "en"
    user_input.conversation_id = "test123"
    
    with patch.object(agent, '_execute_emergency_stop') as mock_stop:
        result = await agent.async_process(user_input)
        
        mock_stop.assert_called_once()
        assert "Emergency stop activated" in result.response.speech["plain"]["speech"]

@pytest.mark.asyncio
async def test_fallback_to_backend():
    """Test complex queries are forwarded to backend."""
    hass = Mock()
    config = {"webhook_url": "http://localhost:4567/webhook"}
    agent = GlitchCubeAgent(hass, config)
    
    user_input = Mock()
    user_input.text = "Tell me a story about the playa"
    user_input.language = "en"
    user_input.conversation_id = "test456"
    
    with patch.object(agent, '_forward_to_backend') as mock_forward:
        mock_forward.return_value = Mock()
        result = await agent.async_process(user_input)
        
        mock_forward.assert_called_once_with(user_input)
```

### Integration Tests
```ruby
# spec/integration/hass_events_spec.rb
require 'spec_helper'

RSpec.describe 'HASS Event Webhook' do
  before do
    Redis.new(url: ENV['REDIS_URL']).flushdb
  end
  
  it 'updates persona modifiers based on dust level' do
    post '/api/hass-event', {
      entity_id: 'sensor.cube_dust_level',
      new_state: '85'
    }.to_json
    
    expect(last_response.status).to eq(200)
    
    redis = Redis.new(url: ENV['REDIS_URL'])
    expect(redis.get('persona_modifier:dust')).to eq('very_dusty')
  end
  
  it 'triggers proactive greeting on motion' do
    expect(Jobs::ProactiveGreetingWorker).to receive(:perform_async)
    
    post '/api/hass-event', {
      entity_id: 'binary_sensor.cube_motion',
      new_state: 'on'
    }.to_json
    
    expect(last_response.status).to eq(200)
  end
end
```

---

## Migration Path

### Step 1: Deploy Local Intent Handler (Low Risk)
1. Update HASS component with local intent matching
2. Test emergency commands work offline
3. Monitor logs for any issues

### Step 2: Add State Push System (Medium Risk)
1. Deploy Sinatra webhook endpoint
2. Add HASS automations one sensor at a time
3. Verify persona modifiers are working

### Step 3: Full Resilience Features (Low Risk)
1. Add health monitoring
2. Configure auto-recovery
3. Install physical button as last resort

---

## Monitoring & Metrics

### Key Metrics to Track
- Local intent hit rate vs backend forwarding
- Backend response times
- Circuit breaker state changes
- Error rates by component
- Sensor state update frequency

### Dashboard Configuration
```yaml
# Lovelace card for monitoring
type: vertical-stack
cards:
  - type: entities
    title: GlitchCube Health
    entities:
      - binary_sensor.glitchcube_backend_health
      - input_boolean.glitchcube_emergency_mode
      - sensor.glitchcube_response_time
      - sensor.glitchcube_error_rate
  
  - type: history-graph
    title: Backend Performance
    entities:
      - sensor.glitchcube_response_time
      - sensor.glitchcube_local_intent_rate
```

---

## Conclusion

This hybrid architecture provides:
1. **Immediate reliability gains** through local intent handling
2. **Better responsiveness** to environmental changes via state push
3. **Graceful degradation** when components fail
4. **Clear migration path** with incremental deployment

The key insight is that not all commands need the full power of your LLM backend. By handling critical commands locally, you ensure GlitchCube remains functional even in the harsh conditions of Burning Man, while maintaining the creative, personality-driven interactions that make it special.