# frozen_string_literal: true

class Boundary < ActiveRecord::Base
  # Validations
  validates :name, presence: true
  validates :boundary_type, presence: true
  validates :coordinates, presence: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_type, ->(type) { where(boundary_type: type) }

  # Instance methods
  def polygon_coordinates
    # Return coordinates in format expected by geocoder
    coordinates.first if coordinates.is_a?(Array) && coordinates.first.is_a?(Array)
  end

  def contains_point?(lat, lng)
    # For now, delegate to LocationHelper which has the tested trash fence logic
    require_relative '../../lib/utils/location_helper'
    include Utils::LocationHelper
    within_trash_fence?(lat, lng)
  end

  # Class methods
  def self.trash_fence
    by_type('fence').first
  end

  def self.within_fence?(lat, lng)
    trash_fence&.contains_point?(lat, lng) || false
  end

  def self.create_trash_fence!
    # Hardcoded trash fence from GIS data
    trash_fence_coords = [[
      [-119.23273810046265, 40.783393446219854],
      [-119.20773209353101, 40.764368446672798], 
      [-119.17619408998932, 40.776562450337401],
      [-119.18168009473258, 40.80310545215228],
      [-119.21663410121434, 40.80735944960616],
      [-119.23273810046265, 40.783393446219854] # Close polygon
    ]]
    
    find_or_create_by!(
      name: 'Burning Man Trash Fence',
      boundary_type: 'fence'
    ) do |boundary|
      boundary.coordinates = trash_fence_coords
      boundary.description = 'Burning Man event perimeter boundary'
      boundary.active = true
    end
  end
end