// One-time bridge while src/01b_gear.js remains the item catalog authority.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '../../..');
const source = fs.readFileSync(path.join(root, 'src/01b_gear.js'), 'utf8');
const boundary = source.indexOf('/* ---------- герой и его слоты ---------- */');
if (boundary < 0) throw new Error('Gear catalog boundary not found');
const gear = vm.runInNewContext(source.slice(0, boundary) + '\nJSON.stringify(EQ)', {});
const items = JSON.parse(gear);
const core = fs.readFileSync(path.join(root, 'src/01_core.js'), 'utf8');
const shieldArrowSource = core.match(/^function shieldArrow\([^\n]+/m);
if (!shieldArrowSource) throw new Error('Browser shield arrow rule not found');
const shieldArrow = vm.runInNewContext(shieldArrowSource[0] + '\nshieldArrow', {});
for (const item of Object.values(items)) {
  if (item.slot === 'shield') item.projectile_block_bonus = shieldArrow(item.look);
}
const expected = JSON.stringify(items, null, 2) + '\n';
const output = path.join(root, 'godot/content/gameplay/equipment/items.json');
if (process.argv.includes('--check')) {
  if (fs.readFileSync(output, 'utf8').replace(/\r\n/g, '\n') !== expected) throw new Error('Godot item catalog differs from browser source');
  console.log(`Catalog matches: ${Object.keys(items).length} items`);
} else {
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, expected);
  console.log(`Exported ${Object.keys(items).length} items`);
}
