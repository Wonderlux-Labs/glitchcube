# frozen_string_literal: true

# Use SQL format for schema dumps to properly handle PostGIS geometry types
# The Ruby schema format cannot dump spatial columns correctly
#
# Note: In Sinatra-ActiveRecord, the schema format is controlled differently than Rails
# We use the custom db:structure_dump task in lib/tasks/postgis_schema.rake instead
# which uses pg_dump to properly handle PostGIS geometry types
