# frozen_string_literal: true

require_relative 'openrouter_service'
require_relative 'logger_service'

module Services
  class MoodAnalyzerService
    # Mood categories compatible with TTSService.MOOD_TO_VOICE_SUFFIX
    SUPPORTED_MOODS = %i[
      friendly angry sad excited cheerful terrified hopeful
      whisper shouting unfriendly assistant chat customerservice newscast
    ].freeze

    # Mood intensity levels for lighting orchestration
    INTENSITY_LEVELS = %i[subtle moderate intense dramatic].freeze

    # Color mappings for different moods (for LightingOrchestrator)
    MOOD_COLOR_PALETTE = {
      friendly: { primary: '#00FF80', secondary: '#80FF00' },      # Green/lime
      excited: { primary: '#FF8000', secondary: '#FFD700' },       # Orange/gold
      cheerful: { primary: '#FFFF00', secondary: '#FF69B4' },      # Yellow/pink
      hopeful: { primary: '#87CEEB', secondary: '#98FB98' },       # Sky blue/pale green
      angry: { primary: '#FF0000', secondary: '#FF4500' },         # Red/orange-red
      sad: { primary: '#4169E1', secondary: '#6495ED' },           # Royal blue/cornflower
      terrified: { primary: '#8B00FF', secondary: '#FF00FF' },     # Violet/magenta
      unfriendly: { primary: '#696969', secondary: '#A9A9A9' },    # Dark/light gray
      whisper: { primary: '#E6E6FA', secondary: '#DDA0DD' },       # Lavender/plum
      shouting: { primary: '#FF1493', secondary: '#DC143C' },      # Deep pink/crimson
      assistant: { primary: '#20B2AA', secondary: '#40E0D0' },     # Light sea green/turquoise
      chat: { primary: '#32CD32', secondary: '#7CFC00' },          # Lime green/lawn green
      customerservice: { primary: '#4682B4', secondary: '#5F9EA0' }, # Steel blue/cadet blue
      newscast: { primary: '#B8860B', secondary: '#DAA520' }       # Dark goldenrod/goldenrod
    }.freeze

    class << self
      # Quick mood analysis for real-time conversation responses
      def analyze_quick(text, context = {})
        new.analyze_conversation_mood(text, context, quick: true)
      end

      # Comprehensive mood analysis for background processing
      def analyze_comprehensive(text, context = {})
        new.analyze_conversation_mood(text, context, quick: false)
      end
    end

    def initialize
      @openrouter = Services::OpenRouterService.new
      @logger = Services::LoggerService
    end

    # Main mood analysis method
    def analyze_conversation_mood(text, context = {}, quick: false)
      start_time = Time.now

      begin
        # Use quick or comprehensive analysis based on parameter
        mood_data = if quick
                      analyze_with_quick_model(text, context)
                    else
                      analyze_with_comprehensive_model(text, context)
                    end

        # Validate and enhance the mood data
        validated_mood = validate_and_enhance_mood(mood_data)

        # Log the analysis
        duration = ((Time.now - start_time) * 1000).round
        @logger.log_api_call(
          service: 'mood_analyzer',
          endpoint: quick ? 'quick_analysis' : 'comprehensive_analysis',
          duration: duration,
          mood_detected: validated_mood[:primary_mood],
          confidence: validated_mood[:confidence]
        )

        validated_mood
      rescue StandardError => e
        @logger.log_api_call(
          service: 'mood_analyzer',
          endpoint: 'analysis_error',
          error: e.message
        )
        
        # Return fallback mood for graceful degradation
        fallback_mood(text)
      end
    end

    private

    # Quick analysis using smaller, faster model
    def analyze_with_quick_model(text, context)
      model = GlitchCube::ModelPresets.get_model(:conversation_small)
      
      prompt = build_quick_analysis_prompt(text, context)
      
      response = @openrouter.complete_with_json_schema(
        prompt,
        model: model,
        schema: mood_analysis_schema,
        temperature: 0.3
      )

      parse_mood_response(response)
    end

    # Comprehensive analysis using more powerful model
    def analyze_with_comprehensive_model(text, context)
      model = GlitchCube::ModelPresets.get_model(:conversation_default)
      
      prompt = build_comprehensive_analysis_prompt(text, context)
      
      response = @openrouter.complete_with_json_schema(
        prompt,
        model: model,
        schema: comprehensive_mood_analysis_schema,
        temperature: 0.4
      )

      parse_comprehensive_mood_response(response)
    end

    # Build prompt for quick mood analysis
    def build_quick_analysis_prompt(text, context)
      <<~PROMPT
        Analyze the emotional tone of this conversation text and determine the primary mood.

        Text: "#{text}"
        
        #{context_prompt_section(context)}

        Available moods: #{SUPPORTED_MOODS.join(', ')}
        
        Respond with JSON containing:
        - primary_mood: One of the available moods
        - confidence: Float between 0.0 and 1.0
        - intensity: One of: #{INTENSITY_LEVELS.join(', ')}
        - reasoning: Brief explanation
      PROMPT
    end

    # Build prompt for comprehensive mood analysis
    def build_comprehensive_analysis_prompt(text, context)
      <<~PROMPT
        Perform a comprehensive mood analysis of this conversation text, considering emotional nuance, context, and conversational dynamics.

        Text: "#{text}"
        
        #{context_prompt_section(context)}

        Available moods: #{SUPPORTED_MOODS.join(', ')}
        Intensity levels: #{INTENSITY_LEVELS.join(', ')}

        Consider:
        - Primary emotional tone and secondary undertones
        - Conversational energy level and excitement
        - Contextual factors that might influence mood expression
        - How this mood should be expressed through voice and lighting

        Respond with detailed mood analysis in JSON format.
      PROMPT
    end

    # Build context section for prompts
    def context_prompt_section(context)
      return '' if context.empty?

      sections = []
      sections << "Previous mood: #{context[:previous_mood]}" if context[:previous_mood]
      sections << "Conversation history: #{context[:history_summary]}" if context[:history_summary]
      sections << "Time of day: #{context[:time_of_day]}" if context[:time_of_day]
      sections << "User engagement level: #{context[:engagement_level]}" if context[:engagement_level]

      sections.empty? ? '' : "\nContext:\n#{sections.join("\n")}\n"
    end

    # JSON schema for quick analysis
    def mood_analysis_schema
      {
        type: 'object',
        properties: {
          primary_mood: { 
            type: 'string', 
            enum: SUPPORTED_MOODS.map(&:to_s) 
          },
          confidence: { 
            type: 'number', 
            minimum: 0.0, 
            maximum: 1.0 
          },
          intensity: { 
            type: 'string', 
            enum: INTENSITY_LEVELS.map(&:to_s) 
          },
          reasoning: { 
            type: 'string' 
          }
        },
        required: %w[primary_mood confidence intensity reasoning]
      }
    end

    # JSON schema for comprehensive analysis
    def comprehensive_mood_analysis_schema
      schema = mood_analysis_schema.deep_dup
      schema[:properties].merge!({
        secondary_moods: {
          type: 'array',
          items: { type: 'string', enum: SUPPORTED_MOODS.map(&:to_s) },
          maxItems: 3
        },
        emotional_dynamics: {
          type: 'object',
          properties: {
            energy_level: { type: 'number', minimum: 0.0, maximum: 1.0 },
            stability: { type: 'number', minimum: 0.0, maximum: 1.0 },
            openness: { type: 'number', minimum: 0.0, maximum: 1.0 }
          }
        },
        lighting_recommendations: {
          type: 'object',
          properties: {
            color_temperature: { type: 'string', enum: %w[warm neutral cool] },
            transition_speed: { type: 'string', enum: %w[slow medium fast] },
            brightness_level: { type: 'number', minimum: 0.0, maximum: 1.0 }
          }
        }
      })
      schema
    end

    # Parse mood response from LLM
    def parse_mood_response(response)
      mood_data = response.is_a?(Hash) ? response : JSON.parse(response)
      
      {
        primary_mood: mood_data['primary_mood']&.to_sym,
        confidence: mood_data['confidence']&.to_f || 0.5,
        intensity: mood_data['intensity']&.to_sym || :moderate,
        reasoning: mood_data['reasoning'] || 'Analysis completed',
        timestamp: Time.now
      }
    end

    # Parse comprehensive mood response
    def parse_comprehensive_mood_response(response)
      mood_data = response.is_a?(Hash) ? response : JSON.parse(response)
      
      basic_data = parse_mood_response(response)
      
      basic_data.merge({
        secondary_moods: mood_data['secondary_moods']&.map(&:to_sym) || [],
        emotional_dynamics: mood_data['emotional_dynamics'] || {},
        lighting_recommendations: mood_data['lighting_recommendations'] || {}
      })
    end

    # Validate mood data and add enhancements
    def validate_and_enhance_mood(mood_data)
      # Ensure primary mood is valid
      primary_mood = mood_data[:primary_mood]
      unless SUPPORTED_MOODS.include?(primary_mood)
        primary_mood = :friendly # Safe fallback
      end

      # Ensure confidence is within bounds
      confidence = [0.0, [1.0, mood_data[:confidence] || 0.5].min].max

      # Ensure intensity is valid
      intensity = INTENSITY_LEVELS.include?(mood_data[:intensity]) ? mood_data[:intensity] : :moderate

      # Add color palette for lighting integration
      color_palette = MOOD_COLOR_PALETTE[primary_mood] || MOOD_COLOR_PALETTE[:friendly]

      mood_data.merge({
        primary_mood: primary_mood,
        confidence: confidence,
        intensity: intensity,
        color_palette: color_palette,
        tts_compatible: true, # Flag indicating TTS service compatibility
        lighting_ready: true  # Flag indicating LightingOrchestrator compatibility
      })
    end

    # Fallback mood when analysis fails
    def fallback_mood(text)
      # Simple keyword-based fallback
      fallback_primary = if text.include?('!') || text.include?('wow') || text.include?('amazing')
                           :excited
                         elsif text.include?('?') && text.length < 50
                           :friendly
                         else
                           :chat
                         end

      {
        primary_mood: fallback_primary,
        confidence: 0.3,
        intensity: :moderate,
        reasoning: 'Fallback analysis - service degraded',
        color_palette: MOOD_COLOR_PALETTE[fallback_primary],
        tts_compatible: true,
        lighting_ready: true,
        timestamp: Time.now,
        fallback_used: true
      }
    end
  end
end