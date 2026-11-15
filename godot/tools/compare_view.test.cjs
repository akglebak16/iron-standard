const assert=require('assert/strict');
const {runGame}=require('./compare_view.cjs');
(async()=>{
  const ok=await runGame(process.execPath,['-e',"console.log('ok')"],process.env,5000);
  assert.equal(ok.status,0); assert.equal(ok.error,undefined);
  const failure=await runGame(process.execPath,['-e',"console.error('ERROR: fixture');setInterval(()=>{},1000)"],process.env,5000);
  assert.match(failure.error.message,/script error/);
  const timedOut=await runGame(process.execPath,['-e','setInterval(()=>{},1000)'],process.env,200);
  assert.match(timedOut.error.message,/timed out/);
  console.log('Visual comparison process cleanup tests passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
