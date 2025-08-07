# Existing Services and Hardware Integrations

## Overview

This document catalogs all existing services and their integrations with Home Assistant entities, providing a foundation for building new interactive features like the LightingOrchestrator and MoodAnalyzer services.

## 🎭 TTS Service - Advanced Mood-Based Speech

**File**: `lib/services/tts_service.rb`

### Capabilities
- **15+ Mood-based voices** with emotional variants
- **Speed adjustment** based on mood (excited=110%, sad=90%)
- **Multiple TTS providers** (Cloud, Google, Piper, ElevenLabs, Chime)
- **Voice style variants** (whispering, shouting, friendly, angry, etc.)

### Available Moods
```ruby
MOOD_TO_VOICE_SUFFIX = {
  # Emotional states
  friendly: 'friendly',
  angry: 'angry', 
  sad: 'sad',
  excited: 'excited',
  cheerful: 'cheerful',
  terrified: 'terrified',
  hopeful: 'hopeful',
  
  # Speaking styles  
  whisper: 'whispering',
  shouting: 'shouting',
  unfriendly: 'unfriendly',
  
  # Professional styles
  assistant: 'assistant',
  chat: 'chat',
  customerservice: 'customerservice',
  newscast: 'newscast'
}
```

### Home Assistant Integration
- **Primary**: `script.glitchcube_tts` - Custom TTS pipeline with mood support
- **Fallbacks**: `tts.cloud_say`, `tts.google_translate_say`
- **Target Entity**: `media_player.tablet` (confirmed available)

### Usage Examples
```ruby
tts = Services::TTSService.new

# Mood-based speech
tts.speak("Hello there!", mood: :friendly)
tts.speak("I'm so excited!", mood: :excited) 
tts.whisper("This is a secret")

# Convenience methods
tts.speak_friendly("Welcome!")
tts.speak_excited("Amazing news!")
tts.speak_sad("I'm feeling down")
```

## 🖥️ AWTRIX LED Matrix Display System

**File**: `lib/home_assistant_client.rb` (methods: `awtrix_*`)

### Display Hardware Available
- **`light.awtrix_b85e20_matrix`** - 32x8 RGB LED matrix display
- **`light.awtrix_b85e20_indicator_1/2/3`** - Individual RGB status indicators

### Display Capabilities

#### Text Display
```ruby
home_assistant.awtrix_display_text(
  "Hello World",
  app_name: 'glitchcube',
  color: '#00FF00',      # Green text
  duration: 10,          # 10 seconds
  rainbow: true,         # Rainbow text effect
  icon: '1234'          # Icon ID or base64 8x8 image
)
```

#### Notifications
```ruby
home_assistant.awtrix_notify(
  "Alert!",
  color: '#FF0000',      # Red text
  duration: 8,
  sound: 'alarm',        # RTTTL or MP3 filename
  wakeup: true,         # Turn on if sleeping
  stack: true           # Allow multiple notifications
)
```

#### Mood Lighting
```ruby
home_assistant.awtrix_mood_light('#FF00FF', brightness: 150)
```

#### Clear Display
```ruby
home_assistant.awtrix_clear_display
```

### Home Assistant Scripts
- **`script.awtrix_send_custom_app`** - Display custom text/apps
- **`script.awtrix_send_notification`** - Send notifications with sounds
- **`script.awtrix_clear_display`** - Clear all custom apps
- **`script.awtrix_set_mood_light`** - Control mood lighting

### MQTT Topics (for direct control if needed)
- `marquee/custom/{app_name}` - Custom apps
- `marquee/notify` - Notifications  
- `marquee/moodlight` - Mood lighting

## 💡 RGB Lighting Hardware Available

### Confirmed RGB-Capable Entities
1. **`light.home_assistant_voice_09739d_led_ring`** - RGB LED ring
   - **Modes**: `rgb`
   - **Use case**: Voice interaction feedback, conversation mood indication

2. **`light.awtrix_b85e20_matrix`** - Main LED matrix display  
   - **Modes**: `rgb`
   - **Use case**: Text display + background mood lighting

3. **`light.awtrix_b85e20_indicator_1/2/3`** - Status indicators
   - **Modes**: `rgb` 
   - **Use case**: Multi-color status indication, breathing effects

4. **`light.cube_light`** - Primary cube lighting
   - **Modes**: `color_temp`, `rgb`
   - **Use case**: Main ambient mood lighting

5. **`light.cart_light`** - Secondary/cart lighting
   - **Modes**: `color_temp`, `rgb`
   - **Use case**: Environmental/area mood lighting

### Basic Light Control Methods
```ruby
# HomeAssistantClient methods
home_assistant.turn_on_light('light.cube_light', 
  brightness: 200, 
  rgb_color: [255, 0, 128]  # Hot pink
)

home_assistant.turn_off_light('light.cube_light')
```

## 🎯 Motion Detection System

### Available Motion Entities
- **`input_boolean.motion_detected`** - Main motion trigger (ready for automation)
- **`automation.camera_motion_vision_analysis`** - Camera-based motion detection  
- **`select.camera_motion_detection_sensitivity`** - Motion sensitivity control
- **`switch.camera_motion_alarm`** - Motion alarm toggle

### Integration Ready
Motion detection is already configured to work with the conversation system through Home Assistant automations.

## 🏠 Kiosk Service - State Management

**File**: `lib/services/kiosk_service.rb`

### Current Capabilities
- **Mood tracking** - `current_mood`, `update_mood(new_mood)`
- **Interaction logging** - `last_interaction`, `update_interaction(data)`
- **Inner thoughts** - `inner_thoughts`, `add_inner_thought(thought)`
- **Environmental data** - Temperature, weather, system stats

### State Management
```ruby
# Current usage
Services::KioskService.update_mood(:excited)
Services::KioskService.current_mood # => :excited

Services::KioskService.add_inner_thought("User seems curious about art")
Services::KioskService.inner_thoughts # => Array of thoughts
```

## 🔊 Audio Hardware

### Media Player Entities Available  
- **`media_player.tablet`** - Primary TTS output (confirmed working)
- **`media_player.tablet_2`** - Secondary audio device

## 🌡️ Environmental Sensors

### Available Sensor Data
Based on entity scan, we have rich environmental data available:
- **Weather sensors** - `weather.openweathermap`, `weather.forecast_home`
- **System monitoring** - CPU, memory, temperature sensors (355 sensor entities total)
- **Custom weather storage** - `input_text.current_weather`

## 📷 Camera Integration

### Camera Hardware
- **`camera.tablet`** - Available for visitor recognition, visual input

## 🔄 Background Jobs & Automation

### Existing Job Infrastructure  
- **Sidekiq job system** - Already configured and running
- **Cron scheduling** - Via `config/sidekiq_cron.yml`
- **Memory consolidation** - `PersonalityMemoryJob` (every 30 minutes)
- **System monitoring** - Various health check jobs

### Job Examples
```ruby
# Existing pattern for new jobs
class MoodLightingJob
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 3
  
  def perform(mood, intensity)
    # Coordinate lighting across multiple entities
  end
end
```

## 🧠 AI & LLM Integration

### OpenRouter Service
**File**: `lib/services/openrouter_service.rb`
- **Model presets** - Different models for different tasks
- **Token tracking** - Automatic cost calculation  
- **Caching** - Response caching for efficiency
- **Structured output** - JSON schema support

### Conversation System  
**Files**: `lib/modules/conversation_module.rb`, `lib/services/conversation_*`
- **Multi-turn sessions** - Full conversation state management
- **Tool calling** - ReAct pattern implementation
- **Context injection** - Memory and environmental data
- **Mood analysis** - Already integrated with conversation responses

## 🔌 Integration Patterns

### Service → Home Assistant Pattern
```ruby
# Standard pattern used throughout codebase
def control_hardware(entity_id, action, params = {})
  home_assistant = HomeAssistantClient.new
  home_assistant.call_service(domain, action, params.merge(entity_id: entity_id))
rescue => e
  log.error("Hardware control failed", error: e.message)
  false
end
```

### Circuit Breaker Pattern
All external services use circuit breakers for reliability:
```ruby
# Built into HomeAssistantClient
# - Closed: Normal operation
# - Open: Service failing, use fallbacks  
# - Half-open: Testing recovery
```

## 🎯 Ready for Enhancement

### Immediate Opportunities for New Services

1. **LightingOrchestrator Service**
   - **Target entities**: All 6 RGB lights identified above
   - **Mood mapping**: Integrate with existing TTS mood system
   - **Synchronization**: Coordinate with TTS timing
   - **Graceful degradation**: Handle offline entities

2. **MoodAnalyzer Service** 
   - **Integration point**: `ConversationModule` already returns structured data
   - **Existing patterns**: TTS service already has mood classification
   - **Output format**: Compatible with both TTS and Lighting services

3. **ProactiveConversation Enhancement**
   - **Trigger**: `input_boolean.motion_detected` ready
   - **Integration**: Existing conversation endpoints support proactive starts
   - **Hardware feedback**: Use LED indicators during conversation

4. **DisplayOrchestrator Service**
   - **AWTRIX integration**: Full API already wrapped
   - **Multi-modal**: Coordinate text + lighting + TTS
   - **Rich content**: Icons, animations, sound effects

## 📊 Integration Summary

| Component | Status | Entity Count | Ready for Enhancement |
|-----------|--------|--------------|----------------------|
| RGB Lighting | ✅ Ready | 6 entities | LightingOrchestrator |
| TTS with Moods | ✅ Complete | 15+ moods | Already integrated |
| LED Display | ✅ Ready | 4 entities | DisplayOrchestrator |
| Motion Detection | ✅ Ready | 4 entities | Proactive triggers |
| Audio Output | ✅ Ready | 2 entities | Multi-modal responses |
| Environmental Data | ✅ Available | 355+ sensors | Context integration |
| Job Infrastructure | ✅ Complete | N/A | Background processing |

## 🚀 Next Development Phase

With this foundation, we can now build:

1. **Mood-synchronized RGB lighting** that responds to conversation emotions
2. **Multi-modal expressions** combining TTS + lighting + display text  
3. **Proactive interactions** triggered by motion with hardware feedback
4. **Rich environmental responses** using weather and sensor data
5. **Coordinated hardware orchestration** for immersive art installation experience

All the building blocks are in place - we just need to orchestrate them together! 🎭✨