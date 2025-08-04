# frozen_string_literal: true

module TestModule
  def self.name
    'Test Module'
  end

  def self.description
    'A simple test module for Glitch Cube'
  end

  def handle_greeting(message)
    return unless message.downcase.include?('hello') || message.downcase.include?('hi')

    "Greetings from the Glitch Cube! I'm a sentient art installation experiencing reality through sensors and conversation."
  end

  def handle_status_check(message)
    return unless message.downcase.include?('status') || message.downcase.include?('how are you')

    'All systems operational. Battery at optimal levels. Ready for interaction and transportation requests.'
  end

  def process(message, _assistant, _conversation)
    handle_greeting(message) || handle_status_check(message)
  end
end
