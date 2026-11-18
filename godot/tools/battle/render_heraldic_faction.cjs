// Heraldic troop atlases for a whole faction from separately drawn parts
// (heraldic_source/<faction>-torsos.png, -heads.png, -shields.png; horses.png; weapons.png, bow.png).
// Rules: shareness/skills/unit-parts/SKILL.md («Правила по опыту»). The head lies OVER the torso and
// laps HEAD_OVERLAP px past the front rim of the collar opening: no joint, no gap.
// Usage: NODE_PATH=<node_modules with sharp> node render_heraldic_faction.cjs nord [--out DIR]
const fs=require('fs'),path=require('path'),sharp=require('sharp');
const dir=__dirname,src=path.join(dir,'heraldic_source');
const args=process.argv.slice(2),faction=args[0];
const outIndex=args.indexOf('--out');
const output=outIndex>=0?path.resolve(args[outIndex+1]):path.resolve(dir,'../../apps/godot/visuals/assets');
const geometryOut=outIndex>=0?output:path.resolve(output,'..');

// Weapon art: [file, col, row, cols, rows]. Placement in the 152×176 foot frame: height, top and the
// grip as a fraction of the weapon's width (bow: the leather wrap) — same numbers as the Dominion.
const WEAPONS={
 sword:{art:['weapons.png',0,0,2,3],h:102,y:28,grip:.5},
 axe:{art:['weapons.png',1,0,2,3],h:80,y:48,grip:.15},
 spear:{art:['weapons.png',0,1,2,3],h:146,y:3,grip:.5},
 lance:{art:['lance.png',0,0,1,1],h:206,y:0,grip:.5,gripY:.77},
 // The bow is held out at the right edge of the bust, so its string clears the face and chest.
 // Held low on the stave (70 % down), so the bow rises well above the fist.
 bow:{art:['bow.png',0,0,1,1],h:104,grip:.72,gripY:.7,hand:132},
};
const FACTIONS={
 nord:{
  // Order = cells of the part sheets (reading order); the last one rides.
  troops:[
   {id:'n1',weapon:'axe',shield:true,steel:false},
   {id:'n2',weapon:'axe',shield:true,steel:false},
   {id:'n3',weapon:'sword',shield:true,steel:true},
   {id:'n2s',weapon:'spear',shield:true,steel:false},
   {id:'n2a',weapon:'bow',shield:false,steel:false},
   {id:'n3a',weapon:'bow',shield:false,steel:false},
   {id:'n3c',weapon:'spear',shield:true,steel:true,horse:'bay'},
  ],
 },
};
const COATS=['bay','chestnut','dun','black','grey','barded','bone'];
const FOOT={W:152,H:176},HORSE={W:240,H:244};
const RIDER=[4,23];
const TORSO_WIDTH=108,HEAD_HEIGHT=64,HEAD_OVERLAP=3;
const HORSE_BOX={left:5,right:235,bottom:232};
// Where a round shield rests on the foot bust (frame pixels): [cx, cy, r], as the Dominion's.
const ROUND_SHIELD=[45.5,126,34.6];

async function cell(file,col,row,cols,rows){
 const meta=await sharp(file).metadata();
 const x=Math.round(col*meta.width/cols),y=Math.round(row*meta.height/rows);
 const width=Math.round((col+1)*meta.width/cols)-x,height=Math.round((row+1)*meta.height/rows)-y;
 const {data,info}=await sharp(file).extract({left:x,top:y,width,height}).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 let left=width,top=height,right=0,bottom=0;
 for(let y=0;y<height;y++)for(let x=0;x<width;x++)if(data[(y*width+x)*4+3]>40){left=Math.min(left,x);right=Math.max(right,x);top=Math.min(top,y);bottom=Math.max(bottom,y);}
 if(right<=left)throw Error('Empty source cell '+file+' '+col+','+row);
 return sharp(data,{raw:info}).extract({left,top,width:right-left+1,height:bottom-top+1}).png().toBuffer();
}
const frameOf=size=>async overlays=>sharp({create:{width:size.W,height:size.H,channels:4,background:'#00000000'}}).composite(overlays).png().toBuffer();
async function raw(buffer){return sharp(buffer).ensureAlpha().raw().toBuffer();}
const pngOf=size=>data=>sharp(data,{raw:{width:size.W,height:size.H,channels:4}}).png().toBuffer();
async function stamp(buffer,width,height,left,top){return {input:await sharp(buffer).resize(width,height,{fit:'fill'}).png().toBuffer(),left,top};}
const sum=(d,p)=>d[p]+d[p+1]+d[p+2];
const dark=(d,p)=>d[p+3]>128&&sum(d,p)<215;
// The collar opening is a dark hollow on the centre line: outline, back of the collar, hollow.
async function neckHole(buffer){
 const {data,info}=await sharp(buffer).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const w=info.width,h=info.height,cx=w>>1;
 let y=0;
 while(y<h&&data[(y*w+cx)*4+3]<=128)y++;
 while(y<h&&dark(data,(y*w+cx)*4))y++;
 while(y<h&&!dark(data,(y*w+cx)*4))y++;
 const top=y;
 while(y<h&&dark(data,(y*w+cx)*4))y++;
 const bottom=y-1,cy=(top+bottom)/2;
 if(bottom-top<3||top>h/3)throw Error('torso part without a collar opening');
 const row=Math.round(cy);let l=cx,r=cx;
 while(l>0&&dark(data,(row*w+l-1)*4))l--;
 while(r<w-1&&dark(data,(row*w+r+1)*4))r++;
 return {hole:[(l+r+1)/2,cy+.5,r-l+1,bottom-top+1]};
}
async function neckBottom(buffer){
 const {data,info}=await sharp(buffer).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const w=info.width,y=info.height-4;let l=-1,r=-1;
 for(let x=0;x<w;x++)if(data[(y*w+x)*4+3]>128){if(l<0)l=x;r=x;}
 return [(l+r+1)/2,r-l+1];
}
const BLOOD=[110,24,32],BLOOD_LIGHT=[158,52,52];
function woundSvg(o){
 const w=Math.ceil(o.rx*2+2),h=Math.ceil(o.ry*2+2),cx=w/2,cy=h/2;
 return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><ellipse cx="${cx}" cy="${cy}" rx="${o.rx}" ry="${o.ry}" fill="rgb(${BLOOD})"/><ellipse cx="${cx}" cy="${cy-o.ry*.25}" rx="${o.rx*.55}" ry="${o.ry*.35}" fill="rgb(${BLOOD_LIGHT})"/></svg>`;
}
function bloodyNeck(head,bottom,size){
 const out=Buffer.from(head),W=size.W,H=size.H;
 for(let y=Math.max(0,bottom-5);y<Math.min(H,bottom+2);y++)for(let x=0;x<W;x++){
  const p=(y*W+x)*4;if(out[p+3]<40)continue;
  // Skin, beard and hood above the very edge stay as drawn; the last rows are the cut.
  const r=out[p],g=out[p+1],b=out[p+2];
  if(!(r>g*1.1&&g>b*1.05)&&y<bottom-1)continue;
  const t=Math.min(1,(y-(bottom-5))/4),c=t>.6?BLOOD:BLOOD_LIGHT;
  for(let k=0;k<3;k++)out[p+k]=Math.round(out[p+k]*(1-Math.max(.55,t))+c[k]*Math.max(.55,t));
 }
 return out;
}
async function horseStamp(buffer){
 const m=await sharp(buffer).metadata();
 const scale=(HORSE_BOX.right-HORSE_BOX.left)/m.width,w=Math.round(m.width*scale),h=Math.round(m.height*scale);
 return {input:await sharp(buffer).resize(w,h).png().toBuffer(),left:HORSE_BOX.left,top:HORSE_BOX.bottom-h};
}

// One figure (foot or mounted): every layer placed in its frame, plus its geometry.
async function figure(spec,index,sheets,art){
 const mounted=!!spec.horse,size=mounted?HORSE:FOOT,frame=frameOf(size);
 const [ox,oy]=mounted?RIDER:[0,0];
 const neck=[76+ox,78+oy];
 const col=index%3,row=Math.floor(index/3);
 const torsoPart=await cell(sheets.torsos,col,row,3,3);
 const headPart=await cell(sheets.heads,col,row,3,3);
 const t=await sharp(torsoPart).metadata(),h=await sharp(headPart).metadata();
 const {hole}=await neckHole(torsoPart);
 const torsoScale=TORSO_WIDTH/t.width,headScale=HEAD_HEIGHT/h.height;
 const torso={input:await sharp(torsoPart).resize(Math.round(t.width*torsoScale),Math.round(t.height*torsoScale)).png().toBuffer(),
  left:Math.round(neck[0]-hole[0]*torsoScale),top:Math.round(neck[1]-hole[1]*torsoScale)};
 const opening={rx:hole[2]*torsoScale/2,ry:hole[3]*torsoScale/2};
 // Front rim of the opening on the centre column: first light pixel after the dark hollow.
 const placed=await raw(await frame([torso]));
 let y=neck[1],seenDark=false,rim=-1;
 for(;y<size.H;y++){const q=(y*size.W+neck[0])*4;const d=dark(placed,q);if(d)seenDark=true;else if(seenDark&&placed[q+3]>128){rim=y;break;}}
 if(rim<0)rim=Math.round(neck[1]+opening.ry);
 const tuck=rim+HEAD_OVERLAP-neck[1];
 const [neckX]=await neckBottom(headPart);
 const hw=Math.round(h.width*headScale),hh=Math.round(h.height*headScale);
 const head={input:await sharp(headPart).resize(hw,hh).png().toBuffer(),left:Math.round(neck[0]-neckX*headScale),top:neck[1]+tuck-hh};
 const geometry={center:[neck[0],Math.round(neck[1]+tuck-hh/2)],neck,canonical_facing:1};
 let shield=null;
 if(spec.shield){
  const s=await cell(sheets.shields,col,row,3,3),sm=await sharp(s).metadata();
  const [cx,cy,r]=[ROUND_SHIELD[0]+ox,ROUND_SHIELD[1]+oy,ROUND_SHIELD[2]];
  const k=Math.min(r*2/sm.width,r*2/sm.height),ow=Math.round(sm.width*k),oh=Math.round(sm.height*k);
  shield={input:await sharp(s).resize(ow,oh).png().toBuffer(),left:Math.round(cx-ow/2),top:Math.round(cy-oh/2)};
  geometry.shield_center=[Math.round(cx),Math.round(cy)];
 }
 // Weapon with its gripping glove; the cavalry lance is gripped below the vamplate.
 const w=WEAPONS[spec.weapon],weapon=art[spec.weapon],wm=await sharp(weapon).metadata();
 const glove=art[spec.steel?'steelGlove':'leatherGlove'];
 const wh=w.h,ww=Math.round(wh*wm.width/wm.height);
 let left,top,handX,handY=105+oy;
 if(w.hand){handX=w.hand+ox;left=handX-Math.round(ww*w.grip);top=Math.round(handY+11-wh*w.gripY);}
 else if(w.gripY){handX=125+ox;left=handX-Math.round(ww/2);top=Math.round(handY+11-wh*w.gripY);}
 else{left=Math.min(125-Math.round(ww*w.grip),FOOT.W-ww-2)+ox;handX=left+Math.round(ww*w.grip);top=w.y+oy;}
 const weaponLayer=[await stamp(weapon,ww,wh,left,top),await stamp(glove,20,22,handX-13,handY)];
 geometry.grip=[handX,handY+11];
 const horse=mounted?await horseStamp(await cell(path.join(src,'horses.png'),COATS.indexOf(spec.horse)%3,Math.floor(COATS.indexOf(spec.horse)/3),3,3)):null;
 return {spec,size,frame,png:pngOf(size),torso,head,shield,weaponLayer,horse,opening,neck,tuck,geometry};
}

// The ten rows of the foot atlas (body, weapon, portrait, headless, head, flash, corpse,
// corpse_headless, bare, shield); the cavalry adds an 11th: the rider alone without his horse.
async function rows(f,variant){
 const {frame,png,size}=f;
 const headImage=await raw(await frame([f.head]));
 for(let p=0;p<headImage.length;p+=4){
  const r=headImage[p],g=headImage[p+1],b=headImage[p+2];
  if(headImage[p+3]>0&&r>g*1.17&&g>b*1.12){const k=[1,.92,1.035,.97][variant];for(let c=0;c<3;c++)headImage[p+c]=Math.min(255,Math.round(headImage[p+c]*k));}
 }
 const under=f.horse?[f.horse]:[];
 const severed=bloodyNeck(headImage,f.neck[1]+f.tuck,size);
 const bare=await raw(await frame([...under,f.torso,{input:await png(headImage),left:0,top:0}]));
 const shieldLayer=f.shield?await raw(await frame([f.shield])):Buffer.alloc(size.W*size.H*4);
 const body=f.shield?await raw(await frame([{input:await png(bare),left:0,top:0},f.shield])):bare;
 const wound=await sharp(Buffer.from(woundSvg(f.opening))).png().toBuffer();
 const headless=await raw(await frame([...under,{input:wound,left:Math.round(f.neck[0]-f.opening.rx-1),top:Math.round(f.neck[1]-f.opening.ry-1)},f.torso,...(f.shield?[f.shield]:[])]));
 const weapon=await raw(await frame(f.weaponLayer));
 const portrait=await raw(await frame([{input:await png(body),left:0,top:0},{input:await png(weapon),left:0,top:0}]));
 const corpseHeadless=await frame([{input:await png(headless),left:0,top:0},{input:await png(weapon),left:0,top:0}]);
 const flash=Buffer.from(portrait);for(let p=0;p<flash.length;p+=4)flash[p]=flash[p+1]=flash[p+2]=255;
 const out=[await png(body),await png(weapon),await png(portrait),await png(headless),await png(severed),await png(flash),await png(portrait),corpseHeadless,
  await png(f.shield?bare:Buffer.alloc(size.W*size.H*4)),await png(shieldLayer)];
 if(f.horse)out.push(await frame([f.torso,{input:await png(headImage),left:0,top:0},...(f.shield?[f.shield]:[]),{input:await png(weapon),left:0,top:0}]));
 return out;
}

async function main(){
 const config=FACTIONS[faction];
 if(!config)throw Error('Unknown faction: '+faction+' (known: '+Object.keys(FACTIONS).join(', ')+')');
 const sheets={torsos:path.join(src,`${faction}-torsos.png`),heads:path.join(src,`${faction}-heads.png`),shields:path.join(src,`${faction}-shields.png`)};
 const art={};
 for(const [kind,w] of Object.entries(WEAPONS))if(fs.existsSync(path.join(src,w.art[0])))art[kind]=await cell(path.join(src,w.art[0]),...w.art.slice(1));
 art.steelGlove=await cell(path.join(src,'gloves.png'),0,0,2,2);
 art.leatherGlove=await cell(path.join(src,'gloves.png'),1,0,2,2);
 const figures=[];
 for(let i=0;i<config.troops.length;i++)figures.push(await figure(config.troops[i],i,sheets,art));
 const foot=figures.filter(f=>!f.spec.horse),cavalry=figures.filter(f=>f.spec.horse);
 const geometry=Object.fromEntries(figures.map(f=>[f.spec.id,f.geometry]));
 fs.writeFileSync(path.join(geometryOut,`${faction}_heraldic_geometry.gd`),'extends RefCounted\n## Generated by tools/battle/render_heraldic_faction.cjs from heraldic_source parts.\nconst DATA = '+JSON.stringify(geometry,null,'\t')+'\n');
 for(const [list,size,name,count] of [[foot,FOOT,`${faction}_heraldic`,10],[cavalry,HORSE,`${faction}_heraldic_cavalry`,11]]){
  if(!list.length)continue;
  for(let variant=0;variant<4;variant++){
   const overlays=[];
   for(let i=0;i<list.length;i++){const r=await rows(list[i],variant);r.forEach((input,row)=>overlays.push({input,left:i*size.W,top:row*size.H}));}
   await sharp({create:{width:size.W*list.length,height:size.H*count,channels:4,background:'#00000000'}}).composite(overlays).png().toFile(path.join(output,`${name}_${variant}.png`));
  }
 }
 console.log(`Built ${faction}: ${foot.length} foot and ${cavalry.length} mounted troops, 4 variants`);
}
main().catch(e=>{console.error(e);process.exitCode=1;});
