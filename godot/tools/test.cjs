const fs = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const os = require('os');
const { schedule, jobCount } = require('./test_schedule.cjs');
const totalStarted = Date.now();
const phases = {};

const engine = process.argv[2] || 'godot';
const root = path.resolve(__dirname, '..');
// Tests must never read or overwrite the player's saves/preferences.
fs.mkdirSync(path.join(root, '.godot'), { recursive: true });
const userData = fs.mkdtempSync(path.join(root, '.godot', 'test-userdata-'));
const env = { ...process.env, APPDATA: userData, XDG_DATA_HOME: userData };
const timeouts = {
  'tests/integration/test_native_movement.gd': 120000,
  'tests/integration/test_native_contacts.gd': 120000,
  'tests/unit/campaign/world/test_world_wars.gd': 120000,
  // Four 900-tick battles compare indexed and exhaustive loops. Parallel Windows CI exceeded 60 s.
  'tests/unit/battle/rules/test_spatial_full_battle.gd': 120000,
  // Multiple world constructions, continuation and recovery from a torn generation.
  'tests/integration/test_save_v2.gd': 120000,
  // Parallel jobs share the CPU: the slowest campaign tests get room.
  'tests/unit/campaign/world/test_party_ai.gd': 90000,
  'tests/unit/campaign/world/test_world_save.gd': 90000,
};
// Бюджет полного прогона Godot-тестов (правило в docs/architecture/DEVELOPMENT.md). Превышение — предупреждение CI.
const BUDGET_MS = 180000;
// При `--changed=<base>` берём только тесты, до которых доходят ссылки от изменённых файлов (tools/test_selection.cjs).
const { selectTests, changedFiles } = require('./test_selection.cjs');
function selectChanged(base) {
  const changed = changedFiles(root, base);
  return changed === null ? {full: true, reason: 'не удалось получить изменения'} : selectTests(root, changed);
}
const scriptErrors = /SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Assertion failed/i;
function findTests(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory() && entry.name !== '.godot') return findTests(full);
    return entry.isFile() && /^test_.*\.gd$/.test(entry.name) ? [full] : [];
  });
}
function run(args, timeout, runEnv = env) {
  return new Promise(resolve => {
    const child = spawn(engine, args, {env: runEnv, windowsHide:true});
    let stdout = '', stderr = '', error, stopping = false;
    const stop = reason => {
      if (stopping) return;
      stopping = true; error = new Error(reason);
      if (process.platform === 'win32') {
        const killed = spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], {windowsHide:true, stdio:'ignore', timeout:2000});
        // Restricted Windows sessions may deny process-tree enumeration. The direct child handle still works.
        if (killed.error || killed.status !== 0) child.kill('SIGKILL');
      } else child.kill('SIGKILL');
    };
    const timer = setTimeout(() => stop(`Timeout after ${timeout} ms`), timeout);
    child.stdout.on('data', data => { stdout += data; if (scriptErrors.test(stdout)) stop('Script error'); });
    child.stderr.on('data', data => { stderr += data; if (scriptErrors.test(stderr)) stop('Script error'); });
    child.on('error', e => { error = e; });
    child.on('close', status => { clearTimeout(timer); resolve({status, stdout, stderr, error}); });
  });
}

async function main() {
const filterArg = process.argv.find(a => a.startsWith('--filter='));
const filter = filterArg ? new RegExp(filterArg.slice(9)) : null;
const changedArg = process.argv.find(a => a.startsWith('--changed='));
const selection = changedArg ? selectChanged(changedArg.slice(10)) : null;
if (selection) console.log(selection.full ? `Полный набор: ${selection.reason}` : `Выбрано по зависимостям: ${selection.tests.size} тестов`);
const tests = findTests(root).sort().filter(file => {
  const relative = path.relative(root, file).replaceAll('\\', '/');
  return (!filter || filter.test(relative)) && (!selection || selection.full || selection.tests.has(relative));
});
const timings = [];
if (!tests.length) throw new Error('No Godot tests found');
// Tests run in parallel, each Godot process with its own user data so saves and preferences never collide.
const jobsArg = process.argv.find(a => a.startsWith('--jobs='));
const jobs = jobCount(jobsArg ? jobsArg.slice(7) : process.env.GODOT_TEST_JOBS, os.availableParallelism?.() || os.cpus().length, tests.length);
const timingFile = path.join(root, '.godot', 'test-timings.json');
let history = {};
try { const cached = JSON.parse(fs.readFileSync(timingFile, 'utf8')); if (cached && typeof cached === 'object' && !Array.isArray(cached)) history = cached; } catch { /* First run or damaged timing cache: use estimates. */ }
const relative = file => path.relative(root, file).replaceAll('\\', '/');
const ordered = schedule(tests.map(relative), history, timeouts).map(file => path.join(root, file));
tests.splice(0, tests.length, ...ordered);
phases.selection_ms = Date.now() - totalStarted;
const nativeStarted = Date.now();
const native = spawnSync(process.execPath,[path.join(root,'tools/native_build.cjs')],{encoding:'utf8',windowsHide:true});
if(native.error || native.status!==0) throw new Error(`Native build failed: ${native.stderr || native.error}`);
phases.native_ms = Date.now() - nativeStarted;
const importStarted = Date.now();
// Assets (audio, images) are loaded through the import cache, which a clean checkout does not have yet.
// A clean checkout imports every atlas (850+ images); on the CI runner this takes close to two minutes.
const imported = await run(['--headless', '--path', root, '--import'], 300000);
if (imported.error || imported.status !== 0 || scriptErrors.test(`${imported.stdout}\n${imported.stderr}`)) {
  process.stderr.write(`${imported.stdout || ''}\n${imported.stderr || ''}`);
  throw new Error(`Godot asset import failed${imported.error ? ` (${imported.error.message})` : ''}`);
}
phases.import_ms = Date.now() - importStarted;
const started = Date.now();
console.log(`Preparation: native ${(phases.native_ms / 1000).toFixed(1)} s; import ${(phases.import_ms / 1000).toFixed(1)} s`);
console.log(`Running ${tests.length} Godot test files in ${jobs} parallel jobs`);
const failures = [];
let next = 0;
async function worker() {
  while (next < tests.length) {
    const test = tests[next++];
    const relative = path.relative(root, test).replaceAll('\\', '/');
    const own = fs.mkdtempSync(path.join(userData, 'job-'));
    const testStart = Date.now();
    const result = await run(['--headless', '--path', root, '--script', `res://${relative}`], timeouts[relative] || 30000, { ...env, APPDATA: own, XDG_DATA_HOME: own });
    const output = `${result.stdout || ''}\n${result.stderr || ''}`;
    if (result.error || result.status !== 0 || scriptErrors.test(output) || !/tests passed/i.test(output)) {
      process.stderr.write(`----- ${relative} -----\n${output}\n`);
      failures.push(`${relative}${result.error ? ` (${result.error.message})` : ''}`);
      continue;
    }
    timings.push([relative, Date.now() - testStart]);
    console.log(`${relative} OK (${((Date.now() - testStart) / 1000).toFixed(1)} s)`);
  }
}
await Promise.all(Array.from({ length: jobs }, worker));
const elapsed = Date.now() - started;
phases.tests_ms = elapsed;
phases.total_ms = Date.now() - totalStarted;
const currentNames = new Set(findTests(root).map(relative));
const saved = Object.fromEntries(Object.entries(history).filter(([name, ms]) => currentNames.has(name) && Number.isFinite(ms) && ms > 0));
for (const [name, ms] of timings) saved[name] = ms;
fs.writeFileSync(timingFile, JSON.stringify(saved, null, 2));
const reportFile = path.join(root, '.godot', 'test-last-run.json');
fs.writeFileSync(reportFile, JSON.stringify({jobs, selected: tests.length, passed: timings.length, failures, phases, timings}, null, 2));
console.log(`Total ${(phases.total_ms / 1000).toFixed(1)} s; tests ${(elapsed / 1000).toFixed(1)} s; report: ${reportFile}`);
if (failures.length) throw new Error(`Godot tests failed: ${failures.join(', ')}`);
console.log(`Slowest: ${timings.sort((a, b) => b[1] - a[1]).slice(0, 5).map(([name, ms]) => `${name} ${(ms / 1000).toFixed(1)} s`).join('; ')}`);
if (elapsed > BUDGET_MS) console.log(`::warning::Godot-тесты шли ${(elapsed / 1000).toFixed(0)} с при бюджете ${BUDGET_MS / 1000} с: ускорь самые медленные или раздели их`);
console.log(`${tests.length} Godot test files passed${filter ? ` (selected by ${filter}; not the full suite)` : ''}. Isolated data: ${userData}`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
