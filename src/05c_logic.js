/* ================= игровая логика, общая для клиента и сервера ================= */
function xpNeed(l) { return 100 + l * 80; }
const xpMul = H => 1 + ((H.int || 1) - 1) * .03 + perkFx(H).xp; // опыт: +3% за очко Интеллекта и перк «Сообразительный»
function heroBattle(H) { heroFix(H); return { name: H.name, str: H.str, vit: H.vit, agi: H.agi, int: H.int, cha: H.cha, perks: H.perks.slice(), eq: Object.assign({}, heroEq(H)), sel: H.sel || 'melee', hp: H.hp, seed: H.seed }; } // снаряжение — слотами (см. 01b_gear.js)
function townEnter(P, s) {
  P.in = s.id; P.path = []; P.pi = 0; P.tid = null; P.sid = null;
  for (const q of P.quests.slice()) if (q.type === 'deliver' && q.sid === s.id) questDone(P, q, true);
  P.rel[s.fac] = Math.min(100, P.rel[s.fac] + .5);
}
function doHire(P, s, type, n) {
  const r = s.recruits.find(x => x.type === type), t = TROOPS[type]; if (!r) return false;
  const c = hireCost(P, type); n = Math.min(n, r.n, Math.floor(P.gold / c), sizeCap(P.hero) - troopCount(P.troops)); if (n < 1) return false;
  P.gold -= n * c; addT(P.troops, type, n); r.n -= n; if (r.n <= 0) s.recruits.splice(s.recruits.indexOf(r), 1); return true;
}
function doGear(P, k) { const H = P.hero, nx = GEAR[k] && GEAR[k][H[k] + 1]; if (!nx || P.gold < nx.p) return false; P.gold -= nx.p; H[k]++; return true; }
function doFood(P, n, price) { const opt = [[10, 22], [30, 60], [80, 150]].find(o => o[0] === n && o[1] === price); if (!opt || P.gold < price) return false; P.gold -= price; P.food += n; return true; }
function doUpgrade(P, type, up) {
  const t = TROOPS[type], s = P.troops.find(x => x.type === type); if (!s || !t.up.includes(up)) return 0; const c = upgCost(P, type), n = Math.min(s.n, Math.floor(P.gold / c)); if (n < 1) return 0;
  P.gold -= n * c; remT(P.troops, type, n); addT(P.troops, up, n); return n;
}
function doAttr(P, k) { const H = heroFix(P.hero); if (!ATTRS[k] || H.pts < 1) return false; H.pts--; H[k]++; return true; }
function doPerk(P, id) { const H = P.hero; if (perkWhy(H, id)) return false; H.pp--; H.perks.push(id); return true; } // перки: см. 01c_perks.js
function doAccept(P, s, qid) { const q = (s.board || []).find(x => x.id === qid); if (!q) return 'Задание уже взято.'; return acceptQuest(P, q); }

/* ---------- встреча и бой ---------- */
function relativePowerOf(P, p) { const a = strength(P.troops) + 8, b = p.str !== undefined && !p.troops ? p.str : partyStr(p); const r = a / Math.max(1, b); return r > 2 ? ['Мы сильнее', 'g'] : r > 1.15 ? ['Мы чуть сильнее', 'g'] : r > .8 ? ['Силы равны', 'b'] : r > .45 ? ['Они сильнее', 'r'] : ['Они намного сильнее', 'r']; }
function encAttack(P, p) { P.rel[p.fac] = Math.max(-100, P.rel[p.fac] - (p.kind === 'caravan' ? 12 : 30)); logW('Ты напал на ' + FACTIONS[p.fac].gen + '. Отношения испорчены.', 1, P); }
function encFlee(P, p) {
  const ch = clamp(.45 + (speedOf(P) - speedOf(p)) * .06 - (p.kind === 'camp' ? .3 : 0) + perkFx(P.hero).flee, .12, .9);
  if (Math.random() < ch) { p.cd = 6; p.state = 'idle'; p.path = []; p.lock = null; const a = Math.atan2(P.y - p.y, P.x - p.x); P.x = clamp(P.x + Math.cos(a) * 40, 20, WW - 20); P.y = clamp(P.y + Math.sin(a) * 40, 20, WH - 20); return true; }
  return false;
}
function battleCfgFor(P, p) {
  return { pl: P.troops.map(s => ({ type: s.type, n: s.n })), en: p.troops.map(s => ({ type: s.type, n: s.n })), pfac: 'player', efac: p.fac, biome: biomeName(P.x, P.y), forest: terrAt(P.x, P.y) === 2,
    title: p.kind === 'camp' ? 'Штурм логова' : 'Бой: ' + p.name, hero: heroBattle(P.hero), heroPid: P.id, leader: p.kind === 'lord' ? p.name : null, seed: rint(1, 1e9) };
}
function autoResult(P, p) {
  const H = P.hero, sv = perkFx(H).surv, sa = strength(P.troops) + 10, sb = partyStr(p), me = sa * rnd(.8, 1.25), foe = sb * rnd(.8, 1.25), win = me >= foe, r = Math.min(me, foe) / Math.max(me, foe);
  const res = { win, dead: {}, wounded: {}, left: {}, enemyDead: 0, enemyTotal: troopCount(p.troops), xp: Math.round(sb * .25), heroDown: false, heroHp: clamp(H.hp - (win ? r * .35 : .55), .25, 1), heroKills: 0, enemyLeft: {}, auto: true, time: 0 };
  for (const s of P.troops) { let d = 0, w = 0; const pk = win ? r * .75 : .9; for (let i = 0; i < s.n; i++) { if (Math.random() < pk) { if (Math.random() < .35 + sv) w++; else d++; } } if (d) res.dead[s.type] = d; if (w) res.wounded[s.type] = w; res.left[s.type] = s.n - d; }
  if (win) res.enemyDead = res.enemyTotal; else for (const s of p.troops) { res.enemyLeft[s.type] = Math.max(1, s.n - Math.floor(s.n * r * .6)); res.enemyDead += s.n - res.enemyLeft[s.type]; }
  return res;
}
function applyBattleResult(P, res, p) {
  const H = heroFix(P.hero), F = perkFx(H); let loot = 0, lvl = 0;
  for (const k in res.dead) remT(P.troops, k, res.dead[k]);
  H.hp = clamp(res.heroHp, .22, 1);
  const lost = Object.values(res.dead).reduce((a, b) => a + b, 0), wounded = Object.values(res.wounded).reduce((a, b) => a + b, 0);
  if (res.win) {
    let sv = 0; for (const s of p.troops) sv += s.n * (TROOPS[s.type].tier * 9 + 6);
    loot = Math.round((sv * rnd(.7, 1.1) + (p.gold || 0) + (p.kind === 'camp' ? 120 : 0)) * (1 + F.loot)); P.gold += loot; P.food += p.kind === 'caravan' ? rint(10, 30) : rint(0, 8);
    P.stats.wins++; P.stats.kills += res.enemyDead; const gx = Math.round((res.xp + 12 + res.heroKills * 4) * xpMul(H)); H.xp += gx; res.gx = gx;
    const pi = G.parties.indexOf(p); if (pi >= 0) G.parties.splice(pi, 1);
    if (p.kind === 'camp') { const c = settleById(p.camp); if (c) { c.camp = null; c.cleared = true; c.respawn = 24 * 9; } for (const q of P.quests.slice()) if (q.type === 'camp' && q.sid === p.camp) questDone(P, q, true); }
    if (p.kind === 'bandit' || p.kind === 'camp') P.rel[P.culture] = Math.min(100, P.rel[P.culture] + 1);
    logW('Победа над отрядом «' + p.name + '». Добыча: ' + loot + ' золота.', 3, P);
  } else {
    const keep = Math.round(P.gold * .25); res.lostGold = keep; P.gold -= keep; H.xp += Math.round(res.xp * .5 * xpMul(H));
    if (res.enemyLeft && Object.keys(res.enemyLeft).length) p.troops = Object.keys(res.enemyLeft).map(k => ({ type: k, n: res.enemyLeft[k] }));
    p.cd = 10; p.state = 'idle'; p.path = []; p.lock = null;
    if (!troopCount(P.troops)) { const t = G.settles.filter(s => s.kind === 'town').sort((a, b) => Math.hypot(a.x - P.x, a.y - P.y) - Math.hypot(b.x - P.x, b.y - P.y))[0]; P.x = t.x + 10; P.y = t.y + 34; res.woke = t.name; if (P.gold < 60) P.gold += 80; }
    logW('Ты потерпел поражение от «' + p.name + '».', 1, P);
  }
  while (H.xp >= xpNeed(H.lvl)) { H.xp -= xpNeed(H.lvl); H.lvl++; H.pts += PTS_LEVEL; H.pp += PP_LEVEL; lvl++; }
  if (lvl) { sfx('level'); logW('Новый уровень: ' + H.lvl + '. Очки: атрибуты +' + PTS_LEVEL * lvl + ', перки +' + PP_LEVEL * lvl + '.', 3, P); }
  return { res, loot, lvl, lost, wounded, win: res.win, lvlNow: H.lvl };
}
