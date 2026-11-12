// Сборка одного файла index.html из src/. Запуск: node build.mjs
import fs from 'fs';
const r = f => fs.readFileSync(new URL('./src/' + f, import.meta.url), 'utf8');
const js = ['01_core.js', '02_art.js', '03_battle.js', '04_audio.js', '05_world.js', '05b_worldart.js', '05c_logic.js', '05d_trade.js', '08_net.js', '06_ui.js', '06b_inventory.js', '09_netui.js', '07_main.js'].map(r).join('\n').replace(/<\/script/g, '<\\/script');
const html = r('shell.html').replace('/*CSS*/', () => r('style.css')).replace('/*JS*/', () => js);
fs.writeFileSync(new URL('./index.html', import.meta.url), html);
console.log('index.html', Math.round(html.length / 1024) + ' KB');
