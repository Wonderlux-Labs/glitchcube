# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cube::Settings do
  describe 'Feature Toggles' do
    before { described_class.clear_overrides! }
    after { described_class.clear_overrides! }

    describe '.simulate_cube_movement?' do
      it 'returns true when overridden to true', :vcr do
        described_class.override!(:simulate_cube_movement, true)
        expect(described_class.simulate_cube_movement?).to be true
      end

      it 'returns false when overridden to false', :vcr do
        described_class.override!(:simulate_cube_movement, false)
        expect(described_class.simulate_cube_movement?).to be false
      end
    end

    # Mock Home Assistant functionality removed - using real HA instance

    describe '.disable_circuit_breakers?' do
      after do
        described_class.clear_overrides!
      end

      xit 'returns true in test environment by default', :pending, :vcr do
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
      it 'returns true when ENV is set to true' do
        with_env_vars('MAC_MINI_DEPLOYMENT' => 'true') do
          expect(described_class.mac_mini_deployment?).to be true
        end
      end

      it 'returns false when ENV is not true' do
        with_env_vars('MAC_MINI_DEPLOYMENT' => 'false') do
          expect(described_class.mac_mini_deployment?).to be false
        end
      end
    end
  end

  describe 'Environment' do
    describe '.rack_env' do
      it 'returns the current rack environment' do
        # Test that it reads from ENV properly - we know test env is set
        expect(described_class.rack_env).to eq('test')
      end

      it 'can be mocked for testing other environments' do
        allow(described_class).to receive(:rack_env).and_return('production')
        expect(described_class.rack_env).to eq('production')
      end
    end

    describe '.development?' do
      it 'returns true when in development environment' do
        allow(described_class).to receive(:rack_env).and_return('development')
        expect(described_class.development?).to be true
      end

      it 'returns false for other environments' do
        allow(described_class).to receive(:rack_env).and_return('production')
        expect(described_class.development?).to be false
      end
    end

    describe '.test?' do
      it 'returns true in test environment' do
        # We're in test, so this should be true
        expect(described_class.test?).to be true
      end
    end

    describe '.production?' do
      it 'returns true when in production environment' do
        allow(described_class).to receive(:rack_env).and_return('production')
        expect(described_class.production?).to be true
      end

      it 'returns false in test environment' do
        # We're in test, so this should be false
        expect(described_class.production?).to be false
      end
    end
  end

  describe 'Application Settings' do
    describe '.app_root' do
      it 'returns APP_ROOT when set' do
        with_env_vars('APP_ROOT' => '/tmp/test/path') do
          expect(described_class.app_root).to eq('/tmp/test/path')
        end
      end

      it 'defaults to current directory when not set' do
        with_env_vars('APP_ROOT' => nil) do
          expect(described_class.app_root).to eq(Dir.pwd)
        end
      end
    end

    describe '.session_secret' do
      it 'returns the SESSION_SECRET value' do
        with_env_vars('SESSION_SECRET' => 'super-secret-key') do
          expect(described_class.session_secret).to eq('super-secret-key')
        end
      end
    end
  end

  describe 'API Keys and Tokens' do
    describe '.openrouter_api_key' do
      it 'returns the OPENROUTER_API_KEY value', :vcr do
        with_env_vars('OPENROUTER_API_KEY' => 'test-api-key') do
          expect(described_class.openrouter_api_key).to eq('test-api-key')
        end
      end
    end

    describe '.home_assistant_token' do
      it 'returns HOME_ASSISTANT_TOKEN when set', :vcr do
        with_env_vars('HOME_ASSISTANT_TOKEN' => 'ha-token', 'HA_TOKEN' => nil) do
          expect(described_class.home_assistant_token).to eq('ha-token')
        end
      end

      it 'falls back to HA_TOKEN when HOME_ASSISTANT_TOKEN is not set', :vcr do
        with_env_vars('HOME_ASSISTANT_TOKEN' => nil, 'HA_TOKEN' => 'fallback-token') do
          expect(described_class.home_assistant_token).to eq('fallback-token')
        end
      end
    end

    describe '.github_webhook_secret' do
      it 'returns the GITHUB_WEBHOOK_SECRET value', :vcr do
        with_env_vars('GITHUB_WEBHOOK_SECRET' => 'webhook-secret') do
          expect(described_class.github_webhook_secret).to eq('webhook-secret')
        end
      end
    end
  end

  describe 'URLs and Endpoints' do
    describe '.home_assistant_url' do
      it 'returns HOME_ASSISTANT_URL when set', :vcr do
        with_env_vars('HOME_ASSISTANT_URL' => 'http://ha.local', 'HA_URL' => nil) do
          expect(described_class.home_assistant_url).to eq('http://ha.local')
        end
      end

      it 'falls back to HA_URL when HOME_ASSISTANT_URL is not set', :vcr do
        with_env_vars('HOME_ASSISTANT_URL' => nil, 'HA_URL' => 'http://fallback.local') do
          expect(described_class.home_assistant_url).to eq('http://fallback.local')
        end
      end
    end
  end

  describe 'Database Configuration' do
    describe '.database_type' do
      it 'returns :sqlite for sqlite URLs', :vcr do
        with_env_vars('DATABASE_URL' => 'sqlite://data/glitchcube.db') do
          expect(described_class.database_type).to eq(:sqlite)
        end
      end

      it 'returns :mariadb for mysql URLs', :vcr do
        with_env_vars('DATABASE_URL' => 'mysql2://user:pass@localhost/db') do
          expect(described_class.database_type).to eq(:mariadb)
        end
      end

      it 'returns :mariadb for mariadb URLs', :vcr do
        with_env_vars('DATABASE_URL' => 'mariadb://user:pass@localhost/db') do
          expect(described_class.database_type).to eq(:mariadb)
        end
      end

      it 'returns :postgres for postgres URLs', :vcr do
        with_env_vars('DATABASE_URL' => 'postgresql://user:pass@localhost/db') do
          expect(described_class.database_type).to eq(:postgres)
        end
      end

      it 'defaults to :sqlite for unknown types', :vcr do
        with_env_vars('DATABASE_URL' => 'unknown://something') do
          expect(described_class.database_type).to eq(:sqlite)
        end
      end
    end

    describe '.using_mariadb?' do
      it 'returns true when DATABASE_URL is mysql', :vcr do
        with_env_vars('DATABASE_URL' => 'mysql2://user:pass@localhost/db') do
          expect(described_class.using_mariadb?).to be true
        end
      end

      it 'returns false when DATABASE_URL is sqlite', :vcr do
        with_env_vars('DATABASE_URL' => 'sqlite://data/glitchcube.db') do
          expect(described_class.using_mariadb?).to be false
        end
      end
    end

    describe '.using_sqlite?' do
      it 'returns true when DATABASE_URL is sqlite', :vcr do
        with_env_vars('DATABASE_URL' => 'sqlite://data/glitchcube.db') do
          expect(described_class.using_sqlite?).to be true
        end
      end

      it 'returns false when DATABASE_URL is not sqlite', :vcr do
        with_env_vars('DATABASE_URL' => 'mysql2://user:pass@localhost/db') do
          expect(described_class.using_sqlite?).to be false
        end
      end
    end

    describe 'MariaDB settings' do
      context 'when using MariaDB' do
        let(:mariadb_env) do
          {
            'DATABASE_URL' => 'mysql2://user:pass@localhost/db',
            'MARIADB_HOST' => 'db.example.com',
            'MARIADB_PORT' => '3307'
          }
        end

        it 'returns mariadb_host when using MariaDB', :vcr do
          with_env_vars(mariadb_env) do
            expect(described_class.mariadb_host).to eq('db.example.com')
          end
        end

        it 'returns mariadb_port when using MariaDB', :vcr do
          with_env_vars(mariadb_env) do
            expect(described_class.mariadb_port).to eq(3307)
          end
        end

        it 'constructs mariadb_url correctly', :vcr do
          with_env_vars(
            mariadb_env.merge(
              'MARIADB_USERNAME' => 'testuser',
              'MARIADB_PASSWORD' => 'testpass',
              'MARIADB_DATABASE' => 'testdb'
            )
          ) do
            expect(described_class.mariadb_url).to eq('mysql2://testuser:testpass@db.example.com:3307/testdb')
          end
        end
      end

      context 'when not using MariaDB' do
        it 'returns nil for mariadb_host', :vcr do
          with_env_vars('DATABASE_URL' => 'sqlite://data/glitchcube.db') do
            expect(described_class.mariadb_host).to be_nil
          end
        end

        it 'returns nil for mariadb_port', :vcr do
          with_env_vars('DATABASE_URL' => 'sqlite://data/glitchcube.db') do
            expect(described_class.mariadb_port).to be_nil
          end
        end

        it 'returns nil for mariadb_url', :vcr do
          with_env_vars('DATABASE_URL' => 'sqlite://data/glitchcube.db') do
            expect(described_class.mariadb_url).to be_nil
          end
        end
      end
    end

    describe 'SQLite settings' do
      context 'when using SQLite' do
        it 'returns the correct sqlite_path', :vcr do
          with_env_vars('DATABASE_URL' => 'sqlite://data/glitchcube.db') do
            expect(described_class.sqlite_path).to eq('data/glitchcube.db')
          end
        end
      end

      context 'when not using SQLite' do
        it 'returns nil for sqlite_path', :vcr do
          with_env_vars('DATABASE_URL' => 'mysql2://user:pass@localhost/db') do
            expect(described_class.sqlite_path).to be_nil
          end
        end
      end
    end
  end

  describe 'Deployment Settings' do
    describe '.deployment_mode' do
      it 'returns :mac_mini when mac_mini_deployment is true', :vcr do
        with_env_vars('MAC_MINI_DEPLOYMENT' => 'true') do
          expect(described_class.deployment_mode).to eq(:mac_mini)
        end
      end

      it 'returns :docker when running in docker', :vcr do
        with_env_vars('MAC_MINI_DEPLOYMENT' => 'false', 'DOCKER_CONTAINER' => 'true') do
          expect(described_class.deployment_mode).to eq(:docker)
        end
      end

      it 'returns :production when in production environment', :vcr do
        with_env_vars(
          'MAC_MINI_DEPLOYMENT' => 'false',
          'DOCKER_CONTAINER' => nil,
          'RACK_ENV' => 'production'
        ) do
          expect(described_class.deployment_mode).to eq(:production)
        end
      end

      it 'returns :development as default', :vcr do
        with_env_vars(
          'MAC_MINI_DEPLOYMENT' => 'false',
          'DOCKER_CONTAINER' => nil,
          'RACK_ENV' => 'development'
        ) do
          expect(described_class.deployment_mode).to eq(:development)
        end
      end
    end

    describe '.docker_deployment?' do
      it 'returns true when DOCKER_CONTAINER is set', :vcr do
        with_env_vars('DOCKER_CONTAINER' => 'true') do
          expect(described_class.docker_deployment?).to be true
        end
      end

      it 'returns false when not in docker', :vcr do
        with_env_vars('DOCKER_CONTAINER' => nil) do
          allow(File).to receive(:exist?).with('/.dockerenv').and_return(false)
          expect(described_class.docker_deployment?).to be false
        end
      end
    end
  end

  describe 'Configuration Validation' do
    describe '.validate_production_config!' do
      let(:valid_config) do
        {
          'OPENROUTER_API_KEY' => 'valid-key',
          'SESSION_SECRET' => 'secret',
          'HOME_ASSISTANT_TOKEN' => 'token',
          'HOME_ASSISTANT_URL' => 'http://ha.local'
        }
      end

      it 'does not raise when all required config is present', :vcr do
        with_env_vars(valid_config) do
          expect { described_class.validate_production_config! }.not_to raise_error
        end
      end

      it 'raises when OPENROUTER_API_KEY is missing', :vcr do
        with_env_vars(valid_config.merge('OPENROUTER_API_KEY' => nil)) do
          expect { described_class.validate_production_config! }.to raise_error(/OPENROUTER_API_KEY is required/)
        end
      end

      it 'raises when SESSION_SECRET is missing', :vcr do
        with_env_vars(valid_config.merge('SESSION_SECRET' => nil)) do
          expect { described_class.validate_production_config! }.to raise_error(/SESSION_SECRET should be explicitly set/)
        end
      end

      it 'raises when HOME_ASSISTANT_TOKEN is missing', :vcr do
        with_env_vars(valid_config.merge('HOME_ASSISTANT_TOKEN' => nil, 'HA_TOKEN' => nil)) do
          expect { described_class.validate_production_config! }.to raise_error(/HOME_ASSISTANT_TOKEN is required/)
        end
      end

      it 'raises when HOME_ASSISTANT_URL is missing', :vcr do
        with_env_vars(valid_config.merge('HOME_ASSISTANT_URL' => nil, 'HA_URL' => nil)) do
          expect { described_class.validate_production_config! }.to raise_error(/HOME_ASSISTANT_URL is required/)
        end
      end

      it 'includes all errors in the message', :vcr do
        with_env_vars(valid_config.merge('OPENROUTER_API_KEY' => nil, 'SESSION_SECRET' => nil)) do
          expect { described_class.validate_production_config! }.to raise_error(/OPENROUTER_API_KEY.*SESSION_SECRET/m)
        end
      end
    end
  end

  describe 'Override mechanism' do
    after do
      described_class.clear_overrides!
    end

    describe '.override!' do
      it 'allows overriding boolean settings', :vcr do
        with_env_vars('SIMULATE_CUBE_MOVEMENT' => 'false') do
          described_class.override!(:simulate_cube_movement, true)
          expect(described_class.simulate_cube_movement?).to be true
        end
      end

      it 'allows overriding string settings', :vcr do
        with_env_vars('APP_ROOT' => '/original/path') do
          described_class.override!(:app_root, '/overridden/path')
          expect(described_class.send(:env_value, 'APP_ROOT')).to eq('/overridden/path')
        end
      end
    end

    describe '.clear_overrides!' do
      it 'clears all overrides', :vcr do
        described_class.override!(:simulate_cube_movement, true)
        described_class.clear_overrides!
        with_env_vars('SIMULATE_CUBE_MOVEMENT' => 'false') do
          expect(described_class.simulate_cube_movement?).to be false
        end
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
