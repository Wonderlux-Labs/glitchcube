# frozen_string_literal: true

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc 'Run the application'
task :run do
  exec 'bundle exec ruby app.rb'
end

desc 'Run the application with Puma'
task :puma do
  exec 'bundle exec puma -C config/puma.rb'
end

desc 'Start Sidekiq'
task :sidekiq do
  exec 'bundle exec sidekiq'
end

desc 'Console with application loaded'
task :console do
  exec 'bundle exec pry -r ./app.rb'
end
