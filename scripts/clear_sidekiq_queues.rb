#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to clear Sidekiq queues of old/stale jobs

require_relative '../config/environment'
require 'sidekiq/api'

puts '🗑️  Clearing Sidekiq queues...'

# Clear all queues
cleared = {}
%w[default critical low summaries].each do |queue_name|
  queue = Sidekiq::Queue.new(queue_name)
  size = queue.size
  queue.clear
  cleared[queue_name] = size
  puts "   Cleared #{size} jobs from #{queue_name} queue"
end

# Clear retry set
retry_set = Sidekiq::RetrySet.new
retry_size = retry_set.size
retry_set.clear
cleared['retry'] = retry_size
puts "   Cleared #{retry_size} jobs from retry set"

# Clear dead set
dead_set = Sidekiq::DeadSet.new
dead_size = dead_set.size
dead_set.clear
cleared['dead'] = dead_size
puts "   Cleared #{dead_size} jobs from dead set"

puts "\n✅ Successfully cleared all queues:"
cleared.each do |queue, count|
  puts "   #{queue}: #{count} jobs"
end

puts "\n🔄 Current queue status after clearing:"
%w[default critical low summaries].each do |queue_name|
  queue = Sidekiq::Queue.new(queue_name)
  puts "   #{queue_name}: #{queue.size} jobs"
end
