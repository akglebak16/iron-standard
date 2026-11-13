/* ================= войны и служба: интерфейс (только одиночная игра) ================= */
function oathBody(s) {
  const P = G.player, f = s.fac, A = facsAlive(), wars = Object.keys(G.wars || {}).map(k => k.split('|')), mine = P.liege === f, why = oathCan(P, f);
  let b = '<div class="note">Фракция: <b>' + FACTIONS[f].name + '</b>. Отношения: ' + relName(P.rel[f]) + ' (' + Math.round(P.rel[f]) + '). ' + (P.liege ? 'Ты служишь: <b>' + FACTIONS[P.liege].name + '</b>.' : 'Ты вольный наёмник.') + '</div>';
  if (mine) {
    b += '<div class="card"><h3>Ты вассал ' + FACTIONS[f].gen + '</h3><p class="note">Жалованье: ' + (16 + (P.hero.lvl || 1) * 6) + ' золота в день. Враги сюзерена — твои враги. Когда он созывает войска, будь рядом с осаждаемым городом: это награда и шанс получить лен. Неявок: ' + (P.strikes || 0) + ' из 3.</p>' + (P.call ? '<p class="note">Зов: ' + settleById(P.call.tid).name + (P.call.joined ? ' (ты участвовал)' : ', срок до дня ' + Math.ceil(P.call.until / 24)) + '.</p>' : '') + '<button class="btn sm danger" data-act="leavesvc">Оставить службу</button></div>';
  } else if (!P.liege) {
    b += '<div class="card"><h3>Принести присягу</h3><p class="note">Нужен ' + OATH_LVL + ' уровень героя и отношения от ' + OATH_REL + '. Сюзерен платит жалованье и награждает за походы, но враги фракции станут твоими.</p><button class="btn sm pri" data-act="swear" ' + (why ? 'disabled' : '') + '>Присягнуть</button>' + (why ? '<p class="note">' + why + '</p>' : '') + '</div>';
  } else b += '<div class="note">Сначала оставь службу у ' + FACTIONS[P.liege].gen + '.</div>';
  b += '<h3 style="margin:14px 0 6px">Мир</h3><div class="cols">' + A.map(x => '<div class="card"><h3>' + FACTIONS[x].name + '</h3><div class="kv"><span>Владения</span><b>' + holdOf(x).all + '</b></div><div class="kv"><span>Воюет с</span><b>' + (wars.filter(w => w.includes(x)).map(w => FACTIONS[w[0] === x ? w[1] : w[0]].name).join(', ') || 'мир') + '</b></div></div>').join('') + '</div>';
  return b;
}
ACT.swear = function () { const r = swear(G.player, UI.town.s.fac); if (r) toast(r); else { sfx('order'); toast('Ты принёс присягу'); } renderTown(); };
ACT.leavesvc = function () { leaveService(G.player, null); sfx('click'); renderTown(); };
/* значки схваток и осад на карте мира */
function drawWar(g, label) {
  const t = performance.now() / 400;
  for (const sk of G.skirm || []) { const x = sk.x, y = sk.y - 4, pu = 14 + Math.sin(t) * 2; g.save(); g.strokeStyle = 'rgba(230,70,40,.8)'; g.lineWidth = 2; g.beginPath(); g.arc(x, y, pu, 0, TAU); g.stroke(); g.strokeStyle = '#ffd9a0'; g.lineWidth = 2.4; g.lineCap = 'round'; g.beginPath(); g.moveTo(x - 7, y - 7); g.lineTo(x + 7, y + 7); g.moveTo(x + 7, y - 7); g.lineTo(x - 7, y + 7); g.stroke(); g.restore(); label('Бой', x, y - 22, '#ff9a7a', 12); }
  for (const s of G.settles) if (s.siege) { g.save(); g.strokeStyle = 'rgba(230,70,40,.85)'; g.lineWidth = 3; g.setLineDash([8, 5]); g.beginPath(); g.ellipse(s.x, s.y + 6, s.kind === 'castle' ? 58 : 66, 24, 0, 0, TAU); g.stroke(); g.restore(); label('Осада · ' + FACTIONS[s.siege.f].name.split(' ')[0], s.x, s.y - 52, '#ff9a7a', 13); }
}

/* переговоры с лордом: переманить весь род к сюзерену игрока */
function parleyBody(p) {
  const P = G.player, c = clanOf(p), T = CLAN_TR[c.trait], why = lureCan(P, p), cost = lureCost(c), ch = lureChance(P, c), lv = ch > .55 ? ['Хорошие', 'g'] : ch > .3 ? ['Средние', 'b'] : ['Низкие', 'r'];
  return '<div class="whead"><img alt="" src="' + crestURL(c.fac) + '"><h2>' + c.name + '<span class="sub">' + FACTIONS[c.fac].name + ' · ' + clanMembers(c).length + ' лорда · ' + clanForce(c) + ' бойцов</span></h2></div><div class="wbody">' +
    '<div class="card"><h3>' + T.n + ' род</h3><p class="note">' + T.d[0].toUpperCase() + T.d.slice(1) + '.</p><div class="kv"><span>Верность</span><b>' + (c.loy > 75 ? 'крепкая' : c.loy > 50 ? 'обычная' : c.loy > 30 ? 'шаткая' : 'на исходе') + '</b></div></div>' +
    (why ? '<div class="note">' + why + '</div>' : '<div class="note">Весь род перейдёт к ' + FACTIONS[P.liege].gen + ' вместе с лордами и отрядами. Задаток: <b>' + cost + '</b> золота. При отказе пропадёт половина, и отношения с этой фракцией ухудшатся. Сюзерен вернёт 40% при успехе. Шансы: <span class="tag ' + lv[1] + '">' + lv[0] + '</span></div>') + '</div>' +
    '<div class="wfoot"><button class="btn" data-act="parleyback">Назад</button>' + (why ? '' : '<button class="btn pri" data-act="lure">Предложить ' + cost + '</button>') + '</div>';
}
ACT.parley = function () { openModal(parleyBody(UI.enc.p), 'narrow'); };
ACT.parleyback = function () { const e = UI.enc; openEncounter(e.p, e.forced); };
ACT.lure = function () {
  const e = UI.enc, r = lureTry(G.player, e.p); sfx(r.ok ? 'coin' : 'click'); toast(r.txt); closeModal();
  if (r.ok) { e.p.cd = 3; return; }
  if (isHostileToPlayer(e.p, G.player)) openEncounter(e.p, e.forced); else e.p.cd = 3;
};
