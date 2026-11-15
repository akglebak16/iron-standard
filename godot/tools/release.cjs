const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const {sourceIdentity,hashFile,hashSources} = require('./build_identity.cjs');
const engine = process.argv[2] || 'godot';
const root = path.resolve(__dirname, '..');
const out = path.resolve(root, '../dist/godot/migration-release');
fs.mkdirSync(out, { recursive: true });
const profile = fs.mkdtempSync(path.join(out, 'user-data-'));
const env = {...process.env, APPDATA: profile, XDG_DATA_HOME: profile};
function run(exe, args, name, timeout = 120000) {
  const result = cp.spawnSync(exe, args, {encoding:'utf8', timeout, env});
  const output = `${result.stdout || ''}\n${result.stderr || ''}`;
  fs.writeFileSync(path.join(out, name + '.log'), output);
  if (result.error || result.status !== 0 || /SCRIPT ERROR|Parse Error|Compile Error|Failed to load|Assertion failed|^ERROR:/m.test(output)) throw new Error(`${name} failed: ${result.error?.message || output.slice(-5000)}`);
  return output;
}
const exe = path.join(out, 'IronStandard.exe');
run(process.execPath,[path.join(root,'tools/native_build.cjs')],'native-build',300000);
run(engine, ['--headless','--path',root,'--import'], 'import');
const source = sourceIdentity(root);
run(engine, ['--headless','--path',root,'--export-release','Windows',exe], 'export');
const smoke = run(exe, ['--headless','--','--release-smoke'], 'smoke');
if (!smoke.includes('Release smoke passed; debug=false')) throw new Error(`Release smoke did not complete in release mode: ${smoke}`);
if (hashSources(root) !== source.source_sha256) throw new Error('Sources changed during export; rebuild before measuring');
const dependencies = {};
function inventory(dir) {
  for(const entry of fs.readdirSync(dir,{withFileTypes:true})) {
    if(entry.name.startsWith('user-data-')) continue;
    const full = path.join(dir,entry.name);
    if(entry.isDirectory()) inventory(full);
    else if(entry.name.endsWith('.dll')) dependencies[path.relative(out,full).replaceAll('\\','/')] = hashFile(full);
  }
}
inventory(out);
if(!Object.keys(dependencies).some(p=>p.endsWith('iron_contacts.windows.x86_64.dll'))) throw new Error('Export omitted native library');
fs.cpSync(path.join(root,'adapters/godot/native/licenses'),path.join(out,'native-licenses'),{recursive:true});
fs.writeFileSync(exe + '.build.json',JSON.stringify({source,dependencies,executable_sha256:hashFile(exe),built_at:new Date().toISOString(),smoke_passed:true},null,2));
console.log(`Windows release and smoke passed: ${exe}`);
