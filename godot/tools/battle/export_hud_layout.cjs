const {chromium}=require('playwright');
const {pathToFileURL}=require('url');const path=require('path'),fs=require('fs');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 const page=await browser.newPage({viewport:{width:1366,height:768}});
 await page.goto(pathToFileURL(path.resolve(__dirname,'../../..','index.html')).href);await page.waitForTimeout(1000);await page.evaluate(()=>document.fonts.ready);
 await page.evaluate(()=>{enterBattle({pl:[{type:'n1',n:18},{type:'n2a',n:5},{type:'n3c',n:2}],en:[{type:'e1',n:20},{type:'e2a',n:4},{type:'e3c',n:2}],pfac:'player',efac:'emp',biome:'grass',seed:4017,quick:true,title:'Быстрый бой',hero:{name:'Ты',str:3,vit:3,agi:2,int:2,cha:2,perks:[],eq:{head:'head_nasal',body:'body_mail',hands:'hands_leather',legs:'legs_boots',melee:'sword_knight',ranged:'bow_long',shield:'shield_banded'},sel:'melee',hp:1,seed:7}});B.paused=true;updateBattleHud();});
 const results={};for(const [width,height]of [[1366,768],[960,650],[1920,1080],[800,600],[640,480],[480,800]]){
  await page.setViewportSize({width,height});await page.waitForTimeout(100);
  results[`${width}x${height}`]=await page.evaluate(()=>Object.fromEntries(['#bhero','#bhero .nm','#bhero .bgrid','#bhero .bar','#bhero .wsw','#borders','#commandState','#bords','.ord','#bgroups','.grp','#btop','#btimer','#bbtns','#bmini','#bmini canvas','#blog'].map(s=>{const e=document.querySelector(s);if(!e)return[s,null];const r=e.getBoundingClientRect(),c=getComputedStyle(e);return[s,{x:r.x,y:r.y,w:r.width,h:r.height,font:c.font,padding:c.padding,gap:c.gap,border:c.borderWidth}]})));

 }
 fs.writeFileSync(path.join(__dirname,'../tests/fixtures/hud_layout.json'),JSON.stringify(results,null,2));await browser.close();console.log('Captured original browser HUD geometry at six resolutions');
})().catch(e=>{console.error(e);process.exit(1)});
