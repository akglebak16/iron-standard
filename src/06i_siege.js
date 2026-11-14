/* ================= осада: интерфейс и картинка на карте мира =================
   Выбор после штурма (разграбить или пощадить) и пожары на карте. Только клиент. */
ACT.sgsack = function () { const P = G.player, s = settleById(P.sgPend); P.sgPend = null; if (s) sgSack(P, s); sfx('coin'); closeModal(); afterBattle(); };
ACT.sgspare = function () { const P = G.player, s = settleById(P.sgPend); P.sgPend = null; if (s) sgSpare(P, s); sfx('click'); closeModal(); afterBattle(); };
// пламя над горящими поселениями, дым над сильно повреждёнными; зовётся из drawWar
function sgDraw(g, t, label) {
  for (const s of G.settles) {
    if (s.blk && typeof label === 'function') label('Блокада · еда ' + Math.ceil(sgFood(s)) + ' дн.', s.x, s.y - 60, '#ffd27a', 12);
    const fire = s.fire > 0, smoke = !fire && (s.dmg || 0) > .3; if (!fire && !smoke) continue;
    const bx = s.x, by = s.y - 8;
    g.save();
    for (let i = 0; i < 3; i++) { const p = (t * .35 + i / 3 + s.id * .13) % 1; g.globalAlpha = (1 - p) * (fire ? .5 : .35); g.fillStyle = '#4a4540'; g.beginPath(); g.arc(bx + Math.sin(p * 5 + i) * 8 + (i - 1) * 8, by - 18 - p * 46, 7 + p * 11, 0, TAU); g.fill(); }
    if (fire) for (let i = 0; i < 6; i++) {
      const ox = (i - 2.5) * 8 + Math.sin(s.id + i * 2) * 3, h = 13 + 7 * Math.sin(t * 3.2 + i * 2.1 + s.id), x = bx + ox, y = by + Math.abs(Math.cos(s.id * 3 + i)) * 6;
      g.globalAlpha = .9; g.fillStyle = i % 2 ? '#ff9a2e' : '#ffd26a'; g.beginPath(); g.moveTo(x - 5, y); g.quadraticCurveTo(x - 3, y - h * .6, x + Math.sin(t * 2 + i) * 2.5, y - h); g.quadraticCurveTo(x + 3, y - h * .5, x + 5, y); g.closePath(); g.fill();
    }
    g.restore();
    if (fire && typeof label === 'function') label('Пожар', s.x, s.y - 74, '#ffb066', 12);
  }
}

// кнопки в окне осады (зовёт openSiege) и окно переговоров
function sgButtons(s) { if (!REAL_F.includes(s.fac)) return ''; return '<button class="btn" data-act="sgtalk">Переговоры</button>' + (s.blk ? '' : '<button class="btn" data-act="sgblock">Блокада</button>'); }
function sgFoodText(s) { const f = sgFood(s); return f <= 0 ? 'кончилась' : f < 3 ? 'на исходе (около ' + Math.ceil(f) + ' дн.)' : 'около ' + Math.ceil(f) + ' дн.'; }
const sgChanceWord = p => p < .2 ? 'почти никаких' : p < .4 ? 'слабые' : p < .6 ? 'неплохие' : p < .8 ? 'хорошие' : 'отличные';
function openTalk(s, msg) {
  const P = G.player, wait = Math.max(0, (s.talkT || 0) - nowH()), price = sgBribe(s), p1 = sgTalkChance(P, s, false), p2 = sgTalkChance(P, s, true);
  openModal('<div class="whead"><img alt="" src="' + crestURL(s.fac) + '"><h2>Переговоры: ' + s.name + '<span class="sub">Запасы еды в городе: ' + sgFoodText(s) + '</span></h2></div><div class="wbody">' + (msg ? '<div class="note">' + msg + '</div>' : '') +
    '<div class="note">Чем больше твоё войско, чем выше Обаяние героя, чем голоднее и разрушеннее город, тем охотнее он сдаётся. Неудача закрывает переговоры на сутки и портит отношения.</div>' +
    '<div class="kv"><span>Потребовать сдачи</span><b>шансы ' + sgChanceWord(p1) + '</b></div><div class="kv"><span>Выкуп за ' + price + ' золота</span><b>шансы ' + sgChanceWord(p2) + '</b></div>' + (wait ? '<div class="note">Гонцов не пускают ещё ' + wait + ' ч.</div>' : '') +
    '</div><div class="wfoot"><button class="btn" data-act="sgback">Назад</button><button class="btn" data-act="sgdemand"' + (wait ? ' disabled' : '') + '>Потребовать сдачи</button><button class="btn pri" data-act="sgbribe"' + (wait || P.gold < price ? ' disabled' : '') + '>Предложить ' + price + ' золота</button></div>', 'narrow');
}
function sgTalkGo(gold) {
  const P = G.player, s = UI.siege.s, r = sgTalk(P, s, gold); if (r === null) return openTalk(s);
  if (r) { sfx('coin'); openModal('<div class="whead"><h2>Город сдался<span class="sub">' + s.name + '</span></h2><span class="tag g">Без боя</span></div><div class="wbody"><div class="note good">Ворота открыты. Гарнизон сложил оружие, жители целы. Зайди в город и оставь там гарнизон.</div></div><div class="wfoot"><button class="btn pri" data-act="siegeoff">Хорошо</button></div>', 'narrow'); }
  else { sfx('click'); openTalk(s, 'Гонцов прогнали: «Мы не сдадимся». Отношение к ним ухудшилось.'); }
}
ACT.sgtalk = function () { openTalk(UI.siege.s); };
ACT.sgback = function () { openSiege(UI.siege.s); };
ACT.sgdemand = function () { sgTalkGo(false); };
ACT.sgbribe = function () { sgTalkGo(true); };
ACT.sgblock = function () { const P = G.player, s = UI.siege.s; sgBlockStart(P, s); sfx('horn'); closeModal(); };
