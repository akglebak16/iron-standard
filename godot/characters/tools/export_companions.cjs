const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '../../..');
const source = fs.readFileSync(path.join(root, 'src/05e_comps.js'), 'utf8');
const boundary = source.indexOf('const COMP =');
if (boundary < 0) throw new Error('Companion catalog boundary not found');
const definitions = vm.runInNewContext(source.slice(0, boundary) + '\nCOMPS', {});
const expected = JSON.stringify(definitions, null, 2) + '\n';
const output = path.join(root, 'godot/characters/data/companions.json');
if (process.argv.includes('--check')) {
  if (fs.readFileSync(output, 'utf8').replace(/\r\n/g, '\n') !== expected) throw new Error('Godot companion catalog differs from browser source');
  console.log(`Catalog matches: ${definitions.length} companions`);
} else {
  fs.writeFileSync(output, expected);
  console.log(`Exported ${definitions.length} companions`);
}
