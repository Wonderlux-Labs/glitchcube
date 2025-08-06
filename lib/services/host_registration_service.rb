# frozen_string_literal: true

require 'socket'
require 'net/ping'
require_relative '../home_assistant_client'
require_relative 'logger_service'

module Services
  class HostRegistrationService
    class Error < StandardError; end

    GLITCHCUBE_HOST_ENTITY = 'input_text.glitchcube_host'
    REGISTRATION_INTERVAL = 300 # 5 minutes

    def self.register_with_home_assistant
      new.register_with_home_assistant
    end

    def self.register_with_retry_loop
      new.register_with_retry_loop
    end

    def register_with_retry_loop
      max_attempts = 20
      attempt = 1
      
      puts "🔄 Starting host registration with Home Assistant (max #{max_attempts} attempts)..."
      
      while attempt <= max_attempts
        puts "  Attempt #{attempt}/#{max_attempts}..."
        
        if register_with_home_assistant
          puts "✅ Successfully registered with Home Assistant!"
          return true
        end
        
        # Progressive backoff: 5s, 10s, 15s, then 30s intervals
        sleep_time = case attempt
                     when 1..3
                       5 * attempt
                     else
                       30
                     end
        
        puts "  ⏳ Waiting #{sleep_time}s before retry..."
        sleep(sleep_time)
        attempt += 1
      end
      
      puts "❌ Failed to register with Home Assistant after #{max_attempts} attempts"
      false
    end

    def register_with_home_assistant
      current_ip = detect_local_ip
      return false unless current_ip

      # Test connectivity to Home Assistant
      ha_host = extract_host_from_url(GlitchCube.config.home_assistant.url)
      unless ping_host(ha_host)
        Services::LoggerService.log_api_call(
          service: 'host_registration',
          endpoint: 'ping_test',
          error: "Cannot reach Home Assistant at #{ha_host}"
        )
        return false
      end

      # Register our IP with Home Assistant
      ha_client = HomeAssistantClient.new
      begin
        # Set the input_text entity with our current IP
        ha_client.set_state(
          GLITCHCUBE_HOST_ENTITY,
          current_ip,
          {
            friendly_name: 'Glitch Cube Host IP',
            icon: 'mdi:cube-outline',
            last_updated: Time.now.iso8601,
            registered_from: Socket.gethostname
          }
        )

        Services::LoggerService.log_api_call(
          service: 'host_registration',
          endpoint: 'register_ip',
          status: 200,
          ip_registered: current_ip,
          hostname: Socket.gethostname
        )

        puts "✅ Registered Glitch Cube at #{current_ip} with Home Assistant"
        true
      rescue HomeAssistantClient::Error => e
        Services::LoggerService.log_api_call(
          service: 'host_registration',
          endpoint: 'register_ip',
          error: "Failed to register IP: #{e.message}"
        )
        puts "❌ Failed to register with Home Assistant: #{e.message}"
        false
      end
    end

    private

    def detect_local_ip
      # Connect to a dummy address to determine our local IP
      # This doesn't actually send data, just determines routing
      socket = UDPSocket.new
      socket.connect('8.8.8.8', 80) # Google DNS
      local_ip = socket.addr.last
      socket.close
      
      # Validate it's a private IP address
      if private_ip?(local_ip)
        local_ip
      else
        # Fallback: get IP from network interfaces
        detect_ip_from_interfaces
      end
    rescue StandardError => e
      puts "⚠️  Error detecting IP via socket: #{e.message}"
      detect_ip_from_interfaces
    end

    def detect_ip_from_interfaces
      # Get all network interfaces and find the first non-loopback IPv4 address
      Socket.ip_address_list.each do |addr|
        next unless addr.ipv4? && !addr.ipv4_loopback? && !addr.ipv4_multicast?
        ip = addr.ip_address
        return ip if private_ip?(ip)
      end
      
      nil
    end

    def private_ip?(ip)
      # Check if IP is in private ranges
      octets = ip.split('.').map(&:to_i)
      return false unless octets.length == 4

      # 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
      (octets[0] == 10) ||
        (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
        (octets[0] == 192 && octets[1] == 168)
    end

    def extract_host_from_url(url)
      return 'localhost' unless url
      URI.parse(url).host
    rescue URI::InvalidURIError
      'localhost'
    end

    def ping_host(host, timeout: 3)
      Net::Ping::External.new(host).ping
    rescue StandardError
      false
    end
  end
end