# frozen_string_literal: true

module Services
  module OpenRouter
    # Caches model availability data to reduce API calls
    class ModelCache
      def initialize
        @cache = {}
      end

      def available_models(client)
        cache_key = :models

        if cached?(cache_key)
          @cache[cache_key][:data]
        else
          fetch_and_cache_models(client)
        end
      end

      def clear!
        @cache = {}
      end

      private

      def cached?(key)
        @cache[key] && @cache[key][:expires] > Time.now
      end

      def fetch_and_cache_models(client)
        models = client.models
        @cache[:models] = {
          data: models,
          expires: Time.now + 3600 # 1 hour cache
        }
        models
      end
    end
  end
end
