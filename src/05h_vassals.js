/* ================= вассалы-спутники: надел, подать, своя дружина =================
   Только одиночная игра (на сервер этот файл не грузится; общий код зовёт его через typeof-проверки).
   Спутника можно посадить на своё владение (город или замок). Он:
   • платит игроку подать — CV_TRIB от чистого дохода надела, остальное копит в своей казне;
   • сам содержит гарнизон надела (игрок за него больше не платит и не получает полный доход);
   • на свою казну нанимает дружину — отряд на карте (party.kind === 'cvass', fac 'player');
   • дружина стоит у надела, ходит дозором за врагами или идёт за игроком (приказ), бьётся с врагами игрока по тем же
     правилам схваток, что и отряды лордов, и помогает гарнизону отбить штурм.
   Хранится в P.vass = [{ cid, c (сам спутник), sid (надел), mode, gold, pid (отряд на карте), rest, day }]. Надел помечен s.vass = cid.
   Новых полей синхронизации нет, симуляция сервера не затронута. */
const CV_TRIB = .3;      // доля чистого дохода надела, которую вассал отдаёт сюзерену
const CV_MAX = 3;        // вассалов у одного игрока
const CV_REST = 3;       // дней, пока разбитая дружина собирается заново
const CV_MODES = { guard: ['Охранять надел', 'дружина стоит у надела и бьёт тех, кто подошёл близко'], patrol: ['Дозор', 'дружина ходит по округе и охотится на слабых врагов'], follow: ['За мной', 'дружина идёт за тобой и держится рядом'] };
const cvList = P => P.vass || [];
const cvOfId = (P, cid) => cvList(P).find(v => v.cid === cid) || null;
const cvAtSettle = s => { if (!s || s.vass === undefined) return null; for (const P of G.players) { const v = cvOfId(P, s.vass); if (v && v.sid === s.id) return v; } return null; };
const cvPartyOf = v => (v && v.pid != null ? G.parties.find(p => p.id === v.pid && p.kind === 'cvass') || null : null);
const cvFiefs = P => G.settles.filter(s => s.fac === 'player' && s.owner === P.id && (s.kind === 'town' || s.kind === 'castle'));
const cvCap = v => Math.round((40 + (v.c.lvl || 1) * 6 + (v.c.cha || 1) * 6) * MK());
const cvIncome = s => Math.max(0, settleIncome(s) - garUpkeep(s)); // чистый доход надела за день (до подати)
function cvCan(P, cid, sid) {
  if (NET.on || typeof SERVER !== 'undefined' && SERVER) return 'Вассалы есть только в одиночной игре.';
  const c = compById(P, cid), s = settleById(sid); if (!c) return 'Этого спутника нет в отряде.';
  if (cvList(P).length >= CV_MAX) return 'Не больше ' + CV_MAX + ' вассалов.';
  if (!s || s.fac !== 'player' || s.owner !== P.id || (s.kind !== 'town' && s.kind !== 'castle')) return 'Надел — это твой город или замок.';
  if (s.vass !== undefined) return 'Здесь уже сидит вассал.';
  return '';
}
function cvGrant(P, cid, sid) {
  const why = cvCan(P, cid, sid); if (why) return why;
  const c = compById(P, cid), s = settleById(sid); P.comps.splice(P.comps.indexOf(c), 1);
  if (!P.vass) P.vass = []; const v = { cid, c, sid, mode: 'guard', gold: 0, pid: null, rest: 0, day: G.day }; P.vass.push(v); s.vass = cid;
  cvSpawn(P, v);
  logW(c.name + ' получает в надел ' + s.name + ' и присягает тебе. Подать: ' + Math.round(CV_TRIB * 100) + '% дохода, остальное он тратит на дружину.', 3, P); return '';
}
function cvSpawn(P, v) {
  const s = settleById(v.sid); if (!s) return null; const old = cvPartyOf(v); if (old) return old;
  const p = mkParty('cvass', 'player', v.c.name, s.x + rnd(-20, 20), s.y + 24, genTroops(sCult(s), 4, .45), { owner: P.id, cid: v.cid, home: s.id, state: 'idle' }); sortT(p.troops); v.pid = p.id; v.rest = 0; return p;
}
/* снять надел: дружина распускается в гарнизон, казна уходит игроку, спутник возвращается в отряд (или ждёт в таверне, если места нет) */
function cvRevoke(P, cid, why) {
  const v = cvOfId(P, cid); if (!v) return false; const s = settleById(v.sid), p = cvPartyOf(v);
  if (p) { if (s && s.fac === 'player' && s.owner === P.id) { const g = garrisonOf(s); for (const t of p.troops) addT(g, t.type, t.n); sortT(g); } G.parties.splice(G.parties.indexOf(p), 1); }
  P.vass.splice(P.vass.indexOf(v), 1); if (s && s.vass === cid) delete s.vass;
  if (v.gold > 0) { P.gold += Math.round(v.gold); }
  const c = v.c; if (compsOf(P).length < COMP_MAX) { P.comps.push(c); logW(c.name + (why || ' оставляет надел') + ' и возвращается в твой отряд. Казна вассала (' + Math.round(v.gold) + ') — тебе.', 1, P); }
  else { compsInit(); G.cstate[cid] = c; const near = compTowns().sort((a, b) => Math.hypot(a.x - (s || P).x, a.y - (s || P).y) - Math.hypot(b.x - (s || P).x, b.y - (s || P).y))[0]; if (near) G.cpos[cid] = near.id; logW(c.name + (why || ' оставляет надел') + ': в отряде нет места, он ждёт в таверне' + (near ? ' ' + near.name : '') + '.', 1, P); }
  return true;
}
const cvTroopCost = t => TROOPS[t].cost || 40;
const cvWage = p => { let w = 0; for (const t of p.troops) w += TROOPS[t.type].wage * t.n; return Math.round(w / 3); }; // содержание полевой дружины в день
/* раз в сутки: доход надела, подать, найм, жалованье */
function cvDay(P) {
  for (const v of cvList(P).slice()) {
    const s = settleById(v.sid);
    if (!s || s.fac !== 'player' || s.owner !== P.id) { logW(v.c.name + ' потерял надел' + (s ? ' ' + s.name : '') + ' и вернулся к тебе.', 1, P); cvRevoke(P, v.cid, ' лишился надела'); continue; }
    let p = cvPartyOf(v);
    if (!p) { if (v.pid != null) { v.pid = null; v.rest = CV_REST; logW('Дружина ' + v.c.name + ' разбита. Он соберёт новую за ' + CV_REST + ' дн.', 1, P); } else if (--v.rest <= 0) p = cvSpawn(P, v); }
    const net = cvIncome(s), trib = Math.round(net * CV_TRIB); P.gold += trib; v.gold += net - trib; v.trib = trib; v.inc = net;
    if (!p) continue;
    const up = cvWage(p); v.gold -= up; v.up = up;
    if (v.gold < 0) { v.gold = 0; for (const t of p.troops.slice()) remT(p.troops, t.type, Math.ceil(t.n * .08)); if (!p.troops.length) for (const a of genTroops(sCult(s), 1, .3, true)) addT(p.troops, a.type, a.n); logW('Казна ' + v.c.name + ' пуста: дружина без жалованья, часть людей разбежалась.', 1, P); continue; }
    // найм: на 60% казны сверх запаса на трое суток жалованья, пока дружина меньше предела
    let budget = v.gold - up * 3, room = cvCap(v) - troopCount(p.troops), spent = 0;
    if (budget > 25 && room > 0) { for (const a of genTroops(sCult(s), Math.min(6, Math.ceil(room / MK())), .55)) for (let i = 0; i < a.n && budget * .6 >= cvTroopCost(a.type) && room > 0; i++) { const c = cvTroopCost(a.type); budget -= c; spent += c; room--; addT(p.troops, a.type, 1); } }
    if (spent) { v.gold -= spent; sortT(p.troops); }
    v.n = troopCount(p.troops);
  }
}
// сила дружины, которая стоит у надела: помогает гарнизону при штурме. Вернёт { str, p } или { str: 0 }
function cvDefStr(s) { const v = cvAtSettle(s); const p = cvPartyOf(v); if (!p || p.hide || Math.hypot(p.x - s.x, p.y - s.y) > 90) return { str: 0, p: null }; return { str: partyStr(p), p }; }
function cvDefHit(p, r, win) { if (!p) return; for (const t of p.troops.slice()) remT(p.troops, t.type, Math.round(t.n * r * (win ? .3 : .5))); if (troopCount(p.troops) < 1) { const i = G.parties.indexOf(p); if (i >= 0) G.parties.splice(i, 1); } }

/* ---------- ИИ дружины ---------- */
function cvAI(p, dh) {
  const P = G.players.find(q => q.id === p.owner), v = P && cvOfId(P, p.cid), s = v && settleById(v.sid);
  if (!v || !s) { const i = G.parties.indexOf(p); if (i >= 0) G.parties.splice(i, 1); return; }
  p.ai = (p.ai || 0) - dh;
  if (p.ai <= 0) { p.ai = rnd(.8, 1.6);
    const me = partyStr(p), mode = v.mode || 'guard', R = mode === 'guard' ? 150 : 260; let tgt = null, tb = 1e9, threat = null;
    for (const o of G.parties) { if (o === p || o.hide || o.kind === 'camp' || o.fight || o.lock || !hostile(p, o)) continue; const d = Math.hypot(o.x - p.x, o.y - p.y); if (d > R || mode === 'guard' && Math.hypot(o.x - s.x, o.y - s.y) > 230) continue; const so = partyStr(o);
      if (so < me * .8) { if (d < tb) { tb = d; tgt = o; } } else if (so > me * 1.2 && d < 150) threat = o; }
    if (threat && !tgt) { const home = mode === 'follow' && P && !P.away ? P : s; p.state = 'flee'; p.tid = null; pathTo(p, home.x, home.y); }
    else if (tgt) { p.tid = tgt.id; p.state = 'hunt'; pathTo(p, tgt.x, tgt.y); }
    else {
      if (p.state === 'hunt' || p.state === 'flee') { p.state = 'idle'; p.tid = null; }
      if (p.pi >= p.path.length) {
        if (mode === 'follow' && P && !P.away) { if (Math.hypot(P.x - p.x, P.y - p.y) > 70) { pathTo(p, P.x + rnd(-40, 40), P.y + rnd(20, 50)); p.state = 'travel'; } }
        else if (mode === 'patrol') { const a = rnd(0, TAU), r = rnd(80, 300); if (pathTo(p, clamp(s.x + Math.cos(a) * r, 60, WW - 60), clamp(s.y + Math.sin(a) * r, 60, WH - 60))) p.state = 'travel'; }
        else { const far = Math.hypot(s.x - p.x, s.y - p.y) > 110; if (far || Math.random() < .25) { const a = rnd(0, TAU), r = far ? 20 : rnd(30, 90); if (pathTo(p, clamp(s.x + Math.cos(a) * r, 60, WW - 60), clamp(s.y + 22 + Math.sin(a) * r, 60, WH - 60))) p.state = 'travel'; } }
      }
    }
  }
  if (p.state === 'hunt') { const t = partyById(p.tid); if (!t || t.hide) { p.state = 'idle'; p.path = []; p.tid = null; } else if ((p.rp = (p.rp || 0) - dh) <= 0) { p.rp = .7; pathTo(p, t.x, t.y); } }
  if (p.pi < p.path.length) { if (moveAlong(p, dh) && p.state === 'travel') { p.state = 'idle'; p.path = []; p.pi = 0; } }
}

/* ---------- дружины вассалов вступают в бой игрока ----------
   Как у врагов (encHelpers/encMerge): дружины вассалов рядом (ENC_HELP_R) идут в бой вместе с игроком. В cfg.pl их бойцы добавляются к отряду игрока,
   после боя потери каждого типа делятся между стеками по числу бойцов. Игрок теряет только свою долю, дружины — свою. На карте они остаются. */
let CVB = null; // { p: враг, al: [{ h: отряд вассала, tr: [{type,n}] }] }
function cvHelpers(P, p) {
  if (NET.on || ['camp', 'siege', 'caravan'].includes(p.kind)) return [];
  return G.parties.filter(o => o.kind === 'cvass' && o.owner === P.id && o !== p && !o.hide && !o.fight && !o.lock && troopCount(o.troops) > 0 && hostile(o, p) && Math.min(Math.hypot(o.x - p.x, o.y - p.y), Math.hypot(o.x - P.x, o.y - P.y)) < ENC_HELP_R);
}
function cvBattleStart(P, p, al) { CVB = al && al.length ? { p, al: al.filter(h => G.parties.includes(h)).map(h => ({ h, tr: h.troops.map(s => ({ type: s.type, n: s.n })) })) } : null; if (CVB && !CVB.al.length) CVB = null; }
function cvAllyTroops(p) { const out = []; if (CVB && CVB.p === p) for (const a of CVB.al) for (const s of a.tr) addT(out, s.type, s.n); return out; }
function cvBattleEnd(P, res, p) {
  const C = CVB; CVB = null; if (!C || C.p !== p) return;
  const lostBy = C.al.map(() => 0); let total = 0;
  for (const kind of ['dead', 'wounded']) for (const k of Object.keys(res[kind] || {})) {
    const D = res[kind][k], mine = (P.troops.find(s => s.type === k) || { n: 0 }).n, stacks = [mine].concat(C.al.map(a => (a.tr.find(s => s.type === k) || { n: 0 }).n)), tot = stacks.reduce((a, b) => a + b, 0);
    if (!tot) continue; const sh = stacks.map(n => Math.floor(D * n / tot)); let rest = D - sh.reduce((a, b) => a + b, 0); for (let i = 0; rest > 0; i = (i + 1) % sh.length) if (stacks[i] > 0) { sh[i]++; rest--; }
    res[kind][k] = sh[0]; if (!sh[0]) delete res[kind][k];
    if (kind === 'dead') C.al.forEach((a, i) => { if (sh[i + 1] > 0 && G.parties.includes(a.h)) { remT(a.h.troops, k, sh[i + 1]); lostBy[i] += sh[i + 1]; total += sh[i + 1]; } });
  }
  C.al.forEach((a, i) => { const h = a.h; if (!G.parties.includes(h)) return; if (troopCount(h.troops) < 1) G.parties.splice(G.parties.indexOf(h), 1); else { h.cd = Math.max(h.cd, 2); h.state = 'idle'; h.path = []; h.pi = 0; }
    logW('Дружина «' + h.name + '» билась рядом с тобой' + (lostBy[i] ? ', павших: ' + lostBy[i] : '') + '.', 3, P); });
  res.allyDead = total;
}
