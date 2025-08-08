# frozen_string_literal: true

module LogHelper
  def self.log(message, level = :info)
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S.%L')
    formatted = "[#{timestamp}] #{message}"
    
    case level
    when :error
      puts "❌ #{formatted}"
    when :warning
      puts "⚠️  #{formatted}"
    when :success
      puts "✅ #{formatted}"
    when :debug
      puts "🔍 #{formatted}" if ENV['DEBUG']
    else
      puts formatted
    end
  end

  def self.error(message)
    log(message, :error)
  end

  def self.warning(message)
    log(message, :warning)
  end

  def self.success(message)
    log(message, :success)
  end

  def self.debug(message)
    log(message, :debug)
  end
end