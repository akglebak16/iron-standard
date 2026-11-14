/* ================= бой в реальном времени ================= */
let B = null;
const US = 0.31;
const VIEW = { w: 800, h: 600, dpr: 1 };
const IN = { keys: {}, mx: 0, my: 0, atk: false, block: false, jx: 0, jy: 0, touch: false, sprint: false };
const ORD_NAME = { hold: 'Держат', follow: 'За тобой', charge: 'В атаке', back: 'Отходят' };

const BATTLE_CAP = SERVER ? 150 : 150 * MASS, JOIN_CAP = 40, UNDEAD_CAP = SERVER ? 300 : 300 * MASS; // нежити на поле больше фигур: она берёт числом // юнитов на сторону в бою; и сколько юнитов приводит второй игрок, присоединившийся к бою
function heroDef(h) { // параметры героя считаются из надетого (слоты и оружие в руках — см. 01b_gear.js)
  const Gr = heroGear(h), W = Gr.W, m = Gr.mounted, F = perkFx(h), heavy = W.hands === 2 && !W.rng ? F.heavy : 0; // перки: см. 01c_perks.js
  return { id: 'hero', name: h.name, tier: 3, cls: m ? 'cav' : 'inf', grp: 0, mounted: m, range: W.rng ? Math.round(W.range * (1 + F.range)) : 0, reach: 9 + (W.reach || 0), fac: 'player', up: [], wpn: W, acc: (W.acc || .05) * (1 - F.acc) * ACC_K, shb: heroShield(h) ? shieldArrow(heroShield(h).look) : 0, anticav: W.anticav ? 1 : 0,
    cd: (W.rng ? Math.max(.35, W.cd * (1 - h.agi * .025)) : Math.max(.3, .56 - h.agi * .03) * (W.spd || 1)) * (1 - F.cd), hp: Math.round((100 + h.vit * 14) * (1 + F.hp)), arm: Gr.arm + F.arm, dmg: (W.dmg + h.str * (W.rng ? W.bs : 2.5)) * (1 + F.dmg + heavy),
    spd: (m ? Gr.horse.v : 86 + h.agi * 3) * (1 + F.run), block: Gr.block };
}
function mkUnit(side, t, fac, x, y, sp) {
  const u = { id: B.units.length, side, t, fac, x, y, vx: 0, vy: 0, face: side ? Math.PI : 0, dir: side ? -1 : 1, hp: t.hp, maxHp: t.hp, arm: t.arm, dmg: t.dmg, block: t.block,
    spd: t.spd * rnd(.94, 1.06), r: t.mounted ? 19 : 12.5, mass: t.mounted ? 3 : 1, cd: rnd(0, 1.2), wind: -1, windT: null, tgt: null, rt: rnd(0, .5), dead: false, flee: false, gone: false,
    morale: 0, mbase: 72 + t.tier * 14, bump: 0, flash: 0, sp, name: null, lx: 0, ly: 0, grp: null, kills: 0, ph: rnd(0, 6), ccd: 0, wav: false, isHero: false, ai: true, blocking: false, swing: 0, stam: 100, w: 1 };
  u.morale = u.mbase; u.grp = B.groups[side][t.grp]; u.grp.units.push(u); B.units.push(u); B.start[side]++; B.men[side]++; return u;
}
function startBattle(cfg) {
  const W = 2600, H = 1700, seed = cfg.seed || rint(1, 1e9), R = mulberry(seed);
  B = { W, H, cfg, ev: [], units: [], arrows: [], fx: [], texts: [], groups: [], t: 0, over: 0, done: false, cam: { x: W / 2, y: H / 2, z: 1 }, log: [], sel: 3, trees: [], start: [0, 0], men: [0, 0], speed: 1, paused: false, hero: null, heroDown: false, flag: null, mt: 0, lt: 0, xp: 0, banner: [null, null], horn: 0 };
  if (!SERVER) { B.ground = paintGround(W, H, cfg.biome, seed); B.gg = B.ground.getContext('2d'); goreInit(); }
  const ts = SERVER ? [null, null, null] : [treeSprite(cfg.biome, seed + 1), treeSprite(cfg.biome, seed + 2), treeSprite(cfg.biome, seed + 3)], bs = SERVER ? [null, null] : [bushSprite(cfg.biome, seed + 4), bushSprite(cfg.biome, seed + 5)];
  const nt = cfg.biome === 'steppe' ? 5 : cfg.biome === 'arid' ? 7 : 15;
  for (let i = 0; i < nt + 16; i++) { const x = 80 + R() * (W - 160), y = 60 + R() * (H - 120); if (Math.abs(y - H / 2) < 330 && x > 330 && x < W - 330 && i < nt) continue; if (i < nt) B.trees.push({ x, y, r: 15, cv: ts[i % 3], w: 100, h: 125, ax: 51, ay: 116, tree: true }); else B.trees.push({ x, y, r: 0, cv: bs[i % 2], w: 60, h: 46, ax: 30, ay: 38 }); }
  for (let s = 0; s < 2; s++) { const sx = s ? W - 640 : 640, d = s ? Math.PI : 0, f = s ? -1 : 1; B.groups.push([0, 1, 2].map(k => ({ side: s, k, units: [], order: 'hold', cx: sx - f * (k === 1 ? 105 : k === 2 ? 20 : 0), cy: H / 2 + (k === 2 ? (R() < .5 ? -1 : 1) * 380 : 0), dir: d, st: 'wait', wx: 0, wy: 0, lt: 0 }))); }
  // Больше BATTLE_CAP юнитов на сторону не рисуем: лишние бойцы сливаются в более крепких. Юнит, который заменяет k бойцов, получает здоровье и урон ×k
  // (сила армии по закону квадратов Ланчестера та же), а потери в конце боя считаются в живых людях (u.w = k).
  B.reserve = [[], []]; B.resDead = [0, 0]; B.cap = [BATTLE_CAP, BATTLE_CAP];
  const fill = (side, list, fac) => { let tot = 0; for (const s of list) tot += s.n;
    const wcap = fac === 'undead' ? UNDEAD_CAP : BATTLE_CAP; B.cap[side] = wcap;
    if ((fac === 'undead' || cfg.quick) && !SERVER && tot > wcap) { // нежить (и все в быстром бою) сверх предела ждёт в запасе и выходит волнами (battleWaves), а не сливается в «толстых» бойцов
      const all = []; for (const s of list) for (let i = 0; i < s.n; i++) all.push(s.type); for (let i = all.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)), x = all[i]; all[i] = all[j]; all[j] = x; }
      list = []; for (const id of all.slice(0, wcap)) addT(list, id, 1); B.reserve[side] = all.slice(wcap); B.men[side] += B.reserve[side].length; tot = wcap; }
    const cap = fac === 'undead' ? UNDEAD_CAP : BATTLE_CAP, sc = tot > cap ? cap / tot : 1; for (const s of list) { const t = TROOPS[s.type], n = sc < 1 ? Math.max(1, Math.round(s.n * sc)) : s.n, k = s.n / n; for (let i = 0; i < n; i++) { const g = B.groups[side][t.grp]; const u = mkUnit(side, t, fac, g.cx + rnd(-30, 30), g.cy + rnd(-30, 30), SERVER ? null : getSprite(s.type, rint(0, 3), fac)); if (k !== 1) { u.w = k; u.hp = u.maxHp = t.hp * k; u.dmg = t.dmg * k; B.men[side] += k - 1; } } } };
  fill(0, cfg.pl, cfg.pfac); fill(1, cfg.en, cfg.efac);
  if (cfg.comps) for (const c of cfg.comps) spawnComp(c);
  if (cfg.siege) siegeSetup();
  for (const u of B.units) if (u.side === 0) u.own = cfg.heroPid;
  for (const g of B.groups[0]) g.own = cfg.heroPid;
  if (cfg.hero) {
    const hd = heroDef(cfg.hero), h = mkUnit(0, hd, 'player', 730, H / 2, SERVER ? null : getHeroSprite(cfg.hero, hd.mounted));
    h.isHero = true; h.ai = !!cfg.heroAI; h.pid = cfg.heroPid; h.inp = null; h.name = cfg.hero.name; h.hp = Math.max(hd.hp * .3, hd.hp * (cfg.hero.hp === undefined ? 1 : cfg.hero.hp)); h.spd = hd.spd; h.mbase = h.morale = 999; h.cd = 0; B.hero = h; B.cam.x = h.x + 200; B.cam.y = h.y;
    const F = perkFx(cfg.hero), mb = (cfg.hero.cha || cfg.hero.lead || 0) * 4 + F.morale; h.fx = F;
    for (const u of B.units) if (u.side === 0 && !u.isHero) { u.mbase += mb; u.morale = u.mbase; if (F.ally) u.dmg *= 1 + F.ally; }
  }
  if (cfg.leader) { const cands = B.units.filter(u => u.side === 1).sort((a, b) => b.t.tier - a.t.tier); const l = cands[0]; if (l) { l.leader = true; l.name = cfg.leader; l.maxHp = l.hp = l.hp * 1.9; l.dmg *= 1.3; l.mbase = l.morale = 200; } }
  for (const u of B.units) if (u.t.fac === 'undead') u.mbase = u.morale = 999; // мёртвые не бегут (и некромант тоже)
  for (const s of B.groups) for (const g of s) layout(g, true);
  for (const u of B.units) { if (u.isHero) continue; const p = slotPos(u); u.x = p[0]; u.y = p[1]; }
  B.count0 = B.men.slice();
  if (!cfg.demo) { blog(cfg.title || 'Битва началась', 2); sfx('horn'); }
  return B;
}
/* спутник (05e_comps.js): юнит-герой под ИИ в группе по оружию — стрелки, конница или пехота; слушается приказов своей группы */
function spawnComp(c) {
  const hd = heroDef(c); hd.id = 'comp:' + c.id; hd.grp = hd.mounted ? 2 : hd.range ? 1 : 0; const g = B.groups[0][hd.grp];
  const u = mkUnit(0, hd, 'player', g.cx + rnd(-30, 30), g.cy + rnd(-30, 30), SERVER ? null : getHeroSprite(c, hd.mounted));
  u.comp = c.id; u.name = c.name; u.hp = Math.max(hd.hp * .3, hd.hp * (c.hp === undefined ? 1 : c.hp)); u.spd = hd.spd; u.mbase = u.morale = 160; u.fx = perkFx(c);
  const d = typeof COMP !== 'undefined' && COMP[c.id]; if (d && d.voice) { u.voice = d.voice; u.sayCd = 0; u.sayStart = rnd(1, 2.2); u.tauntT = rnd(24, 36); } // реплики в бою (03b_gore.js)
  return u;
}
function myPid() { return B.hero ? B.hero.pid : undefined; }
function alive(u) { return !u.dead && !u.gone; }
function fit(u) { return !u.dead && !u.gone && !u.flee; }
function layout(g, init) {
  const us = g.units.filter(u => fit(u) && !u.isHero), n = us.length; if (!n) return;
  const cols = g.k === 0 ? Math.min(n, Math.max(4, Math.ceil(Math.sqrt(n * 3.2)))) : g.k === 1 ? Math.min(n, Math.max(5, Math.ceil(Math.sqrt(n * 6)))) : Math.min(n, Math.max(4, Math.ceil(Math.sqrt(n * 4))));
  const sp = g.k === 0 ? 29 : g.k === 1 ? 38 : 50, rows = Math.ceil(n / cols), px = -Math.sin(g.dir), py = Math.cos(g.dir);
  if (init) us.sort((a, b) => b.t.tier - a.t.tier || (a.t.id < b.t.id ? -1 : 1));
  else us.sort((a, b) => (a.x * px + a.y * py) - (b.x * px + b.y * py));
  const nc = Math.ceil(n / rows);
  if (init) us.forEach((u, i) => { const row = Math.floor(i / nc), col = i % nc, inRow = Math.min(nc, n - row * nc); u.lx = (col - (inRow - 1) / 2) * sp; u.ly = -row * sp * .92; });
  else us.forEach((u, i) => { const col = Math.floor(i / rows), row = i % rows; u.lx = (col - (nc - 1) / 2) * sp; u.ly = -row * sp * .92; });
}
/* волны: когда на поле пала треть предела (у нежити 200 из 600, у живых 100 из 300), из-за края поля выходит следующая треть из запаса */
function battleWaves(n) {
  for (let side = 0; side < 2; side++) { const R = B.reserve && B.reserve[side]; if (!R || !R.length) continue; const cap = B.cap[side], wave = Math.round(cap / 3), room = cap - n[side]; if (room < wave && n[side] > 0) continue;
    const k = Math.min(R.length, room, wave), ex = side ? B.W - 90 : 90, gs = new Set(); let und = false;
    for (const id of R.splice(0, k)) { const t = TROOPS[id], fac = side ? B.cfg.efac : B.cfg.pfac, u = mkUnit(side, t, fac, ex + rnd(-50, 50), B.H / 2 + rnd(-420, 420), getSprite(id, rint(0, 3), fac)); if (t.fac === 'undead') { u.mbase = u.morale = 999; und = true; } if (!side) u.own = B.cfg.heroPid; B.men[side]--; gs.add(u.grp); }
    for (const g of gs) layout(g); n[side] += k;
    if (!B.cfg.demo) { blog((und ? 'Из-за холма выходят ещё ' + k + ' мертвецов' : (side ? 'К врагу подходит подкрепление: ' : 'К нам подходит подкрепление: ') + k) + (R.length ? ' (в запасе ' + R.length + ')' : ' — последняя волна'), side ? 1 : 0); sfx(side ? 'horn2' : 'horn'); }
  }
}
function slotPos(u) { const g = u.grp, c = Math.cos(g.dir), s = Math.sin(g.dir); return [clamp(g.cx - s * u.lx + c * u.ly, 30, B.W - 30), clamp(g.cy + c * u.lx + s * u.ly, 30, B.H - 30)]; }
function centroid(side) { let x = 0, y = 0, n = 0, m = 0; for (const u of B.units) if (u.side === side && fit(u)) { x += u.x; y += u.y; n++; m += u.w || 1; } return n ? { x: x / n, y: y / n, n, m } : null; } // n — юнитов, m — людей (один юнит может быть слитым отрядом)
function nearestFoeDist(x, y, side) { let b = 1e9; for (const u of B.units) if (u.side === side && fit(u)) { const d = Math.hypot(u.x - x, u.y - y); if (d < b) b = d; } return b; }
function blog(txt, kind) { B.log.push({ txt, kind, t: B.t }); if (B.log.length > 30) B.log.shift(); B.logDirty = true; if (SERVER) ev(['l', txt, kind]); }
function ev(a) { if (SERVER && B && B.ev) B.ev.push(a); }
const NOINP = { dx: 0, dy: 0, face: undefined, atk: 0, blk: 0, spr: 0 };
/* второй игрок присоединяется к бою на стороне 0 (общая функция: сервер и клиент-зеркало строят одинаково) */
function joinBattle(c2) {
  const W = B.W, H = B.H, fac = c2.pfac || 'player'; let tot = 0; for (const s of c2.pl) tot += s.n; const sc = tot > JOIN_CAP ? JOIN_CAP / tot : 1, first = B.units.length;
  const NG = [0, 1, 2].map(k => { const g0 = B.groups[0][k], ng = Object.assign({}, g0, { units: [], own: c2.pid, order: 'hold', cy: k === 2 ? H - g0.cy : g0.cy + 330 }); B.groups[0].push(ng); return ng; });
  for (const s of c2.pl) { const t = TROOPS[s.type], n = sc < 1 ? Math.max(1, Math.round(s.n * sc)) : s.n, k = s.n / n; for (let i = 0; i < n; i++) { const g = B.groups[0][t.grp]; const u = mkUnit(0, t, fac, g.cx + rnd(-30, 30), g.cy + rnd(-30, 30), SERVER ? null : getSprite(s.type, rint(0, 3), fac)); if (k !== 1) { u.w = k; u.hp = u.maxHp = t.hp * k; u.dmg = t.dmg * k; B.men[0] += k - 1; } u.own = c2.pid; g.units.pop(); u.grp = NG[t.grp]; NG[t.grp].units.push(u); } }
  const hd = heroDef(c2.hero), h = mkUnit(0, hd, 'player', 700, H / 2 + 70, SERVER ? null : getHeroSprite(c2.hero, hd.mounted));
  h.isHero = true; h.ai = !!c2.heroAI; h.pid = c2.pid; h.own = c2.pid; h.inp = null; h.name = c2.hero.name; h.hp = Math.max(hd.hp * .3, hd.hp * (c2.hero.hp === undefined ? 1 : c2.hero.hp)); h.spd = hd.spd; h.mbase = h.morale = 999; h.cd = 0; B.hero2 = h;
  const F2 = perkFx(c2.hero), mb = (c2.hero.cha || c2.hero.lead || 0) * 4 + F2.morale; h.fx = F2; // харизма и перки второго героя, как у первого в startBattle
  for (let i = first; i < B.units.length; i++) { const u = B.units[i]; if (!u.isHero) { u.mbase += mb; u.morale = u.mbase; if (F2.ally) u.dmg *= 1 + F2.ally; } }
  for (const g of B.groups[0]) layout(g, true);
  for (let i = first; i < B.units.length; i++) { const u = B.units[i]; if (u.isHero) continue; const p = slotPos(u); u.x = p[0]; u.y = p[1]; }
  if (B.count0) B.count0[0] = B.men[0];
  blog(c2.hero.name + ' присоединился к бою', 2);
  return h;
}
function uname(u) { if (!u.name) u.name = unitName(u.t.fac); return u.name; }

/* ---------- приказы ---------- */
function giveOrder(ord, wx, wy, selArg, pid) {
  if (!B || B.cfg.demo) return; const sl = selArg === undefined ? B.sel : selArg; if (pid === undefined) pid = myPid(); // одиночная игра: свои отряды героя
  if (!SERVER && NET.on) { NET.send({ t: 'ord', ord, wx, wy, sel: sl }); if (ord === 'hold') B.flag = { x: wx, y: wy, t: B.t }; sfx(ord === 'charge' ? 'horn' : 'order'); return; }
  const foe = centroid(1), gs = B.groups[0].filter(g => g.own === pid && (sl === 3 || g.k === sl)); let any = false;
  for (const g of gs) {
    if (!g.units.some(fit)) continue; any = true;
    if (ord === 'hold') { g.order = 'hold'; g.cx = wx; g.cy = wy; if (sl === 3) { const f = foe ? Math.atan2(foe.y - wy, foe.x - wx) : 0; g.cx -= Math.cos(f) * (g.k === 1 ? 95 : 0) - Math.sin(f) * (g.k === 2 ? 240 : 0); g.cy -= Math.sin(f) * (g.k === 1 ? 95 : 0) + Math.cos(f) * (g.k === 2 ? 240 : 0); } if (foe) g.dir = Math.atan2(foe.y - g.cy, foe.x - g.cx); layout(g); }
    else if (ord === 'back') { g.order = 'hold'; g.back = true; const d = foe ? Math.atan2(foe.y - g.cy, foe.x - g.cx) : 0; const c = centroidOf(g); g.cx = clamp(c.x - Math.cos(d) * 300, 80, B.W - 80); g.cy = clamp(c.y - Math.sin(d) * 300, 80, B.H - 80); layout(g); }
    else { g.order = ord; if (ord === 'follow') layout(g); }
    if (ord !== 'back') g.back = false;
  }
  if (!any) return;
  if (ord === 'hold') B.flag = { x: wx, y: wy, t: B.t };
  const who = ['Пехота', 'Стрелки', 'Конница', 'Все отряды'][sl];
  const lh = [B.hero, B.hero2].find(h => h && h.pid === pid), pre = B.hero2 && lh ? lh.name + ' · ' : '';
  blog(pre + who + ': ' + { hold: 'держать позицию', follow: 'за мной', charge: 'в атаку!', back: 'отойти назад' }[ord], 2); sfx(ord === 'charge' ? 'horn' : 'order'); B.hudDirty = true;
}
function centroidOf(g) { let x = 0, y = 0, n = 0; for (const u of g.units) if (fit(u) && !u.isHero) { x += u.x; y += u.y; n++; } return n ? { x: x / n, y: y / n } : { x: g.cx, y: g.cy }; }
function sideBrain(s, dt) {
  const gs = B.groups[s], foe = centroid(1 - s), me = centroid(s); if (!foe || !me) return;
  const inf = gs[0], arc = gs[1], cav = gs[2], hasInf = inf.units.some(fit);
  const step = (g, sp) => { const a = Math.atan2(foe.y - g.cy, foe.x - g.cx); g.dir = a; g.cx += Math.cos(a) * sp * dt; g.cy += Math.sin(a) * sp * dt; };
  if (inf.order !== 'charge') { const d = nearestFoeDist(inf.cx, inf.cy, 1 - s); if (d < 215 || B.t > 80) { inf.order = 'charge'; if (hasInf && s === 1 && !B.cfg.demo) { blog('Враг идёт в атаку!', 1); sfx('horn2'); } } else if (B.t > 2.5) step(inf, 40); }
  if (arc.order !== 'charge') { const d = nearestFoeDist(arc.cx, arc.cy, 1 - s); if (d < 105 || (!hasInf && d < 190)) arc.order = 'charge'; else if (d > 325 && B.t > 2.5) step(arc, hasInf ? 40 : 30); else arc.dir = Math.atan2(foe.y - arc.cy, foe.x - arc.cx); }
  if (cav.units.some(fit) && cav.order !== 'charge') {
    if (cav.st === 'wait') { if (B.t > 4) { cav.st = 'flank'; cav.wy = clamp(foe.y + Math.sign(cav.cy - B.H / 2 || 1) * 430, 120, B.H - 120); cav.wx = lerp(me.x, foe.x, .7); } }
    else { const a = Math.atan2(cav.wy - cav.cy, cav.wx - cav.cx), dd = Math.hypot(cav.wy - cav.cy, cav.wx - cav.cx); cav.dir = a; cav.cx += Math.cos(a) * 105 * dt; cav.cy += Math.sin(a) * 105 * dt; if (dd < 60 || nearestFoeDist(cav.cx, cav.cy, 1 - s) < 250) cav.order = 'charge'; }
  }
}
function playerFollow() {
  for (const g of B.groups[0]) if (g.order === 'follow') { const h = B.hero2 && g.own === B.hero2.pid ? B.hero2 : B.hero; if (!h || h.dead) continue; const foe = centroid(1), d = foe ? Math.atan2(foe.y - h.y, foe.x - h.x) : h.face; const off = g.k === 0 ? 50 : g.k === 1 ? 135 : 60, side = g.k === 2 ? 170 : 0; g.dir = d; g.cx = h.x - Math.cos(d) * off - Math.sin(d) * side; g.cy = h.y - Math.sin(d) * off + Math.cos(d) * side; }
}

/* ---------- бойцы ---------- */
function findTarget(u) {
  let best = null, bd = 1e9; const cavm = u.t.mounted && !u.t.range;
  for (const e of B.units) { if (e.side === u.side || e.dead || e.gone) continue; let d = Math.hypot(e.x - u.x, e.y - u.y); if (e.flee) d *= 1.7; if (cavm && e.t.range && !e.t.mounted) d *= .7; if (e === u.tgt) d *= .85; if (d < bd) { bd = d; best = e; } }
  return best;
}
function steer(u, tx, ty, sp, dt) { if (B.wall) { const v = wallVia(u, tx, ty); tx = v[0]; ty = v[1]; } const dx = tx - u.x, dy = ty - u.y, d = Math.hypot(dx, dy); let ax = 0, ay = 0; if (d > 2 && sp > 0) { const s = Math.min(sp, d * 5); ax = dx / d * s; ay = dy / d * s; } const k = Math.min(1, (u.t.mounted ? 2.4 : 10) * dt); u.vx += (ax - u.vx) * k; u.vy += (ay - u.vy) * k; }
function aiUnit(u, dt) {
  const g = u.grp, t = u.t;
  if (u.flee) { steer(u, u.side ? B.W + 90 : -90, u.y, u.spd * 1.12, dt); u.face = Math.atan2(u.vy, u.vx); if (u.x < -25 || u.x > B.W + 25) u.gone = true; return; }
  u.rt -= dt; if (u.rt <= 0 || (u.tgt && (u.tgt.dead || u.tgt.gone))) { u.rt = .35 + Math.random() * .35; u.tgt = findTarget(u); }
  const e = u.tgt; let d = 1e9; if (e) d = Math.hypot(e.x - u.x, e.y - u.y);
  const ord = g.order, sp = slotPos(u), sx = sp[0], sy = sp[1], ds = Math.hypot(sx - u.x, sy - u.y);
  const mreach = u.r + (e ? e.r : 0) + 6 + t.reach; let mode = 'slot';
  if (g.back && ds > 40) mode = 'slot';
  else if (t.range) {
    if (t.mounted) { if (e && (ord === 'charge' || d < t.range * 1.15)) mode = 'skirm'; }
    else if (e && d < mreach + 24) mode = 'melee';
    else if (e && ord === 'charge') mode = 'shoot';
    else if (e && d < t.range && ds < 70) mode = 'shootslot';
  } else if (e) {
    if (ord === 'charge') mode = 'melee';
    else { const er = t.mounted ? 150 : 80, leash = t.mounted ? 260 : 135; if (d < er && Math.hypot(e.x - sx, e.y - sy) < leash) mode = 'melee'; }
  }
  if (mode === 'slot') { steer(u, sx, sy, u.spd, dt); u.face = ds < 8 ? g.dir : Math.atan2(sy - u.y, sx - u.x); }
  else if (mode === 'melee') {
    u.face = Math.atan2(e.y - u.y, e.x - u.x);
    if (t.mounted && u.ccd <= 0 && d < mreach + 5) { const v = Math.hypot(u.vx, u.vy); if (v > 80) chargeHit(u, e, v); }
    if (d > mreach) steer(u, e.x, e.y, u.spd, dt); else { steer(u, u.x, u.y, 0, dt); if (u.cd <= 0 && u.wind < 0) { u.wind = .2; u.windT = e; u.cd = t.cd * rnd(.9, 1.15); u.bump = 1; } }
  } else if (mode === 'shoot' || mode === 'shootslot') {
    u.face = Math.atan2(e.y - u.y, e.x - u.x);
    if (mode === 'shoot') { if (d > t.range * .9) steer(u, e.x, e.y, u.spd, dt); else steer(u, u.x, u.y, 0, dt); } else steer(u, sx, sy, u.spd, dt);
    if (d < t.range && u.cd <= 0 && Math.hypot(u.vx, u.vy) < 26) { shoot(u, e, d); u.cd = t.cd * rnd(.85, 1.2); }
  } else if (mode === 'skirm') {
    u.face = Math.atan2(e.y - u.y, e.x - u.x); const ax = (u.x - e.x) / d, ay = (u.y - e.y) / d, sg = u.id % 2 ? 1 : -1; let tx, ty;
    if (d < t.range * .55) { tx = u.x + ax * 130 - ay * 60 * sg; ty = u.y + ay * 130 + ax * 60 * sg; } else if (d > t.range * .9) { tx = e.x; ty = e.y; } else { tx = u.x - ay * 140 * sg; ty = u.y + ax * 140 * sg; }
    if (tx < 60 || tx > B.W - 60 || ty < 60 || ty > B.H - 60) { tx = B.W / 2; ty = B.H / 2; }
    steer(u, tx, ty, u.spd * .8, dt); if (d < t.range && u.cd <= 0) { shoot(u, e, d); u.cd = t.cd * rnd(.85, 1.2); }
  }
  if (u.wind >= 0) { u.wind -= dt; if (u.wind < 0) { const w = u.windT; if (w && alive(w) && Math.hypot(w.x - u.x, w.y - u.y) < u.r + w.r + 16 + t.reach) strike(u, w); } }
}
function blocked(t, fromA, kind) {
  let ch = t.block || 0, ar = kind === 'arrow', sb = t.t.shb || 0; // щит заметно лучше держит стрелы и дротики; без щита шанс ниже, чем против клинка
  if (t.isHero && !t.ai) ch = t.blocking ? Math.min(.97, ch + .13 + (ar ? sb * 1.5 : 0)) : ch * .25 + (ar ? sb * .5 : 0); else if (ar) ch = sb ? Math.min(.88, ch * 1.25 + sb) : ch * .85;
  if (ch <= 0 || Math.abs(angDiff(fromA, t.face)) > 1.25) return false; return Math.random() < ch;
}
/* нежить: скелеты плохо держат дробящий удар, а стрелы пролетают сквозь рёбра; мертвецам дробящее тоже чуть больнее */
function undeadMul(t, dt, arrow) { const k = t.t.look && t.t.look.undead; if (!k) return 1; if (arrow) return k === 'skel' ? .6 : 1; return dt === 'blunt' ? (k === 'skel' ? 1.4 : 1.15) : 1; }
const lookDt = t => t.wpn ? t.wpn.dt : t.look && (t.look.weapon === 'club' || t.look.weapon === 'mace') ? 'blunt' : 'cut';
function strike(a, t) {
  let dmg = (a.t.range ? (a.t.mdmg || a.dmg * .6) : a.dmg) * rnd(.8, 1.2); const fromA = Math.atan2(a.y - t.y, a.x - t.x), rear = Math.abs(angDiff(fromA, t.face)) > 2.1;
  if (!rear && blocked(t, fromA, 'melee')) { fxSpark(t.x + Math.cos(fromA) * 10, t.y + Math.sin(fromA) * 10 - 14); sfx('clang', t); if (t === B.hero) ftext(t.x, t.y - 44, 'Блок', '#d8d2c4'); return; }
  if (rear) dmg *= 1.4; if (a.t.anticav && t.t.mounted) dmg *= 1.7; dmg *= undeadMul(t, lookDt(a.t), false); B.hk = 'melee'; B.hdt = lookDt(a.t); if (a.t.wpn) { dmg *= dtMul(a.t.wpn.dt, t.arm); hurt(t, dmg, a, dtPierce(a.t.wpn.dt, t.arm, a.t.wpn.pb)); } else hurt(t, dmg, a, 0); sfx('hit', t);
}
function chargeHit(a, e, v) {
  a.ccd = 1.7; let dmg = a.dmg * (.6 + v / 150); const fromA = Math.atan2(a.y - e.y, a.x - e.x), front = Math.abs(angDiff(fromA, e.face)) < 1.1;
  if (e.t.anticav && front && !e.flee) { dmg *= .45; hurt(a, 16 * rnd(.8, 1.3), e, 0); }
  else if (front && blocked(e, fromA, 'melee')) dmg *= .4;
  const k = 15 / (e.mass || 1); e.x -= Math.cos(fromA) * k; e.y -= Math.sin(fromA) * k; a.vx *= .4; a.vy *= .4; a.cd = Math.max(a.cd, .45);
  B.hk = 'charge'; B.hdt = 'blunt'; if (alive(e)) hurt(e, dmg, a, 0); sfx('thud', e); fxDust(e.x, e.y);
}
function shoot(u, e, d) {
  const dur = d / (u.t.wpn && u.t.wpn.wt === 'throw' ? THROW_V : SHOT_V) + .16, px = e.x + e.vx * dur * .8, py = e.y + e.vy * dur * .8, s = 5 + d * u.t.acc;
  B.arrows.push({ x0: u.x, y0: u.y - 16, x1: px + (Math.random() + Math.random() - 1) * s, y1: py + (Math.random() + Math.random() - 1) * s, t: 0, dur, side: u.side, dmg: u.dmg, src: u, pierce: u.t.pierce || (u.t.wpn && u.t.wpn.pb) || 0, dt: u.t.wpn && u.t.wpn.dt, jv: !!(u.t.wpn && u.t.wpn.wt === 'throw'), xb: (u.t.look && u.t.look.weapon === 'xbow') || !!(u.t.wpn && u.t.wpn.wt === 'xbow') });
  u.bump = .5; sfx('bow', u); const ar = B.arrows[B.arrows.length - 1]; ev(['a', Math.round(ar.x0), Math.round(ar.y0), Math.round(ar.x1), Math.round(ar.y1), +dur.toFixed(2), u.side, ar.xb ? 1 : 0, ar.jv ? 1 : 0]);
}
function hurt(t, dmg, src, pierce) {
  if (t.dead) return; const arm = t.arm * (1 - (pierce || 0)), d = Math.max(1, Math.round(dmg * (1 - arm / (arm + 55))));
  t.hp -= d; t.lh = d; t.flash = .13; t.morale -= d * .12; if (!SERVER) { const bc = goreCol(t); if (bc) fxBlood(t.x, t.y - 16, 4, bc); else fxDust(t.x, t.y - 14); if (t.hp > 0) goreHit(t, d, src); if (t.voice && t.hp > 0 && d > t.maxHp * .1 && Math.random() < .35) voiceSay(t, 'hurt'); } ev(['h', t.id, d]);
  if (t === B.hero || (src && src === B.hero)) ftext(t.x + rnd(-6, 6), t.y - 46, String(d), t === B.hero ? '#e2503c' : '#f1e3b0');
  if (t === B.hero) B.shake = .18;
  if (t.hp <= 0 && t.isHero && t.fx && t.fx.lastStand && !t.lsUsed) { t.lsUsed = true; t.hp = Math.max(1, t.maxHp * t.fx.lastStand); if (!SERVER) ftext(t.x, t.y - 62, 'Не сдаюсь!', '#f1d27a'); blog(t.name + ' поднялся на ноги', 0); }
  if (t.hp <= 0) kill(t, src);
}
function kill(t, src) {
  t.dead = true; t.hp = 0; if (src) { src.kills++; src.morale = Math.min(src.mbase, src.morale + 8); if (src.isHero && src.fx && src.fx.killHeal) src.hp = Math.min(src.maxHp, src.hp + src.maxHp * src.fx.killHeal); }
  if (!SERVER) { if (src && src.voice && !src.dead) voiceSay(src, t.t.fac === 'undead' && Math.random() < .5 ? 'killUndead' : 'kill'); if (t.voice) { voiceSay(t, 'down', true); banterDown(t); } }
  if (!SERVER && !goreKill(t, src)) paintCorpse(t); ev(['k', t.id]);
  if (!SERVER && goreCol(t)) fxBlood(t.x, t.y - 14, 12, goreCol(t)); sfx('death', t);
  for (const u of B.units) { if (u.dead || u.gone) continue; const d = Math.hypot(u.x - t.x, u.y - t.y); if (d > 170) continue; if (u.side === t.side) u.morale -= t.leader || t.isHero ? 9 : 1.6 + t.t.tier * .5; else u.morale = Math.min(u.mbase, u.morale + 3); }
  if (t.isHero && t.side === 0 && !t.ai) { t.down = true; if (t === B.hero) B.heroDown = true; blog(t.name + ' ранен и вынесен из боя', 1); for (const g2 of B.groups[0]) if (g2.own === t.pid) g2.order = 'charge'; for (const u of B.units) if (u.side === 0 && u.own === t.pid) u.morale -= 7; B.hudDirty = true; }
  else if (t.comp) { blog(t.name + ' ранен и вынесен из боя', 1); for (const u of B.units) if (u.side === 0 && Math.hypot(u.x - t.x, u.y - t.y) < 170) u.morale -= 4; B.hudDirty = true; }
  else if (t.leader && t.t.fac === 'undead') { blog(t.name + ' пал — мертвецы рассыпаются в прах!', t.side ? 0 : 1); for (const u of B.units) if (u.side === t.side && alive(u) && u.t.fac === 'undead' && Math.random() < .35) { u.leader = false; kill(u, null); } const R = B.reserve && B.reserve[t.side]; if (R && R.length) { const k = Math.round(R.length * .35); R.splice(0, k); B.resDead[t.side] += k; } }
  else if (t.leader) { blog(t.name + ' пал!', t.side ? 0 : 1); for (const u of B.units) if (u.side === t.side) u.morale -= 10; }
  else if (src && src === B.hero) blog(B.hero.name + ' сразил: ' + t.t.name.toLowerCase(), 0);
  if (t.side === 1) B.xp += (t.t.tier * 10 + (t.t.mounted ? 5 : 0)) * (t.w || 1) * (t.t.pw || 1);
}
function paintCorpse(t) {
  const g = B.gg, sp = corpseOf(t.sp), k = US * 1.0, rot = (Math.random() < .5 ? -1 : 1) * rnd(1.2, 1.9);
  g.save(); g.translate(t.x, t.y); g.fillStyle = 'rgba(96,14,10,.5)'; g.beginPath(); g.ellipse(rnd(-4, 4), rnd(-2, 4), rnd(15, 24), rnd(8, 12), rnd(0, 3), 0, TAU); g.fill();
  g.restore(); if (!(t.isHero && t.side === 0) && !t.comp) fallAdd(sp, t.x, t.y, t.sp.ax, t.sp.ay, rot, k, .88);
}
function heroControl(h, dt) {
  const I = h.inp || NOINP; let mx = I.dx || 0, my = I.dy || 0;
  const ml = Math.hypot(mx, my); if (ml > 1) { mx /= ml; my /= ml; }
  if (typeof I.face === 'number') h.face = I.face;
  h.blocking = !!I.blk && h.wind < 0;
  if (I.sw && !h.swHeld && h.wind < 0) swapWield(h); h.swHeld = !!I.sw;
  let sp = h.spd; const sprint = I.spr && ml > .2 && h.stam > 2 && !h.blocking;
  if (sprint) { sp *= h.t.mounted ? 1.2 : 1.4; h.stam = Math.max(0, h.stam - 26 * dt); } else h.stam = Math.min(100, h.stam + (ml > .2 ? 9 : 18) * dt);
  if (h.blocking) sp *= .55; if (h.swing > 0 && !h.t.mounted) sp *= .7;
  const k = Math.min(1, (h.t.mounted ? (ml > .1 ? 1.7 : .9) : 12) * dt); h.vx += (mx * sp - h.vx) * k; h.vy += (my * sp - h.vy) * k;
  if (I.atk && h.cd <= 0 && h.wind < 0 && !h.blocking) { const rw = h.t.wpn && h.t.wpn.rng; h.wind = rw ? .2 : .13; h.cd = h.t.cd; h.swing = rw ? 0 : .26; h.bump = 1; h.swingA = h.face; if (!rw) sfx('swing'); }
  if (h.wind >= 0) { h.wind -= dt; if (h.wind < 0) heroStrike(h); }
  h.swing -= dt;
  if (h.t.mounted && h.ccd <= 0) { const v = Math.hypot(h.vx, h.vy); if (v > 95) { const va = Math.atan2(h.vy, h.vx); for (const e of B.units) { if (e.side !== 1 || !alive(e)) continue; const d = Math.hypot(e.x - h.x, e.y - h.y); if (d < h.r + e.r + 5 && Math.abs(angDiff(Math.atan2(e.y - h.y, e.x - h.x), va)) < .9) { chargeHit(h, e, v); h.ccd = .9; break; } } } }
}
function heroStrike(h) {
  const W = h.t.wpn; if (W && W.rng) return heroShoot(h);
  const R = 30 + h.t.reach + (h.t.mounted ? 8 : 0), arc = W ? W.arc : 1, maxHits = W ? W.cleave : 3, fall = W ? W.fall : .7, kb = W && W.kb ? W.kb : 1; let hits = 0;
  for (const e of B.units) {
    if (e.side === h.side || !alive(e)) continue; const d = Math.hypot(e.x - h.x, e.y - h.y); if (d > R + e.r) continue; const a = Math.atan2(e.y - h.y, e.x - h.x); if (Math.abs(angDiff(a, h.swingA)) > arc) continue;
    const fromA = a + Math.PI, rear = Math.abs(angDiff(fromA, e.face)) > 2.1;
    if (!rear && blocked(e, fromA, 'melee') && Math.random() < .75 - (W && W.brk || 0)) { fxSpark(e.x - Math.cos(a) * 8, e.y - Math.sin(a) * 8 - 14); sfx('clang', e); ftext(e.x, e.y - 44, 'Блок', '#b9b2a5'); }
    else {
      e.x += Math.cos(a) * 5 * kb; e.y += Math.sin(a) * 5 * kb; let dmg = h.dmg * rnd(.85, 1.2) * (rear ? 1.4 : 1) * (hits ? fall : 1);
      if (W) { if (W.anticav && e.t.mounted) dmg *= 1.7; dmg *= dtMul(W.dt, e.arm); } dmg *= undeadMul(e, W ? W.dt : 'blunt', false); B.hk = 'melee'; B.hdt = W ? W.dt : 'blunt';
      hurt(e, dmg, h, W ? dtPierce(W.dt, e.arm, (W.pb || 0) + (h.fx ? h.fx.mpierce : 0)) : .1 + (h.fx ? h.fx.mpierce : 0)); sfx('hit', e);
    }
    if (++hits >= maxHits) break;
  }
}
function heroShoot(h) { // выстрел или бросок в сторону курсора: цель выбирается в узком конусе (формат ввода h.inp не меняется)
  const W = h.t.wpn, R = h.t.range || W.range, a0 = h.swingA; let best = null, bs = 1e9;
  for (const e of B.units) { if (e.side === h.side || !alive(e)) continue; const dx = e.x - h.x, dy = e.y - h.y, d = Math.hypot(dx, dy); if (d > R || d < 14) continue; const da = Math.abs(angDiff(Math.atan2(dy, dx), a0)); if (da > .2) continue; const sc = da * 420 + d * .12; if (sc < bs) { bs = sc; best = e; } }
  const d = best ? Math.hypot(best.x - h.x, best.y - h.y) : R * .7, dur = d / (W.wt === 'throw' ? THROW_V : SHOT_V) + .16, s = 5 + d * (h.t.acc || W.acc * ACC_K || .05 * ACC_K);
  const px = best ? best.x + best.vx * dur * .8 : h.x + Math.cos(a0) * d, py = best ? best.y + best.vy * dur * .8 : h.y + Math.sin(a0) * d;
  B.arrows.push({ x0: h.x, y0: h.y - 16, x1: px + (Math.random() + Math.random() - 1) * s, y1: py + (Math.random() + Math.random() - 1) * s, t: 0, dur, side: h.side, dmg: h.dmg, src: h, pierce: W.pb || 0, dt: W.dt, xb: W.wt === 'xbow', jv: W.wt === 'throw' });
  h.bump = .5; sfx('bow', h); const ar = B.arrows[B.arrows.length - 1]; ev(['a', Math.round(ar.x0), Math.round(ar.y0), Math.round(ar.x1), Math.round(ar.y1), +dur.toFixed(2), h.side, ar.xb ? 1 : 0, ar.jv ? 1 : 0]);
}
function swapWield(h) { // ближнее ↔ дальнее оружие (клавиша X)
  const cfg = B.cfg.hero, eq = heroEq(cfg), to = cfg.sel === 'ranged' ? 'melee' : 'ranged'; if (to === 'ranged' && !eq.ranged) { ftext(h.x, h.y - 52, 'Нет дальнего оружия', '#d8d2c4'); return; }
  cfg.sel = to; const hd = heroDef(cfg); h.t = hd; h.dmg = hd.dmg; h.arm = hd.arm; h.block = hd.block; h.cd = Math.max(h.cd, .35); h.swing = 0; if (!SERVER) h.sp = getHeroSprite(cfg, hd.mounted);
  ftext(h.x, h.y - 52, hd.wpn.name, '#f1e3b0'); sfx('click'); ev(['w', h.id, to === 'ranged' ? 1 : 0]); B.hudDirty = true;
}
/* ---------- эффекты ---------- */
function fxBlood(x, y, n, col) { if (SERVER || B.fx.length > 500) return; for (let i = 0; i < n; i++) B.fx.push({ k: 0, b: 1, x, y, vx: rnd(-60, 60), vy: rnd(-90, 20), l: rnd(.25, .55), c: col || '#8f1a12', s: rnd(1.4, 2.8) }); }
function fxSpark(x, y) { if (SERVER) { ev(['b', Math.round(x), Math.round(y)]); return; } for (let i = 0; i < 6; i++) B.fx.push({ k: 0, x, y, vx: rnd(-90, 90), vy: rnd(-90, 60), l: rnd(.12, .28), c: '#ffe9a8', s: 1.5 }); }
function fxDust(x, y) { if (SERVER) { ev(['d', Math.round(x), Math.round(y)]); return; } for (let i = 0; i < 6; i++) B.fx.push({ k: 1, x: x + rnd(-10, 10), y: y + rnd(-4, 6), vx: rnd(-25, 25), vy: rnd(-25, -5), l: rnd(.4, .8), c: '#b8a880', s: rnd(4, 8) }); }
function ftext(x, y, s, c) { if (SERVER) { ev(['t', Math.round(x), Math.round(y), s, c]); return; } if (B.texts.length < 40) B.texts.push({ x, y, s, c, l: .9 }); }

/* ---------- шаг симуляции ---------- */
function battleUpdate(rdt) {
  if (!B || B.paused || B.done) return;
  const dt = Math.min(rdt, 1 / 30) * B.speed; B.t += dt;
  const demo = B.cfg.demo;
  if (B.wall) siegeBrain(dt); else sideBrain(1, dt); if (demo || (B.heroDown && false)) sideBrain(0, dt); else playerFollow();
  B.lt -= dt; if (B.lt <= 0) { B.lt = 2.4; for (const s of B.groups) for (const g of s) if (g.order !== 'charge') layout(g); }
  for (const u of B.units) {
    if (u.dead || u.gone) continue; u.cd -= dt; u.ccd -= dt; u.flash -= dt; if (u.bump > 0) u.bump = Math.max(0, u.bump - dt * 4.2);
    if (u.isHero && !u.ai) heroControl(u, dt); else aiUnit(u, dt);
    u.x += u.vx * dt; u.y += u.vy * dt;
    const c = Math.cos(u.face); if (c > .25) u.dir = 1; else if (c < -.25) u.dir = -1;
  }
  // расталкивание
  const us = B.units;
  for (let i = 0; i < us.length; i++) { const a = us[i]; if (a.dead || a.gone) continue;
    for (let j = i + 1; j < us.length; j++) { const b = us[j]; if (b.dead || b.gone) continue; const dx = b.x - a.x, rr = a.r + b.r; if (dx > rr || dx < -rr) continue; const dy = b.y - a.y; if (dy > rr || dy < -rr) continue; const d2 = dx * dx + dy * dy; if (d2 >= rr * rr) continue; const d = Math.sqrt(d2) || .01, ov = (rr - d) * (a.side === b.side ? .5 : .9), tm = a.mass + b.mass, nx = dx / d, ny = dy / d; a.x -= nx * ov * b.mass / tm; a.y -= ny * ov * b.mass / tm; b.x += nx * ov * a.mass / tm; b.y += ny * ov * a.mass / tm; }
    if (B.wall) wallPush(a);
    for (const t of B.trees) { if (!t.r) continue; const dx = a.x - t.x, dy = a.y - t.y, rr = a.r + t.r, d2 = dx * dx + dy * dy; if (d2 < rr * rr) { const d = Math.sqrt(d2) || .01; a.x += dx / d * (rr - d); a.y += dy / d * (rr - d); } }
    if (!a.flee) a.x = clamp(a.x, 20, B.W - 20); a.y = clamp(a.y, 26, B.H - 16);
  }
  // стрелы
  for (let i = B.arrows.length - 1; i >= 0; i--) {
    const a = B.arrows[i]; a.t += dt; if (a.t < a.dur) continue; B.arrows.splice(i, 1);
    let hit = null, bd = 1e9; for (const u of B.units) { if (u.side === a.side || u.dead || u.gone) continue; const d = Math.hypot(u.x - a.x1, u.y - 10 - a.y1); if (d < u.r + 3 && d < bd) { bd = d; hit = u; } }
    if (hit) { const fromA = Math.atan2(a.y0 - hit.y, a.x0 - hit.x); B.hk = 'arrow'; B.hdt = 'pierce'; if (blocked(hit, fromA, 'arrow')) { sfx('thunk', hit); fxSpark(hit.x + Math.cos(fromA) * 9, hit.y - 14); if (hit === B.hero) ftext(hit.x, hit.y - 44, 'Блок', '#d8d2c4'); } else { hurt(hit, a.dmg * rnd(.85, 1.15) * dtMul(a.dt, hit.arm) * wallCover(hit, a) * undeadMul(hit, a.dt, true), a.src, a.dt ? dtPierce(a.dt, hit.arm, a.pierce) : a.pierce); sfx('arrowhit', hit); } }
    else if (!SERVER) { const g = B.gg, an = Math.atan2(a.y1 - a.y0, a.x1 - a.x0); g.save(); g.translate(a.x1, a.y1); g.rotate(an - .5); g.strokeStyle = '#3a2a18'; g.lineWidth = 1.4; g.beginPath(); g.moveTo(a.jv ? -18 : -9, 0); g.lineTo(0, 0); g.stroke(); g.strokeStyle = '#e6e0cf'; g.lineWidth = 2; g.beginPath(); g.moveTo(-10, 0); g.lineTo(-7, 0); g.stroke(); g.restore(); }
  }
  for (let i = B.fx.length - 1; i >= 0; i--) { const p = B.fx[i]; p.l -= dt; if (p.l <= 0) { if (p.b && GORE.on) goreSplat(p); B.fx.splice(i, 1); continue; } p.x += p.vx * dt; p.y += p.vy * dt; if (!p.k) p.vy += 260 * dt; }
  for (let i = B.texts.length - 1; i >= 0; i--) { const p = B.texts[i]; p.l -= dt; p.y -= 26 * dt; if (p.l <= 0) B.texts.splice(i, 1); }
  // мораль
  B.mt -= dt; if (B.mt <= 0) {
    B.mt = 1; const n = [0, 0]; for (const u of B.units) if (fit(u)) n[u.side]++; B.n = n;
    for (const u of B.units) { if (!fit(u) || (u.isHero && !u.ai) || u.comp || u.t.fac === 'undead') continue; /* спутники, как и герой, с поля не бегут */ const my = n[u.side], th = n[1 - u.side] || .5, r = my / th; if (r < .5) u.morale -= 2.5; if (r < .3) u.morale -= 3.5; u.morale = Math.min(u.mbase, u.morale + (r > 1.5 ? 4 : r > .8 ? 2.5 : 1));
      if (!u.wav && u.morale < 22) { u.wav = true; if (Math.random() < .5 && !demo) blog(uname(u) + ' дрогнул', u.side ? 0 : 1); }
      if (u.morale <= 0 || (my <= B.start[u.side] * .2 && my < th * .5 && !u.leader && B.start[u.side] > 4)) { u.flee = true; if (Math.random() < .5 && !demo) blog(uname(u) + ' бежит с поля боя', u.side ? 0 : 1); } }
    B.hudDirty = true;
    if (!SERVER && B.reserve) battleWaves(n);
    const f0 = B.units.some(u => u.side === 0 && fit(u)), f1 = B.units.some(u => u.side === 1 && fit(u));
    if ((!f0 || !f1) && !B.over) { B.over = B.t; B.win = f0 && !f1; if (!demo) { blog(B.win ? 'Победа! Враг разбит.' : 'Отряд разбит…', B.win ? 0 : 1); sfx(B.win ? 'horn' : 'horn2'); } }
  }
  if (B.over && B.t - B.over > 2.2 && !B.done) { B.done = true; finishBattle(); }
  if (!SERVER) { goreUpdate(dt); voiceUpdate(dt); battleCamera(rdt); }
}
function battleCamera(rdt) {
  const demo = B.cfg.demo;
  const cam = B.cam; let fx = cam.x, fy = cam.y;
  if (B.hero && !B.heroDown) { const w = IN.touch ? { x: B.hero.x, y: B.hero.y } : s2w(IN.mx, IN.my); fx = B.hero.x + clamp((w.x - B.hero.x) * .22, -140, 140); fy = B.hero.y + clamp((w.y - B.hero.y) * .22, -100, 100); }
  else { const a = centroid(0), b = centroid(1), c = a && b ? { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 } : a || b; if (c) { fx = c.x + (demo ? Math.sin(B.t * .13) * 120 : 0); fy = c.y + (demo ? Math.cos(B.t * .1) * 60 : 0); } }
  const k = Math.min(1, rdt * (demo ? 1.2 : 5)); cam.x += (fx - cam.x) * k; cam.y += (fy - cam.y) * k;
  const hw = VIEW.w / 2 / cam.z, hh = VIEW.h / 2 / cam.z; cam.x = hw * 2 >= B.W ? B.W / 2 : clamp(cam.x, hw, B.W - hw); cam.y = hh * 2 >= B.H ? B.H / 2 : clamp(cam.y, hh, B.H - hh);
  if (B.shake > 0) B.shake -= rdt;
}
function finishBattle() {
  const mk = (pid, hero) => {
    const surv = (hero && hero.fx ? hero.fx.surv : 0) + (pid === B.cfg.heroPid ? B.cfg.csurv || 0 : 0); // csurv — лекарь среди спутников
    const res = { win: B.win, dead: {}, wounded: {}, left: {}, comps: {}, enemyDead: 0, enemyTotal: Math.round(B.men[1]), xp: Math.round(B.xp), heroDown: hero ? !!hero.dead : B.heroDown, heroHp: hero ? clamp(hero.hp / hero.maxHp, 0, 1) : 1, heroKills: hero ? hero.kills : 0, time: B.t, enemyLeft: {} };
    for (const u of B.units) {
      if (u.isHero && u.side === 0) continue;
      if (u.comp) { if (u.own === pid) res.comps[u.comp] = { hp: u.dead ? 0 : clamp(u.hp / u.maxHp, 0, 1), down: !!u.dead, kills: u.kills }; continue; }
      const id = u.t.id, w = u.w || 1; // w: сколько бойцов заменяет юнит (см. fill в startBattle)
      if (u.side === 0) { if (u.own !== pid) continue; if (u.dead && !u.gone) { const k = Math.random() < .38 + surv ? 'wounded' : 'dead'; res[k][id] = (res[k][id] || 0) + w; } else res.left[id] = (res.left[id] || 0) + w; }
      else { if (u.dead && !u.gone) res.enemyDead += w; else res.enemyLeft[id] = (res.enemyLeft[id] || 0) + w; }
    }
    if (B.reserve) { for (const id of B.reserve[1]) res.enemyLeft[id] = (res.enemyLeft[id] || 0) + 1; res.enemyDead += B.resDead[1]; for (const id of B.reserve[0]) res.left[id] = (res.left[id] || 0) + 1; } // нежить, не успевшая выйти, остаётся в армии; рассыпанная со смертью некроманта — в убитых
    for (const m of [res.dead, res.wounded, res.left, res.enemyLeft]) for (const id in m) { m[id] = Math.round(m[id]); if (!m[id]) delete m[id]; }
    res.enemyDead = Math.round(res.enemyDead);
    return res;
  };
  const cb = B.cfg.onEnd, cg = B.cfg.onEndGuest, h2 = B.hero2;
  if (cb) cb(mk(B.cfg.heroPid, B.hero));
  if (cg && h2) cg(mk(h2.pid, h2));
}
function s2w(sx, sy) { const c = B.cam; return { x: c.x + (sx - VIEW.w / 2) / c.z, y: c.y + (sy - VIEW.h / 2) / c.z }; }

/* ---------- отрисовка ---------- */
/* Боец рисуется двумя слоями: тело и рука с оружием. Рука поворачивается вокруг плеча при ударе
   (замах назад → удар вперёд → возврат), копья колют, луки отдаёт назад. Тело слегка дышит и наклоняется на ходу. */
function swingPose(wk, bump) {
  const p = 1 - bump; let a = 0, dx = 0, dy = 0;
  if (wk === 3) { const q = clamp(1 - bump * 2, 0, 1); dx = -5 * (1 - q) * (1 - q); a = -.12 * (1 - q); }
  else if (wk === 2) { if (p < .25) { const q = p / .25; a = .1 * q; dx = -7 * q; dy = 3 * q; } else if (p < .5) { const q = (p - .25) / .25, e = 1 - (1 - q) * (1 - q); a = lerp(.1, .5, e); dx = lerp(-7, 16, e); dy = lerp(3, 2, e); } else { const q = (p - .5) / .5; a = lerp(.5, 0, q); dx = lerp(16, 0, q); dy = lerp(2, 0, q); } }
  else { if (p < .28) { const q = p / .28; a = -.55 * Math.sin(q * Math.PI / 2); } else if (p < .55) { const q = (p - .28) / .27, e = 1 - (1 - q) * (1 - q) * (1 - q); a = lerp(-.55, 1.25, e); } else { const q = (p - .55) / .45; a = lerp(1.25, 0, q * q * (3 - 2 * q)); } }
  return [a, dx, dy];
}
function drawUnitSprite(g, u, sp, mv) {
  const br = 1 + Math.sin(B.t * 2.1 + u.ph) * .012, lean = mv > 12 ? clamp(mv / 90, 0, 1) * .055 : 0;
  if (sp.mnt && mv > 12) { const ph = B.t * (7 + clamp(mv / 60, 0, 3)) + u.ph; g.translate(0, -Math.abs(Math.sin(ph)) * 2.6); g.rotate(Math.sin(ph) * .018 * u.dir); }
  g.scale(u.dir * US, US * br); if (lean) g.rotate(lean);
  if (u.flash > 0 || !sp.body) { g.drawImage(u.flash > 0 ? sp.flash : sp.cv, -sp.ax, -sp.ay); return; }
  g.drawImage(sp.body, -sp.ax, -sp.ay);
  if (u.bump > 0 && sp.wk) { const q = swingPose(sp.wk, u.bump), px = sp.piv[0] - sp.ax, py = sp.piv[1] - sp.ay; g.translate(px + q[1], py + q[2]); g.rotate(q[0]); g.drawImage(sp.wpn, -sp.piv[0], -sp.piv[1]); if (sp.wk === 1 && q[0] > .1) { g.globalAlpha *= .35; g.rotate(-.28); g.drawImage(sp.wpn, -sp.piv[0], -sp.piv[1]); } }
  else g.drawImage(sp.wpn, -sp.ax, -sp.ay);
}
/* павший падает на землю за треть секунды и только потом впечатывается в поле */
function fallAdd(cv, x, y, ax, ay, rot, k, alpha) { if (!B.falls) B.falls = []; B.falls.push({ cv, x, y, ax, ay, rot, k, alpha, t0: B.t }); }
function fallDraw(g) {
  if (!B.falls) return;
  for (let i = B.falls.length - 1; i >= 0; i--) { const f = B.falls[i], p = clamp((B.t - f.t0) / .34, 0, 1), e = p * p, done = p >= 1, c = done ? B.gg : g;
    c.save(); c.translate(f.x, f.y - Math.sin(p * Math.PI) * 5); c.rotate(f.rot * e); c.globalAlpha = done ? f.alpha : 1; c.scale(f.k, f.k); c.drawImage(f.cv, -f.ax, -f.ay + 60 * e); c.restore();
    if (done) B.falls.splice(i, 1); }
}
const drawList = [];
function battleDraw(g) {
  const cam = B.cam, z = cam.z, d = VIEW.dpr, demo = B.cfg.demo;
  g.setTransform(1, 0, 0, 1, 0, 0); g.fillStyle = '#15120c'; g.fillRect(0, 0, VIEW.w * d, VIEW.h * d);
  const shx = B.shake > 0 ? rnd(-3, 3) : 0, shy = B.shake > 0 ? rnd(-3, 3) : 0;
  g.setTransform(d * z, 0, 0, d * z, d * (VIEW.w / 2 - cam.x * z + shx), d * (VIEW.h / 2 - cam.y * z + shy));
  g.drawImage(B.ground, 0, 0); goreDrawUnder(g);
  const x0 = cam.x - VIEW.w / 2 / z - 80, x1 = cam.x + VIEW.w / 2 / z + 80, y0 = cam.y - VIEW.h / 2 / z - 40, y1 = cam.y + VIEW.h / 2 / z + 140;
  if (B.flag && B.t - B.flag.t < 4) { const f = B.flag, a = clamp(4 - (B.t - f.t), 0, 1); g.globalAlpha = a; g.strokeStyle = '#f1d27a'; g.lineWidth = 2; ell(g, f.x, f.y, 26, 10); g.stroke(); drawBanner(g, f.x, f.y, 'player', 15); g.globalAlpha = 1; }
  drawList.length = 0;
  for (const u of B.units) if (!u.dead && !u.gone && u.x > x0 && u.x < x1 && u.y > y0 && u.y < y1) drawList.push(u);
  for (const t of B.trees) if (t.x > x0 - 60 && t.x < x1 + 60 && t.y > y0 && t.y < y1 + 60) drawList.push(t);
  drawList.sort((a, b) => a.y - b.y);
  const hsel = !demo && B.sel;
  for (const u of drawList) {
    if (u.cv) { g.drawImage(u.cv, u.x - u.ax, u.y - u.ay, u.w, u.h); continue; }
    const sp = u.sp, mv = Math.hypot(u.vx, u.vy); let ox = 0, oy = mv > 12 ? Math.sin(B.t * (u.t.mounted ? 15 : 11) + u.ph) * (u.t.mounted ? 2 : 1.3) : 0;
    if (u.bump > 0) { const b = Math.sin((1 - u.bump) * Math.PI) * 7; ox = Math.cos(u.face) * b; oy += Math.sin(u.face) * b; }
    contactShadow(g, u.x + 4, u.y + 3, u.r * 1.65, u.r * .72);
    if (!demo) {
      if (u.isHero && !u.ai) { g.strokeStyle = u === B.hero ? '#ffd86a' : '#7ee07a'; g.lineWidth = 2.2; ell(g, u.x, u.y, u.r + 5, (u.r + 5) * .42); g.stroke(); if (u.blocking) { g.strokeStyle = 'rgba(210,230,255,.85)'; g.lineWidth = 3.5; g.beginPath(); g.arc(u.x, u.y - 12, 24, u.face - 1.1, u.face + 1.1); g.stroke(); } }
      else { const al = !u.side && B.hero2 && u.own !== myPid(); g.strokeStyle = u.side ? 'rgba(214,52,38,.75)' : al ? 'rgba(110,214,110,.8)' : (B.sel === 3 || u.grp.k === B.sel ? 'rgba(250,222,130,.85)' : 'rgba(110,165,235,.75)'); g.lineWidth = u.leader ? 2.6 : 1.5; if (u.comp) { g.strokeStyle = '#7fd6c8'; g.lineWidth = 2.2; } ell(g, u.x, u.y, u.r + 3, (u.r + 3) * .42); g.stroke(); }
    }
    g.save(); g.translate(u.x + ox, u.y + oy); if (u.flee) g.globalAlpha = .75; drawUnitSprite(g, u, sp, mv); g.restore();
    if (u.hp < u.maxHp && !demo) { const w = u.r * 1.9, hy = u.y - (sp.m ? 70 : 52); g.fillStyle = 'rgba(15,10,6,.8)'; g.fillRect(u.x - w / 2 - 1, hy - 1, w + 2, 5); g.fillStyle = u.side ? '#c23a2c' : '#7fb04a'; g.fillRect(u.x - w / 2, hy, w * clamp(u.hp / u.maxHp, 0, 1), 3); }
    if (u.leader && !demo) drawBanner(g, u.x - u.dir * 10, u.y - 2, u.fac, 17);
    if (u.comp && !demo) { g.font = '700 12px "Alegreya Sans SC","Alegreya Sans",sans-serif'; g.textAlign = 'center'; const ny = u.y - (sp.m ? 76 : 58); g.fillStyle = 'rgba(0,0,0,.7)'; g.fillText(u.name, u.x + 1, ny + 1); g.fillStyle = '#9fe3d6'; g.fillText(u.name, u.x, ny); }
    if (u.flee && !demo) { g.fillStyle = '#f4f0e0'; g.fillRect(u.x - 1, u.y - 66, 9, 6); g.fillStyle = '#3a2a18'; g.fillRect(u.x - 2, u.y - 67, 1.5, 14); }
  }
  fallDraw(g); goreDrawOver(g); voiceDraw(g);
  const h = B.hero;
  if (h && !h.dead && h.swing > 0) { const p = 1 - h.swing / .26, R = 34 + h.t.reach + (h.t.mounted ? 8 : 0), a0 = h.swingA - 1 + p * 2; g.strokeStyle = 'rgba(255,250,230,' + (.85 - p * .7) + ')'; g.lineWidth = 5; g.lineCap = 'round'; g.beginPath(); g.arc(h.x, h.y - 14, R, a0 - .7, a0); g.stroke(); }
  // стрелы
  g.lineCap = 'round';
  for (const a of B.arrows) { const p = a.t / a.dur, x = lerp(a.x0, a.x1, p), y = lerp(a.y0, a.y1, p), dd = Math.hypot(a.x1 - a.x0, a.y1 - a.y0), hgt = Math.sin(p * Math.PI) * dd * (a.xb ? .08 : .17), an = Math.atan2(a.y1 - a.y0 - Math.cos(p * Math.PI) * dd * .17 * 1.2, a.x1 - a.x0);
    g.strokeStyle = 'rgba(0,0,0,.25)'; g.lineWidth = 1.5; g.beginPath(); g.moveTo(x, y + 14); g.lineTo(x - Math.cos(an) * 8, y + 14); g.stroke();
    const ln = a.jv ? 22 : 12; g.strokeStyle = '#2a1c10'; g.lineWidth = a.jv ? 2.6 : 1.7; g.beginPath(); g.moveTo(x, y - hgt); g.lineTo(x - Math.cos(an) * ln, y - hgt - Math.sin(an) * ln); g.stroke(); g.strokeStyle = '#efe9d6'; g.lineWidth = 2.2; g.beginPath(); g.moveTo(x - Math.cos(an) * 10, y - hgt - Math.sin(an) * 10); g.lineTo(x - Math.cos(an) * 13, y - hgt - Math.sin(an) * 13); g.stroke(); }
  for (const p of B.fx) { g.globalAlpha = Math.min(1, p.l * 3); g.fillStyle = p.c; if (p.k) { ell(g, p.x, p.y, p.s, p.s * .7); g.fill(); } else g.fillRect(p.x, p.y, p.s, p.s); } g.globalAlpha = 1;
  g.font = '700 15px "Alegreya Sans SC","Alegreya Sans",sans-serif'; g.textAlign = 'center';
  for (const p of B.texts) { g.globalAlpha = Math.min(1, p.l * 2.5); g.lineWidth = 3; g.strokeStyle = 'rgba(15,10,6,.85)'; g.strokeText(p.s, p.x, p.y); g.fillStyle = p.c; g.fillText(p.s, p.x, p.y); } g.globalAlpha = 1;
  g.setTransform(1, 0, 0, 1, 0, 0);
  if (!B.cfg.demo && !B.over) drawFoeArrow(g);
}
/* враг за краем экрана — стрелка у края в его сторону с числом бойцов */
function drawFoeArrow(g) {
  const foe = centroid(1); if (!foe) return; const cam = B.cam, z = cam.z, d = VIEW.dpr;
  const sx = (foe.x - cam.x) * z + VIEW.w / 2, sy = (foe.y - cam.y) * z + VIEW.h / 2, m = 70;
  if (sx > 0 && sx < VIEW.w && sy > 0 && sy < VIEW.h) return;
  const cx = VIEW.w / 2, cy = VIEW.h / 2, a = Math.atan2(sy - cy, sx - cx), hw = cx - m, hh = cy - m - 40, k = Math.min(hw / Math.abs(Math.cos(a) || 1e-6), hh / Math.abs(Math.sin(a) || 1e-6));
  const x = cx + Math.cos(a) * k, y = cy + Math.sin(a) * k, pulse = .75 + Math.sin(B.t * 5) * .25;
  g.setTransform(d, 0, 0, d, d * x, d * y); g.rotate(a); g.globalAlpha = pulse;
  g.beginPath(); g.moveTo(22, 0); g.lineTo(-10, -15); g.lineTo(-4, 0); g.lineTo(-10, 15); g.closePath(); g.fillStyle = '#e0432f'; g.fill(); g.lineWidth = 3; g.strokeStyle = 'rgba(20,10,4,.9)'; g.stroke();
  g.setTransform(d, 0, 0, d, d * x, d * y); g.globalAlpha = 1; g.font = '700 15px "Alegreya Sans SC","Alegreya Sans",sans-serif'; g.textAlign = 'center';
  const t = 'Враг · ' + Math.round(foe.m), ty = Math.sin(a) > .3 ? -26 : 34; g.lineWidth = 4; g.strokeStyle = 'rgba(14,9,4,.9)'; g.strokeText(t, 0, ty); g.fillStyle = '#ffb3a6'; g.fillText(t, 0, ty);
  g.setTransform(1, 0, 0, 1, 0, 0);
}
function drawMinimap(c) {
  const g = c.getContext('2d'), w = c.width, h = c.height, sx = w / B.W, sy = h / B.H; g.clearRect(0, 0, w, h); g.globalAlpha = .9; g.drawImage(B.ground, 0, 0, w, h); g.globalAlpha = 1; g.fillStyle = 'rgba(10,8,4,.25)'; g.fillRect(0, 0, w, h);
  for (const u of B.units) { if (u.dead || u.gone) continue; g.fillStyle = u.side ? '#e0432f' : B.hero2 && u.own !== myPid() ? '#6fe06a' : (u.isHero ? '#fff' : '#5fa8f5'); const s = u.isHero ? 5 : u.t.mounted ? 4 : 3; g.fillRect(u.x * sx - s / 2, u.y * sy - s / 2, s, s); }
  const cam = B.cam; g.strokeStyle = 'rgba(255,255,255,.7)'; g.lineWidth = 1; g.strokeRect((cam.x - VIEW.w / 2 / cam.z) * sx, (cam.y - VIEW.h / 2 / cam.z) * sy, VIEW.w / cam.z * sx, VIEW.h / cam.z * sy);
}

/* ================= осада: стена с проломами ================= */
// стена — вертикальная полоса перед защитниками; пройти можно только через проломы (центральный — выбитые ворота)
function siegeSetup() {
  const sf = B.siegeF = clamp(B.cfg.csiege || 0, 0, .9); // осадное дело спутника: у защитников слабее дух, стена хуже укрывает
  const W = B.W, H = B.H, x = W - 980; B.wall = { x, hw: 22, gaps: [[H / 2 - 80, H / 2 + 80], [H / 2 - 520, H / 2 - 425], [H / 2 + 425, H / 2 + 520]] };
  B.trees = B.trees.filter(t => t.x < x - 140); // у стены и во дворе деревьев нет
  const [inf, arc, cav] = B.groups[1]; inf.cx = x + 80; inf.cy = H / 2; arc.cx = x + 52; arc.cy = H / 2; cav.cx = W - 380; cav.cy = H / 2; for (const g of B.groups[1]) { g.dir = Math.PI; g.order = 'hold'; g.st = 'siege'; layout(g, true); }
  for (const u of B.units) if (u.side === 1) { u.mbase += Math.round(28 * (1 - sf)); u.morale = u.mbase; if (!u.isHero) { const p = slotPos(u); u.x = p[0]; u.y = p[1]; } }
  if (!SERVER) paintWall(B.gg);
}
function inGap(y, pad) { for (const g of B.wall.gaps) if (y > g[0] + pad && y < g[1] - pad) return g; return null; }
function wallPush(a) {
  const w = B.wall, hw = w.hw + a.r * .8, dx = a.x - w.x; if (Math.abs(dx) >= hw) return;
  const g = inGap(a.y, 0); if (g) { a.y = clamp(a.y, g[0] + a.r * .75, g[1] - a.r * .75); return; }
  a.x = w.x + (dx < 0 ? -hw : hw); if (a.vx && Math.sign(a.vx) !== Math.sign(dx || -1)) a.vx = 0;
}
// цель по ту сторону стены — сперва идём к ближайшему пролому
function wallVia(u, tx, ty) {
  const w = B.wall, su = u.x < w.x ? -1 : 1, st = tx < w.x ? -1 : 1; if (su === st) return [tx, ty];
  let best = null, bd = 1e9; for (const g of w.gaps) { const c = (g[0] + g[1]) / 2, d = Math.abs(c - u.y) + Math.abs(c - ty) * .6 + ((u.id * 37) % 23); if (d < bd) { bd = d; best = g; } }
  const c = (best[0] + best[1]) / 2, half = (best[1] - best[0]) / 2 - u.r, gy = clamp(u.y, c - half, c + half), adx = Math.abs(u.x - w.x);
  if (adx < w.hw + 34 && Math.abs(u.y - c) < half) return [w.x - su * 70, gy];
  return [w.x + su * (w.hw + 30), adx < 140 ? c : gy];
}
// стрелки за стеной получают укрытие от стрел с другой стороны
function wallCover(hit, a) { const w = B.wall; if (!w) return 1; const behind = hit.side === 1 && hit.x > w.x && hit.x < w.x + 80 && a.x0 < w.x && !inGap(hit.y, 0); return behind ? .45 + .5 * (B.siegeF || 0) : 1; }
// защитники: пехота держит ворота, стрелки — за стеной, конница — в резерве; выходят, когда враг прорвался внутрь
function siegeBrain(dt) {
  const w = B.wall, [inf, arc, cav] = B.groups[1]; let inside = 0, near = 0; for (const u of B.units) if (u.side === 0 && fit(u)) { if (u.x > w.x + w.hw) inside++; if (u.x > w.x - 160) near++; }
  if (inf.order !== 'charge' && (inside > 2 || B.t > 150)) inf.order = 'charge';
  if (cav.order !== 'charge' && (inside > 4 || B.t > 170)) { cav.order = 'charge'; if (!B.cfg.demo) blog('Конница гарнизона вышла в бой', 1); }
  if (arc.order !== 'charge' && (inside > 8 || !inf.units.some(fit))) arc.order = 'charge';
  if (near && !B.siegeHorn) { B.siegeHorn = 1; blog('Враг у стен!', 1); sfx('horn2'); }
}
function paintWall(g) {
  const w = B.wall, H = B.H, x0 = w.x - w.hw, ww = w.hw * 2, segs = []; let y = 0; for (const gp of w.gaps.slice().sort((a, b) => a[0] - b[0])) { segs.push([y, gp[0]]); y = gp[1]; } segs.push([y, H]);
  const R = mulberry(B.cfg.seed || 7);
  g.save();
  for (const [a, b] of segs) {
    g.fillStyle = 'rgba(0,0,0,.28)'; g.fillRect(x0 - 14, a + 10, ww + 10, b - a); // тень
    g.fillStyle = '#857a68'; g.fillRect(x0, a, ww, b - a); g.strokeStyle = '#2a2219'; g.lineWidth = 3; g.strokeRect(x0, a, ww, b - a);
    g.strokeStyle = 'rgba(40,32,24,.55)'; g.lineWidth = 1.2; for (let yy = a + 12; yy < b; yy += 14) { g.beginPath(); g.moveTo(x0, yy); g.lineTo(x0 + ww, yy); g.stroke(); const o = (yy / 14 | 0) % 2 ? 11 : 22; g.beginPath(); g.moveTo(x0 + o, yy - 14); g.lineTo(x0 + o, yy); g.stroke(); }
    g.fillStyle = '#a49884'; for (let yy = a + 6; yy < b - 8; yy += 22) { g.fillRect(x0 + ww - 9, yy, 9, 12); g.strokeStyle = '#2a2219'; g.lineWidth = 1.5; g.strokeRect(x0 + ww - 9, yy, 9, 12); } // зубцы со стороны защитников
    for (const ty of [a, b]) { if (ty <= 0 || ty >= H) continue; g.fillStyle = 'rgba(0,0,0,.3)'; ell(g, w.x - 6, ty + 10, 36, 34); g.fill(); g.fillStyle = '#93877318'; g.fillStyle = '#93876f'; ell(g, w.x, ty, 34, 34); g.fill(); g.strokeStyle = '#2a2219'; g.lineWidth = 3; g.stroke(); g.fillStyle = '#6d6252'; ell(g, w.x, ty, 22, 22); g.fill(); }
  }
  for (const gp of w.gaps) { const c = (gp[0] + gp[1]) / 2, gate = gp[1] - gp[0] > 140; // обломки в проломах
    for (let i = 0; i < 26; i++) { const yy = gp[0] + 18 + R() * (gp[1] - gp[0] - 36), xx = x0 - 6 + R() * (ww + 12), r = 3 + R() * 6; g.fillStyle = R() < .5 ? '#7a6f5e' : '#968a74'; ell(g, xx, yy, r, r * .75); g.fill(); g.strokeStyle = '#2a2219'; g.lineWidth = 1; g.stroke(); }
    if (gate) for (const s of [-1, 1]) { g.save(); g.translate(w.x + 10, c + s * 52); g.rotate(s * .9); g.fillStyle = '#5b3d22'; g.fillRect(-26, -7, 52, 14); g.strokeStyle = '#21160b'; g.lineWidth = 2; g.strokeRect(-26, -7, 52, 14); g.restore(); } }
  g.restore();
}
