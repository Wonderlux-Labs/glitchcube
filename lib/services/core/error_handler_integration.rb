# frozen_string_literal: true

require 'English'
require_relative '../../modules/globals'

module Services
  module Core
    module ErrorHandlerIntegration
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def with_error_healing(&block)
          block.call
        rescue StandardError => e
          log_exception(e, caller_context.merge(handler_type: 'class_method'))
          handle_error_with_healing(e, caller_context)
          raise # Re-raise after handling
        end

        private

        def log_exception(error, context)
          G.logger.error "[ErrorHandler] Exception caught: #{error.class.name}: #{error.message}"
          G.logger.error "[ErrorHandler] Context: #{context.inspect}"
          G.logger.error "[ErrorHandler] Backtrace: #{error.backtrace&.first(10)&.join("\n")}"
          G.set_world_state(attr: 'last_error', val: "#{error.class.name}: #{error.message}")
        end

        def handle_error_with_healing(error, context)
          return unless GlitchCube.config.self_healing_enabled?

          handler = Services::ErrorHandlingLLM.new

          # Extract context from caller
          caller_info = caller_locations(2, 1).first
          enhanced_context = context.merge(
            file: caller_info.path,
            line: caller_info.lineno,
            method: caller_info.label,
            service: self.class.name
          )

          handler.handle_error(error, enhanced_context)
        end

        def caller_context
          {
            timestamp: Time.now.iso8601,
            environment: GlitchCube.config.rack_env
          }
        end
      end

      # Instance method version
      def with_error_healing(&block)
        block.call
      rescue StandardError => e
        log_exception(e, instance_context.merge(handler_type: 'instance_method'))
        handle_error_with_healing(e)
        raise
      end

      private

      def log_exception(error, context)
        GlitchCube.logger.error "[ErrorHandler] Exception caught: #{error.class.name}: #{error.message}"
        GlitchCube.logger.error "[ErrorHandler] Context: #{context.inspect}"
        GlitchCube.logger.error "[ErrorHandler] Backtrace: #{error.backtrace&.first(10)&.join("\n")}"
      end

      def instance_context
        caller_info = caller_locations(2, 1).first
        {
          file: caller_info.path,
          line: caller_info.lineno,
          method: caller_info.label,
          service: self.class.name,
          timestamp: Time.now.iso8601,
          environment: GlitchCube.config.rack_env
        }
      end

      def handle_error_with_healing(error)
        return unless GlitchCube.config.self_healing_enabled?

        handler = Services::ErrorHandlingLLM.new

        caller_info = caller_locations(2, 1).first
        context = {
          file: caller_info.path,
          line: caller_info.lineno,
          method: caller_info.label,
          service: self.class.name,
          timestamp: Time.now.iso8601,
          environment: GlitchCube.config.rack_env
        }

        handler.handle_error(error, context)
      end
    end

    # Global error handler for uncaught exceptions
    module GlobalErrorHandler
      def self.setup!
        return unless GlitchCube.config.self_healing_enabled?

        # Hook into uncaught exceptions
        at_exit do
          if $ERROR_INFO && !$ERROR_INFO.is_a?(SystemExit)
            context = {
              service: 'GlobalHandler',
              method: 'uncaught_exception',
              timestamp: Time.now.iso8601,
              environment: GlitchCube.config.rack_env,
              handler_type: 'global_handler'
            }

            log_global_exception($ERROR_INFO, context)

            handler = Services::ErrorHandlingLLM.new
            handler.handle_error($ERROR_INFO, context)
          end
        end
      end

      private

      def self.log_global_exception(error, context)
        GlitchCube.logger.error "[GlobalErrorHandler] Uncaught exception: #{error.class.name}: #{error.message}"
        GlitchCube.logger.error "[GlobalErrorHandler] Context: #{context.inspect}"
        GlitchCube.logger.error "[GlobalErrorHandler] Backtrace: #{error.backtrace&.first(10)&.join("\n")}"
      end
    end
  end
end
