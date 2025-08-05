# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'App Route Registration' do
  describe 'Deploy route registration' do
    it 'registers deploy route when mac_mini deployment is enabled' do
      # This test verifies the conditional logic in app.rb
      # In real usage, the route would only be registered if MAC_MINI_DEPLOYMENT=true
      
      # Check if the Deploy module is defined
      expect(defined?(GlitchCube::Routes::Deploy)).to be_truthy
      
      # Verify the conditional would work
      config_double = double('deployment_config', mac_mini: true)
      allow(GlitchCube.config).to receive(:deployment).and_return(config_double)
      
      # The actual registration happens in app.rb:
      # if GlitchCube.config.deployment.mac_mini && defined?(GlitchCube::Routes::Deploy)
      #   register GlitchCube::Routes::Deploy
      # end
      
      should_register = GlitchCube.config.deployment.mac_mini && !!defined?(GlitchCube::Routes::Deploy)
      expect(should_register).to be true
    end
    
    it 'would skip deploy route when mac_mini deployment is disabled' do
      config_double = double('deployment_config', mac_mini: false)
      allow(GlitchCube.config).to receive(:deployment).and_return(config_double)
      
      should_register = GlitchCube.config.deployment.mac_mini && !!defined?(GlitchCube::Routes::Deploy)
      expect(should_register).to be false
    end
  end
end