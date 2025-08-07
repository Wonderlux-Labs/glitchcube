// GPS Map Main Initialization
window.GPSMap = window.GPSMap || {};

// Initialize everything when DOM is ready
document.addEventListener('DOMContentLoaded', async function() {
  const statusEl = document.getElementById('status');
  
  try {
    console.log('🔥 Starting GPS Map initialization...');
    
    // Initialize map
    GPSMap.MapSetup.init();
    console.log('✅ Map initialized');
    
    // Initialize control handlers
    GPSMap.Controls.init();
    console.log('✅ Controls initialized');
    
    // Load landmarks
    await GPSMap.API.loadLandmarks();
    console.log('✅ Landmarks loaded');
    
    // Load route history
    await GPSMap.API.loadRouteHistory();
    console.log('✅ Route history loaded');
    
    // Load home location
    await GPSMap.API.loadHomeLocation();
    console.log('✅ Home location loaded');
    
    // Load GIS data (streets, plazas, toilets)
    await GPSMap.API.loadStreets();
    console.log('✅ Streets loaded');
    
    await GPSMap.API.loadPlazas();
    console.log('✅ Plazas loaded');
    
    await GPSMap.API.loadToilets();
    console.log('✅ Toilets loaded');
    
    // Initial location update
    await GPSMap.API.updateLocation();
    console.log('✅ Initial location updated');
    
    statusEl.textContent = 'GPS tracking active!';
    statusEl.className = 'status-display';
    
    // Update location every X seconds
    setInterval(() => {
      GPSMap.API.updateLocation();
    }, window.APP_CONFIG.updateInterval);
    
    console.log('🔥 GPS Map initialization complete!');
    console.log('Tracking via Home Assistant device tracker');
    
  } catch (error) {
    console.error('❌ Initialization failed:', error);
    statusEl.textContent = 'Initialization failed: ' + error.message;
    statusEl.className = 'status-display offline';
  }
});