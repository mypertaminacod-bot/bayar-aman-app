/* Shared validation and safe text rendering; no geocoding or invented courier location. */
(function (root) {
  'use strict';
  function validate(value) {
    if (!Array.isArray(value) || value.length > 30) throw new Error('Rute harus berupa array maksimal 30 titik.');
    let currentCount = 0;
    const normalized = value.map(point => {
      if (!point || typeof point !== 'object' || Array.isArray(point)) throw new Error('Titik rute tidak valid.');
      const {address, lat = null, lng = null, verified = false, source = '', current = false} = point;
      if (typeof address !== 'string' || !address.trim() || address.length > 1000 || typeof verified !== 'boolean' || typeof source !== 'string' || source.length > 1000) throw new Error('Alamat/sumber rute tidak valid.');
      if ((lat === null) !== (lng === null)) throw new Error('Isi kedua koordinat atau kosongkan keduanya.');
      if (lat !== null && (typeof lat !== 'number' || !Number.isFinite(lat) || Math.abs(lat) > 90 || typeof lng !== 'number' || !Number.isFinite(lng) || Math.abs(lng) > 180)) throw new Error('Koordinat di luar batas.');
      if (typeof current !== 'boolean') throw new Error('Penanda posisi tidak valid.');
      if (current && (!verified || lat === null)) throw new Error('Posisi perjalanan memerlukan koordinat terverifikasi.');
      if (current) currentCount++;
      if (verified && (lat === null || !source.trim())) throw new Error('Koordinat terverifikasi memerlukan koordinat lengkap dan sumber verifikasi.');
      return {address: address.trim(), lat, lng, verified, source: source.trim(), current};
    });
    if (currentCount > 1) throw new Error('Hanya satu posisi perjalanan boleh aktif.');
    return normalized;
  }
  function render(container, value) {
    container.replaceChildren();
    let points;
    try { points = validate(value || []); } catch (_) { container.textContent = 'Data rute tidak valid. Hubungi Admin.'; return; }
    if (!points.length) { container.textContent = 'Rute belum tersedia dari Admin.'; return; }
    const note = document.createElement('p');
    note.textContent = 'Urutan titik dari Admin; bukan posisi GPS kurir atau bukti barang sedang dikirim. Titik berkedip menunjukkan posisi yang ditandai Admin, bukan GPS langsung.';
    container.appendChild(note);
    // Zoomable route overview is only shown for coordinates verified by Admin.
    // This is a schematic connecting verified stops, not a road route or live GPS.
    const mapped = points.filter(p => p.verified && p.lat !== null && p.lng !== null);
    if (mapped.length >= 2) {
      const map = document.createElement('div');
      map.className = 'route-map-overview';
      map.setAttribute('aria-label', 'Pratinjau titik perjalanan dengan zoom');
      const controls = document.createElement('div');
      controls.className = 'route-map-controls';
      const viewport = document.createElement('div');
      viewport.className = 'route-map-viewport';
      viewport.style.overflow = 'hidden';
      viewport.style.touchAction = 'pan-x pan-y';
      const svgNS = 'http://www.w3.org/2000/svg';
      const svg = document.createElementNS(svgNS, 'svg');
      svg.setAttribute('viewBox', '0 0 320 200');
      svg.setAttribute('role', 'img');
      svg.setAttribute('aria-label', 'Skema titik awal, perantara, dan tujuan yang diverifikasi Admin');
      svg.style.cssText = 'display:block;width:100%;height:200px;background:#fff8fa;border:1px solid #e6d6db;border-radius:9px';
      const lats = mapped.map(p => p.lat), lngs = mapped.map(p => p.lng);
      const minLat = Math.min(...lats), maxLat = Math.max(...lats);
      const minLng = Math.min(...lngs), maxLng = Math.max(...lngs);
      const dx = Math.max(maxLng - minLng, 0.001), dy = Math.max(maxLat - minLat, 0.001);
      const xy = p => [24 + 272 * (p.lng - minLng) / dx, 176 - 152 * (p.lat - minLat) / dy];
      const line = document.createElementNS(svgNS, 'polyline');
      line.setAttribute('points', mapped.map(p => xy(p).join(',')).join(' '));
      line.setAttribute('fill', 'none'); line.setAttribute('stroke', '#a6192e');
      line.setAttribute('stroke-width', '3'); line.setAttribute('stroke-linecap', 'round');
      svg.appendChild(line);
      mapped.forEach((p, i) => {
        const [x, y] = xy(p);
        const dot = document.createElementNS(svgNS, 'circle');
        dot.setAttribute('cx', String(x)); dot.setAttribute('cy', String(y));
        dot.setAttribute('r', '6'); dot.setAttribute('fill', '#d00020');
        if (p.current) {
          dot.classList.add('route-position');
        }
        svg.appendChild(dot);
      });
      let zoom = 1;
      const setZoom = z => { zoom = Math.max(1, Math.min(4, z)); svg.style.transform = 'scale(' + zoom + ')'; svg.style.transformOrigin = 'center'; };
      for (const [label, delta] of [['+', 0.5], ['−', -0.5]]) {
        const btn = document.createElement('button'); btn.type = 'button';
        btn.className = 'btn secondary small'; btn.textContent = label;
        btn.setAttribute('aria-label', delta > 0 ? 'Perbesar rute' : 'Perkecil rute');
        btn.addEventListener('click', () => setZoom(zoom + delta));
        controls.appendChild(btn);
      }
      // Pinch zoom for Android touchscreens; never infer live courier coordinates.
      const distance = touches => Math.hypot(touches[0].clientX - touches[1].clientX, touches[0].clientY - touches[1].clientY);
      let pinchStart = null;
      let zoomStart = 1;
      viewport.style.touchAction = 'pan-x pan-y';
      viewport.addEventListener('touchstart', event => {
        if (event.touches.length === 2) {
          pinchStart = distance(event.touches);
          zoomStart = zoom;
        }
      }, {passive:true});
      viewport.addEventListener('touchmove', event => {
        if (event.touches.length === 2 && pinchStart > 0) {
          event.preventDefault();
          setZoom(zoomStart * distance(event.touches) / pinchStart);
        }
      }, {passive:false});
      viewport.addEventListener('touchend', event => {
        if (event.touches.length < 2) pinchStart = null;
      }, {passive:true});
      viewport.addEventListener('touchcancel', () => { pinchStart = null; }, {passive:true});
      viewport.appendChild(svg);
      const info = document.createElement('p'); info.className = 'tiny';
      info.textContent = 'Skema titik terverifikasi Admin, bukan peta jalan atau lokasi GPS langsung.';
      map.append(controls, viewport, info); container.appendChild(map);
    }
    points.forEach((p, i) => {
      const el = document.createElement('div'); el.className = 'route-point';
      const dot = document.createElement('span'); dot.className = 'route-dot'; dot.setAttribute('aria-hidden', 'true'); if (!p.current) dot.style.animation = 'none';
      const label = document.createElement('p'); label.textContent = (i + 1) + '. ' + (p.current ? 'Posisi perjalanan menurut Admin: ' : 'Alamat yang dimasukkan: ') + p.address;
      const coords = document.createElement('p');
      coords.textContent = p.verified ? 'Koordinat terverifikasi oleh Admin: ' + p.lat + ', ' + p.lng + ' · Sumber: ' + p.source : 'Koordinat belum diverifikasi.';
      el.append(dot, label, coords); container.appendChild(el);
    });
  }
  const api = {validate, render};
  if (typeof module !== 'undefined') module.exports = api;
  else root.BayarRoute = api;
})(typeof window !== 'undefined' ? window : globalThis);
