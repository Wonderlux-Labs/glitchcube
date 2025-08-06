# frozen_string_literal: true

require_relative '../unified_logger_service'

module Services
  module OpenRouter
    # Handles API request/response cycle with logging
    class RequestHandler
      def initialize(client)
        @client = client
      end

      def make_api_call(request_params)
        start_time = Time.now

        begin
          response = @client.complete(request_params)
          log_successful_call(request_params, response, start_time)
          response
        rescue StandardError => e
          log_failed_call(request_params, e, start_time)
          raise e
        end
      end

      private

      def log_successful_call(request_params, response, start_time)
        duration = calculate_duration(start_time)
        tokens = extract_token_usage(response)

        Services::UnifiedLoggerService.api_call(
          service: 'openrouter',
          endpoint: 'chat/completions',
          method: 'POST',
          status: 200,
          duration: duration,
          model: request_params[:model],
          request_size: calculate_request_size(request_params),
          response_size: calculate_response_size(response),
          tokens: tokens,
          temperature: request_params[:temperature],
          max_tokens: request_params[:max_tokens]
        )
      end

      def log_failed_call(request_params, error, start_time)
        duration = calculate_duration(start_time)

        Services::UnifiedLoggerService.api_call(
          service: 'openrouter',
          endpoint: 'chat/completions',
          method: 'POST',
          status: 500,
          duration: duration,
          error: error.message,
          model: request_params[:model],
          request_size: calculate_request_size(request_params),
          temperature: request_params[:temperature],
          max_tokens: request_params[:max_tokens]
        )
      end

      def calculate_duration(start_time)
        ((Time.now - start_time) * 1000).round
      end

      def calculate_request_size(params)
        # Estimate request size based on message content
        message_content = params[:messages]&.map { |m| m[:content] }&.join(' ') || ''
        message_content.bytesize
      end

      def calculate_response_size(response)
        # Estimate response size
        content = response.dig('choices', 0, 'message', 'content') || ''
        content.bytesize
      end

      def extract_token_usage(response)
        usage = response['usage']
        return nil unless usage

        {
          prompt_tokens: usage['prompt_tokens'],
          completion_tokens: usage['completion_tokens'],
          total_tokens: usage['total_tokens']
        }
      end
    end
  end
end
