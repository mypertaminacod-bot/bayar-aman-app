/* Shared validation and safe text rendering; no geocoding or invented courier location. */
(function (root) {
  'use strict';
  function validate(value) {
    if (!Array.isArray(value) || value.length > 30) throw new Error('Rute harus berupa array maksimal 30 titik.');
    return value.map(point => {
      if (!point || typeof point !== 'object' || Array.isArray(point)) throw new Error('Titik rute tidak valid.');
      const {address, lat = null, lng = null, verified = false, source = ''} = point;
      if (typeof address !== 'string' || !address.trim() || address.length > 1000 || typeof verified !== 'boolean' || typeof source !== 'string' || source.length > 1000) throw new Error('Alamat/sumber rute tidak valid.');
      if ((lat === null) !== (lng === null)) throw new Error('Isi kedua koordinat atau kosongkan keduanya.');
      if (lat !== null && (typeof lat !== 'number' || !Number.isFinite(lat) || Math.abs(lat) > 90 || typeof lng !== 'number' || !Number.isFinite(lng) || Math.abs(lng) > 180)) throw new Error('Koordinat di luar batas.');
      if (verified && (lat === null || !source.trim())) throw new Error('Koordinat terverifikasi memerlukan koordinat lengkap dan sumber verifikasi.');
      return {address: address.trim(), lat, lng, verified, source: source.trim()};
    });
  }
  function render(container, value) {
    container.replaceChildren();
    let points;
    try { points = validate(value || []); } catch (_) { container.textContent = 'Data rute tidak valid. Hubungi Admin.'; return; }
    if (!points.length) { container.textContent = 'Rute belum tersedia dari Admin.'; return; }
    const note = document.createElement('p');
    note.textContent = 'Urutan titik dari Admin; bukan posisi GPS kurir atau bukti barang sedang dikirim. Titik berkedip hanya penanda rute.';
    container.appendChild(note);
    points.forEach((p, i) => {
      const el = document.createElement('div'); el.className = 'route-point';
      const dot = document.createElement('span'); dot.className = 'route-dot'; dot.setAttribute('aria-hidden', 'true');
      const label = document.createElement('p'); label.textContent = (i + 1) + '. Alamat yang dimasukkan: ' + p.address;
      const coords = document.createElement('p');
      coords.textContent = p.verified ? 'Koordinat terverifikasi oleh Admin: ' + p.lat + ', ' + p.lng + ' · Sumber: ' + p.source : 'Koordinat belum diverifikasi.';
      el.append(dot, label, coords); container.appendChild(el);
    });
  }
  const api = {validate, render};
  if (typeof module !== 'undefined') module.exports = api;
  else root.BayarRoute = api;
})(typeof window !== 'undefined' ? window : globalThis);
