const fs = require('fs'), path = require('path'), cp = require('child_process');
const {hashSources,readBuild,sourceIdentity} = require('./build_identity.cjs');
const root = path.resolve(__dirname,'..');
function runGame(exe,args,env,timeoutMs=180000) {
  return new Promise(resolve=>{
    const child=cp.spawn(exe,args,{env,windowsHide:true});
    let stdout='',stderr='',error,stopping=false;
    function stop(reason) {
      if(stopping) return;
      stopping=true; error=new Error(reason);
      if(child.pid && child.exitCode===null) {
        if(process.platform==='win32') cp.spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
        else child.kill('SIGKILL');
      }
    }
    const timer=setTimeout(()=>stop('Diagnostic timed out'),timeoutMs);
    function inspect() { if(/SCRIPT ERROR|Parse Error|^ERROR:/m.test(stdout+'\n'+stderr)) stop('Diagnostic script error'); }
    child.stdout.on('data',data=>{stdout+=data;inspect();});
    child.stderr.on('data',data=>{stderr+=data;inspect();});
    child.on('error',value=>{error=value;});
    child.on('close',status=>{clearTimeout(timer);resolve({status,stdout,stderr,error});});
  });
}
async function main() {
const [engine,release] = process.argv.slice(2,4);
if(!engine || !release) throw Error('Usage: node godot/tools/compare_view.cjs <Godot-console.exe> <release.exe> [--n=300 --frames=240 --repeat=2 --audio=on --mode=battle|campaign --headless]');
const option = (key,fallback)=>process.argv.find(x=>x.startsWith(`--${key}=`))?.split('=')[1] ?? fallback;
const n = Number(option('n','300')), frames = Number(option('frames','240')), repeat = Number(option('repeat','2'));
const audio = option('audio','on'), mode = option('mode','both');
const seconds=Number(option('measure-seconds','0')), camera=option('camera','hero'), backendChoice=option('backend','both');
const requireTarget=process.argv.includes('--require-target');
if(!Number.isFinite(seconds)||seconds<0||!['hero','wide','near'].includes(camera)||!['both','release','toolchain'].includes(backendChoice)) throw Error('Invalid duration/camera/backend');
if(requireTarget&&(seconds<60||repeat<5||audio!=='on'||mode!=='battle'||backendChoice!=='release'||process.argv.includes('--headless'))) throw Error('Target gate requires release, battle, audio on, at least 60 seconds × five repetitions, and a real window');
if(!Number.isInteger(n)||n<1||!Number.isInteger(frames)||frames<=61||!Number.isInteger(repeat)||repeat<1||!['on','off'].includes(audio)||!['both','battle','campaign'].includes(mode)) throw Error('Invalid comparison parameters');
const build = readBuild(path.resolve(release),hashSources(root));
const source = sourceIdentity(root);
const dir = fs.mkdtempSync(path.resolve(root,'../dist/godot/view-comparison-'));
const profile = fs.mkdtempSync(path.join(root,'.godot','view-comparison-data-'));
const results = [];
for(const scenario of mode==='both' ? ['battle','campaign'] : [mode]) {
  for(let iteration=0;iteration<repeat;iteration++) {
    for(const backend of backendChoice==='both' ? (iteration%2 ? ['release','toolchain'] : ['toolchain','release']) : [backendChoice]) {
      if(hashSources(root)!==source.source_sha256) throw Error('Sources changed during comparison; stop and rebuild');
      const name = `${scenario}-${iteration+1}-${backend}`, out = path.join(dir,name+'.json');
      const args = [...(backend==='toolchain'?['--path',root]:[]),
        ...(process.argv.includes('--headless')?['--headless']:[]),
        '--resolution','1920x1080','--disable-vsync','--max-fps','0','--',
        '--view-benchmark',`--measure-seconds=${seconds}`,`--camera=${camera}`,`--mode=${scenario}`,`--n=${n}`,`--frames=${frames}`,`--audio=${audio}`,'--seed=4242',`--out=${out}`,
        ...(process.argv.includes('--capture')?[`--capture=${path.join(dir,name+'.png')}`]:[])];
      console.log(`Starting ${name}`);
      const run = await runGame(path.resolve(backend==='toolchain'?engine:release),args,
        {...process.env,APPDATA:profile,XDG_DATA_HOME:profile});
      const log = `${run.stdout || ''}\n${run.stderr || ''}`;
      fs.writeFileSync(path.join(dir,name+'.log'),log);
      if(hashSources(root)!==source.source_sha256) throw Error(`Sources changed during ${name}; its sample is invalid`);
      if(run.error || run.status!==0 || /SCRIPT ERROR|Parse Error|^ERROR:/m.test(log) || !fs.existsSync(out)) throw Error(`Comparison failed: ${name}: ${run.error?.message || log.slice(-4000)}`);
      const report = JSON.parse(fs.readFileSync(out,'utf8'));
      if(report.debug!==(backend==='toolchain') || report.mode!==scenario || (seconds>0 ? report.measurement_seconds<seconds : report.frame.count!==frames-60)) throw Error('Wrong diagnostic entry point or sample count');
      if(scenario==='battle' && (report.ordinary_initial.some(x=>x!==n) || report.native_failures!==0 || (n>=32 && report.native_steps===0))) throw Error('Wrong population or contact backend');
      results.push({backend,iteration:iteration+1,report});
      console.log(`${name}: mean=${report.frame.mean_ms.toFixed(2)} ms p95=${report.frame.p95_ms} ms dropped=${report.dropped_seconds ?? 'n/a'}`);
      fs.writeFileSync(path.join(dir,'report.json'),JSON.stringify({complete:false,source,build,options:{n,frames,repeat,audio,mode,seconds,camera,backendChoice},results},null,2));
    }
  }
}
const failures=[];
for(const [index,{report:r}] of results.entries()) {
  if(r.mode!=='battle')continue;
  if(r.frame.p95_ms>16.67||r.frame.p99_ms>25)failures.push(`run ${index+1}: frame budget exceeded`);
  if(r.dropped_seconds!==0||r.backlog_seconds>4/60||Math.abs(r.simulation_ticks_measured-r.measurement_seconds*60)>4)failures.push(`run ${index+1}: simulation clock lag`);
  if(r.native_movement_failures!==0||r.native_movement_steps<=0)failures.push(`run ${index+1}: native movement unavailable/failed`);
}
fs.writeFileSync(path.join(dir,'report.json'),JSON.stringify({complete:true,source,build,options:{n,frames,repeat,audio,mode,seconds,camera,backendChoice},scope:'selected mixed battle view; not the complete blueprint matrix',target_failures:failures,results},null,2));
if(requireTarget&&failures.length){console.error(failures.join('\n'));process.exitCode=1;}
console.log(`Report: ${dir}`);
}
module.exports={runGame};
if(require.main===module) main().catch(error=>{console.error(error);process.exitCode=1;});
