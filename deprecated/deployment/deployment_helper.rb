# frozen_string_literal: true

module GlitchCube
  module Helpers
    module DeploymentHelper
      def self.mac_mini_deployment?
        GlitchCube.config.deployment.mac_mini
      end

      def self.docker_deployment?
        !mac_mini_deployment?
      end

      def self.deployment_type
        mac_mini_deployment? ? 'mac-mini' : 'docker'
      end

      # Helper for conditional logic in scripts
      def self.deployment_script_path
        if mac_mini_deployment?
          'scripts/deploy/vm-update-ha-config.sh'
        else
          'scripts/deploy/pull-from-github.sh'
        end
      end

      # Helper for GitHub Actions workflow selection
      def self.github_workflow
        if mac_mini_deployment?
          '.github/workflows/deploy-mac-mini.yml'
        else
          '.github/workflows/deploy.yml'
        end
      end
    end
  end
end