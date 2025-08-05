# frozen_string_literal: true

module GlitchCube
  module Routes
    module Core
      module Kiosk
        def self.registered(app)
          # Kiosk web interface
          app.get '/kiosk' do
            erb :kiosk, views: File.expand_path('../../../views', __dir__)
          end

          # Kiosk data API endpoint
          app.get '/api/v1/kiosk/status' do
            content_type :json

            begin
              require_relative '../../services/kiosk_service'
              kiosk_service = Services::KioskService.new

              json(kiosk_service.get_status)
            rescue StandardError => e
              status 500
              json({
                     error: e.message,
                     timestamp: Time.now.iso8601
                   })
            end
          end
        end
      end
    end
  end
end