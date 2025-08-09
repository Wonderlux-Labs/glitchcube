# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/cube/settings'

RSpec.describe Cube::Settings do
  describe 'Feature Toggles' do
    describe '.simulate_cube_movement?' do
      it 'returns true when ENV is set to true', :vcr do
        ENV['SIMULATE_CUBE_MOVEMENT'] = 'true'
        expect(described_class.simulate_cube_movement?).to be true
      end

      it 'returns false when ENV is not true', :vcr do
        ENV['SIMULATE_CUBE_MOVEMENT'] = 'false'
        expect(described_class.simulate_cube_movement?).to be false
      end
    end

    # Mock Home Assistant functionality removed - using real HA instance

    describe '.disable_circuit_breakers?' do
      after do
        described_class.clear_overrides!
      end

      xit 'returns true in test environment by default', :vcr, :pending do
        expect(described_class.disable_circuit_breakers?).to be true
      end

      xit 'can be overridden to false', :vcr do
        described_class.override!(:disable_circuit_breakers, false)
        expect(described_class.disable_circuit_breakers?).to be false
      end

      xit 'can be overridden to true', :vcr do
        described_class.override!(:disable_circuit_breakers, true)
        expect(described_class.disable_circuit_breakers?).to be true
      end
    end

    describe '.mac_mini_deployment?' do
      it 'returns true when ENV is set to true', :vcr do
        ENV['MAC_MINI_DEPLOYMENT'] = 'true'
        expect(described_class.mac_mini_deployment?).to be true
      end

      it 'returns false when ENV is not true', :vcr do
        ENV['MAC_MINI_DEPLOYMENT'] = 'false'
        expect(described_class.mac_mini_deployment?).to be false
      end
    end
  end

  describe 'Environment' do
    describe '.rack_env' do
      it 'returns the RACK_ENV value', :vcr do
        ENV['RACK_ENV'] = 'production'
        expect(described_class.rack_env).to eq('production')
      end

      it 'defaults to development when not set', :vcr do
        ENV['RACK_ENV'] = nil
        expect(described_class.rack_env).to eq('development')
      end
    end

    describe '.development?' do
      it 'returns true when RACK_ENV is development', :vcr do
        ENV['RACK_ENV'] = 'development'
        expect(described_class.development?).to be true
      end

      it 'returns false for other environments', :vcr do
        ENV['RACK_ENV'] = 'production'
        expect(described_class.development?).to be false
      end
    end

    describe '.test?' do
      it 'returns true when RACK_ENV is test', :vcr do
        ENV['RACK_ENV'] = 'test'
        expect(described_class.test?).to be true
      end
    end

    describe '.production?' do
      it 'returns true when RACK_ENV is production', :vcr do
        ENV['RACK_ENV'] = 'production'
        expect(described_class.production?).to be true
      end

      it 'returns false for other environments', :vcr do
        ENV['RACK_ENV'] = 'test'
        expect(described_class.production?).to be false
      end
    end
  end

  describe 'Application Settings' do
    describe '.app_root' do
      it 'returns APP_ROOT when set', :vcr do
        ENV['APP_ROOT'] = '/custom/path'
        expect(described_class.app_root).to eq('/custom/path')
      end

      it 'defaults to current directory when not set', :vcr do
        ENV['APP_ROOT'] = nil
        expect(described_class.app_root).to eq(Dir.pwd)
      end
    end

    describe '.session_secret' do
      it 'returns the SESSION_SECRET value', :vcr do
        ENV['SESSION_SECRET'] = 'super-secret-key'
        expect(described_class.session_secret).to eq('super-secret-key')
      end
    end
  end

  describe 'API Keys and Tokens' do
    describe '.openrouter_api_key' do
      it 'returns the OPENROUTER_API_KEY value', :vcr do
        ENV['OPENROUTER_API_KEY'] = 'test-api-key'
        expect(described_class.openrouter_api_key).to eq('test-api-key')
      end
    end

    describe '.home_assistant_token' do
      it 'returns HOME_ASSISTANT_TOKEN when set', :vcr do
        ENV['HOME_ASSISTANT_TOKEN'] = 'ha-token'
        ENV['HA_TOKEN'] = nil
        expect(described_class.home_assistant_token).to eq('ha-token')
      end

      it 'falls back to HA_TOKEN when HOME_ASSISTANT_TOKEN is not set', :vcr do
        ENV['HOME_ASSISTANT_TOKEN'] = nil
        ENV['HA_TOKEN'] = 'fallback-token'
        expect(described_class.home_assistant_token).to eq('fallback-token')
      end
    end

    describe '.github_webhook_secret' do
      it 'returns the GITHUB_WEBHOOK_SECRET value', :vcr do
        ENV['GITHUB_WEBHOOK_SECRET'] = 'webhook-secret'
        expect(described_class.github_webhook_secret).to eq('webhook-secret')
      end
    end
  end

  describe 'URLs and Endpoints' do
    describe '.home_assistant_url' do
      it 'returns HOME_ASSISTANT_URL when set', :vcr do
        ENV['HOME_ASSISTANT_URL'] = 'http://ha.local'
        ENV['HA_URL'] = nil
        expect(described_class.home_assistant_url).to eq('http://ha.local')
      end

      it 'falls back to HA_URL when HOME_ASSISTANT_URL is not set', :vcr do
        ENV['HOME_ASSISTANT_URL'] = nil
        ENV['HA_URL'] = 'http://fallback.local'
        expect(described_class.home_assistant_url).to eq('http://fallback.local')
      end
    end
  end

  describe 'Database Configuration' do
    describe '.database_type' do
      it 'returns :sqlite for sqlite URLs', :vcr do
        ENV['DATABASE_URL'] = 'sqlite://data/glitchcube.db'
        expect(described_class.database_type).to eq(:sqlite)
      end

      it 'returns :mariadb for mysql URLs', :vcr do
        ENV['DATABASE_URL'] = 'mysql2://user:pass@localhost/db'
        expect(described_class.database_type).to eq(:mariadb)
      end

      it 'returns :mariadb for mariadb URLs', :vcr do
        ENV['DATABASE_URL'] = 'mariadb://user:pass@localhost/db'
        expect(described_class.database_type).to eq(:mariadb)
      end

      it 'returns :postgres for postgres URLs', :vcr do
        ENV['DATABASE_URL'] = 'postgresql://user:pass@localhost/db'
        expect(described_class.database_type).to eq(:postgres)
      end

      it 'defaults to :sqlite for unknown types', :vcr do
        ENV['DATABASE_URL'] = 'unknown://something'
        expect(described_class.database_type).to eq(:sqlite)
      end
    end

    describe '.using_mariadb?' do
      it 'returns true when DATABASE_URL is mysql', :vcr do
        ENV['DATABASE_URL'] = 'mysql2://user:pass@localhost/db'
        expect(described_class.using_mariadb?).to be true
      end

      it 'returns false when DATABASE_URL is sqlite', :vcr do
        ENV['DATABASE_URL'] = 'sqlite://data/glitchcube.db'
        expect(described_class.using_mariadb?).to be false
      end
    end

    describe '.using_sqlite?' do
      it 'returns true when DATABASE_URL is sqlite', :vcr do
        ENV['DATABASE_URL'] = 'sqlite://data/glitchcube.db'
        expect(described_class.using_sqlite?).to be true
      end

      it 'returns false when DATABASE_URL is not sqlite', :vcr do
        ENV['DATABASE_URL'] = 'mysql2://user:pass@localhost/db'
        expect(described_class.using_sqlite?).to be false
      end
    end

    describe 'MariaDB settings' do
      context 'when using MariaDB' do
        before do
          ENV['DATABASE_URL'] = 'mysql2://user:pass@localhost/db'
          ENV['MARIADB_HOST'] = 'db.example.com'
          ENV['MARIADB_PORT'] = '3307'
        end

        it 'returns mariadb_host when using MariaDB', :vcr do
          expect(described_class.mariadb_host).to eq('db.example.com')
        end

        it 'returns mariadb_port when using MariaDB', :vcr do
          expect(described_class.mariadb_port).to eq(3307)
        end

        it 'constructs mariadb_url correctly', :vcr do
          ENV['MARIADB_USERNAME'] = 'testuser'
          ENV['MARIADB_PASSWORD'] = 'testpass'
          ENV['MARIADB_DATABASE'] = 'testdb'
          expect(described_class.mariadb_url).to eq('mysql2://testuser:testpass@db.example.com:3307/testdb')
        end
      end

      context 'when not using MariaDB' do
        before do
          ENV['DATABASE_URL'] = 'sqlite://data/glitchcube.db'
        end

        it 'returns nil for mariadb_host', :vcr do
          expect(described_class.mariadb_host).to be_nil
        end

        it 'returns nil for mariadb_port', :vcr do
          expect(described_class.mariadb_port).to be_nil
        end

        it 'returns nil for mariadb_url', :vcr do
          expect(described_class.mariadb_url).to be_nil
        end
      end
    end

    describe 'SQLite settings' do
      context 'when using SQLite' do
        before do
          ENV['DATABASE_URL'] = 'sqlite://data/glitchcube.db'
        end

        it 'returns the correct sqlite_path', :vcr do
          expect(described_class.sqlite_path).to eq('data/glitchcube.db')
        end
      end

      context 'when not using SQLite' do
        before do
          ENV['DATABASE_URL'] = 'mysql2://user:pass@localhost/db'
        end

        it 'returns nil for sqlite_path', :vcr do
          expect(described_class.sqlite_path).to be_nil
        end
      end
    end
  end

  describe 'Deployment Settings' do
    describe '.deployment_mode' do
      it 'returns :mac_mini when mac_mini_deployment is true', :vcr do
        ENV['MAC_MINI_DEPLOYMENT'] = 'true'
        expect(described_class.deployment_mode).to eq(:mac_mini)
      end

      it 'returns :docker when running in docker', :vcr do
        ENV['MAC_MINI_DEPLOYMENT'] = 'false'
        ENV['DOCKER_CONTAINER'] = 'true'
        expect(described_class.deployment_mode).to eq(:docker)
      end

      it 'returns :production when in production environment', :vcr do
        ENV['MAC_MINI_DEPLOYMENT'] = 'false'
        ENV['DOCKER_CONTAINER'] = nil
        ENV['RACK_ENV'] = 'production'
        expect(described_class.deployment_mode).to eq(:production)
      end

      it 'returns :development as default', :vcr do
        ENV['MAC_MINI_DEPLOYMENT'] = 'false'
        ENV['DOCKER_CONTAINER'] = nil
        ENV['RACK_ENV'] = 'development'
        expect(described_class.deployment_mode).to eq(:development)
      end
    end

    describe '.docker_deployment?' do
      it 'returns true when DOCKER_CONTAINER is set', :vcr do
        ENV['DOCKER_CONTAINER'] = 'true'
        expect(described_class.docker_deployment?).to be true
      end

      it 'returns false when not in docker', :vcr do
        ENV['DOCKER_CONTAINER'] = nil
        allow(File).to receive(:exist?).with('/.dockerenv').and_return(false)
        expect(described_class.docker_deployment?).to be false
      end
    end
  end

  describe 'Configuration Validation' do
    describe '.validate_production_config!' do
      before do
        ENV['OPENROUTER_API_KEY'] = 'valid-key'
        ENV['SESSION_SECRET'] = 'secret'
        ENV['HOME_ASSISTANT_TOKEN'] = 'token'
        ENV['HOME_ASSISTANT_URL'] = 'http://ha.local'
      end

      it 'does not raise when all required config is present', :vcr do
        expect { described_class.validate_production_config! }.not_to raise_error
      end

      it 'raises when OPENROUTER_API_KEY is missing', :vcr do
        ENV['OPENROUTER_API_KEY'] = nil
        expect { described_class.validate_production_config! }.to raise_error(/OPENROUTER_API_KEY is required/)
      end

      it 'raises when SESSION_SECRET is missing', :vcr do
        ENV['SESSION_SECRET'] = nil
        expect { described_class.validate_production_config! }.to raise_error(/SESSION_SECRET should be explicitly set/)
      end

      it 'raises when HOME_ASSISTANT_TOKEN is missing', :vcr do
        ENV['HOME_ASSISTANT_TOKEN'] = nil
        ENV['HA_TOKEN'] = nil
        expect { described_class.validate_production_config! }.to raise_error(/HOME_ASSISTANT_TOKEN is required/)
      end

      it 'raises when HOME_ASSISTANT_URL is missing', :vcr do
        ENV['HOME_ASSISTANT_URL'] = nil
        ENV['HA_URL'] = nil
        expect { described_class.validate_production_config! }.to raise_error(/HOME_ASSISTANT_URL is required/)
      end

      it 'includes all errors in the message', :vcr do
        ENV['OPENROUTER_API_KEY'] = nil
        ENV['SESSION_SECRET'] = nil
        expect { described_class.validate_production_config! }.to raise_error(/OPENROUTER_API_KEY.*SESSION_SECRET/m)
      end
    end
  end

  describe 'Override mechanism' do
    after do
      described_class.clear_overrides!
    end

    describe '.override!' do
      it 'allows overriding boolean settings', :vcr do
        ENV['SIMULATE_CUBE_MOVEMENT'] = 'false'
        described_class.override!(:simulate_cube_movement, true)
        expect(described_class.simulate_cube_movement?).to be true
      end

      it 'allows overriding string settings', :vcr do
        ENV['APP_ROOT'] = '/original/path'
        described_class.override!(:app_root, '/overridden/path')
        expect(described_class.send(:env_value, 'APP_ROOT')).to eq('/overridden/path')
      end
    end

    describe '.clear_overrides!' do
      it 'clears all overrides', :vcr do
        described_class.override!(:simulate_cube_movement, true)
        described_class.clear_overrides!
        ENV['SIMULATE_CUBE_MOVEMENT'] = 'false'
        expect(described_class.simulate_cube_movement?).to be false
      end
    end

    describe '.overridden?' do
      it 'returns true when a key has been overridden', :vcr do
        described_class.override!(:simulate_cube_movement, true)
        expect(described_class.overridden?(:simulate_cube_movement)).to be true
      end

      it 'returns false when a key has not been overridden', :vcr do
        expect(described_class.overridden?(:simulate_cube_movement)).to be false
      end
    end
  end
end
