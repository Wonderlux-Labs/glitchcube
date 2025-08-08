# frozen_string_literal: true

# VCR Auto-Recording System
# Automatically creates cassettes for tests that don't have them
module VCRAutoRecording
  class << self
    attr_accessor :auto_recorded_tests, :current_test_context

    def reset!
      @auto_recorded_tests = []
      @current_test_context = nil
    end

    def set_test_context(example)
      @current_test_context = example
    end

    def generate_cassette_name(example, request)
      # Create a cassette name based on the test hierarchy
      full_description = example.full_description.gsub(/[^\w\s-]/, '').strip
      path_parts = full_description.split(/\s+/).map(&:strip).reject(&:empty?)
      
      # Create directory structure from test hierarchy
      cassette_path = path_parts.join('/')
      
      # Add request info to make it unique
      host = URI.parse(request.uri.to_s).host.gsub('.', '_')
      method = request.method.upcase
      
      "#{cassette_path}/auto_#{host}_#{method}_#{SecureRandom.hex(4)}"
    end

    def auto_record_request(request, example)
      return unless example && request

      cassette_name = generate_cassette_name(example, request)
      
      puts "🎬 AUTO-RECORDING: #{cassette_name}"
      
      # Use VCR to record this single request
      VCR.use_cassette(cassette_name, record: :new_episodes, match_requests_on: [:method, :uri, :body]) do
        # Re-execute the request to record it
        # This is tricky - we need to let the original request continue
        # The hook system will handle this automatically
      end
      
      # Track that we auto-recorded this test
      @auto_recorded_tests ||= []
      @auto_recorded_tests << {
        example: example,
        cassette: cassette_name,
        request: "#{request.method.upcase} #{request.uri}",
        location: example.location
      }
      
      # Tag the test metadata
      example.metadata[:vcr_auto_recorded] = true
      example.metadata[:vcr_auto_cassette] = cassette_name
      
      # Log the auto-recording
      log_auto_recording(example, cassette_name, request)
      
      cassette_name
    end

    def log_auto_recording(example, cassette_name, request)
      log_file = File.join('logs', 'vcr_auto_recorded.log')
      FileUtils.mkdir_p(File.dirname(log_file))
      
      File.open(log_file, 'a') do |f|
        f.puts "🎬 AUTO-RECORDED CASSETTE:"
        f.puts "   Test: #{example.full_description}"
        f.puts "   Location: #{example.location}"
        f.puts "   Cassette: #{cassette_name}"
        f.puts "   Request: #{request.method.upcase} #{request.uri}"
        f.puts "   Time: #{Time.now.iso8601}"
        f.puts "   Next: Commit the cassette and re-run the test"
        f.puts "-" * 80
      end
    end

    def generate_report
      return if @auto_recorded_tests.nil? || @auto_recorded_tests.empty?

      report = []
      report << "\n" + "="*80
      report << "🎬 VCR AUTO-RECORDING SUMMARY: #{@auto_recorded_tests.size} cassette(s) created"
      report << "="*80

      @auto_recorded_tests.each do |recording|
        report << "\n✅ #{recording[:cassette]}.yml"
        report << "   Test: #{recording[:example].full_description}"
        report << "   Location: #{recording[:location]}"
        report << "   Request: #{recording[:request]}"
        report << ""
      end

      report << "\n🔧 Next Steps:"
      report << "1. Commit the new cassettes in spec/vcr_cassettes/"
      report << "2. Re-run the tests - they should now pass"
      report << "3. Review the recorded interactions for accuracy"
      report << "\n" + "="*80

      # Write to file
      log_file = File.join('logs', 'vcr_auto_recorded.log')
      File.open(log_file, 'w') do |f|
        f.puts report.join("\n")
      end
      
      # Also output to console
      puts report.join("\n")
    end
  end
end

# Initialize
VCRAutoRecording.reset!