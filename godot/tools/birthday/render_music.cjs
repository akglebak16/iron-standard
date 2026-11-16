// Authoring only: own music-box arrangement of the traditional birthday melody.
const fs = require('node:fs'), path = require('node:path');
const rate=22050, beat=.38;
const notes=[[67,.75],[67,.25],[69,1],[67,1],[72,1],[71,2],[0,.5],[67,.75],[67,.25],[69,1],[67,1],[74,1],[72,2],[0,.5],[67,.75],[67,.25],[79,1],[76,1],[72,1],[71,1],[69,1],[0,.5],[77,.75],[77,.25],[76,1],[72,1],[74,1],[72,2],[0,4]];
const count=Math.ceil(notes.reduce((n,x)=>n+x[1]*beat,0)*rate), samples=new Float64Array(count);
let time=0;
for(const [midi,beats] of notes){const start=Math.round(time*rate), length=Math.round(beats*beat*rate);time+=beats*beat;if(!midi)continue;
const hz=440*2**((midi-69)/12);
for(let i=0;i<Math.min(length+rate*.35,count-start);i++){const t=i/rate, attack=Math.min(1,t/.008), release=Math.min(1,Math.max(0,(length/rate+.25-t)/.25));const bell=(Math.sin(2*Math.PI*hz*t)*Math.exp(-t*3.2)+.22*Math.sin(2*Math.PI*hz*2*t)*Math.exp(-t*6)+.06*Math.sin(2*Math.PI*hz*3*t)*Math.exp(-t*9));samples[start+i]+=.55*attack*release*bell;}
}
const data=Buffer.alloc(count*2);for(let i=0;i<count;i++)data.writeInt16LE(Math.round(Math.max(-1,Math.min(1,samples[i]))*32767),i*2);
const header=Buffer.alloc(44);header.write('RIFF');header.writeUInt32LE(36+data.length,4);header.write('WAVEfmt ',8);header.writeUInt32LE(16,16);header.writeUInt16LE(1,20);header.writeUInt16LE(1,22);header.writeUInt32LE(rate,24);header.writeUInt32LE(rate*2,28);header.writeUInt16LE(2,32);header.writeUInt16LE(16,34);header.write('data',36);header.writeUInt32LE(data.length,40);
fs.writeFileSync(path.join(__dirname,'../../apps/godot/presentation/birthday/happy_birthday.wav'),Buffer.concat([header,data]));console.log(`Birthday music: ${(count/rate).toFixed(1)} s`);
