# frozen_string_literal: true

# All autoloading is now handled by Zeitwerk - no manual loading needed
# This file is deprecated and will be removed

# Create backward compatibility aliases after Zeitwerk loading
unless defined?(ErrorHandling)
  Object.const_set(:ErrorHandling, Modules::ErrorHandling)
end

unless defined?(ConversationModule)
  Object.const_set(:ConversationModule, Modules::ConversationModule)
end
