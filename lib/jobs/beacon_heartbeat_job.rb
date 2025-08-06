# frozen_string_literal: true

require 'sidekiq'
require_relative '../services/beacon_service'

module Jobs
  class BeaconHeartbeatJob
    include Sidekiq::Worker
    
    sidekiq_options queue: 'default', retry: 3

    def perform
      beacon = Services::BeaconService.new
      success = beacon.send_heartbeat

      logger.info "Beacon heartbeat #{success ? 'sent' : 'failed'} at #{Time.now.iso8601}"
    rescue StandardError => e
      logger.error "Beacon heartbeat failed: #{e.message}"
      raise # Re-raise for Sidekiq retry
    end
  end

  # Job to send critical alerts
  class BeaconAlertJob
    include Sidekiq::Worker
    
    sidekiq_options queue: 'alerts', retry: 5

    def perform(message = nil, level = 'info')
      return unless message

      beacon = Services::BeaconService.new
      beacon.send_alert(message, level)

      logger.info "Beacon alert sent: #{message} (#{level})"
    rescue StandardError => e
      logger.error "Beacon alert failed: #{e.message}"
      raise # Re-raise for Sidekiq retry
    end
  end
end