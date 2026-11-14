// Сборка одного файла index.html из src/. Запуск: node build.mjs
import fs from 'fs';
const r = f => fs.readFileSync(new URL('./src/' + f, import.meta.url), 'utf8');
const js = ['01_core.js', '01b_gear.js', '01c_perks.js', '02_art.js', '03_battle.js', '03b_gore.js', '04_audio.js', '05_world.js', '05b_worldart.js', '05c_logic.js', '05d_trade.js', '05e_comps.js', '05f_undead.js', '05g_war.js', '05h_vassals.js', '08_net.js', '06_ui.js', '06b_inventory.js', '06c_hero.js', '06d_comps.js', '06e_war.js', '06h_vassals.js', '06f_jquests.js', '06g_jfactions.js', '09_netui.js', '07_main.js'].map(r).join('\n').replace(/<\/script/g, '<\\/script');
const html = r('shell.html').replace('/*CSS*/', () => ['style.css', 'j_quests.css', 'j_factions.css'].map(r).join('\n')).replace('/*JS*/', () => js);
fs.writeFileSync(new URL('./index.html', import.meta.url), html);
console.log('index.html', Math.round(html.length / 1024) + ' KB');
