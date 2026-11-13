/* ================= рисованная графика: бюсты на подставках ================= */
const OL = '#1b130c';
const SKINS = ['#e2b48c', '#d6a179', '#c98f66', '#b97d58', '#e8c3a0'];
const HAIRS = ['#2a1d14', '#4a3020', '#6b4423', '#8c5a2b', '#a8672e', '#b9b2a5', '#1a1a1a', '#7a2e16'];
const STEEL = '#9aa1a8', IRON = '#6f757b', LEATHER = '#6a4a2c', WOOD = '#7a5a36', GOLD = '#d2a63c';
function ell(g, x, y, rx, ry) { g.beginPath(); g.ellipse(x, y, rx, ry, 0, 0, TAU); }
function fs(g, fill, lw) { if (fill) { g.fillStyle = fill; g.fill(); } if (lw !== 0) { g.strokeStyle = OL; g.lineWidth = lw || 1.5; g.stroke(); } }
function line(g, pts, col, lw) { g.beginPath(); g.moveTo(pts[0], pts[1]); for (let i = 2; i < pts.length; i += 2) g.lineTo(pts[i], pts[i + 1]); g.strokeStyle = col; g.lineWidth = lw; g.stroke(); }
function poly(g, pts) { g.beginPath(); g.moveTo(pts[0], pts[1]); for (let i = 2; i < pts.length; i += 2) g.lineTo(pts[i], pts[i + 1]); g.closePath(); }
function mailTex(g, x, y, w, h, c) { g.strokeStyle = c; g.lineWidth = .6; let r = 0; for (let yy = y; yy < y + h; yy += 2.5, r++) for (let xx = x + (r % 2) * 1.5; xx < x + w; xx += 3) { g.beginPath(); g.arc(xx, yy, 1.3, 0, Math.PI); g.stroke(); } }
function scaleTex(g, x, y, w, h, c1, c2) { let r = 0; for (let yy = y; yy < y + h; yy += 4, r++) for (let xx = x + (r % 2) * 2.5; xx < x + w; xx += 5) { g.beginPath(); g.arc(xx, yy, 2.7, 0, Math.PI); g.fillStyle = c1; g.fill(); g.strokeStyle = c2; g.lineWidth = .6; g.stroke(); } }
function furTex(g, x, y, w, h, R, dark, light) { for (let i = 0; i < w * h / 5; i++) { const xx = x + R() * w, yy = y + R() * h; g.strokeStyle = R() < .5 ? dark : light; g.lineWidth = 1; g.beginPath(); g.moveTo(xx, yy); g.lineTo(xx + (R() - .5) * 3, yy + 2.5 + R() * 3); g.stroke(); } }

function drawBase(g, cx, cy, rx, ry, pal) {
  g.fillStyle = '#14110d'; ell(g, cx, cy + 5, rx, ry); g.fill(); g.fillRect(cx - rx, cy, rx * 2, 5);
  g.strokeStyle = OL; g.lineWidth = 1.4; ell(g, cx, cy + 5, rx, ry); g.stroke();
  const gr = g.createLinearGradient(cx - rx, 0, cx + rx, 0); gr.addColorStop(0, '#7b756b'); gr.addColorStop(.5, '#4a453d'); gr.addColorStop(1, '#26221d');
  ell(g, cx, cy, rx, ry); fs(g, gr, 1.4);
  g.strokeStyle = pal.c1; g.lineWidth = 2.2; ell(g, cx, cy, rx - 2.6, ry - 1.6); g.stroke();
  g.strokeStyle = 'rgba(255,255,255,.18)'; g.lineWidth = .8; g.beginPath(); g.ellipse(cx, cy, rx - 1, ry - .6, 0, Math.PI * 1.05, Math.PI * 1.6); g.stroke();
}
function torsoPath(g) { g.beginPath(); g.moveTo(21.5, 73); g.bezierCurveTo(20.5, 65, 17.5, 57, 18.5, 50.5); g.quadraticCurveTo(19.5, 46, 27, 44.6); g.lineTo(31.5, 42.6); g.lineTo(43.5, 42.6); g.lineTo(48, 44.6); g.quadraticCurveTo(55.5, 46, 56.5, 50.5); g.bezierCurveTo(57.5, 57, 54.5, 65, 53.5, 73); g.quadraticCurveTo(37.5, 79, 21.5, 73); g.closePath(); }
/* --- руки: плечо → локоть → кисть, цвет и фактура рукава по броне --- */
const SH_L = [20.5, 50.5], SH_R = [54.5, 50.5];
const FISTS = { sword: [58.4, 57.5], sabre: [58.4, 57.5], axe: [58.3, 56], mace: [58.3, 56], club: [58, 56], spear: [59, 56], halberd: [59, 52], lance: [59.4, 54], bow: [64.6, 42], xbow: [55, 55] };
function limbPath(g, x1, y1, x2, y2, w1, w2) { const a = Math.atan2(y2 - y1, x2 - x1), nx = -Math.sin(a), ny = Math.cos(a); g.beginPath(); g.moveTo(x1 + nx * w1, y1 + ny * w1); g.lineTo(x2 + nx * w2, y2 + ny * w2); g.arc(x2, y2, w2, a + Math.PI / 2, a - Math.PI / 2, true); g.lineTo(x1 - nx * w1, y1 - ny * w1); g.arc(x1, y1, w1, a - Math.PI / 2, a + Math.PI / 2, true); g.closePath(); }
function elbowOf(S, F, sgn) { const L1 = 11, L2 = 10.5, dx = F[0] - S[0], dy = F[1] - S[1], d = Math.min(L1 + L2 - .5, Math.max(2, Math.hypot(dx, dy))), a = Math.atan2(dy, dx), k = (L1 * L1 - L2 * L2 + d * d) / (2 * d), h = Math.sqrt(Math.max(0, L1 * L1 - k * k)); return [S[0] + Math.cos(a) * k - Math.sin(a) * h * sgn, S[1] + Math.sin(a) * k + Math.cos(a) * h * sgn]; }
function sleeveOf(L, pal, v) { const a = L.armor;
  if (a === 'ribs') return { c: '#d8d0b8', bone: 1 }; if (a === 'fur' || a === 'rags') return { c: v.skin, bare: 1, cuff: a === 'fur' ? '#3a2a1a' : null };
  if (a === 'mail' || a === 'mailtab' || a === 'mailfur' || a === 'scale' || a === 'goldscale') return { c: '#868b90', mail: 1 }; if (a === 'plate') return { c: '#aab1b8', plate: 1 };
  if (a === 'padded') return { c: '#b59c6c', quilt: 1 }; if (a === 'lamellar') return { c: '#6d5639', cuff: '#3a2a1a' }; if (a === 'goldlam') return { c: '#8a6a2c', cuff: GOLD }; if (a === 'habit') return { c: '#5a4630' };
  return { c: pal.c1, k: -.14, cuff: shade(pal.c1, -.34) }; }
function drawArm(g, S, F, sgn, L, pal, v, dark) {
  const sl = sleeveOf(L, pal, v), E = elbowOf(S, F, sgn), w = sl.bone ? 1.5 : 4, c = shade(sl.c, (sl.k || 0) + (dark ? -.16 : 0));
  const seg = (a, b, w1, w2) => { limbPath(g, a[0], a[1], b[0], b[1], w1, w2); fs(g, c, 0); g.save(); limbPath(g, a[0], a[1], b[0], b[1], w1, w2); g.clip();
    if (sl.mail) { mailTex(g, Math.min(a[0], b[0]) - 5, Math.min(a[1], b[1]) - 5, Math.abs(a[0] - b[0]) + 10, Math.abs(a[1] - b[1]) + 10, '#53575b'); }
    if (sl.quilt) { const an = Math.atan2(b[1] - a[1], b[0] - a[0]); for (let k = -1; k <= 1; k++) line(g, [a[0] - Math.sin(an) * k * 2, a[1] + Math.cos(an) * k * 2, b[0] - Math.sin(an) * k * 2, b[1] + Math.cos(an) * k * 2], shade(sl.c, -.42), .7); }
    const gr = g.createLinearGradient(Math.min(a[0], b[0]) - w1, 0, Math.max(a[0], b[0]) + w1, 0); gr.addColorStop(0, 'rgba(255,240,200,.2)'); gr.addColorStop(.5, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,.36)'); g.fillStyle = gr; g.fillRect(0, 30, 80, 60);
    g.restore(); limbPath(g, a[0], a[1], b[0], b[1], w1, w2); fs(g, null, 1.3); };
  seg(S, E, w + .7, w); seg(E, F, w, w - .7);
  if (sl.plate) { ell(g, E[0], E[1], 3.6, 3.6); fs(g, shade(sl.c, dark ? -.06 : .12), 1.1); ell(g, S[0], S[1] - .5, 5.6, 4.6); fs(g, shade(sl.c, dark ? -.1 : .1), 1.3); g.fillStyle = 'rgba(255,255,255,.3)'; ell(g, S[0] - 1.5, S[1] - 2, 2, 1.3); g.fill(); }
  else if (!sl.bone && !sl.bare) { g.save(); limbPath(g, S[0], S[1], E[0], E[1], w + .7, w); g.clip(); g.fillStyle = 'rgba(0,0,0,.16)'; g.fillRect(S[0] - 8, S[1] + 2, 16, 3); g.restore(); }
  if (sl.cuff) { const an = Math.atan2(F[1] - E[1], F[0] - E[0]), mx = F[0] - Math.cos(an) * 3.2, my = F[1] - Math.sin(an) * 3.2; g.lineCap = 'butt'; line(g, [mx - Math.sin(an) * 2.7, my + Math.cos(an) * 2.7, mx + Math.sin(an) * 2.7, my - Math.cos(an) * 2.7], sl.cuff, 1.7); g.lineCap = 'round'; }
  return E;
}

function drawTorso(g, L, pal, R) {
  const a = L.armor; let col = pal.c1;
  if (a === 'padded') col = '#b59c6c'; else if (a === 'mail' || a === 'mailtab' || a === 'mailfur') col = '#868b90'; else if (a === 'scale') col = '#8f8f8a';
  else if (a === 'habit') col = '#5a4630'; else if (a === 'rags') col = '#4a4436'; else if (a === 'ribs') col = '#2a251d';
  else if (a === 'goldscale') col = '#c79d3a'; else if (a === 'lamellar') col = '#6d5639'; else if (a === 'goldlam') col = '#8a6a2c'; else if (a === 'plate') col = '#aab1b8'; else if (a === 'fur') col = '#5f4930';
  torsoPath(g); fs(g, col, 0);
  g.save(); torsoPath(g); g.clip();
  if (a === 'rags') { g.fillStyle = '#2a251c'; for (let i = 0; i < 6; i++) { ell(g, 16 + i * 8 + (i % 2) * 3, 52 + (i * 7) % 18, 2.4, 1.8); g.fill(); } g.fillStyle = shade(col, -.3); poly(g, [10, 70, 16, 76, 22, 70, 28, 77, 34, 70, 40, 77, 46, 70, 52, 77, 58, 70, 64, 76, 64, 80, 10, 80]); g.fill(); }
  if (a === 'ribs') { line(g, [36, 44, 36, 72], '#d8d0b8', 3); for (let y = 49; y < 70; y += 4.4) { const w = 15 - Math.abs(y - 58) * .3; line(g, [36, y, 36 - w, y + 3], '#d8d0b8', 2.2); line(g, [36, y, 36 + w, y + 3], '#cfc4a6', 2.2); } g.fillStyle = '#5a4a36'; g.fillRect(10, 70, 54, 4); }
  if (a === 'habit') { line(g, [36, 44, 36, 78], shade(col, -.35), 1.2); line(g, [20, 46, 14, 78], shade(col, -.25), .9); line(g, [52, 46, 58, 78], shade(col, -.25), .9); g.fillStyle = '#d8c9a0'; g.fillRect(10, 61, 52, 3.4); line(g, [47, 63, 49, 76], '#d8c9a0', 1.6); g.fillStyle = '#d8c9a0'; ell(g, 49, 77, 1.6, 1.6); g.fill(); line(g, [36, 49, 36, 56], '#c9a24a', 1.6); line(g, [33, 52, 39, 52], '#c9a24a', 1.6); }
  if (a === 'tunic') { g.fillStyle = shade(col, -.25); g.fillRect(10, 62, 52, 3); line(g, [36, 44, 36, 62], shade(col, -.3), 1); g.fillStyle = shade(col, .25); poly(g, [31, 43, 36, 50, 43, 43]); g.fill(); }
  if (a === 'padded') { for (let x = 14; x < 60; x += 4.5) line(g, [x, 44, x + (x - 36) * .12, 76], shade(col, -.28), .9); g.fillStyle = pal.c1; g.fillRect(10, 60, 52, 4); }
  if (a === 'mail' || a === 'mailtab' || a === 'mailfur') { mailTex(g, 10, 43, 54, 36, '#53575b'); mailTex(g, 11.5, 44, 54, 36, 'rgba(230,235,240,.35)'); }
  if (a === 'mailtab') { g.fillStyle = pal.c1; poly(g, [27, 43, 47, 43, 50, 78, 24, 78]); g.fill(); g.fillStyle = pal.c2; poly(g, [36, 43, 47, 43, 50, 78, 37, 78]); g.fill(); line(g, [27, 43, 24, 78], OL, .8); line(g, [47, 43, 50, 78], OL, .8); g.fillStyle = '#3a2a1a'; g.fillRect(22, 62, 30, 3); }
  if (a === 'scale' || a === 'goldscale') scaleTex(g, 10, 44, 54, 36, a === 'scale' ? '#a3a39c' : '#dcb44a', a === 'scale' ? '#4c4c48' : '#6e5216');
  if (a === 'lamellar' || a === 'goldlam') { const c = a === 'lamellar' ? '#8a7048' : '#d0a53e'; for (let y = 46; y < 78; y += 5) { g.fillStyle = c; g.fillRect(10, y, 54, 3.6); for (let x = 11; x < 64; x += 3.4) line(g, [x, y, x, y + 3.6], 'rgba(20,12,4,.55)', .6); } g.fillStyle = pal.c1; g.fillRect(10, 61, 54, 3.5); }
  if (a === 'plate') { g.fillStyle = 'rgba(255,255,255,.3)'; ell(g, 28, 54, 9, 6); g.fill(); line(g, [36, 44, 36, 76], '#5c6268', 1); line(g, [16, 62, 56, 62], '#5c6268', 1); g.fillStyle = pal.c1; poly(g, [30, 43, 36, 52, 43, 43]); g.fill(); }
  if (a === 'fur') { g.fillStyle = '#7a6040'; g.fillRect(28, 43, 16, 36); line(g, [28, 43, 28, 78], OL, .7); line(g, [44, 43, 44, 78], OL, .7); g.fillStyle = '#3a2a1a'; g.fillRect(10, 62, 54, 3.4); }
  if (a === 'fur' || a === 'mailfur') { g.fillStyle = '#4a3826'; g.beginPath(); g.moveTo(10, 60); g.bezierCurveTo(10, 46, 22, 42, 31, 42); g.lineTo(31, 50); g.bezierCurveTo(24, 52, 20, 58, 19, 66); g.closePath(); g.fill(); g.beginPath(); g.moveTo(62, 60); g.bezierCurveTo(62, 46, 52, 42, 43, 42); g.lineTo(43, 50); g.bezierCurveTo(50, 52, 54, 58, 55, 66); g.closePath(); g.fill(); furTex(g, 10, 42, 22, 24, R, '#2c2014', '#8a7150'); furTex(g, 42, 42, 22, 24, R, '#2c2014', '#8a7150'); }
  const sh = g.createLinearGradient(12, 0, 60, 0); sh.addColorStop(0, 'rgba(255,240,200,.16)'); sh.addColorStop(.45, 'rgba(0,0,0,0)'); sh.addColorStop(1, 'rgba(0,0,0,.42)'); g.fillStyle = sh; g.fillRect(8, 40, 60, 40);
  const sv = g.createLinearGradient(0, 60, 0, 78); sv.addColorStop(0, 'rgba(0,0,0,0)'); sv.addColorStop(1, 'rgba(0,0,0,.4)'); g.fillStyle = sv; g.fillRect(8, 60, 60, 20);
  g.restore(); torsoPath(g); fs(g, null, 1.6);
  if (a === 'plate' || a === 'scale' || a === 'goldscale' || a === 'goldlam') { const pc = a === 'plate' ? '#b9c0c6' : a === 'scale' ? '#a9a9a2' : '#d9b248'; ell(g, 18, 50, 7, 5); fs(g, pc, 1.3); ell(g, 54, 50, 7, 5); fs(g, shade(pc.length === 7 ? pc : '#b9c0c6', -.25), 1.3); }
}
function facePath(g) { g.beginPath(); g.moveTo(27, 25); g.bezierCurveTo(27, 13, 47.5, 13, 47.5, 25); g.bezierCurveTo(48, 33, 45, 41, 38, 42.5); g.bezierCurveTo(31, 41, 27, 34, 27, 25); g.closePath(); }
function drawUndeadHead(g, v) { // череп или гнилое лицо: пустые глазницы с тусклыми огоньками
  const skin = v.skin, sk = v.undead === 'skel';
  g.fillStyle = shade(skin, -.35); poly(g, [32.5, 36, 41.5, 36, 42.5, 46, 31.5, 46]); g.fill(); g.strokeStyle = OL; g.lineWidth = 1.2; g.stroke();
  if (sk) for (let y = 38; y < 46; y += 2.6) line(g, [33, y, 41, y], shade(skin, -.55), .8); // позвонки шеи
  facePath(g); fs(g, skin, 0);
  g.save(); facePath(g); g.clip();
  const sh = g.createLinearGradient(26, 0, 49, 0); sh.addColorStop(0, 'rgba(20,25,10,.45)'); sh.addColorStop(.45, 'rgba(0,0,0,0)'); sh.addColorStop(1, 'rgba(0,0,0,.25)'); g.fillStyle = sh; g.fillRect(24, 10, 28, 36);
  if (sk) { g.fillStyle = shade(skin, -.4); g.fillRect(26, 33.5, 24, 1.2); } else { g.fillStyle = 'rgba(70,30,30,.35)'; ell(g, 31, 33, 3, 2); g.fill(); ell(g, 45, 24, 2.2, 3); g.fill(); }
  g.restore(); facePath(g); fs(g, null, 1.4);
  g.fillStyle = '#120c08'; ell(g, 35.6, 29, sk ? 3 : 2.3, sk ? 2.8 : 1.9); g.fill(); ell(g, 43.4, 29, sk ? 2.7 : 2.1, sk ? 2.6 : 1.8); g.fill(); // глазницы
  g.fillStyle = sk ? '#9fe3c8' : '#d8e07a'; ell(g, 35.8, 29.2, .9, .9); g.fill(); ell(g, 43.5, 29.2, .8, .8); g.fill();
  g.fillStyle = '#120c08'; poly(g, [39.4, 31.5, 40.8, 34.2, 38.4, 34.2]); g.fill(); // нос
  if (sk) { g.fillStyle = '#f2ecdc'; g.fillRect(35, 37, 9, 2.6); g.strokeStyle = OL; g.lineWidth = .8; g.strokeRect(35, 37, 9, 2.6); for (let x = 36.5; x < 44; x += 1.6) line(g, [x, 37, x, 39.6], OL, .6); }
  else { line(g, [35.5, 38.4, 43.5, 37.6], '#2a1a12', 1.3); line(g, [37, 38.4, 37.5, 39.6], '#e6e0c8', .9); line(g, [41, 38, 41.4, 39.2], '#e6e0c8', .9); line(g, [44, 22, 46.5, 31], '#5a2a22', .8); }
}
function drawHead(g, L, v) {
  if (v.undead) return drawUndeadHead(g, v);
  const skin = v.skin, hair = v.hair;
  g.fillStyle = shade(skin, -.3); poly(g, [31.5, 36, 42.5, 36, 44, 46, 30, 46]); g.fill(); g.strokeStyle = OL; g.lineWidth = 1.2; g.stroke();
  ell(g, 26.9, 29.6, 2, 3.1); fs(g, shade(skin, -.14), 1.1); ell(g, 48, 29.6, 1.9, 3); fs(g, shade(skin, -.3), 1.1);
  facePath(g); fs(g, skin, 0);
  g.save(); facePath(g); g.clip();
  g.fillStyle = 'rgba(190,80,50,.16)'; ell(g, 32, 33.6, 3.6, 2.4); g.fill(); ell(g, 44.6, 33.6, 3, 2.2); g.fill(); g.fillStyle = 'rgba(255,240,215,.2)'; ell(g, 33.6, 21, 5, 3.4); g.fill();
  const sh = g.createLinearGradient(26, 0, 49, 0); sh.addColorStop(0, 'rgba(60,25,10,.42)'); sh.addColorStop(.4, 'rgba(60,25,10,0)'); sh.addColorStop(1, 'rgba(255,230,200,.12)'); g.fillStyle = sh; g.fillRect(24, 10, 28, 36);
  g.fillStyle = 'rgba(40,15,5,.3)'; ell(g, 36, 29.4, 2.6, 1.7); g.fill(); ell(g, 43.4, 29.4, 2.4, 1.7); g.fill();
  if (v.beard === 0) { g.fillStyle = 'rgba(40,25,15,.22)'; g.fillRect(26, 34, 24, 10); }
  if (v.beard >= 1) { g.fillStyle = hair; g.beginPath(); g.moveTo(26, 30); g.lineTo(31, 34); g.lineTo(35, 35.5); g.lineTo(43, 35.5); g.lineTo(46, 33.5); g.lineTo(49, 30); g.lineTo(49, 46); g.lineTo(26, 46); g.closePath(); g.fill(); for (let i = 0; i < 14; i++) line(g, [28 + i * 1.5, 36 + (i % 3), 28.5 + i * 1.5, 43], shade(hair, i % 2 ? -.3 : .2), .6); }
  g.restore();
  facePath(g); fs(g, null, 1.4);
  if (v.beard >= 2) { g.beginPath(); g.moveTo(29.5, 38); g.bezierCurveTo(29, 46, 33, 53, 38, 54); g.bezierCurveTo(43, 52, 46, 46, 46, 38); g.bezierCurveTo(42, 43, 34, 43, 29.5, 38); fs(g, hair, 1.2); for (let i = 0; i < 7; i++) line(g, [32.5 + i * 1.8, 43.5, 33.5 + i * 1.3, 50.5 - Math.abs(i - 3)], shade(hair, i % 2 ? -.3 : .22), .7); }
  if (v.stache) { g.strokeStyle = hair; g.lineWidth = 1.7; g.beginPath(); g.moveTo(39.4, 36.4); g.quadraticCurveTo(35, 36, 33.4, 41.5); g.stroke(); g.beginPath(); g.moveTo(40.4, 36.4); g.quadraticCurveTo(44.4, 36, 45.6, 41.5); g.stroke(); }
  line(g, [32.8, 26.6, 37.8, 27.8], shade(hair, -.35), 1.7); line(g, [41, 27.8, 46, 26.4], shade(hair, -.35), 1.7);
  g.fillStyle = '#ebe3d2'; ell(g, 36, 29.5, 1.9, 1.15); g.fill(); ell(g, 43.5, 29.5, 1.75, 1.1); g.fill();
  g.fillStyle = '#120a06'; ell(g, 36.3, 29.5, 1.05, 1.05); g.fill(); ell(g, 43.7, 29.5, 1, 1.05); g.fill();
  line(g, [34, 28.5, 36, 28, 38, 28.6], OL, .8); line(g, [41.7, 28.6, 43.5, 28, 45.4, 28.5], OL, .8);
  if (hair === '#b9b2a5') { line(g, [34.2, 31.6, 37.4, 32], shade(skin, -.3), .6); line(g, [42.2, 32, 45, 31.6], shade(skin, -.3), .6); line(g, [33, 23.4, 44.6, 23], shade(skin, -.24), .6); }
  g.strokeStyle = shade(skin, -.42); g.lineWidth = 1.1; g.beginPath(); g.moveTo(40.4, 29.5); g.lineTo(42.1, 34); g.quadraticCurveTo(41, 35.4, 39.2, 34.6); g.stroke(); line(g, [39.9, 30, 40.9, 33.4], 'rgba(255,240,215,.4)', .8); g.fillStyle = shade(skin, -.5); ell(g, 41.5, 34.5, .55, .4); g.fill();
  if (v.beard < 1) { line(g, [36.4, 38, 39.6, 38.5, 42.8, 37.9], shade(skin, -.5), 1.1); line(g, [38, 40, 41.4, 40], 'rgba(255,235,215,.28)', .8); } else line(g, [37, 38.3, 42.2, 38.2], shade(hair, -.55), 1);
  if (v.scar) line(g, [44.5, 23, 46, 34], '#8a3a30', .9);
}
/* обрубок шеи: у живых — кровь и позвонок, у скелета — сломанный позвонок, у мертвеца — тёмная жижа */
function drawStump(g, v) {
  const sk = v.undead === 'skel', zb = v.undead === 'zombie', meat = sk ? '#cfc4a6' : zb ? '#3b4a24' : '#8f1a12';
  g.fillStyle = sk ? '#2a251d' : shade(v.skin, -.3); poly(g, [31.5, 38, 42.5, 38, 44, 46, 30, 46]); g.fill(); g.strokeStyle = OL; g.lineWidth = 1.2; g.stroke();
  ell(g, 37, 38.5, 6, 2.6); fs(g, meat, 1.2); if (!sk) { ell(g, 37, 38.4, 4, 1.5); g.fillStyle = zb ? '#1e2612' : '#5a0c08'; g.fill(); }
  ell(g, 37, 38.2, 1.6, 1.1); g.fillStyle = '#efe8d6'; g.fill();
  if (!sk) { g.fillStyle = meat; for (let i = 0; i < 4; i++) { const x = 31 + i * 3.2; g.beginPath(); g.moveTo(x, 40); g.quadraticCurveTo(x + .8, 44 + i % 2 * 3, x + 1.6, 40); g.fill(); } }
}
function plume(g, x, y, col, big) { g.beginPath(); g.moveTo(x, y); g.bezierCurveTo(x - 4, y - (big ? 16 : 10), x - 18, y - (big ? 14 : 9), x - (big ? 22 : 15), y - 1); g.bezierCurveTo(x - 14, y - 5, x - 7, y - 4, x, y); fs(g, col, 1.2); for (let i = 0; i < 5; i++) line(g, [x - 3 - i * 3, y - 2, x - 5 - i * 3.4, y - (big ? 10 : 6)], 'rgba(0,0,0,.28)', .7); }
function drawHelm(g, L, v, pal, R) {
  const h = L.helm, hair = v.hair;
  const dome = (c, top) => { g.beginPath(); g.moveTo(25.6, 26); g.bezierCurveTo(25, 16, 30, top, 37.5, top); g.bezierCurveTo(45, top, 49.6, 16, 49.2, 26); g.closePath(); fs(g, c, 1.5); g.fillStyle = 'rgba(255,255,255,.28)'; ell(g, 33, top + 6, 3.5, 4.5); g.fill(); g.fillStyle = 'rgba(0,0,0,.22)'; g.beginPath(); g.moveTo(42, top + 1); g.bezierCurveTo(47, top + 4, 49.4, 18, 49.2, 26); g.lineTo(43, 26); g.closePath(); g.fill(); };
  const band = c => { g.fillStyle = c; g.fillRect(25.2, 23.4, 24.4, 3.2); g.strokeStyle = OL; g.lineWidth = 1.1; g.strokeRect(25.2, 23.4, 24.4, 3.2); };
  const aventail = () => { g.beginPath(); g.moveTo(25.6, 25); g.lineTo(23.5, 44); g.lineTo(31, 47); g.lineTo(29.6, 33); g.closePath(); fs(g, '#7e8388', 1.1); g.beginPath(); g.moveTo(49.2, 25); g.lineTo(51.5, 44); g.lineTo(44.5, 47); g.lineTo(47, 33); g.closePath(); fs(g, '#63686d', 1.1); g.save(); g.beginPath(); g.rect(23, 25, 9, 22); g.rect(44, 25, 8, 22); g.clip(); mailTex(g, 22, 26, 32, 22, '#3f4347'); g.restore(); };
  if (h === 'none') {
    if (v.bald) return; g.beginPath(); g.moveTo(25.8, 27); g.bezierCurveTo(24, 14, 31, 10.5, 37.5, 10.5); g.bezierCurveTo(45, 10.5, 51, 15, 48.6, 27); g.bezierCurveTo(47, 21, 44, 18.5, 40, 19.5); g.bezierCurveTo(35, 17, 29, 19, 27.6, 24); g.closePath(); fs(g, hair, 1.3);
    for (let i = 0; i < 6; i++) line(g, [29 + i * 3.2, 13.5 + (i % 2), 30 + i * 3, 18], shade(hair, i % 2 ? .25 : -.3), .7);
  } else if (h === 'hood') {
    const c = pal.c1 === '#3b3a36' ? '#4a4034' : shade(pal.c1, -.35) ; g.beginPath(); g.moveTo(23, 44); g.bezierCurveTo(21, 20, 28, 8.5, 38, 8.5); g.bezierCurveTo(48, 8.5, 53.5, 20, 51.5, 44); g.lineTo(47, 44); g.bezierCurveTo(49.5, 30, 46, 19.5, 38, 19.5); g.bezierCurveTo(30, 19.5, 26.5, 30, 28, 44); g.closePath(); g.fillStyle = typeof c === 'string' ? c : '#4a4034'; g.fill(); g.strokeStyle = OL; g.lineWidth = 1.4; g.stroke();
    g.fillStyle = 'rgba(0,0,0,.3)'; g.beginPath(); g.moveTo(28, 26); g.bezierCurveTo(30, 19.5, 46, 19.5, 47.6, 26); g.bezierCurveTo(44, 23.5, 32, 23.5, 28, 26); g.fill();
  } else if (h === 'cap') { dome('#7a5633', 11.5); line(g, [37.5, 11.5, 37.5, 25], 'rgba(0,0,0,.4)', .9); band('#5a3d22'); }
  else if (h === 'furcap') { g.beginPath(); g.moveTo(24, 26); g.bezierCurveTo(22, 12, 31, 8, 37.5, 8); g.bezierCurveTo(45, 8, 53, 12, 51, 26); g.bezierCurveTo(44, 22.5, 31, 22.5, 24, 26); fs(g, '#6a4f33', 1.4); furTex(g, 24, 9, 27, 15, R, '#33241a', '#a08260'); g.beginPath(); g.moveTo(31, 11); g.bezierCurveTo(34, 5, 41, 5, 44, 11); fs(g, pal.c1, 1.1); }
  else if (h === 'nasal') { dome(STEEL, 9); band(IRON); g.fillStyle = IRON; g.fillRect(39, 25, 2.8, 9.5); g.strokeStyle = OL; g.lineWidth = 1; g.strokeRect(39, 25, 2.8, 9.5); line(g, [37.5, 9.5, 37.5, 23], 'rgba(0,0,0,.35)', .9); }
  else if (h === 'kettle') { dome(STEEL, 11); ell(g, 37.5, 24.2, 16.5, 3.8); fs(g, IRON, 1.3); g.strokeStyle = 'rgba(255,255,255,.3)'; g.lineWidth = .8; g.beginPath(); g.ellipse(37.5, 23.6, 15, 2.8, 0, Math.PI, Math.PI * 1.6); g.stroke(); }
  else if (h === 'flat') {
    aventail(); g.beginPath(); g.moveTo(25.4, 26.5); g.lineTo(25.8, 13); g.quadraticCurveTo(26, 10, 29, 10); g.lineTo(46, 10); g.quadraticCurveTo(49, 10, 49.2, 13); g.lineTo(49.6, 26.5); g.closePath(); fs(g, STEEL, 1.5);
    g.fillStyle = 'rgba(0,0,0,.22)'; g.fillRect(42.5, 10.5, 6.8, 15.5); g.fillStyle = 'rgba(255,255,255,.25)'; g.fillRect(28, 11.5, 4, 13);
    g.fillStyle = IRON; g.fillRect(25.2, 23, 24.6, 3.5); g.fillRect(36, 10, 3, 16); g.strokeStyle = OL; g.lineWidth = 1; g.strokeRect(25.2, 23, 24.6, 3.5); g.strokeRect(36, 10, 3, 13);
  } else if (h === 'spectacle') { aventail(); dome(STEEL, 9.5); band(GOLD); g.strokeStyle = IRON; g.lineWidth = 2; g.beginPath(); g.arc(35.6, 29.2, 3.6, Math.PI * 1.05, Math.PI * 2.05); g.stroke(); g.beginPath(); g.arc(43.6, 29.2, 3.4, Math.PI * .95, Math.PI * 1.95); g.stroke(); g.fillStyle = IRON; g.fillRect(38.8, 25, 2.6, 8); line(g, [37.5, 10, 37.5, 23], GOLD, 1.3); }
  else if (h === 'pointed') {
    g.beginPath(); g.moveTo(25.6, 25); g.bezierCurveTo(27, 15, 33, 11, 37.5, 2.5); g.bezierCurveTo(42, 11, 48, 15, 49.2, 25); g.closePath(); fs(g, L.armor === 'goldlam' ? GOLD : STEEL, 1.5); g.fillStyle = 'rgba(0,0,0,.2)'; g.beginPath(); g.moveTo(37.5, 2.5); g.bezierCurveTo(42, 11, 48, 15, 49.2, 25); g.lineTo(42, 25); g.closePath(); g.fill();
    line(g, [37.5, 3, 34, -3, 30, 1], pal.c2 === '#e6c868' ? '#a02c22' : pal.c1, 2);
    g.beginPath(); g.moveTo(23.4, 27); g.bezierCurveTo(25, 20, 50, 20, 51.6, 27); g.bezierCurveTo(46, 24.5, 30, 24.5, 23.4, 27); fs(g, '#5f4930', 1.2); furTex(g, 24, 21, 27, 6, R, '#2c2014', '#9a7f58');
    g.beginPath(); g.moveTo(25.6, 26); g.lineTo(24.6, 42); g.lineTo(30, 44); g.lineTo(29, 31); g.closePath(); fs(g, '#6d5639', 1); g.beginPath(); g.moveTo(49.2, 26); g.lineTo(50.6, 42); g.lineTo(45.6, 44); g.lineTo(47, 31); g.closePath(); fs(g, '#523f28', 1);
  } else if (h === 'turban' || h === 'turbanm') {
    if (h === 'turbanm') { aventail(); dome(STEEL, 12); }
    const cl = '#e6dcc0', wrap = () => { g.beginPath(); g.moveTo(24.2, 27); g.bezierCurveTo(21.5, 14, 29, 5.5, 37.5, 5.5); g.bezierCurveTo(46, 5.5, 53.5, 14, 50.8, 27); g.bezierCurveTo(44, 24, 31, 24, 24.2, 27); g.closePath(); };
    wrap(); fs(g, cl, 1.5); g.save(); wrap(); g.clip();
    for (let i = 0; i < 4; i++) line(g, [22, 25 - i * 5.5, 38, 20 - i * 5.5, 54, 25 - i * 5.5], shade(cl, -.24), 1.2);
    g.fillStyle = 'rgba(0,0,0,.2)'; g.fillRect(44, 4, 12, 26); g.fillStyle = 'rgba(255,255,255,.3)'; ell(g, 31, 14, 3.4, 5); g.fill(); g.restore();
    line(g, [24.6, 25, 37.5, 23, 50.4, 25], pal.c1, 2.8); ell(g, 41, 22.6, 1.9, 1.9); fs(g, GOLD, .9);
    if (h === 'turbanm') { g.beginPath(); g.moveTo(35.6, 7); g.lineTo(37.5, -1.5); g.lineTo(39.4, 7); g.closePath(); fs(g, STEEL, 1.1); }
  } else if (h === 'crest') {
    plume(g, 46, 9.5, '#a3271f', true); dome('#b8a26a', 10); band(GOLD);
    g.beginPath(); g.moveTo(25.6, 25); g.lineTo(26.4, 36); g.lineTo(31.5, 40.5); g.lineTo(31, 30); g.closePath(); fs(g, '#b8a26a', 1.1); g.beginPath(); g.moveTo(49.2, 25); g.lineTo(48.6, 36); g.lineTo(45, 40); g.lineTo(46.4, 30); g.closePath(); fs(g, '#8f7c4c', 1.1);
  } else if (h === 'great') {
    plume(g, 44, 9.5, pal.c1, true);
    g.beginPath(); g.moveTo(25, 14); g.quadraticCurveTo(25, 9.5, 29.5, 9.5); g.lineTo(45.5, 9.5); g.quadraticCurveTo(50, 9.5, 50, 14); g.lineTo(49.4, 38); g.quadraticCurveTo(44, 44.5, 38, 44.5); g.quadraticCurveTo(31, 44.5, 25.6, 38); g.closePath(); fs(g, '#aeb5bc', 1.6);
    g.fillStyle = 'rgba(0,0,0,.24)'; g.fillRect(43, 10, 7, 30); g.fillStyle = 'rgba(255,255,255,.26)'; g.fillRect(27.5, 11, 3.6, 24);
    g.fillStyle = GOLD; g.fillRect(38.4, 9.5, 2.6, 34); g.fillRect(25.4, 26.4, 24.4, 2.4); g.fillStyle = '#0b0705'; g.fillRect(30, 26.8, 7.4, 1.7); g.fillRect(42, 26.8, 6, 1.7);
    for (let i = 0; i < 3; i++) { g.fillRect(43 + i * 2, 33, 1, 1); g.fillRect(43 + i * 2, 36, 1, 1); }
  } else if (h === 'mask') {
    g.save(); g.translate(46, 10); for (let i = 0; i < 6; i++) { g.beginPath(); g.moveTo(-2, 2); g.quadraticCurveTo(-8 - i * 2.6, -14 + i * 1.5, -16 - i * 1.6, -5 + i * 2.6); g.strokeStyle = i % 2 ? '#e8e2d0' : '#a3271f'; g.lineWidth = 3.4; g.stroke(); } g.restore();
    facePath(g); fs(g, '#d9b043', 1.4); g.save(); facePath(g); g.clip(); const sh = g.createLinearGradient(26, 0, 49, 0); sh.addColorStop(0, 'rgba(90,50,0,.45)'); sh.addColorStop(.5, 'rgba(255,240,170,.3)'); sh.addColorStop(1, 'rgba(90,50,0,.2)'); g.fillStyle = sh; g.fillRect(24, 10, 28, 36); g.restore();
    g.fillStyle = '#1a0f05'; ell(g, 35.8, 29.4, 2, 1.2); g.fill(); ell(g, 43.4, 29.4, 1.9, 1.2); g.fill(); line(g, [40.3, 29, 41.8, 34.4, 39.4, 35], '#7a5a16', 1.1); line(g, [36.6, 38.4, 42.6, 38.2], '#7a5a16', 1.1); line(g, [32.6, 26.6, 37.8, 27.6], '#7a5a16', 1.2); line(g, [41, 27.6, 46, 26.4], '#7a5a16', 1.2);
    dome('#d9b043', 9.5); band('#a3271f');
  } else if (h === 'coif') { aventail(); dome('#7e8388', 11); g.save(); g.beginPath(); g.rect(25, 11, 25, 15); g.clip(); mailTex(g, 25, 12, 26, 14, '#3f4347'); g.restore(); }
}
function drawShield(g, L, pal, R) {
  const s = L.shield; if (!s || s === 'none') return;
  if (s === 'round') {
    const cx = 23, cy = 58, r = 14.5; ell(g, cx, cy, r, r); fs(g, pal.c1, 0); g.save(); ell(g, cx, cy, r, r); g.clip();
    g.fillStyle = pal.c2; g.beginPath(); g.moveTo(cx, cy); g.arc(cx, cy, r, -Math.PI / 2, 0); g.closePath(); g.fill(); g.beginPath(); g.moveTo(cx, cy); g.arc(cx, cy, r, Math.PI / 2, Math.PI); g.closePath(); g.fill();
    for (let x = cx - r; x < cx + r; x += 5) line(g, [x, cy - r, x, cy + r], 'rgba(0,0,0,.2)', .7);
    const sh = g.createRadialGradient(cx - 5, cy - 6, 2, cx, cy, r); sh.addColorStop(0, 'rgba(255,255,255,.18)'); sh.addColorStop(1, 'rgba(0,0,0,.38)'); g.fillStyle = sh; g.fillRect(cx - r, cy - r, r * 2, r * 2); g.restore();
    ell(g, cx, cy, r, r); g.strokeStyle = '#4a4034'; g.lineWidth = 2.6; g.stroke(); ell(g, cx, cy, r + 1, r + 1); g.strokeStyle = OL; g.lineWidth = 1.2; g.stroke();
    ell(g, cx, cy, 4, 4); fs(g, STEEL, 1.2); g.fillStyle = 'rgba(255,255,255,.5)'; ell(g, cx - 1.2, cy - 1.2, 1.3, 1.3); g.fill();
  } else if (s === 'kite') {
    const p = () => { g.beginPath(); g.moveTo(11, 46); g.quadraticCurveTo(23, 41, 36, 46); g.bezierCurveTo(37, 60, 31, 72, 23.5, 79); g.bezierCurveTo(16, 72, 10, 60, 11, 46); g.closePath(); };
    p(); fs(g, pal.c1, 0); g.save(); p(); g.clip(); g.strokeStyle = pal.c2; g.lineWidth = 4.4; for (let i = 0; i < 3; i++) { g.beginPath(); g.moveTo(8, 60 + i * 9 - 8); g.lineTo(23.5, 49 + i * 9 - 8); g.lineTo(40, 60 + i * 9 - 8); g.stroke(); }
    const sh = g.createLinearGradient(10, 0, 37, 0); sh.addColorStop(0, 'rgba(255,255,255,.2)'); sh.addColorStop(1, 'rgba(0,0,0,.4)'); g.fillStyle = sh; g.fillRect(8, 40, 32, 42); g.restore(); p(); g.strokeStyle = OL; g.lineWidth = 1.7; g.stroke();
    ell(g, 23.5, 52, 2.4, 2.4); fs(g, STEEL, 1);
  } else if (s === 'small') {
    const cx = 24, cy = 59, r = 11.5; ell(g, cx, cy, r, r); fs(g, '#a8823c', 0); g.strokeStyle = '#5c4218'; g.lineWidth = .8; for (let rr = 3; rr < r; rr += 2.4) { ell(g, cx, cy, rr, rr); g.stroke(); }
    for (let i = 0; i < 4; i++) { const a = i * Math.PI / 2 + .4; line(g, [cx + Math.cos(a) * 3, cy + Math.sin(a) * 3, cx + Math.cos(a) * r, cy + Math.sin(a) * r], pal.c1, 2.2); }
    ell(g, cx, cy, r, r); g.strokeStyle = OL; g.lineWidth = 1.5; g.stroke(); ell(g, cx, cy, 3.4, 3.4); fs(g, GOLD, 1.1);
  }
}
function fist(g, x, y, v) { ell(g, x, y, 3.2, 3.2); fs(g, shade(v.skin, -.12), 1.2); }
function blade(g, x1, y1, x2, y2, w, col) { const a = Math.atan2(y2 - y1, x2 - x1), nx = -Math.sin(a) * w, ny = Math.cos(a) * w; g.beginPath(); g.moveTo(x1 + nx, y1 + ny); g.lineTo(x2 + nx * .5, y2 + ny * .5); g.lineTo(x2 + Math.cos(a) * 4, y2 + Math.sin(a) * 4); g.lineTo(x2 - nx * .5, y2 - ny * .5); g.lineTo(x1 - nx, y1 - ny); g.closePath(); fs(g, col || '#c9cfd4', 1.1); line(g, [x1, y1, x2, y2], 'rgba(255,255,255,.55)', .7); }
function drawWeapon(g, L, pal, v) {
  const w = L.weapon;
  if (w === 'sword') { line(g, [57.5, 62, 59, 54], '#3a2a1a', 3); blade(g, 59.5, 52, 65.5, 20, 2.1); line(g, [55, 52.6, 64.4, 54.4], GOLD, 2.4); fist(g, 58.4, 57.5, v); }
  else if (w === 'sabre') { line(g, [57.5, 62, 59, 54], '#3a2a1a', 3); g.beginPath(); g.moveTo(57.6, 52.5); g.quadraticCurveTo(58, 34, 67, 20); g.quadraticCurveTo(64, 36, 61.6, 53); g.closePath(); fs(g, '#c9cfd4', 1.1); line(g, [55.4, 52.6, 64, 54], GOLD, 2.2); fist(g, 58.4, 57.5, v); }
  else if (w === 'axe') { line(g, [56.5, 68, 63, 22], OL, 4); line(g, [56.5, 68, 63, 22], WOOD, 2.4); g.beginPath(); g.moveTo(62, 24); g.quadraticCurveTo(70, 20, 70.5, 30); g.quadraticCurveTo(70.5, 38, 60.5, 35.5); g.closePath(); fs(g, STEEL, 1.2); line(g, [69.6, 23, 70, 36], 'rgba(255,255,255,.6)', .9); fist(g, 58.3, 56, v); }
  else if (w === 'mace') { line(g, [56.5, 68, 62.5, 28], OL, 4); line(g, [56.5, 68, 62.5, 28], WOOD, 2.4); ell(g, 63.2, 24.5, 5, 5); fs(g, IRON, 1.2); for (let i = 0; i < 6; i++) { const a = i * TAU / 6; line(g, [63.2 + Math.cos(a) * 4.5, 24.5 + Math.sin(a) * 4.5, 63.2 + Math.cos(a) * 7.2, 24.5 + Math.sin(a) * 7.2], OL, 2.2); } fist(g, 58.3, 56, v); }
  else if (w === 'club') { g.beginPath(); g.moveTo(55.6, 67); g.lineTo(60, 22); g.quadraticCurveTo(64.5, 18, 67, 23); g.lineTo(58.6, 67.4); g.closePath(); fs(g, WOOD, 1.3); line(g, [61.6, 25, 60, 44], 'rgba(0,0,0,.3)', .8); fist(g, 58, 56, v); }
  else if (w === 'spear') { line(g, [58.5, 76, 60, 9], OL, 3.6); line(g, [58.5, 76, 60, 9], WOOD, 2); poly(g, [60, -2, 63.2, 9.5, 60, 13, 56.8, 9.5]); fs(g, '#c9cfd4', 1.1); fist(g, 59, 56, v); }
  else if (w === 'halberd') { line(g, [58.5, 76, 60, 9], OL, 3.6); line(g, [58.5, 76, 60, 9], WOOD, 2); poly(g, [60, -3, 62, 8, 60, 11, 58, 8]); fs(g, '#c9cfd4', 1); g.beginPath(); g.moveTo(60.4, 9); g.quadraticCurveTo(70, 7, 69, 20); g.quadraticCurveTo(64, 17, 60.4, 20); g.closePath(); fs(g, STEEL, 1.2); poly(g, [59.4, 12, 53.5, 14.5, 59.4, 17]); fs(g, IRON, 1); fist(g, 59, 52, v); fist(g, 58.6, 64, v); }
  else if (w === 'lance') { line(g, [56, 80, 66, -14], OL, 3.8); line(g, [56, 80, 66, -14], '#8a6a40', 2.2); poly(g, [66.6, -22, 69, -12, 66, -9, 63.4, -12.6]); fs(g, '#c9cfd4', 1); g.beginPath(); g.moveTo(65.2, -8); g.lineTo(52, -6); g.lineTo(56, -2); g.lineTo(51.6, 2); g.lineTo(64.4, 1); g.closePath(); fs(g, pal.c1, 1); line(g, [64.6, -3.4, 54.6, -2.4], pal.c2, 1.6); fist(g, 59.4, 54, v); }
  else if (w === 'bow') { g.strokeStyle = OL; g.lineWidth = 3.6; g.beginPath(); g.moveTo(58, 16); g.quadraticCurveTo(72, 42, 58, 68); g.stroke(); g.strokeStyle = '#8a6234'; g.lineWidth = 2.1; g.stroke(); line(g, [58, 16, 58, 68], 'rgba(235,225,200,.85)', .7); fist(g, 64.6, 42, v); }
  else if (w === 'xbow') { line(g, [44, 57, 68, 50], OL, 5); line(g, [44, 57, 68, 50], WOOD, 3.2); g.strokeStyle = OL; g.lineWidth = 3.4; g.beginPath(); g.moveTo(62, 38); g.quadraticCurveTo(72, 49, 67, 62); g.stroke(); g.strokeStyle = IRON; g.lineWidth = 1.9; g.stroke(); line(g, [62, 38, 52, 54.6, 67, 62], 'rgba(235,225,200,.8)', .7); fist(g, 55, 55, v); }
}
function quiver(g) { g.save(); g.translate(20, 40); g.rotate(-.5); g.fillStyle = LEATHER; g.fillRect(-3.5, -4, 7, 20); g.strokeStyle = OL; g.lineWidth = 1.1; g.strokeRect(-3.5, -4, 7, 20); for (let i = 0; i < 3; i++) { line(g, [-2 + i * 2, -4, -2 + i * 2, -11], '#c9b98a', .9); g.fillStyle = i % 2 ? '#b33' : '#ddd'; g.fillRect(-3 + i * 2, -13, 2, 3.4); } g.restore(); }
const HORSES = { bay: ['#6b4226', '#22160d'], black: ['#2e2824', '#0f0c0a'], dun: ['#b3945c', '#3a2a18'], grey: ['#9c978d', '#4a463f'], chestnut: ['#8a4b22', '#4a2410'], barded: ['#6b4226', '#22160d'], bone: ['#cfc6ad', '#5a5242'] };
function drawHorse(g, kind, pal) {
  const [coat, mane] = HORSES[kind] || HORSES.bay;
  const body = () => { g.beginPath(); g.moveTo(16, 92); g.bezierCurveTo(8, 76, 16, 60, 38, 59); g.lineTo(62, 57); g.bezierCurveTo(70, 53, 76, 42, 79, 31); g.lineTo(83, 23); g.lineTo(86, 28); g.bezierCurveTo(92, 31, 100, 40, 105, 48); g.bezierCurveTo(107, 52, 103, 55, 99, 53); g.bezierCurveTo(95, 50, 91, 48, 88, 48); g.bezierCurveTo(88, 62, 88, 80, 82, 92); g.closePath(); };
  body(); fs(g, coat, 0); g.save(); body(); g.clip();
  if (kind === 'barded') { g.fillStyle = pal.c1; g.beginPath(); g.moveTo(6, 96); g.lineTo(10, 62); g.lineTo(60, 58); g.lineTo(72, 50); g.lineTo(90, 50); g.lineTo(90, 96); g.closePath(); g.fill(); g.strokeStyle = pal.c2; g.lineWidth = 2.4; g.beginPath(); g.moveTo(12, 64); g.lineTo(60, 60); g.lineTo(73, 52); g.lineTo(89, 51); g.stroke(); for (let x = 20; x < 86; x += 12) { g.fillStyle = pal.c2; poly(g, [x, 74, x + 3.4, 78, x, 82, x - 3.4, 78]); g.fill(); } g.fillStyle = '#c9a23c'; g.beginPath(); g.moveTo(84, 26); g.lineTo(101, 43); g.lineTo(96, 47); g.lineTo(82, 35); g.closePath(); g.fill(); }
  const sh = g.createLinearGradient(0, 50, 0, 96); sh.addColorStop(0, 'rgba(255,235,200,.14)'); sh.addColorStop(1, 'rgba(0,0,0,.42)'); g.fillStyle = sh; g.fillRect(0, 20, 112, 80); g.restore();
  body(); fs(g, null, 1.7);
  g.beginPath(); g.moveTo(62, 57); g.bezierCurveTo(66, 48, 72, 36, 80, 25); g.lineTo(83, 23); g.bezierCurveTo(76, 28, 68, 40, 58, 56); g.closePath(); fs(g, mane, 1.1);
  poly(g, [80, 26, 81.4, 16.5, 85.4, 24]); fs(g, coat, 1.2);
  g.fillStyle = '#0d0806'; ell(g, 89.4, 34.6, 1.5, 1.3); g.fill(); ell(g, 102.4, 49.4, 1, .8); g.fill();
  line(g, [86, 29, 96, 50], kind === 'barded' ? pal.c2 : '#2a1a10', 1.3); line(g, [96, 50, 70, 60], '#2a1a10', 1); line(g, [84, 40, 93, 36], '#2a1a10', 1);
}
/* look + palette + seed → рисунок бюста. o.base=false — без подставки (для павших) */
function drawBust(g, L, pal, v, o) {
  g.lineJoin = 'round'; g.lineCap = 'round';
  const R = mulberry(v.seed || 1);
  if (L.horse) {
    if (o.base !== false) drawBase(g, 54, 104, 40, 10.5, pal);
    if (o.part !== 'wpn') { g.save(); g.translate(2, 14); drawHorse(g, L.horse, pal); g.restore(); }
    g.save(); g.translate(4, 2);
    if (o.part !== 'wpn') { g.fillStyle = L.horse === 'barded' ? pal.c2 : '#3a2a1a'; g.beginPath(); g.moveTo(14, 70); g.quadraticCurveTo(36, 62, 58, 70); g.lineTo(55, 80); g.quadraticCurveTo(36, 85, 17, 80); g.closePath(); g.fill(); g.strokeStyle = OL; g.lineWidth = 1.2; g.stroke(); }
  } else if (o.base !== false) drawBase(g, 36, 72, 24, 8.5, pal);
  if (o.only === 'head') { drawHead(g, L, v); drawHelm(g, L, v, pal, R); if (L.horse) g.restore(); return; } // голова отдельно (летит при обезглавливании)
  const body = o.part !== 'wpn', arm = o.part !== 'body', hasSh = L.shield && L.shield !== 'none';
  if (body) {
    if (L.weapon === 'bow' || L.weapon === 'xbow') quiver(g);
    if (hasSh) drawArm(g, SH_L, [22, 61], -1, L, pal, v, false);
    drawTorso(g, L, pal, R);
    if (!hasSh) { const F = L.weapon === 'halberd' ? [50, 63] : L.weapon === 'xbow' ? [46, 57.6] : [19, 70.5]; drawArm(g, SH_L, F, F[0] > 30 ? 1 : -1, L, pal, v, false); if (!sleeveOf(L, pal, v).bone) fist(g, F[0], F[1], v); }
    if (o.nohead) drawStump(g, v); else { drawHead(g, L, v); drawHelm(g, L, v, pal, R); }
    drawShield(g, L, pal, R);
  }
  if (arm) { const F = FISTS[L.weapon] || [59.5, 69.5]; drawArm(g, SH_R, F, 1, L, pal, v, true); if (!L.weapon && !sleeveOf(L, pal, v).bone) fist(g, F[0], F[1], v); drawWeapon(g, L, pal, v); }
  if (L.horse) g.restore();
}
const SPR = {}; const SS = 2;
const UNDEAD_SKIN = { zombie: ['#9aa58a', '#8c9a7e', '#a3a08a', '#7f8f78'], skel: ['#d8d0b8', '#cfc4a6', '#e0d8c2'] };
function makeVariant(L, seed) { const R = mulberry(seed); const b = R() < (L.beard || 0) ? (R() < .45 ? 2 : 1) : 0; const us = L.undead && UNDEAD_SKIN[L.undead];
  if (us) return { seed, undead: L.undead, skin: us[Math.floor(R() * us.length)], hair: L.undead === 'skel' ? '#3a3328' : HAIRS[Math.floor(R() * 3)], beard: L.undead === 'skel' ? 0 : b, stache: 0, bald: L.undead === 'skel' || R() < .5, scar: L.undead === 'zombie' };
  return { seed, skin: SKINS[Math.floor(R() * SKINS.length)], hair: HAIRS[Math.floor(R() * HAIRS.length)], beard: b, stache: L.stache && b === 0 ? 1 : 0, bald: R() < .15, scar: R() < .2 }; }
function buildSprite(L, pal, seed) {
  const m = !!L.horse, W = m ? 120 : 76, H = m ? 122 : 88, ax = m ? 54 : 36, ay = m ? 106 : 74, oy = m ? 26 : 5, ox = m ? 2 : 2;
  const v = makeVariant(L, seed);
  const mk = (base, o2) => { const c = mkCanvas(W * SS, H * SS), g = c.getContext('2d'); g.scale(SS, SS); g.translate(ox, oy); drawBust(g, L, pal, v, Object.assign({ base }, o2)); return c; };
  const cv = mk(true), bodyCv = mk(true, { part: 'body' }), wpnCv = mk(false, { part: 'wpn' }), fl = mkCanvas(W * SS, H * SS), fg = fl.getContext('2d'); fg.drawImage(cv, 0, 0); fg.globalCompositeOperation = 'source-in'; fg.fillStyle = '#fff'; fg.fillRect(0, 0, fl.width, fl.height);
  return { cv, body: bodyCv, wpn: wpnCv, piv: [(SH_R[0] + ox + (m ? 4 : 0)) * SS, (SH_R[1] + oy + (m ? 2 : 0)) * SS], wk: L.weapon === 'spear' || L.weapon === 'halberd' || L.weapon === 'lance' ? 2 : L.weapon === 'bow' || L.weapon === 'xbow' ? 3 : L.weapon ? 1 : 0, flash: fl, ax: (ax + ox) * SS, ay: (ay + oy) * SS, w: W * SS, h: H * SS, m, corpse: null, mk, v, hc: [(37.5 + ox + (m ? 4 : 0)) * SS, (29 + oy + (m ? 2 : 0)) * SS] }; // hc — центр головы на холсте
}
function palOf(fac) { const f = FACTIONS[fac]; return { c1: f.c1, c2: f.c2 }; }
function getSprite(type, variant, fac) { const k = type + '|' + variant + '|' + fac + '|' + FACTIONS[fac].c1; if (!SPR[k]) SPR[k] = buildSprite(TROOPS[type].look, palOf(fac), hashStr(type) + variant * 977); return SPR[k]; }
function heroLook(h) { const eq = heroEq(h), W = heroWield(h), S = heroShield(h), hd = EQ[eq.head], bd = EQ[eq.body], hs = EQ[eq.horse]; return { helm: hd ? hd.look : 'none', armor: bd ? bd.look : 'tunic', weapon: W.look || null, shield: S ? S.look : 'none', horse: hs ? hs.look : null, beard: h.beard === undefined ? 1 : h.beard }; }
function getHeroSprite(h, mounted) { const eq = heroEq(h), W = heroWield(h), S = heroShield(h), k = 'hero|' + [eq.head, eq.body, W.id, S && S.id, mounted ? eq.horse : ''].join(',') + '|' + FACTIONS.player.c1 + '|' + (h.seed || 7); if (!SPR[k]) { const L = heroLook(h); if (!mounted) L.horse = null; SPR[k] = buildSprite(L, palOf('player'), h.seed || 7); } return SPR[k]; }
function corpseOf(sp, nohead) { if (nohead) return sp.corpseNH || (sp.corpseNH = sp.mk(false, { nohead: true })); if (!sp.corpse) sp.corpse = sp.mk(false); return sp.corpse; }
function headOf(sp) { return sp.head || (sp.head = sp.mk(false, { only: 'head' })); }
const PORT = {};
function portrait(type, fac) { const k = type + fac + FACTIONS[fac].c1; if (!PORT[k]) PORT[k] = getSprite(type, 0, fac).cv.toDataURL(); return PORT[k]; }

/* ---------- гербы и знамёна ---------- */
function emblem(g, kind, x, y, s, col) {
  g.save(); g.translate(x, y); g.fillStyle = col; g.strokeStyle = col; g.lineCap = 'round';
  if (kind === 'star') { g.lineWidth = s * .16; for (let i = 0; i < 4; i++) { const a = i * Math.PI / 4; g.beginPath(); g.moveTo(Math.cos(a) * s, Math.sin(a) * s); g.lineTo(-Math.cos(a) * s, -Math.sin(a) * s); g.stroke(); } ell(g, 0, 0, s * .28, s * .28); g.fill(); }
  else if (kind === 'sun') { ell(g, 0, 0, s * .5, s * .5); g.fill(); g.lineWidth = s * .16; for (let i = 0; i < 8; i++) { const a = i * TAU / 8; g.beginPath(); g.moveTo(Math.cos(a) * s * .68, Math.sin(a) * s * .68); g.lineTo(Math.cos(a) * s, Math.sin(a) * s); g.stroke(); } }
  else if (kind === 'moon') { g.beginPath(); g.arc(0, 0, s * .85, .5, TAU - .5); g.arc(s * .34, 0, s * .62, TAU - .85, .85, true); g.closePath(); g.fill(); ell(g, s * .5, 0, s * .2, s * .2); g.fill(); }
  else if (kind === 'skull') { ell(g, 0, -s * .15, s * .72, s * .68); g.fill(); g.fillRect(-s * .4, s * .25, s * .8, s * .55); g.fillStyle = '#17110c'; ell(g, -s * .28, -s * .12, s * .2, s * .22); g.fill(); ell(g, s * .28, -s * .12, s * .2, s * .22); g.fill(); poly(g, [0, s * .12, -s * .1, s * .34, s * .1, s * .34]); g.fill(); for (let i = -1; i <= 1; i++) g.fillRect(i * s * .22 - s * .03, s * .5, s * .06, s * .3); }
  else if (kind === 'lily') { g.beginPath(); g.moveTo(0, -s); g.bezierCurveTo(s * .5, -s * .45, s * .34, s * .1, 0, s * .18); g.bezierCurveTo(-s * .34, s * .1, -s * .5, -s * .45, 0, -s); g.fill();
    for (const d of [-1, 1]) { g.beginPath(); g.moveTo(d * s * .12, s * .1); g.bezierCurveTo(d * s * .9, -s * .35, d * s * 1.05, s * .35, d * s * .5, s * .5); g.bezierCurveTo(d * s * .6, s * .2, d * s * .3, s * .12, d * s * .12, s * .1); g.fill(); }
    g.fillRect(-s * .55, s * .3, s * 1.1, s * .16); g.fillRect(-s * .14, s * .3, s * .28, s * .55); }
  else if (kind === 'crown') { g.fillRect(-s * .8, s * .35, s * 1.6, s * .3); g.beginPath(); g.moveTo(-s * .8, s * .35); g.lineTo(-s * .8, -s * .45); g.lineTo(-s * .4, 0); g.lineTo(0, -s * .7); g.lineTo(s * .4, 0); g.lineTo(s * .8, -s * .45); g.lineTo(s * .8, s * .35); g.closePath(); g.fill(); }
  else if (kind === 'oak') { g.fillRect(-s * .14, s * .1, s * .28, s * .8); for (const q of [[-.42, -.1, .5], [.42, -.1, .5], [0, -.5, .58], [0, .08, .52]]) { ell(g, q[0] * s, q[1] * s, q[2] * s, q[2] * s); g.fill(); } }
  else if (kind === 'octa') { for (let r = 0; r < 2; r++) { g.save(); g.rotate(r * Math.PI / 4); g.fillRect(-s * .66, -s * .66, s * 1.32, s * 1.32); g.restore(); } }
  else { g.lineWidth = s * .3; g.lineJoin = 'miter'; g.beginPath(); g.moveTo(-s * .8, s * .1); g.lineTo(0, -s * .6); g.lineTo(s * .8, s * .1); g.stroke(); g.beginPath(); g.moveTo(-s * .8, s * .75); g.lineTo(0, s * .05); g.lineTo(s * .8, s * .75); g.stroke(); }
  g.restore();
}
function drawBanner(g, x, y, fac, s) { // древко от (x,y) вверх
  const f = FACTIONS[fac]; g.lineCap = 'round'; line(g, [x, y, x, y - s * 2.3], OL, s * .2); line(g, [x, y, x, y - s * 2.3], '#8a6a40', s * .1);
  g.beginPath(); g.moveTo(x, y - s * 2.25); g.lineTo(x + s * 1.3, y - s * 2.15); g.lineTo(x + s * 1.05, y - s * 1.65); g.lineTo(x + s * 1.3, y - s * 1.15); g.lineTo(x, y - s * 1.05); g.closePath(); g.fillStyle = f.c1; g.fill(); g.strokeStyle = OL; g.lineWidth = Math.max(1, s * .08); g.stroke();
  emblem(g, f.emblem, x + s * .52, y - s * 1.65, s * .3, f.c2);
}
function crestCanvas(fac, px) { const c = mkCanvas(px, px), g = c.getContext('2d'), f = FACTIONS[fac]; ell(g, px / 2, px / 2, px / 2 - 2, px / 2 - 2); g.fillStyle = f.c1; g.fill(); g.strokeStyle = '#0d0906'; g.lineWidth = 3; g.stroke(); ell(g, px / 2, px / 2, px / 2 - 5, px / 2 - 5); g.strokeStyle = 'rgba(255,255,255,.22)'; g.lineWidth = 1.2; g.stroke(); emblem(g, f.emblem, px / 2, px / 2, px * .27, f.c2); return c; }

/* ---------- поле боя ---------- */
const BIOMES = {
  grass: { base: '#5f6d2c', a: '#6e7d34', b: '#4d5a25', dirt: '#6f6238', tuft: ['#3f4c1c', '#84903f', '#4b5a22'], stone: '#8f8873', flower: '#e9e6d6' },
  snow: { base: '#c3ccce', a: '#dfe6e7', b: '#a7b4b5', dirt: '#8c8f80', tuft: ['#7c8660', '#eef2f2', '#9aa59a'], stone: '#8a8d90', flower: '#f6f8f8' },
  steppe: { base: '#978a48', a: '#ab9d56', b: '#82773f', dirt: '#8a7446', tuft: ['#6c6230', '#c4b46a', '#7a6e38'], stone: '#9a8f72', flower: '#e8d37a' },
  arid: { base: '#bfa56a', a: '#cfb97c', b: '#aa9156', dirt: '#a68a54', tuft: ['#8a7a3c', '#dac98c', '#9a8a48'], stone: '#a99c80', flower: '#e9dba8' }
};
function treeSprite(biome, seed) {
  const R = mulberry(seed), c = mkCanvas(200, 250), g = c.getContext('2d'); g.lineJoin = 'round';
  g.fillStyle = 'rgba(0,0,0,.25)'; ell(g, 104, 232, 46, 12); g.fill();
  if (biome === 'snow') {
    g.fillStyle = '#4a3320'; g.fillRect(93, 180, 14, 52); g.strokeStyle = OL; g.lineWidth = 2.5; g.strokeRect(93, 180, 14, 52);
    for (let i = 0; i < 4; i++) { const y = 196 - i * 44, w = 74 - i * 14; g.beginPath(); g.moveTo(100 - w, y); g.lineTo(100, y - 70); g.lineTo(100 + w, y); g.quadraticCurveTo(100, y + 12, 100 - w, y); g.closePath(); g.fillStyle = i % 2 ? '#2f4a3a' : '#28402f'; g.fill(); g.strokeStyle = OL; g.lineWidth = 2.5; g.stroke(); g.beginPath(); g.moveTo(100 - w * .7, y - 12); g.lineTo(100, y - 68); g.lineTo(100 + w * .25, y - 30); g.quadraticCurveTo(100 - w * .2, y - 20, 100 - w * .7, y - 12); g.fillStyle = 'rgba(240,246,248,.85)'; g.fill(); }
  } else if (biome === 'arid') { // акация: кривой ствол и плоская зонтичная крона
    g.fillStyle = '#5a4126'; g.beginPath(); g.moveTo(94, 232); g.quadraticCurveTo(92, 190, 100, 150); g.quadraticCurveTo(104, 126, 98, 108); g.lineTo(108, 108); g.quadraticCurveTo(116, 130, 108, 156); g.quadraticCurveTo(104, 196, 108, 232); g.closePath(); g.fill(); g.strokeStyle = OL; g.lineWidth = 2.5; g.stroke();
    const cols = ['#5f6a2c', '#7c8838', '#98a24a'], blobs = []; for (let i = 0; i < 7; i++) blobs.push([100 + (R() - .5) * 120, 100 + (R() - .5) * 26, 28 + R() * 16]);
    g.fillStyle = OL; for (const b of blobs) { ell(g, b[0], b[1], b[2] + 2.5, b[2] * .5 + 2.5); g.fill(); }
    g.fillStyle = cols[0]; for (const b of blobs) { ell(g, b[0], b[1], b[2], b[2] * .5); g.fill(); }
    g.fillStyle = cols[1]; for (const b of blobs) { ell(g, b[0] - 4, b[1] - 5, b[2] * .72, b[2] * .3); g.fill(); }
    for (let i = 0; i < 60; i++) { const b = blobs[i % 7], a = R() * TAU, d = R() * b[2] * .8, x = b[0] + Math.cos(a) * d - 4, y = b[1] + Math.sin(a) * d * .4 - 3; g.fillStyle = R() < .5 ? cols[2] : cols[0]; ell(g, x, y, 3, 1.8); g.fill(); }
  } else {
    const steppe = biome === 'steppe'; g.fillStyle = '#4a3320'; g.beginPath(); g.moveTo(90, 232); g.quadraticCurveTo(96, 190, 92, 150); g.lineTo(110, 150); g.quadraticCurveTo(106, 190, 114, 232); g.closePath(); g.fill(); g.strokeStyle = OL; g.lineWidth = 2.5; g.stroke();
    const cols = steppe ? ['#5a5e22', '#6f7230', '#878a3c'] : ['#2f4a1c', '#3f6124', '#58802e'];
    const blobs = []; for (let i = 0; i < 9; i++) blobs.push([100 + (R() - .5) * 96, 96 + (R() - .5) * 96, 34 + R() * 20]);
    g.fillStyle = OL; for (const b of blobs) { ell(g, b[0], b[1], b[2] + 2.5, b[2] * .92 + 2.5); g.fill(); }
    g.fillStyle = cols[0]; for (const b of blobs) { ell(g, b[0], b[1], b[2], b[2] * .92); g.fill(); }
    g.fillStyle = cols[1]; for (const b of blobs) { ell(g, b[0] - 6, b[1] - 8, b[2] * .72, b[2] * .64); g.fill(); }
    for (let i = 0; i < 150; i++) { const b = blobs[i % 9], a = R() * TAU, d = R() * b[2] * .8, x = b[0] + Math.cos(a) * d - 5, y = b[1] + Math.sin(a) * d * .9 - 6; g.fillStyle = R() < .5 ? cols[2] : cols[0]; ell(g, x, y, 3.4, 2.2); g.fill(); }
  }
  return c;
}
function bushSprite(biome, seed) { const R = mulberry(seed), c = mkCanvas(90, 70), g = c.getContext('2d'); const cols = biome === 'snow' ? ['#6f7b62', '#dfe7e8', '#93a08a'] : biome === 'steppe' ? ['#6a6428', '#8c8438', '#a59c48'] : biome === 'arid' ? ['#7a7436', '#9d9648', '#b7ae5a'] : ['#34521e', '#4b6e26', '#66883a']; g.fillStyle = 'rgba(0,0,0,.2)'; ell(g, 46, 58, 34, 8); g.fill(); const bl = []; for (let i = 0; i < 6; i++) bl.push([45 + (R() - .5) * 46, 38 + (R() - .5) * 20, 12 + R() * 8]); g.fillStyle = OL; for (const b of bl) { ell(g, b[0], b[1], b[2] + 2, b[2] + 2); g.fill(); } g.fillStyle = cols[0]; for (const b of bl) { ell(g, b[0], b[1], b[2], b[2]); g.fill(); } g.fillStyle = cols[1]; for (const b of bl) { ell(g, b[0] - 3, b[1] - 3, b[2] * .65, b[2] * .6); g.fill(); } for (let i = 0; i < 40; i++) { const b = bl[i % 6]; g.fillStyle = cols[2]; ell(g, b[0] + (R() - .5) * b[2] * 1.4 - 2, b[1] + (R() - .5) * b[2] * 1.2 - 3, 2.4, 1.5); g.fill(); } return c; }
function rgbaOf(hex, a) { const n = parseInt(hex.slice(1), 16); return 'rgba(' + (n >> 16) + ',' + (n >> 8 & 255) + ',' + (n & 255) + ',' + a + ')'; }
function paintGround(W, H, biome, seed) {
  const P = BIOMES[biome], R = mulberry(seed), c = mkCanvas(W, H), g = c.getContext('2d'), snow = biome === 'snow', dry = biome === 'arid' || biome === 'steppe';
  const blob = (x, y, rx, ry, col, a, rot) => { const gr = g.createRadialGradient(0, 0, 0, 0, 0, 1); gr.addColorStop(0, rgbaOf(col, a)); gr.addColorStop(.55, rgbaOf(col, a * .6)); gr.addColorStop(1, rgbaOf(col, 0)); g.save(); g.translate(x, y); g.rotate(rot || 0); g.scale(rx, ry); g.fillStyle = gr; g.beginPath(); g.arc(0, 0, 1, 0, TAU); g.fill(); g.restore(); };
  g.fillStyle = P.base; g.fillRect(0, 0, W, H);
  // крупные пятна света и тени, потом мелкая рябь
  for (let i = 0; i < 420; i++) { const r = 70 + R() * 220; blob(R() * W, R() * H, r, r * (.45 + R() * .4), R() < .45 ? P.a : R() < .8 ? P.b : P.dirt, .14 + R() * .16, R() * 3); }
  for (let i = 0; i < 2600; i++) { const r = 9 + R() * 34; blob(R() * W, R() * H, r, r * (.5 + R() * .5), R() < .5 ? P.a : P.b, .1 + R() * .12, R() * 3); }
  // проплешины голой земли с камешками
  const bare = [];
  for (let i = 0; i < 22; i++) { const x = R() * W, y = R() * H, n = 4 + Math.floor(R() * 6); bare.push([x, y]); for (let k = 0; k < n; k++) { const r = 26 + R() * 60; blob(x + (R() - .5) * 150, y + (R() - .5) * 90, r, r * (.4 + R() * .3), P.dirt, .3 + R() * .22, R() * 3); }
    for (let k = 0; k < 26; k++) { const px = x + (R() - .5) * 190, py = y + (R() - .5) * 110, r = 1 + R() * 2.2; g.fillStyle = rgbaOf(P.stone, .7); ell(g, px, py, r, r * .7); g.fill(); g.fillStyle = 'rgba(0,0,0,.2)'; ell(g, px + .8, py + .9, r, r * .5); g.fill(); } }
  // мощёная дорога: утоптанная обочина, колеи, булыжник
  const ph = R() * 6, amp = 160 + R() * 180, y0 = H * (.3 + R() * .4), slope = (R() - .5) * .35;
  const ry = x => y0 + Math.sin(x / 330 + ph) * amp + Math.sin(x / 120 + ph * 2) * 34 + (x - W / 2) * slope;
  for (let x = -40; x < W + 40; x += 14) blob(x, ry(x), 78, 60, P.dirt, snow ? .2 : .34, 0);
  for (let x = -40; x < W + 40; x += 10) blob(x, ry(x), 44, 40, shade2(P.dirt, -.2), snow ? .12 : .3, 0);
  for (let i = 0; i < 4200; i++) { const x = R() * W, t = (R() + R() + R() - 1.5) * 62, y = ry(x) + t; if (R() < Math.abs(t) / 110) continue; const rx = 4 + R() * 7, ry2 = 3 + R() * 4.6, rot = R() * 3; g.fillStyle = 'rgba(0,0,0,.22)'; g.beginPath(); g.ellipse(x + 1.2, y + 1.6, rx, ry2, rot, 0, TAU); g.fill(); g.beginPath(); g.ellipse(x, y, rx, ry2, rot, 0, TAU); g.fillStyle = shade(P.stone, (R() - .5) * .34 - .04); g.fill(); g.strokeStyle = 'rgba(40,36,26,.6)'; g.lineWidth = 1; g.stroke(); g.fillStyle = 'rgba(255,255,255,.16)'; g.beginPath(); g.ellipse(x - rx * .25, y - ry2 * .3, rx * .45, ry2 * .35, rot, 0, TAU); g.fill(); }
  for (const off of [-17, 17]) { g.strokeStyle = 'rgba(30,24,14,.16)'; g.lineWidth = 7; g.lineCap = 'round'; g.beginPath(); for (let x = -40; x < W + 40; x += 24) { const y = ry(x) + off; if (x < 0) g.moveTo(x, y); else g.lineTo(x, y); } g.stroke(); }
  // снег: сугробы с голубой тенью и следы
  if (snow) {
    for (let i = 0; i < 150; i++) { const x = R() * W, y = R() * H, rx = 40 + R() * 110, r2 = rx * (.22 + R() * .14); blob(x + 6, y + r2 * .55, rx, r2, '#7f93a6', .2, 0); blob(x, y, rx, r2, '#f4f8fa', .5, 0); }
    for (let i = 0; i < 26; i++) { let x = R() * W, y = R() * H, a = R() * TAU; for (let k = 0; k < 26; k++) { a += (R() - .5) * .5; x += Math.cos(a) * 15; y += Math.sin(a) * 15; const sx = x - Math.sin(a) * (k % 2 ? 4 : -4), sy = y + Math.cos(a) * (k % 2 ? 4 : -4); g.fillStyle = 'rgba(96,112,128,.28)'; g.beginPath(); g.ellipse(sx, sy, 4, 2.3, a, 0, TAU); g.fill(); } }
  }
  // лужи и сырые низины
  if (!snow && !dry) for (let i = 0; i < 9; i++) { const x = R() * W, y = R() * H, rx = 26 + R() * 44, r2 = rx * (.3 + R() * .2), rot = (R() - .5) * .6; blob(x, y, rx * 1.5, r2 * 1.7, '#3a3320', .32, rot); g.beginPath(); g.ellipse(x, y, rx, r2, rot, 0, TAU); g.fillStyle = 'rgba(46,58,64,.6)'; g.fill(); g.strokeStyle = 'rgba(20,18,10,.4)'; g.lineWidth = 1.4; g.stroke(); g.fillStyle = 'rgba(190,210,215,.26)'; g.beginPath(); g.ellipse(x - rx * .2, y - r2 * .25, rx * .5, r2 * .28, rot, 0, TAU); g.fill(); }
  if (dry) for (let i = 0; i < 60; i++) { let x = R() * W, y = R() * H, a = R() * TAU; g.strokeStyle = 'rgba(60,44,20,.22)'; g.lineWidth = 1; g.beginPath(); g.moveTo(x, y); for (let k = 0; k < 6; k++) { a += (R() - .5) * 1.4; x += Math.cos(a) * 12; y += Math.sin(a) * 9; g.lineTo(x, y); } g.stroke(); }
  // трава куртинами: тёмный корень, светлый кончик; на голой земле её почти нет
  g.lineCap = 'round'; const tufts = snow ? 2600 : 6400;
  for (let i = 0; i < tufts; i++) { const x = R() * W, y = R() * H; if (bare.some(b => Math.abs(b[0] - x) < 80 && Math.abs(b[1] - y) < 46) && R() < .8) continue; if (Math.abs(ry(x) - y) < 46 && R() < .85) continue;
    const n = 3 + Math.floor(R() * 4), h = 5 + R() * 8, ci = Math.floor(R() * 3); g.globalAlpha = .8;
    for (let k = 0; k < n; k++) { const bx = x + (k - n / 2) * 2.1, tx = bx + (k - n / 2) * 1.5 + (R() - .5) * 3, ty = y - h * (.6 + R() * .5); g.strokeStyle = P.tuft[ci === 1 ? 0 : ci]; g.lineWidth = 1.5; g.beginPath(); g.moveTo(bx, y); g.lineTo(tx, ty); g.stroke(); if (k % 2 === 0) { g.strokeStyle = P.tuft[1]; g.lineWidth = .9; g.beginPath(); g.moveTo((bx + tx) / 2, (y + ty) / 2); g.lineTo(tx, ty); g.stroke(); } } }
  g.globalAlpha = 1;
  if (!snow) for (let i = 0; i < 90; i++) { const x = R() * W, y = R() * H, col = R() < .6 ? P.flower : R() < .5 ? '#d8b23a' : '#b9566a'; for (let k = 0; k < 8; k++) { const fx = x + (R() - .5) * 34, fy = y + (R() - .5) * 24; g.fillStyle = 'rgba(0,0,0,.2)'; ell(g, fx + .6, fy + .8, 1.7, 1.2); g.fill(); g.fillStyle = col; ell(g, fx, fy, 1.7, 1.5); g.fill(); g.fillStyle = 'rgba(255,255,255,.5)'; ell(g, fx - .4, fy - .4, .6, .5); g.fill(); } }
  // валуны с тенью и бликом
  for (let i = 0; i < 110; i++) { const x = R() * W, y = R() * H, r = 3 + R() * 8, col = shade('#85806f', (R() - .5) * .3); g.fillStyle = 'rgba(0,0,0,.28)'; ell(g, x + r * .35, y + r * .4, r * 1.05, r * .55); g.fill(); g.beginPath(); g.moveTo(x - r, y + r * .2); g.quadraticCurveTo(x - r * .9, y - r * .7, x - r * .1, y - r * .8); g.quadraticCurveTo(x + r * .9, y - r * .7, x + r, y + r * .15); g.quadraticCurveTo(x, y + r * .7, x - r, y + r * .2); g.closePath(); g.fillStyle = col; g.fill(); g.strokeStyle = 'rgba(30,26,18,.8)'; g.lineWidth = 1.1; g.stroke(); g.fillStyle = 'rgba(255,255,255,.2)'; ell(g, x - r * .3, y - r * .35, r * .4, r * .22); g.fill(); if (snow) { g.fillStyle = 'rgba(244,248,250,.9)'; ell(g, x - r * .1, y - r * .5, r * .7, r * .3); g.fill(); } }
  // общий свет слева сверху и виньетка
  const lg = g.createLinearGradient(0, 0, W, H); lg.addColorStop(0, 'rgba(255,244,210,.07)'); lg.addColorStop(.5, 'rgba(0,0,0,0)'); lg.addColorStop(1, 'rgba(10,14,30,.12)'); g.fillStyle = lg; g.fillRect(0, 0, W, H);
  const vg = g.createRadialGradient(W / 2, H / 2, H * .45, W / 2, H / 2, W * .62); vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(10,8,4,.45)'); g.fillStyle = vg; g.fillRect(0, 0, W, H);
  return c;
}
function shade2(hex, amt) { const n = parseInt(hex.slice(1), 16); let r = n >> 16, gg = n >> 8 & 255, b = n & 255; const f = v => Math.max(0, Math.min(255, Math.round(amt < 0 ? v * (1 + amt) : v + (255 - v) * amt))).toString(16).padStart(2, '0'); return '#' + f(r) + f(gg) + f(b); }

