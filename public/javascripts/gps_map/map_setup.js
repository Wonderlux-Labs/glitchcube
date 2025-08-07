// GPS Map Setup and Initialization
window.GPSMap = window.GPSMap || {};

GPSMap.MapSetup = {
  map: null,
  layers: {},
  
  // Initialize the Leaflet map
  init: function() {
    // Initialize map centered on Black Rock City
    const goldenSpike = [
      window.APP_CONFIG.goldenSpike.lat, 
      window.APP_CONFIG.goldenSpike.lng
    ];
    
    this.map = L.map('map').setView(goldenSpike, 14);
    
    // Add OpenStreetMap tiles
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors | Burning Man 2025 | Glitch Cube GPS'
    }).addTo(this.map);
    
    // Add map controls
    this.addControls();
    
    // Create layer groups
    this.createLayerGroups();
    
    // Add trash fence perimeter
    this.addTrashFence(goldenSpike);
    
    return this.map;
  },
  
  // Add map controls
  addControls: function() {
    // Add scale control
    L.control.scale({
      imperial: true,
      metric: false,
      position: 'bottomright'
    }).addTo(this.map);
    
    // Add compass/north arrow
    const compass = L.control({ position: 'topright' });
    compass.onAdd = function() {
      const div = L.DomUtil.create('div', 'compass-control');
      div.innerHTML = `↑<br><span style="font-size: 12px;">N</span>`;
      div.title = 'North (Click to reset view)';
      
      // Click to reset view to BRC center
      div.onclick = function() {
        GPSMap.MapSetup.centerOnGoldenSpike();
      };
      
      return div;
    };
    compass.addTo(this.map);
  },
  
  // Create layer groups for organization
  createLayerGroups: function() {
    this.layers.streets = L.layerGroup().addTo(this.map);
    this.layers.landmarks = L.layerGroup().addTo(this.map);
    this.layers.proximity = L.layerGroup().addTo(this.map);
    this.layers.trashFence = L.layerGroup();
    this.layers.plazas = L.layerGroup();
  },
  
  // Add trash fence perimeter
  addTrashFence: function(center) {
    const trashFenceRadius = 5280; // ~1 mile radius in feet
    
    L.circle(center, {
      color: '#666',
      fillColor: 'transparent',
      fillOpacity: 0,
      radius: trashFenceRadius,
      weight: 2,
      dashArray: '10, 5'
    }).addTo(this.map).bindPopup('🚫 Trash Fence Perimeter');
  },
  
  // Center map on Golden Spike
  centerOnGoldenSpike: function() {
    const goldenSpike = [
      window.APP_CONFIG.goldenSpike.lat, 
      window.APP_CONFIG.goldenSpike.lng
    ];
    this.map.setView(goldenSpike, 14);
  },
  
  // Center map on specific coordinates
  centerOnCoordinates: function(lat, lng, zoom) {
    this.map.setView([lat, lng], zoom || 15);
  },
  
  // Set map visual mode
  setMapMode: function(mode) {
    const mapElement = document.getElementById('map');
    
    // Remove existing mode classes
    mapElement.classList.remove('temple-mode', 'man-mode', 'emergency-mode', 'service-mode', 'landmark-mode');
    
    // Apply new mode
    if (mode !== 'normal') {
      mapElement.classList.add(`${mode}-mode`);
    }
    
    // Update map tile opacity based on mode
    this.map.eachLayer(layer => {
      if (layer instanceof L.TileLayer) {
        switch (mode) {
          case 'temple':
            layer.setOpacity(0.3);
            break;
          case 'emergency':
            layer.setOpacity(0.7);
            break;
          default:
            layer.setOpacity(1.0);
        }
      }
    });
  }
};