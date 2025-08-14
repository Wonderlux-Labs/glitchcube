# frozen_string_literal: true

# Parent module for all API routes
# This file defines the Api namespace that individual route files nest under
module Routes
  module Api
    # This module serves as a namespace container for all API routes
    # Individual route modules are defined in separate files:
    # - Routes::Api::Conversation (lib/routes/api/conversation.rb)
    # - Routes::Api::Gps (lib/routes/api/gps.rb)
    # - Routes::Api::System (lib/routes/api/system.rb)
    # etc.
  end
end
