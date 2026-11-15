const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createCanvas, GlobalFonts } = require('@napi-rs/canvas');
const root = path.resolve(__dirname, '../../..');
const out = process.argv[2]; if (!out) throw Error('Usage: node render_motion_reference.cjs <output-directory>');
fs.mkdirSync(out, { recursive: true });
GlobalFonts.registerFromPath(path.join(root, 'godot/apps/godot/visuals/assets/fonts/AlegreyaSans-Bold.ttf'), 'Alegreya Sans');
const ctx = vm.createContext({ document: { createElement: () => createCanvas(1, 1) }, console });
vm.runInContext(['01_core.js', '02_art.js', '03_battle.js'].map(f => fs.readFileSync(path.join(root, 'src', f), 'utf8')).join('\n') + '\nglobalThis.source = { getSprite, drawUnitSprite };', ctx);
const cases = [
 ['n3', 'Покой', 120, 180, 0, .3, 'idle'], ['n3', 'Шаг', 360, 180, 60, .3, 'idle'],
 ['n3', 'Рубящий удар', 600, 180, 0, .3, 'melee'], ['n2s', 'Укол копьём', 840, 180, 0, .3, 'melee'],
 ['n2a', 'Выстрел', 120, 390, 0, .3, 'bow'], ['n3c', 'Галоп влево', 360, 390, 135, Math.PI + .3, 'idle'],
 ['n3c', 'Конный удар', 600, 390, 60, .3, 'melee'], ['n3', 'Попадание', 840, 390, 0, .3, 'flash']
];
for (let frame = 0; frame < 60; frame++) {
 const t = frame / 30, canvas = createCanvas(960, 440), g = canvas.getContext('2d');
 vm.runInContext(`B = {t:${t}}`, ctx);
 g.fillStyle = '#181510'; g.fillRect(0, 0, 960, 440);
 g.fillStyle = '#d1a84c'; g.font = '700 18px "Alegreya Sans"'; g.fillText('JS · оригинальные drawUnitSprite и swingPose', 18, 27);
 for (const [troop, label, x, y, speed, facing, mode] of cases) {
  const sp = ctx.source.getSprite(troop, 0, 'player'), phase = .73;
  const bump = mode === 'melee' ? Math.max(0, 1 - t % .55 * 4.2) : mode === 'bow' ? Math.max(0, .5 - t % .55 * 4.2) : 0;
  let ox = 0, oy = speed > 12 ? Math.sin(t * (sp.mnt ? 15 : 11) + phase) * (sp.mnt ? 2 : 1.3) : 0;
  if (bump > 0) { const b = Math.sin((1 - bump) * Math.PI) * 7; ox = Math.cos(facing) * b; oy += Math.sin(facing) * b; }
  g.save(); g.translate(x + ox, y + oy);
  ctx.source.drawUnitSprite(g, { ph: phase, dir: Math.cos(facing) < 0 ? -1 : 1, bump, flash: mode === 'flash' && t % 1.2 < .13 ? .1 : 0 }, sp, speed);
  g.restore(); g.fillStyle = '#eadfc2'; g.font = '700 16px "Alegreya Sans"'; g.textAlign = 'center'; g.fillText(label, x, y + 29); g.textAlign = 'left';
 }
 fs.writeFileSync(path.join(out, `frame_${String(frame).padStart(3, '0')}.png`), canvas.toBuffer('image/png'));
}
console.log('Captured 60 original Canvas animation frames');
