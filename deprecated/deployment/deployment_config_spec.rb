# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Deployment Configuration' do
  describe 'GlitchCube.config.deployment' do
    context 'with MAC_MINI_DEPLOYMENT set to true' do
      before do
        ENV['MAC_MINI_DEPLOYMENT'] = 'true'
        # Reload config to pick up ENV change
        GlitchCube::Config.instance_variable_set(:@instance, nil)
      end

      after do
        ENV['MAC_MINI_DEPLOYMENT'] = nil
        GlitchCube::Config.instance_variable_set(:@instance, nil)
      end

      it 'sets mac_mini to true' do
        expect(GlitchCube.config.deployment.mac_mini).to be true
      end
    end

    context 'with MAC_MINI_DEPLOYMENT set to false' do
      before do
        ENV['MAC_MINI_DEPLOYMENT'] = 'false'
        GlitchCube::Config.instance_variable_set(:@instance, nil)
      end

      after do
        ENV['MAC_MINI_DEPLOYMENT'] = nil
        GlitchCube::Config.instance_variable_set(:@instance, nil)
      end

      it 'sets mac_mini to false' do
        expect(GlitchCube.config.deployment.mac_mini).to be false
      end
    end

    context 'with MAC_MINI_DEPLOYMENT not set' do
      before do
        ENV.delete('MAC_MINI_DEPLOYMENT')
        GlitchCube::Config.instance_variable_set(:@instance, nil)
      end

      it 'defaults to true' do
        expect(GlitchCube.config.deployment.mac_mini).to be true
      end
    end
  end
end
