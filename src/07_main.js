/* ================= главный цикл ================= */
let MODE = 'title', cv, cx;
const WC = { x: WW / 2, y: WH / 2, z: .9, free: false };
const SAVE_KEY = 'zhelezny-styag-save-2';
function resize() { const d = Math.min(window.devicePixelRatio || 1, 2); VIEW.w = (cv && cv.clientWidth) || window.innerWidth; VIEW.h = (cv && cv.clientHeight) || window.innerHeight; VIEW.dpr = d; cv.width = Math.round(VIEW.w * d); cv.height = Math.round(VIEW.h * d); }
function w2s(x, y) { return { x: (x - WC.x) * WC.z + VIEW.w / 2, y: (y - WC.y) * WC.z + VIEW.h / 2 }; }
function s2wW(sx, sy) { return { x: WC.x + (sx - VIEW.w / 2) / WC.z, y: WC.y + (sy - VIEW.h / 2) / WC.z }; }

/* ---------- сохранение ---------- */
function markRoads() { WT.road.fill(0); for (const seg of G.roads) for (let i = 0; i < seg.length - 1; i++) { const n = Math.ceil(Math.hypot(seg[i + 1].x - seg[i].x, seg[i + 1].y - seg[i].y) / 8); for (let k = 0; k <= n; k++) WT.road[cellOf(lerp(seg[i].x, seg[i + 1].x, k / n), lerp(seg[i].y, seg[i + 1].y, k / n))] = 1; } }
function saveGame(silent) { if (!G || MODE !== 'world' || NET.on) return; try { const copy = Object.assign({}, G, { settles: G.settles.map(s => Object.assign({}, s, { camp: s.camp ? s.camp.id : null })), logDirty: false, player: null, players: G.players.map(P => Object.assign({}, P, { in: null })) }); localStorage.setItem(SAVE_KEY, JSON.stringify(copy)); } catch (e) { if (!silent) toast('Не удалось сохранить'); } }
function hasSave() { try { return !!localStorage.getItem(SAVE_KEY); } catch (e) { return false; } }
function loadGame() {
  let raw; try { raw = localStorage.getItem(SAVE_KEY); } catch (e) { } if (!raw) return toast('Сохранения нет');
  try { const d = JSON.parse(raw); G = d; if (d.rv === undefined) d.rv = 0; genWorld(d.seed); for (const s of G.settles) s.camp = s.camp ? G.parties.find(p => p.id === s.camp) || null : null; markRoads(); G.player = G.players[0]; const b = BANNERS[G.player.banner]; FACTIONS.player.c1 = b.c1; FACTIONS.player.c2 = b.c2; closeModal(); enterWorld(); } catch (e) { console.error(e); toast('Сохранение повреждено'); }
}
function showLoad(on) { el('load').hidden = !on; }
function startNew(o) { MODE = 'loading'; B = null; el('title').hidden = true; showLoad(true); setTimeout(() => { newGame(o); enterWorld(); }, 30); }
function enterWorld() {
  MODE = 'loading'; B = null; showLoad(true); setTimeout(() => {
    WT.img = paintTerrain(); MODE = 'world'; B = null; const P = G.player; WC.x = P.x; WC.y = P.y; WC.z = clamp(VIEW.h / 900, .7, 1.25); WC.free = false; G.paused = false; G.wait = false; G.hourAcc = 0; if (!NET.on) relWatch(P);
    el('title').hidden = true; el('bhud').hidden = true; el('whud').hidden = false; el('wlog').innerHTML = ''; G.player.logDirty = true; UI.back = null; showLoad(false); updateWorldHud(true); netFlush();
  }, 30);
}
function gotoTitle() { MODE = 'title'; el('whud').hidden = true; el('bhud').hidden = true; el('title').hidden = false; closeModal(); startDemo(); buildTitleMenu(); }
function buildTitleMenu() { el('tmenu').innerHTML = '<button class="btn pri" data-act="newgame">Новая игра</button>' + (NET.avail ? '<button class="btn pri" data-act="mp">Играть вдвоём</button>' : '') + (hasSave() ? '<button class="btn" data-act="cont">Продолжить</button>' : '') + '<button class="btn" data-act="quick">Быстрый бой</button><button class="btn" data-act="help">Как играть</button><button class="btn" data-act="snd">Звук: ' + (AU.on ? 'вкл' : 'выкл') + '</button>'; }
ACT.snd = function () { auSetOn(!AU.on); if (MODE === 'title') buildTitleMenu(); else openMenu(); };
function startDemo() {
  const fs = REAL_F, a = pick(fs), b = pick(fs.filter(x => x !== a)); FACTIONS.player.c1 = FACTIONS.player.c1 || '#c08a2e';
  startBattle({ demo: true, pl: genTroops(a, 38, .6), en: genTroops(b, 38, .6), pfac: a, efac: b, biome: pick(['grass', 'grass', 'snow', 'steppe', 'arid']), seed: rint(1, 1e9) });
  B.cam.z = clamp(VIEW.h / 760, .7, 1.2); B.speed = 1.4;
}

/* ---------- бой: запуск и итоги ---------- */
function launchBattle(p) {
  const P = G.player; auInit(); P.busy = 'battle';
  const cfg = Object.assign(battleCfgFor(P, p), { party: p, onEnd: res => battleEnded(res, p) });
  enterBattle(cfg);
}
function enterBattle(cfg, coop) {
  startBattle(cfg); if (coop) { joinBattle(coop); const mh = B.units.find(u => u.isHero && u.pid === NET.you); if (mh) B.hero = mh; } MODE = 'battle'; el('whud').hidden = true; el('title').hidden = true; el('bhud').hidden = false; B.cam.z = clamp(VIEW.h / 700, .75, 1.35); IN.atk = IN.block = false; IN.keys = {};
  el('crA').src = crestURL('player'); el('crB').src = crestURL(cfg.efac); el('blog').innerHTML = ''; buildBattleHud(); B.hudDirty = true; B.logDirty = true; el('touch').hidden = !IN.touch;
}
function readHeroInput() {
  const h = B && B.hero; if (!h || B.cfg.demo) return; const k = IN.keys; let dx = (k.KeyD || k.ArrowRight ? 1 : 0) - (k.KeyA || k.ArrowLeft ? 1 : 0), dy = (k.KeyS || k.ArrowDown ? 1 : 0) - (k.KeyW || k.ArrowUp ? 1 : 0);
  if (IN.jx || IN.jy) { dx = IN.jx; dy = IN.jy; }
  const w = IN.touch ? null : s2w(IN.mx, IN.my); let face; if (w) face = Math.atan2(w.y - h.y, w.x - h.x); else if (dx || dy) face = Math.atan2(dy, dx);
  let sw = (k.KeyX || IN.sw) ? 1 : 0;
  if (IN.swTo) { if (B.cfg.hero.sel === IN.swTo || --IN.swT <= 0) IN.swTo = null; else { IN.swP = !IN.swP; if (IN.swP) sw = 1; } } // кнопка в панели героя: импульсы, пока не закончится замах и смена не пройдёт
  h.inp = { dx, dy, face, atk: IN.atk ? 1 : 0, blk: IN.block ? 1 : 0, spr: (k.ShiftLeft || k.ShiftRight || IN.sprint) ? 1 : 0, sw };
}
function launchSiege(p) { const P = G.player; auInit(); P.busy = 'battle'; enterBattle(Object.assign(siegeCfgFor(P, p), { party: p, onEnd: res => battleEnded(res, p) })); }
function autoPlayer(p) { battleEnded(autoResult(G.player, p), p); }
function battleEnded(res, p) {
  if (B && B.cfg.quick) return quickEnded(res);
  const P = G.player; P.busy = null; UI.res = applyBattleResult(P, res, p); if (UI.res.win) { UI.res.drops = rollLoot(P, p); if (UI.res.drops.length) logW('Трофеи: ' + dropText(UI.res.drops) + '.', 3, P); } showResult(UI.res, p);
}
function showResult(r, p) {
  const res = r.res, H = G.player.hero; const left = Object.keys(res.dead).map(k => '<div class="kv"><span>' + TROOPS[k].name + '</span><b class="dn">−' + res.dead[k] + '</b></div>').join('');
  openModal('<div class="whead"><h2>' + (r.win ? 'Победа' : 'Поражение') + '<span class="sub">' + (res.auto ? 'Расчётный бой' : 'Битва длилась ' + Math.floor(res.time / 60) + ' мин ' + Math.round(res.time % 60) + ' сек') + '</span></h2><span class="tag ' + (r.win ? 'g' : 'r') + '">' + (r.win ? 'Враг разбит' : 'Отряд отступил') + '</span></div><div class="wbody"><div class="cols"><div class="card"><h3>Итоги</h3><div class="kv"><span>Враг убит или бежал</span><b>' + res.enemyDead + ' из ' + res.enemyTotal + '</b></div><div class="kv"><span>Твои павшие</span><b class="dn">' + r.lost + '</b></div><div class="kv"><span>Раненые вернулись в строй</span><b>' + r.wounded + '</b></div>' + (res.heroKills ? '<div class="kv"><span>Побед героя в бою</span><b>' + res.heroKills + '</b></div>' : '') + (r.win ? '<div class="kv"><span>Добыча</span><b class="up">+' + r.loot + ' золота</b></div>' : '<div class="kv"><span>Потеряно золота</span><b class="dn">−' + (res.lostGold || 0) + '</b></div>') + '' + (r.drops && r.drops.length ? '<div class="kv"><span>Трофеи</span><b class="up" style="text-align:right">' + dropText(r.drops) + '</b></div>' : '') + '<div class="kv"><span>Опыт героя</span><b>+' + (res.gx || Math.round(res.xp * .5)) + '</b></div>' + (r.lvl ? '<div class="kv"><span>Новый уровень</span><b class="up">' + H.lvl + '</b></div>' : '') + '</div>' + (left ? '<div class="card"><h3>Потери</h3>' + left + '</div>' : '') + '</div>' + (res.woke ? '<div class="note" style="margin-top:10px">Ты очнулся в городе ' + res.woke + '. Отряд разбит, но жив.</div>' : '') + (r.captured ? '<div class="note good" style="margin-top:10px">' + r.captured + ' теперь твой! Зайди туда и оставь гарнизон во вкладке «Гарнизон».</div>' : '') + '</div><div class="wfoot"><button class="btn pri" data-act="cont2">Продолжить</button></div>', 'narrow');
}
function afterBattle() { if (NET.on) NET.send({ t: 'ack' }); MODE = 'world'; B = null; el('bhud').hidden = true; el('whud').hidden = false; WC.x = G.player.x; WC.y = G.player.y; if (G.player.hero.pts > 0 || G.player.hero.pp > 0) toast('Есть свободные очки: атрибуты и перки в окне героя (H)'); saveGame(true); }
function startQuick() {
  const H = { name: 'Ты', str: 3, vit: 3, agi: 2, int: 2, cha: 2, perks: [], eq: { head: 'head_nasal', body: 'body_mail', hands: 'hands_leather', legs: 'legs_boots', melee: 'sword_knight', ranged: 'bow_long', shield: 'shield_banded', horse: QK.me === 'khan' ? 'horse_riding' : null }, sel: 'melee', hp: 1, seed: 7 }; FACTIONS.player.c1 = BANNERS[CR.banner].c1; FACTIONS.player.c2 = BANNERS[CR.banner].c2;
  enterBattle({ pl: genTroops(QK.me, QK.size, .6), en: genTroops(QK.foe, QK.size + 4, QK.foe === 'bandit' ? .35 : .6), pfac: 'player', efac: QK.foe, biome: FACTIONS[QK.me].biome, hero: H, leader: lordName(QK.foe), title: 'Быстрый бой', quick: true, seed: rint(1, 1e9), onEnd: quickEnded });
}
function quickEnded(res) { openModal('<div class="whead"><h2>' + (res.win ? 'Победа' : 'Поражение') + '</h2></div><div class="wbody"><div class="kv"><span>Враг убит или бежал</span><b>' + res.enemyDead + ' из ' + res.enemyTotal + '</b></div><div class="kv"><span>Твои павшие</span><b>' + Object.values(res.dead).reduce((a, b) => a + b, 0) + '</b></div><div class="kv"><span>Побед героя</span><b>' + res.heroKills + '</b></div></div><div class="wfoot"><button class="btn" data-act="endq">В меню</button><button class="btn pri" data-act="again">Ещё бой</button></div>', 'narrow'); }

/* ---------- панель боя ---------- */
function buildBattleHud() {
  const hero = B.cfg.hero, bt = el('bbtns'), dm = B.cfg.demo;
  bt.innerHTML = '<div class="sq plank thin" data-b="pause" title="Пауза (P)">' + ic('pause') + '</div><div class="sq plank thin" data-b="speed" title="Скорость (T)">' + ic('hourglass') + '<span class="kb" id="spv">×1</span></div><div class="sq plank thin" data-b="retreat" title="Отступить">' + ic('retreat') + '</div><div class="sq plank thin" data-b="menu" title="Меню (Esc)">' + ic('gear') + '</div>';
  el('bhero').innerHTML = '<div class="nm"><span id="hn"></span><small id="hs"></small></div><div class="bgrid"><div class="bar st"><i id="bst"></i><span id="tst"></span></div><div class="bar mo"><i id="bmo"></i><span id="tmo"></span></div><div class="bar ar"><i id="bar"></i><span id="tar"></span></div><div class="bar hp"><i id="bhp"></i><span id="thp"></span></div></div><div class="wsw" id="wsw" title="Смена оружия: клавиша X или клик"><div class="wb" data-w="melee" id="wbm">' + ic('sword') + '<span class="wn" id="wnm"></span></div><div class="wb" data-w="ranged" id="wbr">' + ic('bow') + '<span class="wn" id="wnr"></span></div><span class="kb">X</span></div>';
  const gs = [[0, 'Пехота', 'inf'], [1, 'Стрелки', 'arc'], [2, 'Конница', 'cav'], [3, 'Все', null]];
  el('bgroups').innerHTML = gs.map(g => '<div class="grp" data-g="' + g[0] + '"><span class="kb">' + (g[0] + 1) + '</span><img alt="" id="gi' + g[0] + '"><b id="gc' + g[0] + '">0</b>' + g[1] + '</div>').join('');
  el('bords').innerHTML = [['hold', 'hold', 'Q', 'Держать позицию'], ['follow', 'follow', 'E', 'За мной'], ['charge', 'charge', 'R', 'В атаку'], ['back', 'back', 'F', 'Отойти']].map(o => '<div class="ord" data-o="' + o[0] + '" title="' + o[3] + ' (' + o[2] + ')">' + ic(o[1]) + '<span class="kb">' + o[2] + '</span></div>').join('');
  for (let k = 0; k < 3; k++) { const l = B.units.find(u => u.side === 0 && !u.isHero && u.t.grp === k); const im = el('gi' + k); if (l) im.src = portrait(l.t.id, B.cfg.pfac); else im.style.visibility = 'hidden'; }
  const hi = el('gi3'); const hu = B.hero; if (hu) hi.src = hu.sp.cv.toDataURL(); else hi.style.visibility = 'hidden';
  el('bhero').hidden = dm || !hero; el('borders').hidden = dm; el('bbtns').hidden = dm; el('btop').hidden = false;
}
function updateBattleHud() {
  if (!B) return; const n = B.n || B.start; let a = 0, b = 0; for (const u of B.units) if (fit(u)) { if (u.side) b += u.w || 1; else a += u.w || 1; } a = Math.round(a); b = Math.round(b);
  el('cntA').textContent = a; el('cntB').textContent = b; const t = Math.floor(B.t); el('btimer').textContent = Math.floor(t / 60) + ':' + String(t % 60).padStart(2, '0');
  const h = B.hero; if (h) { el('hn').textContent = h.name; el('hs').textContent = B.heroDown ? 'ранен' : (G && G.player && !B.cfg.quick ? 'уровень ' + G.player.hero.lvl + ' · ' : '') + (h.t.wpn ? h.t.wpn.name + (heroEq(B.cfg.hero).ranged ? ' [X]' : '') : ''); const hp = clamp(h.hp / h.maxHp, 0, 1); el('bhp').style.setProperty('--p', hp * 100 + '%'); el('thp').textContent = Math.max(0, Math.round(h.hp)) + ' / ' + Math.round(h.maxHp); el('bst').style.setProperty('--p', h.stam + '%'); el('tst').textContent = 'Силы ' + Math.round(h.stam) + ' / 100'; el('bar').style.setProperty('--p', '100%'); el('tar').textContent = 'Броня ' + h.arm + (h.block ? ' · щит ' + Math.round(h.block * 100) + '%' : ''); let ml = 'Твёрдый'; const army = a / Math.max(1, B.count0[0]); ml = army > .75 ? 'Твёрдый' : army > .5 ? 'Держится' : army > .3 ? 'Колеблется' : 'Паникует'; el('bmo').style.setProperty('--p', clamp(army * 130, 6, 100) + '%'); el('tmo').textContent = 'Мораль: ' + ml; }
  if (h && B.cfg.hero) { const eq = heroEq(B.cfg.hero), sel = B.cfg.hero.sel === 'ranged' && eq.ranged ? 'ranged' : 'melee', nm = eq.melee ? EQ[eq.melee].name : 'Кулаки', nr = eq.ranged ? EQ[eq.ranged].name : 'нет дальнего'; const wk = sel + '|' + nm + '|' + nr; if (B.wk !== wk) { B.wk = wk; el('wnm').textContent = nm; el('wnr').textContent = nr; el('wbm').classList.toggle('on', sel === 'melee'); el('wbr').classList.toggle('on', sel === 'ranged'); el('wbr').classList.toggle('off', !eq.ranged); } }
  const c = [0, 0, 0]; const mp = myPid(); for (const u of B.units) if (u.side === 0 && fit(u) && !u.isHero && u.own === mp) c[u.t.grp] += u.w || 1; for (let k = 0; k < 3; k++) c[k] = Math.round(c[k]); for (let k = 0; k < 3; k++) { el('gc' + k).textContent = c[k]; el('gi' + k).parentNode.style.opacity = c[k] ? 1 : .35; } el('gc3').textContent = c[0] + c[1] + c[2];
  for (const g of document.querySelectorAll('#bgroups .grp')) g.classList.toggle('on', +g.dataset.g === B.sel);
  if (B.logDirty) { B.logDirty = false; el('blog').innerHTML = B.log.slice(-8).reverse().map(l => '<div class="k' + l.kind + '">' + l.txt + '</div>').join(''); }
  const pv = el('spv'); if (pv) pv.textContent = '×' + B.speed;
}
/* перерисовываем кнопку только если её содержимое изменилось: иначе клик, попавший на момент замены, теряется */
function setH(e, html) { if (!e || e.__h === html) return false; e.__h = html; e.innerHTML = html; return true; }
function updateWorldHud(force) {
  if (!G) return; netVoteUI(); netJoinUI(); const P = G.player, cnt = troopCount(P.troops), cap = sizeCap(P.hero), wg = wageDay(P);
  setH(el('sGold'), ic('coin') + fmt(P.gold) + '<small>−' + wg + '/день</small>'); el('sGold').title = 'Золото. Жалованье отряду: ' + wg + ' в день.'; const fd = Math.max(1, Math.ceil(cnt / 6)), days = Math.floor(P.food / fd); setH(el('sFood'), ic('food') + P.food + '<small' + (days < 3 ? ' class="warn"' : '') + '>' + (days > 99 ? '' : '≈' + days + ' дн.') + '</small>'); el('sFood').title = 'Провизия: ' + P.food + '. Отряд съедает ' + fd + ' в день, хватит примерно на ' + days + ' дн. Купить — во вкладке «Рынок» в городе.'; el('sFood').classList.toggle('bad', P.food < Math.ceil(cnt / 6) * 2); setH(el('sMen'), ic('men') + cnt + '<small>/' + cap + '</small>');
  setH(el('sDate'), '<span>День ' + G.day + '</span><small>' + String(G.hour).padStart(2, '0') + ':00</small>');
  setH(el('bPause'), ic(G.paused ? 'play' : 'pause')); for (const b of document.querySelectorAll('[data-sp]')) b.classList.toggle('on', +b.dataset.sp === G.speed);
  const kb = k => '<span class="kb">' + k + '</span>'; setH(document.querySelector('[data-act=party]'), ic('men') + '<span>Отряд</span>' + kb('P')); setH(document.querySelector('[data-act=hero]'), ic('helm') + '<span>Герой' + (P.hero.pts + (P.hero.pp || 0) ? ' +' + (P.hero.pts + (P.hero.pp || 0)) : '') + '</span>' + kb('H')); setH(document.querySelector('[data-act=journal]'), ic('book') + '<span>Журнал</span>' + kb('J')); setH(document.querySelector('[data-act=menu]'), ic('gear') + '<span>Меню</span>' + kb('Esc')); setH(document.querySelector('[data-act=inv]'), ic('bag') + '<span>Обоз</span>' + kb('I'));
  if (P.logDirty || G.logDirty) { P.logDirty = G.logDirty = false; el('wlog').innerHTML = P.log.slice(-4).reverse().map(l => '<div class="k' + l.kind + '">' + l.txt + '</div>').join(''); }
  // ближайшее поселение
  let near = null; for (const s of G.settles) { if (s.kind === 'camp') continue; if (Math.hypot(s.x - P.x, s.y - P.y) < 46) near = s; }
  const w = el('wloc'); if (near && !UI.open) { w.hidden = false; if (setH(w, '<span class="lab">' + near.name + '</span><button class="btn sm pri" id="bEnter">Войти</button>')) el('bEnter').onclick = () => openTown(near); } else w.hidden = true;
}

/* ---------- мир: ввод, шаги, отрисовка ---------- */
function worldClick(sx, sy) {
  if (!G || UI.open) return; const w = s2wW(sx, sy), P = G.player; if (NET.on) return netWorldClick(w); auInit(); P.tid = null; P.sid = null; G.wait = false; WC.free = false;
  let tp = null, bd = 34; for (const p of G.parties) { if (p.hide) continue; const d = Math.hypot(p.x - w.x, p.y - w.y); if (d < bd) { bd = d; tp = p; } }
  if (tp) { P.tid = tp.id; P.path = findPath(P.x, P.y, tp.x, tp.y) || []; P.pi = 0; P.rp = .6; return; }
  let ts = null; bd = 50; for (const s of G.settles) { const d = Math.hypot(s.x - w.x, s.y - w.y); if (d < bd) { bd = d; ts = s; } }
  if (ts && ts.kind === 'camp') { if (ts.camp) { P.tid = ts.camp.id; P.path = findPath(P.x, P.y, ts.x, ts.y) || []; P.pi = 0; P.rp = .6; } else toast('Логово пусто'); return; }
  if (ts) { if (Math.hypot(ts.x - P.x, ts.y - P.y) < 46) { openTown(ts); return; } P.sid = ts.id; P.path = findPath(P.x, P.y, ts.x, ts.y) || []; P.pi = 0; if (!P.path.length) P.sid = null; return; }
  const tx = clamp(w.x, 10, WW - 10), ty = clamp(w.y, 10, WH - 10); const path = findPath(P.x, P.y, tx, ty); if (!path) return toast('Туда не пройти'); P.path = path; P.pi = 0;
}
function worldUpdate(dt) {
  if (NET.on) return netWorldUpdate(dt);
  if (!G || UI.open) return; const P = G.player, moving = (P.path.length && P.pi < P.path.length) || P.tid != null;
  if (!G.paused && (moving || G.wait)) {
    G.acc += dt * 1.2 * G.speed; G.hourAcc = G.hourAcc || 0; let guard = 0;
    while (G.acc >= .2 && guard++ < 40) { G.acc -= .2; snapWorld(); const evs = stepWorld(.2); G.hourAcc += .2; if (G.hourAcc >= 1) { G.hourAcc -= 1; hourTick(); P.logDirty = true; if (G.hour === 0) { saveGame(true); } } if (evs.length) { handleEvent(evs[0]); break; } }
    WA = G.acc >= .2 || UI.open ? 1 : clamp(G.acc / .2, 0, 1);
  } else if (WA < 1) WA = Math.min(1, WA + dt * 6 * G.speed); // мир встал — плавно доводим до последней точки
  const PP = rpos(P);
  if (!WC.free) { const k = Math.min(1, dt * 5); WC.x += (PP.x - WC.x) * k; WC.y += (PP.y - WC.y) * k; }
  const hw = VIEW.w / 2 / WC.z, hh = VIEW.h / 2 / WC.z; WC.x = hw * 2 >= WW ? WW / 2 : clamp(WC.x, hw, WW - hw); WC.y = hh * 2 >= WH ? WH / 2 : clamp(WC.y, hh, WH - hh);
}
/* плавность: между шагами мира рисуем объекты в промежуточной точке */
const WPREV = new Map(); let WA = 1;
function snapWorld() { WPREV.clear(); for (const Q of G.players) WPREV.set(Q, [Q.x, Q.y]); for (const p of G.parties) WPREV.set(p, [p.x, p.y]); }
function rpos(o) { const q = !NET.on && WA < 1 && WPREV.get(o); if (!q || Math.abs(q[0] - o.x) + Math.abs(q[1] - o.y) > 80) return o; return { x: q[0] + (o.x - q[0]) * WA, y: q[1] + (o.y - q[1]) * WA }; }
function handleEvent(ev) { if (ev.type === 'enter') openTown(ev.s); else if (ev.type === 'meet') openEncounter(ev.p, ev.forced); }
function drawWorld(g) {
  const d = VIEW.dpr, z = WC.z, P = G.player; g.setTransform(1, 0, 0, 1, 0, 0); g.fillStyle = '#16232b'; g.fillRect(0, 0, cv.width, cv.height);
  g.setTransform(d * z, 0, 0, d * z, d * (VIEW.w / 2 - WC.x * z), d * (VIEW.h / 2 - WC.y * z)); g.drawImage(WT.img, 0, 0);
  const x0 = WC.x - VIEW.w / 2 / z - 120, x1 = WC.x + VIEW.w / 2 / z + 120, y0 = WC.y - VIEW.h / 2 / z - 120, y1 = WC.y + VIEW.h / 2 / z + 160;
  if (P.path.length && P.pi < P.path.length) { g.setLineDash([8, 7]); g.lineCap = 'round'; const pp = rpos(P); g.beginPath(); g.moveTo(pp.x, pp.y); for (let i = P.pi; i < P.path.length; i++) g.lineTo(P.path[i].x, P.path[i].y); g.strokeStyle = 'rgba(20,12,4,.8)'; g.lineWidth = 5; g.stroke(); g.strokeStyle = '#ffe9a0'; g.lineWidth = 2.6; g.stroke(); g.setLineDash([]); const e = P.path[P.path.length - 1]; g.strokeStyle = '#ffe9a0'; g.lineWidth = 2.6; g.beginPath(); g.arc(e.x, e.y, 9, 0, TAU); g.stroke(); }
  const list = []; for (const s of G.settles) if (s.x > x0 && s.x < x1 && s.y > y0 && s.y < y1) list.push({ y: s.y, s }); for (const p of G.parties) if (!p.hide && p.kind !== 'camp' && p.x > x0 && p.x < x1 && p.y > y0 && p.y < y1) { const r = rpos(p); list.push({ y: r.y, p, r }); } for (const Q of G.players) { if (Q !== P && (Q.in || Q.away)) continue; const r = rpos(Q); list.push({ y: r.y, pl: Q, r }); } list.sort((a, b) => a.y - b.y);
  g.textAlign = 'center'; g.lineJoin = 'round';
  const late = []; // названия поселений рисуем последними — поверх фигурок
  const inTown = (x, y) => G.settles.some(s => s.kind !== 'camp' && Math.abs(s.x - x) < 40 && Math.abs(s.y - y) < 40); // в городе подпись — над фигуркой, чтобы не налезать на название города
  const label = (t, x, y, c, sz) => { g.font = '700 ' + (sz || 15) + 'px "Alegreya Sans SC","Alegreya Sans",sans-serif'; g.lineWidth = 4; g.strokeStyle = 'rgba(14,9,4,.9)'; g.strokeText(t, x, y); g.fillStyle = c || '#f0e6c8'; g.fillText(t, x, y); };
  for (const it of list) {
    if (it.s) { const s = it.s, sp = settleSprite(s), k = s.kind === 'town' ? .72 : s.kind === 'castle' ? .7 : .6; if (s.kind === 'camp' && s.cleared) g.globalAlpha = .5; g.drawImage(sp.cv, s.x - sp.ax * k, s.y - sp.ay * k, sp.cv.width * k, sp.cv.height * k); g.globalAlpha = 1; const hs = settleHostile(s, P), own = s.fac === 'player'; if (hs || own) { g.strokeStyle = hs ? 'rgba(230,60,40,.85)' : 'rgba(255,214,106,.9)'; g.lineWidth = 3; g.setLineDash(hs ? [] : [6, 5]); g.beginPath(); g.ellipse(s.x, s.y + 4, s.kind === 'village' ? 30 : 46, s.kind === 'village' ? 12 : 17, 0, 0, TAU); g.stroke(); g.setLineDash([]); }
      late.push([s.name + (own ? ' ★' : ''), s.x, s.y + 22, s.kind === 'camp' || hs ? '#ff7a66' : own ? '#ffe08a' : '#f0e6c8', s.kind === 'village' ? 13 : 16]); }
    else if (it.p) { const p = Object.assign(Object.create(it.p), { x: it.r.x, y: it.r.y }); let sp, k = .34; if (p.kind === 'caravan') { const c = caravanSprite(); g.drawImage(c.cv, p.x - c.ax * .5, p.y - c.ay * .5, 55, 35); label('Караван', p.x, p.y + 16, '#d8c9a2', 12); continue; } sp = getSprite(leaderType(p), 0, p.fac); const dir = p.fx < 0 ? -1 : 1; const hp = p.kind === 'lord' && isHostileToPlayer(p, P); g.fillStyle = 'rgba(0,0,0,.28)'; g.beginPath(); g.ellipse(p.x + 2, p.y + 3, 20, 7, 0, 0, TAU); g.fill(); if (hp) { g.strokeStyle = 'rgba(230,60,40,.9)'; g.lineWidth = 2.5; g.beginPath(); g.ellipse(p.x, p.y + 1, 22, 8, 0, 0, TAU); g.stroke(); } g.save(); g.translate(p.x, p.y + Math.sin(G.day * 24 + G.hour + p.id) * 0); g.scale(dir * k, k); g.drawImage(sp.cv, -sp.ax, -sp.ay); g.restore(); drawBanner(g, p.x + 14, p.y + 2, p.fac, 9); if (!inTown(p.x, p.y)) label(p.kind === 'bandit' ? 'Разбойники' : p.name, p.x, p.y + 17, p.kind === 'bandit' || hp ? '#ff7a66' : '#f0e6c8', 12); }
    else { const Q = Object.assign(Object.create(it.pl), { x: it.r.x, y: it.r.y }), me = it.pl === P, H = Q.hero, mnt = H.horse > 0, sp = getHeroSprite(H, mnt), k = .4, bf = me ? 'player' : netFac(Q); g.fillStyle = 'rgba(0,0,0,.3)'; g.beginPath(); g.ellipse(Q.x + 2, Q.y + 3, 24, 8, 0, 0, TAU); g.fill(); g.strokeStyle = me ? '#ffd86a' : '#8fd0ff'; g.lineWidth = 2; g.beginPath(); g.ellipse(Q.x, Q.y + 1, 26, 9, 0, 0, TAU); g.stroke(); g.save(); g.translate(Q.x, Q.y); g.scale((Q.fx < 0 ? -1 : 1) * k, k); g.drawImage(sp.cv, -sp.ax, -sp.ay); g.restore(); drawBanner(g, Q.x + 16, Q.y + 2, bf, 11); label(Q.name + (Q.fname ? ' [' + Q.fname + ']' : ''), Q.x, inTown(Q.x, Q.y) ? Q.y - 44 : Q.y + 19, me ? '#ffe9a0' : '#bfe4ff', 14); }
  }
  for (const l of late) label(...l);
  g.setTransform(1, 0, 0, 1, 0, 0);
  const h = G.hour, night = h >= 21 || h < 4 ? .34 : h >= 19 ? (h - 18) * .1 : h < 6 ? (6 - h) * .1 : 0; if (night > 0) { g.fillStyle = 'rgba(8,16,48,' + night + ')'; g.fillRect(0, 0, cv.width, cv.height); }
  const vg = g.createRadialGradient(cv.width / 2, cv.height / 2, cv.height * .45, cv.width / 2, cv.height / 2, cv.width * .72); vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(6,4,2,.5)'); g.fillStyle = vg; g.fillRect(0, 0, cv.width, cv.height);
}
function worldTip(sx, sy) {
  const tip = el('tip'); if (MODE !== 'world' || UI.open) { tip.hidden = true; return; } const w = s2wW(sx, sy); let html = null;
  for (const p of G.parties) { if (p.hide || Math.hypot(p.x - w.x, p.y - w.y) > 30) continue; const pw = relativePower(p), hs = isHostileToPlayer(p); html = '<b>' + (p.kind === 'bandit' ? 'Разбойники' : p.name) + '</b><br>' + FACTIONS[p.fac].name + ' · ' + troopCount(p.troops) + ' бойцов<br><span class="tag ' + pw[1] + '">' + pw[0] + '</span>' + (hs ? '<span class="tag r">враг</span>' : ''); break; }
  if (!html) for (const s of G.settles) { if (Math.hypot(s.x - w.x, s.y - w.y) > 46) continue; html = '<b>' + s.name + '</b><br>' + KIND[s.kind] + ' · ' + (s.fac === 'player' ? 'твоё владение · гарнизон ' + troopCount(garrisonOf(s)) : FACTIONS[s.fac].gen) + (settleHostile(s, G.player) ? '<br><span class="tag r">враждебен</span> ' + (s.kind === 'village' ? 'ворота закрыты' : 'клик — осада, гарнизон ' + troopCount(garrisonOf(s))) : '') + (s.kind === 'camp' ? (s.camp ? '<br>Охраняет ' + troopCount(s.camp.troops) + ' головорезов' : '<br>Опустошено') : (s.fac === 'player' ? '' : '<br>Отношение: ' + relName(G.player.rel[s.fac]))); break; }
  if (!html) { const t = terrAt(w.x, w.y); if (t === 0 || t === 4 || t === 5) html = null; }
  if (html) { tip.innerHTML = html; tip.hidden = false; tip.style.left = Math.min(sx + 18, VIEW.w - 270) + 'px'; tip.style.top = Math.min(sy + 14, VIEW.h - 100) + 'px'; } else tip.hidden = true;
}

/* ---------- ввод ---------- */
let drag = null;
function bindInput() {
  window.addEventListener('keydown', e => {
    if (netKey(e)) return;
    auInit(); IN.keys[e.code] = true; if (['Space', 'Tab', 'ArrowUp', 'ArrowDown'].includes(e.code) && !(e.target && e.target.tagName === 'INPUT')) e.preventDefault();
    if (e.target && e.target.tagName === 'INPUT') return;
    if (MODE === 'battle' && B && !B.cfg.demo) {
      if (e.code === 'Escape') { if (!UI.open) { if (!NET.on) B.paused = true; openMenu(); } else { closeModal(); B.paused = false; } return; }
      if (UI.open) return;
      const k = e.code; if (k >= 'Digit1' && k <= 'Digit4') { B.sel = +k.slice(5) - 1; B.hudDirty = true; sfx('click'); }
      else if (k === 'KeyQ') { const w = s2w(IN.mx, IN.my); giveOrder('hold', w.x, w.y); } else if (k === 'KeyE') giveOrder('follow'); else if (k === 'KeyR') giveOrder('charge'); else if (k === 'KeyF') giveOrder('back');
      else if (k === 'KeyP') { if (!NET.on) B.paused = !B.paused; } else if (k === 'KeyT') { if (!NET.on) cycleSpeed(); }
    } else if (MODE === 'world' && G) {
      if (e.code === 'Escape') { if (UI.open) { if (UI.enc) return; if (UI.town || UI.panel) { ACT.closepanel(); if (!UI.town) closeModal(); } else closeModal(); } else openMenu(); return; }
      if (UI.open) return;
      if (e.code === 'Space') { if (NET.on) NET.send({ t: 'prop', k: 'pause', v: !G.paused }); else { G.paused = !G.paused; updateWorldHud(); } } else if (e.code === 'KeyC') WC.free = false; else if (e.code === 'KeyP') { openPanel('troops'); } else if (e.code === 'KeyH') openPanel('hero'); else if (e.code === 'KeyJ') openPanel('journal'); else if (e.code === 'KeyI') openPanel('inv'); else if (e.code === 'KeyZ') { G.wait = !G.wait; toast(G.wait ? 'Отряд ждёт' : 'Снова в путь'); }
      else if (e.code >= 'Digit1' && e.code <= 'Digit3') { const sp = [1, 2, 4][+e.code.slice(5) - 1]; if (NET.on) NET.send({ t: 'prop', k: 'speed', v: sp }); else { G.speed = sp; updateWorldHud(); } }
    }
  });
  // ушёл из окна (Alt+Tab) с зажатой клавишей или кнопкой мыши — отпускаем всё, иначе герой «залипает»
  const releaseAll = () => { IN.keys = {}; IN.atk = IN.block = false; IN.sprint = IN.sw = false; IN.jx = IN.jy = 0; drag = null; };
  window.addEventListener('blur', releaseAll); document.addEventListener('visibilitychange', () => { if (document.hidden) releaseAll(); });
  window.addEventListener('keyup', e => { if (e.target && e.target.id === 'chatin') return; IN.keys[e.code] = false; });
  cv.addEventListener('contextmenu', e => e.preventDefault());
  cv.addEventListener('mousemove', e => { IN.mx = e.clientX; IN.my = e.clientY; if (MODE === 'world') { if (drag) { const dx = e.clientX - drag.x, dy = e.clientY - drag.y; if (Math.hypot(dx, dy) > 6) drag.moved = true; if (drag.moved) { WC.free = true; WC.x = drag.cx - dx / WC.z; WC.y = drag.cy - dy / WC.z; } } worldTip(e.clientX, e.clientY); } });
  cv.addEventListener('mouseleave', () => { el('tip').hidden = true; });
  cv.addEventListener('mousedown', e => { auInit(); IN.mx = e.clientX; IN.my = e.clientY; if (MODE === 'battle') { if (e.button === 0) IN.atk = true; else if (e.button === 2) IN.block = true; } else if (MODE === 'world' && e.button === 0) drag = { x: e.clientX, y: e.clientY, cx: WC.x, cy: WC.y, moved: false }; });
  window.addEventListener('mouseup', e => { if (MODE === 'battle') { if (e.button === 0) IN.atk = false; if (e.button === 2) IN.block = false; } else if (drag) { if (!drag.moved && e.target === cv) worldClick(e.clientX, e.clientY); drag = null; } });
  cv.addEventListener('wheel', e => { e.preventDefault(); const f = e.deltaY < 0 ? 1.1 : .91; if (MODE === 'world') WC.z = clamp(WC.z * f, WW > 3000 ? .25 : .45, 1.8); else if (B) B.cam.z = clamp(B.cam.z * f, .55, 2); }, { passive: false });
  // тач
  const joy = el('joy'); let jid = null; const jset = (t) => { const r = joy.getBoundingClientRect(), dx = t.clientX - (r.left + r.width / 2), dy = t.clientY - (r.top + r.height / 2), l = Math.hypot(dx, dy), m = r.width / 2; const k = l > m ? m / l : 1; IN.jx = dx * k / m; IN.jy = dy * k / m; joy.firstElementChild.style.transform = 'translate(' + dx * k + 'px,' + dy * k + 'px)'; };
  joy.addEventListener('touchstart', e => { e.preventDefault(); IN.touch = true; jid = e.changedTouches[0].identifier; jset(e.changedTouches[0]); }, { passive: false });
  joy.addEventListener('touchmove', e => { e.preventDefault(); for (const t of e.changedTouches) if (t.identifier === jid) jset(t); }, { passive: false });
  const jend = e => { for (const t of e.changedTouches) if (t.identifier === jid) { jid = null; IN.jx = IN.jy = 0; joy.firstElementChild.style.transform = ''; } }; joy.addEventListener('touchend', jend); joy.addEventListener('touchcancel', jend);
  const hold = (id, fn) => { const b = el(id); b.addEventListener('touchstart', e => { e.preventDefault(); IN.touch = true; fn(true); }, { passive: false }); b.addEventListener('touchend', () => fn(false)); b.addEventListener('touchcancel', () => fn(false)); b.addEventListener('mousedown', () => fn(true)); b.addEventListener('mouseup', () => fn(false)); };
  hold('tbA', v => IN.atk = v); hold('tbB', v => IN.block = v); hold('tbS', v => IN.sprint = v); hold('tbW', v => IN.sw = v);
  cv.addEventListener('touchstart', e => { IN.touch = true; auInit(); if (MODE === 'world' && e.touches.length === 1) { const t = e.touches[0]; drag = { x: t.clientX, y: t.clientY, cx: WC.x, cy: WC.y, moved: false }; } }, { passive: true });
  cv.addEventListener('touchmove', e => { if (MODE === 'world' && drag && e.touches.length === 1) { const t = e.touches[0], dx = t.clientX - drag.x, dy = t.clientY - drag.y; if (Math.hypot(dx, dy) > 10) drag.moved = true; if (drag.moved) { WC.free = true; WC.x = drag.cx - dx / WC.z; WC.y = drag.cy - dy / WC.z; } } }, { passive: true });
  cv.addEventListener('touchend', e => { if (MODE === 'world' && drag && !drag.moved) { const t = e.changedTouches[0]; worldClick(t.clientX, t.clientY); } drag = null; });
  // кнопки интерфейса
  el('wspeed').addEventListener('click', e => { const b = e.target.closest('button'); if (!b) return; auInit(); if (NET.on) { NET.send(b.id === 'bPause' ? { t: 'prop', k: 'pause', v: !G.paused } : { t: 'prop', k: 'speed', v: +b.dataset.sp }); return; } if (b.id === 'bPause') G.paused = !G.paused; else G.speed = +b.dataset.sp; sfx('click'); updateWorldHud(); });
  el('bbtns').addEventListener('click', e => { const b = e.target.closest('[data-b]'); if (!b || !B) return; sfx('click'); const a = b.dataset.b; if (NET.on && (a === 'pause' || a === 'speed')) toast('В сетевой игре бой нельзя ставить на паузу'); else if (a === 'pause') B.paused = !B.paused; else if (a === 'speed') cycleSpeed(); else if (a === 'menu') { if (!NET.on) B.paused = true; openMenu(); } else if (a === 'retreat') { if (NET.on) NET.send({ t: 'retreat' }); else if (!B.over) { B.over = B.t; B.win = false; blog('Отряд отступает!', 1); } } });
  el('bhero').addEventListener('click', e => { const w = e.target.closest('.wb'); if (!w || !B || !B.hero || B.cfg.demo) return; const eq = heroEq(B.cfg.hero), to = w.dataset.w;
    if (NET.on) return toast('В сетевом бою смена оружия пока недоступна');
    if (to === 'ranged' && !eq.ranged) return toast('Дальнего оружия нет. Лук, арбалет или метательные копья можно надеть в обозе (I).');
    if (B.cfg.hero.sel === to || (to === 'melee' && B.cfg.hero.sel !== 'ranged')) return; IN.swTo = to; IN.swT = 90; IN.swP = false; sfx('click'); });
  el('bgroups').addEventListener('click', e => { const g = e.target.closest('.grp'); if (g && B) { B.sel = +g.dataset.g; sfx('click'); } });
  el('bords').addEventListener('click', e => { const o = e.target.closest('.ord'); if (!o || !B || !B.hero) return; const h = B.hero, foe = centroid(1), a = foe ? Math.atan2(foe.y - h.y, foe.x - h.x) : 0; giveOrder(o.dataset.o, h.x + Math.cos(a) * 60, h.y + Math.sin(a) * 60); });
  el('blog').addEventListener('click', () => el('blog').classList.toggle('open'));
  el('bmini').addEventListener('click', e => { if (!B) return; const c = el('bmini').firstElementChild, r = c.getBoundingClientRect(); B.cam.x = (e.clientX - r.left) / r.width * B.W; B.cam.y = (e.clientY - r.top) / r.height * B.H; });
  window.addEventListener('resize', resize);
  const origClose = closeModal; closeModal = function () { origClose(); if (B && B.paused && MODE === 'battle' && !B.over && !B.done) B.paused = false; };
}
function cycleSpeed() { B.speed = B.speed === 1 ? 2 : B.speed === 2 ? .5 : 1; }

/* ---------- цикл ---------- */
let lastT = 0, hudT = 0, wtT = 0;
function frame(ts) {
  const dt = Math.min(.1, (ts - lastT) / 1000 || 0); lastT = ts; const g = cx;
  try {
    if (MODE === 'title') { if (B) { battleUpdate(dt); battleDraw(g); if (B.over && B.t - B.over > 3) startDemo(); } musicTick(dt, 'world'); }
    else if (MODE === 'battle' && B) { if (NET.on) netBattleUpdate(dt); else if (!UI.open || B.over) { readHeroInput(); battleUpdate(dt); } battleDraw(g); drawMinimap(el('bmini').firstElementChild); hudT -= dt; if (hudT <= 0) { hudT = .12; updateBattleHud(); } musicTick(dt, 'battle'); }
    else if (MODE === 'world' && G) { worldUpdate(dt); drawWorld(g); hudT -= dt; if (hudT <= 0) { hudT = .15; updateWorldHud(); } musicTick(dt, 'world'); }
  } catch (e) { console.error(e); if (!window.__err) { window.__err = 1; } }
  requestAnimationFrame(frame);
}
function init() {
  netProbe(); cv = el('cv'); cx = cv.getContext('2d'); try { IN.touch = window.matchMedia('(pointer:coarse)').matches; } catch (e) { } resize(); try { new ResizeObserver(() => resize()).observe(cv); } catch (e) { } bindInput(); window.__dbg = { get G() { return G; }, get B() { return B; }, get MODE() { return MODE; } };
  el('modal').hidden = true; setTimeout(() => { startDemo(); el('title').hidden = false; buildTitleMenu(); showLoad(false); }, 50); requestAnimationFrame(frame);
}
if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => { }); init();
