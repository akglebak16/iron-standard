/* ================= войны фракций (только одиночная игра) =================
   Фракции воюют и мирятся сами, собирают армии (созыв), осаждают чужие города и замки и забирают их себе. Поселения
   меняют владельца, государство без городов и замков падает. Столкновения отрядов ИИ идут часами (схватка), игрок может вмешаться.
   Состояние лежит в G: wars (пары фракций), wcamp (кампании), skirm (схватки). Поселение под осадой хранит s.siege.
   Файл не загружается на сервере: сетевая игра живёт по старым правилам (серверные хуки проверяют typeof). */

const WK = (a, b) => a < b ? a + '|' + b : b + '|' + a;
const nowH = () => G.day * 24 + G.hour;
function warInit() {
  clanInit();
  if (G.wars) return;
  G.wars = {}; const F = worldF(); for (const a in WAR) for (const b in WAR[a]) if (a !== 'bandit' && b !== 'bandit' && F.includes(a) && F.includes(b)) G.wars[WK(a, b)] = { since: G.day };
  G.wcamp = G.wcamp || {}; G.skirm = G.skirm || [];
}
function holdOf(f) { let t = 0, c = 0, v = 0; for (const s of G.settles) if (s.fac === f) { if (s.kind === 'town') t++; else if (s.kind === 'castle') c++; else if (s.kind === 'village') v++; } return { t, c, v, all: t + c + v, core: t + c }; }
function facAlive(f) { return holdOf(f).core > 0; }
function facsAlive() { return worldF().filter(facAlive); }
function facPower(f) { let s = 0; for (const p of G.parties) if (p.fac === f && isNoble(p)) s += partyStr(p); const h = holdOf(f); return s + h.t * 90 + h.c * 70 + h.v * 12; }
const CLANS_PER_F = 4, CLAN_SIZE = 2, VASS_PER_F = 4; // у каждой фракции по 4 рода по 2 лорда и по 4 вассала, независимо от размера земель
const warLords = f => CLANS_PER_F * CLAN_SIZE;
const warVass = f => VASS_PER_F;
/* оборона поселения: гарнизон с множителем стен; у государства на краю гибели защитники бьются отчаянней */
function siegeDef(s) { const h = holdOf(s.fac); return (strength(garrisonOf(s)) + 4) * (1.8 + (h.core <= 3 ? .8 : h.core <= 5 ? .35 : 0)); }
function wlog(msg, kind) { for (const P of G.players) logW(msg, kind || 2, P); if (!SERVER && typeof toast === 'function') toast(msg); }

/* ---------- дипломатия: раз в сутки ---------- */
function warDay() {
  warInit();
  const A = facsAlive();
  for (const k of Object.keys(G.wars)) { const [a, b] = k.split('|'); if (!A.includes(a) || !A.includes(b)) delete G.wars[k]; }
  const wc = f => Object.keys(G.wars).filter(k => k.split('|').includes(f)).length;
  for (let i = 0; i < A.length; i++) for (let j = i + 1; j < A.length; j++) {
    const a = A[i], b = A[j], k = WK(a, b), w = G.wars[k], pa = facPower(a), pb = facPower(b), r = Math.max(pa, pb) / Math.max(1, Math.min(pa, pb));
    if (w) { const d = G.day - w.since; if (d < 10) continue; const weak = Math.min(holdOf(a).all, holdOf(b).all) < 9 ? 3 : 1; if (Math.random() < clamp(.012 + d * .0005, 0, .07) * (r > 1.7 ? .35 : 1) * weak * rulerPeace(a, b)) { delete G.wars[k]; wlog(FACTIONS[a].name + ' и ' + FACTIONS[b].name + ' заключили мир.', 2); } }
    else { if (wc(a) >= 3 || wc(b) >= 3 || kingless(a) || kingless(b)) continue; if (!borders(a, b)) continue; const lone = (!wc(a) ? 3 : 1) * (!wc(b) ? 2 : 1), top = (pa > pb ? pa : pb) / Math.max(1, (pa + pb) / 2); if (Math.random() < .005 * lone * top * rulerWar(a, b)) { G.wars[k] = { since: G.day }; wlog(FACTIONS[(pa > pb ? a : b)].name + ' объявляет войну: ' + FACTIONS[(pa > pb ? b : a)].name + '.', 2); } }
  }
  for (const P of G.players) vassalDay(P);
  clanDay();
  facTally();
}
function borders(a, b) { // у фракций есть соседние поселения (не дальше 900)
  for (const s of G.settles) if (s.fac === a && s.kind !== 'village') for (const t of G.settles) if (t.fac === b && Math.hypot(s.x - t.x, s.y - t.y) < 900) return true; return false;
}
let _tally = 0;
function facTally() { // раз в 10 суток: сообщение о том, кто сильнее всех
  if (++_tally % 10) return; const A = facsAlive().map(f => [f, holdOf(f).all]).sort((x, y) => y[1] - x[1]), tot = G.settles.filter(s => s.kind !== 'camp').length;
  if (A.length && A[0][1] > tot * .5) wlog(FACTIONS[A[0][0]].name + ' правит больше половины земель (' + A[0][1] + ' из ' + tot + ').', 2);
}

/* ---------- кампании: созыв армий, поход, осада ---------- */
function warLordsOf(f) { return G.parties.filter(p => isNoble(p) && p.fac === f && !p.lock && !p.ruler); } // правитель в поход не ходит
function warHour() {
  warInit();
  if (G.hour % 2 === 0) { for (const f of facsAlive()) warCamp(f); for (const s of G.settles) if (s.siege) siegeTick(s); }
  skirmHour();
  if (G.hour === 12) clanRefill();
}
function warCamp(f) {
  if (!G.wcamp[f] && kingless(f)) return; // без правителя новый поход не начинают
  const enemies = facsAlive().filter(e => e !== f && atWar(f, e)); let c = G.wcamp[f];
  if (c) { // проверки: война закончилась, цель сменила владельца, армия растаяла
    const t = settleById(c.tid), army = c.army.map(partyById).filter(p => p && p.fac === f && p.army);
    if (!t || !enemies.includes(t.fac) || army.length === 0) return campEnd(f, 'цель потеряна');
    if (c.state === 'muster') { const ar = army.filter(p => p.arrived).length; if (ar >= Math.ceil(army.length * .7) || nowH() - c.t0 > 40) { c.state = 'march'; c.t1 = nowH(); for (const p of army) campGo(p, t); } else for (const p of army) if (p.pi >= p.path.length && !p.arrived) campGo(p, settleById(c.gid)); }
    else if (c.state === 'march') { const near = army.filter(p => Math.hypot(p.x - t.x, p.y - t.y) < 80); if (near.length >= Math.ceil(army.length * .5) || nowH() - c.t1 > 70) beginSiege(f, t, c); else for (const p of army) if (p.pi >= p.path.length) campGo(p, t); }
    else if (c.state === 'siege') { if (!t.siege) { c.state = 'rest'; c.t2 = nowH(); } }
    else if (c.state === 'rest') { if (nowH() - c.t2 > 72) return campEnd(f, 'передышка'); }
    return;
  }
  if (!enemies.length) return;
  const lords = warLordsOf(f).filter(p => troopCount(p.troops) >= 20 * MK()); if (lords.length < 2 && lords.reduce((a, p) => a + partyStr(p), 0) < 220 * MK()) return;
  if (G.hour % 6 !== 0) return;
  const mine = G.settles.filter(s => s.fac === f && s.kind !== 'camp'); if (!mine.length) return;
  let best = null, bs = 1e9; const power = lords.reduce((a, p) => a + partyStr(p), 0);
  for (const t of G.settles) { if (!enemies.includes(t.fac) || t.kind === 'camp' || t.siege) continue; if (t.kind === 'village') continue; const def = siegeDef(t); if (power < def * .9) continue; let md = 1e9, ms = null; for (const s of mine) { const d = Math.hypot(s.x - t.x, s.y - t.y); if (d < md) { md = d; ms = s; } } const sc = md + def * .6 + rnd(0, 120); if (sc < bs) { bs = sc; best = { t, ms }; } }
  if (!best) return;
  const army = lords.filter(p => !p.fight); if (!army.length) return;
  G.wcamp[f] = c = { tid: best.t.id, gid: best.ms.id, state: 'muster', t0: nowH(), army: army.map(p => p.id), a0: 0 };
  for (const p of army) { p.army = true; p.arrived = false; p.hide = false; p.wait = 0; p.x = p.hide ? p.x : p.x; campGo(p, best.ms); }
  wlog(FACTIONS[f].name + ' созывает войска: поход на ' + best.t.name + '.', 2);
  for (const P of G.players) if (P.liege === f) { P.call = { tid: best.t.id, until: nowH() + 96, joined: false }; logW('Твой сюзерен зовёт тебя в поход: ' + best.t.name + '. Будь рядом, когда начнётся осада.', 3, P); }
}
function campGo(p, s) { if (!s) return; p.state = 'travel'; p.sid = s.id; p.tid = null; const ok = pathTo(p, s.x + rnd(-26, 26), s.y + rnd(18, 40)); if (!ok) p.path = []; p.arrived = false; p.hide = false; }
function campEnd(f, why) {
  const c = G.wcamp[f]; if (c) for (const id of c.army) { const p = partyById(id); if (p) { p.army = false; p.arrived = false; p.state = 'idle'; p.path = []; p.pi = 0; p.wait = rint(1, 4); const h = G.settles.filter(s => s.fac === f && s.kind !== 'camp').sort((a, b) => Math.hypot(a.x - p.x, a.y - p.y) - Math.hypot(b.x - p.x, b.y - p.y))[0]; if (h) { p.home = h.id; p.sid = h.id; p.state = 'travel'; pathTo(p, h.x, h.y); } } }
  delete G.wcamp[f];
}
function beginSiege(f, t, c) {
  const army = c.army.map(partyById).filter(p => p && p.army); c.state = 'siege';
  for (const p of army) { p.state = 'idle'; p.path = []; p.pi = 0; p.arrived = true; }
  if (t.siege) return; const g = garrisonOf(t);
  t.siege = { f, t0: nowH(), a0: Math.max(1, army.reduce((a, p) => a + partyStr(p), 0)), g0: Math.max(1, troopCount(g)) };
  wlog(FACTIONS[f].name + ' осаждает ' + t.name + '.', 2);
}
function siegeTick(s) {
  const sg = s.siege, att = G.parties.filter(p => p.army && p.fac === sg.f && Math.hypot(p.x - s.x, p.y - s.y) < 100 && !p.fight);
  const lift = why => { delete s.siege; wlog('Осада ' + s.name + ' снята' + (why ? ': ' + why : '') + '.', 2); };
  if (!att.length) return lift('осаждающих разбили');
  const g = garrisonOf(s), A = att.reduce((a, p) => a + partyStr(p), 0), D = siegeDef(s), k = A / D, dur = nowH() - sg.t0;
  const lossD = clamp(.05 * k, .01, .12), lossA = clamp(.035 / k, .005, .08);
  for (const t of g.slice()) remT(g, t.type, Math.round(t.n * lossD + (Math.random() < t.n * lossD % 1 ? 1 : 0)));
  for (const p of att) for (const t of p.troops.slice()) remT(p.troops, t.type, Math.round(t.n * lossA));
  for (const p of att.slice()) if (troopCount(p.troops) < 6) G.parties.splice(G.parties.indexOf(p), 1);
  const left = troopCount(g);
  if (left <= Math.max(7, sg.g0 * .16) && dur >= 12) return warCapture(s, sg.f, att);
  if (A < sg.a0 * .3) return lift('силы осаждающих иссякли');
  if (dur > 110) { if (k > 1.25) return warCapture(s, sg.f, att); return lift('осада затянулась'); }
}
function warCapture(s, f, att) {
  const old = s.fac, t0 = s.kind; delete s.siege; s.cult = sCult(s);
  const garN = (s.kind === 'castle' ? 90 : 70) * MK(), tot = Math.max(1, att.reduce((a, p) => a + troopCount(p.troops), 0)), share = Math.min(.5, garN / tot), take = [];
  for (const p of att) for (const t of p.troops.slice()) { const n = Math.round(t.n * share); if (n > 0) { remT(p.troops, t.type, n); take.push([t.type, n]); } }
  s.fac = f; s.owner = null; s.board = []; s.gar = []; for (const [ty, n] of take) addT(s.gar, ty, n); if (troopCount(s.gar) < 25 * MK()) for (const a of genTroops(f, 25, .5)) addT(s.gar, a.type, a.n); sortT(s.gar); genRecruits(s); s.market = null; s.ruin = 0;
  for (const p of G.parties.slice()) if (isNoble(p) && p.fac === old && p.hide && p.home === s.id) { const h = G.settles.find(q => q.fac === old && q.kind !== 'camp' && q !== s); if (h) { p.home = h.id; p.hide = false; p.x = h.x; p.y = h.y + 20; p.state = 'idle'; } else G.parties.splice(G.parties.indexOf(p), 1); }
  for (const v of G.settles) if (v.kind === 'village' && v.fac === old && Math.hypot(v.x - s.x, v.y - s.y) < 170) { v.cult = sCult(v); v.fac = f; }
  wlog(FACTIONS[f].name + ' берёт ' + (t0 === 'castle' ? 'замок ' : 'город ') + s.name + ' (бывший ' + FACTIONS[old].gen + ').', 2);
  for (const P of G.players) { if (P.liege === f && P.call && !P.call.joined && att.some(p => true) && Math.hypot(P.x - s.x, P.y - s.y) < 220) { P.call.joined = true; vassalReward(P, s); } }
  clanLoss(old, f, s);
  if (!facAlive(old)) facFall(old, f);
}
function facFall(old, by) {
  wlog('Государство «' + FACTIONS[old].name + '» пало.', 2);
  for (const c of clansOf(old)) clanDefect(c, by, true); // роды павшего государства переходят к победителю
  for (const v of G.settles) if (v.fac === old) { v.cult = sCult(v); v.fac = by; }
  for (const p of G.parties.slice()) if (p.fac === old && p.kind !== 'caravan') G.parties.splice(G.parties.indexOf(p), 1); else if (p.fac === old) G.parties.splice(G.parties.indexOf(p), 1);
  if (G.rul) delete G.rul[old]; delete G.wcamp[old]; for (const k of Object.keys(G.wars)) if (k.split('|').includes(old)) delete G.wars[k];
  for (const P of G.players) if (P.liege === old) { P.liege = null; logW('Твой сюзерен пал. Ты свободен от присяги.', 1, P); }
}

/* ---------- схватки отрядов ИИ: бой идёт часами ---------- */
function warContact(a, b) {
  const small = x => troopCount(x.troops) < 12 * MK();
  if (a.kind === 'caravan' || b.kind === 'caravan' || (small(a) && small(b))) return autoFight(a, b);
  warInit(); const side = (x, o) => G.parties.filter(c => c !== o && !c.hide && c.kind !== 'camp' && !c.fight && !c.lock && c.fac === x.fac && Math.hypot(c.x - x.x, c.y - x.y) < 70 && !hostile(c, o) && c.kind !== 'caravan');
  const A = side(a, b), B = side(b, a); if (!A.includes(a)) A.push(a); if (!B.includes(b)) B.push(b);
  const sk = { id: G.nid++, A: A.map(p => p.id), B: B.map(p => p.id), t0: nowH(), x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, a0: 0, b0: 0 };
  sk.a0 = A.reduce((n, p) => n + troopCount(p.troops), 0); sk.b0 = B.reduce((n, p) => n + troopCount(p.troops), 0);
  for (const p of A.concat(B)) { p.fight = sk.id; p.path = []; p.pi = 0; p.tid = null; p.state = 'idle'; }
  G.skirm.push(sk);
}
const skSide = (sk, ids) => ids.map(partyById).filter(p => p && p.fight === sk.id);
function skirmHour() {
  if (!G.skirm || !G.skirm.length) return;
  for (const sk of G.skirm.slice()) {
    // подмога: отряды рядом, враждебные одной стороне и дружеские другой, вступают в схватку
    for (const p of G.parties) { if (p.fight || p.hide || p.kind === 'camp' || p.kind === 'caravan' || p.lock || Math.hypot(p.x - sk.x, p.y - sk.y) > 90) continue;
      const A = skSide(sk, sk.A), B = skSide(sk, sk.B); if (!A.length || !B.length) break; const hA = A.some(q => hostile(p, q)), hB = B.some(q => hostile(p, q));
      if (hB && !hA) { sk.A.push(p.id); p.fight = sk.id; sk.a0 += troopCount(p.troops); } else if (hA && !hB) { sk.B.push(p.id); p.fight = sk.id; sk.b0 += troopCount(p.troops); }
      if (p.fight) { p.path = []; p.pi = 0; p.tid = null; p.state = 'idle'; } }
    const A = skSide(sk, sk.A), B = skSide(sk, sk.B), men = L => L.reduce((n, p) => n + troopCount(p.troops), 0);
    if (!A.length || !B.length) { skEnd(sk, A, B, A.length ? 0 : 1); continue; }
    const sa = A.reduce((n, p) => n + partyStr(p), 0), sb = B.reduce((n, p) => n + partyStr(p), 0), la = clamp(.16 * sb / sa, .02, .4) * rnd(.85, 1.15), lb = clamp(.16 * sa / sb, .02, .4) * rnd(.85, 1.15);
    const hit = (L, l) => { for (const p of L) for (const t of p.troops.slice()) { const f = t.n * l, n = Math.floor(f) + (Math.random() < f % 1 ? 1 : 0); if (n > 0) remT(p.troops, t.type, n); } };
    hit(A, la); hit(B, lb);
    const A2 = A.filter(p => troopCount(p.troops) > 0), B2 = B.filter(p => troopCount(p.troops) > 0);
    for (const p of A.concat(B)) if (troopCount(p.troops) < 1 && !rulerSpare(p)) G.parties.splice(G.parties.indexOf(p), 1);
    const ma = men(A2), mb = men(B2);
    if (!A2.length || !B2.length || ma < sk.a0 * .25 || mb < sk.b0 * .25) skEnd(sk, A2, B2, (!A2.length || (B2.length && ma / Math.max(1, sk.a0) < mb / Math.max(1, sk.b0))) ? 1 : 0);
  }
}
function skEnd(sk, A, B, winner) { // winner: 0 — побеждает A, 1 — B
  const W = winner ? B : A, Lz = winner ? A : B, lostMen = (winner ? sk.a0 : sk.b0) - Lz.reduce((n, p) => n + troopCount(p.troops), 0);
  G.skirm.splice(G.skirm.indexOf(sk), 1);
  for (const p of W) { p.fight = null; p.state = 'idle'; p.path = []; p.pi = 0; p.cd = 3; p.gold += 20 + Math.round(lostMen * 2); if (p.fac === 'undead') undeadRaise(p, Math.max(0, lostMen) * UNDEAD.RAISE); }
  for (const p of Lz) { p.fight = null; p.cd = 6; if ((troopCount(p.troops) < 8 && !rulerSpare(p)) || p.kind === 'bandit') { const i = G.parties.indexOf(p); if (i >= 0) G.parties.splice(i, 1); } else { const w = W[0], ang = w ? Math.atan2(p.y - w.y, p.x - w.x) : rnd(0, TAU); p.state = 'flee'; pathTo(p, clamp(p.x + Math.cos(ang) * 240, 60, WW - 60), clamp(p.y + Math.sin(ang) * 240, 60, WH - 60)); } }
}
/* помощь соседям: сила дружеских отрядов рядом учитывается, когда отряд решает, нападать ли */
function warAllyStr(p) { let s = 0; for (const o of G.parties) if (o !== p && o.fac === p.fac && !o.hide && !o.fight && !o.army && o.kind !== 'caravan' && o.kind !== 'camp' && Math.hypot(o.x - p.x, o.y - p.y) < 150) s += partyStr(o) * .85; return s; }
function warRally(p, tgt) { // соседи той же фракции идут на ту же цель
  for (const o of G.parties) { if (o === p || o.fac !== p.fac || o.hide || o.fight || o.army || o.kind === 'caravan' || o.kind === 'camp' || o.lock || o.state === 'hunt') continue; if (Math.hypot(o.x - p.x, o.y - p.y) > 160) continue; o.state = 'hunt'; o.tid = tgt.id; o.tpl = null; pathTo(o, tgt.x, tgt.y); }
}

/* ---------- вассальство игрока ---------- */
const OATH_REL = 20, OATH_LVL = 2;
function oathCan(P, f) { if (P.liege) return 'Ты уже служишь: ' + FACTIONS[P.liege].name + '.'; if (!REAL_F.includes(f) || !facAlive(f)) return 'Нельзя.'; if ((P.hero.lvl || 1) < OATH_LVL) return 'Нужен ' + OATH_LVL + ' уровень героя.'; if (P.rel[f] < OATH_REL) return 'Нужны отношения от ' + OATH_REL + ' (сейчас ' + Math.round(P.rel[f]) + '). Выполняй задания и бей врагов фракции.'; if (G.wars && Object.keys(G.wars).length === 0) return 'Сейчас мир: сюзерену нужны воины для войны. Подожди, пока начнётся.'; return null; }
function swear(P, f) { const why = oathCan(P, f); if (why) return why; P.liege = f; P.oathDay = G.day; P.strikes = 0; P.call = null; P.rel[f] = Math.min(100, P.rel[f] + 10); vassalEnemies(P); relWatch(P); logW('Ты принёс присягу: ' + FACTIONS[f].name + '. Враги сюзерена — твои враги, взамен он платит жалованье и награждает за походы.', 3, P); return null; }
function leaveService(P, why) { const f = P.liege; if (!f) return; P.liege = null; P.call = null; if (why === 'betray') P.rel[f] = Math.min(P.rel[f], -45); else if (why === 'expelled') P.rel[f] = Math.max(-100, P.rel[f] - 15); else P.rel[f] = Math.max(-100, P.rel[f] - 20); relWatch(P); logW(why === 'expelled' ? 'Сюзерен изгнал тебя со службы за неповиновение.' : why === 'betray' ? 'Ты предал сюзерена!' : 'Ты оставил службу: ' + FACTIONS[f].name + '.', why ? 1 : 2, P); }
function vassalEnemies(P) { if (!P.liege || !G.wars) return; for (const f of REAL_F) if (f !== P.liege && atWar(P.liege, f) && P.rel[f] > -25) P.rel[f] = -25; }
function vassalReward(P, s) { const g = 120 + (s.kind === 'castle' ? 160 : s.kind === 'town' ? 120 : 0); P.gold += g; P.rel[P.liege] = Math.min(100, P.rel[P.liege] + 6); logW('Ты участвовал во взятии ' + s.name + ': награда ' + g + ' золота.', 3, P); if ((s.kind === 'village' || Math.random() < .4) && !P.fief) { captureSettle(P, s); logW('Сюзерен жалует тебе ' + s.name + ' в лен.', 3, P); } }
function vassalDay(P) {
  if (!P.liege) return; const f = P.liege; if (!facAlive(f)) { P.liege = null; return; }
  const pay = 16 + (P.hero.lvl || 1) * 6; P.gold += pay; vassalEnemies(P);
  if (P.call && nowH() > P.call.until) { if (!P.call.joined) { P.strikes = (P.strikes || 0) + 1; P.rel[f] = Math.max(-100, P.rel[f] - 5); logW('Ты не явился на зов сюзерена (' + P.strikes + '/3).', 1, P); if (P.strikes >= 3) leaveService(P, 'expelled'); } P.call = null; }
}


/* ---------- рода: у каждой фракции 4 рода по 2 лорда; род можно переманить целиком ---------- */
const CLAN_TR = {
  loyal: { n: 'Верный', d: 'держится присяги, почти не склонен к измене', base: 88, thr: 10, ch: .12, cost: 2, luck: .25 },
  greedy: { n: 'Корыстный', d: 'продаётся тому, кто больше платит', base: 62, thr: 30, ch: .5, cost: .7, luck: 1 },
  ambit: { n: 'Честолюбивый', d: 'тянется к сильному и побеждающему', base: 60, thr: 42, ch: .7, cost: 1.2, luck: 1 },
  proud: { n: 'Обидчивый', d: 'помнит обиды и потери земель', base: 62, thr: 34, ch: .5, cost: 1.1, luck: 1 },
  fickle: { n: 'Переменчивый', d: 'легко меняет сторону', base: 50, thr: 44, ch: 1, cost: .8, luck: 1.4 },
};
const CLAN_DEF_CD = 60, CLAN_FAC_CD = 30, CLAN_MIN = 2, CLAN_MAX = 6, LURE_CD = 20;
const clansOf = f => (G.clans || []).filter(c => c.fac === f);
const clanById = id => (G.clans || []).find(c => c.id === id);
const clanOf = p => p && p.clan != null ? clanById(p.clan) : null;
const clanMembers = c => G.parties.filter(p => p.kind === 'lord' && p.clan === c.id);
const clanFree = c => clanMembers(c).every(p => !p.lock && !p.fight && !p.army);
const clanForce = c => clanMembers(c).reduce((a, p) => a + troopCount(p.troops), 0);
function clanLabel(n) { const g = /ий$/.test(n) ? n.slice(0, -2) + 'ия' : /[йь]$/.test(n) ? n.slice(0, -1) + 'я' : /[аеёиоуыэюя]$/.test(n) ? n : n + 'а'; return 'Дом ' + g; }
function clanInit() {
  if (G.clans || !G.settles || !G.parties) return;
  G.clans = []; G.clanSw = {}; G.cid = 1;
  const kinds = Object.keys(CLAN_TR), pool = ['loyal', 'loyal', 'greedy', 'greedy', 'ambit', 'ambit', 'proud', 'proud', 'fickle'];
  for (const f of facsAlive()) {
    const hs = G.settles.filter(s => s.fac === f && s.kind !== 'village' && s.kind !== 'camp'), used = new Set(), free = G.parties.filter(p => p.kind === 'lord' && p.fac === f && p.clan == null);
    for (let i = 0; i < CLANS_PER_F; i++) {
      let nm, k = 0; do nm = pick(FACTIONS[f].names); while (used.has(nm) && ++k < 30); used.add(nm);
      const tr = pick(pool), h = hs[i % hs.length], c = { id: G.cid++, fac: f, name: clanLabel(nm), trait: tr, loy: CLAN_TR[tr].base + rint(-8, 8), home: h ? h.id : null, cd: 0, vac: 0 };
      G.clans.push(c); for (let j = 0; j < CLAN_SIZE && free.length; j++) free.shift().clan = c.id;
    }
  }
}
function clanLoss(old, f, s) { // фракция потеряла поселение: роды недовольны, у победителя довольны
  for (const c of clansOf(old)) { c.loy = Math.max(0, c.loy - (c.home === s.id ? 18 : c.trait === 'proud' ? 9 : 5)); if (c.home === s.id) { const h = G.settles.find(q => q.fac === old && q.kind !== 'village' && q.kind !== 'camp' && q !== s); c.home = h ? h.id : null; } }
  for (const c of clansOf(f)) c.loy = Math.min(100, c.loy + 4);
}
function clanSettle(f, x, y) { let best = null, bd = 1e9; for (const s of G.settles) if (s.fac === f && s.kind !== 'village' && s.kind !== 'camp') { const d = Math.hypot(s.x - x, s.y - y); if (d < bd) { bd = d; best = s; } } return best; }
function clanDefect(c, to, forced) {
  const from = c.fac, mem = clanMembers(c), h = clanSettle(to, mem.length ? mem[0].x : 0, mem.length ? mem[0].y : 0);
  c.fac = to; c.rule = false; c.cd = G.day + CLAN_DEF_CD; c.loy = Math.max(55, c.loy); if (h) c.home = h.id; if (!forced) G.clanSw[from] = G.day;
  for (const p of mem) { p.fac = to; p.ruler = false; p.name = lordName(to); p.army = false; p.arrived = false; p.state = 'idle'; p.path = []; p.pi = 0; p.tid = null; p.sid = null; if (h) { p.home = h.id; p.hide = false; p.x = h.x + rint(-10, 10); p.y = h.y + 20; } }
  wlog(c.name + ' (' + CLAN_TR[c.trait].n.toLowerCase() + ' род) переходит от ' + FACTIONS[from].gen + ' к ' + FACTIONS[to].gen + '.', 2);
}
function clanDay() {
  if (!G.clans) return;
  rulerDay();
  const A = facsAlive();
  for (const c of G.clans) {
    const T = CLAN_TR[c.trait]; c.loy += c.loy < T.base ? 1 : c.loy > T.base ? -1 : 0;
    if (!A.includes(c.fac) || c.rule || G.day < c.cd || c.loy > T.thr || Math.random() > T.ch * .08) continue;
    if (clansOf(c.fac).length <= CLAN_MIN || G.day - (G.clanSw[c.fac] || -99) < CLAN_FAC_CD || !clanFree(c)) continue;
    let best = null, bp = 0; for (const e of A) if (e !== c.fac && atWar(c.fac, e) && clansOf(e).length < CLAN_MAX) { const pw = facPower(e); if (pw > bp) { bp = pw; best = e; } }
    if (!best || (c.trait === 'ambit' && bp < facPower(c.fac) * 1.15)) continue;
    clanDefect(c, best, false);
  }
}
function clanRefill() { // погиб лорд: через пару дней в роду появляется новый родич
  if (!G.clans) return;
  for (const c of G.clans) {
    if (!facAlive(c.fac)) continue; const n = clanMembers(c).length; if (n >= CLAN_SIZE) { c.vac = 0; continue; }
    if (!c.vac) c.vac = G.day + (c.born ? 3 : 0); if (G.day < c.vac) continue;
    let h = settleById(c.home); if (!h || h.fac !== c.fac) { h = clanSettle(c.fac, 0, 0); c.home = h ? h.id : null; } if (!h) continue;
    mkParty('lord', c.fac, lordName(c.fac), h.x + 10, h.y + 20, genTroops(c.fac, rint(LORD_NEW_MIN, LORD_NEW_MAX), .6), { home: h.id, clan: c.id }); c.born = 1; c.vac = 0;
  }
}
/* переманивание рода игроком: только вассал может звать род к своему сюзерену */
function lureCost(c) { return Math.round((400 + clanForce(c) * 5) * CLAN_TR[c.trait].cost / 10) * 10; }
function lureChance(P, c) {
  const T = CLAN_TR[c.trait], L = P.liege; let ch = (100 - c.loy) / 130 + P.rel[L] / 500 + (P.hero.lvl || 1) * .008;
  if (c.trait === 'ambit' && facPower(L) > facPower(c.fac) * 1.2) ch += .15; if (c.trait === 'proud' && c.loy < 45) ch += .1; if (c.trait === 'greedy') ch += .08;
  return clamp(ch * T.luck, .03, .8);
}
function lureCan(P, p) {
  const c = clanOf(p); if (!c) return 'Это не знатный род.'; if (c.rule) return 'Это правящий род: он не предаст трон.'; if (!P.liege) return 'Звать род к себе может только вассал: присягни фракции.'; if (c.fac === P.liege) return 'Они и так служат твоему сюзерену.';
  if (!facAlive(P.liege)) return 'Сюзерен пал.'; if (G.day < (P.lureDay || -99) + LURE_CD) return 'Ты недавно уже вёл переговоры. Подожди ' + (Math.ceil((P.lureDay || 0) + LURE_CD - G.day)) + ' дн.';
  if (G.day < c.cd) return 'Род недавно сменил сторону и пока не станет метаться.'; if (clansOf(c.fac).length <= CLAN_MIN) return 'Этот дом остался без союзников и не покинет своё государство.';
  if (clansOf(P.liege).length >= CLAN_MAX) return 'У твоего сюзерена уже слишком много родов.'; return null;
}
function lureTry(P, p) {
  const c = clanOf(p), why = lureCan(P, p); if (why) return { ok: false, txt: why }; const cost = lureCost(c); if (P.gold < cost) return { ok: false, txt: 'Нужно ' + cost + ' золота.' };
  P.lureDay = G.day; const L = P.liege, from = c.fac;
  if (Math.random() < lureChance(P, c)) { P.gold -= cost; clanDefect(c, L, false); const back = Math.round(cost * .4); P.gold += back; P.rel[L] = Math.min(100, P.rel[L] + 6); P.rel[from] = Math.max(-100, P.rel[from] - 10); relWatch(P); logW(c.name + ' перешёл на сторону ' + FACTIONS[L].gen + '. Сюзерен возместил ' + back + ' золота.', 3, P); return { ok: true, txt: c.name + ' переходит к ' + FACTIONS[L].gen + '!' }; }
  P.gold -= Math.round(cost * .5); P.rel[from] = Math.max(-100, P.rel[from] - 8); relWatch(P); logW('Переговоры с ' + c.name + ' провалились: золото потеряно.', 1, P); return { ok: false, txt: c.name + ' отказал и забрал половину задатка.' };
}


/* ---------- правитель: глава одного из родов; погиб, и до выборов нового фракция не начинает походы ---------- */
const RTITLE = { nord: 'Конунг', emp: 'Император', khan: 'Хан', kin: 'Король', emi: 'Эмир', dom: 'Великий князь', pact: 'Король' };
const RTRAIT = { war: ['воинственный', 1.6, .6], peace: ['миролюбивый', .5, 1.6], norm: ['рассудительный', 1, 1] };
const rulerOf = f => G.parties.find(p => p.ruler && p.fac === f && p.kind === 'lord');
const kingless = f => !!(G.rul && G.rul[f] && G.rul[f].dead);
const rulerTr = f => (G.rul && G.rul[f] && RTRAIT[G.rul[f].trait]) || RTRAIT.norm;
const rulerWar = (a, b) => (rulerTr(a)[1] + rulerTr(b)[1]) / 2;
const rulerPeace = (a, b) => (rulerTr(a)[2] + rulerTr(b)[2]) / 2;
function rulerPick(f) {
  const lords = G.parties.filter(p => p.kind === 'lord' && p.fac === f && p.clan != null); if (!lords.length) return false;
  const rc = clansOf(f).find(c => c.rule); let cand = rc ? clanMembers(rc) : []; if (!cand.length) cand = lords;
  const best = cand.slice().sort((a, b) => troopCount(b.troops) - troopCount(a.troops))[0], c = clanOf(best);
  for (const x of clansOf(f)) x.rule = false; c.rule = true; best.ruler = true; best.name = RTITLE[f] + ' ' + best.name.split(' ').slice(1).join(' ');
  for (const a of genTroops(f, 50, .7)) addT(best.troops, a.type, a.n); sortT(best.troops);
  const tr = pick(['war', 'peace', 'norm', 'norm']); G.rul = G.rul || {}; G.rul[f] = { trait: tr, dead: 0, until: 0, name: best.name };
  wlog(best.name + ' (' + RTRAIT[tr][0] + ') правит: ' + FACTIONS[f].name + '.', 2); return true;
}
function rulerDay() {
  G.rul = G.rul || {};
  for (const f of facsAlive()) {
    if (rulerOf(f)) { if (G.rul[f]) G.rul[f].dead = 0; continue; }
    const r = G.rul[f];
    if (!r) { rulerPick(f); continue; }
    if (!r.dead) { r.dead = G.day; r.until = G.day + 5; for (const c of clansOf(f)) c.loy = Math.max(0, c.loy - 10); wlog(r.name + ' пал. ' + FACTIONS[f].name + ' без правителя, роды колеблются.', 2); }
    else if (G.day >= r.until) rulerPick(f);
  }
}
function rulerHome(p) { // правитель отходит в своё поселение и собирает новую дружину
  const h = settleById(p.home), s = h && h.fac === p.fac ? h : clanSettle(p.fac, p.x, p.y); if (s) { p.home = s.id; p.x = s.x; p.y = s.y + 20; p.hide = true; p.wait = rint(8, 16); }
  p.fight = null; p.state = 'idle'; p.path = []; p.pi = 0; p.cd = 6; if (troopCount(p.troops) < 90 * MK()) for (const a of genTroops(p.fac, Math.ceil((90 * MK() - troopCount(p.troops)) / MK()), .6)) addT(p.troops, a.type, a.n); sortT(p.troops);
}
function rulerSpare(p) { if (!p.ruler || Math.random() > .78) return false; rulerHome(p); return true; } // телохранители выводят правителя из боя
