// Загружает общую симуляцию (те же файлы, что и в браузере) в изолированную область видимости.
const fs = require('fs'), path = require('path');
const SRC = path.join(__dirname, '..', 'src');
const FILES = ['01_core.js', '03_battle.js', '05_world.js', '05c_logic.js', '05d_trade.js'];
const prelude = `
function sfx(n, u) { if (typeof B !== 'undefined' && B && B.ev) B.ev.push(['s', n, u && u.id !== undefined ? u.id : -1]); }
`;
const tail = `
function markRoads() { WT.road.fill(0); for (const seg of G.roads) for (let i = 0; i < seg.length - 1; i++) { const n = Math.ceil(Math.hypot(seg[i + 1].x - seg[i].x, seg[i + 1].y - seg[i].y) / 8); for (let k = 0; k <= n; k++) WT.road[cellOf(lerp(seg[i].x, seg[i + 1].x, k / n), lerp(seg[i].y, seg[i + 1].y, k / n))] = 1; } }
function dumpWorld() {
  const O = { ver: 1, seed: G.seed, nid: G.nid, day: G.day, hour: G.hour, hourAcc: G.hourAcc || 0, speed: G.speed, roads: G.roads, stats: G.stats, log: G.log,
    settles: G.settles.map(s => Object.assign({}, s, { camp: s.camp ? s.camp.id : null })),
    parties: G.parties.map(p => Object.assign({}, p, { lock: null })),
    factions: (G.factions || []).map(F => Object.assign({}, F)),
    players: G.players.map(P => Object.assign({}, P, { rel: P.fid ? null : P.rel, finv: null, away: true, busy: null, in: null, enc: null, pendRes: null, resT: null, tid: null, sid: null, path: [], pi: 0 })) };
  return JSON.stringify(O);
}
function loadWorld(d) {
  G = { seed: d.seed, nid: d.nid, day: d.day, hour: d.hour, acc: 0, speed: d.speed || 1, paused: false, parties: d.parties, settles: d.settles, roads: d.roads, players: d.players, player: null, log: d.log || [], stats: d.stats || { wins: 0, kills: 0 }, ver: 2, hourAcc: d.hourAcc || 0, factions: d.factions || [] };
  for (const F of G.factions) for (const P of G.players) if (P.fid === F.id) P.rel = F.rel;
  for (const P of G.players) if (!P.rel) { P.fid = null; P.rel = { nord: 0, emp: 0, khan: 0, bandit: -100 }; }
  genWorld(d.seed); for (const s of G.settles) s.camp = s.camp ? G.parties.find(p => p.id === s.camp) || null : null; markRoads(); return G;
}
return {
  dumpWorld, loadWorld,
  get G() { return G; }, set G(v) { G = v; }, get B() { return B; }, set B(v) { B = v; }, get WT() { return WT; },
  newWorld, addPlayer, mkPlayer, stepWorld, hourTick, findPath, losClear, settleById, partyById, genWorld, markRoadsFrom: null,
  townEnter, doHire, doGear, doFood, doUpgrade, doAttr, doAccept, encAttack, encFlee, battleCfgFor, autoResult, applyBattleResult, isHostileToPlayer,
  doBuy, doSell, doEquip, doUnequipHorse, rollLoot, dropText, marketOf, hasMarket, ITEM, TRADE_WHY, invN,
  startBattle, battleUpdate, giveOrder, speedOf, sizeCap, troopCount, strength, partyStr, leaderType, wageDay, logW, relName, FACTIONS, TROOPS, GEAR, BANNERS, WW, WH, cellOf, TCOST, heroDef,
};`;
function load() {
  const code = prelude + FILES.map(f => fs.readFileSync(path.join(SRC, f), 'utf8')).join('\n') + tail;
  return new Function('__SRV', code)(true);
}
module.exports = { load };
