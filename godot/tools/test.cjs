const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const engine = process.argv[2] || 'godot';
const root = path.resolve(__dirname, '..');
// Tests must never read or overwrite the player's saves/preferences.
const userData = fs.mkdtempSync(path.join(require('os').tmpdir(), 'iron-standard-tests-'));
const env = { ...process.env, APPDATA: userData, XDG_DATA_HOME: userData };
const timeouts = {
  'campaign/tests/world/test_world_wars.gd': 120000,
  // Four 900-tick battles compare indexed and exhaustive targeting/contact loops.
  'battle/tests/rules/test_spatial_full_battle.gd': 60000,
};
const scriptErrors = /SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Assertion failed/i;
function findTests(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory() && entry.name !== '.godot') return findTests(full);
    return entry.isFile() && /^test_.*\.gd$/.test(entry.name) ? [full] : [];
  });
}
// Assets (audio, images) are loaded through the import cache, which a clean checkout does not have yet.
const imported = spawnSync(engine, ['--headless', '--path', root, '--import'], { encoding: 'utf8', env, timeout: 120000 });
if (imported.error || imported.status !== 0 || scriptErrors.test(`${imported.stdout}\n${imported.stderr}`)) {
  process.stderr.write(`${imported.stdout || ''}\n${imported.stderr || ''}`);
  throw new Error(`Godot asset import failed${imported.error ? ` (${imported.error.message})` : ''}`);
}
const filterArg = process.argv.find(a => a.startsWith('--filter='));
const filter = filterArg ? new RegExp(filterArg.slice(9)) : null;
const tests = findTests(root).sort().filter(file => !filter || filter.test(path.relative(root, file).replaceAll('\\', '/')));
if (!tests.length) throw new Error('No Godot tests found');
for (const test of tests) {
  const relative = path.relative(root, test).replaceAll('\\', '/');
  const result = spawnSync(engine, ['--headless', '--path', root, '--script', `res://${relative}`], { encoding: 'utf8', env, timeout: timeouts[relative] || 30000 });
  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  if (result.error || result.status !== 0 || scriptErrors.test(output) || !/tests passed/i.test(output)) {
    process.stderr.write(output);
    throw new Error(`Godot test failed: ${relative}${result.error ? ` (${result.error.message})` : ''}`);
  }
  console.log(`${relative} OK`);
}
console.log(`${tests.length} Godot test files passed${filter ? ` (selected by ${filter}; not the full suite)` : ''}. Isolated data: ${userData}`);
