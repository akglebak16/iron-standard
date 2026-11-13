/* ================= кризис: нашествие нежити =================
   Общий для клиента и сервера: без DOM. Случайный день между 40-м и 60-м: 1–2 разбойничьих логова становятся Чёрными курганами,
   из них идут большие армии мертвецов и разъезды. Нежити много, но она слабая (см. войска z1…s3 в 01_core.js, множитель силы pw).
   Мертвецы враждебны всем: игроку, лордам, вассалам, караванам и разбойникам. Побеждая, они поднимают павших (армия растёт).
   Армии жгут деревни (нет рекрутов несколько дней) и штурмуют замки и города: взятое поселение становится руинами нежити
   с гарнизоном мертвецов. Руины можно отбить: игрок — осадой, лорды своей фракции — штурмом. Отбитое поселение
   несколько дней восстанавливается (доход и рекруты урезаны).
   Новые армии идут только из курганов, у каждого кургана запас армий. Разрушить курган может только игрок (бой с ним, как с логовом).
   Кризис кончается, когда разрушены все курганы и перебиты все отряды нежити.
   Хранение: G.crisis = { day, on, done, src: [id логова], left: { id логова: сколько армий ещё выйдет } }.
   Поля поселений: s.barrow (курган), s.burnt (часов до восстановления деревни), s.ruinOf (чьё было до нежити), s.ruin (часов восстановления).
   В игре вдвоём кризис пока не начинается (crisisDay вызывается только в браузере). */

const UNDEAD = { ARMY_MIN: 350, ARMY_MAX: 500, RAID_MIN: 40, RAID_MAX: 80, MAX_ARMY: 700, RAISE: .5, ARMIES_PER_SRC: 6, ARMIES_AT_ONCE: 3, RAIDS_AT_ONCE: 3, SPAWN_EVERY: 3, BURN_H: 24 * 6, RUIN_H: 24 * 10 };
const isUndead = p => p && p.fac === 'undead';

/* состав: больше всего мертвецов и скелетов, немного воинов и всадников, редкие умертвия */
function genUndead(n, elite) {
  const out = {}, w = [['z1', 40], ['s1', 28], ['s1a', 15], ['s2', 11 + (elite || 0) * 6], ['s2c', 5], ['s3', 1 + (elite || 0) * 3]], tot = w.reduce((a, x) => a + x[1], 0);
  for (let i = 0; i < n; i++) { let r = Math.random() * tot; for (const x of w) { r -= x[1]; if (r <= 0) { out[x[0]] = (out[x[0]] || 0) + 1; break; } } }
  return Object.keys(out).map(k => ({ type: k, n: out[k] }));
}
function undeadRaise(p, n) { n = Math.min(Math.round(n), UNDEAD.MAX_ARMY - troopCount(p.troops)); if (n > 0) addT(p.troops, 'z1', n); return Math.max(0, n); }
function notifyAll(txt, kind, near) { for (const P of G.players) { if (near && Math.hypot(near.x - P.x, near.y - P.y) > 700 && !(near.owner === P.id)) continue; logW(txt, kind, P); } if (!SERVER && typeof toast === 'function' && kind === 1 && !near) toast(txt); }

/* ---------- ход кризиса ---------- */
function crisisInit() { if (!G.crisis) G.crisis = { day: G.day > 35 ? G.day + rint(5, 15) : rint(40, 60), on: false, done: false, src: [], left: {} }; return G.crisis; }
function crisisDay() {
  const C = crisisInit(); if (C.done) return;
  if (!C.on) { if (G.day >= C.day) crisisStart(); return; }
  if (G.day % UNDEAD.SPAWN_EVERY === 0) for (const id of C.src) { const s = settleById(id); if (s && s.barrow) crisisSpawn(s); }
  const alive = C.src.some(id => { const s = settleById(id); return s && s.barrow; }), any = G.parties.some(p => isUndead(p) && p.kind !== 'camp');
  if (!alive && !any) { C.on = false; C.done = true; notifyAll('Нашествие мёртвых отбито! Курганы разрушены, армии нежити истреблены.', 3); if (!SERVER && typeof toast === 'function') toast('Нашествие мёртвых отбито!'); }
}
function crisisStart() {
  const C = G.crisis, camps = G.settles.filter(s => s.kind === 'camp'), n = isEU() ? 2 : 1, src = [];
  for (let i = 0; i < n && camps.length; i++) { // курганы подальше друг от друга
    let best = null, bd = -1; for (let k = 0; k < 12; k++) { const c = pick(camps); if (src.includes(c)) continue; const d = src.length ? Math.min(...src.map(o => Math.hypot(o.x - c.x, o.y - c.y))) : rnd(); if (d > bd) { bd = d; best = c; } } if (best) src.push(best);
  }
  C.on = true; C.src = src.map(s => s.id); C.left = {};
  for (const s of src) {
    if (s.camp) { const i = G.parties.indexOf(s.camp); if (i >= 0) G.parties.splice(i, 1); }
    s.barrow = true; s.fac = 'undead'; s.cleared = false; s.name0 = s.name0 || s.name; s.name = 'Чёрный курган'; C.left[s.id] = UNDEAD.ARMIES_PER_SRC;
    s.camp = mkParty('camp', 'undead', 'Чёрный курган', s.x, s.y, genUndead(rint(110, 140), 1), { home: s.id, hide: false }); s.camp.camp = s.id;
    crisisSpawn(s, true);
  }
  const where = src.map(s => { const t = G.settles.filter(x => x.kind === 'town').sort((a, b) => Math.hypot(a.x - s.x, a.y - s.y) - Math.hypot(b.x - s.x, b.y - s.y))[0]; return t ? 'у ' + t.name : ''; }).join(' и ');
  notifyAll('Мёртвые восстали! Из Чёрных курганов ' + where + ' идут армии нежити. Они жгут деревни и берут замки. Разрушь курганы, чтобы остановить нашествие.', 1);
}
function crisisSpawn(s, first) {
  const C = G.crisis, mine = G.parties.filter(p => isUndead(p) && p.src === s.id), armies = mine.filter(p => p.kind === 'dead').length, raids = mine.filter(p => p.kind === 'raid').length;
  if (armies < UNDEAD.ARMIES_AT_ONCE && C.left[s.id] > 0) { C.left[s.id]--; const p = mkParty('dead', 'undead', 'Некромант ' + unitName('undead'), s.x + rnd(-20, 20), s.y + 26, genUndead(rint(UNDEAD.ARMY_MIN, UNDEAD.ARMY_MAX), 0), { home: s.id, src: s.id }); p.state = 'idle'; p.wait = first ? 0 : rint(0, 4); if (!first) notifyAll('Из Чёрного кургана вышла новая армия мертвецов.', 1, s); }
  for (let i = raids; i < UNDEAD.RAIDS_AT_ONCE && (first ? i < 2 : i < raids + 1); i++) { const p = mkParty('raid', 'undead', 'Мертвецы', s.x + rnd(-30, 30), s.y + rnd(10, 40), genUndead(rint(UNDEAD.RAID_MIN, UNDEAD.RAID_MAX), 0), { home: s.id, src: s.id }); p.state = 'idle'; p.wait = rint(0, 6); }
}

/* ---------- ИИ отрядов нежити (вызывается из aiParty, когда отряду нечем заняться) ---------- */
function undeadIdle(p) {
  const army = p.kind === 'dead', R = army ? 1100 : 600;
  let c = G.settles.filter(s => s.kind !== 'camp' && s.fac !== 'undead' && !(s.kind === 'village' && s.burnt) && Math.hypot(s.x - p.x, s.y - p.y) < R);
  if (army) { const big = c.filter(s => s.kind !== 'village'); if (big.length && Math.random() < .55) c = big; } else c = c.filter(s => s.kind === 'village');
  c.sort((a, b) => Math.hypot(a.x - p.x, a.y - p.y) - Math.hypot(b.x - p.x, b.y - p.y)); const d = c.length ? pick(c.slice(0, 4)) : null;
  if (d) { p.sid = d.id; p.state = 'travel'; if (!pathTo(p, d.x, d.y + 20)) { p.state = 'idle'; p.wait = 3; } }
  else { const a = rnd(0, TAU); pathTo(p, clamp(p.x + Math.cos(a) * 300, 60, WW - 60), clamp(p.y + Math.sin(a) * 300, 60, WH - 60)); p.state = 'roam'; }
}
function undeadArrive(p, s) { // нежить у поселения: деревню жжёт, замок или город штурмует (расчётом)
  p.state = 'idle'; p.path = []; p.pi = 0; p.wait = rint(1, 4); if (s.fac === 'undead') return;
  if (s.kind === 'village') { s.burnt = UNDEAD.BURN_H; s.recruits = []; const k = undeadRaise(p, rint(4, 10)); notifyAll('Нежить сожгла деревню ' + s.name + (k ? ' и подняла ' + k + ' мертвецов' : '') + '.', 1, s); return; }
  const g = garrisonOf(s), lords = G.parties.filter(q => q.hide && q.home === s.id && q.fac === s.fac && isNoble(q)), def0 = troopCount(g) + lords.reduce((a, q) => a + troopCount(q.troops), 0);
  let ds = strength(g) + 4; for (const q of lords) ds += partyStr(q);
  const att = partyStr(p) * rnd(.8, 1.2), def = ds * 1.3 * rnd(.8, 1.2), r = Math.min(att, def) / Math.max(att, def), O = ownerOf(s);
  if (att > def) {
    for (const t of p.troops.slice()) remT(p.troops, t.type, Math.round(t.n * r * .55));
    for (const q of lords) { const i = G.parties.indexOf(q); if (i >= 0) G.parties.splice(i, 1); }
    const was = s.fac; s.cult = sCult(s); s.ruinOf = was === 'player' ? (s.ruinOf || s.cult) : was; s.fac = 'undead'; s.owner = null; s.board = []; s.recruits = []; s.ruin = 0;
    const gn = Math.max(25, Math.round(troopCount(p.troops) * .2)); for (const t of p.troops.slice()) remT(p.troops, t.type, Math.round(t.n * gn / Math.max(1, troopCount(p.troops)))); s.gar = genUndead(gn, 0); addT(s.gar, 'z1', Math.round(def0 * UNDEAD.RAISE * .5)); sortT(s.gar);
    undeadRaise(p, def0 * UNDEAD.RAISE * .5);
    const txt = (s.kind === 'town' ? 'Город ' : 'Замок ') + s.name + ' пал под натиском мертвецов' + (lords.length ? ', ' + lords.map(q => q.name).join(', ') + ' погиб' + (lords.length > 1 ? 'ли' : '') + ' при обороне' : '') + '. Теперь это руины нежити.';
    for (const P of G.players) logW(txt, 1, P); if (!SERVER && typeof toast === 'function' && O === G.player) toast(s.name + ' пал под натиском мертвецов!');
  } else {
    for (const t of g.slice()) remT(g, t.type, Math.round(t.n * r * .4));
    for (const t of p.troops.slice()) remT(p.troops, t.type, Math.round(t.n * (.35 + r * .4)));
    notifyAll('Гарнизон ' + s.name + ' отбил натиск мертвецов.', 3, s);
  }
  if (troopCount(p.troops) < 8) { const i = G.parties.indexOf(p); if (i >= 0) G.parties.splice(i, 1); }
}
/* лорд или вассал своей фракции подошёл к руинам: штурмует (расчётом) */
function nobleRetake(p, s) {
  const g = garrisonOf(s), att = partyStr(p) * rnd(.8, 1.2), def = (strength(g) + 4) * 1.5 * rnd(.8, 1.2), r = Math.min(att, def) / Math.max(att, def);
  if (att > def) { for (const t of p.troops.slice()) remT(p.troops, t.type, Math.round(t.n * r * .5)); s.fac = p.fac; s.ruin = UNDEAD.RUIN_H; s.gar = genTroops(p.fac, 20, .5); s.recruits = []; notifyAll(p.name + ' отбил ' + s.name + ' у мертвецов.', 3, s); return true; }
  for (const t of g.slice()) remT(g, t.type, Math.round(t.n * r * .4)); for (const t of p.troops.slice()) remT(p.troops, t.type, Math.round(t.n * (.3 + r * .4)));
  return false;
}
/* руины, которые лорд этой фракции хочет отбить */
const ruinsFor = f => G.settles.filter(s => s.fac === 'undead' && s.kind !== 'camp' && s.ruinOf === f);
/* после победы нежити в бою с игроком: павшие встают в её строй */
function undeadAfterWin(p, lost) { if (isUndead(p)) return undeadRaise(p, lost * UNDEAD.RAISE); return 0; }
/* курган разрушен игроком: логово снова становится обычным (потом там заведутся разбойники) */
function barrowDestroyed(P, c) {
  c.barrow = false; c.fac = 'bandit'; c.name = c.name0 || c.name; if (G.crisis) G.crisis.left[c.id] = 0;
  for (const f of REAL_F) P.rel[f] = Math.min(100, (P.rel[f] || 0) + 5);
  logW('Чёрный курган разрушен! Отсюда больше не выйдут мертвецы. Все фракции благодарны тебе (+5 к отношениям).', 3, P);
}
/* часы: деревни отстраиваются, руины восстанавливаются */
function undeadHour() { for (const s of G.settles) { if (s.burnt > 0 && --s.burnt <= 0) { s.burnt = 0; genRecruits(s); } if (s.ruin > 0 && s.fac !== 'undead') s.ruin--; } }
