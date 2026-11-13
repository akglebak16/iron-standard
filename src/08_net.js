/* ================= сетевая игра на двоих: клиентская часть =================
   Клиент — «зеркало»: рисует то, что присылает сервер, и отправляет команды. */
NET.send = function (o) { if (NET.ws && NET.ws.readyState === 1) NET.ws.send(JSON.stringify(o)); };
NET.chat = [];
function netProbe() {
  try { if (location.protocol.indexOf('http') !== 0) return; fetch('/health', { cache: 'no-store' }).then(r => r.text()).then(t => { if (t === 'ok') { NET.avail = true; if (MODE === 'title') buildTitleMenu(); } }).catch(() => { }); } catch (e) { }
}
function netStart(o) {
  MODE = 'loading'; B = null; el('title').hidden = true; showLoad(true);
  NET.on = true; NET.q = []; NET.vote = null; NET.chat = []; NET.err = null; NET.lastLog = ''; NET.bt = 0; NET.bid = 0;
  const ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host); NET.ws = ws;
  ws.onopen = () => NET.send(Object.assign({ t: 'join' }, o));
  ws.onmessage = e => { let m; try { m = JSON.parse(e.data); } catch (x) { return; } try { netMsg(m); } catch (x) { console.error(x); } };
  ws.onclose = () => { if (NET.ws === ws) netLost(); };
  el('chat').hidden = false; netChatDraw();
}
function netLeave() { const ws = NET.ws; NET.on = false; NET.ws = null; if (ws) try { ws.close(); } catch (e) { } el('chat').hidden = true; el('votebar').hidden = true; G = null; B = null; }
function netLost() { if (!NET.on) return; const msg = NET.err || 'Соединение потеряно'; NET.on = false; NET.ws = null; showLoad(false); closeModal(); el('chat').hidden = true; el('votebar').hidden = true; G = null; B = null; gotoTitle(); toast(msg); }
function netDefer(f) { if (MODE === 'loading' || !G) NET.q.push(f); else f(); }
function netFlush() { const q = NET.q; NET.q = []; for (const f of q) try { f(); } catch (e) { console.error(e); } }
function netMkPlayer(id) {
  return { id, x: 0, y: 0, tx: 0, ty: 0, fx: 1, path: [], pi: 0, troops: [], gold: 0, food: 0, tid: null, sid: null, in: null, busy: null, name: '', culture: 'nord', banner: 0, log: [], logDirty: true, quests: [], rel: { nord: 0, emp: 0, khan: 0, bandit: -100 }, stats: { wins: 0, kills: 0 }, first: true,
    hero: { name: '', lvl: 1, xp: 0, pts: 0, str: 1, vit: 1, agi: 1, lead: 1, armor: 0, weapon: 0, shield: 0, horse: 0, hp: 1, seed: id * 7 + 3 } };
}
function netFac(Q) { const k = 'p2_' + Q.banner; if (!FACTIONS[k]) { const b = BANNERS[Q.banner] || BANNERS[0]; FACTIONS[k] = Object.assign({}, FACTIONS.player, { c1: b.c1, c2: b.c2 }); } return k; }
function netRefresh() { if (!UI.open || UI.enc || UI.res) return; keepScroll(() => { if (UI.panel) renderPanel(); else if (UI.town) renderTown(); }); }

function netMsg(m) {
  switch (m.t) {
    case 'err': NET.err = m.s; try { NET.ws.close(); } catch (e) { } netLost(); break;
    case 'init': {
      G = { seed: m.seed, day: 1, hour: 8, hourAcc: 0, paused: false, speed: 1, parties: [], settles: m.settles.map(s => Object.assign(s, { recruits: [], board: [], camp: null, cleared: false })), roads: m.roads, players: [], player: null, log: [], nid: 1, stats: { wins: 0, kills: 0 }, wait: false };
      genWorld(m.seed); markRoads();
      const P = netMkPlayer(m.you); G.players.push(P); G.player = P; NET.you = m.you; enterWorld(); break;
    }
    case 'me': {
      const P = G && G.player; if (!P) break;
      const old = JSON.stringify([P.gold, P.food, P.troops, P.hero, P.quests, P.inv, P.fac, P.finv]); P.inv = m.inv;
      P.gold = m.gold; P.food = m.food; P.troops = m.troops; P.hero = m.hero; P.quests = m.quests; P.rel = m.rel; P.stats = m.stats; P.name = m.name; P.culture = m.culture; P.banner = m.banner; P.in = m.in; P.busy = m.busy; P.fac = m.fac; P.finv = m.finv; P.fname = m.fac ? m.fac.name : '';
      const lg = JSON.stringify(m.log); if (lg !== NET.lastLog) { NET.lastLog = lg; P.log = m.log; P.logDirty = true; }
      P.path = m.path.map(a => ({ x: a[0], y: a[1] })); P.pi = 0;
      const b = BANNERS[P.banner]; FACTIONS.player.c1 = b.c1; FACTIONS.player.c2 = b.c2;
      if (JSON.stringify([P.gold, P.food, P.troops, P.hero, P.quests, P.inv, P.fac, P.finv]) !== old) { netRefresh(); netInvite(); }
      break;
    }
    case 'w': {
      if (!G) break; G.day = m.day; G.hour = m.hour; G.hourAcc = m.hf; G.paused = m.paused; G.speed = m.speed; NET.vote = m.vote;
      const seen = {};
      for (const a of m.players) {
        seen[a[0]] = 1; let Q = G.players.find(q => q.id === a[0]); if (!Q) { Q = netMkPlayer(a[0]); G.players.push(Q); }
        Q.tx = a[2]; Q.ty = a[3]; if (Q.first) { Q.x = Q.tx; Q.y = Q.ty; Q.first = false; } Q.fx = a[4];
        if (Q.id !== NET.you) { Q.name = a[1]; Q.banner = a[5]; Q.culture = a[6]; Q.in = a[7] ? 1 : 0; Q.busy = a[8] ? 'x' : null; Q.troops = [{ type: a[10], n: a[9] }]; Q.hero.horse = a[11]; Q.hero.name = a[1]; Q.fname = a[12] || ''; Q.bid = a[13] || 0; }
      }
      G.players = G.players.filter(q => q.id === NET.you || seen[q.id]);
      const old = new Map(G.parties.map(p => [p.id, p])), next = [];
      for (const a of m.parties) {
        let p = old.get(a[0]); if (!p) p = { id: a[0], x: a[3], y: a[4], path: [], pi: 0, hide: false, cd: 0 };
        p.kind = a[1]; p.fac = a[2]; p.tx = a[3]; p.ty = a[4]; p.fx = a[5]; p.name = a[6]; p.troops = a[7].map(s => ({ type: s[0], n: s[1] })); p.lock = a[8]; next.push(p);
      }
      G.parties = next;
      for (const c of m.camps) { const s = G.settles.find(s => s.id === c[0]); if (s) { s.camp = c[1] ? G.parties.find(p => p.id === c[1]) || null : null; s.cleared = !!c[2]; } }
      break;
    }
    case 'town': {
      const s = G && G.settles.find(s => s.id === m.sid); if (!s) break; s.recruits = m.recruits; s.board = m.board; if (m.market) s.market = m.market;
      if (m.open) netDefer(() => { G.player.in = null; closeModal(); G.player.in = s.id; G.wait = false; UI.town = { s, tab: 'recruit' }; sfx('click'); renderTown(); });
      else if (UI.town && UI.town.s === s && UI.open && !UI.panel) keepScroll(renderTown);
      break;
    }
    case 'enc': netDefer(() => { const p = G.parties.find(x => x.id === m.p.id) || m.p; p.troops = m.p.troops; closeModal(); openEncounter(p, m.forced); }); break;
    case 'bs': netDefer(() => { closeModal(); auInit(); NET.bid = m.id; NET.ik = ''; NET.it = 0; enterBattle(Object.assign({}, m.cfg), m.coop); }); break;
    case 'bj': if (B && !B.cfg.demo) { joinBattle(m.coop); buildBattleHud(); } break;
    case 'b': netSnap(m); break;
    case 'br': netDefer(() => { closeModal(); UI.res = m.r; showResult(m.r, null); }); break;
    case 'toast': toast(m.s); break;
    case 'chat': NET.chat.push({ from: m.from, txt: m.txt }); if (NET.chat.length > 30) NET.chat.shift(); netChatDraw(); break;
  }
}

/* ---------- карта мира ---------- */
function netWorldClick(w) {
  const P = G.player; if (P.busy || P.in) return; WC.free = false; auInit();
  let tp = null, bd = 34; for (const p of G.parties) { if (p.hide) continue; const d = Math.hypot(p.x - w.x, p.y - w.y); if (d < bd) { bd = d; tp = p; } }
  if (tp) { NET.send({ t: 'goT', id: tp.id }); return; }
  let ts = null; bd = 50; for (const s of G.settles) { const d = Math.hypot(s.x - w.x, s.y - w.y); if (d < bd) { bd = d; ts = s; } }
  if (ts && ts.kind === 'camp') { if (ts.camp) NET.send({ t: 'goT', id: ts.camp.id }); else toast('Логово пусто'); return; }
  if (ts) { NET.send({ t: 'goS', id: ts.id }); return; }
  NET.send({ t: 'go', x: clamp(w.x, 10, WW - 10), y: clamp(w.y, 10, WH - 10) });
}
function netSmooth(dt) {
  const k = Math.min(1, dt * 9);
  const sm = e => { if (e.tx === undefined) return; const dx = e.tx - e.x, dy = e.ty - e.y; if (dx * dx + dy * dy > 90000) { e.x = e.tx; e.y = e.ty; } else { e.x += dx * k; e.y += dy * k; } };
  for (const q of G.players) sm(q); for (const p of G.parties) sm(p);
}
function netWorldUpdate(dt) {
  if (!G) return; if (NET.bt) { NET.bt = 0; el('chat').classList.remove('bt'); } netSmooth(dt); const P = G.player;
  while (P.pi < P.path.length && Math.hypot(P.path[P.pi].x - P.x, P.path[P.pi].y - P.y) < 14) P.pi++;
  if (!WC.free) { WC.x += (P.x - WC.x) * Math.min(1, dt * 5); WC.y += (P.y - WC.y) * Math.min(1, dt * 5); }
  const hw = VIEW.w / 2 / WC.z, hh = VIEW.h / 2 / WC.z; WC.x = hw * 2 >= WW ? WW / 2 : clamp(WC.x, hw, WW - hw); WC.y = hh * 2 >= WH ? WH / 2 : clamp(WC.y, hh, WH - hh);
}

/* ---------- бой (зеркало) ---------- */
function netSnap(m) {
  if (!B || NET.bid !== m.id || B.cfg.demo) return;
  B.t = m.tm;
  for (let i = 0; i < m.u.length; i++) {
    const a = m.u[i], u = B.units[i]; if (!u) continue;
    if (a.length === 1) { if ((a[0] & 1) && !u.dead) { u.dead = true; u.hp = 0; paintCorpse(u); } if (a[0] & 4) u.gone = true; continue; }
    u.tx = a[0]; u.ty = a[1]; if (!u.nx) { u.x = u.tx; u.y = u.ty; u.nx = 1; }
    u.vx = a[2]; u.vy = a[3]; u.face = a[4]; u.hp = a[5]; const f = a[6]; u.flee = !!(f & 2); u.blocking = !!(f & 8); if (u.isHero) u.ai = !!(f & 16); if (f & 32) u.flash = .1; u.swing = a[7]; u.bump = a[8];
  }
  if (m.h && B.hero) { const h = B.hero; h.hp = m.h.hp; h.maxHp = m.h.mhp; h.stam = m.h.st; h.swingA = m.h.sa; B.heroDown = !!m.h.down; }
  for (const e of m.ev) {
    switch (e[0]) {
      case 'h': { const u = B.units[e[1]]; if (u) { u.flash = .13; fxBlood(u.x, u.y - 16, 4); if (u === B.hero) B.shake = .18; } break; }
      case 'k': { const u = B.units[e[1]]; if (u && !u.dead) { u.dead = true; u.hp = 0; if (!goreKill(u, null)) paintCorpse(u); fxBlood(u.x, u.y - 14, 12); } break; }
      case 'a': B.arrows.push({ x0: e[1], y0: e[2], x1: e[3], y1: e[4], t: 0, dur: e[5], side: e[6], xb: e[7], dmg: 0 }); break;
      case 'b': fxSpark(e[1], e[2]); break;
      case 'd': fxDust(e[1], e[2]); break;
      case 't': ftext(e[1], e[2], e[3], e[4]); break;
      case 'l': blog(e[1], e[2]); break;
      case 's': sfx(e[1], B.units[e[2]] || undefined); break;
    }
  }
  if (m.over && !B.over) { B.over = B.t; B.win = !!m.win; }
  B.hudDirty = true;
}
function netBattleUpdate(dt) {
  if (!B) return; if (!NET.bt) { NET.bt = 1; el('chat').classList.add('bt'); } B.paused = false; B.speed = 1; dt = Math.min(dt, .1); B.t += dt;
  const k = Math.min(1, dt * 14);
  for (const u of B.units) {
    if (u.dead || u.gone) continue;
    if (u.tx !== undefined) { u.x += (u.tx - u.x) * k; u.y += (u.ty - u.y) * k; }
    u.flash -= dt; if (u.bump > 0) u.bump = Math.max(0, u.bump - dt * 4.2); if (u.swing > 0) u.swing -= dt;
    const c = Math.cos(u.face); if (c > .25) u.dir = 1; else if (c < -.25) u.dir = -1;
  }
  for (let i = B.arrows.length - 1; i >= 0; i--) { const a = B.arrows[i]; a.t += dt; if (a.t >= a.dur) B.arrows.splice(i, 1); }
  for (let i = B.fx.length - 1; i >= 0; i--) { const p = B.fx[i]; p.l -= dt; if (p.l <= 0) { B.fx.splice(i, 1); continue; } p.x += p.vx * dt; p.y += p.vy * dt; if (!p.k) p.vy += 260 * dt; }
  for (let i = B.texts.length - 1; i >= 0; i--) { const p = B.texts[i]; p.l -= dt; p.y -= 26 * dt; if (p.l <= 0) B.texts.splice(i, 1); }
  // ввод героя
  readHeroInput(); const h = B.hero;
  if (h && h.inp && !B.heroDown && !B.over && !UI.open) {
    const I = h.inp, key = [I.dx, I.dy, I.atk, I.blk, I.spr, Math.round((I.face || 0) * 25)].join();
    NET.it -= dt; if ((key !== NET.ik && NET.it <= 0) || NET.it < -.25) { NET.ik = key; NET.it = .05; NET.send({ t: 'inp', dx: I.dx, dy: I.dy, face: I.face, atk: I.atk, blk: I.blk, spr: I.spr }); }
  }
  battleCamera(dt);
}

/* ---------- голосование и чат ---------- */
function netVoteUI() {
  const v = el('votebar'); if (!v) return; if (!NET.on || !NET.vote) { if (!v.hidden) { v.hidden = true; v.dataset.s = ''; } return; }
  const x = NET.vote, what = x.k === 'pause' ? (x.v ? 'пауза' : 'снять паузу') : 'скорость ×' + x.v, mine = G && G.player && x.by === G.player.name;
  const html = '<span><b>' + x.by.replace(/</g, '&lt;') + '</b> предлагает: ' + what + '</span>' + (mine ? '<span class="note">ждём ответа друга…</span>' : '<button class="btn sm pri" data-act="vyes">Да</button><button class="btn sm" data-act="vno">Нет</button>');
  if (v.dataset.s !== html) { v.dataset.s = html; v.innerHTML = html; } v.hidden = false;
}
function netChatDraw() {
  const l = el('chatlog'); if (!l) return; l.innerHTML = NET.chat.slice(-7).map(c => c.from ? '<div><b>' + c.from.replace(/</g, '&lt;') + ':</b> ' + c.txt.replace(/</g, '&lt;') + '</div>' : '<div><i>' + c.txt.replace(/</g, '&lt;') + '</i></div>').join('');
}
function netKey(e) {
  if (e.target && e.target.id === 'chatin') {
    if (e.code === 'Enter') { const i = e.target, t = i.value.trim(); if (t) NET.send({ t: 'chat', txt: t }); i.value = ''; i.blur(); } else if (e.code === 'Escape') { e.target.value = ''; e.target.blur(); }
    return true;
  }
  if (NET.on && e.code === 'Enter' && !UI.open && (MODE === 'world' || MODE === 'battle')) { el('chatin').focus(); e.preventDefault(); return true; }
  return false;
}
