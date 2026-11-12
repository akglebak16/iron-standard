/* ================= звук (процедурный) ================= */
const AU = { ctx: null, master: null, on: true, last: {}, noiseBuf: null, music: true, mg: null, mt: 0 };
function auInit() {
  if (AU.ctx) { if (AU.ctx.state === 'suspended') AU.ctx.resume(); return; }
  try {
    const C = window.AudioContext || window.webkitAudioContext; if (!C) return; AU.ctx = new C();
    AU.master = AU.ctx.createGain(); AU.master.gain.value = .55; AU.master.connect(AU.ctx.destination);
    const n = AU.ctx.sampleRate, b = AU.ctx.createBuffer(1, n, n), d = b.getChannelData(0); for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1; AU.noiseBuf = b;
    AU.mg = AU.ctx.createGain(); AU.mg.gain.value = AU.music ? .5 : 0; AU.mg.connect(AU.master);
    const dl = AU.ctx.createDelay(1); dl.delayTime.value = .38; const fb = AU.ctx.createGain(); fb.gain.value = .45; dl.connect(fb); fb.connect(dl); AU.mg.connect(dl); dl.connect(AU.master);
  } catch (e) { AU.ctx = null; }
}
function auSetOn(v) { AU.on = v; if (AU.master) AU.master.gain.value = v ? .55 : 0; }
function auSetMusic(v) { AU.music = v; if (AU.mg) AU.mg.gain.value = v ? .5 : 0; }
function tone(f0, f1, dur, type, vol, delay) {
  const c = AU.ctx, t = c.currentTime + (delay || 0), o = c.createOscillator(), g = c.createGain(); o.type = type || 'sine'; o.frequency.setValueAtTime(f0, t); if (f1) o.frequency.exponentialRampToValueAtTime(f1, t + dur);
  g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(vol, t + .006); g.gain.exponentialRampToValueAtTime(.0001, t + dur); o.connect(g); g.connect(AU.master); o.start(t); o.stop(t + dur + .02);
}
function noise(dur, ft, f0, f1, vol, q) {
  const c = AU.ctx, t = c.currentTime, s = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain(); s.buffer = AU.noiseBuf; s.loop = true; f.type = ft; f.frequency.setValueAtTime(f0, t); if (f1) f.frequency.exponentialRampToValueAtTime(f1, t + dur); f.Q.value = q || 1;
  g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(.0001, t + dur); s.connect(f); f.connect(g); g.connect(AU.master); s.start(t, Math.random()); s.stop(t + dur + .02);
}
const SFX_MIN = { hit: .05, clang: .06, bow: .05, arrowhit: .05, death: .08, thud: .1, swing: .08, thunk: .06 };
function sfx(name, u) {
  if (!AU.ctx || !AU.on) return; const now = AU.ctx.currentTime, mn = SFX_MIN[name] || 0; if (AU.last[name] && now - AU.last[name] < mn) return;
  let v = 1; if (u && B) { const d = Math.hypot(u.x - B.cam.x, u.y - B.cam.y); v = clamp(1.15 - d / 900, .06, 1); if (u === B.hero) v = 1; } AU.last[name] = now;
  switch (name) {
    case 'hit': noise(.09, 'lowpass', 1400, 300, .55 * v); tone(130, 60, .12, 'sine', .5 * v); break;
    case 'clang': tone(1900 + Math.random() * 400, 0, .2, 'triangle', .22 * v); tone(2900, 0, .12, 'square', .05 * v); noise(.05, 'highpass', 3000, 0, .25 * v); break;
    case 'swing': noise(.14, 'bandpass', 500, 1800, .25, 2); break;
    case 'bow': noise(.07, 'highpass', 2500, 900, .22 * v); tone(240, 120, .07, 'triangle', .1 * v); break;
    case 'arrowhit': noise(.05, 'lowpass', 1800, 400, .4 * v); tone(220, 110, .08, 'sine', .3 * v); break;
    case 'thunk': tone(160, 90, .07, 'square', .12 * v); break;
    case 'death': tone(170, 55, .3, 'sawtooth', .13 * v); noise(.18, 'lowpass', 700, 150, .25 * v); break;
    case 'thud': tone(80, 40, .2, 'sine', .7 * v); noise(.14, 'lowpass', 500, 120, .5 * v); break;
    case 'order': tone(392, 0, .09, 'triangle', .18); tone(523, 0, .12, 'triangle', .18, .08); break;
    case 'click': tone(660, 440, .05, 'square', .06); break;
    case 'coin': tone(1320, 0, .08, 'triangle', .14); tone(1760, 0, .18, 'triangle', .14, .07); break;
    case 'horn': case 'horn2': { const f = name === 'horn' ? 146 : 110, c = AU.ctx, t = c.currentTime; for (const k of [1, 1.005, 2.01]) { const o = c.createOscillator(), g = c.createGain(), fl = c.createBiquadFilter(); o.type = 'sawtooth'; o.frequency.setValueAtTime(f * k * .96, t); o.frequency.linearRampToValueAtTime(f * k, t + .35); fl.type = 'lowpass'; fl.frequency.value = 900; g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(.11 / k, t + .18); g.gain.setValueAtTime(.11 / k, t + 1); g.gain.exponentialRampToValueAtTime(.0001, t + 1.7); o.connect(fl); fl.connect(g); g.connect(AU.master); o.start(t); o.stop(t + 1.8); } break; }
    case 'level': tone(392, 0, .2, 'triangle', .2); tone(523, 0, .2, 'triangle', .2, .15); tone(659, 0, .4, 'triangle', .2, .3); break;
  }
}
const SCALE = [146.83, 164.81, 174.61, 196, 220, 246.94, 261.63, 293.66, 349.23]; // D дорийский
function musicTick(dt, mode) {
  if (!AU.ctx || !AU.music || !AU.on) return; AU.mt -= dt; if (AU.mt > 0) return;
  const bt = mode === 'battle' ? .5 : 1.6; AU.mt = bt * (.8 + Math.random() * .7); const c = AU.ctx, t = c.currentTime;
  const f = SCALE[Math.floor(Math.random() * (mode === 'battle' ? 6 : SCALE.length))] * (Math.random() < .25 ? .5 : 1);
  const o = c.createOscillator(), g = c.createGain(), fl = c.createBiquadFilter(); o.type = mode === 'battle' ? 'sawtooth' : 'triangle'; o.frequency.value = f; fl.type = 'lowpass'; fl.frequency.value = mode === 'battle' ? 500 : 900;
  g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(mode === 'battle' ? .06 : .09, t + .04); g.gain.exponentialRampToValueAtTime(.0001, t + (mode === 'battle' ? .9 : 2.6)); o.connect(fl); fl.connect(g); g.connect(AU.mg); o.start(t); o.stop(t + 3);
  if (mode !== 'battle' && Math.random() < .4) { const d = c.createOscillator(), dg = c.createGain(); d.type = 'sine'; d.frequency.value = 73.4; dg.gain.setValueAtTime(0, t); dg.gain.linearRampToValueAtTime(.1, t + .8); dg.gain.exponentialRampToValueAtTime(.0001, t + 4); d.connect(dg); dg.connect(AU.mg); d.start(t); d.stop(t + 4.2); }
  if (mode === 'battle' && Math.random() < .5) { const t2 = c.currentTime; const o2 = c.createOscillator(), g2 = c.createGain(); o2.type = 'sine'; o2.frequency.setValueAtTime(90, t2); o2.frequency.exponentialRampToValueAtTime(40, t2 + .25); g2.gain.setValueAtTime(.35, t2); g2.gain.exponentialRampToValueAtTime(.0001, t2 + .3); o2.connect(g2); g2.connect(AU.mg); o2.start(t2); o2.stop(t2 + .35); }
}
