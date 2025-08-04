Project Brief: Glitch Cube Interactive Art Installation
Overview:
Autonomous interactive art installation designed for mobile deployment. A self-contained "smart cube" that engages with participants through conversation, requests transportation, and builds relationships over multi-day events.
Technical Architecture:

Backend: Ruby/Sinatra web application handling personality logic, conversation flow, and decision-making
IoT Integration: Home Assistant managing sensor data, hardware states, and logging
Connectivity: Starlink internet for real-time AI conversations and data sync
Power: 24-hour battery with social charging requests (participants take it "home" to recharge)

Hardware Integration:

Camera (participant interaction documentation)
Speaker (voice output, ambient sounds)
RGB lighting system (mood/status indication)
Motion sensor (proximity detection, engagement triggers)
GPS module (location tracking, journey mapping)
Light sensor (day/night behavior adaptation)

Core Behaviors:

Initiates conversations with passersby
Requests transportation to specific locations
Switches between multiple personality modes
Maintains persistent memory of interactions and locations
Manages own power needs through social requests
Documents experiences via sensors and conversations

Development Priorities:

Home Assistant sensor integration and data pipeline
Sinatra routing for personality switching and conversation logic
Hardware abstraction layer for sensor/output management
Persistent data storage for journey/interaction logging
Power management and "sleepy mode" social protocols

Target Environment: Multi-day outdoor art events, dusty conditions, 24/7 autonomous operation.