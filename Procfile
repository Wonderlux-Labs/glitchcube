web: BIND_ALL=true RACK_ENV=production PORT=4567 bundle exec rackup -o 0.0.0.0 -p 4567
worker: bundle exec sidekiq -r ./app.rb -C config/sidekiq.yml