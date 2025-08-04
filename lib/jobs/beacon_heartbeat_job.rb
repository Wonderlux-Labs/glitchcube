# frozen_string_literal: true

require 'desiru/jobs/base'
require 'desiru/jobs/scheduler'
require_relative '../services/beacon_service'

module Jobs
  class BeaconHeartbeatJob < Desiru::Jobs::Base
    include Desiru::Jobs::Schedulable

    def perform(job_id = nil)
      beacon = Services::BeaconService.new
      success = beacon.send_heartbeat

      # Store the result using Desiru's job result storage
      store_result(job_id || "beacon-heartbeat-#{Time.now.to_i}", {
                     status: success ? 'completed' : 'failed',
                     timestamp: Time.now.iso8601,
                     device_id: GlitchCube.config.device.id
                   })
    rescue StandardError => e
      Desiru.logger.error "Beacon heartbeat failed: #{e.message}"

      # Store failure result
      store_result(job_id || "beacon-heartbeat-#{Time.now.to_i}", {
                     status: 'error',
                     error: e.message,
                     timestamp: Time.now.iso8601
                   })
    end
  end

  # Job to send critical alerts
  class BeaconAlertJob < Desiru::Jobs::Base
    include Desiru::Jobs::Schedulable

    def perform(job_id = nil, message = nil, level = 'info')
      return unless message

      beacon = Services::BeaconService.new
      beacon.send_alert(message, level)

      # Store the result
      store_result(job_id || "beacon-alert-#{Time.now.to_i}", {
                     status: 'sent',
                     message: message,
                     level: level,
                     timestamp: Time.now.iso8601
                   })
    rescue StandardError => e
      Desiru.logger.error "Beacon alert failed: #{e.message}"

      store_result(job_id || "beacon-alert-#{Time.now.to_i}", {
                     status: 'error',
                     error: e.message,
                     timestamp: Time.now.iso8601
                   })
    end
  end
end
