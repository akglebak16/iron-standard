const fs = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');

const engine = process.argv[2] || 'godot';
const root = path.resolve(__dirname, '..');
// Tests must never read or overwrite the player's saves/preferences.
fs.mkdirSync(path.join(root, '.godot'), { recursive: true });
const userData = fs.mkdtempSync(path.join(root, '.godot', 'test-userdata-'));
const env = { ...process.env, APPDATA: userData, XDG_DATA_HOME: userData };
const timeouts = {
  'campaign/tests/world/test_world_wars.gd': 120000,
  // Four 900-tick battles compare indexed and exhaustive targeting/contact loops.
  'battle/tests/rules/test_spatial_full_battle.gd': 60000,
  // Multiple world constructions, continuation and recovery from a torn generation.
  'tests/integration/test_save_v2.gd': 120000,
};
const scriptErrors = /SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Assertion failed/i;
function findTests(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory() && entry.name !== '.godot') return findTests(full);
    return entry.isFile() && /^test_.*\.gd$/.test(entry.name) ? [full] : [];
  });
}
function run(args, timeout) {
  return new Promise(resolve => {
    const child = spawn(engine, args, {env, windowsHide:true});
    let stdout = '', stderr = '', error, stopping = false;
    const stop = reason => {
      if (stopping) return;
      stopping = true; error = new Error(reason);
      if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], {windowsHide:true, stdio:'ignore'});
      else child.kill('SIGKILL');
    };
    const timer = setTimeout(() => stop(`Timeout after ${timeout} ms`), timeout);
    child.stdout.on('data', data => { stdout += data; if (scriptErrors.test(stdout)) stop('Script error'); });
    child.stderr.on('data', data => { stderr += data; if (scriptErrors.test(stderr)) stop('Script error'); });
    child.on('error', e => { error = e; });
    child.on('close', status => { clearTimeout(timer); resolve({status, stdout, stderr, error}); });
  });
}

async function main() {
// Assets (audio, images) are loaded through the import cache, which a clean checkout does not have yet.
const imported = await run(['--headless', '--path', root, '--import'], 120000);
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
  const result = await run(['--headless', '--path', root, '--script', `res://${relative}`], timeouts[relative] || 30000);
  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  if (result.error || result.status !== 0 || scriptErrors.test(output) || !/tests passed/i.test(output)) {
    process.stderr.write(output);
    throw new Error(`Godot test failed: ${relative}${result.error ? ` (${result.error.message})` : ''}`);
  }
  console.log(`${relative} OK`);
}
console.log(`${tests.length} Godot test files passed${filter ? ` (selected by ${filter}; not the full suite)` : ''}. Isolated data: ${userData}`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
