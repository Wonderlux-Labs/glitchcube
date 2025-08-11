# frozen_string_literal: true

require 'spec_helper'

# Combined location specs that load GIS data once before all tests
RSpec.describe 'Location Models', type: :model do
  # Load GIS data once before all location tests - only if not already loaded
  before(:all) do
    # Check if data is already loaded
    # Cache counts to avoid multiple DB queries
    boundary_count = Boundary.count
    street_count = Street.count
    landmark_count = Landmark.count
    # Check if data is already loaded
    if boundary_count == 0 || street_count == 0 || landmark_count == 0
      puts '🌍 Loading GIS data for location specs...'

      # Clear any partial data
      Boundary.destroy_all
      Street.destroy_all
      Landmark.destroy_all

      # Import fresh data
      Street.import_from_geojson('data/gis/street_lines.geojson')
      Boundary.import_from_geojson('data/gis/city_blocks.geojson', 'city_block')
      Boundary.import_from_geojson('data/gis/trash_fence.geojson', 'fence')
      Landmark.import_from_gis_data('data/gis')

      puts "✅ Loaded #{Street.count} streets, #{Boundary.count} boundaries, #{Landmark.count} landmarks"
    else
      puts "✅ Using existing GIS data: #{Street.count} streets, #{Boundary.count} boundaries, #{Landmark.count} landmarks"
    end
  end

  describe Boundary do
    # Get references to loaded data
    let(:trash_fence) { Boundary.where(boundary_type: 'fence').order(:id).first }
    let(:city_block) { Boundary.where(boundary_type: 'city_block').order(:id).first }

    describe 'validations' do
      it 'requires a name' do
        boundary = Boundary.new(boundary_type: 'test')
        expect(boundary).not_to be_valid
        expect(boundary.errors[:name]).to include("can't be blank")
      end

      it 'requires a boundary_type' do
        boundary = Boundary.new(name: 'Test')
        expect(boundary).not_to be_valid
        expect(boundary.errors[:boundary_type]).to include("can't be blank")
      end

      it 'requires geom' do
        boundary = Boundary.new(name: 'Test', boundary_type: 'test')
        expect(boundary).not_to be_valid
        expect(boundary.errors[:geom]).to include("can't be blank")
      end
    end

    describe 'scopes' do
      describe '.active' do
        it 'returns only active boundaries' do
          expect(Boundary.active).to include(trash_fence, city_block)
          expect(Boundary.active.count).to be > 0
        end
      end

      describe '.by_type' do
        it 'filters boundaries by type' do
          expect(Boundary.by_type('fence')).to include(trash_fence)
          expect(Boundary.by_type('fence')).not_to include(city_block)
          expect(Boundary.by_type('city_block')).to include(city_block)
        end
      end

      describe '.nearest' do
        it 'returns boundaries ordered by distance' do
          # Use trash fence centroid
          result = ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.sanitize_sql_array([
                                                    'SELECT ST_X(ST_Centroid(geom)) as lng, ST_Y(ST_Centroid(geom)) as lat FROM boundaries WHERE id = ?',
                                                    trash_fence.id
                                                  ])
          ).first

          results = Boundary.nearest(lat: result['lat'], lng: result['lng'], limit: 2)

          expect(results.to_a.size).to be <= 2
          expect(results.first.distance_meters).to be_a(Numeric)
        end

        it 'respects the limit' do
          results = Boundary.nearest(lat: 40.78, lng: -119.20, limit: 1)
          expect(results.to_a.size).to eq(1)
        end

        it 'only returns active boundaries' do
          results = Boundary.nearest(lat: 40.78, lng: -119.20, limit: 10)
          expect(results.all?(&:active)).to be true
        end
      end

      describe '.containing_point' do
        it 'returns boundaries that contain the point' do
          # The Man coordinates - should be inside trash fence
          results = Boundary.containing_point(-119.2030, 40.78696)
          expect(results.pluck(:boundary_type)).to include('fence')
        end

        it 'returns empty when point is outside all boundaries' do
          # Point way outside
          results = Boundary.containing_point(-120.0, 41.0)
          expect(results).to be_empty
        end
      end

      describe '.within_meters' do
        it 'returns boundaries within specified distance' do
          # Center camp coordinates with 5km radius should find many boundaries
          results = Boundary.within_meters(-119.2065, 40.7864, 5000)
          expect(results.count).to be > 0
          expect(results.pluck(:boundary_type).uniq).to include('fence')
        end

        it 'excludes boundaries outside radius' do
          # Very small radius from a point far outside
          results = Boundary.within_meters(-120.0, 41.0, 10)
          expect(results).to be_empty
        end
      end
    end

    describe 'instance methods' do
      describe '#contains_point?' do
        it 'returns true when point is inside boundary' do
          # The Man coordinates - should be inside trash fence
          expect(trash_fence.contains_point?(40.78696, -119.2030)).to be true
        end

        it 'returns false when point is outside boundary' do
          # Point clearly outside trash fence
          expect(trash_fence.contains_point?(41.0, -120.0)).to be false
        end

        it 'works with city blocks' do
          # Find the centroid of the city block to ensure we have a point inside it
          result = ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.sanitize_sql_array([
                                                    'SELECT ST_Y(ST_Centroid(geom)) as lat, ST_X(ST_Centroid(geom)) as lng FROM boundaries WHERE id = ?',
                                                    city_block.id
                                                  ])
          ).first

          centroid_lat = result['lat']
          centroid_lng = result['lng']

          # Point at centroid should be inside
          expect(city_block.contains_point?(centroid_lat, centroid_lng)).to be true
          # Point far away should be outside
          expect(city_block.contains_point?(41.0, -120.0)).to be false
        end
      end

      describe '#coordinates' do
        it 'returns the polygon coordinates' do
          coords = trash_fence.coordinates
          expect(coords).to be_an(Array)
          expect(coords.first).to be_an(Array)
          expect(coords.first.first).to be_an(Array)
          expect(coords.first.first.length).to eq(2) # [lng, lat]
        end
      end
    end

    describe 'class methods' do
      describe '.trash_fence' do
        it 'returns the fence boundary' do
          expect(Boundary.trash_fence).to eq(trash_fence)
        end
      end

      describe '.within_fence?' do
        it 'returns true for points inside the trash fence' do
          # The Man - should be inside
          expect(Boundary.within_fence?(40.78696, -119.2030)).to be true
        end

        it 'returns false for points outside the trash fence' do
          expect(Boundary.within_fence?(41.0, -120.0)).to be false
        end
      end
    end

    describe 'PostGIS integration' do
      it 'can perform spatial queries' do
        # Find boundaries that intersect with a line
        line_wkt = 'LINESTRING(-119.21 40.78, -119.20 40.79)'

        results = Boundary.where(
          "ST_Intersects(geom, ST_GeomFromText('#{line_wkt}', 4326))"
        )

        expect(results).to include(trash_fence)
      end

      it 'can calculate boundary area' do
        result = ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
                                                  'SELECT ST_Area(geom::geography) as area FROM boundaries WHERE id = ?',
                                                  trash_fence.id
                                                ])
        ).first

        area = result['area'].to_f
        expect(area).to be > 0 # Trash fence should have substantial area
      end

      it 'can find boundary centroid' do
        result = ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
                                                  'SELECT ST_AsText(ST_Centroid(geom)) as centroid FROM boundaries WHERE id = ?',
                                                  city_block.id
                                                ])
        ).first

        expect(result['centroid']).to match(/POINT/)
      end
    end
  end

  describe Street do
    # Get references to seeded streets
    let(:esplanade) { Street.where(name: 'Esplanade').order(:id).first }
    let(:three_oclock) { Street.where(name: '3:00').order(:id).first }
    let(:arc_street) { Street.arc_streets.order(:id).first }
    let(:radial_street) { Street.radial_streets.order(:id).first }

    describe 'validations' do
      it 'requires a name' do
        street = Street.new(street_type: 'arc', width: 30)
        expect(street).not_to be_valid
        expect(street.errors[:name]).to include("can't be blank")
      end

      it 'requires a street_type' do
        street = Street.new(name: 'Test', width: 30)
        expect(street).not_to be_valid
        expect(street.errors[:street_type]).to include("can't be blank")
      end

      it 'requires width to be positive' do
        street = Street.new(name: 'Test', street_type: 'arc', width: 0)
        expect(street).not_to be_valid
        expect(street.errors[:width]).to include('must be greater than 0')
      end

      it 'requires geom' do
        street = Street.new(name: 'Test', street_type: 'arc', width: 30)
        expect(street).not_to be_valid
        expect(street.errors[:geom]).to include("can't be blank")
      end
    end

    describe 'scopes' do
      describe '.active' do
        it 'returns only active streets' do
          expect(Street.active).to include(esplanade)
          expect(Street.active).to include(three_oclock)
          expect(Street.active.count).to be > 0
        end
      end

      describe '.by_type' do
        it 'filters streets by type' do
          expect(Street.by_type('arc')).to include(esplanade)
          expect(Street.by_type('arc')).not_to include(three_oclock)
          expect(Street.by_type('radial')).to include(three_oclock)
        end
      end

      describe '.radial_streets' do
        it 'returns only radial streets' do
          expect(Street.radial_streets).to include(three_oclock)
          expect(Street.radial_streets).not_to include(esplanade)
        end
      end

      describe '.arc_streets' do
        it 'returns only arc streets' do
          expect(Street.arc_streets).to include(esplanade)
          expect(Street.arc_streets).not_to include(three_oclock)
        end
      end

      describe '.nearest' do
        it 'returns streets ordered by distance' do
          test_coords = esplanade.start_coordinates || esplanade.center_point

          results = Street.nearest(lat: test_coords[1], lng: test_coords[0], limit: 2)

          expect(results.first).to eq(esplanade)
          expect(results.first.distance_meters).to be_a(Numeric)
          expect(results.first.distance_meters).to be < 100 # Should be very close
        end

        it 'respects the limit' do
          results = Street.nearest(lat: 40.78, lng: -119.20, limit: 1)
          expect(results.to_a.size).to eq(1)
        end
      end

      describe '.within_meters' do
        it 'returns streets within specified distance' do
          test_coords = esplanade.start_coordinates || esplanade.center_point

          results = Street.within_meters(test_coords[0], test_coords[1], 500)
          expect(results).to include(esplanade)
        end

        it 'excludes streets outside radius' do
          test_coords = esplanade.start_coordinates || esplanade.center_point

          # Very small radius at a point far away
          results = Street.within_meters(test_coords[0] + 1, test_coords[1] + 1, 10)
          expect(results).to be_empty
        end
      end
    end

    describe 'instance methods' do
      describe '#radial?' do
        it 'returns true for radial streets' do
          expect(three_oclock.radial?).to be true
          expect(esplanade.radial?).to be false
        end
      end

      describe '#arc?' do
        it 'returns true for arc streets' do
          expect(esplanade.arc?).to be true
          expect(three_oclock.arc?).to be false
        end
      end

      describe '#coordinates' do
        it 'returns the linestring coordinates' do
          coords = three_oclock.coordinates
          expect(coords).to be_an(Array)
          expect(coords.length).to be >= 2 # At least two points for a line
          expect(coords.first).to be_an(Array)
          expect(coords.first.length).to eq(2) # [lng, lat]
        end
      end

      describe '#start_coordinates' do
        it 'returns the first coordinate pair' do
          start_coords = three_oclock.start_coordinates
          expect(start_coords).to be_an(Array)
          expect(start_coords.length).to eq(2)
          expect(start_coords[0]).to be_a(Numeric) # longitude
          expect(start_coords[1]).to be_a(Numeric) # latitude
        end
      end

      describe '#end_coordinates' do
        it 'returns the last coordinate pair' do
          end_coords = three_oclock.end_coordinates
          expect(end_coords).to be_an(Array)
          expect(end_coords.length).to eq(2)
          expect(end_coords[0]).to be_a(Numeric) # longitude
          expect(end_coords[1]).to be_a(Numeric) # latitude
        end
      end

      describe '#center_point' do
        it 'calculates the center point of the street' do
          center = three_oclock.center_point
          expect(center).to be_an(Array)
          expect(center.length).to eq(2)

          # Center should be within the bounding box of start and end
          start_coords = three_oclock.start_coordinates
          end_coords = three_oclock.end_coordinates

          min_lng = [start_coords[0], end_coords[0]].min
          max_lng = [start_coords[0], end_coords[0]].max
          min_lat = [start_coords[1], end_coords[1]].min
          max_lat = [start_coords[1], end_coords[1]].max

          # Allow some tolerance for curved streets
          tolerance = 0.01
          expect(center[0]).to be_between(min_lng - tolerance, max_lng + tolerance)
          expect(center[1]).to be_between(min_lat - tolerance, max_lat + tolerance)
        end
      end
    end

    describe 'PostGIS integration' do
      it 'can find streets that intersect with a point buffer' do
        test_coords = esplanade.start_coordinates || esplanade.center_point

        # Find streets within 100m of the point
        results = Street.where(
          'ST_DWithin(geom::geography, ST_Point(?, ?)::geography, ?)',
          test_coords[0], test_coords[1], 100
        )

        expect(results).to include(esplanade)
      end

      it 'can calculate street length' do
        result = ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
                                                  'SELECT ST_Length(geom::geography) as length FROM streets WHERE id = ?',
                                                  esplanade.id
                                                ])
        ).first

        length = result['length'].to_f
        expect(length).to be > 0 # Should have measurable length
      end

      it 'can find nearest point on street to a location' do
        test_coords = esplanade.start_coordinates || esplanade.center_point

        result = ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
                                                  'SELECT ST_AsText(ST_ClosestPoint(geom, ST_SetSRID(ST_Point(?, ?), 4326))) as closest FROM streets WHERE id = ?',
                                                  test_coords[0] + 0.001, test_coords[1] + 0.001, esplanade.id
                                                ])
        ).first

        expect(result['closest']).to match(/POINT/)
      end
    end
  end

  describe Landmark do
    # Get references to seeded landmarks
    let(:center_camp) { Landmark.find_by(name: 'Center Camp') }
    let(:temple) { Landmark.find_by(name: 'The Temple') }
    let(:the_man) { Landmark.find_by(name: 'The Man') }

    describe 'validations' do
      it 'requires a name' do
        landmark = Landmark.new(latitude: 40.78, longitude: -119.20, landmark_type: 'test')
        expect(landmark).not_to be_valid
        expect(landmark.errors[:name]).to include("can't be blank")
      end

      it 'requires latitude and longitude' do
        landmark = Landmark.new(name: 'Test', landmark_type: 'test')
        expect(landmark).not_to be_valid
        expect(landmark.errors[:latitude]).to include("can't be blank")
        expect(landmark.errors[:longitude]).to include("can't be blank")
      end

      it 'requires landmark_type' do
        landmark = Landmark.new(name: 'Test', latitude: 40.78, longitude: -119.20)
        expect(landmark).not_to be_valid
        expect(landmark.errors[:landmark_type]).to include("can't be blank")
      end
    end

    describe 'scopes' do
      describe '.active' do
        it 'returns only active landmarks' do
          expect(Landmark.active).to include(center_camp, temple)
          expect(Landmark.active.count).to be > 0
        end
      end

      describe '.by_type' do
        it 'filters landmarks by type' do
          # The Man is type 'center', Temple is 'sacred', Center Camp is 'gathering'
          expect(Landmark.by_type('center')).to include(the_man) if the_man
          expect(Landmark.by_type('sacred')).to include(temple) if temple
          expect(Landmark.by_type('gathering')).to include(center_camp) if center_camp
        end
      end

      describe '.nearest' do
        it 'returns landmarks ordered by distance' do
          test_landmark = center_camp || Landmark.first

          results = Landmark.nearest(lat: test_landmark.latitude, lng: test_landmark.longitude, limit: 2)

          expect(results.first).to eq(test_landmark)
          expect(results.first.distance_meters).to be < 10 # Should be very close to itself
        end

        it 'respects the limit' do
          test_landmark = center_camp || Landmark.first

          results = Landmark.nearest(lat: test_landmark.latitude, lng: test_landmark.longitude, limit: 1)
          expect(results.to_a.size).to eq(1)
        end
      end

      describe '.within_meters' do
        it 'returns landmarks within specified radius' do
          test_landmark = center_camp || Landmark.first

          # Search from test landmark location with 1000m radius
          results = Landmark.within_meters(test_landmark.longitude, test_landmark.latitude, 1000)
          expect(results).to include(test_landmark)
          expect(results.count).to be >= 1
        end

        it 'excludes landmarks outside radius' do
          test_landmark = center_camp || Landmark.first

          # Very small radius from a far point
          results = Landmark.within_meters(test_landmark.longitude + 1, test_landmark.latitude + 1, 10)
          expect(results).not_to include(test_landmark)
        end
      end
    end

    describe 'instance methods' do
      describe '#coordinates' do
        it 'returns lat/lng as array' do
          test_landmark = center_camp || Landmark.first

          coords = test_landmark.coordinates
          expect(coords).to be_an(Array)
          expect(coords.length).to eq(2)
          expect(coords[0]).to eq(test_landmark.latitude.to_f)
          expect(coords[1]).to eq(test_landmark.longitude.to_f)
        end
      end

      describe '#distance_from' do
        it 'calculates distance from a point' do
          test_landmark = center_camp || Landmark.first

          # Test distance to a nearby point
          distance = test_landmark.distance_from(
            test_landmark.latitude + 0.001,
            test_landmark.longitude + 0.001
          )
          expect(distance).to be_a(Float)
          expect(distance).to be > 0
          expect(distance).to be < 1 # Should be less than 1 mile
        end
      end

      describe '#within_radius?' do
        it 'returns true if point is within radius' do
          test_landmark = center_camp || Landmark.first

          # Very close point (same location)
          expect(test_landmark.within_radius?(test_landmark.latitude, test_landmark.longitude, 0.1)).to be true
        end

        it 'returns false if point is outside radius' do
          test_landmark = center_camp || Landmark.first

          # Far point
          expect(test_landmark.within_radius?(test_landmark.latitude + 1, test_landmark.longitude + 1, 0.001)).to be false
        end
      end
    end

    describe 'PostGIS integration' do
      it 'creates location geometry from lat/lng on save' do
        landmark = Landmark.create!(
          name: 'Test Point',
          landmark_type: 'test',
          latitude: 40.7864,
          longitude: -119.2065
        )

        # Check that location was set
        result = ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
                                                  'SELECT ST_AsText(location) as wkt FROM landmarks WHERE id = ?',
                                                  landmark.id
                                                ])
        ).first

        expect(result['wkt']).to match(/POINT\(-119\.2065 40\.7864\)/)
      end

      it 'updates location when coordinates change' do
        landmark = Landmark.create!(
          name: 'Moving Point',
          landmark_type: 'test',
          latitude: 40.7864,
          longitude: -119.2065
        )

        landmark.update!(latitude: 40.7900, longitude: -119.2100)

        result = ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
                                                  'SELECT ST_AsText(location) as wkt FROM landmarks WHERE id = ?',
                                                  landmark.id
                                                ])
        ).first

        expect(result['wkt']).to match(/POINT\(-119\.21 40\.79\)/)
      end
    end
  end
end
