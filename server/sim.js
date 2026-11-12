// Загружает общую симуляцию (те же файлы, что и в браузере) в изолированную область видимости.
const fs = require('fs'), path = require('path');
const SRC = path.join(__dirname, '..', 'src');
const FILES = ['01_core.js', '03_battle.js', '05_world.js', '05c_logic.js'];
const prelude = `
function sfx(n, u) { if (typeof B !== 'undefined' && B && B.ev) B.ev.push(['s', n, u && u.id !== undefined ? u.id : -1]); }
`;
const tail = `
return {
  get G() { return G; }, set G(v) { G = v; }, get B() { return B; }, set B(v) { B = v; }, get WT() { return WT; },
  newWorld, addPlayer, mkPlayer, stepWorld, hourTick, findPath, losClear, settleById, partyById, genWorld, markRoadsFrom: null,
  townEnter, doHire, doGear, doFood, doUpgrade, doAttr, doAccept, encAttack, encFlee, battleCfgFor, autoResult, applyBattleResult, isHostileToPlayer,
  startBattle, battleUpdate, giveOrder, speedOf, sizeCap, troopCount, strength, partyStr, leaderType, wageDay, logW, relName, FACTIONS, TROOPS, GEAR, BANNERS, WW, WH, cellOf, TCOST, heroDef,
};`;
function load() {
  const code = prelude + FILES.map(f => fs.readFileSync(path.join(SRC, f), 'utf8')).join('\n') + tail;
  return new Function('__SRV', code)(true);
}
module.exports = { load };
