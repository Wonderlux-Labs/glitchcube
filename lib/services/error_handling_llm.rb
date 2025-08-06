# frozen_string_literal: true

module Services
  class ErrorHandlingLLM
    def criticality_threshold
      GlitchCube.config.self_healing_min_confidence
    end

    def error_recurrence_threshold
      GlitchCube.config.self_healing_error_threshold
    end
    ERROR_TRACKING_TTL = 3600 # 1 hour

    def initialize
      @redis = begin
        Redis.new(url: GlitchCube.config.redis_url)
      rescue Redis::CannotConnectError => e
        @logger&.log_api_call(
          service: 'ErrorHandlingLLM',
          endpoint: 'initialize',
          error: "Redis unavailable: #{e.message}"
        )
        nil
      end
      @logger = Services::LoggerService
      @rate_limit_cache = {}
    end

    def handle_error(error, context = {})
      return handle_disabled unless self_healing_enabled?

      # Check if we've already proposed a fix for this error
      error_key = generate_error_key(error, context)
      if @redis&.exists?("glitchcube:fixed_errors:#{error_key}")
        return {
          action: 'already_analyzed',
          message: 'Fix already proposed for this error'
        }
      end

      occurrence_count = track_error_occurrence(error, context)

      if occurrence_count < error_recurrence_threshold
        return {
          action: 'tracked',
          occurrence_count: occurrence_count,
          message: "Error tracked (occurrence #{occurrence_count})"
        }
      end

      context[:occurrence_count] = occurrence_count
      analysis = assess_criticality(error, context)

      if analysis[:critical] && analysis[:confidence] > criticality_threshold
        result = attempt_self_healing(error, context, analysis)
        log_healing_attempt(error, context, analysis, result)
        result
      else
        {
          action: 'monitored',
          critical: analysis[:critical],
          confidence: analysis[:confidence],
          reason: analysis[:reason],
          message: 'Error assessed as non-critical or low confidence'
        }
      end
    rescue StandardError => e
      @logger.log_api_call(
        service: 'ErrorHandlingLLM',
        endpoint: 'handle_error',
        error: e.message,
        original_error: error.message
      )
      { action: 'handler_failed', error: e.message }
    end

    def assess_criticality(error, context)
      # Check rate limit (10 calls per minute)
      if rate_limit_exceeded?
        return {
          critical: false,
          confidence: 0,
          reason: 'Rate limit exceeded - waiting before next analysis'
        }
      end

      prompt = build_criticality_prompt(error, context)

      response = OpenRouterService.complete(
        prompt,
        model: 'anthropic/claude-3.5-haiku-20241022',
        response_format: { type: 'json_object' }
      )

      parse_criticality_response(response)
    rescue StandardError => e
      {
        critical: false,
        confidence: 0,
        reason: "Failed to assess: #{e.message}"
      }
    end

    def attempt_self_healing(error, context, analysis)
      return low_confidence_response if analysis[:confidence] < criticality_threshold

      fix_result = analyze_and_fix_code(error, context.merge(analysis))

      if fix_result[:success]
        # Check mode: DRY_RUN or YOLO
        if GlitchCube.config.self_healing_yolo?
          # YOLO mode - actually apply the fix!
          deploy_result = apply_and_deploy_fix(fix_result)
          {
            action: 'self_healed',
            success: deploy_result[:deployed],
            mode: 'YOLO',
            fix_applied: fix_result[:description],
            commit_sha: deploy_result[:commit_sha],
            confidence: analysis[:confidence]
          }
        else
          # DRY_RUN mode - save proposed fix for review
          save_proposed_fix(error, context, analysis, fix_result)
          {
            action: 'fix_proposed',
            success: true,
            mode: 'DRY_RUN',
            fix_proposed: fix_result[:description],
            confidence: analysis[:confidence],
            message: 'Fix analyzed and saved for review (DRY_RUN mode)'
          }
        end
      else
        {
          action: 'fix_failed',
          success: false,
          reason: fix_result[:error] || 'Could not generate fix',
          confidence: analysis[:confidence]
        }
      end
    end

    def analyze_and_fix_code(error, context)
      agent_result = spawn_fix_agent(error, context)

      if agent_result[:success]
        {
          success: true,
          description: agent_result[:fix][:description],
          changes: agent_result[:fix][:changes],
          files_modified: agent_result[:fix][:changes].map { |c| c[:file] }.uniq,
          commit_message: generate_commit_message(error, agent_result[:fix])
        }
      else
        { success: false, error: agent_result[:error] }
      end
    end

    def apply_and_deploy_fix(fix)
      current_sha = `git rev-parse HEAD`.strip
      store_rollback_sha(current_sha)

      # Create a feature branch for the fix
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      branch_name = "auto-fix/#{timestamp}_#{fix[:description].downcase.gsub(/\s+/, '_')[0..30]}"

      # Create and checkout new branch
      return git_failure('Failed to create branch') unless system("git checkout -b #{branch_name}")

      fix[:files_modified].each do |file|
        return git_failure("Failed to add #{file}") unless system("git add #{file}")
      end

      commit_message = fix[:commit_message] || '[AUTO-FIX] Automated error resolution'
      return git_failure('Failed to commit') unless system("git commit -m '#{commit_message}'")

      if system("git push origin #{branch_name}")
        new_sha = `git rev-parse HEAD`.strip

        # Try to create a PR (if gh CLI is available)
        pr_body = <<~BODY
          ## 🤖 Automated Fix

          **Error**: #{fix[:error_class] || 'Unknown'}
          **Confidence**: #{fix[:confidence] || 'N/A'}
          **Description**: #{fix[:description]}

          Files modified: #{fix[:files_modified].join(', ')}

          ---
          *Generated by Glitch Cube Self-Healing System*
        BODY

        pr_url = nil
        if system('which gh > /dev/null 2>&1')
          pr_output = `gh pr create --title "[AUTO-FIX] #{fix[:description]}" --body "#{pr_body}" --base main 2>&1`
          pr_url = pr_output.match(%r{https://github\.com/.*/pull/\d+})&.to_s
        end

        # Switch back to main
        system('git checkout main')

        {
          deployed: true,
          commit_sha: new_sha,
          previous_sha: current_sha,
          branch: branch_name,
          pr_url: pr_url,
          message: "Fix pushed to branch #{branch_name}. Review at 4am with your favorite substances! 🎉"
        }
      else
        system('git checkout main')
        system("git branch -D #{branch_name}")
        git_failure('Failed to push branch')
      end
    end

    def rollback_last_fix
      return { success: false, error: 'Redis not available for rollback' } unless @redis

      sha = @redis.get('glitchcube:rollback_sha')

      return { success: false, error: 'No recent fix to rollback' } unless sha

      if system("git revert --no-edit #{sha}") && system('git push origin main')
        @redis.del('glitchcube:rollback_sha')
        { success: true, reverted_to: sha }
      else
        { success: false, error: 'Rollback failed' }
      end
    end

    private

    def self_healing_enabled?
      GlitchCube.config.self_healing_enabled?
    end

    def handle_disabled
      @logger.log_api_call(
        service: 'ErrorHandlingLLM',
        endpoint: 'handle_error',
        self_healing: false
      )
      { action: 'logged_only', message: 'Self-healing disabled' }
    end

    def track_error_occurrence(error, context)
      error_key = generate_error_key(error, context)

      # Fallback to memory tracking if Redis unavailable
      unless @redis
        @rate_limit_cache[error_key] ||= 0
        @rate_limit_cache[error_key] += 1
        return @rate_limit_cache[error_key]
      end

      count = @redis.incr("glitchcube:error_count:#{error_key}")
      @redis.expire("glitchcube:error_count:#{error_key}", ERROR_TRACKING_TTL)
      count
    rescue Redis::BaseError => e
      @logger.log_api_call(
        service: 'ErrorHandlingLLM',
        endpoint: 'track_error',
        error: "Redis error: #{e.message}"
      )
      # Fallback to in-memory tracking
      @rate_limit_cache[error_key] ||= 0
      @rate_limit_cache[error_key] += 1
    end

    def generate_error_key(error, context)
      key_parts = [
        error.class.name,
        context[:service],
        context[:method],
        error.message.split("\n").first
      ].compact

      Digest::MD5.hexdigest(key_parts.join(':'))
    end

    def build_criticality_prompt(error, context)
      <<~PROMPT
        Analyze this error in a production art installation and determine if it's critical.

        Error: #{error.class.name}: #{error.message}
        Service: #{context[:service]}
        Method: #{context[:method]}
        File: #{context[:file]}
        Occurrences: #{context[:occurrence_count]} times in the last hour

        Context: This is an autonomous art installation that must operate reliably for days.

        Respond with JSON:
        {
          "critical": true/false,
          "confidence": 0.0-1.0,
          "reason": "explanation",
          "suggested_fix": "what to do",
          "affects_core_functionality": true/false,
          "can_self_heal": true/false
        }

        Consider critical if:
        - Affects conversation ability
        - Breaks hardware control
        - Causes data loss
        - Prevents core features

        Consider non-critical if:
        - Temporary network issues
        - Rate limits that will reset
        - Non-essential features
        - Cosmetic issues
      PROMPT
    end

    def parse_criticality_response(response)
      data = begin
        JSON.parse(response)
      rescue StandardError
        {}
      end

      {
        critical: data['critical'] || false,
        confidence: data['confidence'] || 0,
        reason: data['reason'] || 'Unknown',
        suggested_fix: data['suggested_fix'],
        affects_core: data['affects_core_functionality'],
        can_self_heal: data['can_self_heal']
      }
    end

    def spawn_fix_agent(error, context)
      prompt = <<~PROMPT
        You are an expert Ruby developer fixing a production error.

        Error: #{error.class.name}: #{error.message}
        #{error.backtrace&.first(5)&.join("\n")}

        Context:
        - Service: #{context[:service]}
        - File: #{context[:file]}
        - Line: #{context[:line]}
        - Suggested fix: #{context[:suggested_fix]}

        Analyze the code and provide a MINIMAL, SAFE fix that:
        1. Handles the error gracefully
        2. Adds defensive programming
        3. Doesn't break existing functionality
        4. Is simple and reliable

        Read the file, understand the context, and provide the fix.

        Respond with JSON:
        {
          "success": true/false,
          "fix": {
            "description": "what was fixed",
            "changes": [
              {
                "file": "path/to/file.rb",
                "diff": "the actual code change",
                "line": line_number
              }
            ]
          }
        }
      PROMPT

      # Use debug-detective agent if available, otherwise use simpler analysis
      result = if defined?(Task)
                 Task.new.call(
                   description: 'Fix production error',
                   prompt: prompt,
                   subagent_type: 'debug-detective'
                 )
               else
                 # Fallback to direct LLM call if Task agent not available
                 response = OpenRouterService.complete(
                   prompt,
                   model: 'anthropic/claude-3.5-sonnet-20241022',
                   response_format: { type: 'json_object' }
                 )
                 response
               end

      parse_agent_response(result)
    rescue StandardError => e
      { success: false, error: e.message }
    end

    def parse_agent_response(response)
      return { success: false, error: 'No response' } unless response

      # Extract JSON from agent response
      json_match = response.match(/\{.*\}/m)
      return { success: false, error: 'No JSON in response' } unless json_match

      data = JSON.parse(json_match[0])
      {
        success: data['success'],
        fix: data['fix'],
        error: data['error']
      }
    rescue StandardError => e
      { success: false, error: "Parse error: #{e.message}" }
    end

    def generate_commit_message(error, fix)
      "[AUTO-FIX] #{fix[:description]}\n\n" \
        "Error: #{error.class.name}: #{error.message.split("\n").first}\n" \
        "Confidence: #{fix[:confidence] || 'high'}\n" \
        "Files: #{fix[:changes].map { |c| c[:file] }.join(', ')}"
    end

    def store_rollback_sha(sha)
      return unless @redis

      @redis.set('glitchcube:rollback_sha', sha)
      @redis.expire('glitchcube:rollback_sha', 86_400) # 24 hours
    rescue Redis::BaseError => e
      @logger.log_api_call(
        service: 'ErrorHandlingLLM',
        endpoint: 'store_rollback',
        error: "Redis error: #{e.message}"
      )
    end

    def git_failure(message)
      { deployed: false, error: message }
    end

    def low_confidence_response
      {
        success: false,
        reason: 'Confidence too low for automated fix',
        action: 'manual_review_required'
      }
    end

    def rate_limit_exceeded?
      key = 'glitchcube:llm_rate_limit'

      # Use Redis if available, otherwise in-memory
      if @redis
        begin
          count = @redis.incr(key)
          @redis.expire(key, 60) if count == 1
          count > 10 # Max 10 calls per minute
        rescue Redis::BaseError
          # Fallback to in-memory rate limiting
          check_memory_rate_limit
        end
      else
        check_memory_rate_limit
      end
    end

    def check_memory_rate_limit
      now = Time.now.to_i
      minute_key = now / 60

      # Clean old entries
      @rate_limit_cache.delete_if { |k, _| k.to_s.start_with?('rate_') && k != "rate_#{minute_key}" }

      # Check current minute
      @rate_limit_cache["rate_#{minute_key}"] ||= 0
      @rate_limit_cache["rate_#{minute_key}"] += 1
      @rate_limit_cache["rate_#{minute_key}"] > 10
    end

    def save_proposed_fix(error, context, analysis, fix_result)
      # Mark this error as "fixed" in Redis so we don't keep analyzing it
      error_key = generate_error_key(error, context)
      # 7 days
      @redis&.set("glitchcube:fixed_errors:#{error_key}", 'proposed', ex: 86_400 * 7)

      # Save to database if available
      if defined?(ProposedFix)
        ProposedFix.create!(
          error_class: error.class.name,
          error_message: error.message,
          error_backtrace: error.backtrace&.first(10)&.join("\n"),
          occurrence_count: context[:occurrence_count],
          service_name: context[:service],
          method_name: context[:method],
          file_path: context[:file],
          line_number: context[:line],
          environment: GlitchCube.config.rack_env,
          confidence: analysis[:confidence],
          critical: analysis[:critical],
          analysis_reason: analysis[:reason],
          suggested_fix: analysis[:suggested_fix],
          fix_details: fix_result,
          context_data: context,
          status: 'pending'
        )
      else
        # Fallback to file logging if database not available
        log_proposed_fix_to_file(error, context, analysis, fix_result)
      end
    rescue StandardError => e
      @logger.log_api_call(
        service: 'ErrorHandlingLLM',
        endpoint: 'save_proposed_fix',
        error: e.message
      )
    end

    def log_proposed_fix_to_file(error, context, analysis, fix_result)
      require 'json'

      fix_log = {
        timestamp: Time.now.iso8601,
        error: {
          class: error.class.name,
          message: error.message,
          occurrences: context[:occurrence_count]
        },
        context: context,
        analysis: analysis,
        proposed_fix: fix_result,
        confidence: analysis[:confidence]
      }

      log_dir = 'log/proposed_fixes'
      FileUtils.mkdir_p(log_dir)

      filename = "#{log_dir}/#{Time.now.strftime('%Y%m%d')}_proposed_fixes.jsonl"
      File.open(filename, 'a') do |f|
        f.puts JSON.generate(fix_log)
      end
    end

    def log_healing_attempt(error, _context, analysis, result)
      @logger.log_api_call(
        service: 'ErrorHandlingLLM',
        endpoint: 'self_healing',
        error_class: error.class.name,
        error_message: error.message,
        critical: analysis[:critical],
        confidence: analysis[:confidence],
        success: result[:success],
        action: result[:action]
      )
    end
  end
end
