# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/helpers/deployment_helper'

RSpec.describe GlitchCube::Helpers::DeploymentHelper do
  describe '.mac_mini_deployment?' do
    it 'returns true when MAC_MINI_DEPLOYMENT is true' do
      allow(GlitchCube.config.deployment).to receive(:mac_mini).and_return(true)
      expect(described_class.mac_mini_deployment?).to be true
    end

    it 'returns false when MAC_MINI_DEPLOYMENT is false' do
      allow(GlitchCube.config.deployment).to receive(:mac_mini).and_return(false)
      expect(described_class.mac_mini_deployment?).to be false
    end
  end

  describe '.docker_deployment?' do
    it 'returns true when not in mac mini mode' do
      allow(GlitchCube.config.deployment).to receive(:mac_mini).and_return(false)
      expect(described_class.docker_deployment?).to be true
    end

    it 'returns false when in mac mini mode' do
      allow(GlitchCube.config.deployment).to receive(:mac_mini).and_return(true)
      expect(described_class.docker_deployment?).to be false
    end
  end

  describe '.deployment_type' do
    it 'returns mac-mini when in mac mini mode' do
      allow(described_class).to receive(:mac_mini_deployment?).and_return(true)
      expect(described_class.deployment_type).to eq('mac-mini')
    end

    it 'returns docker when in docker mode' do
      allow(described_class).to receive(:mac_mini_deployment?).and_return(false)
      expect(described_class.deployment_type).to eq('docker')
    end
  end

  describe '.deployment_script_path' do
    it 'returns VM script path for mac mini deployment' do
      allow(described_class).to receive(:mac_mini_deployment?).and_return(true)
      expect(described_class.deployment_script_path).to eq('scripts/deploy/vm-update-ha-config.sh')
    end

    it 'returns docker script path for docker deployment' do
      allow(described_class).to receive(:mac_mini_deployment?).and_return(false)
      expect(described_class.deployment_script_path).to eq('scripts/deploy/pull-from-github.sh')
    end
  end
end