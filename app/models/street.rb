# frozen_string_literal: true

class Street < ActiveRecord::Base
  # Validations
  validates :name, presence: true
  validates :street_type, presence: true, inclusion: { in: %w[radial arc] }
  validates :width, presence: true, numericality: { greater_than: 0 }
  validates :geom, presence: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_type, ->(type) { where(street_type: type) }
  scope :radial_streets, -> { where(street_type: 'radial') }
  scope :arc_streets, -> { where(street_type: 'arc') }

  # Viewport-based scope using PostGIS bounding box operator
  scope :within_viewport, lambda { |sw_lng, sw_lat, ne_lng, ne_lat|
    where('geom && ST_MakeEnvelope(?, ?, ?, ?, 4326)', sw_lng, sw_lat, ne_lng, ne_lat)
  }

  # Instance methods
  def radial?
    street_type == 'radial'
  end

  def arc?
    street_type == 'arc'
  end

  def coordinates
    return [] unless geom.present?

    # Extract coordinates from PostGIS geometry
    result = self.class.connection.execute(
      "SELECT ST_AsGeoJSON(geom) as geojson FROM streets WHERE id = #{id}"
    ).first

    return [] unless result && result['geojson']

    geojson = JSON.parse(result['geojson'])
    geojson['coordinates'] || []
  rescue StandardError
    []
  end

  def start_coordinates
    coords = coordinates
    return nil if coords.empty?

    coords.first
  end

  def end_coordinates
    coords = coordinates
    return nil if coords.empty?

    coords.last
  end

  def center_point
    coords = coordinates
    return nil if coords.empty?

    lat_sum = coords.sum { |coord| coord[1] }
    lng_sum = coords.sum { |coord| coord[0] }
    count = coords.length
    [lng_sum / count, lat_sum / count]
  end

  # Modern PostGIS scope for finding nearest streets
  # Usage: Street.nearest(lng, lat, 10) or Street.nearest(lng: -119.20, lat: 40.78, limit: 5)
  scope :nearest, lambda { |*args|
    if args.first.is_a?(Hash)
      opts = args.first
      lng = opts[:lng] || opts[:longitude]
      lat = opts[:lat] || opts[:latitude]
      limit = opts[:limit] || 10
    else
      lng, lat, limit = args
      limit ||= 10
    end

    raise ArgumentError, 'Must provide lng and lat coordinates' unless lng && lat

    # Sanitized point SQL for safe query building
    point_sql = sanitize_sql_array(
      ['ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography', lng.to_f, lat.to_f]
    )

    active
      .select("#{table_name}.*, ST_Distance(geom::geography, #{point_sql}) AS distance_meters")
      .order(Arel.sql("geom::geography <-> #{point_sql}"))
      .limit(limit)
  }

  # Find streets within a certain distance (meters)
  scope :within_meters, lambda { |lng, lat, meters|
    raise ArgumentError, 'Must provide lng, lat, and meters' unless lng && lat && meters

    point_sql = sanitize_sql_array(
      ['ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography', lng.to_f, lat.to_f]
    )

    where("ST_DWithin(geom::geography, #{point_sql}, ?)", meters.to_f)
  }

  # Lightning-fast nearest street finder with distance (FIXED coordinate order)
  def self.nearest_streets(lat, lng, limit = 5, max_distance_meters = 1000)
    # Use consistent lng, lat order for PostGIS (matches GeoJSON standard)
    select('*, ST_Distance(geom::geography, ST_Point(?, ?)::geography) as distance', lng, lat)
      .where('ST_DWithin(geom::geography, ST_Point(?, ?)::geography, ?)', lng, lat, max_distance_meters)
      .order('distance')
      .limit(limit)
  end

  # Simple and fast: find nearest radial and arc streets
  # At Burning Man, intersections are always radial + arc
  def self.nearest_intersection(lat, lng)
    nearest_radial = radial_streets.nearest(lat: lat, lng: lng, limit: 1).first
    nearest_arc = arc_streets.nearest(lat: lat, lng: lng, limit: 1).first

    {
      radial: nearest_radial&.name,
      arc: nearest_arc&.name,
      radial_distance: nearest_radial&.distance_meters,
      arc_distance: nearest_arc&.distance_meters
    }
  end

  # Get both nearest radial and arc in one call (FIXED to use consistent nearest scope)
  def self.nearest_radial_and_arc(lat, lng)
    # Use the consistent nearest scope instead of duplicate SQL
    radial = radial_streets.nearest(lat: lat, lng: lng, limit: 1).first
    arc = arc_streets.nearest(lat: lat, lng: lng, limit: 1).first

    { radial: radial, arc: arc }
  end

  # Class methods
  def self.import_from_geojson(file_path)
    return unless File.exist?(file_path)

    data = JSON.parse(File.read(file_path))
    imported_count = 0

    data['features'].each do |feature|
      street = find_or_initialize_by(
        name: feature['properties']['name'],
        street_type: feature['properties']['type']
      )

      street.assign_attributes(
        width: feature['properties']['width']&.to_i || 30,
        properties: {
          fid: feature['id'],
          original_properties: feature['properties'],
          geometry_type: feature['geometry']['type']
        }.compact,
        active: true
      )

      next unless street.save(validate: false) # Skip validation since geom will be set separately

      # Set geometry using PostGIS
      geojson = feature['geometry'].to_json
      connection.execute(sanitize_sql_array([
                                              'UPDATE streets SET geom = ST_SetSRID(ST_GeomFromGeoJSON(?), 4326) WHERE id = ?',
                                              geojson, street.id
                                            ]))
      imported_count += 1
    end

    puts "✅ Imported #{imported_count} streets from #{File.basename(file_path)}"
    imported_count
  end
end
