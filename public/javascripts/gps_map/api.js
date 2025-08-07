// GPS Map API Calls
window.GPSMap = window.GPSMap || {};

GPSMap.API = {
  // Update location from API
  updateLocation: async function() {
    const statusEl = document.getElementById('status');
    
    try {
      const response = await fetch(window.APP_CONFIG.api.locationEndpoint);
      const data = await response.json();
      
      if (data.lat && data.lng) {
        // Update cube marker
        GPSMap.Markers.updateCubeMarker(data.lat, data.lng, data.address);
        
        // Update info panels
        this.updateInfoPanels(data);
        
        // Update landmark proximity
        GPSMap.Landmarks.updateLandmarkProximity({ lat: data.lat, lng: data.lng });
        
        // Check for nearby landmarks
        const nearbyLandmarks = GPSMap.Landmarks.getNearbyLandmarks(data.lat, data.lng);
        this.updateProximityAlert(nearbyLandmarks);
        
        // Add to route history
        GPSMap.Markers.addToRouteHistory(data.lat, data.lng, data.timestamp, data.address);
        
        statusEl.textContent = `Last updated: ${new Date(data.timestamp).toLocaleTimeString()}`;
        statusEl.className = 'status-display';
      } else {
        throw new Error('Invalid location data');
      }
    } catch (error) {
      console.error('Error fetching location:', error);
      statusEl.textContent = 'Connection lost - retrying...';
      statusEl.className = 'status-display offline';
    }
  },
  
  // Update info panels with location data
  updateInfoPanels: function(data) {
    const addressBar = document.getElementById('addressBar');
    const sectionBar = document.getElementById('sectionBar');
    const distanceBar = document.getElementById('distanceBar');
    const coordinatesEl = document.getElementById('coordinates');
    const simModeIndicator = document.getElementById('simModeIndicator');
    
    // Update address
    let addressStr = '';
    if (data.landmark_name) {
      addressStr = data.landmark_name;
    } else if (data.address) {
      addressStr = data.address;
    }
    addressBar.textContent = addressStr;
    
    // Update section and coordinates
    sectionBar.textContent = data.section || '';
    coordinatesEl.textContent = `${data.lat?.toFixed(6) ?? ''}, ${data.lng?.toFixed(6) ?? ''}`;
    distanceBar.textContent = data.distance_from_man || '';
    
    // Show simulation mode indicator
    if (data.source === 'simulation') {
      simModeIndicator.textContent = 'SIMULATION MODE';
    } else {
      simModeIndicator.textContent = '';
    }
  },
  
  // Update proximity alert
  updateProximityAlert: function(nearbyLandmarks) {
    const existingAlert = document.getElementById('proximity-alert');
    if (existingAlert) existingAlert.remove();
    
    if (nearbyLandmarks.length > 0) {
      const nearest = nearbyLandmarks[0];
      const distance = Math.round(GPSMap.Utils.haversineDistance(
        GPSMap.Markers.cubeMarker.getLatLng().lat,
        GPSMap.Markers.cubeMarker.getLatLng().lng,
        nearest.lat, nearest.lng
      ));
      
      const alertEl = document.createElement('div');
      alertEl.id = 'proximity-alert';
      alertEl.textContent = `⚠️ Near ${nearest.name} (${distance}m)`;
      alertEl.style.cssText = 'color: #39ff14; font-size: 12px; margin-top: 5px; background: rgba(57, 255, 20, 0.1); padding: 3px; border-radius: 3px;';
      document.getElementById('addressBar').parentNode.appendChild(alertEl);
    }
  },
  
  // Load route history
  loadRouteHistory: async function() {
    try {
      const response = await fetch(window.APP_CONFIG.api.historyEndpoint);
      const data = await response.json();
      
      if (data.history && data.history.length > 0) {
        GPSMap.Markers.routeHistory = data.history.map(point => ({
          lat: point.lat,
          lng: point.lng,
          timestamp: point.timestamp,
          address: point.address
        }));
        
        console.log(`Loaded ${GPSMap.Markers.routeHistory.length} route points`);
      }
    } catch (error) {
      console.error('Error loading route history:', error);
    }
  },
  
  // Load landmarks
  loadLandmarks: async function() {
    try {
      const response = await fetch(window.APP_CONFIG.api.landmarksEndpoint);
      const data = await response.json();
      
      if (data.landmarks && data.landmarks.length > 0) {
        GPSMap.Landmarks.loadLandmarks(data.landmarks);
        console.log(`✅ Loaded ${data.landmarks.length} landmarks from database`);
      } else {
        console.warn('No landmarks loaded from database');
      }
    } catch (error) {
      console.error('Error loading landmarks:', error);
    }
  },
  
  // Load home location
  loadHomeLocation: async function() {
    try {
      const response = await fetch(window.APP_CONFIG.api.homeEndpoint);
      const homeData = await response.json();
      
      if (homeData.lat && homeData.lng) {
        GPSMap.Markers.addHomeMarker(homeData.lat, homeData.lng, homeData.address);
      }
    } catch (error) {
      console.error('Error loading home location:', error);
    }
  },
  
  // Load streets from GIS API
  loadStreets: async function() {
    try {
      const response = await fetch(window.APP_CONFIG.api.streetsEndpoint);
      const data = await response.json();
      
      if (data.streets && data.streets.length > 0) {
        // Add streets to the map
        data.streets.forEach(street => {
          if (street.geometry && street.geometry.coordinates) {
            const coords = street.geometry.coordinates.map(coord => [coord[1], coord[0]]);
            L.polyline(coords, {
              color: '#8B4513',
              weight: 2,
              opacity: 0.6
            }).addTo(GPSMap.MapSetup.layers.streets)
              .bindPopup(street.properties?.name || 'Street');
          }
        });
        console.log(`Loaded ${data.streets.length} streets`);
      }
    } catch (error) {
      console.error('Error loading streets:', error);
    }
  },
  
  // Load plazas from GIS API
  loadPlazas: async function() {
    try {
      const response = await fetch(window.APP_CONFIG.api.plazasEndpoint);
      const data = await response.json();
      
      if (data.plazas && data.plazas.length > 0) {
        // Add plazas to the map
        data.plazas.forEach(plaza => {
          if (plaza.geometry && plaza.geometry.coordinates) {
            const coords = plaza.geometry.coordinates[0].map(coord => [coord[1], coord[0]]);
            L.polygon(coords, {
              color: '#FF6B6B',
              fillColor: '#FF6B6B',
              fillOpacity: 0.3,
              weight: 2
            }).addTo(GPSMap.MapSetup.layers.plazas)
              .bindPopup(plaza.properties?.name || 'Plaza');
          }
        });
        console.log(`Loaded ${data.plazas.length} plazas`);
      }
    } catch (error) {
      console.error('Error loading plazas:', error);
    }
  },
  
  // Load toilets from GIS API
  loadToilets: async function() {
    try {
      const response = await fetch(window.APP_CONFIG.api.toiletsEndpoint);
      const data = await response.json();
      
      if (data.toilets && data.toilets.length > 0) {
        // Add toilet markers to landmarks layer
        data.toilets.forEach(toilet => {
          if (toilet.geometry && toilet.geometry.coordinates) {
            const lat = toilet.geometry.coordinates[1];
            const lng = toilet.geometry.coordinates[0];
            
            L.marker([lat, lng], {
              icon: L.divIcon({
                className: 'toilet-marker',
                html: '🚽',
                iconSize: [20, 20]
              })
            }).addTo(GPSMap.MapSetup.layers.landmarks)
              .bindPopup(toilet.properties?.name || 'Portable Toilet');
          }
        });
        console.log(`Loaded ${data.toilets.length} toilets`);
      }
    } catch (error) {
      console.error('Error loading toilets:', error);
    }
  }
};