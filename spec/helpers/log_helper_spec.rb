# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Helpers::LogHelper do
  describe 'delegation to SimpleLogger' do
    it 'delegates error to SimpleLogger' do
      expect(Services::Logging::SimpleLogger).to receive(:error).with('test error', tagged: [:log_helper])
      Helpers::LogHelper.error('test error')
    end

    it 'delegates warning to SimpleLogger' do
      expect(Services::Logging::SimpleLogger).to receive(:warn).with('test warning', tagged: [:log_helper])
      Helpers::LogHelper.warning('test warning')
    end

    it 'delegates success to SimpleLogger with emoji' do
      expect(Services::Logging::SimpleLogger).to receive(:info).with('✅ test success', tagged: %i[log_helper success])
      Helpers::LogHelper.success('test success')
    end

    it 'delegates debug to SimpleLogger' do
      expect(Services::Logging::SimpleLogger).to receive(:debug).with('test debug', tagged: [:log_helper])
      Helpers::LogHelper.debug('test debug')
    end

    it 'supports info method with metadata' do
      expect(Services::Logging::SimpleLogger).to receive(:info).with('test info', tagged: [:log_helper], foo: 'bar')
      Helpers::LogHelper.info('test info', foo: 'bar')
    end
  end
end
