// Выгружает из браузерного src/05_world.js данные Европы и эталон генерации (для теста совпадения в Godot).
// Запуск: node godot/campaign/tools/export_world.cjs
const fs = require('fs'), path = require('path'), vm = require('vm');
const root = path.join(__dirname, '..', '..', '..');
const code = ['01_core.js', '05_world.js'].map(f => fs.readFileSync(path.join(root, 'src', f), 'utf8')).join('\n');
const tail = `
;globalThis.__api = { genWorld, setMapSize, getWT: () => WT, setG: g => { G = g; }, EU_SHAPES, EU_RIDGES, EU_REG, EU_RIVERS, EU, GC, size: () => [WW, WH, GW, GH] };`;
const ctx = { console, Math, Float32Array, Int32Array, Uint8Array, Map, Set, document: { querySelector: () => null }, window: {}, localStorage: {} };
vm.createContext(ctx);
vm.runInContext(code + tail, ctx, { filename: 'world.js' });
const A = ctx.__api;
const outData = path.join(root, 'godot', 'campaign', 'data', 'europe.json');
fs.writeFileSync(outData, JSON.stringify({ eu: A.EU, shapes: A.EU_SHAPES, ridges: A.EU_RIDGES, regions: A.EU_REG, rivers: A.EU_RIVERS }));
const fix = { seeds: [] };
for (const seed of [1, 12345, 777777]) {
  A.setG({ mapv: 2, rv: 1 }); A.setMapSize(2);
  const W = A.genWorld(seed), [WW, WH, GW, GH] = A.size();
  fix.seeds.push({ seed, GW, GH, cells: Buffer.from(W.cells).toString('base64'), bio: Buffer.from(W.bio).toString('base64'),
    bridges: W.bridges.length, rivers: W.rivers.map(r => [r.w, r.c.length, r.p.length]),
    samples: [[500, 500], [2600, 1700], [3100, 900], [1200, 2500], [4400, 2800]].map(([x, y]) => { const i = W.info(x, y); return [x, y, i.e, i.t, W.biomeAt(x, y)]; }) });
}
fs.mkdirSync(path.join(root, 'godot', 'campaign', 'tests', 'fixtures'), { recursive: true });
fs.writeFileSync(path.join(root, 'godot', 'campaign', 'tests', 'fixtures', 'world_parity.json'), JSON.stringify(fix));
console.log('ok', fs.statSync(outData).size, JSON.stringify(fix).length);
