/* ---------- ландшафт: картинка ---------- */
function paintTerrain() {
  const W = WT, PX = 2, w = WW / PX, h = WH / PX, c = mkCanvas(w, h), g = c.getContext('2d'), im = g.createImageData(w, h), d = im.data, nF = W.nF, nD = W.nD;
  const E = new Float32Array(w * h), Tt = new Uint8Array(w * h);
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) { const r = W.info(i * PX, j * PX); E[j * w + i] = r.e; Tt[j * w + i] = r.t; }
  const hex = s => [parseInt(s.slice(1, 3), 16), parseInt(s.slice(3, 5), 16), parseInt(s.slice(5, 7), 16)];
  const COL = { grass: hex('#6a8239'), forest: hex('#4b6a2c'), hills: hex('#86884a'), mount: hex('#857f72'), water: hex('#2f5568'), shallow: hex('#4c7a86'), snowg: hex('#d9e2e4'), snowf: hex('#a9bcae'), snowh: hex('#c1cbcd'), steppe: hex('#b09f58'), steppef: hex('#8c8a40'), steppeh: hex('#a59152') };
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
    const k = j * w + i, x = i * PX, y = j * PX, t = Tt[k], bio = W.biomeAt(x, y); let col;
    if (t === 0) { col = E[k] > .27 ? COL.shallow : COL.water; const m = (E[k] - .1) / .2; if (E[k] <= .27) { col = [lerp(COL.water[0] - 8, COL.water[0], clamp(m, 0, 1)), lerp(COL.water[1] - 10, COL.water[1], clamp(m, 0, 1)), lerp(COL.water[2] - 8, COL.water[2], clamp(m, 0, 1))]; } }
    else if (bio === 'snow') col = t === 2 ? COL.snowf : t === 3 ? COL.snowh : t === 4 ? COL.mount : COL.snowg;
    else if (bio === 'steppe') col = t === 2 ? COL.steppef : t === 3 ? COL.steppeh : t === 4 ? COL.mount : COL.steppe;
    else col = t === 2 ? COL.forest : t === 3 ? COL.hills : t === 4 ? COL.mount : COL.grass;
    const il = i > 0 ? E[k - 1] : E[k], ir = i < w - 1 ? E[k + 1] : E[k], iu = j > 0 ? E[k - w] : E[k], idn = j < h - 1 ? E[k + w] : E[k];
    let sh = t === 0 ? 0 : ((il - ir) + (iu - idn)) * 3.2; const n = (nD(x / 22, y / 22) - .5) * 30 + (nD(x / 6 + 40, y / 6) - .5) * 14;
    if (t === 0) { sh = (nD(x / 40 + 9, y / 40) - .5) * .22; }
    d[k * 4] = clamp(col[0] + n + sh * 90, 0, 255); d[k * 4 + 1] = clamp(col[1] + n + sh * 90, 0, 255); d[k * 4 + 2] = clamp(col[2] + n * .8 + sh * 90, 0, 255); d[k * 4 + 3] = 255;
    // береговая линия
    if (t === 0 && (i < w - 1 && Tt[k + 1] !== 0 || j < h - 1 && Tt[k + w] !== 0 || i > 0 && Tt[k - 1] !== 0 || j > 0 && Tt[k - w] !== 0)) { d[k * 4] = 205; d[k * 4 + 1] = 205; d[k * 4 + 2] = 180; }
    else if (t !== 0 && (i < w - 1 && Tt[k + 1] === 0 || j < h - 1 && Tt[k + w] === 0 || i > 0 && Tt[k - 1] === 0 || j > 0 && Tt[k - w] === 0)) { d[k * 4] = 40; d[k * 4 + 1] = 36; d[k * 4 + 2] = 26; }
  }
  g.putImageData(im, 0, 0);
  const full = mkCanvas(WW, WH), f = full.getContext('2d'); f.imageSmoothingEnabled = true; f.imageSmoothingQuality = 'high'; f.drawImage(c, 0, 0, WW, WH);
  const R = mulberry(G.seed + 3), icons = [];
  for (let j = 0; j < GH; j++) for (let i = 0; i < GW; i++) { const k = j * GW + i, t = W.cells[k], bio = W.bio[k], x = i * GC, y = j * GC; if (t === 2) for (let q = 0; q < 3; q++) icons.push({ k: 'tree', bio, x: x + R() * GC, y: y + R() * GC }); else if (t === 3) icons.push({ k: 'hill', bio, x: x + R() * GC, y: y + R() * GC }); else if (t === 4) icons.push({ k: 'mount', bio, x: x + R() * GC, y: y + R() * GC, s: .8 + R() * .6 }); else if (t === 1 && R() < .05) icons.push({ k: 'bush', bio, x: x + R() * GC, y: y + R() * GC }); }
  icons.sort((a, b) => a.y - b.y); f.lineJoin = 'round';
  for (const ic of icons) { const { x, y } = ic;
    if (ic.k === 'tree') { f.fillStyle = 'rgba(0,0,0,.22)'; ell(f, x + 2, y + 1, 6, 2.4); f.fill(); if (ic.bio === 1) { poly(f, [x, y - 15, x + 6, y, x - 6, y]); fs(f, '#2f4a3a', 1.2); poly(f, [x, y - 15, x + 3, y - 8, x - 3, y - 8]); fs(f, '#e9f0f1', .5); } else { f.fillStyle = '#3b2a1a'; f.fillRect(x - 1, y - 3, 2.2, 4); ell(f, x, y - 8, 6, 6.4); fs(f, ic.bio === 2 ? '#707a2e' : '#33521f', 1.2); f.fillStyle = 'rgba(255,255,255,.2)'; ell(f, x - 2, y - 10, 2.6, 2.6); f.fill(); } }
    else if (ic.k === 'hill') { f.beginPath(); f.moveTo(x - 16, y); f.quadraticCurveTo(x, y - 17, x + 16, y); f.closePath(); fs(f, ic.bio === 1 ? '#c8d2d3' : ic.bio === 2 ? '#a59152' : '#8a8f4e', 1.1); f.strokeStyle = 'rgba(0,0,0,.18)'; f.beginPath(); f.moveTo(x + 3, y - 12); f.quadraticCurveTo(x + 10, y - 8, x + 14, y - 1); f.stroke(); }
    else if (ic.k === 'mount') { const s = ic.s * 1.5; f.fillStyle = 'rgba(0,0,0,.25)'; ell(f, x + 6 * s, y, 22 * s, 4.4 * s); f.fill(); poly(f, [x - 21 * s, y, x - 3 * s, y - 34 * s, x + 6 * s, y - 24 * s, x + 13 * s, y - 30 * s, x + 25 * s, y]); fs(f, '#8f897d', 1.6); poly(f, [x - 3 * s, y - 34 * s, x + 6 * s, y - 24 * s, x + 13 * s, y - 30 * s, x + 25 * s, y, x + 7 * s, y]); fs(f, '#6c675d', 0); poly(f, [x - 6 * s, y - 28 * s, x - 3 * s, y - 34 * s, x + 2 * s, y - 28 * s, x - 1 * s, y - 25 * s]); fs(f, '#f1f3f2', .8); }
    else { ell(f, x, y - 3, 5, 3.6); fs(f, ic.bio === 1 ? '#8ea08a' : ic.bio === 2 ? '#8c8a3e' : '#4d6b27', 1); } }
  // дороги
  f.lineCap = 'round'; f.setLineDash([7, 6]);
  for (const seg of G.roads) { f.beginPath(); f.moveTo(seg[0].x, seg[0].y); for (let i = 1; i < seg.length; i++) f.lineTo(seg[i].x, seg[i].y); f.strokeStyle = 'rgba(40,28,14,.55)'; f.lineWidth = 4.6; f.stroke(); f.strokeStyle = 'rgba(214,190,140,.9)'; f.lineWidth = 2.6; f.stroke(); } f.setLineDash([]);
  // виньетка по краям карты
  const vg = f.createRadialGradient(WW / 2, WH / 2, WH * .55, WW / 2, WH / 2, WW * .62); vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(8,6,3,.4)'); f.fillStyle = vg; f.fillRect(0, 0, WW, WH);
  return full;
}
/* ---------- спрайты поселений ---------- */
function house(g, x, y, w, h, wall, roof) { g.fillStyle = 'rgba(0,0,0,.2)'; ell(g, x + w * .55, y + 1, w * .6, 3.5); g.fill(); g.fillStyle = wall; g.fillRect(x - w / 2, y - h, w, h); g.strokeStyle = OL; g.lineWidth = 1.4; g.strokeRect(x - w / 2, y - h, w, h); poly(g, [x - w / 2 - 3, y - h, x, y - h - w * .62, x + w / 2 + 3, y - h]); fs(g, roof, 1.4); g.fillStyle = 'rgba(0,0,0,.3)'; g.fillRect(x - 2, y - h * .5, 4, h * .5); }
function tower(g, x, y, w, h, col, cap) { g.fillStyle = col; g.fillRect(x - w / 2, y - h, w, h); g.strokeStyle = OL; g.lineWidth = 1.5; g.strokeRect(x - w / 2, y - h, w, h); g.fillStyle = 'rgba(0,0,0,.22)'; g.fillRect(x, y - h, w / 2, h); for (let i = 0; i < 3; i++) { g.fillStyle = col; g.fillRect(x - w / 2 + i * w / 3 - 1, y - h - 4, w / 3 - 1, 4); g.strokeRect(x - w / 2 + i * w / 3 - 1, y - h - 4, w / 3 - 1, 4); } if (cap) { poly(g, [x - w / 2 - 2, y - h - 4, x, y - h - 4 - w * .9, x + w / 2 + 2, y - h - 4]); fs(g, cap, 1.4); } }
const SS_CACHE = {};
function settleSprite(s) {
  const key = s.id + FACTIONS[s.fac].c1; if (SS_CACHE[key]) return SS_CACHE[key]; const c = mkCanvas(170, 150), g = c.getContext('2d'), f = FACTIONS[s.fac], R = mulberry(s.id * 31); g.lineJoin = 'round'; const cx = 85, cy = 120;
  g.fillStyle = 'rgba(0,0,0,.28)'; ell(g, cx + 4, cy + 4, 70, 18); g.fill();
  const wall = s.fac === 'nord' ? '#9b8d78' : s.fac === 'emp' ? '#cfc2a2' : '#c9b48a', roof = s.fac === 'nord' ? '#5a3a24' : s.fac === 'emp' ? '#a8462f' : '#2b7568';
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
