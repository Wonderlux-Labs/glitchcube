#!/usr/bin/env ruby
# frozen_string_literal: true

# Debug script to understand ToolExecutor behavior

require 'bundler/setup'
require_relative 'spec/spec_helper'
require_relative 'lib/services/tool_executor'

# Create a test tool class like in the spec
test_tool_class = Class.new do
  def self.name
    'TestTool'
  end

  def self.test_method(required_param:, optional_param: nil)
    { required: required_param, optional: optional_param }
  end

  def self.available_tools
    ['test_method']
  end
end

# Mock the find_tool_class_for method like in the spec
allow(Services::ToolExecutor).to receive(:find_tool_class_for).and_return(test_tool_class)

# Test the execution
tool_call = {
  name: 'test_method',
  arguments: {
    required_param: 'value1',
    optional_param: 'value2',
    extra_param: 'should be filtered out'
  }
}

puts "Tool call: #{tool_call.inspect}"
result = Services::ToolExecutor.execute([tool_call])
puts "Result: #{result.inspect}"
puts "First result: #{result.first.inspect}"
puts "Result class: #{result.first.class}"
puts "Result keys: #{result.first.keys}" if result.first.respond_to?(:keys)
