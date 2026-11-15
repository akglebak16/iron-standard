const fs = require('fs'), path = require('path'), cp = require('child_process'), crypto = require('crypto');
const root = path.resolve(__dirname,'..'), workspace = path.dirname(root);
const tools = path.join(workspace,'dist/godot/native-tools');
const cpp = path.join(tools,'godot-cpp-10.0.0-stable');
const compiler = path.join(tools,'llvm-mingw-20260908-ucrt-x86_64/bin/clang++.exe');
const python = path.join(tools,'python-3.13.17/python.exe');
const build = path.join(workspace,'dist/godot/native-build');
const objects = path.join(build,'objects'); fs.mkdirSync(objects,{recursive:true});
const flags = ['-std=c++17','-O2','-ffp-contract=off','-fno-exceptions','-DNDEBUG','-DGDEXTENSION','-DTHREADS_ENABLED','-DWINDOWS_ENABLED','-DTYPED_METHOD_BIND','-DNOMINMAX', '-I'+path.join(cpp,'include'),'-I'+path.join(build,'gen/include')];
function files(dir, extension) { return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(path.join(dir,e.name),extension):e.name.endsWith(extension)?[path.join(dir,e.name)]:[]); }
function run(command,args) {return new Promise((resolve,reject)=>{
 const p=cp.spawn(command,args,{cwd:workspace,windowsHide:true}); let output='';
 p.stdout.on('data',d=>output+=d);p.stderr.on('data',d=>output+=d);p.on('error',reject);
 p.on('close',code=>code===0?resolve(output):reject(new Error(output)));
});}
async function main() {
 if(process.platform!=='win32') throw new Error('Native build currently targets Windows x86_64');
 for(const required of [compiler,python,path.join(cpp,'gdextension/extension_api-4-7.json')]) {
  if(!fs.existsSync(required)) throw new Error('Missing native toolchain. Run: pwsh -File godot/tools/native_bootstrap.ps1');
 }
 const marker=path.join(build,'binding-version.txt');
 const generatorHash=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'tools/native_bindings.py'))).digest('hex');
 if(!fs.existsSync(marker)||fs.readFileSync(marker,'utf8')!==generatorHash){
  console.log((await run(python,[path.join(root,'tools/native_bindings.py'),cpp,build])).trim()); fs.writeFileSync(marker,generatorHash);
 }
 const inputs=[...files(path.join(cpp,'src'),'.cpp'),...files(path.join(build,'gen/src'),'.cpp'),path.join(root,'adapters/godot/native/contact_adapter.cpp')];
 const outputPaths=[]; const queue=[];
 for(const source of inputs){
  const id=crypto.createHash('sha256').update(source).digest('hex').slice(0,16);const out=path.join(objects,id+'.o');outputPaths.push(out);
  const deps=source.includes('contact_adapter')?[source,path.join(root,'runtime/simulation/native/contact_solver.hpp')]:[source];
  const fingerprint=crypto.createHash('sha256').update(generatorHash+flags.join('\0')+deps.map(f=>fs.readFileSync(f)).join('\0')).digest('hex');
  if(!fs.existsSync(out)||!fs.existsSync(out+'.hash')||fs.readFileSync(out+'.hash','utf8')!==fingerprint)queue.push({source,out,fingerprint});
 }
 console.log(`Native build: ${queue.length}/${inputs.length} translation units`);
 let cursor=0,finished=0;
 async function worker(){while(cursor<queue.length){const job=queue[cursor++];await run(compiler,[...flags,'-c',job.source,'-o',job.out]);fs.writeFileSync(job.out+'.hash',job.fingerprint);finished++;if(finished%10===0)console.log(`Compiled ${finished}/${queue.length}`);}}
 const workers=await Promise.allSettled(Array.from({length:4},worker));
 const failures=workers.filter(r=>r.status==='rejected');
 if(failures.length) throw failures[0].reason;
 const outdir=path.join(root,'adapters/godot/native/bin');fs.mkdirSync(outdir,{recursive:true});
 const dll=path.join(outdir,'iron_contacts.windows.x86_64.dll');
 const linkHash=crypto.createHash('sha256').update(outputPaths.map(p=>fs.readFileSync(p+'.hash','utf8')).join('\0')).digest('hex');
 if(!fs.existsSync(dll)||!fs.existsSync(dll+'.hash')||fs.readFileSync(dll+'.hash','utf8')!==linkHash) {
  await run(compiler,['-shared','-static',...outputPaths,'-o',dll]);
  fs.writeFileSync(dll+'.hash',linkHash);
 }
 console.log(`Native contact adapter built: ${dll}`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
