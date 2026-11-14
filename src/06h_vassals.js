/* ================= окна вассалов-спутников: надел в «Спутниках», беседа с вассалом на карте =================
   Логика: 05h_vassals.js. Кнопки встроены в compsBody() (06d_comps.js), встреча — в openEncounter() (06_ui.js). */
const cvModeBtns = (v, extra) => Object.keys(CV_MODES).map(m => '<button class="btn sm ' + ((v.mode || 'guard') === m ? 'pri' : '') + '" title="' + CV_MODES[m][1] + '" data-act="cvmode" data-id="' + v.cid + '" data-m="' + m + '">' + CV_MODES[m][0] + '</button>').join('') + (extra || '');
// кнопка «Дать надел» в строке спутника
function cvBtn(c) { if (NET.on) return ''; return '<button class="btn sm pri" data-act="cvpick" data-id="' + c.id + '">' + (UI.cvpick === c.id ? 'Выбери надел ↓' : 'Дать надел') + '</button>'; }
// список наделов под строкой спутника, пока он выбирается
function cvPickHtml(c) {
  if (UI.cvpick !== c.id) return ''; const P = G.player, fiefs = cvFiefs(P).filter(s => s.vass === undefined);
  let b = '<div class="note" style="margin-left:8px">';
  if (cvList(P).length >= CV_MAX) b += 'Вассалов уже ' + CV_MAX + ': больше не прокормить.';
  else if (!fiefs.length) b += 'Надел — твой город или замок без вассала. Сначала возьми его: захвати или получи от сюзерена.';
  else b += 'Вассал отдаёт тебе ' + Math.round(CV_TRIB * 100) + '% чистого дохода надела, остальное тратит на содержание гарнизона и свою дружину. Выбери надел:' + fiefs.map(s => '<div class="kv"><span>' + s.name + ' <span class="dim">(' + (s.kind === 'town' ? 'город' : 'замок') + ', доход ' + cvIncome(s) + ' в день, гарнизон ' + troopCount(garrisonOf(s)) + ')</span></span><button class="btn sm pri" data-act="cvgrant" data-id="' + c.id + '" data-s="' + s.id + '">Отдать в надел</button></div>').join('');
  return b + '</div>';
}
function cvRow(P, v) {
  const s = settleById(v.sid), p = cvPartyOf(v), conf = UI.cvrev === v.cid;
  return '<div class="row comp"><img alt="" src="' + compImg(v.c) + '"><div class="grow"><div class="nm">' + v.c.name + ' <span class="tag g">Вассал</span><span class="tag">Ур. ' + v.c.lvl + '</span></div>' +
    '<div class="ds">Надел: <b>' + (s ? s.name : '—') + '</b> · подать тебе ' + (v.trib || Math.round(cvIncome(s || { kind: 'x' }) * CV_TRIB)) + ' в день · его казна ' + Math.round(v.gold) + '</div>' +
    '<div class="ds">' + (p ? 'Дружина: <b>' + troopCount(p.troops) + '</b> из ' + cvCap(v) + ' бойцов · содержание ' + cvWage(p) + ' в день' : 'Дружина разбита, соберёт новую через ' + Math.max(1, v.rest) + ' дн.') + '</div>' +
    '<div class="ds">Приказ: <b>' + CV_MODES[v.mode || 'guard'][0] + '</b> — ' + CV_MODES[v.mode || 'guard'][1] + '</div></div>' +
    '<div class="acts col">' + cvModeBtns(v) + '<button class="btn sm" data-act="cvgive" data-id="' + v.cid + '" ' + (P.gold >= 200 ? '' : 'disabled') + '>Дать 200 золота</button>' +
    (conf ? '<button class="btn sm danger" data-act="cvrevokeok" data-id="' + v.cid + '">Точно забрать?</button>' : '<button class="btn sm danger" data-act="cvrevoke" data-id="' + v.cid + '">Забрать надел</button>') + '</div></div>';
}
function vassalsBlock(P) {
  const L = cvList(P); if (!L.length || NET.on) return '';
  return '<h3 style="margin:14px 0 6px">Вассалы</h3><div class="note">Вассал живёт на своём наделе и содержит его гарнизон, платит тебе подать и сам нанимает дружину на остаток дохода. Дружина бьёт врагов у надела, помогает отбить штурм; золото в казну можно добавить, чтобы набор шёл быстрее. Приказ можно отдать и при встрече с ним на карте.</div>' + L.map(v => cvRow(P, v)).join('');
}
// встреча с дружиной вассала на карте: разговор вместо «разойтись или напасть»
function vassalTalk(p) {
  const P = G.player, v = cvOfId(P, p.cid); if (!v) return; UI.cvp = p; UI.enc = null; P.path = []; P.tid = null; G.wait = false;
  const s = settleById(v.sid), list = p.troops.slice().sort((a, b) => TROOPS[b.type].tier - TROOPS[a.type].tier);
  openModal('<div class="whead"><img alt="" src="' + compImg(v.c) + '"><h2>' + v.c.name + '<span class="sub">Твой вассал · надел ' + (s ? s.name : '—') + ' · ' + troopCount(p.troops) + ' из ' + cvCap(v) + ' бойцов</span></h2></div><div class="wbody"><div class="note">Казна вассала: ' + Math.round(v.gold) + ' золота. Подать тебе: ' + (v.trib || 0) + ' в день. Приказ сейчас: <b>' + CV_MODES[v.mode || 'guard'][0] + '</b>.</div>' +
    list.map(t => troopRow(t, '<div class="cnt">' + t.n + '</div>')).join('') + '</div><div class="wfoot">' + cvModeBtns(v) + '<button class="btn" data-act="cvgive" data-id="' + v.cid + '" ' + (P.gold >= 200 ? '' : 'disabled') + '>Дать 200 золота</button><button class="btn pri" data-act="resume">Хорошо</button></div>', 'narrow');
}
const cvRefresh = () => { if (UI.cvp && !UI.panel && G.parties.includes(UI.cvp)) vassalTalk(UI.cvp); else keepScroll(renderPanel); };
ACT.cvpick = function (d) { UI.cvpick = UI.cvpick === d.id ? null : d.id; keepScroll(renderPanel); };
ACT.cvgrant = function (d) { const r = cvGrant(G.player, d.id, +d.s); UI.cvpick = null; if (r) toast(r); else { sfx('coin'); toast('Надел отдан: у тебя новый вассал'); } if (!compsOf(G.player).length && !cvList(G.player).length) UI.panel = 'troops'; keepScroll(renderPanel); };
ACT.cvmode = function (d) { const v = cvOfId(G.player, d.id); if (!v || !CV_MODES[d.m]) return; v.mode = d.m; const p = cvPartyOf(v); if (p) { p.path = []; p.pi = 0; p.state = 'idle'; p.tid = null; p.ai = 0; } sfx('click'); toast(v.c.name + ': ' + CV_MODES[d.m][0].toLowerCase()); cvRefresh(); };
ACT.cvgive = function (d) { const P = G.player, v = cvOfId(P, d.id); if (!v || P.gold < 200) return; P.gold -= 200; v.gold += 200; sfx('coin'); cvRefresh(); };
ACT.cvrevoke = function (d) { UI.cvrev = d.id; keepScroll(renderPanel); };
ACT.cvrevokeok = function (d) { UI.cvrev = null; if (cvRevoke(G.player, d.id)) sfx('click'); if (!compsOf(G.player).length && !cvList(G.player).length) UI.panel = 'troops'; keepScroll(renderPanel); };
