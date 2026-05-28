// ── Utility ───────────────────────────────────────────────────────────────────
function clampPercent(value, maxBase) {
  return Math.max(0, Math.min(100, (Number(value) / Number(maxBase)) * 100));
}

// ── State ────────────────────────────────────────────────────────────────────
let fieldMap, editableLayers, drawControl, activeDrawPolygon;
let satelliteLayer, streetLayer;
let currentBaseLayer = 'satellite';
let heatTintEnabled  = true;
let coordMarker      = null;   // marker dropped by manual lat/lon input

const panaboBounds    = L.latLngBounds([7.20, 125.50], [7.41, 125.72]);
const selectedStyle   = { color:'#00e18c', weight:3, fillColor:'#22c97f', fillOpacity:0.28 };
const unselectedStyle = { color:'#4ce09e', weight:2, fillColor:'#27b16f', fillOpacity:0.2  };

// Keep the map north-up and flat. This prevents dizzy rotation/tilt on touch devices.
function enforceNorthUpMap() {
  if (!fieldMap) return;
  ['zoomend', 'moveend', 'dragend'].forEach(evt => fieldMap.on(evt, () => {
    if (typeof fieldMap.setBearing === 'function') fieldMap.setBearing(0);
    if (typeof fieldMap.setPitch === 'function') fieldMap.setPitch(0);
  }));
}

// ── Map initialisation ────────────────────────────────────────────────────────
function initMap(lat=7.2915, lon=125.6255) {
  if (typeof L === 'undefined' || fieldMap) return;

  fieldMap = L.map('fieldMap', {
    zoomControl: false,
    attributionControl: true,
    maxBounds: panaboBounds,
    maxBoundsViscosity: 1.0,
    rotate: false,
    touchRotate: false,
    bearing: 0,
    pitch: 0,
  }).setView([lat, lon], 13);
  fieldMap.setMinZoom(12);
  fieldMap.fitBounds(panaboBounds);
  enforceNorthUpMap();

  satelliteLayer = L.tileLayer(
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    { maxZoom:19, attribution:'Tiles &copy; Esri, Maxar, Earthstar Geographics' });
  streetLayer = L.tileLayer(
    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    { maxZoom:19, attribution:'&copy; OpenStreetMap contributors' });

  satelliteLayer.addTo(fieldMap);
  setupMapToggles();

  editableLayers = new L.FeatureGroup().addTo(fieldMap);
  drawControl = new L.Control.Draw({
    draw:{ polygon:{allowIntersection:false,showArea:true},
           rectangle:false, circle:false, marker:false, polyline:false, circlemarker:false },
    edit:{ featureGroup:editableLayers, edit:true, remove:true },
  });
  fieldMap.addControl(drawControl);

  // Draw events
  fieldMap.on(L.Draw.Event.CREATED, (e) => {
    clearCoordMarker();
    editableLayers.clearLayers();
    activeDrawPolygon = e.layer;
    activeDrawPolygon.setStyle(selectedStyle);
    attachPolygonClick(activeDrawPolygon);
    editableLayers.addLayer(activeDrawPolygon);
    updateTopBadges(null, getPolygonPoints());
  });
  fieldMap.on(L.Draw.Event.EDITED, (e) => {
    e.layers.eachLayer(layer => {
      activeDrawPolygon = layer;
      activeDrawPolygon.setStyle(selectedStyle);
      attachPolygonClick(activeDrawPolygon);
    });
    updateTopBadges(null, getPolygonPoints());
  });
  fieldMap.on(L.Draw.Event.DELETED, () => {
    activeDrawPolygon = null;
    updateTopBadges();
  });

  // Toolbar buttons
  document.getElementById('startDrawBtn')?.addEventListener('click', () =>
    new L.Draw.Polygon(fieldMap, drawControl.options.draw.polygon).enable());

  document.getElementById('clearDrawBtn')?.addEventListener('click', () => {
    editableLayers.clearLayers();
    clearCoordMarker();
    activeDrawPolygon = null;
    updateTopBadges();
    clearCoordInputs();
  });

  document.getElementById('analyzeAreaBtn')?.addEventListener('click', async () => {
    if (!activeDrawPolygon) {
      alert('Draw a polygon on the map first, then click Analyze Selection.');
      return;
    }
    await runAnalysis({ polygon: getPolygonPoints() });
  });

  // Manual coordinate input
  document.getElementById('analyzeCoordBtn')?.addEventListener('click', async () => {
    const latVal = parseFloat(document.getElementById('manualLat').value);
    const lonVal = parseFloat(document.getElementById('manualLon').value);

    if (isNaN(latVal) || isNaN(lonVal)) {
      alert('Please enter valid latitude and longitude values.');
      return;
    }
    if (latVal < 7.20 || latVal > 7.41 || lonVal < 125.50 || lonVal > 125.72) {
      alert('Coordinates are outside Panabo City bounds.\nLat: 7.20–7.41 | Lon: 125.50–125.72');
      return;
    }

    // Clear any polygon and drop a marker
    editableLayers.clearLayers();
    activeDrawPolygon = null;
    clearCoordMarker();

    coordMarker = L.marker([latVal, lonVal])
      .addTo(editableLayers)
      .bindPopup(`📍 Lat: ${latVal.toFixed(4)}, Lon: ${lonVal.toFixed(4)}`)
      .openPopup();

    fieldMap.setView([latVal, lonVal], 15);
    updateTopBadges(null, []);

    await runAnalysis({ lat: latVal, lon: lonVal });
  });
}

// ── Map helpers ───────────────────────────────────────────────────────────────
function clearCoordMarker() {
  if (coordMarker) { editableLayers.removeLayer(coordMarker); coordMarker = null; }
}
function clearCoordInputs() {
  const la = document.getElementById('manualLat');
  const lo = document.getElementById('manualLon');
  if (la) la.value = '';
  if (lo) lo.value = '';
}

function setBaseLayer(name) {
  if (!fieldMap) return;
  if (name === 'street') {
    fieldMap.hasLayer(satelliteLayer) && fieldMap.removeLayer(satelliteLayer);
    !fieldMap.hasLayer(streetLayer)   && fieldMap.addLayer(streetLayer);
    currentBaseLayer = 'street';
  } else {
    fieldMap.hasLayer(streetLayer)    && fieldMap.removeLayer(streetLayer);
    !fieldMap.hasLayer(satelliteLayer)&& fieldMap.addLayer(satelliteLayer);
    currentBaseLayer = 'satellite';
  }
  document.getElementById('satelliteToggleBtn')?.classList.toggle('active', currentBaseLayer==='satellite');
  document.getElementById('streetToggleBtn')?.classList.toggle('active',   currentBaseLayer==='street');
}

function setHeatTint(enabled) {
  heatTintEnabled = enabled;
  document.querySelector('.map-card')?.classList.toggle('heat-off', !enabled);
  const btn = document.getElementById('heatToggleBtn');
  if (btn) { btn.textContent = enabled ? 'Heat Tint: On' : 'Heat Tint: Off'; btn.classList.toggle('active', enabled); }
}

function setupMapToggles() {
  document.getElementById('satelliteToggleBtn')?.addEventListener('click', () => setBaseLayer('satellite'));
  document.getElementById('streetToggleBtn')?.addEventListener('click',    () => setBaseLayer('street'));
  document.getElementById('heatToggleBtn')?.addEventListener('click',      () => setHeatTint(!heatTintEnabled));
  setBaseLayer(currentBaseLayer);
  setHeatTint(heatTintEnabled);
}

function attachPolygonClick(layer) {
  layer.off('click');
  layer.on('click', () => {
    editableLayers.eachLayer(c => typeof c.setStyle==='function' &&
      c.setStyle(c===layer ? selectedStyle : unselectedStyle));
    activeDrawPolygon = layer;
    updateTopBadges(null, getPolygonPoints());
  });
}

function updateMap(lat, lon) {
  if (!fieldMap) initMap(lat, lon);
  fieldMap.setView([lat, lon], 14);
}

function getPolygonPoints() {
  if (!activeDrawPolygon || !activeDrawPolygon.getLatLngs) return [];
  return activeDrawPolygon.getLatLngs()[0].map(pt => ({ lat:pt.lat, lng:pt.lng }));
}

function getPolygonAreaHa() {
  if (!activeDrawPolygon || !L.GeometryUtil) return 0;
  const ll = activeDrawPolygon.getLatLngs?.()?.[0];
  return (ll && ll.length >= 3) ? L.GeometryUtil.geodesicArea(ll) / 10000 : 0;
}

// ── UI helpers ────────────────────────────────────────────────────────────────
function updateSoilDonut(phValue) {
  const donut  = document.getElementById('phDonut');
  const center = document.getElementById('phDonutValue');
  if (!donut || !center) return;
  const pct = clampPercent(Number(phValue), 14);
  donut.style.background =
    `conic-gradient(#1f9c65 0 ${pct*0.5}%, #8c6b5f ${pct*0.5}% ${pct*0.8}%, #9c7d12 ${pct*0.8}% 100%)`;
  center.textContent = Number(phValue).toFixed(1);
}

function fillLiveObservations(data) {
  document.getElementById('liveRainfall').textContent = `${Number(data.rainfall_mm).toFixed(1)} mm`;
  document.getElementById('surfaceTemp').textContent  = `${Number(data.surface_temp_c).toFixed(1)} °C`;
  document.getElementById('liveHumidity').textContent = `${Math.round(data.live_humidity)} %`;
  document.getElementById('windSpeed').textContent    = `${Number(data.wind_speed_ms).toFixed(1)} m/s`;
  document.getElementById('cloudCover').textContent   = `${Math.round(data.cloud_cover_pct)} %`;
  document.getElementById('liveNdvi').textContent     = Number(data.ndvi).toFixed(3);
}

function renderRecommendation(data) {
  const el = id => document.getElementById(id);
  if (!el('cropName')) return;

  el('recommendationHeader').textContent = data.recommendation_title || 'RECOMMENDED CROP MATCH';
  el('cropName').textContent             = String(data.predicted_crop || '--').toUpperCase();
  el('landStatus').textContent           = data.land_status || '--';
  if (el('recommendationLine')) el('recommendationLine').textContent = '';
  if (el('landUseList'))        el('landUseList').innerHTML          = '';
  if (el('altCropsList'))       el('altCropsList').innerHTML         = '';
  if (el('suitabilityNote'))  { el('suitabilityNote').textContent = ''; el('suitabilityNote').style.display='none'; }

  if (data.is_crop_recommended) {
    const compat = Number(data.crop_compatibility_pct||0).toFixed(1);
    el('compatibilityBadge').textContent   = `${compat}% Compatibility`;
    el('compatibilityBadge').style.display = 'inline-block';

    const sb = el('suitabilityBadge');
    if (sb) {
      sb.textContent   = data.suitability_level || '';
      sb.style.display = 'inline-block';
      sb.className     = 'suitability-badge ' +
        (data.suitability_level==='HIGHLY SUITABLE' ? 'high' :
         data.suitability_level==='MODERATELY SUITABLE' ? 'moderate' : 'low');
    }

    if (el('recommendationLine')) el('recommendationLine').textContent = data.crop_label || '';
    if (el('suitabilityNote') && data.crop_suitability_note) {
      el('suitabilityNote').textContent   = data.crop_suitability_note;
      el('suitabilityNote').style.display = 'block';
    }

    el('rainfall').textContent  = `${Number(data.rainfall_mm).toFixed(1)} mm`;
    el('elevation').textContent = `${Number(data.elevation_m).toFixed(1)} m`;

    const alts = (data.top_crop_recommendations||[]).slice(1);
    if (el('altCropsList') && alts.length) {
      const h = document.createElement('p');
      h.className = 'alt-crops-heading'; h.textContent = 'Also suitable:';
      el('altCropsList').appendChild(h);
      alts.forEach(a => {
        const li = document.createElement('li');
        li.textContent = `${a.crop}  —  ${a.compatibility_pct}%`;
        el('altCropsList').appendChild(li);
      });
    }
  } else {
    el('compatibilityBadge').style.display = 'none';
    const sb = el('suitabilityBadge'); if (sb) sb.style.display = 'none';
    el('rainfall').textContent  = `${Number(data.rainfall_mm).toFixed(1)} mm`;
    el('elevation').textContent = `${Number(data.elevation_m).toFixed(1)} m`;
    const lul = el('landUseList');
    if (lul && Array.isArray(data.land_use_recommendations)) {
      data.land_use_recommendations.forEach(tip => {
        const li = document.createElement('li'); li.textContent = tip;
        lul.appendChild(li);
      });
    }
  }
}


function renderInfrastructure(data) {
  const el = id => document.getElementById(id);
  if (!el('infraSuitability')) return;

  const suitability = data.infrastructure_suitability || 'ANALYZED';
  const cls = suitability.includes('HIGH') ? 'high' :
              suitability.includes('MODERATE') || suitability.includes('CONDITION') ? 'moderate' :
              suitability.includes('NOT') ? 'low' : 'neutral';

  el('infraSuitability').textContent = suitability;
  el('infraSuitability').className = `infra-badge ${cls}`;
  el('infraStatus').textContent = data.infrastructure_status || 'Infrastructure assessment completed';
  el('infraRecommendation').textContent = data.infrastructure_recommendation || 'Use this as a preliminary guide only. Final construction decisions require independent technical site validation and local compliance checking.';
  el('infraScore').textContent = `${Math.round(Number(data.infrastructure_score || 0))}%`;
  el('slopePct').textContent = `${Number(data.slope_pct || 0).toFixed(1)}%`;
  el('infraElevation').textContent = `${Number(data.elevation_m || 0).toFixed(1)} m`;
  el('infraRisk').textContent = data.infrastructure_risk || '--';
}

function updateTopBadges(data=null, polygonPoints=null) {
  const vb = document.getElementById('vegBadge');
  const ib = document.getElementById('infraBadge');
  const ab = document.getElementById('selectedAreaBadge');
  if (!vb) return;
  if (data) {
    const veg = clampPercent(Number(data.ndvi)*100, 100);
    vb.textContent = `Vegetated: ${Math.round(veg)}%`;
    ib.textContent = `Infrastructure: ${Math.round(100-veg)}%`;
  } else {
    vb.textContent = 'Vegetated: --%';
    ib.textContent = 'Infrastructure: --%';
  }
  const hasPolygon = polygonPoints && polygonPoints.length >= 3;
  ab.textContent = hasPolygon
    ? `Selected Area: ${getPolygonAreaHa().toFixed(2)} ha`
    : 'Selected Area: -- ha';
}

function updateTimestamp() {
  const el = document.getElementById('lastAnalysisAt');
  if (el) el.textContent = `Last analysis: ${new Date().toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',second:'2-digit'})}`;
}

function setLoadingState(loading) {
  const aBtn  = document.getElementById('analyzeAreaBtn');
  const cBtn  = document.getElementById('analyzeCoordBtn');
  const label = loading ? 'Analyzing…' : null;
  if (aBtn) { aBtn.disabled = loading; if(label) aBtn.textContent = label; else aBtn.textContent = 'Analyze Selection'; }
  if (cBtn) { cBtn.disabled = loading; if(label) cBtn.textContent = label; else cBtn.textContent = 'Analyze Point'; }
}

// ── Core analysis function ────────────────────────────────────────────────────
async function runAnalysis({ polygon=[], lat=null, lon=null }) {
  setLoadingState(true);
  initMap();

  try {
    let response;

    if (lat !== null && lon !== null) {
      // Manual coordinate point — GET request
      response = await fetch(`/api/analysis?lat=${lat}&lon=${lon}`);
    } else {
      // Polygon — POST request
      if (!polygon.length && activeDrawPolygon) polygon = getPolygonPoints();
      response = await fetch('/api/analysis', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ polygon }),
      });
    }

    if (!response.ok) throw new Error(`Server error: ${response.status}`);
    const data = await response.json();

    // Weather card
    document.getElementById('temperatureC').textContent       = Number(data.temperature_c).toFixed(1);
    document.getElementById('weatherDescription').textContent = data.weather_description;
    document.getElementById('humidity').textContent           = `${Math.round(data.live_humidity)}%`;
    document.getElementById('humidityBar').style.width        = `${clampPercent(data.live_humidity,100)}%`;
    document.getElementById('seasonAdvice').textContent       = data.season_advice;

    // Crop card
    renderRecommendation(data);

    // Infrastructure card
    renderInfrastructure(data);

    // Soil card
    document.getElementById('soilPh').textContent     = `pH ${Number(data.soil_ph).toFixed(1)}`;
    document.getElementById('ndvi').textContent        = Number(data.ndvi).toFixed(3);
    document.getElementById('nitrogen').textContent   = Math.round(data.nitrogen);
    document.getElementById('phosphorus').textContent = Math.round(data.phosphorus);
    document.getElementById('potassium').textContent  = Math.round(data.potassium);

    // Nutrient bars — max values match dataset ranges
    document.getElementById('nBar').style.width = `${clampPercent(data.nitrogen,  140)}%`;
    document.getElementById('pBar').style.width = `${clampPercent(data.phosphorus,145)}%`;
    document.getElementById('kBar').style.width = `${clampPercent(data.potassium, 205)}%`;

    updateSoilDonut(data.soil_ph);
    fillLiveObservations(data);
    updateTopBadges(data, polygon);
    updateMap(data.lat, data.lon);
    updateTimestamp();

    // Sync coord input fields if point mode
    if (lat !== null) {
      document.getElementById('manualLat').value = data.lat;
      document.getElementById('manualLon').value = data.lon;
    }

  } catch (err) {
    document.getElementById('weatherDescription').textContent = 'Data source unavailable.';
    const ls = document.getElementById('landStatus');
    if (ls) ls.textContent = 'Analysis failed — check API keys and Earth Engine auth.';
    console.error('Analysis error:', err);
  } finally {
    setLoadingState(false);
  }
}

// backwards-compat wrapper used by old inline calls
async function loadAnalysis(polygonPoints=[]) {
  await runAnalysis({ polygon: polygonPoints });
}

initMap();
