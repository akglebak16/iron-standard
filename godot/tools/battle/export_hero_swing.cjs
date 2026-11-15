// Ground truth: record the hero arc emitted by the original complete battleDraw function.
const fs=require('fs'),path=require('path'),vm=require('vm');
const {createCanvas}=require('@napi-rs/canvas');
const root=path.resolve(__dirname,'../../..');
const context=vm.createContext({document:{createElement:()=>createCanvas(1,1)},console,
 VIEW:{w:960,h:650,dpr:1},goreDrawUnder(){},goreDrawOver(){},commandDraw(){},voiceDraw(){}});
vm.runInContext(['01_core.js','02_art.js','03_battle.js'].map(f=>fs.readFileSync(path.join(root,'src',f),'utf8')).join('\n')+'\nglobalThis.drawReference=battleDraw;',context);
const samples=[];
for(const mounted of [false,true])for(const reach of [0,14,30])for(const facing of [-1.2,0,2.5])for(const remaining of [.26,.195,.13,.065,.001]) {
 const canvas=createCanvas(960,650),g=canvas.getContext('2d'),arcs=[];
 let assignedStroke='';Object.defineProperty(g,'strokeStyle',{get:()=>assignedStroke,set:value=>{assignedStroke=value;}});
 g.arc=(...circle)=>arcs.push({circle,style:g.strokeStyle,color:g.strokeStyle.match(/[\d.]+/g).map(Number),width:g.lineWidth,cap:g.lineCap});
 const action={position:[320,240],remaining,facing,reach,mounted,dead:false};
 context.sample={W:2600,H:1700,cfg:{demo:true},cam:{x:480,y:325,z:1},shake:0,ground:createCanvas(1,1),
  t:0,units:[],trees:[],falls:[],fx:[],texts:[],arrows:[],hero:{x:320,y:240,swing:remaining,swingA:facing,dead:false,t:{reach,mounted}}};
 vm.runInContext('B=sample;',context);context.drawReference(g);
 if(arcs.length!==1)throw Error('Expected exactly the original hero attack arc');
 samples.push({action,...arcs[0]});
}
fs.writeFileSync(path.join(root,'godot/tests/unit/battle/fixtures/hero_swing.json'),JSON.stringify(samples,null,2)+'\n');
console.log(`Captured ${samples.length} original hero arcs`);
