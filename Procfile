web: BIND_ALL=true RACK_ENV=production PORT=4567 PUMA_WORKERS=0 bundle exec rackup -o 0.0.0.0 -p 4567
worker: bundle exec sidekiq -r ./config/sidekiq_boot.rb -C config/sidekiq.yml