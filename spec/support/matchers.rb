# frozen_string_literal: true

RSpec::Matchers.define :include_any_of do |*expected|
  match do |actual|
    expected.any? { |word| actual.to_s.downcase.include?(word.downcase) }
  end

  failure_message do |actual|
    "expected '#{actual}' to include any of: #{expected.join(', ')}"
  end
end
