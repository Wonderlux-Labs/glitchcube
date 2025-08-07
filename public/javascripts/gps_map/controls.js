// GPS Map Controls Handler
window.GPSMap = window.GPSMap || {};

GPSMap.Controls = {
  // Control states
  showRoute: false,
  showPlazas: false,
  showPortos: false,
  showMedical: false,
  showLandmarks: false,
  
  // Initialize control handlers
  init: function() {
    // Route toggle (default active)
    document.getElementById('routeToggle').addEventListener('click', () => {
      this.showRoute = !this.showRoute;
      const btn = document.getElementById('routeToggle');
      const showing = GPSMap.Markers.toggleRouteHistory();
      btn.classList.toggle('active', showing);
      btn.textContent = showing ? 'HIDE route' : 'SHOW route';
    });
    
    // Plaza toggle
    document.getElementById('plazaToggle').addEventListener('click', () => {
      this.showPlazas = !this.showPlazas;
      const btn = document.getElementById('plazaToggle');
      btn.classList.toggle('active', this.showPlazas);
      btn.textContent = this.showPlazas ? 'HIDE plazas' : 'SHOW plazas';
      
      if (this.showPlazas) {
        GPSMap.MapSetup.layers.plazas.addTo(GPSMap.MapSetup.map);
      } else {
        GPSMap.MapSetup.map.removeLayer(GPSMap.MapSetup.layers.plazas);
      }
    });
    
    // Medical toggle
    document.getElementById('medicalToggle').addEventListener('click', () => {
      this.showMedical = !this.showMedical;
      const btn = document.getElementById('medicalToggle');
      btn.classList.toggle('active', this.showMedical);
      btn.textContent = this.showMedical ? 'HIDE medical' : 'SHOW medical';
      this.updateLandmarkVisibility();
    });
    
    // Landmarks toggle
    document.getElementById('landmarksToggle').addEventListener('click', () => {
      this.showLandmarks = !this.showLandmarks;
      const btn = document.getElementById('landmarksToggle');
      btn.classList.toggle('active', this.showLandmarks);
      btn.textContent = this.showLandmarks ? 'HIDE landmarks' : 'SHOW landmarks';
      this.updateLandmarkVisibility();
    });
    
    // Portos toggle
    document.getElementById('portosToggle').addEventListener('click', () => {
      this.showPortos = !this.showPortos;
      const btn = document.getElementById('portosToggle');
      btn.classList.toggle('active', this.showPortos);
      btn.textContent = this.showPortos ? 'HIDE portos' : 'SHOW portos';
      this.updateLandmarkVisibility();
    });
    
    // Center map button
    document.getElementById('centerToggle').addEventListener('click', () => {
      GPSMap.Markers.centerOnCube();
    });
    
    // Route is hidden by default, user can click to show
  },
  
  // Update landmark visibility based on toggle states
  updateLandmarkVisibility: function() {
    GPSMap.Landmarks.updateLandmarkVisibility(
      this.showPortos,
      this.showMedical,
      this.showLandmarks
    );
  }
};