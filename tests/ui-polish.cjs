/* Регрессии UI: реальные клики/клавиши, сравнение без изменения снаряжения, узкий экран. */
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path'), http = require('http'), assert = require('assert/strict');
const root = path.join(__dirname, '..'), out = process.env.UI_SCREENSHOTS;
async function run() {
  const server = http.createServer((req, res) => { res.setHeader('Content-Type', 'text/html; charset=utf-8'); res.end(fs.readFileSync(path.join(root, 'index.html'))); });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const browser = await chromium.launch(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {});
  const page = await browser.newPage({ viewport: { width: 1366, height: 768 } }), errors = [];
  page.on('pageerror', e => errors.push(e.message));
  const shot = async name => { if (out) { fs.mkdirSync(out, { recursive: true }); await page.screenshot({ path: path.join(out, name + '.png') }); } };
  try {
    await page.goto('http://127.0.0.1:' + server.address().port);
    await page.waitForSelector('[data-act=newgame]'); await page.click('[data-act=newgame]');
    for (let i = 0; i < 5 && await page.evaluate(() => __dbg.MODE) !== 'world'; i++) { await page.waitForTimeout(600); const b = page.locator('#modal:not([hidden]) .btn.pri').first(); if (await b.count()) await b.click(); }
    await page.waitForFunction(() => __dbg.MODE === 'world');
    await page.evaluate(() => { closeModal(); G.paused = true; WC.z = .8; const P = G.player; P.path = findPath(P.x, P.y, P.x + 150, P.y + 40) || []; P.pi = 0; saveGame(true); });
    await page.waitForTimeout(300); await shot('ui-map');
    const pure = await page.evaluate(() => {
      const P = G.player; invAdd(P, 'body_plate', 1); invAdd(P, 'tw_sword', 1); openPanel('inv');
      const original = JSON.stringify(P.hero), comp = Object.assign({}, P.hero, { name: 'Проверка спутника', eq: { ...heroEq(P.hero), body: 'body_plate' } });
      const c0 = JSON.stringify(comp); const html = gearComparison(ITEM.body_mail, comp), two = gearComparison(ITEM.tw_sword, P.hero);
      return { same: JSON.stringify(P.hero) === original && JSON.stringify(comp) === c0, companion: html.includes('Проверка спутника') && html.includes('Латы'), two: !!two, quality: document.querySelectorAll('.qualitymark').length };
    });
    assert(pure.same && pure.companion && pure.two && pure.quality > 0, JSON.stringify(pure));
    await page.locator('.igrid .tile[data-item="body_plate"]').hover(); await page.waitForSelector('#gearPeek:not([hidden])');
    assert.match(await page.locator('#gearPeek').innerText(), /Броня/); await shot('ui-equipment');
    await page.keyboard.press('Escape'); assert(await page.locator('#gearPeek').isHidden());
    await page.evaluate(() => { closeModal(); QK.me = 'khan'; QK.foe = 'emp'; QK.size = 50; startQuick(); B.paused = true; B.cam.x = B.hero.x; B.cam.y = B.hero.y; });
    await page.waitForTimeout(200);
    await page.click('#bords [data-o=charge]'); await page.waitForTimeout(180);
    assert.equal(await page.locator('#bords [data-o=charge]').getAttribute('aria-pressed'), 'true');
    await page.keyboard.press('KeyE'); await page.waitForTimeout(180);
    assert.equal(await page.locator('#bords [data-o=follow]').getAttribute('aria-pressed'), 'true');
    await page.keyboard.press('Digit1'); await page.waitForTimeout(180);
    assert.equal(await page.locator('#bgroups [data-g="0"]').getAttribute('aria-pressed'), 'true');
    await page.keyboard.press('KeyF'); await page.waitForTimeout(180);
    assert.equal(await page.locator('#bords [data-o=back]').getAttribute('aria-pressed'), 'true');
    await page.mouse.move(820, 310); await page.keyboard.press('KeyQ'); await page.waitForTimeout(180); await shot('ui-battle');
    for (const viewport of [{ width: 1100, height: 620 }, { width: 1366, height: 768 }]) {
      await page.setViewportSize(viewport); await page.waitForTimeout(150);
      assert(await page.evaluate(() => {
        const boxes = ['bhero', 'borders', 'bmini'].map(id => document.getElementById(id).getBoundingClientRect());
        const inside = boxes.every(r => r.x >= 0 && r.y >= 0 && r.right <= innerWidth && r.bottom <= innerHeight);
        const intersect = (a, b) => a.x < b.right && a.right > b.x && a.y < b.bottom && a.bottom > b.y;
        return inside && !intersect(boxes[0], boxes[1]) && !intersect(boxes[1], boxes[2]);
      }), 'HUD overlaps at ' + JSON.stringify(viewport));
      if (viewport.width === 1100) await shot('ui-battle-laptop');
    }
    const drawing = await page.evaluate(() => {
      const ctx = document.getElementById('cv').getContext('2d'), rows = [], saved = Math.random; let calls = 0;
      Math.random = () => { calls++; return .5; };
      try { commandDraw(ctx); const u = B.units.find(u => u.t.mounted); if (u) unitPolish(ctx, { ...u, flash: .1, vx: 80, vy: 0 }, 80); } finally { Math.random = saved; }
      settlementLabels(ctx, [['Первый', 200, 200, '#fff', 16], ['Второй', 200, 200, '#fff', 16], ['Третий', 200, 200, '#fff', 13]], (t, x, y) => rows.push([x, y]));
      return { calls, labels: rows.length, distinct: new Set(rows.map(r => r[1])).size };
    });
    assert.equal(drawing.calls, 0); assert.equal(drawing.labels, 3); assert.equal(drawing.distinct, 3);
    await page.evaluate(() => { for (const group of selectedGroups()) group.units.forEach(u => { u.dead = true; }); updateBattleHud(); });
    assert(await page.locator('#bords [data-o=charge]').isDisabled());
    for (const [faction, name] of [['emp', 'ui-grass'], ['nord', 'ui-snow']]) {
      await page.evaluate(faction => { QK.me = faction; startQuick(); B.paused = true; B.cam.x = B.hero.x; B.cam.y = B.hero.y; B.t = 1; const u = B.units.find(u => !u.isHero); u.flash = .1; }, faction);
      await page.waitForTimeout(180); await shot(name);
    }
    await page.evaluate(() => { gotoTitle(); loadGame(); closeModal(); openTown(G.settles.find(s => s.kind === 'town')); });
    await page.waitForFunction(() => __dbg.MODE === 'world', null, { timeout: 20000 }); // loadGame грузит мир через setTimeout, на медленном CI режим ещё «loading»
    assert.equal(await page.evaluate(() => __dbg.MODE), 'world');
    await page.waitForTimeout(180); await shot('ui-town');
    assert.equal(await page.evaluate(() => !!window.__err), false);
    assert.deepEqual(errors, []); console.log('UI: приказы, клавиши, сравнение спутника, отсутствие мутаций и размеры 1100×620 / 1366×768 — всё прошло');
  } finally { await browser.close(); await new Promise(r => server.close(r)); }
}
run().catch(e => { console.error(e); process.exitCode = 1; });
