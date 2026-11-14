/* ================= журнал: вкладка «Фракции» (как «Королевство/Энциклопедия» в Bannerlord) =================
   Вызывается из renderPanel (06_ui.js), вкладка 'factions'. Выбранная фракция — UI.jf. Возвращает HTML тела окна.
   Слева список фракций, справа — правитель, отношение, силы, войны и мир, матрица дипломатии, рода, вассалы, владения.
   В сетевой игре нет G.wars/G.clans/G.rul: показываем то, что есть (все вызовы из 05g_war.js проверяются через typeof). */

const JF_PORT = {}; /* портреты лордов: тип бойца + фракция -> dataURL */
const jfHas = () => typeof holdOf === 'function';
const jfHold = f => jfHas() ? holdOf(f) : (() => { let t = 0, c = 0, v = 0; for (const s of G.settles || []) if (s.fac === f) { if (s.kind === 'town') t++; else if (s.kind === 'castle') c++; else if (s.kind === 'village') v++; } return { t, c, v, all: t + c + v, core: t + c }; })();
const jfAlive = f => jfHold(f).core > 0;
const jfPow = f => typeof facPower === 'function' ? facPower(f) : (G.parties || []).reduce((a, p) => a + (p.fac === f && isNoble(p) ? partyStr(p) : 0), 0);
const jfPl = (n, a, b, c) => { const m = n % 10, h = n % 100; return n + ' ' + (m === 1 && h !== 11 ? a : m >= 2 && m <= 4 && (h < 12 || h > 14) ? b : c); };
const jfW = (n, a, b, c) => jfPl(n, a, b, c).split(' ')[1];
const jfDays = n => jfPl(n, 'день', 'дня', 'дней');
const jfCrown = '<svg class="jf-crown" viewBox="0 0 24 16" aria-label="правитель"><path d="M2 14 L3 4 L8 9 L12 2 L16 9 L21 4 L22 14 Z" fill="#e0b85c" stroke="#2a1d12" stroke-width="1.5" stroke-linejoin="round"/></svg>';
const jfOrd = n => n + '-е';

function jfPortrait(p) {
  if (typeof leaderType !== 'function' || typeof getSprite !== 'function' || !p.troops || !p.troops.length) return '';
  const t = leaderType(p); if (!t || !TROOPS[t]) return '';
  const k = t + '|' + p.fac + '|' + FACTIONS[p.fac].c1;
  if (JF_PORT[k] === undefined) {
    try {
      const S = getSprite(t, 0, p.fac), c = document.createElement('canvas'), g = c.getContext('2d'), sc = typeof SS === 'number' ? SS : 2, hc = S.hc || [S.w / 2, S.h * .35], bs = 40 * sc;
      c.width = c.height = 64; g.imageSmoothingQuality = 'high';
      g.drawImage(S.cv, hc[0] - bs / 2, hc[1] - bs * .4, bs, bs, 0, 0, 64, 64);
      JF_PORT[k] = c.toDataURL();
    } catch (e) { JF_PORT[k] = ''; }
  }
  return JF_PORT[k];
}

/* где лорд и чем занят */
function jfWhere(p) {
  if (p.fight) return ['в бою', 'r'];
  const s = p.sid != null ? settleById(p.sid) : null;
  if (p.army) return ['в походе' + (s ? ' · ' + s.name : ''), 'b'];
  if (p.hide) { const h = s || (p.home != null ? settleById(p.home) : null); if (h) return ['в ' + h.name, '']; }
  let best = null, bd = 1e9; for (const q of G.settles || []) if (q.kind !== 'camp') { const d = Math.hypot(q.x - p.x, q.y - p.y); if (d < bd) { bd = d; best = q; } }
  return [best ? 'у ' + best.name : 'в пути', ''];
}

function jfTags(f, P, alive, short) {
  const t = [];
  if (!alive) return '<span class="tag jf-fallen">пало</span>';
  if (P.liege === f) t.push('<span class="tag g">твой сюзерен</span>');
  if (typeof relHostile === 'function' && relHostile(P, f)) t.push('<span class="tag r">война с тобой</span>');
  else if (P.liege && P.liege !== f && atWar(P.liege, f)) t.push('<span class="tag r">враг сюзерена</span>');
  else if ((P.rel[f] || 0) >= 50 && P.liege !== f) t.push('<span class="tag g">союзны</span>');
  if (!short && typeof kingless === 'function' && kingless(f)) t.push('<span class="tag b">междуцарствие</span>');
  return t.join('');
}

function jfRel(v) {
  v = Math.round(clamp(v || 0, -100, 100));
  const pos = (v + 100) / 2, neg = v < 0, w = Math.abs(v) / 2;
  return '<div class="jf-rel"><div class="jf-relhd"><span>Твоё отношение</span><b class="' + (v < -20 ? 'dn' : v >= 20 ? 'up' : '') + '">' + relName(v) + ' <em>' + (v > 0 ? '+' : v < 0 ? '−' : '') + Math.abs(v) + '</em></b></div>' +
    '<div class="jf-relbar" role="meter" aria-valuemin="-100" aria-valuemax="100" aria-valuenow="' + v + '"><i class="' + (neg ? 'neg' : 'pos') + '" style="left:' + (neg ? pos : 50) + '%;width:' + w + '%"></i>' +
    [-20, 20, 50].map(x => '<s style="left:' + (x + 100) / 2 + '%"></s>').join('') + '<u style="left:50%"></u><b style="left:' + pos + '%"></b></div>' +
    '<div class="jf-relsc"><span>−100</span><span>враги</span><span>0</span><span>друзья</span><span>+100</span></div></div>';
}

function journalFactionsBody() {
  const P = G.player, all = worldF().filter(f => FACTIONS[f]);
  if (!all.length) return '<div class="note">Сведений о фракциях нет.</div>';
  const pw = {}, alive = {}; for (const f of all) { alive[f] = jfAlive(f); pw[f] = alive[f] ? jfPow(f) : 0; }
  const A = all.filter(f => alive[f]).sort((a, b) => pw[b] - pw[a]), dead = all.filter(f => !alive[f]), order = A.concat(dead), top = Math.max(1, ...A.map(f => pw[f]));
  let f = UI.jf; if (!all.includes(f)) f = P.liege && alive[P.liege] ? P.liege : (A[0] || all[0]); UI.jf = f;
  const ruler = typeof rulerOf === 'function' ? rulerOf : () => null;

  /* ---- список ---- */
  const list = order.map(x => {
    const r = alive[x] ? ruler(x) : null, kl = typeof kingless === 'function' && kingless(x);
    return '<button class="jf-it' + (x === f ? ' on' : '') + (alive[x] ? '' : ' dead') + '" data-act="jfac" data-f="' + x + '" style="--fc:' + FACTIONS[x].c1 + '" aria-pressed="' + (x === f) + '">' +
      '<img alt="" src="' + crestURL(x) + '"><span class="jf-itx"><b>' + FACTIONS[x].name + '</b><small>' + (alive[x] ? (r ? r.name : kl ? 'междуцарствие' : (G.rul && Object.keys(G.rul).length ? 'нет правителя' : 'сведений ещё нет')) : 'государство пало') + '</small>' +
      (alive[x] ? '<span class="jf-pw" title="Сила: ' + fmt(pw[x]) + '"><i style="width:' + Math.max(3, pw[x] / top * 100) + '%"></i></span>' : '') +
      '<span class="jf-tags">' + jfTags(x, P, alive[x], 1) + '</span></span></button>';
  }).join('');

  /* ---- детали ---- */
  const F = FACTIONS[f], h = jfHold(f), r = alive[f] ? ruler(f) : null, kl = typeof kingless === 'function' && kingless(f), tr = typeof rulerTr === 'function' ? rulerTr(f)[0] : '';
  const nobles = (G.parties || []).filter(p => p.fac === f && isNoble(p)), lords = nobles.filter(p => p.kind === 'lord'), vass = nobles.filter(p => p.kind === 'vassal'), men = nobles.reduce((a, p) => a + troopCount(p.troops), 0);
  const rank = A.indexOf(f) + 1;
  let d = '<div class="jf-head" style="--fc:' + F.c1 + '"><img alt="" src="' + crestURL(f) + '"><div class="jf-hx"><h2>' + F.name + '</h2><div class="jf-ruler">' +
    (!alive[f] ? 'Государство пало: земель не осталось.' : r ? jfCrown + '<b>' + r.name + '</b>' + (tr ? '<span class="jf-dim"> · ' + tr + '</span>' : '') : kl ? '<b>Междуцарствие</b><span class="jf-dim"> · роды выбирают нового правителя, походов нет</span>' : '<span class="jf-dim">Нет правителя</span>') +
    '</div><div class="jf-tags">' + jfTags(f, P, alive[f]) + '</div></div>' + jfRel(P.rel[f]) + '</div>';

  d += '<div class="jf-tiles">' +
    '<div class="jf-tile"><span>Сила</span><b>' + (alive[f] ? jfOrd(rank) + ' <small>из ' + A.length + '</small>' : '—') + '</b><em>' + (alive[f] ? fmt(pw[f]) + (rank > 1 ? ' · ' + Math.round(pw[f] / top * 100) + '% от первой' : ' · сильнейшая') : 'нет войска') + '</em></div>' +
    '<div class="jf-tile"><span>Знать</span><b>' + lords.length + ' <small>' + jfW(lords.length, 'лорд', 'лорда', 'лордов') + '</small></b><em>' + jfPl(vass.length, 'вассал', 'вассала', 'вассалов') + (typeof clansOf === 'function' && G.clans ? ' · ' + jfPl(clansOf(f).length, 'род', 'рода', 'родов') : '') + '</em></div>' +
    '<div class="jf-tile"><span>Бойцов в поле</span><b>' + fmt(men) + '</b><em>в отрядах знати</em></div>' +
    '<div class="jf-tile"><span>Владения</span><b>' + h.all + '</b><em>' + h.t + ' гор. · ' + h.c + ' зам. · ' + h.v + ' дер.</em></div></div>';

  /* ---- войны, мир, матрица ---- */
  if (alive[f]) {
    const foes = A.filter(o => o !== f && atWar(f, o)), friends = A.filter(o => o !== f && !atWar(f, o));
    const wr = o => { const w = G.wars && G.wars[WK(f, o)], s = w ? w.since : null, sh = Math.round(pw[f] / Math.max(1, pw[f] + pw[o]) * 100), sg = (G.settles || []).filter(q => q.siege && ((q.siege.f === f && q.fac === o) || (q.siege.f === o && q.fac === f)));
      return '<div class="jf-war"><button class="jf-lnk" data-act="jfac" data-f="' + o + '"><img alt="" src="' + crestURL(o) + '">' + FACTIONS[o].name + '</button><span class="jf-dim">' + (s != null ? 'с ' + s + '-го дня · ' + jfDays(Math.max(0, G.day - s)) : 'давняя вражда') + '</span>' +
        '<div class="jf-bal" title="Соотношение сил: ' + sh + ' на ' + (100 - sh) + '"><i style="width:' + sh + '%;background:' + F.c1 + '"></i><i style="width:' + (100 - sh) + '%;background:' + FACTIONS[o].c1 + '"></i></div>' +
        (sg.length ? '<div class="jf-sg">' + sg.map(q => 'Осада: ' + q.name + ' (' + FACTIONS[q.siege.f].name.split(' ')[0] + ')').join(' · ') + '</div>' : '') + '</div>'; };
    d += '<div class="jf-two"><section><h3>Войны <small>' + foes.length + '</small></h3>' + (foes.length ? foes.map(wr).join('') : '<div class="note">Ни с кем не воюет.</div>') +
      '<h3 class="jf-mt">Мир</h3>' + (friends.length ? '<div class="jf-chips">' + friends.map(o => '<button class="jf-chip" data-act="jfac" data-f="' + o + '"><img alt="" src="' + crestURL(o) + '">' + FACTIONS[o].name + '</button>').join('') + '</div>' : '<div class="note">Мира нет ни с кем.</div>') + '</section>';
    d += '<section><h3>Дипломатия</h3><div class="jf-mx" style="grid-template-columns:repeat(' + (A.length + 1) + ',26px)"><span></span>' + A.map(o => '<button class="jf-ax' + (o === f ? ' on' : '') + '" data-act="jfac" data-f="' + o + '" title="' + FACTIONS[o].name + '"><img alt="' + FACTIONS[o].name + '" src="' + crestURL(o) + '"></button>').join('') +
      A.map(a => '<button class="jf-ax' + (a === f ? ' on' : '') + '" data-act="jfac" data-f="' + a + '" title="' + FACTIONS[a].name + '"><img alt="' + FACTIONS[a].name + '" src="' + crestURL(a) + '"></button>' + A.map(b => { const wa = atWar(a, b), w = G.wars && G.wars[WK(a, b)];
        return '<i class="' + (a === b ? 'me' : wa ? 'war' : 'peace') + (a === f || b === f ? ' hl' : '') + '" title="' + (a === b ? FACTIONS[a].name : FACTIONS[a].name + ' — ' + FACTIONS[b].name + ': ' + (wa ? 'война' + (w ? ' с ' + w.since + '-го дня' : '') : 'мир')) + '"></i>'; }).join('')).join('') +
      '</div><div class="jf-leg"><span><i class="war"></i>война</span><span><i class="peace"></i>мир</span></div></section></div>';
  }

  /* ---- рода ---- */
  if (typeof clansOf === 'function' && G.clans) {
    const cs = clansOf(f).slice().sort((a, b) => (b.rule ? 1 : 0) - (a.rule ? 1 : 0) || clanForce(b) - clanForce(a));
    d += '<h3 class="jf-mt">Рода <small>' + cs.length + '</small></h3>';
    if (!cs.length) d += '<div class="note">Знатных родов не осталось.</div>';
    else d += '<div class="jf-clans">' + cs.map(c => {
      const T = CLAN_TR[c.trait] || { n: c.trait, d: '' }, loy = Math.round(clamp(c.loy, 0, 100)), lc = loy > 60 ? 'g' : loy > 35 ? 'm' : 'r', hm = c.home != null ? settleById(c.home) : null, mem = clanMembers(c).sort((a, b) => (b.ruler ? 1 : 0) - (a.ruler ? 1 : 0));
      return '<div class="jf-clan' + (c.rule ? ' rule' : '') + '"><div class="jf-ch"><b>' + c.name + '</b>' + (c.rule ? '<span class="tag jf-gold">правящий</span>' : '') + '<span class="tag" title="' + T.n + ' род: ' + T.d + '">' + T.n + '</span></div>' +
        '<div class="jf-loy" title="Верность ' + loy + ' из 100' + (T.thr ? ' · ниже ' + T.thr + ' может уйти к врагу' : '') + '"><span>Верность</span><span class="jf-lb ' + lc + '"><i style="width:' + loy + '%"></i>' + (T.thr ? '<s style="left:' + T.thr + '%"></s>' : '') + '</span><b>' + loy + '</b></div>' +
        '<div class="jf-cm"><span>' + ic('flag', 14) + (hm ? hm.name : 'без гнезда') + '</span><span>' + ic('men', 14) + fmt(clanForce(c)) + ' ' + jfW(clanForce(c), 'боец', 'бойца', 'бойцов') + '</span></div>' +
        '<div class="jf-mem">' + (mem.length ? mem.map(p => { const pt = jfPortrait(p), wh = jfWhere(p);
          return '<div class="jf-lord">' + (pt ? '<img alt="" src="' + pt + '">' : '<span class="jf-noimg"></span>') + '<div><b>' + (p.ruler ? jfCrown : '') + p.name + '</b><small><span class="jf-n">' + fmt(troopCount(p.troops)) + '</span> ' + jfW(troopCount(p.troops), 'боец', 'бойца', 'бойцов') + ' · <span class="' + (wh[1] ? 'jf-st ' + wh[1] : '') + '">' + wh[0] + '</span></small></div></div>'; }).join('') : '<div class="note">Все члены рода пали, ждут наследника.</div>') + '</div></div>';
    }).join('') + '</div>';
  }

  /* ---- вассалы и владения ---- */
  const st = G.settles || [], byK = k => st.filter(s => s.fac === f && s.kind === k).sort((a, b) => a.name.localeCompare(b.name, 'ru'));
  d += '<div class="jf-two"><section><h3>Вассалы <small>' + vass.length + '</small></h3>' + (vass.length ? '<div class="jf-vs">' + vass.slice().sort((a, b) => troopCount(b.troops) - troopCount(a.troops)).map(p => { const wh = jfWhere(p); return '<div class="jf-v"><b>' + p.name + '</b><span class="jf-n">' + fmt(troopCount(p.troops)) + '</span><small class="' + (wh[1] ? 'jf-st ' + wh[1] : '') + '">' + wh[0] + '</small></div>'; }).join('') + '</div>' : '<div class="note">Вассалов нет.</div>') + '</section>' +
    '<section><h3>Владения <small>' + h.all + '</small></h3>' + (h.all ? [['town', 'Города'], ['castle', 'Замки'], ['village', 'Деревни']].map(([k, n]) => { const l = byK(k); return l.length ? '<div class="jf-hk"><span>' + n + '</span><div class="jf-chips">' + l.map(s => '<span class="jf-chip st ' + k + (s.siege ? ' sg' : '') + '"' + (s.siege ? ' title="В осаде"' : '') + '>' + s.name + '</span>').join('') + '</div></div>' : ''; }).join('') : '<div class="note">Земель нет.</div>') + '</section></div>';

  /* выбранная фракция всегда видна в списке (на телефоне список — лента, выбранная может быть за краем) */
  requestAnimationFrame(() => { const L = document.querySelector('.jf-list'), o = L && L.querySelector('.jf-it.on'); if (!o) return; const a = L.getBoundingClientRect(), r = o.getBoundingClientRect();
    if (r.left < a.left || r.right > a.right) L.scrollLeft += r.left - a.left - 10; if (r.top < a.top || r.bottom > a.bottom) L.scrollTop += r.top - a.top - 12; });
  return '<div class="jf"><nav class="jf-list" aria-label="Фракции">' + list + '</nav><div class="jf-main">' + d + '</div></div>';
}

Object.assign(ACT, {
  jfac(d) {
    const L = document.querySelector('.jf-list'), sl = L ? [L.scrollTop, L.scrollLeft] : null;
    UI.jf = d.f; if (typeof sfx === 'function') sfx('click'); renderPanel();
    const N = document.querySelector('.jf-list'); if (N && sl) { N.scrollTop = sl[0]; N.scrollLeft = sl[1]; }
  }
});
