// Heraldic parts of the player's hero (and companions): every part placed in the 152×176 foot frame,
// in key colours the game repaints at run time (apps/godot/visuals/hero_heraldic_art.gd):
// cloth red #C62828 → banner c1, green #2E7D32 → banner c2, skin #E2B48C → chosen skin,
// hair and beards blue #1E5AC8 → chosen hair colour.
// Sources: heraldic_source/hero-*.png (prompts: hero-prompts.md). Heads, hair and beards are aligned
// to the bare head of hero-heads-a.png by their faces (hero-registration.json, from hero_register.py).
// Usage: NODE_PATH=<node_modules with sharp> node render_heraldic_hero.cjs [--out DIR]
const fs=require('fs'),path=require('path'),sharp=require('sharp');
const {WEAPONS,SHIELDS,cell,dark,src}=require('./render_heraldic_faction.cjs');
const args=process.argv.slice(2),outIndex=args.indexOf('--out');
const output=outIndex>=0?path.resolve(args[outIndex+1]):path.resolve(__dirname,'../../apps/godot/visuals/assets');
const geometryOut=outIndex>=0?output:path.resolve(output,'..');

// The bare head is 56 px tall, so a helmeted head comes out about 64 px like the troops' heads.
const W=152,H=176,NECK=[76,78],TORSO_WIDTH=108,HEAD_HEIGHT=56;
// Riders of every faction sit at one height: the bottom of the torso (the belt) on row MOUNTED_BELT_Y of the
// 240×244 mounted frame, as the faction cavalry (shareness/skills/unit-parts/SKILL.md). The hero's rider
// offset is worked out from his tunic so his belt lands there too.
const MOUNTED_BELT_Y=182,RIDER_DX=6,RIDER=[RIDER_DX,0],HW=240,HH=244;
// Sheet → part names in reading order ('-' skips a blob that another sheet replaces).
const SHEETS={
 'hero-torsos-a.png':['torso:tunic','torso:fur','-','torso:padded','-','-'],
 'hero-mail.png':['torso:mailfur','torso:mail','torso:mailtab'],
 'hero-torsos-b.png':['torso:scale','torso:goldscale','torso:lamellar','torso:goldlam','torso:plate'],
 'hero-heads-a.png':['head:none','head:nasal','head:spectacle','head:cap','head:hood','head:flat','-','head:kettle','head:mask'],
 'hero-heads-b.png':['head:furcap','head:pointed','head:great','head:coif','head:turban','head:turbanm','head:crest'],
 'hero-hair.png':['hair:hair','hair:beard1','hair:beard2','hair:stache'],
 'hero-shields.png':['shield:kite','shield:round','shield:small'],
};
const ARMORS=['tunic','fur','mailfur','padded','mail','mailtab','scale','goldscale','lamellar','goldlam','plate'];
const HELMS=['none','nasal','spectacle','cap','hood','flat','crest','kettle','mask','furcap','pointed','great','coif','turban','turbanm'];
const WEAPON_KINDS=['sword','axe','spear','halberd','sabre','club','xbow','lance','bow'];
// Helmets whose face is open below the nose: a beard shows under them.
const OPEN_FACE=['none','nasal','cap','hood','kettle','furcap','turban'];

const hsv=(r,g,b)=>{r/=255;g/=255;b/=255;const mx=Math.max(r,g,b),mn=Math.min(r,g,b);let h=0;
 if(mx>mn){h=mx===r?((g-b)/(mx-mn))%6:mx===g?(b-r)/(mx-mn)+2:(r-g)/(mx-mn)+4;h=(h/6+1)%1;}return [h,mx?(mx-mn)/mx:0,mx];};
const keyBlue=(h,s,v)=>h>.55&&h<.7&&s>.4&&v>.35;

// The generator's light checkerboard background, flood-filled away from the edges.
function clearBackground(data,w,h){
 let transparent=0;for(let i=3;i<data.length;i+=4)if(data[i]<40)transparent++;
 if(transparent>w*h*.3){for(let i=3;i<data.length;i+=4)if(data[i]<40)data[i-3]=data[i-2]=data[i-1]=data[i]=0;return;}
 const light=i=>{const p=i*4,mn=Math.min(data[p],data[p+1],data[p+2]),mx=Math.max(data[p],data[p+1],data[p+2]);return mn>200&&mx-mn<20;};
 const seen=new Uint8Array(w*h),stack=[];
 for(let x=0;x<w;x++)stack.push(x,(h-1)*w+x);for(let y=0;y<h;y++)stack.push(y*w,y*w+w-1);
 while(stack.length){const i=stack.pop();if(seen[i]||!light(i))continue;seen[i]=1;data[i*4+3]=0;const x=i%w;
  if(x>0)stack.push(i-1);if(x<w-1)stack.push(i+1);if(i>=w)stack.push(i-w);if(i<w*(h-1))stack.push(i+w);}
 // The anti-aliased rim between the outline and the white background stays pale: peel pale, grey
 // pixels off the edge until the dark outline is reached.
 const pale=i=>{const p=i*4,mn=Math.min(data[p],data[p+1],data[p+2]),mx=Math.max(data[p],data[p+1],data[p+2]);return data[p+3]>0&&mn>90&&mx-mn<50;};
 for(let pass=0;pass<4;pass++){const peel=[];
  for(let i=0;i<w*h;i++){if(!pale(i))continue;const x=i%w;
   if((x>0&&!data[(i-1)*4+3])||(x<w-1&&!data[(i+1)*4+3])||(i>=w&&!data[(i-w)*4+3])||(i<w*(h-1)&&!data[(i+w)*4+3]))peel.push(i);}
  if(!peel.length)break;for(const i of peel)data[i*4]=data[i*4+1]=data[i*4+2]=data[i*4+3]=0;}
}
// Blobs in reading order: bands of opaque rows, then opaque columns inside each band.
async function blobs(file){
 const {data,info}=await sharp(path.join(src,file)).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const w=info.width,h=info.height;clearBackground(data,w,h);
 const runs=(n,on)=>{const r=[];let s=-1;for(let i=0;i<=n;i++){const o=i<n&&on(i);if(o&&s<0)s=i;if(!o&&s>=0){if(i-s>30)r.push([s,i]);s=-1;}}return r;};
 const opaque=(x,y)=>data[(y*w+x)*4+3]>40;
 const out=[];
 for(const [y0,y1] of runs(h,y=>{for(let x=0;x<w;x++)if(opaque(x,y))return true;return false;}))
  for(const [x0,x1] of runs(w,x=>{for(let y=y0;y<y1;y++)if(opaque(x,y))return true;return false;})){
   const piece=await sharp(data,{raw:info}).extract({left:x0,top:y0,width:x1-x0,height:y1-y0}).png().toBuffer();
   out.push(await sharp(piece).trim({threshold:0}).png().toBuffer());
  }
 return out;
}
async function pixels(buffer){return sharp(buffer).ensureAlpha().raw().toBuffer({resolveWithObject:true});}
// Middle of the outline over a band of rows (fractions of the height).
async function middle(buffer,from,to){const {data,info}=await pixels(buffer);const w=info.width,h=info.height;let s=0,n=0;
 for(let y=Math.round(h*from);y<Math.round(h*to);y++){let l=-1,r=-1;for(let x=0;x<w;x++)if(data[(y*w+x)*4+3]>128){if(l<0)l=x;r=x;}if(l>=0){s+=(l+r+1)/2;n++;}}return s/n;}
// The collar hollow: the dark run on the centre column whose row is the widest dark span.
async function hollow(buffer){const {data,info}=await pixels(buffer);const w=info.width,cx=w>>1,limit=info.height/3;
 const span=y=>{let l=cx,r=cx;while(l>0&&dark(data,(y*w+l-1)*4))l--;while(r<w-1&&dark(data,(y*w+r+1)*4))r++;return [l,r];};
 let best=null,bw=-1,start=-1;
 for(let y=0;y<limit;y++){const d=dark(data,(y*w+cx)*4);if(d&&start<0)start=y;
  if((!d||y+1>=limit)&&start>=0){const [l,r]=span((start+y)>>1);if(y-start>=3&&r-l>bw){bw=r-l;best={cx:(l+r+1)/2,cy:(start+y)/2,rx:(r-l+1)/2,ry:(y-start)/2};}start=-1;}}
 if(!best)throw Error('torso part without a collar opening');return best;}
// The hollow becomes the shadowed neck inside the collar, so a narrow neckerchief shows no black gap.
async function fillHollow(buffer,o){const {data,info}=await pixels(buffer);
 for(let y=Math.floor(o.cy-o.ry-2);y<=o.cy+o.ry+2;y++)for(let x=Math.floor(o.cx-o.rx-2);x<=o.cx+o.rx+2;x++){
  if(x<0||y<0||x>=info.width||y>=info.height||((x-o.cx)/(o.rx+1))**2+((y-o.cy)/(o.ry+1))**2>1)continue;
  const p=(y*info.width+x)*4;if(dark(data,p)){data[p]=0x34;data[p+1]=0x22;data[p+2]=0x16;}}
 return sharp(data,{raw:info}).png().toBuffer();}
// Blue hair with its own outline, without the head outline of the sheet it was drawn on.
async function hairOnly(buffer,transform,bald){const {data,info}=await pixels(buffer);const w=info.width,h=info.height;
 const blue=new Uint8Array(w*h);for(let i=0;i<w*h;i++){const p=i*4;if(data[p+3]>40&&keyBlue(...hsv(data[p],data[p+1],data[p+2])))blue[i]=1;}
 const baldDark=(x,y)=>{const X=Math.round(x*transform[0]+transform[1]),Y=Math.round(y*transform[0]+transform[2]);
  for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){const xx=X+dx,yy=Y+dy;if(xx>=0&&yy>=0&&xx<bald.info.width&&yy<bald.info.height&&dark(bald.data,(yy*bald.info.width+xx)*4))return true;}return false;};
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){const i=y*w+x;if(blue[i])continue;const p=i*4;
  let keep=false;if(dark(data,p)&&!baldDark(x,y))for(let dy=-4;dy<=4&&!keep;dy++)for(let dx=-4;dx<=4;dx++){const xx=x+dx,yy=y+dy;if(xx>=0&&yy>=0&&xx<w&&yy<h&&blue[yy*w+xx]){keep=true;break;}}
  if(!keep)data[p+3]=0;}
 return sharp(data,{raw:info}).png().toBuffer();}
const frameOf=(width,height)=>layers=>sharp({create:{width,height,channels:4,background:'#00000000'}}).composite(layers).png().toBuffer();
const frame=frameOf(W,H);
async function stamp(buffer,width,height,left,top){return {input:await sharp(buffer).resize(Math.max(1,Math.round(width)),Math.max(1,Math.round(height)),{fit:'fill'}).png().toBuffer(),left:Math.round(left),top:Math.round(top)};}

async function main(){
 const parts={};
 for(const [file,names] of Object.entries(SHEETS)){
  const list=await blobs(file);
  if(list.length!==names.length)throw Error(`${file}: ${list.length} parts, expected ${names.length}`);
  names.forEach((n,i)=>{if(n!=='-')parts[n]=list[i];});
 }
 const registration=JSON.parse(fs.readFileSync(path.join(src,'hero-registration.json'),'utf8'));
 const frames={},geometry={torso_head_dy:{},grip:{},mounted_grip:{},shield_center:{}};
 // Torsos: collar opening at the neck point; where the head's bottom goes on each of them.
 const bottoms={};
 for(const armor of ARMORS){
  const raw=parts['torso:'+armor],m=await sharp(raw).metadata(),o=await hollow(raw),k=TORSO_WIDTH/m.width;
  const filled=await fillHollow(raw,o);
  const layer=await stamp(filled,m.width*k,m.height*k,NECK[0]-o.cx*k,NECK[1]-o.cy*k);
  frames['torso:'+armor]=await frame([layer]);
  const {data}=await pixels(frames['torso:'+armor]);
  let y=NECK[1],seen=false,rim=-1;for(;y<H;y++){const q=(y*W+NECK[0])*4;if(dark(data,q))seen=true;else if(seen&&data[q+3]>128){rim=y;break;}}
  let rimH=0;while(rimH<12){const q=((rim+rimH)*W+NECK[0])*4;if(data[q+3]<=128||data[q]+data[q+1]+data[q+2]<150)break;rimH++;}
  bottoms[armor]=rim+Math.round(rimH*.5);
  if(armor==='tunic')geometry.opening={rx:o.rx*k,ry:o.ry*k};
 }
 const bottom=bottoms.tunic;
 {const {data}=await pixels(frames['torso:tunic']);let low=0;for(let y=0;y<H;y++)for(let x=0;x<W;x++)if(data[(y*W+x)*4+3]>128)low=y;RIDER[1]=MOUNTED_BELT_Y-low;}
 for(const armor of ARMORS)geometry.torso_head_dy[armor]=bottoms[armor]-bottom;
 // Heads, hair and beards: placed as the bare head is, then moved by their face registration.
 const bald=parts['head:none'],bm=await sharp(bald).metadata(),k=HEAD_HEIGHT/bm.height,baldPixels=await pixels(bald);
 const refLeft=NECK[0]-await middle(bald,.35,.8)*k,refTop=bottom-bm.height*k;
 const neckMid=await middle(bald,.88,.97);
 async function placed(name,buffer){const m=await sharp(buffer).metadata();
  let t=registration[name.replace(':','-').replace('head-','h-').replace('hair-','x-')];
  // Closed helmets show no face to match: their neckerchief sits where the bare head's does.
  if(!t)t=[1,neckMid-await middle(buffer,.88,.97),bm.height-m.height];
  return stamp(buffer,m.width*k*t[0],m.height*k*t[0],refLeft+t[1]*k,refTop+t[2]*k);}
 for(const helm of HELMS)frames['head:'+helm]=await frame([await placed('head:'+helm,parts['head:'+helm])]);
 for(const hair of ['hair','beard1','beard2','stache']){
  const name='hair:'+hair,t=registration['x-'+hair];
  frames[name]=await frame([await placed(name,await hairOnly(parts[name],t,baldPixels))]);
 }
 geometry.head_center=[NECK[0],Math.round(refTop+bm.height*k/2)];
 geometry.neck=NECK;
 // A scar across the right cheek of the bare face (frame pixels): from, to.
 geometry.scar=[[Math.round(refLeft+bm.width*k*.66),Math.round(refTop+bm.height*k*.5)],[Math.round(refLeft+bm.width*k*.74),Math.round(refTop+bm.height*k*.64)]];
 // Shields on the foot bust, as the factions'.
 for(const kind of ['kite','round','small']){
  const s=parts['shield:'+kind],sm=await sharp(s).metadata(),shape=SHIELDS[kind];let layer;
  if(shape.round){const [cx,cy,r]=shape.round,q=Math.min(r*2/sm.width,r*2/sm.height);
   layer=await stamp(s,sm.width*q,sm.height*q,cx-sm.width*q/2,cy-sm.height*q/2);geometry.shield_center[kind]=[Math.round(cx),Math.round(cy)];}
  else{const [xl,yl,xr,yr,xt,yt,bulge]=shape.kite,sw=xr-xl,sh=yt-Math.min(yl,yr)+bulge,q=Math.min(sw/sm.width,sh/sm.height);
   const ow=sm.width*q,oh=sm.height*q,left=(xl+xr+xt)/3-ow/2,top=Math.min(yl,yr)-bulge;
   layer=await stamp(s,ow,oh,left,top);geometry.shield_center[kind]=[Math.round(left+ow/2),Math.round(top+oh/2)];}
  frames['shield:'+kind]=await frame([layer]);
 }
 // The cut neck of a fallen hero, laid over the collar.
 const o=geometry.opening;
 frames.wound=await frame([{input:Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}"><ellipse cx="${NECK[0]}" cy="${NECK[1]}" rx="${o.rx}" ry="${o.ry}" fill="rgb(110,24,32)"/><ellipse cx="${NECK[0]}" cy="${NECK[1]-o.ry*.25}" rx="${o.rx*.55}" ry="${o.ry*.35}" fill="rgb(158,52,52)"/></svg>`),left:0,top:0}]);
 // Weapons with the gripping glove, as the factions' (foot frame; spear and lance also mounted).
 const art={};
 for(const kind of WEAPON_KINDS){const w=WEAPONS[kind];art[kind]=await cell(path.join(src,w.art[0]),...w.art.slice(1));}
 for(const [name,c,r] of [['steelGlove',0,0],['leatherGlove',1,0],['steelSupport',0,1],['leatherSupport',1,1]])art[name]=await cell(path.join(src,'gloves.png'),c,r,2,2);
 const mountedFrames={};
 async function weapon(kind,steel,mounted){
  const w=WEAPONS[kind],picture=art[kind],wm=await sharp(picture).metadata(),glove=art[steel?'steelGlove':'leatherGlove'];
  const [ox,oy]=mounted?RIDER:[0,0],wh=w.h,ww=Math.round(wh*wm.width/wm.height);let left,top,handX,handY=105+oy,grip;
  if(w.support){left=w.left+ox;top=w.y+oy;handX=w.hand+ox;grip=[handX,w.pivotY+oy];
   return {grip,layers:[await stamp(glove,20,22,83+ox,117+oy),await stamp(art[steel?'steelSupport':'leatherSupport'],20,22,w.support[0]+ox,w.support[1]+oy),await stamp(picture,ww,wh,left,top)]};}
  if(mounted&&w.mountedGripY){handX=125+ox;left=handX-Math.round(ww/2);top=Math.round(handY+11-wh*w.mountedGripY);}
  else if(w.hand){handX=w.hand+ox;left=handX-Math.round(ww*w.grip);top=Math.round(handY+11-wh*w.gripY);}
  else if(w.gripY){handX=125+ox;left=handX-Math.round(ww/2);top=Math.round(handY+11-wh*w.gripY);}
  else{left=Math.min(125-Math.round(ww*w.grip),W-ww-2)+ox;handX=left+Math.round(ww*w.grip);top=w.y+oy;}
  return {grip:[handX,handY+11],layers:[await stamp(picture,ww,wh,left,top),await stamp(glove,20,22,handX-13,handY)]};
 }
 for(const kind of WEAPON_KINDS)for(const steel of [false,true]){
  const name=`weapon:${kind}:${steel?'steel':'leather'}`,foot=await weapon(kind,steel,false);
  frames[name]=await frame(foot.layers);geometry.grip[kind]=foot.grip;
  if(WEAPONS[kind].mountedGripY||kind==='lance'){const m=await weapon(kind,steel,true);mountedFrames[name]=await frameOf(HW,HH)(m.layers);geometry.mounted_grip[kind]=m.grip;}
 }
 // Atlases: foot parts in a grid of 152×176 cells, mounted weapons in a row of 240×244 cells.
 const names=Object.keys(frames),columns=9,rows=Math.ceil(names.length/columns);
 await sharp({create:{width:W*columns,height:H*rows,channels:4,background:'#00000000'}})
  .composite(names.map((n,i)=>({input:frames[n],left:(i%columns)*W,top:Math.floor(i/columns)*H}))).png().toFile(path.join(output,'hero_heraldic_parts.png'));
 const mountedNames=Object.keys(mountedFrames);
 await sharp({create:{width:HW*mountedNames.length,height:HH,channels:4,background:'#00000000'}})
  .composite(mountedNames.map((n,i)=>({input:mountedFrames[n],left:i*HW,top:0}))).png().toFile(path.join(output,'hero_heraldic_mounted.png'));
 geometry.frames=Object.fromEntries(names.map((n,i)=>[n,[(i%columns)*W,Math.floor(i/columns)*H]]));
 geometry.mounted_frames=Object.fromEntries(mountedNames.map((n,i)=>[n,[i*HW,0]]));
 geometry.open_face=OPEN_FACE;
 geometry.rider=RIDER;
 fs.writeFileSync(path.join(geometryOut,'hero_heraldic_geometry.gd'),'extends RefCounted\n## Generated by tools/battle/render_heraldic_hero.cjs from heraldic_source/hero-*.png.\nconst DATA = '+JSON.stringify(geometry,null,'\t')+'\n');
 console.log(`Built hero parts: ${names.length} foot frames, ${mountedNames.length} mounted weapon frames`);
}
main().catch(e=>{console.error(e);process.exitCode=1;});
