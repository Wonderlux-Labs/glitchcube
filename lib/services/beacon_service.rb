# frozen_string_literal: true

require 'httparty'
require 'socket'
require 'json'
require 'redis'

module Services
  class BeaconService
    include HTTParty

    def initialize
      @beacon_url = GlitchCube.config.beacon.url
      @beacon_token = GlitchCube.config.beacon.token
      @device_id = GlitchCube.config.device.id
      @location = GlitchCube.config.device.location
    end

    def send_heartbeat
      return unless beacon_enabled?

      payload = build_heartbeat_payload

      begin
        response = self.class.post(
          @beacon_url,
          body: payload.to_json,
          headers: {
            'Content-Type' => 'application/json',
            'Authorization' => "Bearer #{@beacon_token}"
          },
          timeout: 10
        )

        if response.success?
          puts "Beacon sent successfully at #{Time.now}"
          true
        else
          puts "Beacon failed: #{response.code} - #{response.message}"
          false
        end
      rescue StandardError => e
        puts "Beacon error: #{e.message}"
        false
      end
    end

    def send_alert(message, level = 'info')
      return unless beacon_enabled?

      payload = build_alert_payload(message, level)

      begin
        self.class.post(
          @beacon_url,
          body: payload.to_json,
          headers: {
            'Content-Type' => 'application/json',
            'Authorization' => "Bearer #{@beacon_token}"
          },
          timeout: 5
        )
      rescue StandardError => e
        puts "Alert beacon error: #{e.message}"
      end
    end

    private

    def beacon_enabled?
      !@beacon_url.nil? && !@beacon_url.empty? &&
        !@beacon_token.nil? && !@beacon_token.empty?
    end

    def build_heartbeat_payload
      {
        device_id: @device_id,
        type: 'heartbeat',
        timestamp: Time.now.iso8601,
        location: @location,
        network: network_info,
        system: system_info,
        app_status: app_status,
        sensor_data: fetch_sensor_data,
        recent_activity: recent_activity_summary
      }
    end

    def build_alert_payload(message, level)
      {
        device_id: @device_id,
        type: 'alert',
        timestamp: Time.now.iso8601,
        location: @location,
        level: level,
        message: message,
        network: network_info
      }
    end

    def network_info
      {
        local_ip: local_ip_address,
        public_ip: public_ip_address,
        hostname: Socket.gethostname,
        wifi_ssid: current_wifi_ssid
      }
    rescue StandardError => e
      { error: e.message }
    end

    def system_info
      {
        uptime: system_uptime,
        memory_usage: memory_usage,
        disk_usage: disk_usage,
        temperature: cpu_temperature,
        docker_status: docker_status
      }
    rescue StandardError => e
      { error: e.message }
    end

    def app_status
      {
        version: GlitchCube.config.device.version,
        rack_env: GlitchCube.config.rack_env,
        sidekiq_status: sidekiq_status,
        last_conversation: last_conversation_time,
        conversation_count_today: todays_conversation_count
      }
    end

    def fetch_sensor_data
      return {} unless defined?(HomeAssistantClient)

      client = HomeAssistantClient.new

      {
        battery_level: client.get_state('sensor.battery_level')&.dig('state'),
        temperature: client.get_state('sensor.temperature')&.dig('state'),
        motion_detected: client.get_state('binary_sensor.motion')&.dig('state') == 'on',
        light_state: client.get_state('light.glitch_cube')&.dig('state')
      }
    rescue StandardError => e
      { error: e.message }
    end

    def recent_activity_summary
      return {} unless defined?(GlitchCube::Persistence)

      recent = GlitchCube::Persistence.get_conversation_history(limit: 5)

      {
        last_interaction: recent.first&.dig(:created_at),
        interaction_count: recent.length,
        recent_topics: extract_recent_topics(recent)
      }
    rescue StandardError
      {}
    end

    def local_ip_address
      Socket.ip_address_list
        .find { |ai| ai.ipv4? && !ai.ipv4_loopback? }
        &.ip_address
    end

    def public_ip_address
      response = HTTParty.get('https://api.ipify.org?format=json', timeout: 5)
      response['ip'] if response.success?
    rescue StandardError
      nil
    end

    def current_wifi_ssid
      case RUBY_PLATFORM
      when /darwin/
        # macOS
        `/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep ' SSID' | awk '{print $2}'`.strip
      when /linux/
        # Linux (Raspberry Pi)
        `iwgetid -r`.strip
      else
        'unknown'
      end
    rescue StandardError
      'unknown'
    end

    def system_uptime
      `uptime -p`.strip
    rescue StandardError
      'unknown'
    end

    def memory_usage
      if File.exist?('/proc/meminfo')
        meminfo = File.read('/proc/meminfo')
        total = meminfo.match(/MemTotal:\s+(\d+)/)&.captures&.first.to_i
        available = meminfo.match(/MemAvailable:\s+(\d+)/)&.captures&.first.to_i

        {
          total_mb: total / 1024,
          available_mb: available / 1024,
          used_percent: ((total - available).to_f / total * 100).round(2)
        }
      else
        {}
      end
    end

    def disk_usage
      df_output = `df -h /app 2>/dev/null | tail -1`.strip
      parts = df_output.split(/\s+/)

      if parts.length >= 5
        {
          total: parts[1],
          used: parts[2],
          available: parts[3],
          percent: parts[4]
        }
      end
    rescue StandardError
      {}
    end

    def cpu_temperature
      # Raspberry Pi temperature
      (File.read('/sys/class/thermal/thermal_zone0/temp').to_i / 1000.0).round(1) if File.exist?('/sys/class/thermal/thermal_zone0/temp')
    rescue StandardError
      nil
    end

    def docker_status
      containers = `docker ps --format "{{.Names}}:{{.Status}}" 2>/dev/null`.strip.split("\n")

      containers.each_with_object({}) do |line, hash|
        name, status = line.split(':')
        hash[name] = status if name&.include?('glitch')
      end
    rescue StandardError
      {}
    end

    def sidekiq_status
      return 'unknown' unless defined?(Sidekiq)

      stats = Sidekiq::Stats.new
      {
        processed: stats.processed,
        failed: stats.failed,
        queues: stats.queues
      }
    rescue StandardError
      'unavailable'
    end

    def last_conversation_time
      # TODO: Implement when persistence is available
      nil
    end

    def todays_conversation_count
      # TODO: Implement when persistence is available
      0
    end

    def extract_recent_topics(_conversations)
      # TODO: Extract topics from recent conversations
      []
    end
  end
end
