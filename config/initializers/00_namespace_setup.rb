# frozen_string_literal: true

# This file sets up namespaces BEFORE any code loading happens
# It ensures all modules exist before any code tries to reference them

# Define root module
module GlitchCube
  # Pre-define all nested modules to avoid constant resolution issues
  module Routes; end
  module Services; end
  module Jobs; end
  module Personas; end
  module Tools; end
  module Helpers; end
  module Modules; end
  module Schemas; end
  module Core; end
end

# Define global modules if they don't exist
unless defined?(Services)
  module Services
    # Zeitwerk will handle const_missing automatically for services
    # No custom const_missing needed since file names match class names
  end
end

module Utils; end unless defined?(Utils)
