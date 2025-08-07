# frozen_string_literal: true

class Street < ActiveRecord::Base
  # Validations
  validates :name, presence: true
  validates :street_type, presence: true, inclusion: { in: %w[radial arc] }
  validates :width, presence: true, numericality: { greater_than: 0 }
  validates :coordinates, presence: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_type, ->(type) { where(street_type: type) }
  scope :radial_streets, -> { where(street_type: 'radial') }
  scope :arc_streets, -> { where(street_type: 'arc') }

  # Instance methods
  def radial?
    street_type == 'radial'
  end

  def arc?
    street_type == 'arc'
  end

  def start_coordinates
    return nil if coordinates.empty?

    coordinates.first
  end

  def end_coordinates
    return nil if coordinates.empty?

    coordinates.last
  end

  def center_point
    return nil if coordinates.empty?

    lat_sum = coordinates.sum { |coord| coord[1] }
    lng_sum = coordinates.sum { |coord| coord[0] }
    count = coordinates.length
    [lng_sum / count, lat_sum / count]
  end

  # Class methods
  def self.import_from_geojson(file_path)
    return unless File.exist?(file_path)

    data = JSON.parse(File.read(file_path))
    data['features'].each do |feature|
      street = find_or_initialize_by(
        name: feature['properties']['name'],
        street_type: feature['properties']['type']
      )

      street.assign_attributes(
        coordinates: feature['geometry']['coordinates'],
        width: feature['properties']['width']&.to_i || 30,
        properties: {
          fid: feature['id'],
          geometry_type: feature['geometry']['type']
        }.compact,
        active: true
      )

      street.save! if street.changed?
    end
  end
end
