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
  const c = await pg.evaluate(() => { const P = G.player, s = G.settles.find(x => x.fac === 'emp' && x.kind === 'castle'); P.x = s.x - 60; P.y = s.y + 20; P.troops = [{ type: 'n2a', n: 20 }, { type: 'n2s', n: 20 }]; openTown(s); return s.id; });
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
    await multiPlayer(await open());
  } catch (e) { console.error(e); failed++; }
  ok('нет ошибок в консоли страницы', errs.length === 0, errs.slice(0, 3));
  await browser.close(); await new Promise(r => { srv.on('exit', r); srv.kill(); setTimeout(r, 3000); }); fs.rmSync(data, { recursive: true, force: true });
  console.log(failed ? '\nПровалено проверок: ' + failed : '\nВсё прошло');
  process.exit(failed ? 1 : 0);
})();
