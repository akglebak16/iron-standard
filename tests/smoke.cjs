// Быстрая проверка игры в настоящем браузере: node tests/smoke.cjs  (или npm test)
// Нужен Playwright:  npm i --no-save playwright && npx playwright install chromium
// Свой Chrome вместо скачанного: CHROME_PATH=/usr/bin/google-chrome npm test
// Тест сам собирает index.html, поднимает сервер на свободном порту с временной папкой мира и гоняет проверки.
const { chromium } = require('playwright');
const { spawn, execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path'), net = require('net');
const ROOT = path.join(__dirname, '..');

let failed = 0;
const ok = (name, cond, info) => { console.log((cond ? '  ✓ ' : '  ✗ ') + name + (info !== undefined ? '  ' + JSON.stringify(info) : '')); if (!cond) failed++; };
const freePort = () => new Promise(r => { const s = net.createServer(); s.listen(0, () => { const p = s.address().port; s.close(() => r(p)); }); });
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function newSinglePlayer(pg) {
  await pg.click('[data-act=newgame]'); await sleep(600);
  for (let i = 0; i < 5 && await pg.evaluate(() => __dbg.MODE) !== 'world'; i++) { const b = await pg.$('#modal:not([hidden]) .btn.pri'); if (b) await b.click(); await sleep(700); }
  await pg.waitForFunction(() => __dbg.MODE === 'world', null, { timeout: 15000 }); await sleep(500);
  await pg.evaluate(() => closeModal());
}

async function singlePlayer(pg) {
  console.log('Одиночная игра');
  await newSinglePlayer(pg);

  // 1. плавность движения по карте на ×1: позиция героя на экране меняется каждый кадр небольшими шагами
  const mv = await pg.evaluate(async () => {
    const G = __dbg.G, P = G.player; G.speed = 1; G.paused = false;
    let path = null; for (const [dx, dy] of [[400, 0], [-400, 0], [0, 400], [0, -400]]) { path = findPath(P.x, P.y, clamp(P.x + dx, 20, WW - 20), clamp(P.y + dy, 20, WH - 20)); if (path && path.length) break; }
    P.path = path; P.pi = 0; P.tid = null; P.sid = null;
    await new Promise(r => setTimeout(r, 300));
    const xs = []; await new Promise(res => { let n = 0; const f = () => { const q = rpos(P); xs.push([q.x, q.y]); if (++n < 90) requestAnimationFrame(f); else res(); }; requestAnimationFrame(f); });
    const d = xs.slice(1).map((v, i) => Math.hypot(v[0] - xs[i][0], v[1] - xs[i][1])); const moving = d.filter(x => x > 1e-6).length;
    return { frames: d.length, moving, max: +Math.max(...d).toFixed(2), avg: +(d.reduce((a, b) => a + b, 0) / d.length).toFixed(2) };
  });
  ok('карта ×1: отряд движется плавно (сдвиг почти каждый кадр, без прыжков)', mv.moving >= mv.frames * .8 && mv.max < mv.avg * 4 + .5, mv);

  // 2. кнопки верхнего меню срабатывают даже при медленном нажатии (успевает пройти обновление панели)
  let opened = 0, tries = 0;
  for (const a of ['party', 'hero', 'journal', 'inv', 'menu']) for (let k = 0; k < 2; k++) {
    const bb = await pg.locator('#whud [data-act=' + a + ']').first().boundingBox();
    await pg.mouse.move(bb.x + bb.width / 2, bb.y + bb.height / 2); await pg.mouse.down(); await sleep(220); await pg.mouse.up(); await sleep(120);
    tries++; if (await pg.evaluate(() => UI.open)) opened++; await pg.evaluate(() => closeModal()); await sleep(80);
  }
  ok('кнопки верхнего меню нажимаются с первого раза', opened === tries, opened + '/' + tries);

  // камера карты мира двигается клавишами WASD, C возвращает её к отряду, при открытом окне не двигается
  await pg.evaluate(() => { closeModal(); G.paused = true; G.player.path = []; WC.free = false; WC.x = WW / 2; WC.y = WH / 2; WC.z = .9; });
  const cam0 = await pg.evaluate(() => ({ x: WC.x, y: WC.y }));
  await pg.keyboard.down('d'); await pg.waitForTimeout(350); await pg.keyboard.up('d');
  const camD = await pg.evaluate(() => ({ x: WC.x, y: WC.y, free: WC.free }));
  await pg.keyboard.down('a'); await pg.waitForTimeout(350); await pg.keyboard.up('a');
  const camA = await pg.evaluate(() => ({ x: WC.x }));
  await pg.keyboard.down('s'); await pg.waitForTimeout(350); await pg.keyboard.up('s');
  const camS = await pg.evaluate(() => ({ y: WC.y }));
  await pg.keyboard.down('w'); await pg.waitForTimeout(350); await pg.keyboard.up('w');
  const camW = await pg.evaluate(() => ({ y: WC.y }));
  await pg.evaluate(() => openMenu()); const frozen0 = await pg.evaluate(() => WC.x);
  await pg.keyboard.down('d'); await pg.waitForTimeout(250); await pg.keyboard.up('d');
  const frozen1 = await pg.evaluate(() => WC.x); await pg.evaluate(() => closeModal());
  await pg.keyboard.press('c'); const back = await pg.evaluate(() => WC.free);
  ok('WASD двигают камеру по карте мира, C возвращает её к отряду, при открытом окне камера стоит',
    camD.x > cam0.x + 30 && camD.free && camA.x < camD.x - 30 && camS.y > camD.y + 30 && camW.y < camS.y - 30 && Math.abs(frozen1 - frozen0) < 1 && back === false, { cam0, camD, camA, camS, camW, frozen0, frozen1, back });
  await pg.evaluate(() => { G.paused = false; });

  // 3. клавиши не залипают после Alt+Tab
  await pg.keyboard.down('KeyW'); const held = await pg.evaluate(() => !!IN.keys.KeyW);
  const freed = await pg.evaluate(() => { IN.atk = true; window.dispatchEvent(new Event('blur')); return !IN.keys.KeyW && !IN.atk; }); await pg.keyboard.up('KeyW');
  ok('после ухода из окна зажатые клавиши отпускаются', held && freed);

  // 4. закрытие окна сбрасывает «откуда открыта панель» и выделения
  ok('закрытие окна сбрасывает UI.back / выделения', await pg.evaluate(() => { UI.back = { s: G.settles[0] }; UI.isel = { from: 'bag' }; UI.tsel = {}; closeModal(); return !UI.back && !UI.isel && !UI.tsel; }));

  // 4б. окна с вкладками не прыгают при смене вкладки
  const tops = await pg.evaluate(async () => { const r = []; for (const t of ['troops', 'hero', 'inv', 'journal']) { openPanel(t); await new Promise(z => setTimeout(z, 60)); r.push(Math.round(document.querySelector('#modal .win').getBoundingClientRect().top)); } closeModal(); return r; });
  ok('вкладки окна героя не сдвигают окно', new Set(tops).size === 1, tops);

  // 4в. «В главное меню» с карты сохраняет игру
  const saved = await pg.evaluate(() => { localStorage.removeItem(SAVE_KEY); const day = G.day; ACT.tomenu(); const sv = JSON.parse(localStorage.getItem(SAVE_KEY) || 'null'); return !!sv && sv.day === day && MODE === 'title'; });
  ok('выход в главное меню с карты сохраняет игру', saved);
  await pg.evaluate(() => loadGame()); await pg.waitForFunction(() => __dbg.MODE === 'world', null, { timeout: 10000 }); await sleep(300);

  // 5. приказы армии в бою с карты мира (кнопки и клавиши)
  await pg.evaluate(() => { const G = __dbg.G; const p = G.parties.find(p => p.kind === 'bandit' && !p.hide) || G.parties.find(p => !p.hide); launchBattle(p); });
  await pg.waitForFunction(() => __dbg.MODE === 'battle', null, { timeout: 10000 }); await sleep(800);
  const ord = await pg.evaluate(() => { const B = __dbg.B; B.sel = 3; document.querySelector('#bords .ord[data-o=charge]').click(); return B.groups[0].filter(g => g.units.some(fit)).map(g => g.order); });
  ok('кнопка «В атаку» отдаёт приказ своим отрядам', ord.length > 0 && ord.every(o => o === 'charge'), ord);
  await pg.evaluate(() => { for (const g of __dbg.B.groups[0]) g.order = 'charge'; });
  await pg.mouse.move(800, 450); await pg.keyboard.press('KeyQ'); await sleep(150);
  const hold = await pg.evaluate(() => __dbg.B.groups[0].filter(g => g.units.some(fit)).map(g => g.order));
  ok('клавиша Q — «держать позицию»', hold.every(o => o === 'hold'), hold);
  // 6. выход из идущего боя просит подтверждение
  const conf = await pg.evaluate(() => { ACT.tomenu({}); return __dbg.MODE === 'battle' && !!document.querySelector('#modal [data-act=tomenu][data-ok]'); });
  ok('выход из боя в меню просит подтверждение', conf); await pg.evaluate(() => closeModal());
}

async function sieges(pg) {
  console.log('Осады и враждебность');
  await newSinglePlayer(pg);
  const c = await pg.evaluate(() => { const P = G.player, s = G.settles.find(x => x.fac === 'emp' && x.kind === 'castle'); P.x = s.x - 60; P.y = s.y + 20; P.troops = [{ type: 'n2a', n: 60 }, { type: 'n2s', n: 60 }]; openTown(s); return s.id; });
  ok('в чужом замке есть кнопка «Осадить»', !!(await pg.$('#modal [data-act=siegeask]')));
  await pg.click('#modal [data-act=siegeask]'); await pg.click('#modal [data-act=siegeyes]'); await sleep(200);
  const war = await pg.evaluate(() => ({ hostile: relHostile(G.player, 'emp'), log: G.player.log.slice(-1)[0].txt, siege: !!document.querySelector('#modal [data-act=siegeatk]') }));
  ok('объявление войны: фракция враждебна, в журнале сообщение, открыто окно осады', war.hostile && /враг/.test(war.log) && war.siege, war);
  ok('враждебный замок не пускает в город, а предлагает осаду', await pg.evaluate(id => { closeModal(); openTown(settleById(id)); return !UI.town && !!document.querySelector('#modal [data-act=siegeatk]'); }, c));
  await pg.click('#modal [data-act=siegeatk]'); await pg.waitForFunction(() => __dbg.MODE === 'battle', null, { timeout: 10000 }); await sleep(300);
  await pg.evaluate(() => { giveOrder('charge', 0, 0, 3); __dbg.B.speed = 2; });
  await pg.waitForFunction(() => { const B = __dbg.B, w = B.wall; return B.units.some(u => u.side === 0 && fit(u) && u.x > w.x + w.hw) || B.over; }, null, { timeout: 45000 }).catch(() => {});
  const fight = await pg.evaluate(() => { const B = __dbg.B, w = B.wall; let inWall = 0, inside = 0; for (const u of B.units) if (fit(u)) { if (Math.abs(u.x - w.x) < w.hw && !inGap(u.y, 0)) inWall++; if (u.side === 0 && u.x > w.x + w.hw) inside++; } return { wall: !!w, inWall, inside }; });
  ok('бой-осада: есть стена, бойцы не стоят внутри стены, атакующие проходят через проломы', fight.wall && fight.inWall === 0 && fight.inside > 0, fight);
  await pg.evaluate(() => { for (const u of __dbg.B.units) if (u.side) { u.dead = true; u.hp = 0; } }); await pg.waitForFunction(() => document.querySelector('#modal [data-act=cont2]'), null, { timeout: 10000 });
  await pg.evaluate(() => ACT.cont2()); await sleep(300);
  const own = await pg.evaluate(id => { const s = settleById(id); return { fac: s.fac, mine: s.owner === G.player.id, recruits: s.recruits.length > 0 }; }, c);
  ok('после победы замок наш, в нём можно нанимать', own.fac === 'player' && own.mine && own.recruits, own);
  const gar = await pg.evaluate(id => { const s = settleById(id); const before = troopCount(s.gar); garMove(G.player, s, 'n2a', 5, true); return troopCount(s.gar) - before; }, c);
  ok('можно оставить бойцов в гарнизоне', gar === 5, gar);
  const day = await pg.evaluate(() => { const g0 = G.player.gold; garrisonDay(); return G.player.gold - g0; });
  ok('владение приносит доход', day > 0, day);
  const lost = await pg.evaluate(id => { const s = settleById(id); s.gar = [{ type: 'n1', n: 1 }]; mkParty('lord', 'emp', 'Легат Тест', s.x + 20, s.y + 10, genTroops('emp', 40, .7)); assaultsTick(); return s.fac; }, c);
  ok('враждебный лорд отбивает владение со слабым гарнизоном', lost === 'emp', lost);
}

async function companions(pg) {
  console.log('Спутники');
  await newSinglePlayer(pg);
  const t = await pg.evaluate(() => { const P = G.player; P.gold = 5000; compsInit(); const s = G.settles.find(x => x.kind === 'town' && x.fac === P.culture); G.cpos.ingrid = s.id; G.cpos.halvdan = s.id; openTown(s); ACT.ttab({ t: 'tavern' }); return s.id; });
  ok('в городе есть таверна со спутниками', await pg.evaluate(() => document.querySelectorAll('#modal [data-act=chire]').length >= 2));
  await pg.click('#modal [data-act=chire][data-id=ingrid]'); await pg.click('#modal [data-act=chire][data-id=halvdan]'); await sleep(150);
  const h = await pg.evaluate(() => ({ n: G.player.comps.length, gold: G.player.gold, left: document.querySelectorAll('#modal [data-act=chire][data-id=ingrid], #modal [data-act=chire][data-id=halvdan]').length }));
  ok('спутника можно нанять: он в отряде, золото списано, в таверне его больше нет', h.n === 2 && h.gold === 5000 - 350 - 800 && h.left === 0, h);
  ok('пан Глебио сидит в Мяделе и идёт в отряд бесплатно', await pg.evaluate(() => { const m = G.settles.find(s => s.name === 'Мядель'), g0 = G.player.gold; if (!m || G.cpos.glebio !== m.id) return false; const r = doCompHire(G.player, m, 'glebio'); const ok = !r && G.player.gold === g0 && !!compById(G.player, 'glebio'); doCompFire(G.player, 'glebio'); return ok; }));
  ok('Викентий: арбалет, умение лечит и ослабляет защиту стен при штурме', await pg.evaluate(() => { const s = G.settles.find(x => x.kind === 'town'); G.player.gold = 5000; G.cpos.vikenty = s.id; const r = doCompHire(G.player, s, 'vikenty'), c = compById(G.player, 'vikenty'); if (r || !c) return false; const f = compFx(G.player).f, cfg = battleCfgFor(G.player, { troops: [{ type: 'n1', n: 3 }], fac: 'nord', name: 'Тест', kind: 'raid', x: 0, y: 0 }), ok = f.siege === .25 && f.heal >= .15 && cfg.csiege === .25 && heroWield(c).wt === 'xbow'; doCompFire(G.player, 'vikenty'); return ok; }));
  ok('вкладка «Спутники» в окне отряда', await pg.evaluate(() => { closeModal(); openPanel('comps'); return document.querySelectorAll('#modal .row.comp').length === 2; }));
  ok('в обозе можно выбрать спутника и надеть на него вещь', await pg.evaluate(() => { invAdd(G.player, 'bow_long', 1); ACT.cgear({ id: 'halvdan' }); ACT.equip({ id: 'bow_long' }); const c = compById(G.player, 'halvdan'); return !!document.querySelector('#modal .whobar') && heroEq(c).ranged === 'bow_long' && heroEq(G.player.hero).ranged !== 'bow_long'; }));
  await pg.evaluate(() => { closeModal(); const P = G.player, p = mkParty('bandit', 'bandit', 'Тестовая шайка', P.x + 5, P.y, [{ type: 'b1', n: 8 }]); launchBattle(p); });
  await pg.waitForFunction(() => __dbg.MODE === 'battle', null, { timeout: 10000 }); await sleep(400);
  const b = await pg.evaluate(() => __dbg.B.units.filter(u => u.comp).map(u => [u.comp, u.grp.k]));
  ok('спутники выходят в бой в своих группах (лучница — стрелки)', b.length === 2 && b.some(x => x[0] === 'ingrid' && x[1] === 1), b);
  await pg.evaluate(() => { for (const u of __dbg.B.units) if (u.side) { u.dead = true; u.hp = 0; } }); await pg.waitForFunction(() => document.querySelector('#modal [data-act=cont2]'), null, { timeout: 10000 });
  ok('в итогах боя есть спутники и их опыт', await pg.evaluate(() => /Спутники/.test(el('modal').innerHTML) && G.player.comps.every(c => c.xp > 0 || c.lvl > 1)));
  await pg.evaluate(() => ACT.cont2()); await sleep(200);
  const sv = await pg.evaluate(() => { saveGame(); const d = JSON.parse(localStorage.getItem(SAVE_KEY)); return d.players[0].comps.map(c => c.id).join(',') + '|' + !!d.cpos; });
  ok('спутники и таверны сохраняются', sv === 'ingrid,halvdan|true', sv);
}

async function vassals(pg) {
  console.log('Вассалы-спутники');
  await newSinglePlayer(pg);
  const set = await pg.evaluate(() => { const P = G.player, s = G.settles.find(x => x.kind === 'town' && x.fac !== 'player' && REAL_F.includes(x.fac)); captureSettle(P, s); s.gar = genTroops(sCult(s), 20, .5); const t = G.settles.find(x => x.kind === 'town' && x.fac === 'player'); P.gold = 5000; compsInit(); G.cpos.vikenty = t.id; const r = doCompHire(P, t, 'vikenty'); return { sid: s.id, r, n: P.comps.length }; });
  ok('есть своё владение и спутник в отряде', !set.r && set.n === 1, set);
  await pg.evaluate(() => { closeModal(); openPanel('comps'); });
  ok('у спутника есть кнопка «Дать надел»', await pg.evaluate(() => !!document.querySelector('#modal [data-act=cvpick][data-id=vikenty]')));
  await pg.click('#modal [data-act=cvpick][data-id=vikenty]'); await sleep(100);
  ok('кнопка показывает список наделов', await pg.evaluate(id => !!document.querySelector('#modal [data-act=cvgrant][data-s="' + id + '"]'), set.sid));
  await pg.click('#modal [data-act=cvgrant][data-id=vikenty]'); await sleep(150);
  const g = await pg.evaluate(sid => { const P = G.player, s = settleById(sid), v = cvOfId(P, 'vikenty'), p = v && cvPartyOf(v); return { out: !compById(P, 'vikenty'), vass: P.vass.length, mark: s.vass === 'vikenty', party: !!p && p.kind === 'cvass' && p.fac === 'player', hired: compHired('vikenty'), ui: /Вассал/.test(el('modal').innerHTML) && !!document.querySelector('#modal [data-act=cvrevoke]'), tab: !!document.querySelector('#modal .tab[data-t=comps]') }; }, set.sid);
  ok('надел отдан: спутник стал вассалом, на карте его дружина, в таверне его нет', g.out && g.vass === 1 && g.mark && g.party && g.hired && g.ui && g.tab, g);
  const eco = await pg.evaluate(sid => { const P = G.player, s = settleById(sid), v = cvOfId(P, 'vikenty'), g0 = P.gold, n0 = troopCount(cvPartyOf(v).troops); v.gold = 3000; for (let i = 0; i < 4; i++) { garrisonDay(); cvDay(P); } return { dg: P.gold - g0, n: troopCount(cvPartyOf(v).troops) - n0, vg: v.gold, cap: cvCap(v) }; }, set.sid);
  ok('вассал платит подать, на казну нанимает дружину, содержание списывается', eco.dg > 0 && eco.n > 0 && eco.vg < 3000 + 4 * 400, eco);
  const hs = await pg.evaluate(() => { const v = cvOfId(G.player, 'vikenty'), p = cvPartyOf(v), P = G.player; const bd = { kind: 'bandit', fac: 'bandit' }, lord = f => ({ kind: 'lord', fac: f }); const f1 = REAL_F[0], f2 = REAL_F[1]; P.rel[f1] = 40; P.rel[f2] = -45; return { bandit: hostile(p, bd) && hostile(bd, p), friend: !hostile(p, lord(f1)), foe: hostile(p, lord(f2)), own: !hostile(p, { kind: 'cvass', fac: 'player' }), cara: !hostile(p, { kind: 'caravan', fac: f2 }), hunted: isHostileToPlayer(p, P) === false }; });
  ok('дружина вассала враждует с врагами игрока и не трогает друзей и караваны', hs.bandit && hs.friend && hs.foe && hs.own && hs.cara && hs.hunted, hs);
  const wr = await pg.evaluate(sid => { const P = G.player, s = settleById(sid), v = cvOfId(P, 'vikenty'), p = cvPartyOf(v); p.x = s.x; p.y = s.y; p.troops = genTroops('emp', 60, .8); s.gar = [{ type: 'n1', n: 1 }]; const f = REAL_F.find(x => x !== sCult(s)) || 'emp'; P.rel[f] = -60; mkParty('lord', f, 'Лорд Тест', s.x + 15, s.y + 5, genTroops(f, 40, .6)); assaultsTick(); return { fac: s.fac, party: !!cvPartyOf(v) }; }, set.sid);
  ok('дружина вассала у надела помогает отбить штурм при слабом гарнизоне', wr.fac === 'player', wr);
  const sim = await pg.evaluate(sid => { const P = G.player, v = cvOfId(P, 'vikenty'), p = cvPartyOf(v); for (const m of ['patrol', 'follow', 'guard']) { v.mode = m; for (let i = 0; i < 120; i++) stepWorld(.5); } const s = settleById(sid); return { ok: G.parties.includes(p) ? Math.hypot(p.x - s.x, p.y - s.y) < 400 : true }; }, set.sid);
  ok('дружина ходит по приказам (дозор, за героем, охрана) без ошибок', sim.ok, sim);
  const talk = await pg.evaluate(() => { closeModal(); const p = cvPartyOf(cvOfId(G.player, 'vikenty')); if (!p) return true; openEncounter(p, false); return /Твой вассал/.test(el('modal').innerHTML) && !!document.querySelector('#modal [data-act=cvmode][data-m=patrol]') && !document.querySelector('#modal [data-act=attack]'); });
  ok('при встрече с дружиной вассала — разговор и приказы, а не нападение', talk);
  await pg.evaluate(() => { const P = G.player, v = cvOfId(P, 'vikenty'); closeModal(); ACT.cvmode({ id: 'vikenty', m: 'patrol' }); });
  ok('приказ вассалу меняет режим', await pg.evaluate(() => cvOfId(G.player, 'vikenty').mode === 'patrol'));
  const rv = await pg.evaluate(sid => { const P = G.player, s = settleById(sid), n0 = troopCount(garrisonOf(s)); cvRevoke(P, 'vikenty'); return { back: !!compById(P, 'vikenty'), no: !P.vass.length, mark: s.vass === undefined, gar: troopCount(garrisonOf(s)) >= n0, party: !G.parties.some(p => p.kind === 'cvass') }; }, set.sid);
  ok('надел можно забрать: спутник в отряде, дружина распущена в гарнизон', rv.back && rv.no && rv.mark && rv.gar && rv.party, rv);
  const lost = await pg.evaluate(sid => { const P = G.player, s = settleById(sid); cvGrant(P, 'vikenty', sid); s.fac = 'emp'; s.owner = null; cvDay(P); return { back: !!compById(P, 'vikenty'), no: !P.vass.length, party: !G.parties.some(p => p.kind === 'cvass') }; }, set.sid);
  ok('потерянный надел снимает вассала автоматически', lost.back && lost.no && lost.party, lost);
  ok('лишнее: нельзя отдать чужой город или несуществующего спутника', await pg.evaluate(() => { const s = G.settles.find(x => x.kind === 'town' && x.fac !== 'player'); return !!cvCan(G.player, 'vikenty', s.id) && !!cvCan(G.player, 'nobody', s.id); }));
}

async function undead(pg) {
  console.log('Нашествие нежити');
  await newSinglePlayer(pg);
  const st = await pg.evaluate(() => { crisisInit(); G.crisis.day = G.day; crisisDay(); const U = G.parties.filter(p => p.fac === 'undead'); return { on: G.crisis.on, armies: U.filter(p => p.kind === 'dead').length, raids: U.filter(p => p.kind === 'raid').length, barrows: G.settles.filter(s => s.barrow).length }; });
  ok('кризис начался: курганы, армии и разъезды нежити на карте', st.on && st.barrows >= 1 && st.armies >= 1 && st.raids >= 1, st);
  const fall = await pg.evaluate(() => { const s = G.settles.find(x => x.kind === 'castle' && x.fac !== G.player.culture); for (const q of G.parties.slice()) if (q.hide && q.home === s.id) G.parties.splice(G.parties.indexOf(q), 1); const a = mkParty('dead', 'undead', 'Некромант Тест', s.x, s.y, genUndead(4000, 1)); undeadArrive(a, s); return { fac: s.fac, id: s.id }; });
  ok('большая армия нежити берёт замок, он становится руинами', fall.fac === 'undead', fall);
  ok('руины нежити не пускают внутрь, а предлагают осаду', await pg.evaluate(id => { openTown(settleById(id)); return !UI.town && !!document.querySelector('#modal [data-act=siegeatk]'); }, fall.id));
  await pg.evaluate(() => { closeModal(); const P = G.player, p = mkParty('raid', 'undead', 'Мертвецы', P.x + 5, P.y, genUndead(60, 0)); P.troops = [{ type: 'n2', n: 30 }]; launchBattle(p); });
  await pg.waitForFunction(() => __dbg.MODE === 'battle', null, { timeout: 10000 }); await sleep(500);
  const b = await pg.evaluate(() => { const U = __dbg.B.units.filter(u => u.side === 1); return { n: U.length, undead: U.every(u => u.t.fac === 'undead'), brave: U.every(u => u.mbase >= 999), leader: !!U.find(u => u.leader) }; });
  ok('в бою с мертвецами: все враги — нежить, не бегут, есть некромант', b.n > 0 && b.undead && b.brave && b.leader, b);
  await pg.evaluate(() => { const l = __dbg.B.units.find(u => u.leader); kill(l, __dbg.B.hero); });
  ok('расчленёнка: рубящий удар сносит голову, она летит, тело без головы', await pg.evaluate(() => { const B = __dbg.B, u = B.units.find(x => x.side === 1 && alive(x) && !x.leader), r = Math.random; Math.random = () => 0; B.hk = 'melee'; B.hdt = 'cut'; const n = B.gibs.length; kill(u, B.hero); Math.random = r; return B.gibs.length > n && B.gibs.some(g => g.type === 'head') && !!u.sp.corpseNH; }));
  ok('в меню паузы есть переключатель расчленёнки', await pg.evaluate(() => { openMenu(); const b = document.querySelector('#modal [data-act=gore]'); const was = GORE.on; if (b) b.click(); const now = GORE.on; ACT.gore(); closeModal(); return !!b && now !== was && GORE.on === was; }));
  ok('гибель некроманта рассыпает часть мертвецов', await pg.evaluate(() => __dbg.B.units.filter(u => u.side === 1 && u.dead).length > 1));
  await pg.evaluate(() => { for (const u of __dbg.B.units) if (u.side) { u.dead = true; u.hp = 0; } }); await pg.waitForFunction(() => document.querySelector('#modal [data-act=cont2]'), null, { timeout: 10000 });
  await pg.evaluate(() => ACT.cont2());
}

async function multiPlayer(pg) {
  console.log('Игра вдвоём');
  await pg.evaluate(() => netStart({ name: 'Тест', code: '', banner: 0, culture: 'nord', replace: true }));
  await pg.waitForFunction(() => __dbg.MODE === 'world' && G && G.player && G.player.troops.length, null, { timeout: 15000 }); await sleep(800);
  const dismissRedraws = async () => {
    await pg.evaluate(() => openPanel('troops')); await sleep(300);
    const h0 = await pg.evaluate(() => el('modal').innerHTML), n0 = await pg.evaluate(() => troopCount(G.player.troops));
    await pg.click('#modal [data-act=dismiss]'); await pg.waitForFunction(n => troopCount(G.player.troops) < n, n0, { timeout: 5000 }); await sleep(200);
    const r = await pg.evaluate(h0 => el('modal').innerHTML !== h0, h0); await pg.evaluate(() => closeModal()); return r;
  };
  ok('окно отряда обновляется сразу после действия', await dismissRedraws());
  await pg.evaluate(() => { UI.res = { res: { dead: {} } }; closeModal(); }); // как после окна итогов боя
  ok('…и после боя тоже', await dismissRedraws());
}

(async () => {
  execFileSync(process.execPath, [path.join(ROOT, 'build.mjs')], { stdio: 'inherit' });
  const port = await freePort(), data = fs.mkdtempSync(path.join(os.tmpdir(), 'iron-test-'));
  const srv = spawn(process.execPath, [path.join(ROOT, 'server/index.js')], { env: Object.assign({}, process.env, { PORT: String(port), DATA_DIR: data, ROOM_CODE: '' }), stdio: ['ignore', 'pipe', 'inherit'] });
  const browser = await chromium.launch(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH, args: ['--no-sandbox'] } : {});
  const errs = [];
  try {
    for (let i = 0; i < 50; i++) { try { const r = await fetch('http://localhost:' + port + '/health'); if (r.ok) break; } catch (e) { } await sleep(100); }
    const open = async () => { const pg = await browser.newPage({ viewport: { width: 1600, height: 900 } }); pg.on('pageerror', e => errs.push(e.message)); await pg.goto('http://localhost:' + port + '/'); await pg.waitForFunction(() => window.__dbg && __dbg.MODE === 'title', null, { timeout: 15000 }); await sleep(300); return pg; };
    await singlePlayer(await open());
    await sieges(await open());
    await companions(await open());
    { const vp = await open(); await vassals(vp); await vp.close(); } // страница больше не нужна: фоновые вкладки грузят процессор и тормозят игру вдвоём
    await undead(await open());
    await multiPlayer(await open());
  } catch (e) { console.error(e); failed++; }
  ok('нет ошибок в консоли страницы', errs.length === 0, errs.slice(0, 3));
  await browser.close(); await new Promise(r => { srv.on('exit', r); srv.kill(); setTimeout(r, 3000); }); fs.rmSync(data, { recursive: true, force: true });
  console.log(failed ? '\nПровалено проверок: ' + failed : '\nВсё прошло');
  process.exit(failed ? 1 : 0);
})();
