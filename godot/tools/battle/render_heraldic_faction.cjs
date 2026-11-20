// Heraldic troop atlases for a whole faction from separately drawn parts
// (heraldic_source/<faction>-torsos.png, -heads.png, -shields.png; horses.png; weapons.png, bow.png).
// Rules: shareness/skills/unit-parts/SKILL.md («Правила по опыту»). The head lies OVER the torso and
// laps HEAD_OVERLAP px past the front rim of the collar opening: no joint, no gap.
// `variants: true`: pages 1–3 take <faction>-torsos-vN.png / -heads-vN.png when they exist (other men,
// other armour details, same troop) and rotate natural horse coats, so a squad is not twenty clones.
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
 // On horseback the spear is held low on the shaft (75 % down) so it rises well above the head.
 spear:{art:['weapons.png',0,1,2,3],h:146,y:3,grip:.5,mountedGripY:.75},
 halberd:{art:['weapons.png',1,1,2,3],h:146,y:3,grip:.4},
 // Sabre like the sword; its hilt sits a third of the way across the curved blade's width.
 sabre:{art:['sabre.png',0,0,1,1],h:102,y:28,grip:.31},
 // Club like a short axe: thick end up, held near the bottom of its grip.
 club:{art:['club.png',0,0,1,1],h:86,y:40,grip:.5},
 mace:{art:['mace.png',0,0,1,1],h:86,y:40,grip:.5},
 // Crossbow as the Dominion's: stock across the body, rear fist at the trigger, other hand under the fore-end.
 xbow:{art:['weapons.png',0,2,2,3],h:63,y:88,left:72,hand:96,support:[115,116],pivotY:128},
 // 172 px: the point stays inside the 244 px mounted frame (206 cut it off at the top).
 lance:{art:['lance.png',0,0,1,1],h:172,y:0,grip:.5,gripY:.77},
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
FACTIONS.emp={
 // The cataphract rides a horse with the faction's own caparison (crimson, gold suns).
 troops:[
  {id:'e1',weapon:'sword',shield:'kite',steel:false},
  {id:'e2',weapon:'sword',shield:'kite',steel:true},
  {id:'e3',weapon:'sword',shield:'kite',steel:true,headHeight:72},
  {id:'e2s',weapon:'spear',shield:'kite',steel:false},
  {id:'e3s',weapon:'halberd',shield:false,steel:true},
  {id:'e2a',weapon:'xbow',shield:false,steel:false},
  {id:'e3a',weapon:'xbow',shield:false,steel:true},
  {id:'e3c',weapon:'lance',shield:'kite',steel:true,horse:'barded',horseArt:'emp-horse.png',headHeight:73},
 ],
};
FACTIONS.khan={
 troops:[
  {id:'k1',weapon:'sabre',shield:'small',steel:false},
  {id:'k2',weapon:'spear',shield:'small',steel:true,headHeight:68},
  {id:'k2a',weapon:'bow',shield:false,steel:false},
  {id:'k2c',weapon:'sabre',shield:'small',steel:true,horse:'dun',riderDx:6,riderDy:5},
  {id:'k3h',weapon:'bow',shield:false,steel:true,horse:'dun',headHeight:68,riderDy:7},
  {id:'k3c',weapon:'lance',shield:'small',steel:true,horse:'black',headHeight:74,riderDy:5},
 ],
};
FACTIONS.undead={
 troops:[
  {id:'z1',weapon:'club',shield:false,steel:false},
  {id:'s1',weapon:'sword',shield:'round',steel:false},
  {id:'s1a',weapon:'bow',shield:false,steel:false},
  {id:'s2',weapon:'axe',shield:'round',steel:true},
  {id:'s2c',weapon:'spear',shield:false,steel:false,horse:'bone'},
  {id:'s3',weapon:'sword',shield:'kite',steel:true},
 ],
};
FACTIONS.kin={
 variants:true,
 troops:[
  {id:'f1',weapon:'sword',shield:'round',steel:false},
  {id:'f2',weapon:'sword',shield:'kite',steel:true},
  {id:'f3',weapon:'sword',shield:'kite',steel:true},
  {id:'f2s',weapon:'spear',shield:'round',steel:false},
  {id:'f3s',weapon:'halberd',shield:false,steel:true},
  {id:'f2a',weapon:'bow',shield:false,steel:false},
  {id:'f3a',weapon:'bow',shield:false,steel:true},
  {id:'f2c',weapon:'sword',shield:'kite',steel:true,horse:'chestnut'},
  {id:'f3c',weapon:'lance',shield:'kite',steel:true,horse:'grey'},
 ],
};
FACTIONS.emi={
 troops:[
  {id:'m1',weapon:'sabre',shield:'small',steel:false},
  {id:'m2',weapon:'sabre',shield:'round',steel:false},
  {id:'m3',weapon:'sabre',shield:'round',steel:true},
  {id:'m2s',weapon:'spear',shield:'small',steel:false},
  {id:'m2a',weapon:'bow',shield:false,steel:false},
  {id:'m2c',weapon:'sabre',shield:'small',steel:false,horse:'dun',riderDy:7},
  {id:'m3h',weapon:'bow',shield:false,steel:true,horse:'dun',riderDy:4},
  {id:'m3c',weapon:'lance',shield:'small',steel:true,horse:'black',riderDy:6},
 ],
};
FACTIONS.pact={
 troops:[
  {id:'p1',weapon:'sword',shield:'round',steel:false},
  {id:'p2',weapon:'sword',shield:'kite',steel:true},
  {id:'p3',weapon:'sword',shield:'kite',steel:true},
  {id:'p2s',weapon:'spear',shield:'kite',steel:false},
  {id:'p3s',weapon:'halberd',shield:false,steel:true},
  {id:'p2a',weapon:'bow',shield:false,steel:false},
  {id:'p3a',weapon:'bow',shield:false,steel:true},
  {id:'p2c',weapon:'lance',shield:'kite',steel:true,horse:'bay'},
  {id:'p3c',weapon:'lance',shield:'kite',steel:true,horse:'grey'},
 ],
};
FACTIONS.bandit={
 troops:[
  {id:'b1',weapon:'club',shield:false,steel:false},
  {id:'b2',weapon:'axe',shield:'round',steel:false},
  {id:'b1a',weapon:'bow',shield:false,steel:false},
  {id:'b3',weapon:'mace',shield:'round',steel:true},
  {id:'b2c',weapon:'sword',shield:false,steel:false,horse:'bay',riderDy:8},
 ],
};
// Natural coats a variant may switch to.
const NATURAL_COATS=['bay','chestnut','dun','black','grey'];
const COATS=['bay','chestnut','dun','black','grey','barded','bone'];
const FOOT={W:152,H:176},HORSE={W:240,H:244};
const RIDER=[4,23];
const TORSO_WIDTH=108,HEAD_HEIGHT=64,HEAD_OVERLAP=3;
const HORSE_BOX={left:5,right:235,bottom:232};
// Where a shield rests on the foot bust (frame pixels), as the Dominion's: a circle [cx, cy, r] or a
// kite [left x, left y, right x, right y, tip x, tip y, top bulge]. `shield: true` means round.
const SHIELDS={round:{round:[45.5,126,34.6]},small:{round:[45.5,126,26]},kite:{kite:[18.4,86,78.8,86,48,161,4]}};

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
const dark=(d,p,limit=215)=>d[p+3]>128&&sum(d,p)<limit;

// The collar opening is a dark hollow on the centre line: outline, back of the collar, hollow.
// Variant sheets pass a lower `limit`: their back of the collar may be grey (≈200), not cream.
async function neckHole(buffer,limit=215){
 const {data,info}=await sharp(buffer).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const w=info.width,h=info.height,cx=w>>1;
 let y=0;
 while(y<h&&data[(y*w+cx)*4+3]<=128)y++;
 while(y<h&&dark(data,(y*w+cx)*4,limit))y++;
 while(y<h&&!dark(data,(y*w+cx)*4,limit))y++;
 const top=y;
 while(y<h&&dark(data,(y*w+cx)*4,limit))y++;
 const bottom=y-1,cy=(top+bottom)/2;
 if(bottom-top<3||top>h/3)throw Error('torso part without a collar opening');
 const row=Math.round(cy);let l=cx,r=cx;
 while(l>0&&dark(data,(row*w+l-1)*4,limit))l--;
 while(r<w-1&&dark(data,(row*w+r+1)*4,limit))r++;
 return {hole:[(l+r+1)/2,cy+.5,r-l+1,bottom-top+1]};
}
// Horizontal centre of a head part: the middle of its outline across the face band (35–80 % of the
// height), so a knot or scarf at the bottom and a crest or plume on top do not pull it sideways.
async function neckBottom(buffer){
 const {data,info}=await sharp(buffer).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const w=info.width,h=info.height;let sum=0,n=0;
 for(let y=Math.round(h*.35);y<Math.round(h*.8);y++){
  let l=-1,r=-1;
  for(let x=0;x<w;x++)if(data[(y*w+x)*4+3]>128){if(l<0)l=x;r=x;}
  if(l>=0){sum+=(l+r+1)/2;n++;}
 }
 return [sum/n,0];
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
// Repaint the shared ochre caparison in a faction colour, keeping shading. Its speckled texture
// reaches down to hue 0.085; the brass bridle fittings on the head (top third) keep their colour.
async function recolour(buffer,hex){
 const {data,info}=await sharp(buffer).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const target=[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16));
 for(let p=0;p<data.length;p+=4){
  if(!data[p+3])continue;
  const r=data[p]/255,g=data[p+1]/255,b=data[p+2]/255,max=Math.max(r,g,b),min=Math.min(r,g,b),v=max,s=max?(max-min)/max:0;
  let h=0;if(max>min){h=max===r?((g-b)/(max-min))%6:max===g?(b-r)/(max-min)+2:(r-g)/(max-min)+4;h=(h/6+1)%1;}
  if(p/4/info.width<info.height*.3)continue;
  if(h>.085&&h<.16&&s>.4){const k=Math.min(1.35,Math.max(.45,v/.68));for(let c=0;c<3;c++)data[p+c]=Math.min(255,Math.round(target[c]*k));}
 }
 return sharp(data,{raw:info}).png().toBuffer();
}
async function horseStamp(buffer,caparison){
 if(caparison)buffer=await recolour(buffer,caparison);
 const m=await sharp(buffer).metadata();
 const scale=(HORSE_BOX.right-HORSE_BOX.left)/m.width,w=Math.round(m.width*scale),h=Math.round(m.height*scale);
 return {input:await sharp(buffer).resize(w,h).png().toBuffer(),left:HORSE_BOX.left,top:HORSE_BOX.bottom-h};
}

// One figure (foot or mounted): every layer placed in its frame, plus its geometry.
async function figure(spec,index,sheets,art,caparison,variant=0){
 // Variants (factions with `variants: true`): own torso/head sheets and a rotated natural horse coat.
 const mounted=!!spec.horse,size=mounted?HORSE:FOOT,frame=frameOf(size);
 // A rider can be nudged in the saddle: `riderDx` forward, `riderDy` down (a quiver widens a torso,
 // which then comes out shorter and sits too high).
 const [ox,oy]=mounted?[RIDER[0]+(spec.riderDx||0),RIDER[1]+(spec.riderDy||0)]:[0,0];
 const neck=[76+ox,78+oy];
 const col=index%3,row=Math.floor(index/3);
 const torsoPart=await cell(sheets.torsos,col,row,3,3);
 const headPart=await cell(sheets.heads,col,row,3,3);
 const t=await sharp(torsoPart).metadata(),h=await sharp(headPart).metadata();
 const {hole}=await neckHole(torsoPart,variant?150:215);
 // A crest or plume adds height only: such heads set their own height so the helmet keeps its size.
 const torsoScale=TORSO_WIDTH/t.width,headScale=(spec.headHeight||HEAD_HEIGHT)/h.height;
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
  const shape=SHIELDS[spec.shield===true?'round':spec.shield];
  let ow,oh,left,top;
  if(shape.round){
   const [cx,cy,r]=[shape.round[0]+ox,shape.round[1]+oy,shape.round[2]];
   const k=Math.min(r*2/sm.width,r*2/sm.height);ow=Math.round(sm.width*k);oh=Math.round(sm.height*k);
   left=Math.round(cx-ow/2);top=Math.round(cy-oh/2);
   geometry.shield_center=[Math.round(cx),Math.round(cy)];
  }else{
   const [xl,yl,xr,yr,xt,yt,bulge]=shape.kite;
   const sw=xr-xl,sh=yt-Math.min(yl,yr)+bulge,k=Math.min(sw/sm.width,sh/sm.height);
   ow=Math.round(sm.width*k);oh=Math.round(sm.height*k);
   left=Math.round((xl+xr+xt)/3+ox-ow/2);top=Math.round(Math.min(yl,yr)-bulge+oy);
  }
  shield={input:await sharp(s).resize(ow,oh).png().toBuffer(),left,top};
  if(!geometry.shield_center)geometry.shield_center=[Math.round(left+ow/2),Math.round(top+oh/2)];
 }
 // Weapon with its gripping glove; the cavalry lance is gripped below the vamplate.
 const w=WEAPONS[spec.weapon],weapon=art[spec.weapon],wm=await sharp(weapon).metadata();
 const glove=art[spec.steel?'steelGlove':'leatherGlove'];
 const wh=w.h,ww=Math.round(wh*wm.width/wm.height);
 let left,top,handX,handY=105+oy;
 if(w.support){
  left=w.left+ox;top=w.y+oy;handX=w.hand+ox;
  const weaponLayer=[await stamp(glove,20,22,83+ox,117+oy),await stamp(art[spec.steel?'steelSupport':'leatherSupport'],20,22,w.support[0]+ox,w.support[1]+oy),await stamp(weapon,ww,wh,left,top)];
  geometry.grip=[handX,w.pivotY+oy];
  return finish(weaponLayer);
 }
 if(mounted&&w.mountedGripY){handX=125+ox;left=handX-Math.round(ww/2);top=Math.round(handY+11-wh*w.mountedGripY);}
 else if(w.hand){handX=w.hand+ox;left=handX-Math.round(ww*w.grip);top=Math.round(handY+11-wh*w.gripY);}
 else if(w.gripY){handX=125+ox;left=handX-Math.round(ww/2);top=Math.round(handY+11-wh*w.gripY);}
 else{left=Math.min(125-Math.round(ww*w.grip),FOOT.W-ww-2)+ox;handX=left+Math.round(ww*w.grip);top=w.y+oy;}
 geometry.grip=[handX,handY+11];
 return finish([await stamp(weapon,ww,wh,left,top),await stamp(glove,20,22,handX-13,handY)]);
 async function finish(weaponLayer){
  // Each variant rides its own coat, so a squadron is not four copies of one horse; the faction's own
  // horse art (cataphract) and the bone horse stay as drawn.
  const coat=COATS.indexOf(NATURAL_COATS.includes(spec.horse)&&!spec.horseArt?NATURAL_COATS[(NATURAL_COATS.indexOf(spec.horse)+variant)%NATURAL_COATS.length]:spec.horse);
  const horseArt=spec.horseArt?await cell(path.join(src,spec.horseArt),0,0,1,1):mounted?await cell(path.join(src,'horses.png'),coat%3,Math.floor(coat/3),3,3):null;
  const horse=mounted?await horseStamp(horseArt,spec.horse==='barded'&&!spec.horseArt?caparison:null):null;
  return {spec,size,frame,png:pngOf(size),torso,head,shield,weaponLayer,horse,opening,neck,tuck,geometry};
 }
}

// The ten rows of the foot atlas (body, weapon, portrait, headless, head, flash, corpse,
// corpse_headless, bare, shield); the cavalry adds the rider alone and the horse alone.
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
 if(f.horse){
  out.push(await frame([f.torso,{input:await png(headImage),left:0,top:0},...(f.shield?[f.shield]:[]),{input:await png(weapon),left:0,top:0}]));
  // Row 12: the horse alone, lying on after its rider is cut from the saddle.
  out.push(await frame([f.horse]));
 }
 return out;
}

async function main(){
 const config=FACTIONS[faction];
 if(!config)throw Error('Unknown faction: '+faction+' (known: '+Object.keys(FACTIONS).join(', ')+')');
 // Variant N (1-3) takes its own torsos and heads (<faction>-torsos-vN.png, -heads-vN.png) when they
 // exist: other faces and armour details on the same troop, so twenty men are not twenty clones.
 const sheet=(part,variant)=>{const own=path.join(src,`${faction}-${part}-v${variant}.png`);return variant&&fs.existsSync(own)?own:path.join(src,`${faction}-${part}.png`);};
 const sheetsOf=variant=>({torsos:sheet('torsos',variant),heads:sheet('heads',variant),shields:path.join(src,`${faction}-shields.png`)});
 const art={};
 for(const [kind,w] of Object.entries(WEAPONS))if(fs.existsSync(path.join(src,w.art[0])))art[kind]=await cell(path.join(src,w.art[0]),...w.art.slice(1));
 art.steelGlove=await cell(path.join(src,'gloves.png'),0,0,2,2);
 art.leatherGlove=await cell(path.join(src,'gloves.png'),1,0,2,2);
 art.steelSupport=await cell(path.join(src,'gloves.png'),0,1,2,2);
 art.leatherSupport=await cell(path.join(src,'gloves.png'),1,1,2,2);
 const byVariant=[];
 for(let variant=0;variant<4;variant++){
  const list=[];
  for(let i=0;i<config.troops.length;i++)list.push(await figure(config.troops[i],i,sheetsOf(config.variants?variant:0),art,config.caparison,config.variants?variant:0));
  byVariant.push(list);
 }
 const figures=byVariant[0];
 const foot=figures.filter(f=>!f.spec.horse),cavalry=figures.filter(f=>f.spec.horse);
 const geometry=Object.fromEntries(figures.map(f=>[f.spec.id,f.geometry]));
 fs.writeFileSync(path.join(geometryOut,`${faction}_heraldic_geometry.gd`),'extends RefCounted\n## Generated by tools/battle/render_heraldic_faction.cjs from heraldic_source parts.\nconst DATA = '+JSON.stringify(geometry,null,'\t')+'\n');
 for(const [mounted,size,name,count] of [[false,FOOT,`${faction}_heraldic`,10],[true,HORSE,`${faction}_heraldic_cavalry`,12]]){
  if(!(mounted?cavalry:foot).length)continue;
  for(let variant=0;variant<4;variant++){
   const list=byVariant[variant].filter(f=>!!f.spec.horse===mounted);
   const overlays=[];
   for(let i=0;i<list.length;i++){const r=await rows(list[i],variant);r.forEach((input,row)=>overlays.push({input,left:i*size.W,top:row*size.H}));}
   await sharp({create:{width:size.W*list.length,height:size.H*count,channels:4,background:'#00000000'}}).composite(overlays).png().toFile(path.join(output,`${name}_${variant}.png`));
  }
 }
 console.log(`Built ${faction}: ${foot.length} foot and ${cavalry.length} mounted troops, 4 variants`);
}
if(require.main===module)main().catch(e=>{console.error(e);process.exitCode=1;});
module.exports={WEAPONS,SHIELDS,cell,neckHole,woundSvg,dark,src};
