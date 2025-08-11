"""Glitch Cube Conversation Agent."""
from __future__ import annotations

import aiohttp
import asyncio
import logging
from typing import Any
import os
from pathlib import Path

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
    MEDIA_KEY,
    SUPPORTED_LANGUAGES,
)

_LOGGER = logging.getLogger(__name__)

# Set up dedicated file logging for conversation agent
def setup_conversation_logger():
    """Set up a dedicated logger for the conversation agent."""
    # Create logs directory if it doesn't exist
    log_dir = Path("/config/logs")
    log_dir.mkdir(exist_ok=True)
    
    # Create a file handler for conversation logs
    file_handler = logging.FileHandler(log_dir / "glitchcube_conversation.log")
    file_handler.setLevel(logging.DEBUG)
    
    # Create formatter
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    file_handler.setFormatter(formatter)
    
    # Add handler to logger
    _LOGGER.addHandler(file_handler)
    _LOGGER.setLevel(logging.DEBUG)
    
    return _LOGGER

# Initialize the dedicated logger
_LOGGER = setup_conversation_logger()


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
        # Get connection details from config
        # If host is empty or missing, we'll use dynamic host from input_text
        host = config_entry.data.get("host", "")
        port = config_entry.data.get("port", DEFAULT_PORT)
        
        # If no host specified, we'll determine it dynamically
        if not host:
            self._attr_name = f"Glitch Cube (Dynamic IP:{port})"
            # Don't set a fixed URL - we'll get it dynamically
            self._api_url = None
        else:
            self._attr_name = f"Glitch Cube ({host}:{port})"
            self._api_url = f"http://{host}:{port}/api/v1/conversation"
        
        self._attr_unique_id = f"{DOMAIN}_{config_entry.entry_id}"
        self._timeout = DEFAULT_TIMEOUT  # Optimized for voice interactions
        
        _LOGGER.info("Initialized Glitch Cube conversation agent: %s", 
                     self._api_url if self._api_url else "Dynamic IP mode")

    @property
    def supported_languages(self) -> list[str]:
        """Return list of supported languages."""
        return SUPPORTED_LANGUAGES

    def _get_current_api_url(self) -> str:
        """Get the current API URL, checking for dynamic host first."""
        # Always check for dynamic host first (for dynamic IP support)
        try:
            glitchcube_host_state = self.hass.states.get("input_text.glitchcube_host")
            if glitchcube_host_state and glitchcube_host_state.state:
                dynamic_host = glitchcube_host_state.state
                port = self._config_entry.data.get("port", DEFAULT_PORT)
                api_url = f"http://{dynamic_host}:{port}/api/v1/conversation"
                _LOGGER.debug(f"Using dynamic host from input_text: {dynamic_host}")
                return api_url
        except Exception as e:
            _LOGGER.warning(f"Could not read dynamic host: {e}")
        
        # If we have a configured URL, use it
        if self._api_url:
            return self._api_url
        
        # Last resort: use production IP
        port = self._config_entry.data.get("port", DEFAULT_PORT)
        fallback_url = f"http://192.168.0.99:{port}/api/v1/conversation"
        _LOGGER.warning(f"No host configured and no dynamic host available, using fallback: {fallback_url}")
        return fallback_url

    async def async_process(
        self, user_input: conversation.ConversationInput
    ) -> conversation.ConversationResult:
        """Process a conversation turn."""
        _LOGGER.info("=" * 60)
        _LOGGER.info("NEW CONVERSATION REQUEST")
        _LOGGER.info("User input: %s", user_input.text)
        _LOGGER.info("Conversation ID: %s", user_input.conversation_id)
        _LOGGER.info("Device ID: %s", user_input.device_id)
        _LOGGER.info("Language: %s", user_input.language)
        
        try:
            # Get current API URL (may be dynamic)
            api_url = self._get_current_api_url()
            _LOGGER.info("Using API URL: %s", api_url)
            
            # Phase 3.5: Ultra-simple session management
            # Just use HA's conversation_id as our session ID
            # HA already tracks multi-turn conversations for us
            # No state tracking needed in the agent - keep it stateless
            session_id = f"voice_{user_input.conversation_id}"
            _LOGGER.info("Session ID: %s", session_id)
            
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
            
            _LOGGER.debug("Sending payload to Sinatra: %s", payload)
            
            # Call Sinatra app using dynamic URL
            timeout = aiohttp.ClientTimeout(total=self._timeout)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.post(
                    api_url,
                    json=payload,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    _LOGGER.info("Sinatra response status: %d", response.status)
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
        
        # Log complete response details
        _LOGGER.info("=" * 40)
        _LOGGER.info("SINATRA RESPONSE DETAILS")
        _LOGGER.info("Response keys: %s", list(conversation_data.keys()))
        _LOGGER.info("Response text: %s", response_text[:200] if len(response_text) > 200 else response_text)
        
        # Create intent response
        intent_response = intent.IntentResponse(language=user_input.language)
        
        # Get persona and TTS voice info from Sinatra
        persona = conversation_data.get("persona", "default")
        tts_voice = conversation_data.get("tts_voice", "JennyNeural")
        tts_provider = conversation_data.get("tts_provider", "cloud")
        
        _LOGGER.info("Persona: %s", persona)
        _LOGGER.info("TTS Voice: %s", tts_voice)
        _LOGGER.info("TTS Provider: %s", tts_provider)
        
        # Set the speech text for the pipeline
        intent_response.async_set_speech(response_text)
        
        # Use TTS action from Sinatra if provided (for persona-specific voices)
        if conversation_data.get("tts_action"):
            tts_action = conversation_data["tts_action"]
            _LOGGER.info("TTS Action provided by Sinatra")
            _LOGGER.debug("TTS Action details: %s", tts_action)
            
            # Set the action on the intent response
            # This will override the pipeline's default TTS with persona-specific voice
            intent_response.async_set_action(tts_action)
            _LOGGER.info("TTS action set on intent response")
        
        # Phase 3.5: Ultra-simple continuation logic
        # Let Sinatra decide if conversation should continue based on LLM's decision
        # The LLM has full context and makes intelligent continuation decisions
        # Just use continue_conversation directly - no need for inverse
        continue_conversation = conversation_data.get("continue_conversation", False)
        
        _LOGGER.info("=" * 40)
        _LOGGER.info("FINAL RESULT")
        _LOGGER.info("Response length: %d", len(response_text))
        _LOGGER.info("Continue conversation: %s", continue_conversation)
        _LOGGER.info("Persona: %s", persona)
        _LOGGER.info("=" * 60)
        
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