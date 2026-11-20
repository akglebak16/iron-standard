// Dominion cavalry atlas: heraldic horse busts (heraldic_source/horses.png, 7 coats) carrying a
// rider assembled from separately drawn parts (riders-torsos/heads/shields.png), like the infantry
// in render_dominion_heraldic.cjs. Frames are 240×244, the same box and anchor as the old mounted
// troops, so battle placement does not change.
// NODE_PATH may point to a node_modules with sharp.
const fs=require('fs'),path=require('path'),sharp=require('sharp');
const dir=__dirname,src=path.join(dir,'heraldic_source'),output=process.env.OUT||path.resolve(dir,'../../apps/godot/visuals/assets');
const W=240,H=244,ids=['d2c','d3c'];
const COATS=['bay','chestnut','dun','black','grey','barded','bone'];
// Horse bust box inside the frame (same place as the old horse) and where the rider's
// infantry-sized 152×176 bust frame is laid onto the saddle.
const HORSE_BOX={left:5,right:235,bottom:232};
const RIDER=[4,23];
const TORSO_WIDTH=108,HEAD_HEIGHT=64,HEAD_OVERLAP=3;
const NECK=[76+RIDER[0],78+RIDER[1]];
// Head heights differ by the plume: the greathelm is scaled by its helmet, not its feather.
// Head heights measured so each helmet is as wide as its infantry counterpart (spearman, guard).
const HEAD_SCALE_HEIGHT={d2c:73,d3c:78};
const SHIELDS={
 d2c:{round:[45.5+RIDER[0],126+RIDER[1],34.6]},
 d3c:{kite:[14.8+RIDER[0],84+RIDER[1],80.8+RIDER[0],81.5+RIDER[1],47.5+RIDER[0],161+RIDER[1],4]},
};
const TROOPS={d2c:{coat:'bay',weapon:'spear'},d3c:{coat:'chestnut',weapon:'lance'}};

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
async function frame(overlays){return sharp({create:{width:W,height:H,channels:4,background:'#00000000'}}).composite(overlays).png().toBuffer();}
async function raw(buffer){return sharp(buffer).ensureAlpha().raw().toBuffer();}
function png(data){return sharp(data,{raw:{width:W,height:H,channels:4}}).png().toBuffer();}
async function stamp(buffer,width,height,left,top){return {input:await sharp(buffer).resize(width,height,{fit:'fill'}).png().toBuffer(),left,top};}
// The riders' stand-up collars are lined in dark brown, lighter than the infantry's hollow.
const dark=(d,p)=>d[p+3]>128&&d[p]+d[p+1]+d[p+2]<215;
// Same collar-opening search as the infantry script.
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
 const rx=(r-l+1)/2,ry=(bottom-top+1)/2,ex=(l+r+1)/2;
 for(let yy=top;yy<=bottom;yy++)for(let x=l;x<=r;x++){
  const p=(yy*w+x)*4,dx=(x+.5-ex)/rx,dy=(yy+.5-cy-.5)/ry;
  if(dx*dx+dy*dy<=0.85&&dark(data,p))data.fill(0,p,p+4);
 }
 return {buffer:await sharp(data,{raw:info}).png().toBuffer(),hole:[ex,cy+.5,r-l+1,bottom-top+1]};
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
function bloodyNeck(head,bottom){
 const out=Buffer.from(head);
 for(let y=Math.max(0,bottom-5);y<Math.min(H,bottom+2);y++)for(let x=0;x<W;x++){
  const p=(y*W+x)*4;if(out[p+3]<40)continue;
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
function shieldCenter(spec){
 if(spec.round)return [spec.round[0],spec.round[1]];
 const [xl,yl,xr,yr,xt,yt]=spec.kite;return [(xl+xr+xt)/3,((yl+yr)/2+yt)/2];
}
async function main(){
 const horses={};
 for(let i=0;i<COATS.length;i++)horses[COATS[i]]=await horseStamp(await cell(path.join(src,'horses.png'),i%3,Math.floor(i/3),3,3));
 // All seven coats as a plain strip (one 240×244 frame each): the mount alone, for riders
 // thrown off their horse and for future Dominion cavalry.
 await sharp({create:{width:W*COATS.length,height:H,channels:4,background:'#00000000'}})
  .composite(await Promise.all(COATS.map(async(c,i)=>({input:await frame([horses[c]]),left:i*W,top:0}))))
  .png().toFile(path.join(output,'dominion_heraldic_horses.png'));
 const spear=await cell(path.join(src,'weapons.png'),0,1,2,3);
 const lance=await cell(path.join(src,'lance.png'),0,0,1,1);
 const glove=await cell(path.join(src,'gloves.png'),0,0,2,2);
 const geometry={};
 const placed=[];
 for(let i=0;i<ids.length;i++){
  const id=ids[i];
  let torso=await cell(path.join(src,'riders-torsos.png'),i,0,3,3);
  const head=await cell(path.join(src,'riders-heads.png'),i,0,3,3);
  const shield=await cell(path.join(src,'riders-shields.png'),i,0,3,3);
  const t=await sharp(torso).metadata(),h=await sharp(head).metadata();
  const torsoScale=TORSO_WIDTH/t.width,headScale=HEAD_SCALE_HEIGHT[id]/h.height;
  const opened=await neckHole(torso);torso=opened.buffer;const hole=opened.hole;
  const [neckX]=await neckBottom(head);
  const tw=Math.round(t.width*torsoScale),th=Math.round(t.height*torsoScale);
  const hw=Math.round(h.width*headScale),hh=Math.round(h.height*headScale);
  const opening={rx:hole[2]*torsoScale/2,ry:hole[3]*torsoScale/2};
  // The head lies OVER the body: the coif's cut covers the whole opening and laps a few px
  // past its front rim onto the mail collar, so there is no joint to see.
  const torsoStamp={input:await sharp(torso).resize(tw,th).png().toBuffer(),left:Math.round(NECK[0]-hole[0]*torsoScale),top:Math.round(NECK[1]-hole[1]*torsoScale)};
  // Front rim of the opening: the first light pixel below the neck line on the centre column.
  const placedTorso=await raw(await frame([torsoStamp]));
  let rim=NECK[1];
  while(rim<H-1){const q=(rim*W+NECK[0])*4;if(placedTorso[q+3]>128&&placedTorso[q]+placedTorso[q+1]+placedTorso[q+2]>450)break;rim++;}
  const tuck=rim+HEAD_OVERLAP-NECK[1];
  const part={
   torso:torsoStamp,
   head:{input:await sharp(head).resize(hw,hh).png().toBuffer(),left:Math.round(NECK[0]-neckX*headScale),top:NECK[1]+tuck-hh},
   opening,tuck,
  };
  // The head turns around the middle of the face, not the plume.
  geometry[id]={center:[NECK[0],Math.round(NECK[1]+tuck-Math.min(hh,HEAD_HEIGHT)/2)],neck:NECK,canonical_facing:1};
  const spec=SHIELDS[id],sm=await sharp(shield).metadata(),[cx,cy]=shieldCenter(spec);
  const sw=spec.round?spec.round[2]*2:spec.kite[2]-spec.kite[0];
  const sh=spec.round?spec.round[2]*2:spec.kite[5]-Math.min(spec.kite[1],spec.kite[3])+spec.kite[6];
  const scale=Math.min(sw/sm.width,sh/sm.height),ow=Math.round(sm.width*scale),oh=Math.round(sm.height*scale);
  const top=spec.round?Math.round(cy-oh/2):Math.round(Math.min(spec.kite[1],spec.kite[3])-spec.kite[6]);
  part.shield={input:await sharp(shield).resize(ow,oh).png().toBuffer(),left:Math.round(cx-ow/2),top};
  geometry[id].shield_center=[Math.round(cx),Math.round(top+oh/2)];
  // Spear like the infantry spearman's, the lance longer and gripped below its vamplate.
  const kind=TROOPS[id].weapon,art=kind==='lance'?lance:spear,am=await sharp(art).metadata();
  // The lance is 172 px so its point stays inside the frame (206 cut it off at the top).
  // The spear is held low on the shaft so it rises well above the rider's head.
  const wh=kind==='lance'?172:146,ww=Math.round(wh*am.width/am.height),grip=kind==='lance'?.77:.75;
  const handY=105+RIDER[1],handX=125+RIDER[0];
  const wy=Math.round(handY+11-wh*grip);
  part.weapon=[await stamp(art,ww,wh,handX-Math.round(ww/2),wy),await stamp(glove,20,22,handX-13,handY)];
  geometry[id].grip=[handX,handY+11];
  part.horse=horses[TROOPS[id].coat];
  placed.push(part);
 }
 fs.writeFileSync(path.join(output,process.env.OUT?'dominion_heraldic_cavalry_geometry.gd':'../dominion_heraldic_cavalry_geometry.gd'),'extends RefCounted\n## Generated by tools/battle/render_dominion_cavalry.cjs from heraldic_source parts.\nconst DATA = '+JSON.stringify(geometry,null,'\t')+'\n');
 for(let variant=0;variant<4;variant++){
  const overlays=[];
  for(let i=0;i<ids.length;i++){
   const part=placed[i];
   const head=await raw(await frame([part.head]));
   for(let p=0;p<head.length;p+=4){
    const r=head[p],g=head[p+1],b=head[p+2];
    if(head[p+3]>0&&r>g*1.17&&g>b*1.12){const k=[1,.92,1.035,.97][variant];for(let c=0;c<3;c++)head[p+c]=Math.min(255,Math.round(head[p+c]*k));}
   }
   const torso=await raw(await frame([part.torso]));
   const severed=bloodyNeck(head,NECK[1]+part.tuck);
   const o=part.opening;
   const bare=await raw(await frame([part.horse,part.torso,{input:await png(head),left:0,top:0}]));
   const shieldLayer=await raw(await frame([part.shield]));
   const body=await raw(await frame([{input:await png(bare),left:0,top:0},part.shield]));
   const wound=await sharp(Buffer.from(woundSvg(o))).png().toBuffer();
   const headless=await raw(await frame([part.horse,{input:wound,left:Math.round(NECK[0]-o.rx-1),top:Math.round(NECK[1]-o.ry-1)},part.torso,part.shield]));
   const weapon=await raw(await frame(part.weapon));
   const portrait=await raw(await frame([{input:await png(body),left:0,top:0},{input:await png(weapon),left:0,top:0}]));
   const corpseHeadless=await frame([{input:await png(headless),left:0,top:0},{input:await png(weapon),left:0,top:0}]);
   const flash=Buffer.from(portrait);for(let p=0;p<flash.length;p+=4)flash[p]=flash[p+1]=flash[p+2]=255;
   // The infantry atlas's ten rows (body, weapon, portrait, headless, head, flash, corpse,
   // corpse_headless, bare, shield) plus the rider without his horse.
   // Row 10: the rider alone with his weapon, no horse. A rider cut in half falls apart from
   // his mount, which lies down on its own (OriginalArt.mount_corpse).
   const rider=await frame([part.torso,{input:await png(head),left:0,top:0},part.shield,{input:await png(weapon),left:0,top:0}]);
   const rows=[await png(body),await png(weapon),await png(portrait),await png(headless),await png(severed),await png(flash),await png(portrait),corpseHeadless,await png(bare),await png(shieldLayer),rider];
   for(let row=0;row<rows.length;row++)overlays.push({input:rows[row],left:i*W,top:row*H});
  }
  await sharp({create:{width:W*ids.length,height:H*11,channels:4,background:'#00000000'}}).composite(overlays).png().toFile(path.join(output,`dominion_heraldic_cavalry_${variant}.png`));
 }
 console.log('Built Dominion cavalry: 2 troops × 11 states × 4 variants, 240×244 frames; 7 horse coats');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
