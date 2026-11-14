/* ---------- ландшафт: картинка ---------- */
function paintTerrain() {
  const W = WT, PX = 2, w = WW / PX, h = WH / PX, c = mkCanvas(w, h), g = c.getContext('2d'), im = g.createImageData(w, h), d = im.data, nF = W.nF, nD = W.nD;
  const E = new Float32Array(w * h), Tt = new Uint8Array(w * h);
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) { const r = W.info(i * PX, j * PX); E[j * w + i] = r.e; Tt[j * w + i] = r.t; }
  const hex = s => [parseInt(s.slice(1, 3), 16), parseInt(s.slice(3, 5), 16), parseInt(s.slice(5, 7), 16)];
  const COL = { grass: hex('#6a8239'), forest: hex('#4b6a2c'), hills: hex('#86884a'), mount: hex('#857f72'), water: hex('#2f5568'), shallow: hex('#4c7a86'), snowg: hex('#d9e2e4'), snowf: hex('#a9bcae'), snowh: hex('#c1cbcd'), steppe: hex('#b09f58'), steppef: hex('#8c8a40'), steppeh: hex('#a59152'), sand: hex('#cdb078'), sandh: hex('#b99a62') };
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    const k = j * w + i, x = i * PX, y = j * PX, t = Tt[k], bio = t === 0 ? 'grass' : W.biomeAt(x, y); let col;
    if (t === 0) { col = E[k] > .27 ? COL.shallow : COL.water; const m = (E[k] - .1) / .2; if (E[k] <= .27) { col = [lerp(COL.water[0] - 8, COL.water[0], clamp(m, 0, 1)), lerp(COL.water[1] - 10, COL.water[1], clamp(m, 0, 1)), lerp(COL.water[2] - 8, COL.water[2], clamp(m, 0, 1))]; } }
    else if (bio === 'snow') col = t === 2 ? COL.snowf : t === 3 ? COL.snowh : t === 4 ? COL.mount : COL.snowg;
    else if (bio === 'steppe') col = t === 2 ? COL.steppef : t === 3 ? COL.steppeh : t === 4 ? COL.mount : COL.steppe;
    else if (bio === 'arid') col = t === 2 ? COL.forest : t === 3 ? COL.sandh : t === 4 ? COL.mount : COL.sand;
    else col = t === 2 ? COL.forest : t === 3 ? COL.hills : t === 4 ? COL.mount : COL.grass;
    const il = i > 0 ? E[k - 1] : E[k], ir = i < w - 1 ? E[k + 1] : E[k], iu = j > 0 ? E[k - w] : E[k], idn = j < h - 1 ? E[k + w] : E[k];
    let sh = t === 0 ? 0 : ((il - ir) + (iu - idn)) * 3.2; const n = (nD(x / 22, y / 22) - .5) * 30 + (nD(x / 6 + 40, y / 6) - .5) * 14;
    if (t === 0) { sh = (nD(x / 40 + 9, y / 40) - .5) * .16; }
    d[k * 4] = clamp(col[0] + n + sh * 90, 0, 255); d[k * 4 + 1] = clamp(col[1] + n + sh * 90, 0, 255); d[k * 4 + 2] = clamp(col[2] + n * .8 + sh * 90, 0, 255); d[k * 4 + 3] = 255;
    // береговая линия
    if (t === 0 && (i < w - 1 && Tt[k + 1] !== 0 || j < h - 1 && Tt[k + w] !== 0 || i > 0 && Tt[k - 1] !== 0 || j > 0 && Tt[k - w] !== 0)) { d[k * 4] = 205; d[k * 4 + 1] = 205; d[k * 4 + 2] = 180; }
    else if (t === 0 && i > 2 && j > 2 && i < w - 3 && j < h - 3 && (Tt[k + 2] !== 0 || Tt[k - 2] !== 0 || Tt[k + 2 * w] !== 0 || Tt[k - 2 * w] !== 0 || Tt[k + 3] !== 0 || Tt[k - 3] !== 0)) { d[k * 4] = d[k * 4] * .55 + 205 * .45; d[k * 4 + 1] = d[k * 4 + 1] * .55 + 214 * .45; d[k * 4 + 2] = d[k * 4 + 2] * .55 + 205 * .45; }
    else if (t !== 0 && (i < w - 1 && Tt[k + 1] === 0 || j < h - 1 && Tt[k + w] === 0 || i > 0 && Tt[k - 1] === 0 || j > 0 && Tt[k - w] === 0)) { d[k * 4] = col[0] * .55 + 166 * .45; d[k * 4 + 1] = col[1] * .55 + 151 * .45; d[k * 4 + 2] = col[2] * .55 + 102 * .45; }
  }
  g.putImageData(im, 0, 0);
  const full = mkCanvas(WW, WH), f = full.getContext('2d'); f.imageSmoothingEnabled = true; f.imageSmoothingQuality = 'high'; f.drawImage(c, 0, 0, WW, WH);
  /* Редкие спокойные блики на воде рисуются в кэш карты, не на каждом кадре. */
  f.lineCap = 'round'; f.lineWidth = .8;
  for (let y = 18; y < WH - 18; y += 26) for (let x = 18; x < WW - 18; x += 41) {
    const wave = Math.sin(x * .13 + y * .19), xx = x + wave * 12, yy = y + Math.cos(x * .07) * 6;
    if (W.info(xx - 10, yy).t !== 0 || W.info(xx + 10, yy).t !== 0) continue;
    f.strokeStyle = 'rgba(184,217,218,' + (.045 + (wave + 1) * .025) + ')';
    f.beginPath(); f.moveTo(xx - 5, yy); f.quadraticCurveTo(xx, yy + 1.6, xx + 6, yy); f.stroke();
  }
  drawFarms(f);
  const R = mulberry(G.seed + 3), icons = [];
  for (let j = 0; j < GH; j++) for (let i = 0; i < GW; i++) { const k = j * GW + i, t = W.cells[k], bio = W.bio[k], x = i * GC, y = j * GC; if (t === 2) for (let q = 0; q < 3; q++) icons.push({ k: 'tree', bio, x: x + R() * GC, y: y + R() * GC }); else if (t === 3) icons.push({ k: 'hill', bio, x: x + R() * GC, y: y + R() * GC }); else if (t === 4) icons.push({ k: 'mount', bio, x: x + R() * GC, y: y + R() * GC, s: .8 + R() * .6 }); else if (t === 1 && R() < .05) icons.push({ k: 'bush', bio, x: x + R() * GC, y: y + R() * GC }); }
  icons.sort((a, b) => a.y - b.y); f.lineJoin = 'round';
  for (const ic of icons) { const { x, y } = ic;
    if (ic.k === 'tree') {
      /* Варианты размера/силуэта привязаны к месту, без расходования RNG мира. */
      const v = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453, q = v - Math.floor(v);
      const sx = .82 + q * .36, sy = .88 + (1 - q) * .28;
      contactShadow(f, x + 4, y + 2, 11 * sx, 4 * sy);
      f.save(); f.translate(x, y); f.scale(sx, sy); f.translate(-x, -y);
      f.fillStyle = 'rgba(0,0,0,.24)'; ell(f, x + 3, y + 1, 7, 2.6); f.fill(); if (ic.bio === 1) { f.fillStyle = '#3b2a1a'; f.fillRect(x - .8, y - 2, 1.8, 3); poly(f, [x, y - 16, x + 6.5, y - 1, x - 6.5, y - 1]); fs(f, '#2a4434', 1.2); poly(f, [x, y - 16, x + 6.5, y - 1, x + 1, y - 1]); fs(f, 'rgba(0,0,0,.25)', 0); poly(f, [x, y - 16, x + 3.2, y - 9, x - 3.4, y - 9]); fs(f, '#eef4f5', .5); } else { f.fillStyle = '#3b2a1a'; f.fillRect(x - 1, y - 4, 2.2, 5); const dk = ic.bio === 2 ? '#5c6424' : '#2a4619', md = ic.bio === 2 ? '#707a2e' : '#3d6226', lt = ic.bio === 2 ? '#8e9843' : '#5f8a35'; ell(f, x, y - 9, 6.6, 6.8); fs(f, dk, 1.2); f.fillStyle = 'rgba(0,0,0,.18)'; ell(f, x + 2, y - 6.5, 4.4, 3.6); f.fill(); f.fillStyle = md; ell(f, x - 1.6, y - 10.4, 4.6, 4.6); f.fill(); f.fillStyle = lt; ell(f, x - 3, y - 12, 2.4, 2.1); f.fill();
        f.fillStyle = q > .66 ? '#8b9c48' : '#729441';
        for (let leaf = 0; leaf < 4; leaf++) { ell(f, x - 3.8 + leaf * 1.7, y - 12 + (leaf % 2) * 2, .9, .6); f.fill(); }
      } f.restore(); }
    else if (ic.k === 'hill') { f.beginPath(); f.moveTo(x - 17, y); f.quadraticCurveTo(x, y - 18, x + 17, y); f.closePath(); const hc = ic.bio === 1 ? '#c8d2d3' : ic.bio === 2 ? '#a59152' : ic.bio === 3 ? '#bfa268' : '#8a8f4e'; fs(f, hc, 1.1); f.save(); f.beginPath(); f.moveTo(x - 17, y); f.quadraticCurveTo(x, y - 18, x + 17, y); f.closePath(); f.clip(); f.fillStyle = 'rgba(0,0,0,.16)'; f.fillRect(x + 2, y - 20, 20, 22); f.fillStyle = 'rgba(255,255,255,.14)'; ell(f, x - 6, y - 10, 7, 3.4); f.fill(); f.restore(); }
    else if (ic.k === 'mount') { const s = ic.s * 1.5; f.fillStyle = 'rgba(0,0,0,.25)'; ell(f, x + 6 * s, y, 22 * s, 4.4 * s); f.fill(); poly(f, [x - 21 * s, y, x - 3 * s, y - 34 * s, x + 6 * s, y - 24 * s, x + 13 * s, y - 30 * s, x + 25 * s, y]); fs(f, '#948e82', 1.6); poly(f, [x - 3 * s, y - 34 * s, x + 6 * s, y - 24 * s, x + 13 * s, y - 30 * s, x + 25 * s, y, x + 7 * s, y]); fs(f, '#6c675d', 0); poly(f, [x - 3 * s, y - 34 * s, x - 21 * s, y, x - 12 * s, y]); fs(f, 'rgba(255,255,255,.12)', 0); f.strokeStyle = 'rgba(30,26,20,.45)'; f.lineWidth = .9; f.beginPath(); f.moveTo(x - 3 * s, y - 34 * s); f.lineTo(x + 1 * s, y - 14 * s); f.lineTo(x - 3 * s, y - 2 * s); f.moveTo(x + 13 * s, y - 30 * s); f.lineTo(x + 14 * s, y - 14 * s); f.lineTo(x + 18 * s, y - 2 * s); f.moveTo(x + 6 * s, y - 24 * s); f.lineTo(x + 8 * s, y - 12 * s); f.stroke(); poly(f, [x - 7 * s, y - 27 * s, x - 3 * s, y - 34 * s, x + 2.5 * s, y - 27 * s, x + 0 * s, y - 29 * s, x - 3 * s, y - 24 * s]); fs(f, '#f4f6f5', .8); poly(f, [x + 9 * s, y - 27 * s, x + 13 * s, y - 30 * s, x + 16 * s, y - 25 * s, x + 12 * s, y - 26 * s]); fs(f, '#e3e8e8', .6); }
    else { ell(f, x, y - 3, 5, 3.6); fs(f, ic.bio === 1 ? '#8ea08a' : ic.bio === 2 ? '#8c8a3e' : ic.bio === 3 ? '#9a8a4e' : '#4d6b27', 1); } }
  drawRoads(f); drawRivers(f); drawBridges(f);
  // виньетка по краям карты
  const vg = f.createRadialGradient(WW / 2, WH / 2, WH * .55, WW / 2, WH / 2, WW * .62); vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(8,6,3,.4)'); f.fillStyle = vg; f.fillRect(0, 0, WW, WH);
  return full;
}
/* ---------- пашни и фермы вокруг поселений (только красота) ---------- */
function drawFarms(f) {
  const R = mulberry(G.seed + 7), W = WT, placed = [], okAt = (x, y) => { if (x < 30 || y < 30 || x > WW - 30 || y > WH - 30) return false; const k = cellOf(x, y); return W.cells[k] === 1 && !W.road[k] && W.bio[k] !== 1 && W.bio[k] !== 3; };
  const CROP = [['#86683d', '#6a4f2b'], ['#b9a24f', '#9a853a'], ['#7f9a45', '#667f34'], ['#9fae56', '#82903f'], ['#78593a', '#5b4128']];
  const corners = (x, y, ang, w, h) => { const c = Math.cos(ang), sn = Math.sin(ang); return [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]].map(q => [x + q[0] * c - q[1] * sn, y + q[0] * sn + q[1] * c]); };
  const overlap = (A, B) => { for (const P of [A, B]) for (let i = 0; i < 2; i++) { const ex = P[i + 1][0] - P[i][0], ey = P[i + 1][1] - P[i][1], pr = Q => { let lo = 1e9, hi = -1e9; for (const q of Q) { const d = q[0] * ey - q[1] * ex; lo = Math.min(lo, d); hi = Math.max(hi, d); } return [lo, hi]; }, a = pr(A), b = pr(B); if (a[1] < b[0] + 1.5 || b[1] < a[0] + 1.5) return false; } return true; };
  f.lineJoin = 'round';
  for (const s of G.settles) { if (s.kind === 'camp') continue;
    const n = s.kind === 'village' ? 7 + Math.floor(R() * 4) : s.kind === 'town' ? 6 + Math.floor(R() * 4) : 3 + Math.floor(R() * 2), r0 = s.kind === 'village' ? 60 : s.kind === 'town' ? 88 : 80, base = R() * Math.PI, farm = [];
    for (let t = 0; farm.length < n && t < 90; t++) {
      const w = 34 + R() * 22, h = 22 + R() * 14; let x, y, ang;
      if (!farm.length || R() < .12) { const a = R() * TAU, d = r0 + R() * 55; x = s.x + Math.cos(a) * d; y = s.y + Math.sin(a) * d * .8; ang = base + (R() < .5 ? 0 : Math.PI / 2) + (R() - .5) * .3; }
      else { const q = farm[Math.floor(R() * farm.length)]; ang = q.ang; const sg = R() < .5 ? 1 : -1, c = Math.cos(ang), sn = Math.sin(ang); let lx, ly; if (R() < .55) { lx = sg * (q.w / 2 + w / 2 + 2.5); ly = (R() - .5) * h * .5; } else { lx = (R() - .5) * w * .5; ly = sg * (q.h / 2 + h / 2 + 2.5); } x = q.x + lx * c - ly * sn; y = q.y + lx * sn + ly * c; }
      const C = corners(x, y, ang, w, h); if (!C.every(q => okAt(q[0], q[1])) || !okAt(x, y)) continue;
      if (Math.hypot(s.x - x, s.y - y) < r0 - 6) continue;
      if (G.settles.some(o => o !== s && Math.hypot(o.x - x, o.y - y) < 80)) continue;
      if (placed.some(o => Math.hypot(o.x - x, o.y - y) < 90 && overlap(o.C, C))) continue;
      const fl = { x, y, ang, w, h, C }; farm.push(fl); placed.push(fl);
      const cr = CROP[Math.floor(R() * CROP.length)]; f.save(); f.translate(x, y); f.rotate(ang);
      f.fillStyle = 'rgba(0,0,0,.14)'; f.fillRect(-w / 2 + 1.5, -h / 2 + 2, w, h);
      f.fillStyle = cr[0]; f.fillRect(-w / 2, -h / 2, w, h);
      f.strokeStyle = cr[1]; f.globalAlpha = .75; f.lineWidth = 1; for (let yy = -h / 2 + 3; yy < h / 2; yy += 3.4) { f.beginPath(); f.moveTo(-w / 2 + 1, yy); f.lineTo(w / 2 - 1, yy); f.stroke(); }
      f.globalAlpha = 1; f.strokeStyle = 'rgba(38,48,18,.5)'; f.lineWidth = 1.3; f.strokeRect(-w / 2, -h / 2, w, h); f.restore();
    }
    if (s.kind === 'village' && farm.length) { const q = farm[0], hx = q.x + Math.cos(q.ang + 1.57) * (q.h / 2 + 11), hy = q.y + Math.sin(q.ang + 1.57) * (q.h / 2 + 11); if (okAt(hx, hy)) { house(f, hx, hy, 16, 11, '#cdbd96', '#9b7d42'); ell(f, hx + 14, hy + 2, 5, 4); f.fillStyle = '#c9a94a'; f.fill(); f.strokeStyle = OL; f.lineWidth = 1; f.stroke(); } }
  }
}
/* ---------- дороги, реки, мосты ---------- */
// Дорога — это ломаная по клеткам: сглаживаем её и слегка «разводим» шумом, чтобы вилась как настоящая. Шум зависит только от места, поэтому общие участки разных дорог совпадают
function roadCurve(seg, bridges) {
  const W = WT, P = [];
  for (let i = 0; i < seg.length; i++) { const q = seg[i]; if (i) { const a = seg[i - 1], n = Math.ceil(Math.hypot(q.x - a.x, q.y - a.y) / 16); for (let k = 1; k < n; k++) P.push({ x: lerp(a.x, q.x, k / n), y: lerp(a.y, q.y, k / n) }); } P.push({ x: q.x, y: q.y, pin: i === 0 || i === seg.length - 1 || (W.rv && W.bridge[cellOf(q.x, q.y)] === 1) }); }
  const n = P.length; if (n < 3) return P;
  const wt = new Float32Array(n), acc = new Float32Array(n); for (let i = 1; i < n; i++) acc[i] = acc[i - 1] + Math.hypot(P[i].x - P[i - 1].x, P[i].y - P[i - 1].y);
  for (let i = 0; i < n; i++) { let bd = 1e9; for (const b of bridges) bd = Math.min(bd, Math.hypot(b.x - P[i].x, b.y - P[i].y)); wt[i] = Math.min(clamp((bd - 14) / 46, 0, 1), clamp((Math.min(acc[i], acc[n - 1] - acc[i]) - 10) / 50, 0, 1)); }
  for (let it = 0; it < 3; it++) { const Q = P.map(q => ({ x: q.x, y: q.y })); for (let i = 1; i < n - 1; i++) { if (P[i].pin) continue; P[i].x = lerp(Q[i].x, (Q[i - 1].x + 2 * Q[i].x + Q[i + 1].x) / 4, wt[i]); P[i].y = lerp(Q[i].y, (Q[i - 1].y + 2 * Q[i].y + Q[i + 1].y) / 4, wt[i]); } }
  for (let i = 0; i < n; i++) { if (P[i].pin) continue; P[i].x += (WT.nD(P[i].x / 90 + 3, P[i].y / 90) - .5) * 15 * wt[i]; P[i].y += (WT.nD(P[i].x / 90, P[i].y / 90 + 7) - .5) * 15 * wt[i]; }
  return P;
}
function curvePath(P, path) { path.moveTo(P[0].x, P[0].y); for (let i = 1; i < P.length - 1; i++) path.quadraticCurveTo(P[i].x, P[i].y, (P[i].x + P[i + 1].x) / 2, (P[i].y + P[i + 1].y) / 2); path.lineTo(P[P.length - 1].x, P[P.length - 1].y); return path; }
function drawRoads(f) {
  const br = WT.bridges || [], big = new Path2D(), small = new Path2D(), kindAt = q => { for (const s of G.settles) if (Math.hypot(s.x - q.x, s.y - q.y) < 40) return s.kind; return 'none'; };
  for (const seg of G.roads) { if (seg.length < 2) continue; const a = kindAt(seg[0]), b = kindAt(seg[seg.length - 1]), main = (a === 'town' || a === 'castle') && (b === 'town' || b === 'castle'); curvePath(roadCurve(seg, br), main ? big : small); }
  f.lineCap = 'round'; f.lineJoin = 'round';
  f.strokeStyle = 'rgba(52,36,18,.5)'; f.lineWidth = 8.6; f.stroke(small); f.lineWidth = 11; f.stroke(big);
  f.strokeStyle = '#b8955f'; f.lineWidth = 5.4; f.stroke(small); f.lineWidth = 7.4; f.stroke(big);
  f.strokeStyle = 'rgba(224,200,150,.7)'; f.lineWidth = 2.2; f.stroke(small); f.lineWidth = 3.2; f.stroke(big);
}
function drawRivers(f) {
  f.lineCap = 'round'; f.lineJoin = 'round';
  const widthAt = (r, i) => r.w * (.5 + .5 * i / r.p.length);
  for (const [col, add, alpha] of [['rgba(36,52,40,.55)', 4.4, 1], ['#4a82a0', 0, 1], ['rgba(190,226,236,.45)', -.62, 1]])
    for (const r of WT.rivers || []) { const P = r.p; for (let i = 0; i < P.length - 1; i += 6) { const e = Math.min(P.length - 1, i + 7); f.beginPath(); f.moveTo(P[i][0], P[i][1]); for (let k = i + 1; k <= e; k++) f.lineTo(P[k][0], P[k][1]); f.strokeStyle = col; const w = widthAt(r, i); f.lineWidth = add < 0 ? w * -add : w + add; f.stroke(); } }
}
function drawBridges(f) {
  for (const b of WT.bridges || []) { const L = (b.w || 10) + 18, H = 12; f.save(); f.translate(b.x, b.y); if (b.ax) f.rotate(Math.PI / 2);
    f.fillStyle = 'rgba(10,20,20,.35)'; f.fillRect(-L / 2 + 1, -H / 2 + 3, L, H);
    f.fillStyle = '#85653c'; f.fillRect(-L / 2, -H / 2, L, H); f.strokeStyle = 'rgba(40,26,12,.55)'; f.lineWidth = 1; for (let x = -L / 2 + 3; x < L / 2; x += 3.5) { f.beginPath(); f.moveTo(x, -H / 2); f.lineTo(x, H / 2); f.stroke(); }
    f.fillStyle = '#4a3520'; f.fillRect(-L / 2, -H / 2 - 1.8, L, 2.6); f.fillRect(-L / 2, H / 2 - .8, L, 2.6);
    f.fillStyle = '#9a9484'; f.fillRect(-L / 2 - 1, -H / 2 - 2, 5, H + 4); f.fillRect(L / 2 - 4, -H / 2 - 2, 5, H + 4); f.strokeStyle = OL; f.lineWidth = 1.1; f.strokeRect(-L / 2 - 1, -H / 2 - 2, 5, H + 4); f.strokeRect(L / 2 - 4, -H / 2 - 2, 5, H + 4);
    f.restore(); }
}
/* ---------- спрайты поселений ---------- */
function house(g, x, y, w, h, wall, roof) {
  g.fillStyle = 'rgba(0,0,0,.2)'; ell(g, x + w * .55, y + 1, w * .6, 3.5); g.fill();
  g.fillStyle = wall; g.fillRect(x - w / 2, y - h, w, h); g.fillStyle = 'rgba(0,0,0,.2)'; g.fillRect(x, y - h, w / 2, h);
  g.strokeStyle = 'rgba(0,0,0,.18)'; g.lineWidth = .7; for (let i = 1; i < 4; i++) { g.beginPath(); g.moveTo(x - w / 2, y - h * i / 4); g.lineTo(x + w / 2, y - h * i / 4); g.stroke(); }
  g.strokeStyle = OL; g.lineWidth = 1.4; g.strokeRect(x - w / 2, y - h, w, h);
  const ty = y - h - w * .62; poly(g, [x - w / 2 - 3, y - h, x, ty, x + w / 2 + 3, y - h]); fs(g, roof, 1.4);
  g.fillStyle = 'rgba(0,0,0,.28)'; g.beginPath(); g.moveTo(x, ty); g.lineTo(x + w / 2 + 3, y - h); g.lineTo(x + 1, y - h); g.closePath(); g.fill();
  g.strokeStyle = 'rgba(0,0,0,.3)'; g.lineWidth = .7; for (let i = 1; i < 3; i++) { const k = i / 3, yy = ty + (y - h - ty) * k, d = (w / 2 + 3) * k; g.beginPath(); g.moveTo(x - d, yy); g.lineTo(x + d, yy); g.stroke(); }
  g.fillStyle = 'rgba(255,255,255,.18)'; g.beginPath(); g.moveTo(x, ty); g.lineTo(x - w / 2 - 3, y - h); g.lineTo(x - w / 2 + 1, y - h); g.lineTo(x, ty + 2); g.closePath(); g.fill();
  g.fillStyle = '#2a1d12'; g.fillRect(x - 2.5, y - h * .55, 5, h * .55);
  if (w > 18) { g.fillStyle = '#f0c868'; g.fillRect(x - w * .36, y - h * .78, 3, 3.4); g.fillRect(x + w * .22, y - h * .78, 3, 3.4); g.strokeStyle = OL; g.lineWidth = .8; g.strokeRect(x - w * .36, y - h * .78, 3, 3.4); g.strokeRect(x + w * .22, y - h * .78, 3, 3.4); }
  g.fillStyle = '#4a4036'; g.fillRect(x + w * .22, ty + (y - h - ty) * .35, 3.4, 7); g.strokeStyle = OL; g.lineWidth = .8; g.strokeRect(x + w * .22, ty + (y - h - ty) * .35, 3.4, 7);
}
function tower(g, x, y, w, h, col, cap) { g.fillStyle = col; g.fillRect(x - w / 2, y - h, w, h); g.strokeStyle = OL; g.lineWidth = 1.5; g.strokeRect(x - w / 2, y - h, w, h); g.fillStyle = 'rgba(0,0,0,.22)'; g.fillRect(x, y - h, w / 2, h); g.strokeStyle = 'rgba(0,0,0,.2)'; g.lineWidth = .7; for (let k = 1; k < h / 7; k++) { g.beginPath(); g.moveTo(x - w / 2, y - k * 7); g.lineTo(x + w / 2, y - k * 7); g.stroke(); } if (h > 30) { g.fillStyle = '#1a130c'; g.fillRect(x - 1.2, y - h * .6, 2.4, 7); } g.strokeStyle = OL; g.lineWidth = 1.5; for (let i = 0; i < 3; i++) { g.fillStyle = col; g.fillRect(x - w / 2 + i * w / 3 - 1, y - h - 4, w / 3 - 1, 4); g.strokeRect(x - w / 2 + i * w / 3 - 1, y - h - 4, w / 3 - 1, 4); } if (cap) { poly(g, [x - w / 2 - 2, y - h - 4, x, y - h - 4 - w * .9, x + w / 2 + 2, y - h - 4]); fs(g, cap, 1.4); } }
const SS_CACHE = {};
function settleSprite(s) {
  const key = s.id + FACTIONS[s.fac].c1; if (SS_CACHE[key]) return SS_CACHE[key]; const c = mkCanvas(170, 150), g = c.getContext('2d'), f = FACTIONS[s.fac], R = mulberry(s.id * 31); g.lineJoin = 'round'; const cx = 85, cy = 120;
  g.fillStyle = 'rgba(0,0,0,.28)'; ell(g, cx + 4, cy + 4, 70, 18); g.fill();
  const cu = sCult(s), CA = { nord: ['#9b8d78', '#5a3a24'], emp: ['#cfc2a2', '#a8462f'], khan: ['#c9b48a', '#2b7568'], kin: ['#d3c7ac', '#3f5f9f'], emi: ['#e3d2a6', '#b5512a'], dom: ['#bfb08c', '#4a5a2e'], pact: ['#d9cfb4', '#8f2b2b'] }[cu] || ['#c9b48a', '#2b7568'], wall = CA[0], roof = CA[1];
  if (s.kind === 'town') {
    g.beginPath(); g.ellipse(cx, cy - 8, 66, 22, 0, 0, TAU); g.fillStyle = '#8f8878'; g.fill(); g.strokeStyle = OL; g.lineWidth = 2; g.stroke(); g.beginPath(); g.ellipse(cx, cy - 18, 66, 22, 0, 0, TAU); g.fillStyle = '#b3ab99'; g.fill(); g.stroke();
    house(g, cx - 36, cy - 14, 26, 18, wall, roof); house(g, cx + 34, cy - 12, 28, 20, wall, roof); house(g, cx - 8, cy - 6, 30, 22, wall, roof); house(g, cx + 6, cy - 30, 26, 22, wall, roof); house(g, cx - 28, cy - 34, 22, 16, wall, roof);
    tower(g, cx + 4, cy - 38, 22, 44, '#b5ad9a', roof); tower(g, cx - 64, cy - 12, 12, 22, '#a39b88', null); tower(g, cx + 62, cy - 12, 12, 22, '#a39b88', null);
  } else if (s.kind === 'castle') {
    tower(g, cx - 40, cy - 4, 22, 44, '#8f897b', roof); tower(g, cx + 40, cy - 4, 22, 44, '#8f897b', roof); g.fillStyle = '#a49d8c'; g.fillRect(cx - 40, cy - 38, 80, 34); g.strokeStyle = OL; g.lineWidth = 1.6; g.strokeRect(cx - 40, cy - 38, 80, 34); for (let i = 0; i < 6; i++) { g.fillRect(cx - 38 + i * 13.5, cy - 43, 8, 6); g.strokeRect(cx - 38 + i * 13.5, cy - 43, 8, 6); }
    g.beginPath(); g.moveTo(cx - 9, cy - 4); g.lineTo(cx - 9, cy - 22); g.quadraticCurveTo(cx, cy - 32, cx + 9, cy - 22); g.lineTo(cx + 9, cy - 4); g.closePath(); fs(g, '#2a1d12', 1.4); tower(g, cx, cy - 36, 28, 38, '#b0a994', roof);
  } else if (s.kind === 'village') {
    house(g, cx - 28, cy - 6, 24, 15, wall, '#a98a4a'); house(g, cx + 22, cy - 2, 26, 16, wall, '#a98a4a'); house(g, cx - 2, cy - 22, 22, 14, wall, '#9b7d42');
    for (let i = 0; i < 2; i++) { const x = cx + 52 - i * 18, y = cy + 4 + i * 4; ell(g, x, y - 5, 8, 7); fs(g, '#cfb45a', 1.2); }
    g.strokeStyle = '#4d3a22'; g.lineWidth = 1.6; for (let i = 0; i < 6; i++) { g.beginPath(); g.moveTo(cx - 62 + i * 8, cy + 6); g.lineTo(cx - 62 + i * 8, cy - 4); g.stroke(); } g.beginPath(); g.moveTo(cx - 62, cy - 1); g.lineTo(cx - 18, cy - 1); g.stroke();
  } else {
    for (const [x, y, sc] of [[-28, -4, 1], [24, -8, 1.1], [-2, -20, .9]]) { poly(g, [cx + x - 20 * sc, cy + y, cx + x, cy + y - 32 * sc, cx + x + 20 * sc, cy + y]); fs(g, '#3d352b', 1.5); poly(g, [cx + x, cy + y - 32 * sc, cx + x + 20 * sc, cy + y, cx + x + 4 * sc, cy + y]); fs(g, '#2a231b', 0); poly(g, [cx + x - 5 * sc, cy + y, cx + x, cy + y - 14 * sc, cx + x + 5 * sc, cy + y]); fs(g, '#120d08', 1); }
    for (let i = 0; i < 4; i++) { const x = cx - 48 + i * 30; line(g, [x, cy + 12, x, cy - 6], '#4d3a22', 2.2); ell(g, x, cy - 9, 4.4, 4.6); fs(g, '#d6cfbc', 1); } ell(g, cx + 36, cy + 10, 5, 3); fs(g, '#4a4034', 1); g.fillStyle = '#ff9a2a'; poly(g, [cx + 33, cy + 9, cx + 36, cy + 0, cx + 39, cy + 9]); g.fill();
  }
  if (s.kind !== 'camp') drawBanner(g, cx + (s.kind === 'castle' ? 14 : 20), cy - (s.kind === 'town' ? 62 : s.kind === 'castle' ? 66 : 28), s.fac, 13);
  return SS_CACHE[key] = { cv: c, ax: cx, ay: cy };
}
function caravanSprite() { if (SS_CACHE.car) return SS_CACHE.car; const c = mkCanvas(110, 70), g = c.getContext('2d'); g.lineJoin = 'round'; g.fillStyle = 'rgba(0,0,0,.25)'; ell(g, 52, 58, 40, 7); g.fill(); g.fillStyle = '#7a5a36'; g.fillRect(24, 28, 50, 20); g.strokeStyle = OL; g.lineWidth = 1.6; g.strokeRect(24, 28, 50, 20); for (let i = 0; i < 4; i++) { ell(g, 36 + i * 11, 24, 8, 6); fs(g, ['#a8823c', '#6a4a2c', '#b9a06a', '#8a6a3a'][i], 1.2); } for (const x of [34, 66]) { ell(g, x, 52, 8, 8); fs(g, '#4a3420', 1.6); line(g, [x, 44, x, 60], '#2a1d12', 1.4); line(g, [x - 8, 52, x + 8, 52], '#2a1d12', 1.4); } line(g, [74, 40, 94, 46], '#4a3420', 2.4);
  g.beginPath(); g.moveTo(94, 52); g.quadraticCurveTo(94, 34, 102, 36); g.lineTo(104, 30); g.lineTo(108, 36); g.lineTo(108, 50); g.lineTo(104, 58); g.lineTo(98, 58); g.closePath(); fs(g, '#7c6a58', 1.4); return SS_CACHE.car = { cv: c, ax: 55, ay: 56 }; }
