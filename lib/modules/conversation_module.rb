# frozen_string_literal: true

require 'securerandom'
require 'concurrent'

require_relative '../services/conversation/conversation_flow_manager'
require_relative 'error_handling'
class ConversationModule
  include ErrorHandling

  # Convenience class methods for each persona
  # Class method to switch persona programmatically
  # This updates Redis state and syncs with Home Assistant
  def self.switch_persona(persona_name)
    Services::PersonaStateService.set_current_persona(persona_name)
  end

  # Get the current active persona
  def self.current_persona
    Services::PersonaStateService.get_current_persona
  end

  # These convenience methods set the persona and return a new instance
  def self.buddy
    switch_persona('buddy')
    new
  end

  def self.jax
    switch_persona('jax')
    new
  end

  def self.lomi
    switch_persona('lomi')
    new
  end

  def self.zorp
    switch_persona('zorp')
    new
  end

  def self.default
    new
  end

  def initialize
    @flow_manager = Services::Conversation::FlowManager.new
  end

  def call(message:, context: {}, persona: nil)
    # Simple logging instead of complex tracing
    persona_name = persona || context[:persona] || Services::PersonaStateService.get_current_persona
    Services::Logging::SimpleLogger.debug('Conversation started', tagged: [:conversation], persona: persona_name, message_preview: message[0..100])

    begin
      start_time = Time.now
      result = @flow_manager.process_conversation(message: message, context: context, persona: persona)

      total_duration = ((Time.now - start_time) * 1000).round
      Services::Logging::SimpleLogger.info('Conversation completed', tagged: [:conversation], duration_ms: total_duration)

      result
    rescue Services::LLMService::RateLimitError, Services::LLMService::LLMError, StandardError => e
      puts "CAUGHT ERROR: #{e.class.name} - #{e.message}\n#{e.backtrace.join("\n")}"
      Services::Logging::SimpleLogger.log_error(error: e, message: 'Conversation error occurred', tagged: %i[conversation error])

      Services::Conversation::ErrorHandler.handle(
        e,
        session: nil, # Session is now managed within the flow
        message: message,
        persona: persona_name,
        context: context
      )
    end
  end
end
