#!/usr/bin/env python3
import json

# Load and analyze the street_lines.geojson file
with open('street_lines.geojson', 'r') as f:
    data = json.load(f)

print("=== GeoJSON Structure Analysis ===")
print(f"Type: {data['type']}")
print(f"Number of features: {len(data['features'])}")

# Examine first feature
first_feature = data['features'][0]
print(f"\nFirst feature type: {first_feature['type']}")
print(f"Geometry type: {first_feature['geometry']['type']}")
print(f"Properties: {first_feature['properties']}")

# Examine coordinate system
coords = first_feature['geometry']['coordinates']
print(f"\nFirst coordinate pair: {coords[0]}")
print(f"Coordinate range sample:")
print(f"  X (longitude): {coords[0][0]} to {coords[-1][0]}")
print(f"  Y (latitude): {coords[0][1]} to {coords[-1][1]}")

# Check if there's CRS information
if 'crs' in data:
    print(f"\nCRS: {data['crs']}")
else:
    print("\nNo CRS specified (likely WGS84)")

# Sample a few features to understand the street naming
print(f"\nSample street names:")
for i, feature in enumerate(data['features'][:10]):
    props = feature['properties']
    name = props.get('name', 'Unnamed')
    fid = props.get('FID', 'No FID')
    print(f"  {i+1}. FID: {fid}, Name: {name}")

