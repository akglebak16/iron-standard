/* ================= расчленёнка в бою (только в браузере, на сервере не грузится) =================
   При смерти бойца смотрим, чем его добили (B.hk: 'melee' | 'arrow' | 'charge', B.hdt: тип урона 'cut' | 'pierce' | 'blunt'):
   - рубящим — может слететь голова (летит, крутится, катится; из шеи бьёт фонтан) или отлететь рука;
   - дробящим — голова разлетается вдребезги: кровь, осколки черепа;
   - любой смертью — кровь брызжет по направлению удара, растекается лужа.
   Удары героя игрока кромсают чаще. Скелеты сыплют костями и пылью, мертвецы — тёмной жижей.
   Всё, что упало и успокоилось, впечатывается в землю поля (B.gg), так что поле к концу боя усеяно.
   Выключается в меню паузы («Расчленёнка»). Герой игрока и спутники не расчленяются: они ранены, а не убиты. */
const GORE = { on: true };
try { GORE.on = localStorage.getItem('zs-gore') !== '0'; } catch (e) { }
const GIB_MAX = 70;
function goreCol(t) { const k = t.t.look && t.t.look.undead; return k === 'skel' ? null : k === 'zombie' ? '#3b4a22' : '#8f1a12'; } // null — крови нет (скелет)
function goreInit() { B.gibs = []; B.pools = []; B.spurts = []; }

/* брызги: летят от удара, падают, оставляют пятна на земле */
function goreSpray(x, y, n, ang, sp, col, up) {
  if (B.fx.length > 650) return;
  for (let i = 0; i < n; i++) { const a = ang + rnd(-.7, .7), v = rnd(.3, 1) * sp; B.fx.push({ k: 0, x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v * .5 - rnd(up * .5, up), l: rnd(.3, .65), c: col, s: rnd(1.5, 3.4), b: 1 }); }
}
function goreDust(x, y, n, col) { for (let i = 0; i < n; i++) B.fx.push({ k: 1, x: x + rnd(-8, 8), y: y + rnd(-6, 4), vx: rnd(-30, 30), vy: rnd(-40, -10), l: rnd(.4, .9), c: col, s: rnd(3, 6) }); }
function gorePool(x, y, max, col) { if (col) B.pools.push({ x: x + rnd(-6, 6), y: y + rnd(-2, 5), r: 3, max, col, t: 0, rot: rnd(0, 3) }); }
function gib(o) { if (B.gibs.length >= GIB_MAX) bakeGib(B.gibs.shift()); B.gibs.push(Object.assign({ z: 18, vz: rnd(120, 220), rot: 0, vr: rnd(-14, 14), rest: 0 }, o)); }

/* голова над телом: где она на поле (спрайт рисуется со смещением от ног) */
function headPos(t) { const sp = t.sp, k = US; return { x: t.x + (sp.hc[0] - sp.ax) * k * t.dir, y: t.y + (sp.hc[1] - sp.ay) * k }; }

/* главное: вызывается из kill(). true — тело уже нарисовано здесь, false — рисуй обычный труп */
function goreKill(t, src) {
  if (!GORE.on || !t.sp || (t.isHero && t.side === 0) || t.comp) return false;
  const col = goreCol(t), skel = !col, kind = B.hk || 'melee', dt = B.hdt || 'cut', hero = src && src.isHero && !src.ai, big = t.lh > t.maxHp * .3;
  const ang = src ? Math.atan2(t.y - src.y, t.x - src.x) : rnd(0, TAU), hp = headPos(t), bonus = (hero ? .25 : 0) + (big ? .15 : 0);
  let nohead = false;
  if (kind === 'melee' && dt === 'cut' && Math.random() < .2 + bonus) { // голова с плеч
    nohead = true; gib({ type: 'head', x: hp.x, y: t.y, z: t.y - hp.y, vz: rnd(140, 240), vx: Math.cos(ang) * rnd(60, 150), vy: Math.sin(ang) * rnd(30, 80), cv: headOf(t.sp), hc: t.sp.hc, dir: t.dir, col });
    if (col) { B.spurts.push({ x: hp.x, y: hp.y + 6, t: rnd(.6, 1), ang: ang + Math.PI * .5 * (Math.random() < .5 ? 1 : -1), col }); goreSpray(hp.x, hp.y + 6, 18, ang, 170, col, 160); }
    else goreBones(hp.x, hp.y, ang, 3);
    if (hero) ftext(t.x, t.y - 60, 'Голова с плеч!', '#ff8d79');
  } else if (kind === 'melee' && dt === 'blunt' && Math.random() < .18 + bonus) { // череп вдребезги
    nohead = true; if (col) { goreSpray(hp.x, hp.y, 30, ang, 190, col, 120); goreSpray(hp.x, hp.y, 6, ang, 120, '#e8e0cc', 90); for (let i = 0; i < 3; i++) gib({ type: 'chunk', x: hp.x, y: t.y, z: t.y - hp.y, vz: rnd(60, 160), vx: Math.cos(ang + rnd(-.8, .8)) * rnd(40, 110), vy: Math.sin(ang) * rnd(20, 60), col, s: rnd(2.5, 4) }); }
    goreBones(hp.x, hp.y, ang, skel ? 6 : 3);
    if (hero) ftext(t.x, t.y - 60, 'Всмятку!', '#ff8d79');
  } else if (kind === 'melee' && dt === 'cut' && Math.random() < .16 + bonus * .6) { // рука
    const arm = { type: 'arm', x: t.x, y: t.y, z: 30, vz: rnd(100, 180), vx: Math.cos(ang) * rnd(50, 120), vy: Math.sin(ang) * rnd(20, 70), col, skin: t.sp.v ? t.sp.v.skin : '#d6a179', sleeve: FACTIONS[t.fac] ? FACTIONS[t.fac].c1 : '#555', skel };
    gib(arm); if (col) goreSpray(t.x, t.y - 26, 14, ang, 150, col, 110);
  }
  if (col) { goreSpray(t.x, t.y - 18, kind === 'arrow' ? 6 : 12, ang, kind === 'charge' ? 220 : 140, col, 90); gorePool(t.x, t.y, rnd(16, 26) + (nohead ? 8 : 0), col); }
  else goreDust(t.x, t.y - 10, 6, '#cfc6ad');
  paintBody(t, nohead); return true;
}
function goreBones(x, y, ang, n) { for (let i = 0; i < n; i++) gib({ type: 'bone', x, y: y + 30, z: 30, vz: rnd(80, 180), vx: Math.cos(ang + rnd(-1, 1)) * rnd(40, 120), vy: rnd(-40, 40), s: rnd(4, 7) }); }
/* труп (с головой или без) на землю; лужу рисуют B.pools */
function paintBody(t, nohead) {
  const g = B.gg, sp = corpseOf(t.sp, nohead), k = US, rot = (Math.random() < .5 ? -1 : 1) * rnd(1.2, 1.9);
  fallAdd(sp, t.x, t.y, t.sp.ax, t.sp.ay, rot, k, .9);
}
/* кровь при сильном ударе по живому */
function goreHit(t, d, src) { if (!GORE.on || !t.sp) return; const col = goreCol(t); if (!col || d < t.maxHp * .18) return; const ang = src ? Math.atan2(t.y - src.y, t.x - src.x) : rnd(0, TAU); goreSpray(t.x, t.y - 20, 6 + Math.min(10, d / 6 | 0), ang, 150, col, 80); }

/* шаг: фонтаны, полёт кусков, лужи */
function goreUpdate(dt) {
  if (!B.gibs) return;
  for (let i = B.spurts.length - 1; i >= 0; i--) { const s = B.spurts[i]; s.t -= dt; if (s.t <= 0) { B.spurts.splice(i, 1); continue; } if (B.fx.length < 650) for (let k = 0; k < 2; k++) B.fx.push({ k: 0, x: s.x, y: s.y, vx: Math.cos(s.ang) * rnd(10, 50), vy: -rnd(90, 170) * s.t, l: rnd(.3, .5), c: s.col, s: rnd(1.6, 2.8), b: 1 }); }
  for (let i = B.gibs.length - 1; i >= 0; i--) {
    const b = B.gibs[i]; if (b.rest > 0) { b.rest -= dt; if (b.rest <= 0) { bakeGib(b); B.gibs.splice(i, 1); } continue; }
    b.vz -= 560 * dt; b.z += b.vz * dt; b.x += b.vx * dt; b.y += b.vy * dt; b.rot += b.vr * dt;
    if (b.z <= 0) { b.z = 0; if (b.col && Math.abs(b.vz) > 60 && B.fx.length < 650) goreSpray(b.x, b.y, 3, 0, 40, b.col, 20); b.vz *= -.32; b.vx *= .55; b.vy *= .55; b.vr *= .5; if (Math.abs(b.vz) < 35) { b.vz = 0; b.rest = .25; if (b.col && b.type !== 'chunk') gorePool(b.x, b.y, rnd(6, 11), b.col); } }
  }
  for (let i = B.pools.length - 1; i >= 0; i--) { const p = B.pools[i]; p.t += dt; p.r = Math.min(p.max, p.r + dt * p.max * .5); if (p.t > 2.6) { const g = B.gg; g.fillStyle = p.col; g.globalAlpha = .55; ell(g, p.x, p.y, p.r, p.r * .5); g.fill(); g.globalAlpha = 1; B.pools.splice(i, 1); } }
}
/* капля крови упала на землю: пятно навсегда */
function goreSplat(p) { const g = B.gg; g.globalAlpha = .6; g.fillStyle = p.c; ell(g, p.x, p.y + 14, p.s * .9, p.s * .45); g.fill(); g.globalAlpha = 1; }
function bakeGib(b) { const g = B.gg; g.save(); drawGibAt(g, b, true); g.restore(); }

/* отрисовка: лужи под бойцами, куски поверх */
function goreDrawUnder(g) { if (!B.pools) return; for (const p of B.pools) { g.fillStyle = p.col; g.globalAlpha = .55; ell(g, p.x, p.y, p.r, p.r * .5); g.fill(); } g.globalAlpha = 1; }
function goreDrawOver(g) { if (!B.gibs) return; for (const b of B.gibs) { g.fillStyle = 'rgba(0,0,0,.25)'; ell(g, b.x, b.y, 5, 2); g.fill(); g.save(); drawGibAt(g, b, false); g.restore(); } }
function drawGibAt(g, b, flat) {
  g.translate(b.x, b.y - (flat ? 0 : b.z)); g.rotate(b.rot);
  if (b.type === 'head') { g.scale(b.dir * US, US); g.drawImage(b.cv, -b.hc[0], -b.hc[1]); if (b.col) { g.fillStyle = b.col; ell(g, 0, 22, 9, 4); g.fill(); } return; }
  if (b.type === 'arm') {
    if (b.skel) { g.strokeStyle = '#d8d0b8'; g.lineWidth = 2.4; g.beginPath(); g.moveTo(-7, 0); g.lineTo(7, 0); g.stroke(); ell(g, 7.5, 0, 2, 2); g.fillStyle = '#d8d0b8'; g.fill(); return; }
    g.fillStyle = b.sleeve; g.fillRect(-8, -2.4, 9, 4.8); g.fillStyle = b.skin; g.fillRect(1, -2, 6, 4); ell(g, 8, 0, 2.6, 2.6); g.fill();
    g.fillStyle = b.col; ell(g, -8, 0, 2, 2.6); g.fill(); g.fillStyle = '#efe8d6'; ell(g, -8.5, 0, .9, .9); g.fill(); return;
  }
  if (b.type === 'bone') { g.strokeStyle = '#e2dac4'; g.lineWidth = 1.6; g.beginPath(); g.moveTo(-b.s / 2, 0); g.lineTo(b.s / 2, 0); g.stroke(); g.fillStyle = '#e2dac4'; ell(g, -b.s / 2, 0, 1.2, 1.2); g.fill(); ell(g, b.s / 2, 0, 1.2, 1.2); g.fill(); return; }
  g.fillStyle = b.col; ell(g, 0, 0, b.s, b.s * .7); g.fill(); g.fillStyle = 'rgba(255,220,200,.25)'; ell(g, -b.s * .3, -b.s * .2, b.s * .35, b.s * .25); g.fill(); // кусок
}

/* ================= реплики спутников над головой (пан Глебио и др.: COMP[id].voice в 05e_comps.js) =================
   start — в начале боя, kill / killUndead — когда убил, taunt — время от времени рядом с врагом, hurt — получил сильный удар, down — ранен и вынесен. */
function voiceSay(u, kind, force) {
  const V = u.voice, L = V && (V[kind] || (kind === 'killUndead' ? V.kill : null)); if (!L || !L.length) return;
  if (!force && u.sayCd > 0 && !(kind === 'kill' || kind === 'killUndead') && Math.random() > .3) return;
  if (!force && (kind === 'kill' || kind === 'killUndead') && (u.sayCd > .6 || Math.random() > .5)) return; // реплик вдвое меньше: дольше пауза и не на каждое убийство
  let txt = pick(L); if (L.length > 1 && txt === u.sayLast) txt = pick(L); u.sayLast = txt;
  u.say = { txt, t: kind === 'start' || kind === 'siege' ? 3 : 2.4 }; u.sayCd = kind === 'kill' || kind === 'killUndead' ? 3.2 : 6;
  if (kind === 'start' || kind === 'siege' || kind === 'down') blog(u.name + ': «' + txt + '»', kind === 'down' ? 1 : 2);
}
/* Глебио и Захарий влюблены и флиртуют, пока оба на поле: реплика одного и через пару секунд ответ второго. Где-то раз в 20–30 секунд боя. */
const BANTER = [
  ['g', 'Захарка, ты сегодня красивый… для идиота!', 'Хы хы, а ты красный, Глебушка! Ты чего, влюбился?!'],
  ['z', 'Глебушка, давай после боя в Полоцк? Там лужа есть. Романтика!', 'Курва, Захарка… ну давай. Только никому, бля!'],
  ['g', 'Держись рядом, красавчик, я тебя прикрою!', 'Я пукнул! Это тебе от всего сердца!'],
  ['z', 'Глебушка, ты как Головка: такой же твёрдый!', 'Ёб твою мать, Захарка, да ты поэт… я таю.'],
  ['g', 'Твоя дубина шляхетнее всего, что я видел, пупсик!', 'Глебушка назвал меня пупсиком! Хочу домой, жениться!'],
  ['z', 'Глебушка, я тебе цветочек принёс. Это, ну, репейник.', 'Лучший букет в моей жизни, сука, я щас заплачу!'],
  ['g', 'Захарка, смотри на меня, а не на врагов!', 'А я и смотрю! Ой, меня бьют!'],
  ['z', 'Мамка сказала: найди шляхтича. Я нашёл!', 'Передай мамке: я согласен, курва!']
];
const BANTER_DOWN = { glebio: ['Глебушка! Ты чего лёг?! Я тебе пирог принесу!', 'Глебушка, вставай, я не умею без тебя!'], zahariy: ['Захарка, не смей помирать, я тебе ещё не сказал, курва!', 'Захарка, ёб твою мать, держись!'] };
function banterUnit(id) { return B.units.find(x => x.comp === id && x.side === 0 && !x.dead && !x.gone && x.voice); }
function banterSay(u, txt) { u.say = { txt, t: 3 }; u.sayCd = 4; blog(u.name + ': «' + txt + '»', 2); }
function banterDown(t) { // один упал: второй переживает
  if (!B || !t.comp || !BANTER_DOWN[t.comp]) return; const o = banterUnit(t.comp === 'glebio' ? 'zahariy' : 'glebio'); if (!o) return;
  B.banR = { t: 1.3, u: o, txt: pick(BANTER_DOWN[t.comp]) };
}
function banterUpdate(dt) {
  if (B.banR && (B.banR.t -= dt) <= 0) { const r = B.banR; B.banR = null; if (!r.u.dead && !r.u.gone) banterSay(r.u, r.txt); }
  if (B.banT === undefined) B.banT = rnd(9, 14); if ((B.banT -= dt) > 0 || B.banR) return;
  const g = banterUnit('glebio'), z = banterUnit('zahariy'); if (!g || !z || g.say || z.say) { B.banT = 3; return; }
  B.banT = rnd(20, 32); let b; do b = pick(BANTER); while (b === B.banLast); B.banLast = b; const a = b[0] === 'g' ? g : z, o = a === g ? z : g; banterSay(a, b[1]); B.banR = { t: 3.2, u: o, txt: b[2] };
}
function voiceUpdate(dt) {
  banterUpdate(dt);
  for (const u of B.units) {
    if (!u.voice) continue; if (u.say && (u.say.t -= dt) <= 0) u.say = null; if (u.dead || u.gone) continue; u.sayCd -= dt;
    if (u.sayStart > 0 && (u.sayStart -= dt) <= 0) voiceSay(u, B.wall && u.voice.siege ? 'siege' : 'start', true);
    if ((u.tauntT -= dt) <= 0) { u.tauntT = rnd(24, 40); if (nearestFoeDist(u.x, u.y, 1 - u.side) < 260) voiceSay(u, 'taunt'); }
  }
}
function voiceDraw(g) {
  g.font = '700 13px "Alegreya Sans","Alegreya Sans SC",sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
  for (const u of B.units) {
    if (!u.say) continue; const s = u.say, a = clamp(s.t / .3, 0, 1), w = g.measureText(s.txt).width + 14, h = 20, x = u.x, y = u.y - (u.sp && u.sp.m ? 98 : 78) - (u.dead ? -40 : 0);
    g.globalAlpha = a; g.fillStyle = '#f3e8c9'; g.strokeStyle = '#1b130c'; g.lineWidth = 1.6;
    g.beginPath(); g.moveTo(x - w / 2 + 4, y - h / 2); g.lineTo(x + w / 2 - 4, y - h / 2); g.quadraticCurveTo(x + w / 2, y - h / 2, x + w / 2, y - h / 2 + 4); g.lineTo(x + w / 2, y + h / 2 - 4); g.quadraticCurveTo(x + w / 2, y + h / 2, x + w / 2 - 4, y + h / 2);
    g.lineTo(x + 6, y + h / 2); g.lineTo(x - 2, y + h / 2 + 8); g.lineTo(x - 2, y + h / 2); g.lineTo(x - w / 2 + 4, y + h / 2); g.quadraticCurveTo(x - w / 2, y + h / 2, x - w / 2, y + h / 2 - 4); g.lineTo(x - w / 2, y - h / 2 + 4); g.quadraticCurveTo(x - w / 2, y - h / 2, x - w / 2 + 4, y - h / 2); g.closePath(); g.fill(); g.stroke();
    g.fillStyle = /[А-ЯЁ]{4,}|!$/.test(s.txt) ? '#8f1a12' : '#2a1a0e'; g.fillText(s.txt, x, y + 1);
  }
  g.globalAlpha = 1; g.textBaseline = 'alphabetic';
}
