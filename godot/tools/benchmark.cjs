const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const {hashSources,readBuild} = require('./build_identity.cjs');
const root = path.resolve(__dirname, '..');
const exe = process.argv[2];
if (!exe) throw new Error('Usage: node godot/tools/benchmark.cjs <exported-release.exe> [--n=1000 --ticks=3600 --scenario=contact --repeat=5]');
const executionContext = process.argv.find(x=>x.startsWith('--execution-context='))?.split('=')[1] || 'unspecified';
if (!['host','sandbox','unspecified'].includes(executionContext)) throw new Error('Invalid execution context');
const build = readBuild(path.resolve(exe), hashSources(root), process.argv.includes('--allow-stale-build'));
const options = process.argv.slice(3).filter(x=>!x.startsWith('--repeat=') && !x.startsWith('--execution-context=') && x!=='--allow-stale-build');
const repeat = Number(process.argv.find(x=>x.startsWith('--repeat='))?.slice(9) || 5);
if (!Number.isInteger(repeat) || repeat<1) throw new Error('Invalid repeat count');
const dir = fs.mkdtempSync(path.resolve(root,'../dist/godot/benchmark-'));
const userData = fs.mkdtempSync(path.join(os.tmpdir(),'iron-benchmark-'));
const reports=[];
for(let i=0;i<repeat;i++){
  const file=path.join(dir,`run-${i+1}.json`);
  const r=cp.spawnSync(path.resolve(exe),['--headless','--','--cpu-benchmark',...options,`--out=${file}`],{encoding:'utf8',timeout:900000,env:{...process.env,APPDATA:userData}});
  fs.writeFileSync(path.join(dir,`run-${i+1}.log`),`${r.stdout}\n${r.stderr}`);
  if(r.error||r.status!==0||/SCRIPT ERROR|Parse Error|Assertion failed|^ERROR:/m.test(`${r.stdout}\n${r.stderr}`)||!fs.existsSync(file)) throw new Error(`Benchmark failed: ${r.error?.message||r.stderr}`);
  const report=JSON.parse(fs.readFileSync(file,'utf8'));
  if(report.debug || report.ordinary_initial.some(n=>n!==report.requested_per_side) || report.weight!==1) throw new Error('Invalid release/population baseline');
  reports.push(report);
  console.log(`${report.scenario} ${report.requested_per_side}×${report.requested_per_side}: tick p95 ${report.simulation.p95_ms} ms; snapshot p95 ${report.snapshot.p95_ms} ms`);
}
fs.writeFileSync(path.join(dir,'report.json'),JSON.stringify({revision:build.source.revision,dirty:build.source.dirty,
  build,execution_context:executionContext,measuredAt:new Date().toISOString(),reports},null,2));
console.log(`Report: ${dir}`);
