#!/usr/bin/env ruby
# Debug script to test conversation endpoint without VCR

require_relative 'spec/spec_helper'
require 'rack/test'

class TestApp
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  def test_conversation
    begin
      puts "Testing conversation endpoint..."
      
      post '/api/v1/conversation', {
        message: "Goodbye",
        context: {
          session_id: "voice_test_123",
          voice_interaction: true
        }
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }
      
      puts "Status: #{last_response.status}"
      puts "Response body: #{last_response.body}"
      
    rescue => e
      puts "Error: #{e.class} - #{e.message}"
      puts "Backtrace: #{e.backtrace.first(10).join("\n")}"
    end
  end
end

# Run the test
VCR.turned_off do
  test_app = TestApp.new
  test_app.test_conversation
end