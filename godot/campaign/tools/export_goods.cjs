const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '../../..');
const source = fs.readFileSync(path.join(root, 'src/05d_trade.js'), 'utf8');
const start = source.indexOf('const GOODS =');
const end = source.indexOf('const GEAR_APPEAR');
if (start < 0 || end <= start) throw new Error('Goods catalog boundaries not found');
const goods = vm.runInNewContext(source.slice(start, end) + '\nGOODS', {});
const expected = JSON.stringify(goods, null, 2) + '\n';
const output = path.join(root, 'godot/campaign/data/goods.json');
if (process.argv.includes('--check')) {
  if (fs.readFileSync(output, 'utf8').replace(/\r\n/g, '\n') !== expected) throw new Error('Godot goods catalog differs from browser source');
  console.log(`Catalog matches: ${Object.keys(goods).length} trade goods`);
} else {
  fs.writeFileSync(output, expected);
}
