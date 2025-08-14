# frozen_string_literal: true

RSpec::Matchers.define :include_any_of do |*expected|
  match do |actual|
    expected.any? { |word| actual.to_s.downcase.include?(word.downcase) }
  end

  failure_message do |actual|
    "expected '#{actual}' to include any of: #{expected.join(', ')}"
  end
end

RSpec::Matchers.define :be_a_valid_conversation_response do |expected_persona: 'buddy', expected_error: nil|
  match do |actual|
    return false unless actual.is_a?(Hash)

    # Check for required keys
    required_keys = %i[response conversation_id session_id persona model
                       cost tokens continue_conversation tts_handled
                       voice_interaction error]
    missing_keys = required_keys - actual.keys
    return false unless missing_keys.empty?

    # Validate response content
    return false unless actual[:response].is_a?(String) && !actual[:response].empty?
    return false unless actual[:persona] == expected_persona

    # Validate error expectation
    if expected_error
      return false unless actual[:error] == expected_error
    else
      return false unless actual[:error].nil?
    end

    # Validate conversation IDs
    return false unless actual[:conversation_id].is_a?(String) && !actual[:conversation_id].empty?
    return false unless actual[:session_id].is_a?(String) && !actual[:session_id].empty?

    # Validate cost and token tracking
    return false unless actual[:cost].is_a?(Numeric) && actual[:cost] >= 0
    return false unless actual[:tokens].is_a?(Hash)
    return false unless actual[:tokens].key?(:prompt_tokens) && actual[:tokens].key?(:completion_tokens)

    # Validate boolean flags
    return false unless [true, false].include?(actual[:continue_conversation])
    return false unless [true, false].include?(actual[:tts_handled])
    return false unless [true, false].include?(actual[:voice_interaction])

    true
  end

  failure_message do |actual|
    if actual.is_a?(Hash)
      required_keys = %i[response conversation_id session_id persona model
                         cost tokens continue_conversation tts_handled
                         voice_interaction error]
      missing_keys = required_keys - actual.keys
      if missing_keys.any?
        "expected response to have all required keys, missing: #{missing_keys}"
      else
        "expected valid conversation response but validation failed for #{actual.inspect}"
      end
    else
      "expected a Hash, got #{actual.class}"
    end
  end
end
