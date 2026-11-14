// One-time bridge while src/01c_perks.js remains the reference for perk data.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '../../..');
const source = fs.readFileSync(path.join(root, 'src/01c_perks.js'), 'utf8');
const exported = vm.runInNewContext(source + '\nJSON.stringify({perks: PERKS, zero: FX_ZERO})', {});
const data = JSON.parse(exported);
const expected = JSON.stringify(data, null, 2) + '\n';
const output = path.join(root, 'godot/characters/data/perks.json');
if (process.argv.includes('--check')) {
  if (fs.readFileSync(output, 'utf8').replace(/\r\n/g, '\n') !== expected) throw new Error('Godot perk catalog differs from browser source');
  console.log(`Catalog matches: ${data.perks.length} perks`);
} else {
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, expected);
  console.log(`Exported ${data.perks.length} perks`);
}
