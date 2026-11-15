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
  'tests/integration/test_native_contacts.gd': 120000,
  'tests/unit/campaign/world/test_world_wars.gd': 120000,
  // Four 900-tick battles compare indexed and exhaustive targeting/contact loops.
  'tests/unit/battle/rules/test_spatial_full_battle.gd': 60000,
  // Multiple world constructions, continuation and recovery from a torn generation.
  'tests/integration/test_save_v2.gd': 120000,
};
// Бюджет полного прогона Godot-тестов (правило в docs/architecture/DEVELOPMENT.md). Превышение — предупреждение CI.
const BUDGET_MS = 180000;
// При `--changed=<base>` берём только тесты, до которых доходят ссылки от изменённых файлов (tools/test_selection.cjs).
const { selectTests } = require('./test_selection.cjs');
function selectChanged(base) {
  const diff = spawnSync('git', ['diff', '--name-only', '--relative', base, 'HEAD', '--', '.'], {cwd: root, encoding: 'utf8'});
  if (diff.error || diff.status !== 0) return {full: true, reason: 'не удалось получить diff'};
  return selectTests(root, diff.stdout.split(/\r?\n/).filter(Boolean));
}
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
const native = spawnSync(process.execPath,[path.join(root,'tools/native_build.cjs')],{encoding:'utf8',windowsHide:true});
if(native.error || native.status!==0) throw new Error(`Native build failed: ${native.stderr || native.error}`);
// Assets (audio, images) are loaded through the import cache, which a clean checkout does not have yet.
const imported = await run(['--headless', '--path', root, '--import'], 120000);
if (imported.error || imported.status !== 0 || scriptErrors.test(`${imported.stdout}\n${imported.stderr}`)) {
  process.stderr.write(`${imported.stdout || ''}\n${imported.stderr || ''}`);
  throw new Error(`Godot asset import failed${imported.error ? ` (${imported.error.message})` : ''}`);
}
const filterArg = process.argv.find(a => a.startsWith('--filter='));
const filter = filterArg ? new RegExp(filterArg.slice(9)) : null;
const changedArg = process.argv.find(a => a.startsWith('--changed='));
const selection = changedArg ? selectChanged(changedArg.slice(10)) : null;
if (selection) console.log(selection.full ? `Полный набор: ${selection.reason}` : `Выбрано по зависимостям: ${selection.tests.size} тестов`);
const tests = findTests(root).sort().filter(file => {
  const relative = path.relative(root, file).replaceAll('\\', '/');
  return (!filter || filter.test(relative)) && (!selection || selection.full || selection.tests.has(relative));
});
const started = Date.now();
const timings = [];
if (!tests.length) throw new Error('No Godot tests found');
for (const test of tests) {
  const relative = path.relative(root, test).replaceAll('\\', '/');
  const testStart = Date.now();
  const result = await run(['--headless', '--path', root, '--script', `res://${relative}`], timeouts[relative] || 30000);
  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  if (result.error || result.status !== 0 || scriptErrors.test(output) || !/tests passed/i.test(output)) {
    process.stderr.write(output);
    throw new Error(`Godot test failed: ${relative}${result.error ? ` (${result.error.message})` : ''}`);
  }
  timings.push([relative, Date.now() - testStart]);
  console.log(`${relative} OK (${((Date.now() - testStart) / 1000).toFixed(1)} s)`);
}
const elapsed = Date.now() - started;
console.log(`Slowest: ${timings.sort((a, b) => b[1] - a[1]).slice(0, 5).map(([name, ms]) => `${name} ${(ms / 1000).toFixed(1)} s`).join('; ')}`);
if (elapsed > BUDGET_MS) console.log(`::warning::Godot-тесты шли ${(elapsed / 1000).toFixed(0)} с при бюджете ${BUDGET_MS / 1000} с: ускорь самые медленные или раздели их`);
console.log(`${tests.length} Godot test files passed${filter ? ` (selected by ${filter}; not the full suite)` : ''}. Isolated data: ${userData}`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
