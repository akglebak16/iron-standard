// Atlas assembly only: generated drawings are preserved in heraldic_source/ (torso, head and
// shield drawn as separate parts; body.png is the earlier single-piece reference).
// NODE_PATH may point to the bundled runtime's node_modules (sharp).
const fs=require('fs'),path=require('path'),sharp=require('sharp');
const dir=__dirname,output=path.resolve(dir,'../../apps/godot/visuals/assets');
const W=152,H=176,ids=['d1','d2','d3','d2s','d3s','d2x','d3x'];
async function cell(file,col,row,cols,rows){
 const meta=await sharp(file).metadata();
 const x=Math.round(col*meta.width/cols),y=Math.round(row*meta.height/rows);
 const width=Math.round((col+1)*meta.width/cols)-x,height=Math.round((row+1)*meta.height/rows)-y;
 const {data,info}=await sharp(file).extract({left:x,top:y,width,height}).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 let left=width,top=height,right=0,bottom=0;
 for(let y=0;y<height;y++)for(let x=0;x<width;x++)if(data[(y*width+x)*4+3]>40){left=Math.min(left,x);right=Math.max(right,x);top=Math.min(top,y);bottom=Math.max(bottom,y);}
 if(right<=left)throw Error('Empty source cell');
 return sharp(data,{raw:info}).extract({left,top,width:right-left+1,height:bottom-top+1}).png().toBuffer();
}
async function stamp(buffer,width,height,left,top){
 const sprite=await sharp(buffer).resize(width,height,{fit:'fill'}).png().toBuffer();
 return {input:sprite,left,top};
}
async function frame(overlays){return sharp({create:{width:W,height:H,channels:4,background:'#00000000'}}).composite(overlays).png().toBuffer();}
async function raw(buffer){return sharp(buffer).ensureAlpha().raw().toBuffer();}
function png(data){return sharp(data,{raw:{width:W,height:H,channels:4}}).png().toBuffer();}
// Where each shield rests on the bust (frame pixels): a circle [cx, cy, r] or a kite
// [left x, left y, right x, right y, tip x, tip y, top bulge]; the shield part is fitted into it.
const SHIELDS={
 d1:{round:[45.5,126,34.6]},
 d2:{kite:[18.4,86,78.8,86,48,161,4]},
 d3:{kite:[14.8,84,80.8,81.5,47.5,161,4]},
 d2s:{round:[49.2,127,35.1]},
};
function shieldCenter(spec){
 if(spec.round)return [spec.round[0],spec.round[1]];
 const [xl,yl,xr,yr,xt,yt]=spec.kite;return [(xl+xr+xt)/3,((yl+yr)/2+yt)/2];
}
// Frame sizes of the parts, matched to the previous single-piece busts.
const TORSO_WIDTH=108,HEAD_HEIGHT=64,NECK_TUCK=4;
// The collar opening of a torso part is painted as a dark hollow. Find it on the centre line
// (outline, back of the collar, then the dark hollow), clear it so the neck can show through,
// and return the cleaned part with the hollow's centre.
const dark=(d,p)=>d[p+3]>128&&d[p]+d[p+1]+d[p+2]<150;
async function neckHole(buffer){
 const {data,info}=await sharp(buffer).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const w=info.width,h=info.height,cx=w>>1;
 let y=0;
 while(y<h&&data[(y*w+cx)*4+3]<=128)y++;          // above the figure
 while(y<h&&dark(data,(y*w+cx)*4))y++;              // outer outline
 while(y<h&&!dark(data,(y*w+cx)*4))y++;             // back of the collar
 const top=y;
 while(y<h&&dark(data,(y*w+cx)*4))y++;              // the hollow
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
// Centre x of the neck at the bottom of a head part.
async function neckBottom(buffer){
 const {data,info}=await sharp(buffer).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const w=info.width,y=info.height-4;let l=-1,r=-1;
 for(let x=0;x<w;x++)if(data[(y*w+x)*4+3]>128){if(l<0)l=x;r=x;}
 return [(l+r+1)/2,r-l+1];
}
const BLOOD=[110,24,32],BLOOD_LIGHT=[158,52,52];
// Blood filling the emptied collar opening (drawn behind the torso, so the collar frames it).
function woundSvg(o){
 const w=Math.ceil(o.rx*2+2),h=Math.ceil(o.ry*2+2),cx=w/2,cy=h/2;
 return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><ellipse cx="${cx}" cy="${cy}" rx="${o.rx}" ry="${o.ry}" fill="rgb(${BLOOD})"/><ellipse cx="${cx}" cy="${cy-o.ry*.25}" rx="${o.rx*.55}" ry="${o.ry*.35}" fill="rgb(${BLOOD_LIGHT})"/></svg>`;
}
// The bottom rows of a severed head's neck become blood (darker at the very edge).
function bloodyNeck(head,bottom){
 const out=Buffer.from(head);
 for(let y=Math.max(0,bottom-5);y<Math.min(H,bottom+2);y++)for(let x=0;x<W;x++){
  const p=(y*W+x)*4;if(out[p+3]<40)continue;
  // Only the neck: skin-coloured pixels, not coif mail or hair beside it.
  const r=out[p],g=out[p+1],b=out[p+2];
  if(!(r>g*1.1&&g>b*1.05)&&y<bottom-1)continue;
  const t=Math.min(1,(y-(bottom-5))/4),c=t>.6?BLOOD:BLOOD_LIGHT;
  for(let k=0;k<3;k++)out[p+k]=Math.round(out[p+k]*(1-Math.max(.55,t))+c[k]*Math.max(.55,t));
 }
 return out;
}
async function main(){
 const neckJoint=[76,78];
 const headData=Object.fromEntries(ids.map(id=>[id,{center:[76,48],neck:neckJoint,canonical_facing:1}]));
 const weapons=[],gloves=[];
 for(let i=0;i<5;i++)weapons.push(await cell(path.join(dir,'heraldic_source/weapons.png'),i%2,Math.floor(i/2),2,3));
 for(let i=0;i<4;i++)gloves.push(await cell(path.join(dir,'heraldic_source/gloves.png'),i%2,Math.floor(i/2),2,2));
 const config=[{w:1,h:80,y:48,grip:.15},{w:0,h:102,y:28,grip:.5},{w:0,h:102,y:28,grip:.5},{w:2,h:146,y:3,grip:.5},{w:3,h:146,y:3,grip:.4},{w:4,h:63,y:88,grip:.31},{w:4,h:63,y:88,grip:.31}];
 // Separately drawn parts (heraldic_source/parts-prompts.md): torso without head or shield,
 // head with a short neck, shield alone. Uniform scales keep the drawn proportions.
 const torsos=[],headParts=[],shieldParts={};
 for(let i=0;i<7;i++){
  torsos.push(await cell(path.join(dir,'heraldic_source/torsos.png'),i%3,Math.floor(i/3),3,3));
  headParts.push(await cell(path.join(dir,'heraldic_source/heads.png'),i%3,Math.floor(i/3),3,3));
  if(SHIELDS[ids[i]])shieldParts[ids[i]]=await cell(path.join(dir,'heraldic_source/shields.png'),i%3,Math.floor(i/3),3,3);
 }
 const placed=[];
 for(let i=0;i<7;i++){
  const t=await sharp(torsos[i]).metadata(),h=await sharp(headParts[i]).metadata();
  const torsoScale=TORSO_WIDTH/t.width,headScale=HEAD_HEIGHT/h.height;
  const opened=await neckHole(torsos[i]);torsos[i]=opened.buffer;const hole=opened.hole;
  // The emptied collar opening, in frame pixels: blood fills it when the head is gone.
  const opening={rx:hole[2]*torsoScale/2,ry:hole[3]*torsoScale/2};
  const [neckX,neckWidth]=await neckBottom(headParts[i]);
  const tw=Math.round(t.width*torsoScale),th=Math.round(t.height*torsoScale);
  const hw=Math.round(h.width*headScale),hh=Math.round(h.height*headScale);
  placed.push({
   torso:{input:await sharp(torsos[i]).resize(tw,th).png().toBuffer(),left:Math.round(neckJoint[0]-hole[0]*torsoScale),top:Math.round(neckJoint[1]-hole[1]*torsoScale)},
   head:{input:await sharp(headParts[i]).resize(hw,hh).png().toBuffer(),left:Math.round(neckJoint[0]-neckX*headScale),top:neckJoint[1]+NECK_TUCK-hh},
  });
  // The head turns around a point above its neck, centred on the shared joint.
  headData[ids[i]].center=[neckJoint[0],Math.round(neckJoint[1]+NECK_TUCK-hh/2)];
  placed[i].neckWidth=Math.round(neckWidth*headScale);
  placed[i].opening=opening;
  const spec=SHIELDS[ids[i]];
  if(spec){
   const sm=await sharp(shieldParts[ids[i]]).metadata();
   const [cx,cy]=shieldCenter(spec);
   const sw=spec.round?spec.round[2]*2:spec.kite[2]-spec.kite[0];
   const sh=spec.round?spec.round[2]*2:spec.kite[5]-Math.min(spec.kite[1],spec.kite[3])+spec.kite[6];
   const scale=Math.min(sw/sm.width,sh/sm.height),ow=Math.round(sm.width*scale),oh=Math.round(sm.height*scale);
   const top=spec.round?Math.round(cy-oh/2):Math.round(Math.min(spec.kite[1],spec.kite[3])-spec.kite[6]);
   placed[i].shield={input:await sharp(shieldParts[ids[i]]).resize(ow,oh).png().toBuffer(),left:Math.round(cx-ow/2),top};
   headData[ids[i]].shield_center=[Math.round(cx),Math.round(top+oh/2)];
  }
 }
 fs.writeFileSync(path.join(output,'../dominion_heraldic_heads.gd'),'extends RefCounted\n## Generated by tools/battle/render_dominion_heraldic.cjs from heraldic_source parts.\nconst DATA = '+JSON.stringify(headData,null,'\t')+'\n');
 for(let variant=0;variant<4;variant++){
  const overlays=[];
  for(let i=0;i<7;i++){
   const part=placed[i];
   // Four subtle complexion variants on the head only.
   const head=await raw(await frame([part.head]));
   for(let p=0;p<head.length;p+=4){
    const r=head[p],g=head[p+1],b=head[p+2];
    if(head[p+3]>0 && r>g*1.17 && g>b*1.12){const k=[1,.92,1.035,.97][variant];for(let c=0;c<3;c++)head[p+c]=Math.min(255,Math.round(head[p+c]*k));}
   }
   const torso=await raw(await frame([part.torso]));
   // A severed head: the lowest few pixels of its own neck turn to blood, following its outline.
   const severed=bloodyNeck(head,neckJoint[1]+NECK_TUCK);
   // Puppet joint: the head sits over the back of the collar, the front half of the collar
   // (below the opening's centre line) is laid over the neck again, so the neck goes INTO it.
   const front=Buffer.alloc(W*H*4),o=part.opening;
   for(let y=neckJoint[1];y<=Math.min(H-1,neckJoint[1]+o.ry+4);y++)for(let x=0;x<W;x++){
    if(Math.abs(x+.5-neckJoint[0])>o.rx+4)continue;
    const p=(y*W+x)*4;torso.copy(front,p,p,p+4);
   }
   const bare=await raw(await frame([part.torso,{input:await png(head),left:0,top:0},{input:await png(front),left:0,top:0}]));
   const shieldLayer=part.shield?await raw(await frame([part.shield])):Buffer.alloc(W*H*4);
   const body=part.shield?await raw(await frame([{input:await png(bare),left:0,top:0},part.shield])):bare;
   // The stump is as wide as the collar opening and sits behind the torso; only its cut shows.
   // Without the head the collar opening is filled with blood: no stump, no false perspective.
   const wound=await sharp(Buffer.from(woundSvg(part.opening))).png().toBuffer();
   const headlessTorso=part.shield?await raw(await frame([part.torso,part.shield])):torso;
   const headless=await raw(await frame([{input:wound,left:Math.round(neckJoint[0]-part.opening.rx-1),top:Math.round(neckJoint[1]-part.opening.ry-1)},{input:await png(headlessTorso),left:0,top:0}]));
   const c=config[i],meta=await sharp(weapons[c.w]).metadata();
   const width=Math.round(c.h*meta.width/meta.height);
   const left=c.w===4?72:Math.min(125-Math.round(width*c.grip),W-width-2);
   const handX=c.w===4?96:left+Math.round(width*c.grip);
   const weaponStamp=await stamp(weapons[c.w],width,c.h,left,c.y);
   const moving=[];
   // Hand-only dorsal mittens: no forearm/cuff and no separated fingers.
   const steel=[1,2,4,6].includes(i);
   const grip=gloves[steel?0:1];
   if(c.w===4){
    const support=gloves[steel?2:3];
    // Rear fist wraps the trigger area; the other hand cradles the fore-end.
    // Both thumbs stay beside/below the rail, clear of the bolt and string path.
    moving.push(await stamp(grip,20,22,83,117));
    moving.push(await stamp(support,20,22,115,116));
    // Keep the bolt rail and string visible above the supporting fingers.
    moving.push(weaponStamp);
   }else{
    moving.push(weaponStamp);
    moving.push(await stamp(grip,20,22,handX-13,105));
    // All five melee skins, including the requested halberd pose, use one hand.
   }
   if(variant===0)console.log(ids[i], 'weapon pivot',handX,c.w===4?128:116);
   const weapon=await raw(await frame(moving));
   const portrait=await raw(await frame([{input:await png(body),left:0,top:0},{input:await png(weapon),left:0,top:0}]));
   const corpseHeadless=await frame([{input:await png(headless),left:0,top:0},{input:await png(weapon),left:0,top:0}]);
   const flash=Buffer.from(portrait);for(let p=0;p<flash.length;p+=4)flash[p]=flash[p+1]=flash[p+2]=255;
   // Rows 8-9: the figure without its shield and the shield alone (block animation).
   const parts=[await png(body),await png(weapon),await png(portrait),await png(headless),await png(severed),await png(flash),await png(portrait),corpseHeadless,await png(part.shield?bare:Buffer.alloc(W*H*4)),await png(shieldLayer)];
   for(let row=0;row<parts.length;row++)overlays.push({input:parts[row],left:i*W,top:row*H});
  }
  await sharp({create:{width:W*7,height:H*10,channels:4,background:'#00000000'}}).composite(overlays).png().toFile(path.join(output,`dominion_heraldic_${variant}.png`));
 }
 console.log('Built 4 Dominion atlases: 7 troops × 10 states, 152×176 frames');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
