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
