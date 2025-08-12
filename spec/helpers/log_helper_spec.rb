# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LogHelper do
  describe 'delegation to SimpleLogger' do
    it 'delegates error to SimpleLogger' do
      expect(Services::SimpleLogger).to receive(:error).with('test error', tagged: [:log_helper])
      LogHelper.error('test error')
    end

    it 'delegates warning to SimpleLogger' do
      expect(Services::SimpleLogger).to receive(:warn).with('test warning', tagged: [:log_helper])
      LogHelper.warning('test warning')
    end

    it 'delegates success to SimpleLogger with emoji' do
      expect(Services::SimpleLogger).to receive(:info).with('✅ test success', tagged: %i[log_helper success])
      LogHelper.success('test success')
    end

    it 'delegates debug to SimpleLogger' do
      expect(Services::SimpleLogger).to receive(:debug).with('test debug', tagged: [:log_helper])
      LogHelper.debug('test debug')
    end

    it 'supports info method with metadata' do
      expect(Services::SimpleLogger).to receive(:info).with('test info', tagged: [:log_helper], foo: 'bar')
      LogHelper.info('test info', foo: 'bar')
    end
  end
end
