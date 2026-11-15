const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const engine = process.argv[2] || 'godot';
const root = path.resolve(__dirname, '..');
function findTests(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory() && entry.name !== '.godot') return findTests(full);
    return entry.isFile() && /^test_.*\.gd$/.test(entry.name) ? [full] : [];
  });
}
// Assets (audio, images) are loaded through the import cache, which a clean checkout does not have yet.
const imported = spawnSync(engine, ['--headless', '--path', root, '--import'], { encoding: 'utf8', timeout: 120000 });
if (imported.error || imported.status !== 0) {
  process.stderr.write(`${imported.stdout || ''}\n${imported.stderr || ''}`);
  throw new Error(`Godot asset import failed${imported.error ? ` (${imported.error.message})` : ''}`);
}
const tests = findTests(root).sort();
if (!tests.length) throw new Error('No Godot tests found');
for (const test of tests) {
  const relative = path.relative(root, test).replaceAll('\\', '/');
  // Ten simulated campaign days take about 31 seconds on the Windows debug engine.
  // Keep every assertion and a bounded timeout; other tests retain their 30-second limit.
  const timeout = relative === 'campaign/tests/world/test_world_wars.gd' ? 60000 : 30000;
  const result = spawnSync(engine, ['--headless', '--path', root, '--script', `res://${relative}`], { encoding: 'utf8', timeout });
  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  if (result.error || result.status !== 0 || /SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Assertion failed/i.test(output) || !/tests passed/i.test(output)) {
    process.stderr.write(output);
    throw new Error(`Godot test failed: ${relative}${result.error ? ` (${result.error.message})` : ''}`);
  }
  console.log(`${relative} OK`);
}
