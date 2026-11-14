/* ================= журнал: вкладка «Задания» (активные задания и хроника) =================
   Вызывается из renderPanel (06_ui.js), вкладка 'journal'. Возвращает HTML тела окна.
   Только отображение: данные заданий не меняются, кроме кнопки «В путь» (прокладывает маршрут, как клик по карте). */
const JQ_TYPES = {
  camp: { n: 'Разгром', i: 'skull' }, scout: { n: 'Разведка', i: 'zoom' }, purge: { n: 'Охота', i: 'sword' },
  supply: { n: 'Поставка', i: 'bag' }, muster: { n: 'Пополнение', i: 'men' }, deliver: { n: 'Доставка', i: 'horse' }
};
const JQ_MAX = 4; /* предел одновременных заданий, как в acceptQuest */
function jqDays(n) { const a = Math.abs(n) % 100, b = a % 10; return n + ' ' + (a > 10 && a < 20 ? 'дней' : b === 1 ? 'день' : b >= 2 && b <= 4 ? 'дня' : 'дней'); }
function jqLg(a, b) { return Math.round(Math.hypot(a.x - b.x, a.y - b.y) / 10) / 10; }
/* награда с учётом перка «Знаменитый наёмник» (как в questDone) */
function jqReward(P, q) { let k = 0; try { k = perkFx(P.hero).quest || 0; } catch (e) { } return Math.round(q.reward * (1 + k)); }
/* куда идти по заданию сейчас: разведанный лагерь — обратно к заказчику */
function jqTarget(q) { if (q.type === 'purge') return null; return settleById(q.type === 'scout' && q.seen ? q.from : q.sid) || null; }
/* прогресс: [есть, нужно, подпись] или null */
function jqProgress(P, q) {
  if (q.type === 'purge') return [q.got || 0, q.n, 'Разбито отрядов'];
  if (q.type === 'scout') return [q.seen ? 1 : 0, 2, q.seen ? 'Лагерь разведан — вернись к заказчику' : 'Подойди к лагерю, затем вернись'];
  if (q.type === 'supply') { const h = typeof invN === 'function' ? invN(P, q.item) : 0; return [Math.min(h, q.n), q.n, 'В обозе: ' + GOODS[q.item].n.toLowerCase()]; }
  if (q.type === 'muster') { let h = 0; for (const t of P.troops) if (TROOPS[t.type].tier >= 2) h += t.n; return [Math.min(h, q.n), q.n, 'Бойцов 2 уровня и выше в отряде']; }
  return null;
}
/* что мешает выполнить: текст предупреждения или '' */
function jqProblem(P, q, left) {
  if (left < 0) return 'Задание снимут, отношения с заказчиком ухудшатся';
  const t = jqTarget(q);
  if (q.type === 'camp') { const c = settleById(q.sid); if (c && !c.camp) return 'Лагерь пуст — разбойники ещё не вернулись'; }
  if (t && t.kind !== 'camp') { if (t.fac === 'undead') return t.name + ' в руинах'; if (typeof relHostile === 'function' && relHostile(P, t.fac)) return 'Ворота ' + t.name + ' закрыты: ты враг ' + FACTIONS[t.fac].gen; }
  if (q.type === 'muster') { const pr = jqProgress(P, q); if (pr[0] < pr[1]) return 'Не хватает бойцов: ' + (pr[1] - pr[0]); }
  if (q.type === 'supply') { const pr = jqProgress(P, q); if (pr[0] < pr[1]) return 'Нужно докупить: ' + (pr[1] - pr[0]); }
  return '';
}
function jqCard(P, q) {
  const T = JQ_TYPES[q.type] || { n: 'Поручение', i: 'flag' }, from = settleById(q.from), tgt = jqTarget(q), left = q.dl - G.day;
  const total = Math.max(1, q.dl - (q.day || G.day)), frac = clamp(left / total, 0, 1);
  const urgent = left >= 0 && left <= 2, warn = jqProblem(P, q, left), hard = left < 0 || /закрыты|руинах/.test(warn), pr = jqProgress(P, q);
  const st = left < 0 ? 'late' : urgent ? 'urgent' : '';
  let h = '<div class="jq-card ' + st + (hard ? ' blocked' : '') + '">';
  h += '<div class="jq-ic">' + ic(T.i) + '</div><div class="jq-main">';
  h += '<div class="jq-top"><span class="jq-type">' + T.n + '</span>' + (left < 0 ? '<span class="tag r">просрочено</span>' : urgent ? '<span class="tag r">срочно</span>' : '') + (pr && pr[0] >= pr[1] && !hard ? '<span class="tag g">готово к сдаче</span>' : '') + '</div>';
  h += '<div class="jq-title">' + questText(q) + '</div>';
  h += '<div class="jq-from"><img alt="" src="' + crestURL(q.fac) + '"><span>' + (from ? from.name : '—') + '</span><i>·</i><span>' + FACTIONS[q.fac].name + '</span></div>';
  h += '<div class="jq-det">' + ic(q.type === 'purge' ? 'sword' : 'flag') + '<span>' + questDetail(q, P).replace('асстояние: ', 'асстояние от тебя: ') + (q.type === 'scout' && q.seen && tgt ? ' · до ' + tgt.name + ': ' + jqLg(P, tgt) + ' лиг' : '') + '</span></div>';
  if (q.type === 'camp') { const c = settleById(q.sid); if (c && c.camp) h += '<div class="jq-det">' + ic('men') + '<span>В лагере около ' + troopCount(c.camp.troops) + ' бойцов</span></div>'; }
  if (pr) h += '<div class="jq-prog"><div class="jq-pl"><span>' + pr[2] + '</span><b>' + pr[0] + ' / ' + pr[1] + '</b></div><div class="jq-bar"><i style="width:' + Math.round(pr[0] / pr[1] * 100) + '%"></i></div></div>';
  if (warn) h += '<div class="jq-warn">' + warn + '</div>';
  h += '</div><div class="jq-side">';
  h += '<div class="jq-rw">' + ic('coin') + fmt(jqReward(P, q)) + '</div>';
  h += '<div class="jq-dl"><span>' + (left < 0 ? 'срок вышел' : left === 0 ? 'последний день' : 'осталось ' + jqDays(left)) + '</span><small>до дня ' + q.dl + '</small></div>';
  h += '<div class="jq-time" title="Осталось времени"><i style="width:' + Math.round(frac * 100) + '%"></i></div>';
  if (!NET.on && tgt && !hard) h += '<button class="btn sm jq-go" data-act="jqgo" data-q="' + q.id + '">В путь</button>';
  return h + '</div></div>';
}
function jqChronicle(P) {
  const L = (P.log || []).slice(-30).reverse();
  if (!L.length) return '<div class="jq-empty sm">Записей пока нет.</div>';
  let h = '', day = null;
  for (const l of L) {
    if (l.d !== day) { if (day !== null) h += '</div>'; day = l.d; h += '<div class="jq-day"><div class="jq-dh">День ' + day + (day === G.day ? ' <small>сегодня</small>' : '') + '</div>'; }
    const k = l.kind === 1 ? 'bad' : l.kind === 3 ? 'good' : l.kind === 2 ? 'info' : 'neu';
    h += '<div class="jq-ev ' + k + '"><i></i><span>' + l.txt + '</span></div>';
  }
  return h + '</div>';
}
function journalQuestsBody() {
  const P = G.player, Q = (P.quests || []).filter(q => settleById(q.sid) && settleById(q.from)).sort((a, b) => a.dl - b.dl || b.reward - a.reward);
  const sum = Q.reduce((s, q) => s + jqReward(P, q), 0), near = Q.length ? Q[0].dl - G.day : null;
  const done = (P.log || []).filter(l => /^Задание выполнено/.test(l.txt)).length;
  const tile = (i, v, lab, sub, cls) => '<div class="jq-tile' + (cls ? ' ' + cls : '') + '">' + ic(i) + '<div><b>' + v + '</b><span>' + lab + '</span>' + (sub ? '<small>' + sub + '</small>' : '') + '</div></div>';
  let h = '<div class="jq-root"><div class="jq-sum">' +
    tile('book', Q.length + '<em>/' + JQ_MAX + '</em>', 'Активных заданий', Q.length >= JQ_MAX ? 'журнал полон' : 'можно взять ещё ' + (JQ_MAX - Q.length)) +
    tile('coin', fmt(sum), 'Сумма наград', 'золотом', 'gold') +
    tile('hourglass', near === null ? '—' : near < 0 ? 'просрочено' : near === 0 ? 'сегодня' : jqDays(near), 'Ближайший срок', near === null ? 'нет заданий' : 'до дня ' + Q[0].dl, near !== null && near <= 2 ? 'hot' : '') +
    tile('flag', done, 'Выполнено', 'по свежей хронике') + '</div>';
  h += '<div class="jq-cols"><section class="jq-list"><h3 class="jq-h">Активные задания <small>по сроку</small></h3>';
  if (!Q.length) h += '<div class="jq-empty">' + ic('book', 34) + '<b>Нет активных заданий</b><span>Задания раздают в городах: зайди в любой город и открой вкладку «Задания» — там висит доска заказов. Одновременно можно вести до ' + JQ_MAX + '.</span></div>';
  else h += Q.map(q => jqCard(P, q)).join('');
  h += '</section><section class="jq-chron"><h3 class="jq-h">Хроника <small>последние записи</small></h3><div class="jq-feed">' + jqChronicle(P) + '</div></section></div></div>';
  return h;
}
Object.assign(ACT, {
  /* «В путь»: маршрут к цели задания, как клик по поселению или логову на карте */
  jqgo(d) {
    const P = G.player, q = (P.quests || []).find(x => x.id === +d.q), t = q && jqTarget(q); if (!t || NET.on) return;
    P.tid = null; P.sid = null; G.wait = false;
    if (t.kind === 'camp') { if (!t.camp) { toast('Логово пусто'); return; } P.tid = t.camp.id; P.path = findPath(P.x, P.y, t.x, t.y) || []; P.pi = 0; P.rp = .6; }
    else { P.sid = t.id; P.path = findPath(P.x, P.y, t.x, t.y) || []; P.pi = 0; if (!P.path.length) P.sid = null; }
    if (!P.path.length) { toast('Туда не пройти'); return; }
    sfx('order'); closeModal(); toast('Отряд выступил: ' + t.name);
  }
});
