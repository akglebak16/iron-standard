// One-time bridge while the browser prototype is the reference for troop data.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(root, 'src/01_core.js'), 'utf8');
const end = source.indexOf('const GEAR =');
if (end < 0) throw new Error('Troop catalog boundary not found');
const troops = vm.runInNewContext(source.slice(0, end) + '\nJSON.stringify(TROOPS)', {});
const expected = JSON.stringify(JSON.parse(troops), null, 2) + '\n';
const output = path.join(root, 'godot/data/troops.json');
if (process.argv.includes('--check')) {
  if (fs.readFileSync(output, 'utf8').replace(/\r\n/g, '\n') !== expected) throw new Error('Godot troop catalog differs from browser source');
  console.log(`Catalog matches: ${Object.keys(JSON.parse(troops)).length} troop types`);
} else {
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, expected);
  console.log(`Exported ${Object.keys(JSON.parse(troops)).length} troop types`);
}
