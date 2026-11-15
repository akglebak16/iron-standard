/* Original player palettes as sparse, lossless replacements of the existing atlases.
 * The game applies them once with Image.blit_rect_mask, never by guessing material colours.
 * Authoring only: NODE_PATH=... node godot/tools/export_banners.cjs [--banner=N] */
const fs = require('fs'), path = require('path'), vm = require('vm');
const { createCanvas, loadImage } = require('@napi-rs/canvas');
const root = path.resolve(__dirname, '../..');
const out = path.join(root, 'godot/apps/godot/visuals/assets');
const manifest = JSON.parse(fs.readFileSync(path.join(out, 'visuals.json'), 'utf8'));
const context = vm.createContext({document:{createElement:()=>createCanvas(1,1)}, console});
context.sCult = s => s.cult || s.fac;
vm.runInContext(['01_core.js','02_art.js','05b_worldart.js'].map(f=>fs.readFileSync(path.join(root,'src',f),'utf8')).join('\n') + '\nglobalThis.art={BANNERS,FACTIONS,TROOPS,hashStr,buildSprite,palOf,crestCanvas,settleSprite,makeVariant,mulberry,drawTorso,drawHead,drawHelm,drawShield,drawWeapon,drawBase,drawHorse};',context);
const a=context.art, baseCache=new Map();
const selected=process.argv.find(arg=>arg.startsWith('--banner='));
const parts=['body','wpn','portrait','headless','head','corpse','corpse_headless'];
async function base(name) {
 if(!baseCache.has(name)) {
  const image=await loadImage(path.join(out,name+'.png'));
  const canvas=createCanvas(image.width,image.height),g=canvas.getContext('2d');g.drawImage(image,0,0);
  baseCache.set(name,{width:image.width,height:image.height,data:g.getImageData(0,0,image.width,image.height).data});
 }
 return baseCache.get(name);
}
function delta(original, entries, name) {
 const canvas=createCanvas(original.width,original.height),g=canvas.getContext('2d');
 const result=g.createImageData(original.width,original.height),dst=result.data,src=original.data;
 for(const {image,rect} of entries) {
  const cg=image.getContext('2d'),pixels=cg.getImageData(0,0,image.width,image.height).data;
  const [left,top,width,height]=rect;
  for(let y=0;y<height;y++)for(let x=0;x<width;x++) {
   const i=(y*width+x)*4,j=((y+top)*original.width+left+x)*4;
   if(!pixels[i+3])continue;
   if(pixels[i]===src[j]&&pixels[i+1]===src[j+1]&&pixels[i+2]===src[j+2]&&pixels[i+3]===src[j+3])continue;
   dst[j]=pixels[i];dst[j+1]=pixels[i+1];dst[j+2]=pixels[i+2];dst[j+3]=pixels[i+3];
  }
 }
 g.putImageData(result,0,0);fs.writeFileSync(path.join(out,name+'.png'),canvas.toBuffer('image/png'));
}
function layer(sp,part) {
 if(part==='portrait')return sp.cv;
 if(part==='headless')return sp.mk(false,{part:'body',nohead:true});
 if(part==='head')return sp.mk(false,{only:'head'});
 if(part==='corpse')return sp.mk(false);
 if(part==='corpse_headless')return sp.mk(false,{nohead:true});
 return sp[part];
}
function component(key,rect,pal) {
 const [kind,,value,undead]=key.split('|'),canvas=createCanvas(rect[2],rect[3]),g=canvas.getContext('2d');
 g.scale(2,2);g.lineJoin='round';g.lineCap='round';
 const v=a.makeVariant({beard:1},7);
 if(kind==='torso')a.drawTorso(g,{armor:value},pal,a.mulberry(7));
 else if(kind==='head') {
  const look={helm:value,beard:1,undead:undead||undefined},variant=a.makeVariant(look,7);
  a.drawHead(g,look,variant);a.drawHelm(g,look,variant,pal,a.mulberry(7));
 } else if(kind==='shield')a.drawShield(g,{shield:value},pal,a.mulberry(7));
 else if(kind==='weapon')a.drawWeapon(g,{weapon:value},pal,v);
 else if(kind==='base')a.drawBase(g,36,72,24,8.5,pal);
 else if(kind==='horse'||kind==='horse_corpse') {
  if(kind==='horse')a.drawBase(g,54,104,40,10.5,pal);
  g.save();g.translate(2,14);a.drawHorse(g,value,pal);g.restore();
  g.fillStyle=value==='barded'?pal.c2:'#3a2a1a';g.beginPath();g.moveTo(18,72);g.quadraticCurveTo(40,64,62,72);g.lineTo(59,82);g.quadraticCurveTo(40,87,21,82);g.closePath();g.fill();g.strokeStyle='#1b130c';g.lineWidth=1.2;g.stroke();
 } else throw Error('Unknown palette component '+key);
 return canvas;
}
(async()=>{
 fs.writeFileSync(path.join(out,'banner_definitions.gd'),'extends RefCounted\n## Original BANNERS from src/01_core.js.\nconst DATA = '+JSON.stringify(a.BANNERS)+'\n');
 const troops=Object.entries(manifest.troops).filter(([key])=>key.endsWith('|player'));
 for(let index=1;index<a.BANNERS.length;index++) {
  if(selected&&index!==Number(selected.split('=')[1]))continue;
  const pal=a.BANNERS[index];Object.assign(a.FACTIONS.player,{c1:pal.c1,c2:pal.c2});
  fs.writeFileSync(path.join(out,`banner_${index}_crest.png`),a.crestCanvas('player',96).toBuffer('image/png'));
  for(let variant=0;variant<4;variant++) {
   const sprites=troops.map(([key,entry])=>({entry,sp:a.buildSprite(entry.look,pal,a.hashStr(key.split('|')[0])+variant*977)}));
   for(const part of parts) {
    const original=await base(part+(variant?'_v'+variant:''));
    const entries=sprites.map(({entry,sp})=>({image:layer(sp,part),rect:entry.rect}));
    delta(original,entries,`banner_${index}_${part}_v${variant}`);
   }
  }
  const pages=new Map();
  for(const [key,entry]of Object.entries(manifest.components))if(key==='base|player'||key.includes('|player|')) {
   if(!pages.has(entry.page))pages.set(entry.page,[]);
   pages.get(entry.page).push({image:component(key,entry.rect,pal),rect:entry.rect});
  }
  for(const [page,entries]of pages)delta(await base('components_'+page),entries,`banner_${index}_components_${page}`);
  const settlements=[];let id=1;
  for(const cult of ['nord','emp','khan','kin','dom','pact','emi'])for(const fac of Object.keys(a.FACTIONS))for(const kind of ['town','castle','village','camp']) {
   const settlement={id:id++,kind,cult,fac};if(fac!=='player')continue;
   settlements.push({image:a.settleSprite(settlement).cv,rect:manifest.settlements[`${kind}|${cult}|${fac}`]});
  }
  delta(await base('settlements'),settlements,`banner_${index}_settlements`);
  // Compact original reference for native image tests, independent of the replacement implementation.
  const reference=a.buildSprite(a.TROOPS.n3.look,pal,a.hashStr('n3'));
  const fixture=path.join(root,'godot/tests/unit/visuals/fixtures');fs.mkdirSync(fixture,{recursive:true});
  fs.writeFileSync(path.join(fixture,`banner_${index}_n3.png`),reference.cv.toBuffer('image/png'));
  console.log(`Exported original banner ${index}: ${pal.n}`);
 }
})().catch(error=>{console.error(error);process.exitCode=1});
