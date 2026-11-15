const fs = require('fs');
const path = require('path');
const os = require('os');
const cp = require('child_process');
const engine = process.argv[2] || 'godot';
const root = path.resolve(__dirname, '..');
const out = path.resolve(root, '../dist/godot/migration-release');
fs.mkdirSync(out, { recursive: true });
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'iron-release-'));
const env = {...process.env, APPDATA: profile, XDG_DATA_HOME: profile};
function run(exe, args, name, timeout = 120000) {
  const result = cp.spawnSync(exe, args, {encoding:'utf8', timeout, env});
  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  fs.writeFileSync(path.join(out, name + '.log'), output);
  if (result.error || result.status !== 0 || /SCRIPT ERROR|Parse Error|Compile Error|Failed to load|Assertion failed|^ERROR:/m.test(output)) throw new Error(`${name} failed: ${result.error?.message || output.slice(-5000)}`);
  return output;
}
const exe = path.join(out, 'IronStandard.exe');
run(engine, ['--headless','--path',root,'--export-release','Windows',exe], 'export');
const smoke = run(exe, ['--headless','--','--release-smoke'], 'smoke');
if (!smoke.includes('Release smoke passed; debug=false')) throw new Error(`Release smoke did not complete in release mode: ${smoke}`);
console.log(`Windows release and smoke passed: ${exe}`);
