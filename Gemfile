# frozen_string_literal: true

source 'https://rubygems.org'

# Core
gem 'puma', '~> 6.6'
gem 'rake', '~> 13.3'
gem 'sinatra', '~> 4.1'
gem 'sinatra-contrib', '~> 4.1'

# AI & API
gem 'open_router', '~> 0.3'

# Database
gem 'pg', '~> 1.5'
gem 'activerecord', '~> 7.2'
gem 'sinatra-activerecord', '~> 2.0'

# API Support
gem 'grape', '~> 2.4'
gem 'ostruct'
gem 'rack-cors', '~> 3.0'

# Environment and Configuration
gem 'dotenv', '~> 3.1'

# Timezone handling
gem 'tzinfo', '~> 2.0'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

# Background Jobs
gem 'redis', '~> 5.4'
gem 'sidekiq', '~> 7.3'
gem 'sidekiq-cron', '~> 1.12'

# HTTP Client
gem 'httparty', '~> 0.23'
gem 'net-ping', '~> 2.0'

# JSON handling
gem 'json', '~> 2.13'

# Development and Test
group :development, :test do
  gem 'pry', '~> 0.15'
  gem 'rack-test', '~> 2.2'
  gem 'rspec', '~> 3.13'
  gem 'rspec_junit_formatter', '~> 0.6' # For CI test reporting
  gem 'rubocop', '~> 1.79'
  gem 'rubocop-rspec', '~> 3.6'
  gem 'simplecov', '~> 0.22', require: false
  gem 'vcr', '~> 6.3'
  gem 'webmock', '~> 3.25'
end

# Production
group :production do
  gem 'rack-protection', '~> 4.1'
end

gem 'rackup', '~> 2.2'
