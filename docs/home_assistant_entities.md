# Home Assistant Entities

✅ **Status**: Connected to Home Assistant at http://glitchcube.local:8123
Generated on: 2025-08-04 04:10:14
Total entities: 192

## Entity Summary by Domain

- **automation**: 13 entities
- **binary_sensor**: 4 entities
- **button**: 6 entities
- **calendar**: 1 entities
- **camera**: 1 entities
- **conversation**: 2 entities
- **event**: 1 entities
- **image**: 1 entities
- **input_boolean**: 10 entities
- **input_datetime**: 1 entities
- **input_number**: 1 entities
- **input_text**: 3 entities
- **media_player**: 2 entities
- **notify**: 2 entities
- **number**: 4 entities
- **person**: 2 entities
- **script**: 12 entities
- **sensor**: 103 entities
- **stt**: 1 entities
- **sun**: 1 entities
- **switch**: 5 entities
- **todo**: 1 entities
- **tts**: 3 entities
- **update**: 9 entities
- **weather**: 2 entities
- **zone**: 1 entities

## Glitch Cube Integration Status

### Entities Used in Code:
- ✅ **input_text.current_weather** - Weather error: the server responded with status 400 for POST https (Available)
- ❌ **sensor.battery_level** - (Missing - needs configuration)
- ❌ **sensor.temperature** - (Missing - needs configuration)
- ❌ **sensor.outdoor_temperature** - (Missing - needs configuration)
- ❌ **sensor.outdoor_humidity** - (Missing - needs configuration)
- ❌ **binary_sensor.motion** - (Missing - needs configuration)
- ❌ **camera.glitch_cube** - (Missing - needs configuration)
- ❌ **media_player.glitch_cube_speaker** - (Missing - needs configuration)

### Available Entity Types for Integration:
- **Weather entities**: 2 (weather.openweathermap, weather.forecast_home)
- **Camera entities**: 1 (camera.tablet)
- **Media players**: 2 (media_player.tablet_2, media_player.tablet)

## All Entities by Domain

### Automation (13 entities)

- automation.alert_on_app_health_issues - Alert on App Health Issues (on)
- automation.alert_on_high_temperature - Alert on High Temperature (on)
- automation.alert_on_internet_connectivity_loss - Alert on Internet Connectivity Loss (on)
- automation.daily_health_summary - Daily Health Summary (on)
- automation.disable_offline_mode - Disable Offline Mode (on)
- automation.enable_offline_mode - Enable Offline Mode (on)
- automation.glitch_cube_text_to_speech - Glitch Cube Text-to-Speech (on)
- automation.update_average_sound_level - Update Average Sound Level (on)
- automation.update_binary_sensors - Update Binary Sensors (on)
- automation.update_current_environment - Update Current Environment (on)
- automation.update_current_persona - Update Current Persona (on)
- automation.update_last_interaction_time - Update Last Interaction Time (on)
- automation.update_weather_summary - Update Weather Summary (on)

### Binary_sensor (4 entities)

- binary_sensor.remote_ui - Remote UI (off)
- binary_sensor.tablet_device_admin - Tablet Device admin (on)
- binary_sensor.tablet_kiosk_mode - Tablet Kiosk mode (off)
- binary_sensor.tablet_plugged_in - Tablet Plugged in (on)

### Button (6 entities)

- button.tablet_bring_to_foreground - Tablet Bring to foreground (unknown)
- button.tablet_favorite_current_song - Tablet Favorite current song (unknown)
- button.tablet_load_start_url - Tablet Load start URL (unknown)
- button.tablet_restart_browser - Tablet Restart browser (unknown)
- button.tablet_restart_device - Tablet Restart device (unknown)
- button.tablet_send_to_background - Tablet Send to background (unknown)

### Calendar (1 entities)

- calendar.llm_vision_timeline - LLM Vision Timeline (off)

### Camera (1 entities)

- **camera.tablet** - Tablet (idle)

### Conversation (2 entities)

- conversation.claude_conversation - Claude conversation (unknown)
- conversation.home_assistant - Home Assistant (unknown)

### Event (1 entities)

- event.backup_automatic_backup - Backup Automatic backup (unknown)

### Image (1 entities)

- image.tablet_screenshot - Tablet Screenshot (2025-08-04T11:09:32.812452+00:00)

### Input_boolean (10 entities)

- input_boolean.battery_low - Battery Low (off)
- input_boolean.cube_is_moving - Cube Is Moving (off)
- input_boolean.cube_stable - Cube Stable (on)
- input_boolean.cube_stopped_moving - Cube Stopped Moving (off)
- input_boolean.cube_tilted - Cube Tilted (off)
- input_boolean.human_detected - Human Detected (off)
- input_boolean.motion_detected - Motion Detected (off)
- input_boolean.offline_mode - Offline Mode (off)
- input_boolean.resources_low - Resources Low (off)
- input_boolean.temp_critical - Temperature Critical (off)

### Input_datetime (1 entities)

- input_datetime.last_interaction - Last Interaction Timestamp (2025-08-04 00:00:00)

### Input_number (1 entities)

- input_number.avg_sound_db - Average Sound Level (40.0)

### Input_text (3 entities)

- input_text.current_environment - Current Environment (Unknown location)
- input_text.current_persona - Current AI Persona (Default)
- **input_text.current_weather** - input_text.current_weather (Weather error: the server responded with status 400 for POST https)

### Media_player (2 entities)

- **media_player.tablet** - Tablet (idle)
- **media_player.tablet_2** - Tablet (idle)

### Notify (2 entities)

- notify.tablet_overlay_message - Tablet Overlay message (unknown)
- notify.tablet_text_to_speech - Tablet Text to speech (unknown)

### Number (4 entities)

- number.tablet_screen_brightness - Tablet Screen brightness (45)
- number.tablet_screen_off_timer - Tablet Screen off timer (0)
- number.tablet_screensaver_brightness - Tablet Screensaver brightness (50)
- number.tablet_screensaver_timer - Tablet Screensaver timer (0)

### Person (2 entities)

- person.glitch - glitch (unknown)
- person.tablet - tablet (unknown)

### Script (12 entities)

- script.change_persona - Change AI Persona (off)
- script.emergency_shutdown - Emergency Shutdown Sequence (off)
- script.generate_health_report - Generate Health Report (off)
- script.reset_all_sensors - Reset All Sensors to Default (off)
- script.simulate_cube_movement - Simulate Cube Movement (off)
- script.simulate_human_interaction - Simulate Human Interaction Sequence (off)
- script.simulate_interaction - Simulate User Interaction (off)
- script.simulate_motion - Simulate Motion Detection (off)
- script.speak_with_persona - Speak with Current Persona (off)
- script.test_all_sensors - Test All Sensors (off)
- script.test_health_sensors - Test All Health Sensors (off)
- script.toggle_offline_mode - Toggle Offline Mode (off)

### Sensor (103 entities)

- sensor.backup_backup_manager_state - Backup Backup Manager state (idle)
- sensor.backup_last_attempted_automatic_backup - Backup Last attempted automatic backup (unknown)
- sensor.backup_last_successful_automatic_backup - Backup Last successful automatic backup (unknown)
- sensor.backup_next_scheduled_automatic_backup - Backup Next scheduled automatic backup (unknown)
- sensor.cube_br_14a53c3eb3b7_rx - br-14a53c3eb3b7 RX (unavailable)
- sensor.cube_br_14a53c3eb3b7_tx - br-14a53c3eb3b7 TX (unavailable)
- sensor.cube_br_dffd57da0b65_rx - cube br-dffd57da0b65 RX (0.0004)
- sensor.cube_br_dffd57da0b65_tx - cube br-dffd57da0b65 TX (0.000472)
- sensor.cube_containers_active - cube Containers active (8)
- sensor.cube_containers_cpu_usage - cube Containers CPU usage (3.0)
- sensor.cube_containers_memory_used - cube Containers memory used (0.0)
- sensor.cube_cpu_load - cube CPU load (0.17578125)
- sensor.cube_cpu_thermal_0_temperature - cube cpu_thermal 0 temperature (129.2)
- sensor.cube_cpu_usage - cube CPU usage (3.3)
- sensor.cube_etc_hostname_disk_free - cube /etc/hostname disk free (45.7)
- sensor.cube_etc_hostname_disk_usage - cube /etc/hostname disk usage (15.2)
- sensor.cube_etc_hostname_disk_used - cube /etc/hostname disk used (8.2)
- sensor.cube_etc_hosts_disk_free - cube /etc/hosts disk free (45.7)
- sensor.cube_etc_hosts_disk_usage - cube /etc/hosts disk usage (15.2)
- sensor.cube_etc_hosts_disk_used - cube /etc/hosts disk used (8.2)
- sensor.cube_etc_resolv_conf_disk_free - cube /etc/resolv.conf disk free (45.7)
- sensor.cube_etc_resolv_conf_disk_usage - cube /etc/resolv.conf disk usage (15.2)
- sensor.cube_etc_resolv_conf_disk_used - cube /etc/resolv.conf disk used (8.2)
- sensor.cube_eth0_rx - cube eth0 RX (0.028352)
- sensor.cube_eth0_tx - cube eth0 TX (0.021744)
- sensor.cube_lo_rx - cube lo RX (0.004376)
- sensor.cube_lo_tx - cube lo TX (0.004376)
- sensor.cube_memory_free - cube Memory free (6412.9)
- sensor.cube_memory_usage - cube Memory usage (20.5)
- sensor.cube_memory_use - cube Memory use (1650.3)
- sensor.cube_mmcblk0_disk_read - cube mmcblk0 disk read (0.0)
- sensor.cube_mmcblk0_disk_write - cube mmcblk0 disk write (0.064502)
- sensor.cube_mmcblk0p1_disk_read - cube mmcblk0p1 disk read (0.0)
- sensor.cube_mmcblk0p1_disk_write - cube mmcblk0p1 disk write (0.0)
- sensor.cube_mmcblk0p2_disk_read - cube mmcblk0p2 disk read (0.0)
- sensor.cube_mmcblk0p2_disk_write - cube mmcblk0p2 disk write (0.064502)
- sensor.cube_rootfs_boot_firmware_disk_free - cube /rootfs/boot/firmware disk free (0.4)
- sensor.cube_rootfs_boot_firmware_disk_usage - cube /rootfs/boot/firmware disk usage (11.2)
- sensor.cube_rootfs_boot_firmware_disk_used - cube /rootfs/boot/firmware disk used (0.1)
- sensor.cube_rootfs_disk_free - cube /rootfs disk free (45.7)
- sensor.cube_rootfs_disk_usage - cube /rootfs disk usage (15.2)
- sensor.cube_rootfs_disk_used - cube /rootfs disk used (8.2)
- sensor.cube_rp1_adc_0_temperature - cube rp1_adc 0 temperature (132.8)
- sensor.cube_running - cube Running (0)
- sensor.cube_sleeping - cube Sleeping (111)
- sensor.cube_swap_free - cube Swap free (0.5)
- sensor.cube_swap_usage - cube Swap usage (0.0)
- sensor.cube_swap_use - cube Swap use (0.0)
- sensor.cube_threads - cube Threads (398)
- sensor.cube_total - cube Total (193)
- sensor.cube_uptime - cube Uptime (2025-08-04T03:56:31+00:00)
- sensor.cube_usr_lib_os_release_disk_free - cube /usr/lib/os-release disk free (45.7)
- sensor.cube_usr_lib_os_release_disk_usage - cube /usr/lib/os-release disk usage (15.2)
- sensor.cube_usr_lib_os_release_disk_used - cube /usr/lib/os-release disk used (8.2)
- sensor.cube_veth80a017b_rx - cube veth80a017b RX (0.003808)
- sensor.cube_veth80a017b_tx - cube veth80a017b TX (0.003152)
- sensor.cube_vetha25bf37_rx - cube vetha25bf37 RX (0.000448)
- sensor.cube_vetha25bf37_tx - cube vetha25bf37 TX (0.000472)
- sensor.cube_vethab3ef84_rx - vethab3ef84 RX (unavailable)
- sensor.cube_vethab3ef84_tx - vethab3ef84 TX (unavailable)
- sensor.cube_vethe78c618_rx - vethe78c618 RX (unavailable)
- sensor.cube_vethe78c618_tx - vethe78c618 TX (unavailable)
- sensor.cube_vethf598115_rx - cube vethf598115 RX (0.003152)
- sensor.cube_vethf598115_tx - cube vethf598115 TX (0.003808)
- sensor.cube_wlan0_rx - wlan0 RX (unavailable)
- sensor.cube_wlan0_tx - wlan0 TX (unavailable)
- sensor.current_persona - Current Persona (Default)
- sensor.glitch_cube_app_health - Glitch Cube App Health (offline)
- sensor.ha_text_ai_current_events - Current Events (ready)
- sensor.installation_health - Installation Health (critical)
- sensor.internet_connectivity - Internet Connectivity (connected)
- sensor.last_interaction_time - Last Interaction Time (2025-08-04 00:00:00)
- sensor.last_repeating_jobs_run - Last Repeating Jobs Run (2025-08-04 11:08:54 UTC)
- sensor.openweathermap_cloud_coverage - OpenWeatherMap Cloud coverage (25)
- sensor.openweathermap_condition - OpenWeatherMap Condition (partlycloudy)
- sensor.openweathermap_dew_point - OpenWeatherMap Dew Point (36.338)
- sensor.openweathermap_feels_like_temperature - OpenWeatherMap Feels like temperature (62.366)
- sensor.openweathermap_humidity - OpenWeatherMap Humidity (35)
- sensor.openweathermap_precipitation_kind - OpenWeatherMap Precipitation kind (None)
- sensor.openweathermap_pressure - OpenWeatherMap Pressure (14.6923234567948)
- sensor.openweathermap_rain - OpenWeatherMap Rain (0.0)
- sensor.openweathermap_snow - OpenWeatherMap Snow (0.0)
- sensor.openweathermap_temperature - OpenWeatherMap Temperature (64.562)
- sensor.openweathermap_uv_index - OpenWeatherMap UV Index (0)
- sensor.openweathermap_visibility - OpenWeatherMap Visibility (32808.3989501312)
- sensor.openweathermap_weather - OpenWeatherMap Weather (scattered clouds)
- sensor.openweathermap_weather_code - OpenWeatherMap Weather Code (802)
- sensor.openweathermap_wind_bearing - OpenWeatherMap Wind bearing (243)
- sensor.openweathermap_wind_speed - OpenWeatherMap Wind speed (6.19631352899069)
- sensor.sun_next_dawn - Sun Next dawn (2025-08-04T12:13:54+00:00)
- sensor.sun_next_dusk - Sun Next dusk (2025-08-05T03:51:10+00:00)
- sensor.sun_next_midnight - Sun Next midnight (2025-08-05T08:02:50+00:00)
- sensor.sun_next_noon - Sun Next noon (2025-08-04T20:03:01+00:00)
- sensor.sun_next_rising - Sun Next rising (2025-08-04T12:47:36+00:00)
- sensor.sun_next_setting - Sun Next setting (2025-08-05T03:17:36+00:00)
- sensor.tablet_battery - Tablet Battery (100)
- sensor.tablet_current_page - Tablet Current page (http://192.168.0.51:8123/lovelace/0)
- sensor.tablet_foreground_app - Tablet Foreground app (de.ozerov.fully)
- sensor.tablet_free_memory - Tablet Free memory (716.0)
- sensor.tablet_internal_storage_free_space - Tablet Internal storage free space (532.3)
- sensor.tablet_internal_storage_total_space - Tablet Internal storage total space (7800.6)
- sensor.tablet_screen_orientation - Tablet Screen orientation (90)
- sensor.tablet_total_memory - Tablet Total memory (1954.6)

### Stt (1 entities)

- stt.home_assistant_cloud - Home Assistant Cloud (unknown)

### Sun (1 entities)

- sun.sun - Sun (below_horizon)

### Switch (5 entities)

- switch.tablet_kiosk_lock - Tablet Kiosk lock (off)
- switch.tablet_maintenance_mode - Tablet Maintenance mode (off)
- switch.tablet_motion_detection - Tablet Motion detection (on)
- switch.tablet_screen - Tablet Screen (on)
- switch.tablet_screensaver - Tablet Screensaver (off)

### Todo (1 entities)

- todo.shopping_list - Shopping List (0)

### Tts (3 entities)

- tts.elevenlabs - ElevenLabs (unknown)
- tts.google_translate_en_com - Google Translate en com (unknown)
- tts.home_assistant_cloud - Home Assistant Cloud (unknown)

### Update (9 entities)

- update.chime_tts_update - Chime TTS update (off)
- update.ha_text_ai_update - HA Text AI update (off)
- update.hacs_update - HACS update (off)
- update.llm_vision_update - LLM Vision update (off)
- update.music_assistant_queue_update - Music Assistant Queue update (off)
- update.openweathermaphistory_update - openweathermaphistory update (off)
- update.passive_ble_monitor_integration_update - Passive BLE monitor integration update (off)
- update.satellite_tracker_n2yo_update - Satellite Tracker (N2YO) update (off)
- update.scheduler_component_update - Scheduler component update (off)

### Weather (2 entities)

- **weather.forecast_home** - Forecast Glitch Cube (clear-night)
- **weather.openweathermap** - OpenWeatherMap (partlycloudy)

### Zone (1 entities)

- zone.home - Glitch Cube (0)

