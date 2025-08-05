# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/jobs/simulate_cube_movement_worker'

RSpec.describe Jobs::SimulateCubeMovementWorker do
  let(:worker) { described_class.new }
  let(:sim_file) { Jobs::SimulateCubeMovementWorker::SIM_FILE }
  let(:history_file) { Jobs::SimulateCubeMovementWorker::HISTORY_FILE }
  let(:dest_file) { Jobs::SimulateCubeMovementWorker::DEST_FILE }

  before do
    allow(Cube::Settings).to receive(:simulate_cube_movement?).and_return(true)
    # Clean up files before each test
    FileUtils.rm_f(sim_file)
    FileUtils.rm_f(history_file)
    FileUtils.rm_f(dest_file)
  end

  after do
    # Clean up files after tests
    FileUtils.rm_f(sim_file)
    FileUtils.rm_f(history_file)
    FileUtils.rm_f(dest_file)
  end

  describe '#perform' do
    context 'when simulation is disabled' do
      it 'returns immediately without moving' do
        allow(Cube::Settings).to receive(:simulate_cube_movement?).and_return(false)
        
        expect(worker).not_to receive(:move_toward_destination)
        worker.perform
        
        expect(File.exist?(sim_file)).to be false
      end
    end

    context 'when simulation is enabled' do
      it 'creates coordinate file with proper movement data' do
        # Mock the should_continue? method to limit execution
        call_count = 0
        allow(worker).to receive(:should_continue?) do
          call_count += 1
          call_count <= 2  # Only run 2 iterations
        end
        
        # Mock sleep to avoid actual delays
        allow(worker).to receive(:sleep)
        
        worker.perform
        
        expect(File.exist?(sim_file)).to be true
        
        coords = JSON.parse(File.read(sim_file))
        expect(coords).to have_key('lat')
        expect(coords).to have_key('lng')
        expect(coords).to have_key('timestamp')
        expect(coords).to have_key('address')
        expect(coords).to have_key('destination')
        
        expect(coords['lat']).to be_a(Float)
        expect(coords['lng']).to be_a(Float)
        expect(coords['destination']).to be_a(String)
      end

      it 'moves toward its destination' do
        # Mock should_continue to limit execution
        call_count = 0
        allow(worker).to receive(:should_continue?) do
          call_count += 1
          call_count <= 1  # Only run 1 iteration
        end
        allow(worker).to receive(:sleep)
        
        # Track movement calls
        expect(worker).to receive(:move_toward_destination).at_least(:once).and_call_original
        
        worker.perform
      end

      it 'loads existing configuration or uses defaults' do
        # Test default configuration loading
        config_path = Jobs::SimulateCubeMovementWorker::CONFIG_FILE
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(config_path).and_return(false)
        
        # Mock should_continue to prevent long execution
        call_count = 0
        allow(worker).to receive(:should_continue?) do
          call_count += 1
          call_count <= 1  # Only run 1 iteration
        end
        allow(worker).to receive(:sleep)
        
        worker.perform
        
        # Should use default destinations
        expect(File.exist?(sim_file)).to be true
      end
    end
  end

  describe 'cron schedule' do
    it 'is configured to run every 5 minutes' do
      # Load the cron configuration
      cron_config = YAML.load_file(File.expand_path('../../config/sidekiq_cron.yml', __dir__))
      
      job_config = cron_config['simulate_cube_movement_worker']
      expect(job_config).not_to be_nil
      expect(job_config['cron']).to eq('*/5 * * * *')
      expect(job_config['class']).to eq('Jobs::SimulateCubeMovementWorker')
    end
  end
end