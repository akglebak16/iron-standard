/* Ground truth is the original Canvas code, not a JS rewrite of the GDScript formulas. */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createCanvas } = require('@napi-rs/canvas');
const root = path.resolve(__dirname, '../../..');
const ctx = vm.createContext({ document: { createElement: () => createCanvas(1, 1) }, console });
vm.runInContext(['01_core.js', '02_art.js', '03_battle.js'].map(f => fs.readFileSync(path.join(root, 'src', f), 'utf8')).join('\n') + '\nglobalThis.source = { getSprite, drawUnitSprite, swingPose, fallDraw };', ctx);
const source = ctx.source;
const matrix = g => { const m = g.getTransform(); return [m.a, m.b, m.c, m.d, m.e, m.f]; };
const fixtures = { poses: [], bodies: [], falls: [] };
for (const kind of [1, 2, 3]) for (const bump of [1, .9, .75, .72, .6, .5, .45, .25, .01, 0]) fixtures.poses.push({ kind, bump, result: source.swingPose(kind, bump) });
for (const [troop, mounted] of [['n3', false], ['n2s', false], ['n2a', false], ['n3c', true]]) {
  const sp = source.getSprite(troop, 0, 'player');
  for (const direction of [-1, 1]) for (const speed of [0, 12, 36, 90, 150]) for (const bump of [0, .9, .5, .1]) {
    const time = 1.75, phase = .73, facing = direction === 1 ? .3 : Math.PI + .3;
    vm.runInContext(`B = { t: ${time} };`, ctx);
    const g = createCanvas(640, 480).getContext('2d'), calls = [];
    g.drawImage = (_, x, y) => calls.push({ transform: matrix(g), offset: [x, y], alpha: g.globalAlpha });
    let ox = 0, oy = speed > 12 ? Math.sin(time * (mounted ? 15 : 11) + phase) * (mounted ? 2 : 1.3) : 0;
    if (bump > 0) { const b = Math.sin((1 - bump) * Math.PI) * 7; ox = Math.cos(facing) * b; oy += Math.sin(facing) * b; }
    g.translate(320 + ox, 240 + oy);
    source.drawUnitSprite(g, { ph: phase, dir: direction, bump, flash: 0 }, sp, speed);
    fixtures.bodies.push({ troop, mounted, direction, speed, bump, time, phase, facing, at: [320, 240], anchor: [sp.ax, sp.ay], pivot: sp.piv, kind: sp.wk, calls });
  }
}
for (const elapsed of [0, .03, .085, .17, .255, .339, .34, .5]) for (const rotation of [-1.7, 1.4]) {
  const g = createCanvas(640, 480).getContext('2d'), calls = [];
  g.drawImage = (_, x, y) => calls.push({ transform: matrix(g), offset: [x, y], alpha: g.globalAlpha });
  ctx.testGround = g;
  vm.runInContext(`B = {t:${elapsed}, gg:testGround, falls:[{cv:null,x:320,y:240,ax:76,ay:158,rot:${rotation},k:.31,alpha:.9,t0:0}]};`, ctx);
  source.fallDraw(g);
  fixtures.falls.push({ elapsed, rotation, at: [320, 240], anchor: [76, 158], call: calls[0] });
}
const out = path.join(root, 'godot/battle/tests/fixtures/unit_motion.json');
fs.writeFileSync(out, JSON.stringify(fixtures, null, 2) + '\n');
console.log(`Original Canvas fixtures: ${fixtures.poses.length} poses, ${fixtures.bodies.length} body/weapon transforms, ${fixtures.falls.length} falls`);
