const fs=require('fs'),path=require('path');
const {createCanvas,loadImage}=require('@napi-rs/canvas');
const {GIFEncoder,quantize,applyPalette}=require('gifenc');
const [jsDir,nativeDir,outDir]=process.argv.slice(2); if(!outDir) throw Error('Usage: node compare_motion.cjs <js-directory> <native-directory> <output-directory>'); fs.mkdirSync(outDir,{recursive:true});
(async()=>{
 const canvas=createCanvas(960,880),ctx=canvas.getContext('2d'),gif=GIFEncoder();
 let pixels=0,error=0,different=0;
 for(let f=0;f<60;f++){
  const name=`frame_${String(f).padStart(3,'0')}.png`;
  const js=await loadImage(path.join(jsDir,name));
  const native=await loadImage(path.join(nativeDir,name));
  ctx.drawImage(js,0,0);ctx.drawImage(native,0,0,960,440,0,440,960,440);
  const data=ctx.getImageData(0,0,960,880).data;
  for(const ybase of [180,390])for(const xbase of [120,360,600,840])for(let y=ybase-110;y<ybase+8;y++)for(let x=xbase-70;x<xbase+70;x++){
   const a=(y*960+x)*4,b=((y+440)*960+x)*4;
   const fg=[0,1,2].some(k=>Math.abs(data[a+k]-[24,21,16][k])>10||Math.abs(data[b+k]-[24,21,16][k])>10);
   if(!fg)continue;
   const delta=Math.max(...[0,1,2].map(k=>Math.abs(data[a+k]-data[b+k])));
   pixels++;error+=delta;if(delta>16)different++;
  }
  const palette=quantize(data,256);gif.writeFrame(applyPalette(data,palette),960,880,{palette,delay:f%3===0?40:30});
  if(f===3)fs.writeFileSync(path.join(outDir,'animations-comparison.png'),canvas.toBuffer('image/png'));
 }
 gif.finish();fs.writeFileSync(path.join(outDir,'animations-comparison.gif'),gif.bytes());
 const result={frames:60,cases:8,foreground_pixels:pixels,mean_max_channel_error:error/pixels,over_16_percent:different/pixels*100};
 fs.writeFileSync(path.join(outDir,'animation-metric.json'),JSON.stringify(result,null,2));console.log(result);
})().catch(e=>{console.error(e);process.exit(1)});
