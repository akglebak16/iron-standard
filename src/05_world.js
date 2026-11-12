/* ================= карта мира ================= */
const WW = 2600, WH = 1700, GC = 20, GW = WW / GC, GH = Math.ceil(WH / GC);
let G = null, WT = null; // G — состояние игры, WT — статичный ландшафт
const SNAMES = {
  nord: { town: ['Хольмгард', 'Скьярвик'], castle: ['Ульвхейм', 'Бьёрнборг'], village: ['Эйдфьорд', 'Ватнсдал', 'Ормслунд', 'Хавик', 'Тюрсби'] },
  emp: { town: ['Вентум', 'Мариум'], castle: ['Кастра Руфа', 'Корвинум'], village: ['Остра', 'Тибурий', 'Сильва', 'Агрум', 'Лукрин'] },
  khan: { town: ['Кешир', 'Алтын-Тобе'], castle: ['Булан-Орда', 'Тенгри-Кала'], village: ['Ак-Булак', 'Сары-Агач', 'Темир-Тау', 'Ордабаш', 'Кара-Су'] }
};
const CAMPN = ['Волчья яма', 'Разбитая башня', 'Чёрный брод', 'Пещера висельников', 'Гнилой овраг', 'Старая застава'];
const WAR = { nord: { emp: 1 }, emp: { nord: 1, khan: 1 }, khan: { emp: 1 }, bandit: { nord: 1, emp: 1, khan: 1 } };
const atWar = (a, b) => a !== b && ((WAR[a] && WAR[a][b]) || (WAR[b] && WAR[b][a]));
const TCOST = [0, 1, 1.75, 1.5, 0];
const TNAME = ['вода', 'равнина', 'лес', 'холмы', 'горы'];

function genWorld(seed) {
  const nE = makeNoise(seed), nM = makeNoise(seed ^ 0x9e3779b9), nF = makeNoise(seed + 77), nD = makeNoise(seed + 5);
  const info = (x, y) => {
    const dx = (x - WW / 2) / (WW / 2), dy = (y - WH / 2) / (WH / 2), f = dx * dx + dy * dy, e = nE(x / 520, y / 520) + .22 - f * .5, m = nM(x / 230, y / 230);
    let t = 1; if (e < .33) t = 0; else if (e > .52 && m > .64) t = 4; else if (m > .56 && e > .4) t = 3; else if (nF(x / 130, y / 130) > .6) t = 2;
    return { e, t };
  };
  const snowLine = x => WH * .27 + (nF(x / 200, 5) - .5) * 160, steppeLine = y => WW * .66 + (nF(7, y / 200) - .5) * 180;
  const biomeAt = (x, y) => y < snowLine(x) ? 'snow' : x > steppeLine(y) ? 'steppe' : 'grass';
  const cells = new Uint8Array(GW * GH), bio = new Uint8Array(GW * GH);
  for (let j = 0; j < GH; j++) for (let i = 0; i < GW; i++) { const x = i * GC + GC / 2, y = j * GC + GC / 2; cells[j * GW + i] = info(x, y).t; bio[j * GW + i] = { grass: 0, snow: 1, steppe: 2 }[biomeAt(x, y)]; }
  // крупнейшая проходимая область
  const comp = new Int32Array(GW * GH).fill(-1); let best = -1, bestN = 0, cid = 0;
  for (let s = 0; s < cells.length; s++) { if (comp[s] >= 0 || !TCOST[cells[s]]) continue; let n = 0; const st = [s]; comp[s] = cid; while (st.length) { const c = st.pop(); n++; const ci = c % GW, cj = (c / GW) | 0; for (const [a, b] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const x = ci + a, y = cj + b; if (x < 0 || y < 0 || x >= GW || y >= GH) continue; const k = y * GW + x; if (comp[k] < 0 && TCOST[cells[k]]) { comp[k] = cid; st.push(k); } } } if (n > bestN) { bestN = n; best = cid; } cid++; }
  WT = { seed, cells, bio, comp, main: best, info, biomeAt, road: new Uint8Array(GW * GH), nF, nD };
  return WT;
}
const cellOf = (x, y) => clamp(Math.floor(y / GC), 0, GH - 1) * GW + clamp(Math.floor(x / GC), 0, GW - 1);
function terrAt(x, y) { return WT.cells[cellOf(x, y)]; }
function biomeName(x, y) { return ['grass', 'snow', 'steppe'][WT.bio[cellOf(x, y)]]; }
function cellCost(k) { const t = WT.cells[k]; if (!TCOST[t]) return 0; let c = TCOST[t]; if (WT.bio[k] === 1) c *= 1.25; if (WT.road[k]) c *= .55; return c; }

/* ---------- поиск пути ---------- */
const PA = { g: new Float32Array(GW * GH), prev: new Int32Array(GW * GH), closed: new Uint8Array(GW * GH) };
function nearestPass(x, y) { const ci = clamp(Math.floor(x / GC), 0, GW - 1), cj = clamp(Math.floor(y / GC), 0, GH - 1); if (TCOST[WT.cells[cj * GW + ci]]) return [ci, cj]; for (let r = 1; r < 40; r++) for (let j = cj - r; j <= cj + r; j++) for (let i = ci - r; i <= ci + r; i++) { if (i < 0 || j < 0 || i >= GW || j >= GH) continue; if (Math.max(Math.abs(i - ci), Math.abs(j - cj)) !== r) continue; if (TCOST[WT.cells[j * GW + i]] && WT.comp[j * GW + i] === WT.main) return [i, j]; } return [ci, cj]; }
function hpush(h, f, v) { h.push([f, v]); let i = h.length - 1; while (i > 0) { const p = (i - 1) >> 1; if (h[p][0] <= h[i][0]) break; [h[p], h[i]] = [h[i], h[p]]; i = p; } }
function hpop(h) { const top = h[0], last = h.pop(); if (h.length) { h[0] = last; let i = 0; for (; ;) { let l = i * 2 + 1, r = l + 1, m = i; if (l < h.length && h[l][0] < h[m][0]) m = l; if (r < h.length && h[r][0] < h[m][0]) m = r; if (m === i) break; [h[m], h[i]] = [h[i], h[m]]; i = m; } } return top; }
function losClear(x0, y0, x1, y1) { const d = Math.hypot(x1 - x0, y1 - y0), n = Math.ceil(d / (GC * .5)); for (let i = 1; i < n; i++) { const t = i / n; if (!TCOST[terrAt(lerp(x0, x1, t), lerp(y0, y1, t))]) return false; } return true; }
function findPath(sx, sy, tx, ty) {
  const [a, b] = nearestPass(sx, sy), [c, d] = nearestPass(tx, ty), s = b * GW + a, e = d * GW + c; if (s === e) return [{ x: tx, y: ty }];
  PA.g.fill(1e9); PA.closed.fill(0); const h = []; PA.g[s] = 0; PA.prev[s] = -1; hpush(h, 0, s); let found = false;
  while (h.length) { const [, cur] = hpop(h); if (PA.closed[cur]) continue; PA.closed[cur] = 1; if (cur === e) { found = true; break; } const ci = cur % GW, cj = (cur / GW) | 0;
    for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) { if (!di && !dj) continue; const ni = ci + di, nj = cj + dj; if (ni < 0 || nj < 0 || ni >= GW || nj >= GH) continue; const k = nj * GW + ni; if (PA.closed[k]) continue; const cc = cellCost(k); if (!cc) continue; if (di && dj && (!cellCost(cj * GW + ni) || !cellCost(nj * GW + ci))) continue; const g = PA.g[cur] + cc * (di && dj ? 1.414 : 1); if (g < PA.g[k]) { PA.g[k] = g; PA.prev[k] = cur; hpush(h, g + Math.hypot(ni - c, nj - d) * .55, k); } } }
  if (!found) return null;
  const pts = []; for (let k = e; k >= 0; k = PA.prev[k]) pts.push({ x: (k % GW) * GC + GC / 2, y: ((k / GW) | 0) * GC + GC / 2 }); pts.reverse(); pts[0] = { x: sx, y: sy }; pts[pts.length - 1] = { x: tx, y: ty };
  if (!TCOST[terrAt(tx, ty)]) pts[pts.length - 1] = pts[pts.length - 2] || pts[0];
  const out = [pts[0]]; let i = 0; while (i < pts.length - 1) { let j = pts.length - 1; while (j > i + 1 && !losClear(pts[i].x, pts[i].y, pts[j].x, pts[j].y)) j--; out.push(pts[j]); i = j; } out.shift(); return out;
}

/* ---------- создание мира ---------- */
function mkSettle(kind, fac, name, x, y) { return { id: G.nid++, kind, fac, name, x, y, recruits: [], rt: 0, pros: rint(2, 5), camp: null, cleared: false, respawn: 0, hv: 0 }; }
function genSettlements() {
  const R = mulberry(G.seed + 11), W = WT; const ok = (x, y, md) => { const k = cellOf(x, y); if (W.comp[k] !== W.main || W.cells[k] !== 1) return false; for (const s of G.settles) if (Math.hypot(s.x - x, s.y - y) < md) return false; return true; };
  const reg = { nord: [.08, .08, .46, .38], emp: [.12, .5, .6, .9], khan: [.64, .2, .92, .8] };
  const place = (fac, kind, name, md) => { const r = reg[fac]; let x, y, tries = 0; do { x = rnd2(R, r[0] * WW, r[2] * WW); y = rnd2(R, r[1] * WH, r[3] * WH); tries++; if (tries > 400) { r[0] = Math.max(.03, r[0] - .03); r[1] = Math.max(.03, r[1] - .03); r[2] = Math.min(.97, r[2] + .03); r[3] = Math.min(.97, r[3] + .03); tries = 0; } } while (!ok(x, y, md)); const s = mkSettle(kind, fac, name, x, y); G.settles.push(s); return s; };
  for (const f of ['nord', 'emp', 'khan']) { const n = SNAMES[f]; place(f, 'town', n.town[0], 260); place(f, 'town', n.town[1], 260); place(f, 'castle', n.castle[0], 220); place(f, 'castle', n.castle[1], 220); for (let i = 0; i < 3; i++) place(f, 'village', n.village[i], 130); }
  for (let i = 0; i < 4; i++) { const f = ['nord', 'emp', 'khan', 'emp'][i], r = reg[f]; let x, y, t = 0; do { x = rnd2(R, .05 * WW, .95 * WW); y = rnd2(R, .05 * WH, .95 * WH); t++; } while (!ok(x, y, 170) && t < 2000); const s = mkSettle('camp', 'bandit', CAMPN[i], x, y); G.settles.push(s); }
}
const rnd2 = (R, a, b) => a + R() * (b - a);
function genRoads() {
  const towns = G.settles.filter(s => s.kind !== 'camp'); WT.road.fill(0);
  const link = (a, b) => { const p = findPath(a.x, a.y, b.x, b.y); if (!p) return; let px = a.x, py = a.y; const seg = []; for (const q of [{ x: a.x, y: a.y }, ...p]) seg.push(q); for (let i = 0; i < seg.length - 1; i++) { const n = Math.ceil(Math.hypot(seg[i + 1].x - seg[i].x, seg[i + 1].y - seg[i].y) / 8); for (let k = 0; k <= n; k++) WT.road[cellOf(lerp(seg[i].x, seg[i + 1].x, k / n), lerp(seg[i].y, seg[i + 1].y, k / n))] = 1; } G.roads.push(seg); };
  G.roads = []; const done = new Set();
  for (const a of towns) { const ds = towns.filter(b => b !== a).sort((p, q) => Math.hypot(p.x - a.x, p.y - a.y) - Math.hypot(q.x - a.x, q.y - a.y)); let n = 0; for (const b of ds) { const key = Math.min(a.id, b.id) + '-' + Math.max(a.id, b.id); if (done.has(key)) { n++; if (n >= 2) break; continue; } done.add(key); link(a, b); if (++n >= 2) break; } }
  for (const c of G.settles.filter(s => s.kind === 'camp')) { const b = towns.sort((p, q) => Math.hypot(p.x - c.x, p.y - c.y) - Math.hypot(q.x - c.x, q.y - c.y))[0]; if (Math.hypot(b.x - c.x, b.y - c.y) < 380) link(c, b); }
}
function genRecruits(s) {
  const f = s.fac; if (f === 'bandit') return; const out = {}, n = s.kind === 'town' ? rint(5, 9) : s.kind === 'castle' ? rint(3, 6) : rint(3, 7);
  for (let i = 0; i < n; i++) { const ids = Object.keys(TROOPS).filter(k => TROOPS[k].fac === f && TROOPS[k].tier <= (s.kind === 'village' ? 1 : s.kind === 'town' ? 2 : 3) && (s.kind !== 'castle' || TROOPS[k].tier >= 2) && (s.kind === 'village' || TROOPS[k].tier >= 1)); let id = pick(ids.length ? ids : Object.keys(TROOPS).filter(k => TROOPS[k].fac === f)); if (s.kind === 'village' && TROOPS[id].tier > 1) id = Object.keys(TROOPS).find(k => TROOPS[k].fac === f && TROOPS[k].tier === 1); out[id] = (out[id] || 0) + 1; }
  s.recruits = Object.keys(out).map(k => ({ type: k, n: out[k] }));
}
function lordName(fac) { const f = FACTIONS[fac]; return f.title[0].toUpperCase() + f.title.slice(1) + ' ' + unitName(fac); }
function partyStr(p) { return strength(p.troops); }
function mkParty(kind, fac, name, x, y, troops, extra) { const p = Object.assign({ id: G.nid++, kind, fac, name, x, y, troops, path: [], pi: 0, tid: null, sid: null, home: null, state: 'idle', wait: 0, hide: false, gold: 0, hold: 0, cd: 0 }, extra || {}); G.parties.push(p); return p; }
function partyById(id) { return G.parties.find(p => p.id === id); }
function settleById(id) { return G.settles.find(s => s.id === id); }
function sizeCap(h) { return 20 + h.lead * 5 + (h.lvl - 1) * 3; }
function leaderType(p) { let b = null, bs = -1; for (const s of p.troops) { const t = TROOPS[s.type], v = t.tier * 10 + s.n * .01; if (v > bs) { bs = v; b = s.type; } } return b; }
function addT(list, type, n) { const f = list.find(s => s.type === type); if (f) f.n += n; else list.push({ type, n }); }
function remT(list, type, n) { const f = list.find(s => s.type === type); if (!f) return; f.n -= n; if (f.n <= 0) list.splice(list.indexOf(f), 1); }
function sortT(list) { list.sort((a, b) => TROOPS[b.type].tier - TROOPS[a.type].tier || (a.type < b.type ? -1 : 1)); }

const CULT = {
  nord: { start: [['n1', 6], ['n2a', 2], ['n2s', 2]], horse: 0 }, emp: { start: [['e1', 6], ['e2a', 3], ['e2s', 1]], horse: 0 }, khan: { start: [['k1', 5], ['k2a', 3], ['k2c', 2]], horse: 1 }
};
function newGame(o) {
  const seed = o.seed || rint(1, 1e9); G = { seed, nid: 1, day: 1, hour: 8, acc: 0, speed: 1, paused: false, parties: [], settles: [], roads: [], log: [], quests: [], rel: { nord: 0, emp: 0, khan: 0, bandit: -100 }, stats: { wins: 0, kills: 0 }, ver: 1 };
  genWorld(seed); genSettlements(); genRoads(); for (const s of G.settles) { genRecruits(s); if (s.kind === 'camp') respawnCamp(s); }
  const home = G.settles.find(s => s.fac === o.culture && s.kind === 'town');
  const troops = CULT[o.culture].start.map(a => ({ type: a[0], n: a[1] }));
  const pl = { x: home.x + 10, y: home.y + 34, troops, gold: 650, food: 60, path: [], pi: 0, tid: null, sid: null, in: null, name: o.name || 'Безымянный', culture: o.culture, banner: o.banner || 0,
    hero: { name: o.name || 'Безымянный', lvl: 1, xp: 0, pts: 2, str: 1, vit: 1, agi: 1, lead: 1, armor: 0, weapon: 0, shield: 0, horse: CULT[o.culture].horse, hp: 1, seed: rint(1, 99999) } };
  G.player = pl; FACTIONS.player.c1 = BANNERS[pl.banner].c1; FACTIONS.player.c2 = BANNERS[pl.banner].c2;
  for (const f of ['nord', 'emp', 'khan']) { const hs = G.settles.filter(s => s.fac === f); for (let i = 0; i < 3; i++) { const h = hs[i % 2 === 0 ? 0 : rint(0, hs.length - 1)]; const p = mkParty('lord', f, lordName(f), h.x + 12, h.y + 20, genTroops(f, rint(22, 40), .6), { home: h.id }); p.state = 'idle'; p.wait = rint(1, 20); } }
  for (let i = 0; i < 2; i++) { const t = pick(G.settles.filter(s => s.kind === 'town')); spawnCaravan(t); }
  genQuests(); logW('Ты прибыл в ' + home.name + '. Собери отряд и заработай имя.');
  return G;
}
function respawnCamp(c) { c.camp = mkParty('camp', 'bandit', 'Лагерь: ' + c.name, c.x, c.y, genTroops('bandit', rint(12, 20), .4), { home: c.id, hide: false }); c.cleared = false; c.camp.camp = c.id; }
function spawnCaravan(t) { const dst = pick(G.settles.filter(s => s.kind === 'town' && s !== t)); const p = mkParty('caravan', t.fac, 'Караван', t.x + 10, t.y + 20, genTroops(t.fac, rint(3, 5), .3), { home: t.id, sid: dst.id, state: 'travel' }); p.path = findPath(p.x, p.y, dst.x, dst.y) || []; p.pi = 0; return p; }
function logW(txt, kind) { G.log.push({ txt, kind: kind || 0, d: G.day }); if (G.log.length > 40) G.log.shift(); G.logDirty = true; }
function relName(v) { return v <= -60 ? 'Враждебные' : v <= -20 ? 'Недружелюбные' : v < 20 ? 'Нейтральные' : v < 50 ? 'Дружелюбные' : 'Союзные'; }

/* ---------- задания ---------- */
function genQuests() {
  for (const s of G.settles) { if (s.kind !== 'town') continue; s.board = s.board || []; s.board = s.board.filter(q => G.day - q.day < 12); while (s.board.length < 2) {
    const camps = G.settles.filter(c => c.kind === 'camp'); const r = Math.random();
    if (r < .5 && camps.length) { const c = pick(camps); s.board.push({ id: G.nid++, type: 'camp', sid: c.id, from: s.id, fac: s.fac, reward: rint(300, 520), day: G.day, dl: G.day + 20 }); }
    else { const d = pick(G.settles.filter(x => x.kind !== 'camp' && x !== s)); const dist = Math.hypot(d.x - s.x, d.y - s.y); s.board.push({ id: G.nid++, type: 'deliver', sid: d.id, from: s.id, fac: s.fac, reward: Math.round(90 + dist * .22), day: G.day, dl: G.day + Math.ceil(dist / 150) + 4 }); } } }
}
function questText(q) { const s = settleById(q.sid), f = settleById(q.from); return q.type === 'camp' ? 'Разгромить разбойников: «' + s.name + '»' : 'Доставить груз в ' + s.name; }
function acceptQuest(q) { const t = settleById(q.from); if (G.quests.length >= 4) return 'Не больше четырёх заданий одновременно.'; t.board.splice(t.board.indexOf(q), 1); G.quests.push(q); return null; }
function questDone(q, why) { G.quests.splice(G.quests.indexOf(q), 1); if (why) { G.player.gold += q.reward; G.rel[q.fac] = Math.min(100, G.rel[q.fac] + 6); sfx('coin'); logW('Задание выполнено: ' + questText(q) + '. Награда: ' + q.reward + ' золота.', 3); } }

/* ---------- ход времени ---------- */
function speedOf(p) {
  let m = 1, base = 17, any = false, mo = true; for (const s of p.troops) { any = true; if (!TROOPS[s.type].mounted) mo = false; } if (any && mo) base = 22;
  if (p === G.player) { base = (G.player.hero.horse && mo ? 22 : base) + 1; if (G.player.food <= 0) base *= .85; if (G.player.troops.length > 14) base *= .96; }
  const k = cellOf(p.x, p.y), t = WT.cells[k]; m = t === 2 ? .72 : t === 3 ? .78 : 1; if (WT.bio[k] === 1) m *= .85; if (WT.road[k]) m *= 1.3; if (p.kind === 'bandit') m *= 1.04; return base * m;
}
function moveAlong(p, dh) { let rem = speedOf(p) * dh; while (rem > 0 && p.pi < p.path.length) { const t = p.path[p.pi], dx = t.x - p.x, dy = t.y - p.y, d = Math.hypot(dx, dy); if (d <= rem) { p.x = t.x; p.y = t.y; p.pi++; rem -= d; } else { p.x += dx / d * rem; p.y += dy / d * rem; p.fx = dx / d; rem = 0; } } return p.pi >= p.path.length; }
function pathTo(p, x, y) { const pa = findPath(p.x, p.y, x, y); p.path = pa || []; p.pi = 0; return !!pa; }
function stepWorld(dh) {
  const P = G.player;
  if (!P.in) {
    let tg = P.tid != null ? partyById(P.tid) : null; if (P.tid != null && !tg) { P.tid = null; P.path = []; }
    if (tg) { P.rp = (P.rp || 0) - dh; if (P.rp <= 0) { P.rp = .6; if (losClear(P.x, P.y, tg.x, tg.y)) P.path = [{ x: tg.x, y: tg.y }]; else P.path = findPath(P.x, P.y, tg.x, tg.y) || []; P.pi = 0; } }
    if (P.path.length && P.pi < P.path.length) { const arrived = moveAlong(P, dh); if (arrived && !tg) { P.path = []; if (P.sid != null) { const s = settleById(P.sid); P.sid = null; if (s && Math.hypot(s.x - P.x, s.y - P.y) < 40) return { type: 'enter', s }; } } }
    if (tg && Math.hypot(tg.x - P.x, tg.y - P.y) < 24) { P.tid = null; P.path = []; return { type: 'meet', p: tg, forced: false }; }
    for (const p of G.parties) { if (p.hide || p.kind === 'camp') continue; if (Math.hypot(p.x - P.x, p.y - P.y) < 22 && isHostileToPlayer(p) && p.cd <= 0) return { type: 'meet', p, forced: true }; }
  }
  // ИИ
  for (const p of G.parties.slice()) { if (!G.parties.includes(p)) continue; aiParty(p, dh); }
  for (let i = 0; i < G.parties.length; i++) { const a = G.parties[i]; if (a.hide || a.kind === 'camp' || !G.parties.includes(a)) continue; for (let j = i + 1; j < G.parties.length; j++) { const b = G.parties[j]; if (b.hide || b.kind === 'camp' || !G.parties.includes(b)) continue; if (Math.hypot(a.x - b.x, a.y - b.y) < 15 && hostile(a, b)) { autoFight(a, b); break; } } }
  return null;
}
function isHostileToPlayer(p) { if (p.kind === 'bandit' || p.kind === 'camp') return true; if (p.kind === 'caravan') return false; return G.rel[p.fac] < -20; }
function hostile(a, b) { if (a.kind === 'caravan' && b.kind === 'caravan') return false; if (a.kind === 'bandit' && b.fac !== 'bandit') return true; if (b.kind === 'bandit' && a.fac !== 'bandit') return true; return a.fac !== b.fac && atWar(a.fac, b.fac) && a.kind !== 'caravan' && b.kind !== 'caravan'; }
function aiParty(p, dh) {
  if (p.kind === 'camp') return; p.cd -= dh;
  if (p.hide) { p.wait -= dh; if (p.wait <= 0) { p.hide = false; const h = settleById(p.home); if (h) { const need = Math.max(0, 34 - troopCount(p.troops)); if (need > 0 && h.fac === p.fac) { const add = genTroops(p.fac, Math.min(need, rint(4, 10)), .6); for (const a of add) addT(p.troops, a.type, a.n); } } if (p.kind === 'lord') p.state = 'idle'; } return; }
  p.ai = (p.ai || 0) - dh;
  if (p.ai <= 0) { p.ai = rnd(.8, 1.6);
    const me = partyStr(p);
    // охота / бегство
    let tgt = null, tb = 1e9, threat = null;
    for (const o of G.parties) { if (o === p || o.hide || o.kind === 'camp') continue; if (!hostile(p, o)) continue; const d = Math.hypot(o.x - p.x, o.y - p.y); if (d > 260) continue; const so = partyStr(o); if (so < me * (p.kind === 'bandit' ? .9 : .75)) { if (d < tb) { tb = d; tgt = o; } } else if (so > me * 1.2 && d < 190) threat = o; }
    const P = G.player; if (!P.in && hostileToPlayerAI(p)) { const d = Math.hypot(P.x - p.x, P.y - p.y); if (d < 230) { const sp = strength(P.troops) * 1.0 + 6; if (sp < me * .95) { if (d < tb) { tgt = { id: -1, x: P.x, y: P.y, pl: true }; tb = d; } } else if (sp > me * 1.25 && d < 180) threat = P; } }
    if (threat && !tgt) { const a = Math.atan2(p.y - threat.y, p.x - threat.x); const tx = clamp(p.x + Math.cos(a) * 220, 60, WW - 60), ty = clamp(p.y + Math.sin(a) * 220, 60, WH - 60); pathTo(p, tx, ty); p.state = 'flee'; p.tid = null; return; }
    if (tgt) { p.tid = tgt.pl ? -1 : tgt.id; p.state = 'hunt'; pathTo(p, tgt.x, tgt.y); return; }
    if (p.state === 'hunt' || p.state === 'flee') { p.state = 'idle'; p.tid = null; p.path = []; }
    if (p.state === 'idle' && p.pi >= p.path.length) {
      if (p.kind === 'lord') { p.wait -= 1.2; if (p.wait <= 0) { const home = settleById(p.home), targets = G.settles.filter(s => s.fac === p.fac && s.kind !== 'camp'); const d = pick(targets); p.sid = d.id; p.state = 'travel'; pathTo(p, d.x, d.y); } }
      else if (p.kind === 'bandit') { const c = settleById(p.home); const a = rnd(0, TAU), r = rnd(80, 340), tx = clamp((c ? c.x : p.x) + Math.cos(a) * r, 60, WW - 60), ty = clamp((c ? c.y : p.y) + Math.sin(a) * r, 60, WH - 60); if (!pathTo(p, tx, ty)) p.path = []; p.state = 'roam'; }
      else if (p.kind === 'caravan') { p.state = 'travel'; }
    }
  }
  if (p.state === 'hunt') { if (p.tid === -1) { if (!G.player.in) { if (Math.hypot(G.player.x - p.x, G.player.y - p.y) > 300) { p.state = 'idle'; p.path = []; } else if ((p.rp = (p.rp || 0) - dh) <= 0) { p.rp = .7; pathTo(p, G.player.x, G.player.y); } } else { p.state = 'idle'; p.path = []; } } else { const t = partyById(p.tid); if (!t || t.hide) { p.state = 'idle'; p.path = []; } else if ((p.rp = (p.rp || 0) - dh) <= 0) { p.rp = .7; pathTo(p, t.x, t.y); } } }
  if (p.pi < p.path.length) { const done = moveAlong(p, dh); if (done) { if (p.state === 'travel') { const s = settleById(p.sid); if (s && Math.hypot(s.x - p.x, s.y - p.y) < 40) { if (p.kind === 'caravan') { if (s.fac !== 'bandit') { G.parties.splice(G.parties.indexOf(p), 1); return; } } p.hide = true; p.wait = rint(5, 20); p.home = s.id; p.x = s.x; p.y = s.y; p.state = 'idle'; p.path = []; } } else if (p.state === 'roam') { p.state = 'idle'; p.wait = 0; } } }
  else if (p.state === 'travel' && p.kind === 'caravan') { const s = settleById(p.sid); if (s) pathTo(p, s.x, s.y); else G.parties.splice(G.parties.indexOf(p), 1); }
}
function hostileToPlayerAI(p) { return isHostileToPlayer(p); }
function autoFight(a, b) {
  const sa = partyStr(a) * rnd(.8, 1.25), sb = partyStr(b) * rnd(.8, 1.25), w = sa >= sb ? a : b, l = w === a ? b : a, r = Math.min(sa, sb) / Math.max(sa, sb), wl = Math.min(.85, r * .85);
  for (const s of w.troops.slice()) { let d = 0; for (let i = 0; i < s.n; i++) if (Math.random() < wl) d++; remT(w.troops, s.type, d); }
  const li = G.parties.indexOf(l); if (li >= 0) G.parties.splice(li, 1); if (l.kind === 'camp') { /* лагеря не воюют */ }
  if (!w.troops.length || troopCount(w.troops) < 2) { const wi = G.parties.indexOf(w); if (wi >= 0) G.parties.splice(wi, 1); }
  w.state = 'idle'; w.path = []; w.pi = 0; w.cd = 3; w.gold += 20;
}
function hourTick() {
  const P = G.player; G.hour++; if (G.hour >= 24) { G.hour = 0; G.day++; dayTick(); }
  const heal = P.in ? .035 : P.path.length && P.pi < P.path.length ? .006 : .014; P.hero.hp = Math.min(1, P.hero.hp + heal);
  for (const s of G.settles) { if (s.kind === 'camp') { if (s.cleared) { s.respawn -= 1; if (s.respawn <= 0) respawnCamp(s); } continue; } s.rt += 1; if (s.rt >= 72) { s.rt = 0; genRecruits(s); } }
  // спавны
  const bands = G.parties.filter(p => p.kind === 'bandit').length, cars = G.parties.filter(p => p.kind === 'caravan').length;
  if (G.hour % 6 === 0) { if (bands < 5) { const cs = G.settles.filter(s => s.kind === 'camp' && s.camp); if (cs.length && Math.random() < .5) { const c = pick(cs); mkParty('bandit', 'bandit', unitName('bandit') + ' и шайка', c.x + rnd(-30, 30), c.y + rnd(20, 40), genTroops('bandit', rint(9, 18), .4), { home: c.id }); } }
    if (cars < 4 && Math.random() < .5) spawnCaravan(pick(G.settles.filter(s => s.kind === 'town'))); }
  for (const f of ['nord', 'emp', 'khan']) { const n = G.parties.filter(p => p.kind === 'lord' && p.fac === f).length; if (n < 3 && G.hour === 12) { const h = pick(G.settles.filter(s => s.fac === f && s.kind !== 'village')); mkParty('lord', f, lordName(f), h.x + 10, h.y + 20, genTroops(f, rint(18, 30), .6), { home: h.id }); } }
}
function dayTick() {
  const P = G.player; const cnt = troopCount(P.troops); P.food -= Math.max(0, Math.ceil(cnt / 6)) * 1; let wage = 0; for (const s of P.troops) wage += TROOPS[s.type].wage * s.n; wage = Math.round(wage / 3);
  if (P.gold >= wage) P.gold -= wage; else { P.gold = 0; if (cnt > 3 && Math.random() < .6) { const s = pick(P.troops); remT(P.troops, s.type, 1); logW('Не хватило денег на жалованье: ' + TROOPS[s.type].name.toLowerCase() + ' дезертировал.', 1); } }
  if (P.food <= 0) { P.food = 0; if (cnt > 2 && Math.random() < .5) { const s = pick(P.troops); remT(P.troops, s.type, 1); logW('Отряд голодает: боец ушёл.', 1); } else logW('Закончилась провизия!', 1); }
  for (const q of G.quests.slice()) if (G.day > q.dl) { G.quests.splice(G.quests.indexOf(q), 1); G.rel[q.fac] = Math.max(-100, G.rel[q.fac] - 4); logW('Срок задания истёк: ' + questText(q), 1); }
  genQuests(); for (const f of ['nord', 'emp', 'khan']) G.rel[f] = G.rel[f] > 0 ? G.rel[f] - .1 : G.rel[f] < 0 ? Math.min(0, G.rel[f] + .25) : 0;
}
function wageDay() { let w = 0; for (const s of G.player.troops) w += TROOPS[s.type].wage * s.n; return Math.round(w / 3); }

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
