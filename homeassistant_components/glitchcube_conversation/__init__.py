"""Glitch Cube Conversation Agent Integration."""
from __future__ import annotations

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant

DOMAIN = "glitchcube_conversation"

async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Set up Glitch Cube Conversation from a config entry."""
    hass.async_create_task(
        hass.config_entries.async_forward_entry_setup(entry, "conversation")
    )
    return True

async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload a config entry."""
    return await hass.config_entries.async_forward_entry_unload(entry, "conversation")