# frozen_string_literal: true

require 'json'
require_relative '../../services/proactive_interaction_service'

module GlitchCube
  module Routes
    module Api
      module Proactive
        def self.registered(app)
          # POST /api/v1/proactive/attention
          app.post '/api/v1/proactive/attention' do
            content_type :json
            
            begin
              params = JSON.parse(request.body.read) rescue {}
              level = params['level'] || 'moderate'
              
              result = Services::ProactiveInteractionService.seek_attention(loneliness_level: level)
              
              if result[:success]
                status 200
                { success: true, data: result }.to_json
              else
                status 500
                { success: false, error: result[:error] }.to_json
              end
            rescue StandardError => e
              status 500
              { success: false, error: e.message }.to_json
            end
          end
          
          # POST /api/v1/proactive/mood
          app.post '/api/v1/proactive/mood' do
            content_type :json
            
            begin
              params = JSON.parse(request.body.read) rescue {}
              mood = params['mood'] || 'happy'
              reason = params['reason']
              
              result = Services::ProactiveInteractionService.express_mood(mood, reason)
              
              if result[:success]
                status 200
                { success: true, data: result }.to_json
              else
                status 500
                { success: false, error: result[:error] }.to_json
              end
            rescue StandardError => e
              status 500
              { success: false, error: e.message }.to_json
            end
          end
          
          # POST /api/v1/proactive/custom
          app.post '/api/v1/proactive/custom' do
            content_type :json
            
            begin
              params = JSON.parse(request.body.read) rescue {}
              prompt = params['prompt'] || "Express yourself!"
              persona = params['persona'] || 'playful'
              
              result = Services::ProactiveInteractionService.call(
                prompt: prompt,
                persona: persona,
                event_type: params['event_type']
              )
              
              if result[:success]
                status 200
                { success: true, data: result }.to_json
              else
                status 500
                { success: false, error: result[:error] }.to_json
              end
            rescue StandardError => e
              status 500
              { success: false, error: e.message }.to_json
            end
          end
          
          # POST /api/v1/proactive/morning
          app.post '/api/v1/proactive/morning' do
            content_type :json
            
            begin
              result = Services::ProactiveInteractionService.morning_greeting
              
              if result[:success]
                status 200
                { success: true, data: result }.to_json
              else
                status 500
                { success: false, error: result[:error] }.to_json
              end
            rescue StandardError => e
              status 500
              { success: false, error: e.message }.to_json
            end
          end
          
          # POST /api/v1/proactive/night
          app.post '/api/v1/proactive/night' do
            content_type :json
            
            begin
              result = Services::ProactiveInteractionService.nighttime_lullaby
              
              if result[:success]
                status 200
                { success: true, data: result }.to_json
              else
                status 500
                { success: false, error: result[:error] }.to_json
              end
            rescue StandardError => e
              status 500
              { success: false, error: e.message }.to_json
            end
          end
        end
      end
    end
  end
end