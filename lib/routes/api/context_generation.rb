# frozen_string_literal: true

module Routes
  module Api
    class ContextGeneration < Sinatra::Base
      post '/api/v1/context/generate' do
        content_type :json

        # Parse HA webhook request
        data = JSON.parse(request.body.read)
        model = data['model'] || 'google/gemini-2.0-flash-thinking-exp:free'
        prompt = data['prompt']
        sensor = data['sensor'] || 'sensor.glitchcube_context'
        attribute = data['attribute'] || 'state' # or '1hr_summary', '4hr_summary', etc.

        # Queue background job for LLM call
        ContextGenerationJob.perform_async(
          model: model,
          prompt: prompt,
          sensor: sensor,
          attribute: attribute
        )

        { status: 'queued', sensor: sensor, attribute: attribute }.to_json
      end
    end
  end
end
