// Сервер «Железного Стяга»: общий мир на двоих. Без внешних зависимостей.
const http = require('http'), fs = require('fs'), path = require('path');
const { attach } = require('./ws');
const sim = require('./sim').load();

const PORT = +process.env.PORT || 3000, CODE = process.env.ROOM_CODE || '';
const DAY_SEC = +process.env.DAY_SEC || 72;       // реальных секунд в игровых сутках при ×1
const MOVE_K = +process.env.MOVE_K || 2.5;        // ускорение передвижения по карте относительно часов
const MAX_PLAYERS = 2, ENC_TIMEOUT = 45000, RES_TIMEOUT = 40000;
const ROOT = path.join(__dirname, '..');

/* ---------- HTTP ---------- */
const server = http.createServer((req, res) => {
  const u = req.url.split('?')[0];
  if (u === '/health') { res.writeHead(200); return res.end('ok'); }
  if (u === '/' || u === '/index.html') {
    fs.readFile(path.join(ROOT, 'index.html'), (e, d) => { if (e) { res.writeHead(500); return res.end('no build'); } res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache' }); res.end(d); });
    return;
  }
  if (process.env.MP_DEBUG && u === '/__dbg') { let body = ''; req.on('data', d => body += d); req.on('end', () => { try { const r = new Function('S', 'return (' + body + ')')(DBG); res.writeHead(200); res.end(JSON.stringify(r === undefined ? null : r)); } catch (e) { res.writeHead(500); res.end(String(e.stack)); } }); return; }
  res.writeHead(404); res.end('not found');
});

/* ---------- состояние ---------- */
sim.newWorld(+process.env.SEED || 0);
const G = sim.G; G.hourAcc = 0; G.speed = 1; G.paused = false;
const conns = new Set();             // активные соединения с игроком
const battles = new Map();           // id -> бой
let bid = 1, vote = null;
const FAC = sim.FACTIONS;
const playerOf = c => c.P;
const online = () => [...conns].filter(c => c.P);
const send = (c, o) => { if (c && c.open) c.send(JSON.stringify(o)); };
const bcast = o => { const s = JSON.stringify(o); for (const c of conns) if (c.open && c.P) c.send(s); };
const connOf = P => [...conns].find(c => c.P === P && c.open);
const rnd2 = n => Math.round(n * 10) / 10;

function staticSettle(s) { const o = {}; for (const k in s) if (k !== 'recruits' && k !== 'board' && k !== 'camp') o[k] = s[k]; return o; }
function initMsg(P) { return { t: 'init', you: P.id, seed: G.seed, roads: G.roads, settles: G.settles.map(staticSettle), day: DAY_SEC }; }

function meMsg(P) {
  const bt = battleOf(P);
  return { t: 'me', inv: P.inv || {}, gold: P.gold, food: P.food, troops: P.troops, hero: P.hero, quests: P.quests, rel: P.rel, stats: P.stats, name: P.name, culture: P.culture, banner: P.banner,
    in: P.in, busy: P.busy, wage: sim.wageDay(P), cap: sim.sizeCap(P.hero), log: P.log.slice(-8), path: P.path.slice(P.pi).map(p => [Math.round(p.x), Math.round(p.y)]), bid: bt ? bt.id : 0 };
}
function worldMsg() {
  const players = G.players.filter(P => !P.away).map(P => [P.id, P.name, rnd2(P.x), rnd2(P.y), P.fx < 0 ? -1 : 1, P.banner, P.culture, P.in ? 1 : 0, P.busy ? 1 : 0, P.troops.reduce((a, s) => a + s.n, 0), sim.leaderType(P), P.hero.horse ? 1 : 0]);
  const parties = G.parties.filter(p => !p.hide).map(p => [p.id, p.kind, p.fac, rnd2(p.x), rnd2(p.y), p.fx < 0 ? -1 : 1, p.name, p.troops.map(s => [s.type, s.n]), p.lock ? 1 : 0]);
  const camps = G.settles.filter(s => s.kind === 'camp').map(s => [s.id, s.camp ? s.camp.id : 0, s.cleared ? 1 : 0]);
  return { t: 'w', day: G.day, hour: G.hour, hf: G.hourAcc, paused: G.paused, speed: G.speed, players, parties, camps, vote: vote ? { k: vote.k, v: vote.v, by: vote.byName, yes: vote.yes.size } : null };
}
function townMsg(s) { return { t: 'town', sid: s.id, recruits: s.recruits, board: s.board || [], market: sim.hasMarket(s) ? sim.marketOf(s) : null }; }
function pushTown(sid) { const s = sim.settleById(sid); if (!s) return; for (const c of online()) if (c.P.in === sid) send(c, townMsg(s)); }
function sendMe(P) { const c = connOf(P); if (c) send(c, meMsg(P)); }
function battleOf(P) { for (const b of battles.values()) if (b.P === P) return b; return null; }
function sysChat(txt) { bcast({ t: 'chat', from: '', txt }); }

/* ---------- встречи ---------- */
function enterTown(P, s) { sim.townEnter(P, s); const c = connOf(P); P.busy = null; sendMe(P); if (c) send(c, Object.assign(townMsg(s), { open: 1 })); }
function beginEnc(P, p, forced) {
  P.busy = 'enc'; P.path = []; P.tid = null; P.sid = null; p.lock = P.id;
  const hostile = sim.isHostileToPlayer(p, P) || p.kind === 'camp';
  P.enc = { pid: p.id, forced, hostile, t0: Date.now() };
  const pw = relPower(P, p);
  send(connOf(P), { t: 'enc', p: { id: p.id, kind: p.kind, fac: p.fac, name: p.name, troops: p.troops }, forced, hostile, pw });
  sendMe(P);
}
function relPower(P, p) { const a = sim.strength(P.troops) + 8, b = sim.partyStr(p), r = a / Math.max(1, b); return r > 2 ? ['Мы сильнее', 'g'] : r > 1.15 ? ['Мы чуть сильнее', 'g'] : r > .8 ? ['Силы равны', 'b'] : r > .45 ? ['Они сильнее', 'r'] : ['Они намного сильнее', 'r']; }
function encParty(P) { return P.enc ? sim.partyById(P.enc.pid) : null; }
function resolveEnc(P, a) {
  const p = encParty(P); if (!p) { P.enc = null; if (P.busy === 'enc') P.busy = null; sendMe(P); return; }
  const e = P.enc;
  if (a === 'greet') { if (e.hostile) return; p.cd = 3; p.lock = null; P.enc = null; P.busy = null; }
  else if (a === 'attack') { if (e.hostile) return; sim.encAttack(P, p); P.enc = null; startBattle(P, p); }
  else if (a === 'fight') { P.enc = null; startBattle(P, p); }
  else if (a === 'auto') { P.enc = null; finishWith(P, p, sim.autoResult(P, p), 0); }
  else if (a === 'flee') { const ok = sim.encFlee(P, p); P.enc = null; if (ok) { p.lock = null; P.busy = null; const c = connOf(P); send(c, { t: 'toast', s: 'Ты оторвался от погони' }); } else { send(connOf(P), { t: 'toast', s: 'Не вышло уйти!' }); startBattle(P, p); } }
  sendMe(P);
}

/* ---------- бои ---------- */
function startBattle(P, p) {
  P.busy = 'battle'; P.enc = null; p.lock = P.id;
  const cfg = sim.battleCfgFor(P, p); cfg.heroAI = false;
  const bt = { id: bid++, P, p, cfg, B: null, tick: 0 };
  cfg.onEnd = res => endBattle(bt, res);
  sim.B = null; bt.B = sim.startBattle(cfg); battles.set(bt.id, bt);
  send(connOf(P), startMsg(bt));
}
function startMsg(bt) { const c = bt.cfg; return { t: 'bs', id: bt.id, cfg: { pl: c.pl, en: c.en, pfac: c.pfac, efac: c.efac, biome: c.biome, forest: c.forest, title: c.title, hero: c.hero, leader: c.leader, seed: c.seed } }; }
function snap(bt, fin) {
  const B = bt.B, u = B.units.map(x => (x.dead || x.gone) ? [(x.dead ? 1 : 0) | (x.gone ? 4 : 0)] : [rnd2(x.x), rnd2(x.y), Math.round(x.vx), Math.round(x.vy), Math.round(x.face * 100) / 100, Math.max(0, Math.round(x.hp)), (x.flee ? 2 : 0) | (x.blocking ? 8 : 0) | (x.ai ? 16 : 0) | (x.flash > 0 ? 32 : 0), Math.round(Math.max(0, x.swing || 0) * 100) / 100, Math.round(x.bump * 100) / 100]);
  const h = B.hero, hm = h ? { hp: Math.round(h.hp), mhp: Math.round(h.maxHp), st: Math.round(h.stam), sa: Math.round((h.swingA || 0) * 100) / 100, down: B.heroDown ? 1 : 0 } : null;
  let n0 = 0, n1 = 0; for (const x of B.units) if (!x.dead && !x.gone && !x.flee) { if (x.side) n1++; else n0++; }
  const m = { t: 'b', id: bt.id, tm: Math.round(B.t * 100) / 100, u, ev: B.ev, h: hm, n: [n0, n1], over: B.over ? 1 : 0, win: B.win ? 1 : 0, fin: fin ? 1 : 0 };
  B.ev = []; return m;
}
function giveHeroInput(bt, m) { const h = bt.B.hero; if (!h || h.ai || !bt.P) return; const f = x => (typeof x === 'number' && isFinite(x)) ? x : 0; h.inp = { dx: f(m.dx), dy: f(m.dy), face: typeof m.face === 'number' && isFinite(m.face) ? m.face : undefined, atk: m.atk ? 1 : 0, blk: m.blk ? 1 : 0, spr: m.spr ? 1 : 0 }; }
function battleTick(dt) {
  for (const bt of [...battles.values()]) {
    sim.B = bt.B; const B = bt.B;
    if (B.hero && !connOf(bt.P)) B.hero.ai = true;
    sim.battleUpdate(dt);
    if (!battles.has(bt.id)) continue;
    bt.tick++;
    if (bt.tick % 2 === 0) { const c = connOf(bt.P); const m = snap(bt, false); if (c) send(c, m); }
  }
}
function endBattle(bt, res) {
  const B = bt.B, P = bt.P, p = bt.p; const c = connOf(P);
  if (c) send(c, snap(bt, true));
  battles.delete(bt.id);
  finishWith(P, p, res, B.t);
}
function finishWith(P, p, res, tm) {
  if (!res.time) res.time = tm;
  const R = sim.applyBattleResult(P, res, p);
  if (R.win) { R.drops = sim.rollLoot(P, p); if (R.drops.length) sim.logW('Трофеи: ' + sim.dropText(R.drops) + '.', 3, P); }
  P.busy = 'res'; P.resT = Date.now(); P.pendRes = { t: 'br', r: R, p: { name: p.name } };
  const c = connOf(P); if (c) { send(c, P.pendRes); } sendMe(P);
}

/* ---------- голосование ---------- */
function applyVote(v) { if (v.k === 'pause') G.paused = !!v.v; else if (v.k === 'speed') { G.speed = v.v; G.paused = false; } }
function propose(c, m) {
  const P = c.P, k = m.k === 'speed' ? 'speed' : 'pause', v = k === 'speed' ? (m.v === 2 || m.v === 4 ? m.v : 1) : !!m.v;
  const others = online().filter(x => x !== c);
  if (!others.length) { applyVote({ k, v }); sysChat('Время: ' + describe({ k, v })); return; }
  vote = { k, v, by: P.id, byName: P.name, yes: new Set([P.id]), t: Date.now() };
  bcast(worldMsg());
}
function describe(v) { return v.k === 'pause' ? (v.v ? 'пауза' : 'пауза снята') : '×' + v.v; }
function castVote(c, yes) {
  if (!vote) return; if (!yes) { sysChat(c.P.name + ' против: ' + describe(vote)); vote = null; return; }
  vote.yes.add(c.P.id); const need = online().length;
  if (online().every(x => vote.yes.has(x.P.id)) && vote.yes.size >= need) { applyVote(vote); sysChat('Согласие: ' + describe(vote)); vote = null; }
}

/* ---------- сообщения клиентов ---------- */
function handleJoin(c, m) {
  const name = String(m.name || '').trim().slice(0, 18); if (!name) return send(c, { t: 'err', s: 'Введи имя' });
  if (CODE && String(m.code || '') !== CODE) return send(c, { t: 'err', s: 'Неверный код комнаты' });
  let P = G.players.find(q => q.name.toLowerCase() === name.toLowerCase());
  if (P) { if (connOf(P)) return send(c, { t: 'err', s: 'Это имя уже в игре' }); }
  else {
    if (G.players.length >= MAX_PLAYERS) return send(c, { t: 'err', s: 'В мире уже двое. Войди под своим именем.' });
    const cult = ['nord', 'emp', 'khan'].includes(m.culture) ? m.culture : 'nord';
    P = sim.addPlayer({ name, culture: cult, banner: Math.max(0, Math.min(sim.BANNERS.length - 1, +m.banner || 0)) });
  }
  c.P = P; P.away = false; conns.add(c);
  send(c, initMsg(P)); send(c, worldMsg()); sendMe(P);
  const bt = battleOf(P);
  if (bt) { if (bt.B.hero) bt.B.hero.ai = false; send(c, startMsg(bt)); }
  else if (P.pendRes) send(c, P.pendRes);
  else if (P.in) { const s = sim.settleById(P.in); if (s) send(c, Object.assign(townMsg(s), { open: 1 })); }
  sysChat(P.name + ' вошёл в мир');
}
function handle(c, m) {
  if (m.t === 'join') return handleJoin(c, m);
  const P = c.P; if (!P) return;
  const free = !P.busy && !P.in;
  switch (m.t) {
    case 'go': if (free && isFinite(m.x) && isFinite(m.y)) { P.tid = null; P.sid = null; const pa = sim.findPath(P.x, P.y, Math.max(10, Math.min(sim.WW - 10, m.x)), Math.max(10, Math.min(sim.WH - 10, m.y))); if (pa) { P.path = pa; P.pi = 0; sendMe(P); } else send(c, { t: 'toast', s: 'Туда не пройти' }); } break;
    case 'goT': if (free) { const p = sim.partyById(+m.id); if (p && !p.hide) { P.sid = null; P.tid = p.id; P.path = sim.findPath(P.x, P.y, p.x, p.y) || []; P.pi = 0; P.rp = .6; sendMe(P); } } break;
    case 'goS': if (free) { const s = sim.settleById(+m.id); if (s && s.kind !== 'camp') { if (Math.hypot(s.x - P.x, s.y - P.y) < 46) enterTown(P, s); else { P.tid = null; P.sid = s.id; P.path = sim.findPath(P.x, P.y, s.x, s.y) || []; P.pi = 0; if (!P.path.length) P.sid = null; sendMe(P); } } } break;
    case 'enter': if (free) { const s = sim.settleById(+m.id); if (s && s.kind !== 'camp' && Math.hypot(s.x - P.x, s.y - P.y) < 46) enterTown(P, s); } break;
    case 'leave': if (P.in) { P.in = null; sendMe(P); } break;
    case 'hire': { const s = P.in && sim.settleById(P.in); if (s && sim.doHire(P, s, String(m.type), Math.max(1, Math.min(50, +m.n || 1)))) { sendMe(P); pushTown(s.id); } break; }
    case 'gear': if (P.in && sim.doGear(P, String(m.k))) sendMe(P); break;
    case 'food': if (P.in && sim.doFood(P, +m.n, +m.p)) sendMe(P); break;
    case 'accept': { const s = P.in && sim.settleById(P.in); if (s) { const r = sim.doAccept(P, s, +m.q); if (r) send(c, { t: 'toast', s: r }); sendMe(P); pushTown(s.id); } break; }
    case 'tbuy': case 'tsell': { const s = P.in && sim.settleById(P.in); if (!s || !sim.ITEM[m.id]) break; const n = Math.max(1, Math.min(99, +m.n || 1)), buy = m.t === 'tbuy', r = buy ? sim.doBuy(P, s, m.id, n) : sim.doSell(P, s, m.id, n), nm = sim.ITEM[m.id].name;
      if (r.n) send(c, { t: 'toast', s: (buy ? 'Куплено: ' : 'Продано: ') + nm + (r.n > 1 ? ' ×' + r.n : '') + ' за ' + r.sum }); else send(c, { t: 'toast', s: sim.TRADE_WHY[r.why] || 'Не вышло' });
      sendMe(P); pushTown(s.id); break; }
    case 'equip': if (P.busy !== 'battle' && sim.ITEM[m.id] && sim.doEquip(P, String(m.id))) { send(c, { t: 'toast', s: 'Надето: ' + sim.ITEM[m.id].name }); sendMe(P); } break;
    case 'unhorse': if (P.busy !== 'battle' && sim.doUnequipHorse(P)) { send(c, { t: 'toast', s: 'Конь отправлен в обоз' }); sendMe(P); } break;
    case 'upg': if (P.busy !== 'battle' && sim.doUpgrade(P, String(m.type), String(m.up))) sendMe(P); break;
    case 'dismiss': if (P.busy !== 'battle' && sim.TROOPS[m.type]) { const s = P.troops.find(x => x.type === m.type); if (s) { s.n--; if (s.n <= 0) P.troops.splice(P.troops.indexOf(s), 1); sendMe(P); } } break;
    case 'attr': if (sim.doAttr(P, String(m.k))) sendMe(P); break;
    case 'enc': if (P.busy === 'enc') resolveEnc(P, String(m.a)); break;
    case 'ack': if (P.busy === 'res') { P.busy = null; P.pendRes = null; sendMe(P); } break;
    case 'inp': { const bt = battleOf(P); if (bt) giveHeroInput(bt, m); break; }
    case 'ord': { const bt = battleOf(P); if (bt && ['hold', 'follow', 'charge', 'back'].includes(m.ord)) { sim.B = bt.B; sim.giveOrder(m.ord, +m.wx || 0, +m.wy || 0, [0, 1, 2, 3].includes(m.sel) ? m.sel : 3); } break; }
    case 'retreat': { const bt = battleOf(P); if (bt && !bt.B.over) { sim.B = bt.B; bt.B.over = bt.B.t; bt.B.win = false; } break; }
    case 'prop': propose(c, m); break;
    case 'vote': castVote(c, !!m.yes); break;
    case 'chat': { const txt = String(m.txt || '').slice(0, 200).trim(); if (txt) bcast({ t: 'chat', from: P.name, txt }); break; }
  }
}

attach(server, c => {
  c.P = null; c.alive = true;
  c.onmessage = s => { let m; try { m = JSON.parse(s); } catch (e) { return; } try { handle(c, m); } catch (e) { console.error('handle', e); } };
  c.onclose = () => {
    conns.delete(c); const P = c.P; if (!P) return;
    if (connOf(P)) return;
    P.away = true; P.path = []; P.tid = null; P.sid = null;
    if (P.busy === 'enc') resolveEnc(P, P.enc && P.enc.hostile ? 'auto' : 'greet');
    if (P.in) P.in = null;
    const bt = battleOf(P); if (bt && bt.B.hero) bt.B.hero.ai = true;
    if (vote && vote.by === P.id) vote = null;
    sysChat(P.name + ' вышел из мира');
  };
  c.sock.on('pong', () => { });
});

/* ---------- главный цикл ---------- */
let last = Date.now(), wtick = 0, mtick = 0;
setInterval(() => { const now = Date.now(), dt = Math.min(.25, (now - last) / 1000); last = now; battleTick(Math.min(dt, 1 / 20)); }, 33);
let wlast = Date.now();
setInterval(() => {
  const now = Date.now(), dt = Math.min(.5, (now - wlast) / 1000); wlast = now;
  if (!online().length) return;
  if (vote && now - vote.t > 25000) { vote = null; }
  if (!G.paused) {
    const dh = dt * 24 / DAY_SEC * G.speed;
    const evs = sim.stepWorld(dh * MOVE_K);
    G.hourAcc += dh; let guard = 0; while (G.hourAcc >= 1 && guard++ < 10) { G.hourAcc -= 1; sim.hourTick(); }
    for (const ev of evs) { if (ev.P.busy || ev.P.in || ev.P.away) continue; if (ev.type === 'enter') enterTown(ev.P, ev.s); else if (ev.type === 'meet') beginEnc(ev.P, ev.p, ev.forced); }
  }
  for (const P of G.players) {
    if (P.busy === 'enc' && P.enc && now - P.enc.t0 > ENC_TIMEOUT) resolveEnc(P, P.enc.hostile ? 'auto' : 'greet');
    if (P.busy === 'res' && now - P.resT > RES_TIMEOUT) { P.busy = null; P.pendRes = null; sendMe(P); }
  }
  wtick++;
  if (wtick % 2 === 0) bcast(worldMsg());
  if (wtick % 5 === 0) for (const c of online()) send(c, meMsg(c.P));
  if (wtick % 150 === 0) for (const c of conns) c.ping();
}, 100);

const DBG = { sim, G, battles, conns, get vote() { return vote; } };
server.listen(PORT, () => console.log('Железный Стяг: сервер на порту ' + PORT + (CODE ? ' (код комнаты задан)' : '')));
