# TTS Voice Mapping Guide

## Available Voices and Emotional Variants

This document maps standard moods to Home Assistant Cloud TTS voice variants based on the voice data from [hass-nabucasa](https://github.com/NabuCasa/hass-nabucasa/blob/main/hass_nabucasa/voice_data.py).

## Voice Format

Emotional variants use the `||` separator: `VoiceName||variant`

Example: `JennyNeural||friendly`

## Primary Voices (en-US)

### JennyNeural (Female - Default)
**Variants:**
- `assistant` - Professional assistant voice
- `chat` - Conversational tone
- `customerservice` - Service-oriented, helpful
- `newscast` - News anchor style
- `angry` - Frustrated, irritated tone
- `cheerful` - Upbeat, positive
- `sad` - Melancholic, downcast
- `excited` - Energetic, enthusiastic
- `friendly` - Warm, welcoming
- `terrified` - Fearful, scared
- `shouting` - Loud, urgent
- `unfriendly` - Cold, distant
- `whispering` - Quiet, secretive
- `hopeful` - Optimistic, encouraging

### AriaNeural (Female)
**Variants:**
- `chat` - Conversational
- `customerservice` - Professional service
- `narration-professional` - Storytelling voice
- `newscast-casual` - Relaxed news style
- `newscast-formal` - Professional news
- `cheerful` - Happy, upbeat
- `empathetic` - Understanding, caring
- `angry` - Frustrated tone
- `sad` - Sorrowful
- `excited` - Enthusiastic
- `friendly` - Warm
- `terrified` - Scared
- `shouting` - Urgent, loud
- `unfriendly` - Cold
- `whispering` - Quiet
- `hopeful` - Optimistic

### DavisNeural (Male)
**Variants:**
- `chat` - Conversational
- `angry` - Frustrated
- `cheerful` - Happy
- `excited` - Enthusiastic
- `friendly` - Warm
- `hopeful` - Optimistic
- `sad` - Melancholic
- `shouting` - Urgent
- `terrified` - Scared
- `unfriendly` - Cold
- `whispering` - Quiet

### GuyNeural (Male)
**Variants:**
- `newscast` - News anchor
- `angry` - Frustrated
- `cheerful` - Upbeat
- `sad` - Downcast
- `excited` - Energetic
- `friendly` - Welcoming
- `terrified` - Fearful
- `shouting` - Loud
- `unfriendly` - Distant
- `whispering` - Secretive
- `hopeful` - Encouraging

### Additional Voices (Base only, no variants)
- `AmberNeural` - Female
- `AnaNeural` - Female (child)
- `AndrewNeural` - Male
- `AshleyNeural` - Female
- `BrandonNeural` - Male
- `ChristopherNeural` - Male
- `CoraNeural` - Female
- `ElizabethNeural` - Female
- `EmmaNeural` - Female
- `EricNeural` - Male
- `JacobNeural` - Male
- `JaneNeural` - Female
- `JasonNeural` - Male
- `MichelleNeural` - Female
- `MonicaNeural` - Female
- `NancyNeural` - Female
- `RogerNeural` - Male
- `SaraNeural` - Female
- `SteffanNeural` - Male
- `TonyNeural` - Male

### Specialized Voices with Variants

#### AndrewMultilingualNeural (Male - Multilingual)
**Variants:** angry, cheerful, excited, friendly, hopeful, sad, shouting, terrified, unfriendly, whispering

#### AvaMultilingualNeural (Female - Multilingual)
**Variants:** angry, cheerful, excited, friendly, hopeful, sad, shouting, terrified, unfriendly, whispering

#### BrianMultilingualNeural (Male - Multilingual)
**Variants:** Same as above

#### EmmaMultilingualNeural (Female - Multilingual)
**Variants:** Same as above

#### AlloyMultilingualNeural, EchoMultilingualNeural, FableMultilingualNeural, etc.
**Variants:** Similar emotional range

## Recommended Mood Mappings

### Standard Moods → Best Voice Variants

| Mood | Primary Choice | Alternative Choices | Notes |
|------|---------------|-------------------|--------|
| **Happy** | `JennyNeural\|\|cheerful` | `AriaNeural\|\|cheerful`, `DavisNeural\|\|cheerful` | Upbeat, positive energy |
| **Sad** | `JennyNeural\|\|sad` | `AriaNeural\|\|sad`, `DavisNeural\|\|sad` | Melancholic, slower pace |
| **Angry** | `JennyNeural\|\|angry` | `AriaNeural\|\|angry`, `DavisNeural\|\|angry` | Frustrated, sharp tone |
| **Excited** | `JennyNeural\|\|excited` | `AriaNeural\|\|excited`, `DavisNeural\|\|excited` | High energy, faster pace |
| **Friendly** | `JennyNeural\|\|friendly` | `AriaNeural\|\|friendly`, `DavisNeural\|\|friendly` | Warm, welcoming |
| **Scared** | `JennyNeural\|\|terrified` | `AriaNeural\|\|terrified`, `DavisNeural\|\|terrified` | Fearful, tense |
| **Whispering** | `JennyNeural\|\|whispering` | `AriaNeural\|\|whispering`, `DavisNeural\|\|whispering` | Quiet, secretive |
| **Shouting** | `JennyNeural\|\|shouting` | `AriaNeural\|\|shouting`, `DavisNeural\|\|shouting` | Loud, urgent |
| **Hopeful** | `JennyNeural\|\|hopeful` | `AriaNeural\|\|hopeful`, `DavisNeural\|\|hopeful` | Optimistic, encouraging |
| **Empathetic** | `AriaNeural\|\|empathetic` | `JennyNeural\|\|friendly` | Understanding, caring |
| **Professional** | `AriaNeural\|\|narration-professional` | `JennyNeural\|\|assistant` | Formal, clear |
| **Casual** | `JennyNeural\|\|chat` | `AriaNeural\|\|chat`, `DavisNeural\|\|chat` | Conversational |
| **News** | `JennyNeural\|\|newscast` | `AriaNeural\|\|newscast-formal`, `GuyNeural\|\|newscast` | News anchor style |
| **Service** | `JennyNeural\|\|customerservice` | `AriaNeural\|\|customerservice` | Helpful, patient |
| **Cold** | `JennyNeural\|\|unfriendly` | `AriaNeural\|\|unfriendly`, `DavisNeural\|\|unfriendly` | Distant, detached |

## Context-Based Voice Selection

### For Interactive Art Installation (Glitch Cube)

| Context | Recommended Voice | Reasoning |
|---------|------------------|-----------|
| **Greeting visitors** | `JennyNeural\|\|friendly` | Warm, welcoming first impression |
| **Requesting help** | `JennyNeural\|\|hopeful` or `AriaNeural\|\|empathetic` | Vulnerable, seeking assistance |
| **Celebrating** | `JennyNeural\|\|excited` or `JennyNeural\|\|cheerful` | Joyful interaction |
| **Low battery** | `JennyNeural\|\|sad` or `JennyNeural\|\|whispering` | Energy conservation mood |
| **Emergency** | `DavisNeural\|\|shouting` | Urgent attention needed |
| **Storytelling** | `AriaNeural\|\|narration-professional` | Engaging narrative voice |
| **Night mode** | `JennyNeural\|\|whispering` | Quiet, respectful of environment |
| **Playful** | `JennyNeural\|\|cheerful` with faster speed | Fun, energetic |
| **Philosophical** | `AriaNeural\|\|chat` or `JennyNeural\|\|assistant` | Thoughtful, measured |
| **Annoyed** | `JennyNeural\|\|unfriendly` | When ignored repeatedly |

## Usage Examples

```ruby
# Ruby implementation
tts = Services::TTSService.new

# Happy greeting
tts.speak("Hello! I'm so glad you're here!", mood: :cheerful)

# Sad low battery
tts.speak("My battery is getting low...", mood: :sad)

# Excited discovery
tts.speak("Oh wow, I just learned something amazing!", mood: :excited)

# Whispered secret
tts.speak("Can I tell you a secret?", mood: :whisper)

# Direct voice selection
tts.speak("Breaking news!", voice: "JennyNeural||newscast")
```

## Implementation Notes

1. **Fallback Strategy**: If a variant isn't available, the system falls back to the base voice
2. **Caching**: Home Assistant caches generated audio, so the same text with the same voice won't regenerate
3. **Language Support**: These variants are for `en-US`. Other languages have different voice options
4. **Performance**: Emotional variants may have slightly longer generation time than base voices
5. **Volume**: Some variants (like `shouting`) are louder by design - adjust media player volume accordingly

## Voice Selection Guidelines

1. **Match emotion to content** - Don't use `cheerful` for sad news
2. **Consider context** - Time of day, user interaction history, device state
3. **Avoid overuse** - Too much emotion can be overwhelming
4. **Test combinations** - Some voices work better for certain emotions
5. **User preferences** - Allow users to select preferred voice personalities

## Special Considerations for Art Installation

- **Battery < 20%**: Use `sad` or `whispering` variants
- **Multiple visitors**: Use `excited` or `cheerful` for group energy
- **Quiet hours**: Default to `whispering` variants
- **First interaction**: Use `friendly` to establish rapport
- **Extended conversation**: Vary emotions to maintain engagement
- **Error states**: Use `empathetic` when things go wrong

## Future Enhancements

- Map weather conditions to voice moods
- Time-based voice selection (morning = cheerful, evening = calm)
- Visitor sentiment analysis → responsive voice selection
- Personality profiles with preferred voice combinations