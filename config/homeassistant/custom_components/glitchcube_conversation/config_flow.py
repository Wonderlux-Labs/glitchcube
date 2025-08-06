"""Config flow for Glitch Cube Conversation integration."""
from __future__ import annotations

import aiohttp
import asyncio
import logging
from typing import Any

import voluptuous as vol

from homeassistant import config_entries
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResult
from homeassistant.exceptions import HomeAssistantError

from .const import DOMAIN, DEFAULT_HOST, DEFAULT_PORT, DEFAULT_TIMEOUT

_LOGGER = logging.getLogger(__name__)

STEP_USER_DATA_SCHEMA = vol.Schema(
    {
        vol.Optional("port", default=DEFAULT_PORT): int,
    }
)


async def validate_input(hass: HomeAssistant, data: dict[str, Any]) -> dict[str, Any]:
    """Validate the user input allows us to connect."""
    
    # Try to get dynamic host from input_text entity first
    try:
        glitchcube_host_state = hass.states.get("input_text.glitchcube_host")
        if glitchcube_host_state and glitchcube_host_state.state:
            dynamic_host = glitchcube_host_state.state
            _LOGGER.info(f"Found dynamic Glitch Cube host: {dynamic_host}")
            host = dynamic_host
        else:
            # No dynamic host available - skip validation since Mac Mini may not be running yet
            return {
                "title": "Glitch Cube (Dynamic IP)",
                "version": "unknown - will connect when Glitch Cube starts"
            }
    except Exception as e:
        _LOGGER.warning(f"Could not read dynamic host, will connect when available: {e}")
        return {
            "title": "Glitch Cube (Dynamic IP)",
            "version": "unknown - will connect when Glitch Cube starts"
        }
    
    port = data.get("port", DEFAULT_PORT)
    url = f"http://{host}:{port}/health"
    timeout = aiohttp.ClientTimeout(total=DEFAULT_TIMEOUT)
    
    try:
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get(url) as response:
                if response.status == 200:
                    health_data = await response.json()
                    return {
                        "title": f"Glitch Cube ({host}:{port})",
                        "version": health_data.get("version", "unknown")
                    }
                else:
                    raise CannotConnect("Health check failed")
    except asyncio.TimeoutError:
        raise CannotConnect("Connection timeout - ensure Glitch Cube is running")
    except aiohttp.ClientError:
        raise CannotConnect("Connection error - check if Glitch Cube service is available")
    except Exception as e:
        _LOGGER.exception("Unexpected error validating Glitch Cube connection")
        raise CannotConnect(f"Unexpected error: {str(e)}")


class ConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    """Handle a config flow for Glitch Cube Conversation."""

    VERSION = 1

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> FlowResult:
        """Handle the initial step."""
        errors: dict[str, str] = {}
        
        if user_input is not None:
            try:
                # Set unique ID to prevent duplicate configurations - use domain since IP is dynamic
                unique_id = f"{DOMAIN}"
                await self.async_set_unique_id(unique_id)
                self._abort_if_unique_id_configured()
                
                info = await validate_input(self.hass, user_input)
            except CannotConnect:
                errors["base"] = "cannot_connect"
            except Exception:  # pylint: disable=broad-except
                _LOGGER.exception("Unexpected exception")
                errors["base"] = "unknown"
            else:
                return self.async_create_entry(title=info["title"], data=user_input)

        return self.async_show_form(
            step_id="user", data_schema=STEP_USER_DATA_SCHEMA, errors=errors
        )


class CannotConnect(HomeAssistantError):
    """Error to indicate we cannot connect."""