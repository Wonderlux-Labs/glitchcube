"""Glitch Cube Conversation Agent."""
from __future__ import annotations

import aiohttp
import asyncio
import logging
from typing import Any

from homeassistant.components import conversation
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers import intent
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.util import dt as dt_util

from .const import (
    DOMAIN,
    DEFAULT_HOST,
    DEFAULT_PORT,
    DEFAULT_TIMEOUT,
    RESPONSE_KEY,
    ACTIONS_KEY,
    CONTINUE_KEY,
    MOOD_KEY,
    MEDIA_KEY,
    SUPPORTED_LANGUAGES,
)

_LOGGER = logging.getLogger(__name__)


async def async_setup_entry(
    hass: HomeAssistant,
    config_entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up Glitch Cube conversation entity."""
    entity = GlitchCubeConversationEntity(config_entry)
    async_add_entities([entity])


class GlitchCubeConversationEntity(conversation.ConversationEntity):
    """Glitch Cube conversation agent."""

    def __init__(self, config_entry: ConfigEntry) -> None:
        """Initialize the conversation entity."""
        self._config_entry = config_entry
        # Get connection details from config (all containers use host networking)
        host = config_entry.data.get("host", DEFAULT_HOST)
        port = config_entry.data.get("port", DEFAULT_PORT)
        
        self._attr_name = f"Glitch Cube ({host}:{port})"
        self._attr_unique_id = f"{DOMAIN}_{config_entry.entry_id}"
        
        # Build API URL from config
        self._api_url = f"http://{host}:{port}/api/v1/conversation"
        self._timeout = DEFAULT_TIMEOUT  # Optimized for voice interactions
        
        # Store conversation sessions for continuity
        self._conversation_sessions = {}
        
        _LOGGER.info("Initialized Glitch Cube conversation agent: %s", self._api_url)

    @property
    def supported_languages(self) -> list[str]:
        """Return list of supported languages."""
        return SUPPORTED_LANGUAGES

    def _get_current_api_url(self) -> str:
        """Get the current API URL, checking for dynamic host first."""
        try:
            # Try to get dynamic host from input_text entity
            glitchcube_host_state = self.hass.states.get("input_text.glitchcube_host")
            if glitchcube_host_state and glitchcube_host_state.state:
                dynamic_host = glitchcube_host_state.state
                port = self._config_entry.data.get("port", DEFAULT_PORT)
                api_url = f"http://{dynamic_host}:{port}/api/v1/conversation"
                _LOGGER.debug(f"Using dynamic host from input_text: {dynamic_host}")
                return api_url
        except Exception as e:
            _LOGGER.warning(f"Could not read dynamic host, using configured: {e}")
        
        # Fallback to configured API URL
        return self._api_url

    def _get_or_create_session(self, conversation_id: str) -> str:
        """Get or create a session ID for conversation continuity."""
        if conversation_id not in self._conversation_sessions:
            self._conversation_sessions[conversation_id] = {
                "session_id": f"ha_{conversation_id}_{dt_util.utcnow().timestamp()}",
                "started_at": dt_util.utcnow().isoformat(),
                "turn_count": 0
            }
        
        # Increment turn count
        self._conversation_sessions[conversation_id]["turn_count"] += 1
        return self._conversation_sessions[conversation_id]["session_id"]
    
    async def async_process(
        self, user_input: conversation.ConversationInput
    ) -> conversation.ConversationResult:
        """Process a conversation turn."""
        _LOGGER.debug("Processing conversation: %s", user_input.text)
        
        try:
            # Get current API URL (may be dynamic)
            api_url = self._get_current_api_url()
            
            # Get or create session for conversation continuity
            session_id = self._get_or_create_session(user_input.conversation_id)
            
            # Prepare request payload for Sinatra app
            payload = {
                "message": user_input.text,
                "context": {
                    "conversation_id": user_input.conversation_id,
                    "ha_conversation_id": user_input.conversation_id,
                    "session_id": session_id,
                    "device_id": user_input.device_id,
                    "language": user_input.language,
                    "voice_interaction": True,
                    "timestamp": dt_util.utcnow().isoformat(),
                    # Add any additional context
                    "ha_context": {
                        "agent_id": self._attr_unique_id,
                        "user_id": getattr(user_input, "user_id", None),
                    }
                }
            }
            
            # Call Sinatra app using dynamic URL
            timeout = aiohttp.ClientTimeout(total=self._timeout)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.post(
                    api_url,
                    json=payload,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    if response.status != 200:
                        raise ConversationError(f"API error: {response.status}")
                    
                    result_data = await response.json()
                    
                    if not result_data.get("success", False):
                        raise ConversationError(f"Conversation failed: {result_data.get('error', 'Unknown error')}")
                    
                    conversation_data = result_data.get("data", {})
                    
        except asyncio.TimeoutError:
            _LOGGER.error("Timeout calling Glitch Cube API")
            return self._create_error_response(user_input, "I'm having trouble thinking right now. Please try again.")
        
        except aiohttp.ClientError as e:
            _LOGGER.error("Client error calling Glitch Cube API: %s", str(e))
            return self._create_error_response(user_input, "I can't connect to my brain right now. Please try again.")
        
        except ConversationError as e:
            _LOGGER.error("Conversation error: %s", str(e))
            return self._create_error_response(user_input, "Something went wrong with my thinking. Please try again.")
        
        except Exception as e:
            _LOGGER.exception("Unexpected error in conversation processing")
            return self._create_error_response(user_input, "I encountered an unexpected error. Please try again.")
        
        # Extract response text
        response_text = conversation_data.get(RESPONSE_KEY, "I didn't understand that.")
        
        # Create intent response
        intent_response = intent.IntentResponse(language=user_input.language)
        intent_response.async_set_speech(response_text)
        
        # Handle suggested actions from Sinatra app
        await self._handle_suggested_actions(conversation_data)
        
        # Handle media actions (ONLY for non-speech audio like sound effects, music)
        # NOTE: Primary speech response comes from intent_response.async_set_speech above
        await self._handle_media_actions(conversation_data)
        
        # Determine if conversation should continue - default to True for ongoing conversations
        continue_conversation = conversation_data.get(CONTINUE_KEY, True)
        
        # Store session info for debugging
        if user_input.conversation_id in self._conversation_sessions:
            turn_count = self._conversation_sessions[user_input.conversation_id]["turn_count"]
            _LOGGER.debug(
                "Conversation result: response_length=%d, continue=%s, turn=%d", 
                len(response_text), 
                continue_conversation,
                turn_count
            )
        else:
            _LOGGER.debug(
                "Conversation result: response_length=%d, continue=%s", 
                len(response_text), 
                continue_conversation
            )
        
        return conversation.ConversationResult(
            conversation_id=user_input.conversation_id,
            response=intent_response,
            continue_conversation=continue_conversation,
        )

    async def _handle_suggested_actions(self, conversation_data: dict[str, Any]) -> None:
        """Handle suggested Home Assistant actions from the conversation."""
        actions = conversation_data.get(ACTIONS_KEY, [])
        
        if not actions:
            return
            
        _LOGGER.debug("Processing %d suggested actions", len(actions))
        
        for action in actions:
            try:
                domain = action.get("domain")
                service = action.get("service")
                service_data = action.get("data", {})
                target = action.get("target", {})
                
                if not domain or not service:
                    _LOGGER.warning("Invalid action format: %s", action)
                    continue
                
                # Execute the service call
                await self.hass.services.async_call(
                    domain=domain,
                    service=service,
                    service_data=service_data,
                    target=target,
                    blocking=False,  # Don't block conversation response
                )
                
                _LOGGER.debug("Executed action: %s.%s", domain, service)
                
            except Exception as e:
                _LOGGER.error("Failed to execute action %s: %s", action, str(e))

    async def _handle_media_actions(self, conversation_data: dict[str, Any]) -> None:
        """Handle media-related actions (audio playback, sound effects - NOT primary speech)."""
        media_actions = conversation_data.get(MEDIA_KEY, [])
        
        if not media_actions:
            return
            
        _LOGGER.debug("Processing %d media actions", len(media_actions))
        
        for media_action in media_actions:
            try:
                action_type = media_action.get("type")
                
                if action_type == "tts":
                    # DEPRECATED: Use 'response' field in main JSON instead
                    # This is only for secondary TTS on different speakers
                    _LOGGER.warning("TTS action deprecated - use 'response' field for primary speech")
                    await self._handle_tts_action(media_action)
                elif action_type == "audio":
                    # Handle audio playback (sound effects, music, etc.)
                    await self._handle_audio_action(media_action)
                elif action_type == "sound_effect":
                    # Handle sound effects
                    await self._handle_audio_action(media_action)
                else:
                    _LOGGER.warning("Unknown media action type: %s", action_type)
                    
            except Exception as e:
                _LOGGER.error("Failed to execute media action %s: %s", media_action, str(e))

    async def _handle_tts_action(self, tts_action: dict[str, Any]) -> None:
        """Handle TTS action."""
        message = tts_action.get("message")
        entity_id = tts_action.get("entity_id", "media_player.glitchcube_speaker")
        
        if not message:
            return
            
        await self.hass.services.async_call(
            domain="tts",
            service="speak",
            service_data={
                "message": message,
                "media_player_entity_id": entity_id,
            },
            blocking=False,
        )

    async def _handle_audio_action(self, audio_action: dict[str, Any]) -> None:
        """Handle audio playback action."""
        media_url = audio_action.get("url")
        entity_id = audio_action.get("entity_id", "media_player.glitchcube_speaker")
        
        if not media_url:
            return
            
        await self.hass.services.async_call(
            domain="media_player",
            service="play_media",
            service_data={
                "media_content_id": media_url,
                "media_content_type": "music",
            },
            target={"entity_id": entity_id},
            blocking=False,
        )

    def _create_error_response(
        self, 
        user_input: conversation.ConversationInput, 
        error_message: str
    ) -> conversation.ConversationResult:
        """Create an error response."""
        intent_response = intent.IntentResponse(language=user_input.language)
        intent_response.async_set_speech(error_message)
        
        return conversation.ConversationResult(
            conversation_id=user_input.conversation_id,
            response=intent_response,
            continue_conversation=False,
        )


    async def trigger_proactive_conversation(self, trigger_type: str, context: dict = None):
        """Trigger proactive conversation from HA automations."""
        api_url = self._get_current_api_url().replace('/conversation', '/conversation/start')
        
        payload = {
            "trigger": trigger_type,
            "context": context or {},
            "device_id": "glitchcube"
        }
        
        try:
            timeout = aiohttp.ClientTimeout(total=self._timeout)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.post(
                    api_url,
                    json=payload,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    if response.status == 200:
                        result = await response.json()
                        _LOGGER.info("Triggered proactive conversation: %s", trigger_type)
                        return result
                    else:
                        _LOGGER.error("Failed to trigger proactive conversation: %s", response.status)
                        return None
        except Exception as e:
            _LOGGER.error("Error triggering proactive conversation: %s", str(e))
            return None


class ConversationError(Exception):
    """Custom exception for conversation errors."""