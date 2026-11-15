// Authoring only: rasterize the final, cascaded original CSS into native nine-patch assets.
// Requires Playwright and Chrome; no browser is used by the Godot game.
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');
const root = path.resolve(__dirname, '../..');
(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const page = await browser.newPage({ viewport: { width: 1366, height: 768 }, deviceScaleFactor: 1 });
  const css = ['style.css', 'polish.css'].map(n => fs.readFileSync(path.join(root, 'src', n), 'utf8')).join('\n');
  for (const [name, cls, width, height] of [
    ['plank', 'plank', 108, 96], ['button', 'btn', 108, 50], ['primary', 'btn pri', 108, 50],
    ['danger', 'btn danger', 108, 50], ['order', 'ord', 78, 66], ['tile', 'tile', 76, 76],
    ['square', 'sq plank thin', 52, 52], ['group', 'grp', 84, 72], ['group_on', 'grp on', 84, 72]
  ]) {
    await page.setContent(`<style>${css}\nhtml,body{background:transparent!important}#asset{position:absolute;inset:0 auto auto 0;width:${width}px;height:${height}px;padding:0;margin:0;min-width:0;box-sizing:border-box}</style><div id="asset" class="${cls}"></div>`);
    await page.locator('#asset').screenshot({ path: path.join(root, 'godot/apps/godot/visuals/assets', name + '.png'), omitBackground: true });
  }
  for (const [name, html, selector] of [
    ['timer', '<div id="btimer"></div>', '#btimer'],
    ...['st', 'mo', 'ar', 'hp'].map(kind => ['bar_' + kind, `<div class="bar ${kind}" style="width:124px;--p:100%"><i></i></div>`, '.bar i'])
  ]) {
    await page.setContent(`<style>${css}\nhtml,body{background:transparent!important}#btimer{margin:0}</style>${html}`);
    await page.locator(selector).screenshot({path:path.join(root, 'godot/apps/godot/visuals/assets', name + '.png'),omitBackground:true});
  }
  await browser.close();
  console.log('Exported final CSS planks, beveled buttons, order buttons and tiles');
})().catch(error => { console.error(error); process.exitCode = 1; });
