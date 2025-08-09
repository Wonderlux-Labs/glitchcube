# frozen_string_literal: true

namespace :hass do
  desc 'Deploy Home Assistant configuration to VM via SCP'
  task :deploy do
    # VM Configuration - Update these for your Mac Mini/VMware setup
    vm_host = ENV['HASS_VM_HOST'] || '192.168.1.100' # VM's separate IP
    vm_user = ENV['HASS_VM_USER'] || 'homeassistant'
    vm_config_path = '/config'
    local_hass_path = 'config/homeassistant'

    puts "🚀 Deploying Home Assistant config to VM at #{vm_user}@#{vm_host}"

    unless Dir.exist?(local_hass_path)
      puts "❌ Local HA config not found at #{local_hass_path}"
      exit 1
    end

    # Create backup on VM first
    puts '💾 Creating backup on VM...'
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    ssh_cmd = "ssh #{vm_user}@#{vm_host}"
    system("#{ssh_cmd} 'mkdir -p #{vm_config_path}/backups && cd #{vm_config_path} && tar -czf backups/pre_deploy_#{timestamp}.tar.gz *.yaml automations scripts sensors custom_components 2>/dev/null || true'")

    # Core config files
    config_files = %w[
      configuration.yaml
      automations.yaml
      scenes.yaml
      scripts.yaml
      rest_commands.yaml
      mqtt.yaml
    ]

    # Directories to sync
    config_dirs = %w[
      automations
      scripts
      sensors
      template
      binary_sensors
      input_helpers
      custom_components/glitchcube_conversation
    ]

    # Deploy files
    puts '📤 Deploying configuration files...'
    config_files.each do |file|
      local_file = "#{local_hass_path}/#{file}"
      if File.exist?(local_file)
        puts "  📄 #{file}"
        system("scp -q #{local_file} #{vm_user}@#{vm_host}:#{vm_config_path}/")
      end
    end

    # Deploy directories
    config_dirs.each do |dir|
      local_dir = "#{local_hass_path}/#{dir}"
      next unless Dir.exist?(local_dir)

      puts "  📁 #{dir}/"
      remote_dir = "#{vm_config_path}/#{dir}"
      system("#{ssh_cmd} 'mkdir -p #{remote_dir}'")
      system("scp -q -r #{local_dir}/* #{vm_user}@#{vm_host}:#{remote_dir}/ 2>/dev/null")
    end

    puts '✅ Configuration deployed!'

    # Reload HA config
    puts '🔄 Reloading Home Assistant...'
    reload_result = system("#{ssh_cmd} 'ha core check' 2>/dev/null")

    if reload_result
      system("#{ssh_cmd} 'ha core restart'")
      puts '✅ Home Assistant restarted!'
    else
      puts '⚠️  Could not validate config, attempting reload anyway...'
      system("#{ssh_cmd} 'sudo systemctl restart home-assistant@homeassistant' 2>/dev/null")
    end

    puts '🎉 Deployment complete!'
  end

  desc 'Quick deploy - Just copy files without backup/restart'
  task :quick do
    vm_host = ENV['HASS_VM_HOST'] || '192.168.1.100'
    vm_user = ENV['HASS_VM_USER'] || 'homeassistant'
    vm_config_path = '/config'
    local_hass_path = 'config/homeassistant'

    puts "⚡ Quick deploy to #{vm_user}@#{vm_host}"

    # Use rsync for faster sync
    rsync_cmd = "rsync -av --exclude='*.log' --exclude='*.db' --exclude='.storage' #{local_hass_path}/ #{vm_user}@#{vm_host}:#{vm_config_path}/"

    if system(rsync_cmd)
      puts '✅ Files synced!'
      puts '💡 Run "rake hass:reload" to apply changes'
    else
      puts '❌ Sync failed!'
    end
  end

  desc 'Pull current config from VM'
  task :pull do
    vm_host = ENV['HASS_VM_HOST'] || '192.168.1.100'
    vm_user = ENV['HASS_VM_USER'] || 'homeassistant'
    vm_config_path = '/config'
    local_hass_path = 'config/homeassistant'

    puts "📥 Pulling config from #{vm_user}@#{vm_host}"

    FileUtils.mkdir_p(local_hass_path)

    # Use rsync to pull
    rsync_cmd = "rsync -av --exclude='*.log' --exclude='*.db' --exclude='.storage' --exclude='backups' #{vm_user}@#{vm_host}:#{vm_config_path}/ #{local_hass_path}/"

    if system(rsync_cmd)
      puts '✅ Configuration pulled!'
      puts "📁 Files saved to #{local_hass_path}"
    else
      puts '❌ Pull failed!'
    end
  end

  desc 'Reload Home Assistant configuration'
  task :reload do
    vm_host = ENV['HASS_VM_HOST'] || '192.168.1.100'
    vm_user = ENV['HASS_VM_USER'] || 'homeassistant'

    puts '🔄 Reloading Home Assistant YAML configs...'
    ssh_cmd = "ssh #{vm_user}@#{vm_host}"

    # Try different reload methods
    if system("#{ssh_cmd} 'ha service call homeassistant.reload_all' 2>/dev/null")
      puts '✅ All YAML configurations reloaded!'
    elsif system("#{ssh_cmd} 'ha core check && ha core restart' 2>/dev/null")
      puts '✅ Home Assistant restarted!'
    else
      puts '⚠️  Manual restart may be required'
      puts "  SSH to VM: ssh #{vm_user}@#{vm_host}"
      puts '  Then run: ha core restart'
    end
  end

  desc 'Check VM connectivity and HA status'
  task :status do
    vm_host = ENV['HASS_VM_HOST'] || '192.168.1.100'
    vm_user = ENV['HASS_VM_USER'] || 'homeassistant'

    puts '🔍 Checking Home Assistant VM status...'
    ssh_cmd = "ssh #{vm_user}@#{vm_host}"

    # Test SSH connectivity
    if system("#{ssh_cmd} 'exit' 2>/dev/null")
      puts "✅ SSH connection to #{vm_host} successful"

      # Check HA status
      ha_status = `#{ssh_cmd} 'ha core info --raw-json 2>/dev/null | jq -r .state 2>/dev/null || echo "unknown"'`.strip
      puts "🏠 Home Assistant status: #{ha_status}"

      # Check last deployment
      if File.exist?('.last_deploy')
        last_deploy = File.read('.last_deploy').strip
        puts "📅 Last deployment: #{last_deploy}"
      end
    else
      puts "❌ Cannot connect to #{vm_host}"
      puts 'Check that:'
      puts '  1. VM is running'
      puts '  2. SSH is enabled'
      puts "  3. Host/IP is correct (current: #{vm_host})"
      puts '  4. Set HASS_VM_HOST and HASS_VM_USER env vars if needed'
    end
  end

  desc 'Setup SSH key for passwordless deployment'
  task :setup_ssh do
    vm_host = ENV['HASS_VM_HOST'] || '192.168.1.100'
    vm_user = ENV['HASS_VM_USER'] || 'homeassistant'

    puts '🔑 Setting up SSH key for passwordless access...'

    # Check if key exists
    ssh_key = File.expand_path('~/.ssh/id_rsa.pub')
    unless File.exist?(ssh_key)
      puts '⚠️  No SSH key found. Generate one with:'
      puts '  ssh-keygen -t rsa -b 4096'
      exit 1
    end

    puts "📤 Copying SSH key to #{vm_user}@#{vm_host}"
    puts "You'll need to enter the VM password once:"

    if system("ssh-copy-id #{vm_user}@#{vm_host}")
      puts '✅ SSH key installed!'
      puts 'You can now deploy without entering a password'
    else
      puts '❌ Failed to copy SSH key'
    end
  end

  desc 'Deploy and notify Home Assistant of completion'
  task deploy_with_notify: [:deploy] do
    ENV['HASS_VM_HOST'] || '192.168.1.100'

    puts '📢 Notifying Home Assistant of deployment...'

    # Create a marker file with deployment info
    deploy_info = {
      timestamp: Time.now.iso8601,
      git_commit: `git rev-parse HEAD`.strip,
      git_branch: `git branch --show-current`.strip,
      deployed_by: ENV.fetch('USER', nil)
    }

    File.write('.last_deploy', deploy_info.to_json)

    # Could also send a webhook to HA if configured
    # system("curl -X POST http://#{vm_host}:8123/api/webhook/deployment_complete -d '#{deploy_info.to_json}'")

    puts '✅ Deployment recorded'
  end
end

# Convenience aliases
desc 'Deploy Home Assistant config to VM'
task hass: 'hass:deploy'

desc 'Quick sync HA config without restart'
task 'hass:sync' => 'hass:quick'
