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

    async def async_process(
        self, user_input: conversation.ConversationInput
    ) -> conversation.ConversationResult:
        """Process a conversation turn."""
        _LOGGER.debug("Processing conversation: %s", user_input.text)
        
        try:
            # Get current API URL (may be dynamic)
            api_url = self._get_current_api_url()
            
            # Phase 3.5: Ultra-simple session management
            # Just use HA's conversation_id as our session ID
            # HA already tracks multi-turn conversations for us
            # No state tracking needed in the agent - keep it stateless
            session_id = f"voice_{user_input.conversation_id}"
            
            # Prepare request payload for Sinatra app  
            payload = {
                "message": user_input.text,
                "context": {
                    "session_id": session_id,  # Derived from HA's conversation tracking
                    "conversation_id": user_input.conversation_id,  # Original HA ID for reference
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
        
        # Phase 3.5: Ultra-simple continuation logic
        # Let Sinatra decide if conversation should continue based on LLM's decision
        # The LLM has full context and makes intelligent continuation decisions
        # Just use continue_conversation directly - no need for inverse
        continue_conversation = conversation_data.get("continue_conversation", False)
        
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

    # REMOVED: Complex bidirectional service call methods for Phase 3 simplification
    # All actions now handled by Sinatra via tools:
    # - _handle_suggested_actions() → Now handled by Sinatra tools (lighting_control, etc.)
    # - _handle_media_actions() → Now handled by Sinatra speech_synthesis tool
    # - _handle_tts_action() → Now handled by Sinatra speech_synthesis tool  
    # - _handle_audio_action() → Now handled by Sinatra tools
    #
    # This creates clean separation: HA = STT + hardware, Sinatra = conversation + tools

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


class ConversationError(Exception):
    """Custom exception for conversation errors."""