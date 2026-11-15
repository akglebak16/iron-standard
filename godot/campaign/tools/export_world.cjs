// Выгружает из браузерного src/05_world.js данные Европы и эталон генерации (для теста совпадения в Godot).
// Запуск: node godot/campaign/tools/export_world.cjs
const fs = require('fs'), path = require('path'), vm = require('vm');
const root = path.join(__dirname, '..', '..', '..');
const code = ['01_core.js', '05_world.js'].map(f => fs.readFileSync(path.join(root, 'src', f), 'utf8')).join('\n');
const tail = `
;globalThis.__api = { genWorld, genSettlements, genRoads, getG: () => G, FAC_V, SNAMES2, CAMPN2, DEFAULT_MAPV, setMapSize, getWT: () => WT, setG: g => { G = g; }, EU_SHAPES, EU_RIDGES, EU_REG, EU_RIVERS, EU, GC, size: () => [WW, WH, GW, GH] };`;
const ctx = { console, Math, Float32Array, Int32Array, Uint8Array, Map, Set, document: { querySelector: () => null }, window: {}, localStorage: {} };
vm.createContext(ctx);
vm.runInContext(code + tail, ctx, { filename: 'world.js' });
const A = ctx.__api;
const outData = path.join(root, 'godot', 'campaign', 'data', 'europe.json');
fs.writeFileSync(outData, JSON.stringify({ eu: A.EU, shapes: A.EU_SHAPES, ridges: A.EU_RIDGES, regions: A.EU_REG, rivers: A.EU_RIVERS, factions: A.FAC_V[A.DEFAULT_MAPV], town_names: A.SNAMES2, camp_names: A.CAMPN2 }));
const fix = { seeds: [] };
for (const seed of [1, 12345, 777777]) {
  A.setG({ seed, mapv: A.DEFAULT_MAPV, rv: 1, nid: 1, settles: [], roads: [] }); A.setMapSize(A.DEFAULT_MAPV);
  const W = A.genWorld(seed), [WW, WH, GW, GH] = A.size();
  A.genSettlements(); A.genRoads(); const G = A.getG();
  fix.seeds.push({ seed, GW, GH, cells: Buffer.from(W.cells).toString('base64'), bio: Buffer.from(W.bio).toString('base64'),
    bridges: W.bridges.length, road: Buffer.from(W.road).toString('base64'),
    settles: G.settles.map(t => [t.id, t.kind, t.fac, t.name, t.x, t.y]), roads: G.roads.map(seg => seg.map(q => [q.x, q.y])), rivers: W.rivers.map(r => [r.w, r.c.length, r.p.length]),
    samples: [[500, 500], [2600, 1700], [3100, 900], [1200, 2500], [4400, 2800]].map(([x, y]) => { const i = W.info(x, y); return [x, y, i.e, i.t, W.biomeAt(x, y)]; }) });
}
fs.mkdirSync(path.join(root, 'godot', 'campaign', 'tests', 'fixtures'), { recursive: true });
fs.writeFileSync(path.join(root, 'godot', 'campaign', 'tests', 'fixtures', 'world_parity.json'), JSON.stringify(fix));
console.log('ok', fs.statSync(outData).size, JSON.stringify(fix).length);
