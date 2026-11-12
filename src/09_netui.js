/* ================= сетевой интерфейс: союз с другом (передачи, фракция) ================= */
function allyOther() { return G && G.players.find(q => q.id !== NET.you) || null; }
function allyBody() {
  const P = G.player, o = allyOther(); let b = '';
  if (!o) return '<div class="note">Друг сейчас не в игре.</div>';
  const d = Math.round(Math.hypot(o.x - P.x, o.y - P.y)), near = d <= 90, busy = P.busy || o.busy;
  b += '<div class="note"><b>' + o.name.replace(/</g, '&lt;') + '</b>' + (o.fname ? ' [' + o.fname.replace(/</g, '&lt;') + ']' : '') + ' · расстояние ' + d + (near ? ' — можно передавать' : ' — нужно подойти ближе (до 90)') + '</div>';
  const dis = near && !busy ? '' : ' disabled';
  b += '<h3>Передать золото и еду</h3><div class="row sm"><div class="grow"><div class="nm">Золото</div><div class="ds">у тебя ' + fmt(P.gold) + '</div></div>' + [50, 200, 1000].map(n => '<button class="btn sm" data-act="give" data-k="gold" data-n="' + n + '"' + dis + '>' + n + '</button>').join('') + '<button class="btn sm" data-act="give" data-k="gold" data-n="999999"' + dis + '>Все</button></div>';
  b += '<div class="row sm"><div class="grow"><div class="nm">Провизия</div><div class="ds">у тебя ' + P.food + '</div></div>' + [10, 30].map(n => '<button class="btn sm" data-act="give" data-k="food" data-n="' + n + '"' + dis + '>' + n + '</button>').join('') + '<button class="btn sm" data-act="give" data-k="food" data-n="999999"' + dis + '>Все</button></div>';
  b += '<h3 style="margin-top:14px">Передать бойцов</h3>';
  for (const s of P.troops) { const t = TROOPS[s.type]; b += '<div class="row sm"><div class="grow"><div class="nm">' + t.name + '</div><div class="ds">в отряде ' + s.n + '</div></div><button class="btn sm" data-act="give" data-k="troop" data-t="' + s.type + '" data-n="1"' + dis + '>1</button><button class="btn sm" data-act="give" data-k="troop" data-t="' + s.type + '" data-n="5"' + dis + '>5</button><button class="btn sm" data-act="give" data-k="troop" data-t="' + s.type + '" data-n="999"' + dis + '>Все</button></div>'; }
  b += '<h3 style="margin-top:14px">Фракция</h3>';
  const F = P.fac;
  if (F) {
    b += '<div class="note">Ты во фракции <b>«' + F.name.replace(/</g, '&lt;') + '»</b>. Участники: ' + F.members.map(x => x.replace(/</g, '&lt;')).join(', ') + '. Знамя и репутация у вас общие.</div><div style="display:flex;gap:8px;flex-wrap:wrap">' + (F.members.length < 2 && o && !o.fname ? '<button class="btn sm pri" data-act="finvite">Пригласить друга</button>' : '') + '<button class="btn sm danger" data-act="fleave">Покинуть фракцию</button></div>';
  } else {
    b += '<div class="note">Основай фракцию: общее знамя, имя и репутация с королевствами. Друга можно пригласить, а можно остаться отдельно.</div><div style="display:flex;gap:8px;align-items:center"><input type="text" id="fname" maxlength="20" placeholder="Название фракции" style="flex:1" autocomplete="off"><button class="btn sm pri" data-act="fcreate">Основать</button></div>';
    if (P.finv) b += '<div class="note" style="margin-top:10px">Тебя зовут во фракцию «' + P.finv.name.replace(/</g, '&lt;') + '» (' + P.finv.from.replace(/</g, '&lt;') + ').</div><div style="display:flex;gap:8px"><button class="btn sm pri" data-act="faccept">Вступить</button><button class="btn sm" data-act="fdecline">Отказаться</button></div>';
  }
  return b;
}
ACT.give = function (d) { NET.send({ t: 'give', k: d.k, type: d.t, n: +d.n }); sfx('coin'); };
ACT.fcreate = function () { const i = el('fname'); NET.send({ t: 'fcreate', name: i ? i.value : '' }); };
ACT.finvite = function () { NET.send({ t: 'finvite' }); };
ACT.faccept = function () { NET.send({ t: 'faccept' }); };
ACT.fdecline = function () { NET.send({ t: 'fdecline' }); };
ACT.fleave = function () { NET.send({ t: 'fleave' }); };
function netInvite() { const P = G && G.player; if (P && P.finv && !P.finvSeen) { P.finvSeen = P.finv.fid; toast(P.finv.from + ' зовёт во фракцию «' + P.finv.name + '» (Герой → Союз)'); } else if (P && !P.finv) P.finvSeen = null; }

function netJoinUI() {
  const w = el('wjoin'); if (!w) return; const P = G && G.player, o = allyOther();
  const ok = NET.on && MODE === 'world' && P && o && o.bid && !P.busy && !P.in && !UI.open && Math.hypot(o.x - P.x, o.y - P.y) <= 120;
  if (!ok) { if (!w.hidden) { w.hidden = true; w.dataset.b = ''; } return; }
  if (w.dataset.b !== String(o.bid)) { w.dataset.b = String(o.bid); w.innerHTML = '<span><b>' + o.name.replace(/</g, '&lt;') + '</b> в бою</span><button class="btn sm pri" data-act="bjoin" data-id="' + o.bid + '">Присоединиться</button>'; }
  w.hidden = false;
}
ACT.bjoin = function (d) { NET.send({ t: 'bjoin', id: +d.id }); };
