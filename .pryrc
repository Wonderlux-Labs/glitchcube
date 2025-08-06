# frozen_string_literal: true

# Pry configuration for GlitchCube project

# Load the app if not already loaded
unless defined?(GlitchCubeApp)
  require_relative 'app'
  Dir[File.join(__dir__, 'lib/**/*.rb')].each { |f| require f }
end

# Helpful aliases
Pry.config.commands.alias_command 'r', 'reload!'
Pry.config.commands.alias_command 'c', 'continue'
Pry.config.commands.alias_command 's', 'step'
Pry.config.commands.alias_command 'n', 'next'
Pry.config.commands.alias_command 'q', 'exit'

# Custom commands
Pry::Commands.create_command 'test-tts' do
  description 'Test TTS with a character'

  def options(opt)
    opt.on :c, :character=, 'Character to use (default: default)'
    opt.on :m, :message=, 'Message to speak'
  end

  def process
    character = opts[:c] || :default
    message = opts[:m] || 'Testing TTS from Pry console!'

    tts = Services::CharacterService.new(character: character.to_sym)
    result = tts.speak(message)
    output.puts result ? "✅ Spoke as #{character}" : '❌ TTS failed'
  end
end

Pry::Commands.create_command 'characters' do
  description 'List available characters'

  def process
    Services::CharacterService::CHARACTERS.each do |key, char|
      output.puts "#{key.to_s.ljust(10)} - #{char[:name]} (#{char[:voice_id]})"
      output.puts "             #{char[:description]}"
      output.puts ''
    end
  end
end

# Pretty print for better output
begin
  require 'awesome_print'
  Pry.config.print = proc { |output, value| output.puts value.ai }
rescue LoadError
  # awesome_print not available
end

# History file
Pry.config.history_file = "#{Dir.home}/.pry_history_glitchcube"

# Welcome message for project-specific console
if $PROGRAM_NAME == 'bin/console' || $PROGRAM_NAME.end_with?('pry')
  puts '🎲 GlitchCube project loaded!'
  puts '   Custom commands: test-tts, characters'
  puts '   Aliases: r=reload!, c=continue, s=step, n=next, q=exit'
end
