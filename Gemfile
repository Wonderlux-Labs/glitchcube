# frozen_string_literal: true

source 'https://rubygems.org'

# Core
gem 'puma', '~> 6.0'
gem 'rake', '~> 13.0'
gem 'sinatra', '~> 3.0'
gem 'sinatra-contrib', '~> 3.0'

# Desiru AI Framework
gem 'anthropic', '~> 0.1'
gem 'desiru', git: 'https://github.com/estiens/desiru.git', branch: 'main'
gem 'grape', '~> 2.0'
gem 'open_router', '~> 0.1'
gem 'ostruct'
gem 'rack-cors', '~> 2.0'
gem 'ruby-openai', '~> 7.0'
gem 'sequel', '~> 5.0'
gem 'sqlite3', '~> 1.5' # For local persistence

# Environment and Configuration
gem 'dotenv', '~> 2.8'

# Timezone handling
gem 'tzinfo', '~> 2.0'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

# Background Jobs
gem 'redis', '~> 5.0'
gem 'sidekiq', '~> 7.0'

# HTTP Client
gem 'httparty', '~> 0.21'

# JSON handling
gem 'json', '~> 2.6'

# Development and Test
group :development, :test do
  gem 'pry', '~> 0.14'
  gem 'rack-test', '~> 2.0'
  gem 'rspec', '~> 3.12'
  gem 'rspec_junit_formatter', '~> 0.6' # For CI test reporting
  gem 'rubocop'
  gem 'rubocop-rspec'
  gem 'simplecov', '~> 0.22', require: false
  gem 'vcr', '~> 6.2'
  gem 'webmock', '~> 3.19'
end

# Production
group :production do
  gem 'rack-protection', '~> 3.0'
end
