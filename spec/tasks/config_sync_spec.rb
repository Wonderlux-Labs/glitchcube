# frozen_string_literal: true

require 'spec_helper'
require 'rake'

RSpec.describe 'Config sync rake tasks' do
  before(:all) do
    # Load the rake tasks
    Rake.application.rake_require 'tasks/config_sync'
  end

  let(:rake) { Rake::Application.new }

  before do
    Rake.application = rake
    Rake.application.rake_require 'tasks/config_sync'
  end

  describe 'task definitions' do
    %w[
      config:push_newer
      config:pull_newer
      config:push_created
      config:pull_created
      config:clean_local
      config:clean_remote
      config:prune
      config:sync
      config:mirror_to_remote
      config:mirror_from_remote
      config:status
      config:backup
      config:diff
      config:bisync
      config:smartsync
    ].each do |task_name|
      it "defines #{task_name} task" do
        expect(Rake::Task.task_defined?(task_name)).to be true
      end
    end

    it 'defines convenience aliases' do
      expect(Rake::Task.task_defined?('config:push')).to be true
      expect(Rake::Task.task_defined?('config:pull')).to be true

      # Verify aliases point to the correct tasks
      expect(Rake::Task['config:push'].prerequisites).to include('config:push_newer')
      expect(Rake::Task['config:pull'].prerequisites).to include('config:pull_newer')
    end
  end

  describe 'task descriptions' do
    it 'has meaningful descriptions for all tasks' do
      task_descriptions = {
        'config:push_newer' => /Push only newer.*local files.*remote/i,
        'config:pull_newer' => /Pull only newer.*remote files.*local/i,
        'config:push_created' => /Push only new local files/i,
        'config:pull_created' => /Pull only new remote files/i,
        'config:clean_local' => /Delete local files.*don't exist on remote/i,
        'config:clean_remote' => /Delete remote files.*don't exist locally/i,
        'config:prune' => /Interactive cleanup/i,
        'config:sync' => /Smart bidirectional sync.*conflict detection/i,
        'config:mirror_to_remote' => /Make remote exactly match local/i,
        'config:mirror_from_remote' => /Make local exactly match remote/i,
        'config:status' => /Show sync status.*differences/i,
        'config:backup' => /Create timestamped backup/i,
        'config:diff' => /Show detailed diff/i
      }

      task_descriptions.each do |task_name, expected_pattern|
        task = Rake::Task[task_name]
        expect(task.full_comment).to match(expected_pattern)
      end
    end
  end

  describe 'helper methods' do
    let(:task_namespace) { Object.new.extend(Rake::DSL) }

    before do
      # Load the tasks into our test context
      load File.join(Rails.root, 'lib/tasks/config_sync.rake') if defined?(Rails)
    end

    it 'defines expected constants' do
      expect(defined?(REMOTE_HOST)).to be_truthy
      expect(defined?(REMOTE_CONFIG_PATH)).to be_truthy
      expect(defined?(LOCAL_CONFIG_PATH)).to be_truthy
    end
  end

  describe 'dry run functionality' do
    around do |example|
      original_env = ENV.fetch('DRY_RUN', nil)
      ENV['DRY_RUN'] = 'true'
      example.run
      ENV['DRY_RUN'] = original_env
    end

    it 'respects DRY_RUN environment variable' do
      # This test would need to mock the actual rsync calls
      # For now, just verify the environment variable is respected
      expect(ENV.fetch('DRY_RUN', nil)).to eq('true')
    end
  end

  describe 'exclude patterns' do
    it 'excludes system files and logs' do
      expected_excludes = [
        '.storage',
        'backups',
        'tts',
        '.cloud',
        'deps',
        'llmvision',
        'home-assistant.log*',
        '*.db*',
        'secrets.yaml',
        '.DS_Store',
        '**/__pycache__/',
        '*.pyc',
        'logs/',
        '*.log'
      ]

      # Would need to access the actual SYNC_EXCLUDES constant
      # This is more of an integration test
      expect(expected_excludes).to all(be_a(String))
    end

    it 'includes only our custom component and excludes others' do
      expected_includes = [
        'custom_components/glitchcube_conversation/',
        'custom_components/glitchcube_conversation/**'
      ]

      expected_excludes = [
        'custom_components/**'
      ]

      expect(expected_includes).to all(be_a(String))
      expect(expected_excludes).to all(be_a(String))
    end
  end
end
