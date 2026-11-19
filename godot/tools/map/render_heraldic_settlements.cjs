// Heraldic settlements of the campaign map (#254): towns, castles and villages of seven cultures and the
// bandit lair, cut from generated sheets (settlement_source/*.png, prompts in settlement_source/prompts.md)
// into one atlas of equal frames with a common ground anchor, plus where the owner's banner pole stands.
// Usage: NODE_PATH=<node_modules with sharp> node render_heraldic_settlements.cjs [--out DIR]
const fs=require('fs'),path=require('path'),sharp=require('sharp');
const src=path.join(__dirname,'settlement_source');
const args=process.argv.slice(2),outIndex=args.indexOf('--out');
const output=outIndex>=0?path.resolve(args[outIndex+1]):path.resolve(__dirname,'../../apps/godot/visuals/assets');
const geometryOut=outIndex>=0?output:path.resolve(output,'..');

// Frame and the point standing on the map position (the middle of the ground patch).
const FRAME=[220,220],ANCHOR=[110,180];
const CULTURES=['nord','emp','khan','kin','emi','dom','pact'];
// Sheet, kinds in reading order, width of the ground patch in frame pixels (as the old icons:
// towns widest, villages smallest).
const SHEETS=[
 ['towns.png',CULTURES.map(c=>'town|'+c),150],
 ['castles.png',CULTURES.map(c=>'castle|'+c),140],
 ['villages.png',[...CULTURES.map(c=>'village|'+c),'camp'],125],
];
// Redrawn cells laid over the sheets above: each takes the ground width of the picture it replaces.
// The Dominion was red brick like the Pact; it is now whitewashed stone, dark timber and gold.
const REDRAWN=[['dominion.png',['town|dom','castle|dom','village|dom']]];

async function blobs(file){
 const {data,info}=await sharp(path.join(src,file)).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const w=info.width,h=info.height;for(let i=3;i<data.length;i+=4)if(data[i]<40)data[i-3]=data[i-2]=data[i-1]=data[i]=0;
 const runs=(n,on)=>{const r=[];let s=-1;for(let i=0;i<=n;i++){const o=i<n&&on(i);if(o&&s<0)s=i;if(!o&&s>=0){if(i-s>30)r.push([s,i]);s=-1;}}return r;};
 const opaque=(x,y)=>data[(y*w+x)*4+3]>0;
 const out=[];
 for(const [y0,y1] of runs(h,y=>{for(let x=0;x<w;x++)if(opaque(x,y))return true;return false;}))
  for(const [x0,x1] of runs(w,x=>{for(let y=y0;y<y1;y++)if(opaque(x,y))return true;return false;}))
   out.push(await sharp(await sharp(data,{raw:info}).extract({left:x0,top:y0,width:x1-x0,height:y1-y0}).png().toBuffer()).trim({threshold:0}).png().toBuffer());
 return out;
}
// The ground patch: its widest row in the lower third is the middle of the oval.
async function ground(buffer){
 const {data,info}=await sharp(buffer).ensureAlpha().raw().toBuffer({resolveWithObject:true});const w=info.width,h=info.height;
 let best=null;
 for(let y=Math.floor(h*.6);y<h;y++){let l=-1,r=-1;for(let x=0;x<w;x++)if(data[(y*w+x)*4+3]>128){if(l<0)l=x;r=x;}
  if(l>=0&&(!best||r-l>=best.width))best={y,cx:(l+r+1)/2,width:r-l+1};}
 // Highest opaque point, for the banner pole.
 let top=null;for(let y=0;y<h&&!top;y++)for(let x=0;x<w;x++)if(data[(y*w+x)*4+3]>128){top=[x,y];break;}
 return {...best,top};
}

async function main(){
 const frames={},flags={},groundWidth={},parts={};
 for(const [file,names,width] of SHEETS){
  const list=await blobs(file);
  if(list.length!==names.length)throw Error(`${file}: ${list.length} parts, expected ${names.length}`);
  const info=await Promise.all(list.map(ground));
  // One scale per sheet, so the cultures keep their sizes relative to each other.
  const widths=info.map(g=>g.width).sort((a,b)=>a-b),k=width/widths[widths.length>>1];
  names.forEach((n,i)=>{parts[n]={buffer:list[i],g:info[i],k};groundWidth[n]=info[i].width*k;});
 }
 for(const [file,names] of REDRAWN){
  const list=await blobs(file);
  if(list.length!==names.length)throw Error(`${file}: ${list.length} parts, expected ${names.length}`);
  for(let i=0;i<list.length;i++){const g=await ground(list[i]);parts[names[i]]={buffer:list[i],g,k:groundWidth[names[i]]/g.width};}
 }
 for(const [name,{buffer,g,k}] of Object.entries(parts)){
  const m=await sharp(buffer).metadata(),w=Math.round(m.width*k),h=Math.round(m.height*k);
  const left=Math.round(ANCHOR[0]-g.cx*k),top=Math.round(ANCHOR[1]-g.y*k);
  if(left<0||top<0||left+w>FRAME[0]||top+h>FRAME[1])throw Error(`${name} does not fit the frame: ${left},${top} ${w}×${h}`);
  frames[name]=await sharp({create:{width:FRAME[0],height:FRAME[1],channels:4,background:'#00000000'}})
   .composite([{input:await sharp(buffer).resize(w,h).png().toBuffer(),left,top}]).png().toBuffer();
  // The banner pole stands just right of the highest point (offset from the anchor, frame pixels).
  flags[name]=[Math.round(left+g.top[0]*k+3-ANCHOR[0]),Math.round(top+g.top[1]*k+10-ANCHOR[1])];
 }
 const names=Object.keys(frames),columns=CULTURES.length,rows=Math.ceil(names.length/columns);
 await sharp({create:{width:FRAME[0]*columns,height:FRAME[1]*rows,channels:4,background:'#00000000'}})
  .composite(names.map((n,i)=>({input:frames[n],left:(i%columns)*FRAME[0],top:Math.floor(i/columns)*FRAME[1]}))).png().toFile(path.join(output,'settlements_heraldic.png'));
 const geometry={frame:FRAME,anchor:ANCHOR,cells:Object.fromEntries(names.map((n,i)=>[n,[(i%columns)*FRAME[0],Math.floor(i/columns)*FRAME[1]]])),flags};
 fs.writeFileSync(path.join(geometryOut,'settlements_heraldic_geometry.gd'),'extends RefCounted\n## Generated by tools/map/render_heraldic_settlements.cjs from tools/map/settlement_source.\nconst DATA = '+JSON.stringify(geometry,null,'\t')+'\n');
 console.log(`Built ${names.length} settlements`);
}
main().catch(e=>{console.error(e);process.exitCode=1;});
