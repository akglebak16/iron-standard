/* ================= инвентарь и торговля: интерфейс =================
   Окно «Обоз»: кукла героя со слотами по бокам, рюкзак сеткой плиток и карточка выбранной вещи внизу окна.
   Вкладка «Торговля»: те же плитки, цена на плитке, карточка внизу с кнопками. Двойной щелчок по плитке:
   надеть / снять, купить / продать одну штуку. Выбор хранится в UI.isel (обоз) и UI.tsel (торговля). */

/* ---------- иконки предметов ---------- */
const bodyBase = '<path d="M8 3l4 2 4-2 5 4-3 4-2-1v11H8V10l-2 1-3-4z"/>';
const dotsAt = (xs, ys, r) => ys.map(y => xs.map(x => '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>').join('')).join('');
Object.assign(ICONS, {
  body: bodyBase,
  hands: '<path d="M7 21v-8l-2-3 2-1 2 3V4h2v7V3h2v8V4h2v8V6h2v9l-2 6z"/>',
  legs: '<path d="M9 3h6v10l5 3v5H5v-4l4-2z"/>',
  // доспехи: общий силуэт и узор по виду
  b_padded: bodyBase + '<path d="M10 8v13M12 6v15M14 8v13" stroke="#0008" stroke-width="1" fill="none"/>',
  b_mail: bodyBase + '<g fill="#0009">' + dotsAt([10, 12, 14], [9, 12, 15, 18], .7) + '</g>',
  b_scale: bodyBase + '<path d="' + [9, 12, 15, 18].map(y => [9.2, 11.6, 14].map(x => 'M' + x + ' ' + y + 'a1.200 1.200 0 0 0 2.400 0').join('')).join('') + '" stroke="#0009" stroke-width=".9" fill="none"/>',
  b_plate: bodyBase + '<path d="M8 9h8M8 13h8M8 17h8M12 6v15" stroke="#0009" stroke-width="1.200" fill="none"/>',
  // шлемы
  h_cap: '<path d="M3.500 17c0-6.500 3.500-11 8.500-11s8.500 4.500 8.500 11z"/><path d="M3.500 14.500h17" stroke="#0008" stroke-width="1" fill="none"/>',
  h_nasal: '<path d="M4 15c0-6 3-10 8-10s8 4 8 10v4H4z"/><path d="M11.100 9h1.800v10h-1.800z" fill="#0009"/>',
  h_kettle: '<path d="M12 3c4.500 0 7 3.500 7 8v1h4v2.500H1V12h4v-1c0-4.500 2.500-8 7-8z"/>',
  h_great: '<path d="M5.500 2.500h13V16l-3 5.500h-7L5.500 16z"/><path d="M7.500 9.500h9v2h-9z" fill="#0009"/><path d="M12 13v6" stroke="#0007" stroke-width="1.100"/>',
  // щиты
  sh_round: '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="7" fill="none" stroke="#0007" stroke-width="1"/><circle cx="12" cy="12" r="3.200" fill="#0008"/>',
  sh_small: '<circle cx="12" cy="12" r="7.500"/><circle cx="12" cy="12" r="2.600" fill="#0008"/>',
  // оружие
  twohand: '<path d="M12 1l2.800 3.400V14H9.200V4.400z"/><path d="M6 14h12v2.400H6z"/><path d="M10.800 16.400h2.400v4.400h-2.400z"/><circle cx="12" cy="22" r="1.500"/>',
  axe: '<g transform="rotate(35 12 12)"><path d="M10.900 2.500h2.200V22h-2.200z"/><path d="M13 3.500c5.500.4 8.500 3 8.500 6.800S18.500 16.600 13 17c2.200-3 2.200-10 0-13.500z"/></g>',
  hammer: '<g transform="rotate(35 12 12)"><path d="M10.900 6h2.200v16h-2.200z"/><path d="M5.500 2h13v6h-13z"/></g>',
  mace: '<g transform="rotate(35 12 12)"><path d="M10.900 9h2.200v13h-2.200z"/><circle cx="12" cy="6" r="3.800"/><path d="M12 .2l1.600 2h-3.200zM6.400 6l2-1.600v3.200zM17.600 6l-2-1.600v3.200z"/></g>',
  club: '<g transform="rotate(35 12 12)"><path d="M12 1.500c2.800 0 4.200 2 4.200 4.800 0 2.600-1.200 4.200-2.200 5.200L13.400 22h-2.800l-.6-10.500c-1-1-2.200-2.600-2.200-5.200C7.800 3.500 9.200 1.500 12 1.500z"/></g>',
  spear: '<g transform="rotate(35 12 12)"><path d="M11.200 7h1.600v16h-1.600z"/><path d="M12 .8l3 7h-6z"/></g>',
  pike: '<g transform="rotate(35 12 12)"><path d="M11.400 5h1.200v18h-1.200z"/><path d="M12 .5l2 5h-4z"/><path d="M9.600 5h4.800v1.200H9.600z"/></g>',
  halberd: '<g transform="rotate(35 12 12)"><path d="M11.200 5h1.600v18h-1.600z"/><path d="M12 .5l1.800 4.500h-3.600z"/><path d="M12.800 6.500c4.200 0 6.200 1.600 6.200 4s-2 4-6.200 4c1.200-2 1.200-6 0-8z"/></g>',
  jav: '<g transform="rotate(45 12 12)"><path d="M11.300 6h1.400v14h-1.400z"/><path d="M12 .8l2.200 5.400H9.800z"/><path d="M12 16.500l-3 5.500h6z"/></g>',
  xbow: '<path d="M1.500 9.500C6 3.500 18 3.500 22.500 9.500" fill="none" stroke="currentColor" stroke-width="2.400"/><path d="M1.800 9.500L12 13l10.200-3.500" fill="none" stroke="currentColor" stroke-width="1.200"/><path d="M10.800 5.500h2.400V22h-2.400z"/><path d="M12 .8l2 4.200h-4z"/>',
  // товары
  grain: '<path d="M12 2c2 2 2 4 0 6-2-2-2-4 0-6zM12 8c2 2 2 4 0 6-2-2-2-4 0-6zM7.500 6c2.200.3 3.600 1.800 4 4-2.200-.3-3.700-1.800-4-4zM16.500 6c-2.200.3-3.600 1.800-4 4 2.200-.3 3.700-1.800 4-4zM7.500 12c2.200.3 3.600 1.800 4 4-2.200-.3-3.700-1.800-4-4zM16.500 12c-2.200.3-3.600 1.800-4 4 2.200-.3 3.700-1.800 4-4z"/><path d="M11.300 14h1.400v8h-1.400z"/>',
  sack: '<path d="M8 2h8l-1.500 3c3 1.500 5 5 5 9 0 5-3 8-7.500 8S4.500 19 4.500 14c0-4 2-7.500 5-9z"/><path d="M8.500 6h7" stroke="#0008" stroke-width="1.500"/>',
  ale: '<path d="M4 6h12v13a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"/><path d="M16 9h2.500a2.500 2.500 0 0 1 0 5H16v-2h2.500a.5.500 0 0 0 0-1H16z"/><path d="M4 6c0-2.500 2-3.500 4-3.500s2.200 1 4 1 4-1 4 2.500z"/>',
  ingot: '<path d="M2 20l2.500-6h8l2.500 6zM9 14l2.500-6h8l2.500 6z"/>',
  hide: '<path d="M5 4l4 2h6l4-2 3 5-3 3 1 3-3 1 .5 5H7.500L8 16l-3-1 1-3-3-3z"/>',
  pelt: '<path d="M7 3c2 1.500 8 1.500 10 0l4 6-3 3 2 6-4-1-1 5h-6l-1-5-4 1 2-6-3-3z"/>',
  roll: '<path d="M7 5h11a3 7 0 0 1 0 14H7a3 7 0 0 1 0-14z"/><ellipse cx="7" cy="12" rx="3" ry="7" fill="#0006"/>',
  bottle: '<path d="M10 2h4v5c2 1 3 2.500 3 5v8a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2v-8c0-2.500 1-4 3-5z"/>',
  jar: '<path d="M8 2h8v3H8zM6.500 6h11c1 2 1.500 4 1.500 6.500 0 4-2 7.500-4 9.500H9c-2-2-4-5.500-4-9.500 0-2.500.5-4.500 1.500-6.500z"/>'
});
const SLOT_ICON = { head: 'helm', body: 'body', hands: 'hands', legs: 'legs', melee: 'sword', ranged: 'bow', shield: 'shield', horse: 'horse' };
const GOOD_IC = { grain: 'grain', salt: 'sack', ale: 'ale', iron: 'ingot', leather: 'hide', furs: 'pelt', cloth: 'roll', wine: 'bottle', spice: 'jar' };
const TIER = [{ n: 'Простое', c: '#a89f8a' }, { n: 'Добротное', c: '#8fc24f' }, { n: 'Редкое', c: '#5fa0e6' }, { n: 'Мастерское', c: '#e5902a' }];
const tierOf = it => it && it.slot ? TIER[Math.min(3, it.tier || 0)] : null; // предметы каталога (EQ) и вещи из ITEM; у товаров слота нет
function iconKey(it) {
  if (it.kind === 'goods') return GOOD_IC[it.id] || 'sack';
  switch (it.slot) {
    case 'melee': case 'ranged':
      if (it.wt === 'twohand') return it.look === 'axe' ? 'axe' : it.look === 'mace' ? 'hammer' : 'twohand';
      if (it.wt === 'polearm') return it.look === 'halberd' ? 'halberd' : 'pike';
      if (it.wt === 'mace') return it.look === 'club' ? 'club' : 'mace';
      return { sword: 'sword', axe: 'axe', spear: 'spear', bow: 'bow', xbow: 'xbow', throw: 'jav' }[it.wt] || 'sword';
    case 'head': return 'h_' + it.look;
    case 'body': return 'b_' + it.look;
    case 'shield': return it.look === 'round' ? 'sh_round' : it.look === 'small' ? 'sh_small' : 'shield';
    default: return SLOT_ICON[it.slot];
  }
}
function itemIc(it, s) { const k = iconKey(it); return ic(ICONS[k] ? k : (SLOT_ICON[it.slot] || 'bag'), s); }

const pc = v => Math.round(v * 100) + '%';
function cargoBar(P) { const w = invWeight(P), c = cargoCap(P); return '<div class="kv"><span>Обоз</span><b class="' + (w > c ? 'dn' : '') + '">' + w + ' / ' + c + '</b></div><div class="pbar cargo' + (w > c ? ' over' : '') + '"><i style="width:' + clamp(w / c * 100, 0, 100) + '%"></i></div>'; }
function swingLabel(spd) { return spd < 1 ? 'быстрый' : spd <= 1.1 ? 'обычный' : spd <= 1.35 ? 'медленный' : 'тяжёлый'; }
function keepScroll(fn) { const b = document.querySelector('#modal .wbody'), t = b ? b.scrollTop : 0; fn(); const n = document.querySelector('#modal .wbody'); if (n) n.scrollTop = t; }
const slotOrd = id => SLOTS.indexOf(ITEM[id].slot);
const byGear = (a, c) => slotOrd(a) - slotOrd(c) || ITEM[a].price - ITEM[c].price;

/* Двойной щелчок считаем сами: после первого щелчка окно перерисовывается, и родное событие dblclick до новой плитки не доходит.
   Плитка с data-dbl="действие" по второму быстрому нажатию выполняет это действие. */
let lastTap = { k: '', t: 0 };
function dblTap(d, key) { const now = Date.now(), hit = lastTap.k === key && now - lastTap.t < 420; lastTap = hit ? { k: '', t: 0 } : { k: key, t: now }; return hit && d.dbl && ACT[d.dbl]; }

/* ---------- плитка предмета ---------- */
function tile(o) {
  const it = o.it, t = tierOf(it), cls = ['tile'];
  if (o.on) cls.push('on'); if (o.fit) cls.push('fit'); if (!it) cls.push('empty'); if (it && it.kind === 'goods') cls.push('g'); if (o.price !== undefined) cls.push('hp');
  const st = '--tc:' + (t ? t.c : it ? '#8a7a58' : '#ffffff22') + (it && it.kind === 'goods' ? ';--ic:' + it.c : ''), tag = o.attr ? 'button' : 'div';
  let h = '<' + tag + ' class="' + cls.join(' ') + '" style="' + st + '"' + (o.title ? ' title="' + o.title + '"' : '') + ' ' + (o.attr || '') + '>' + (it ? itemIc(it) : ic(o.ghost || 'bag'));
  if (o.qty > 1) h += '<b class="qty">' + o.qty + '</b>';
  if (o.price !== undefined) h += '<span class="pr ' + (o.tone || '') + '">' + ic('coin') + fmt(o.price) + '</span>';
  if (o.rib) h += '<i class="rib ' + (o.rib[1] || '') + '">' + o.rib[0] + '</i>';
  if (o.lab) h += '<span class="lab">' + o.lab + '</span>';
  return h + '</' + tag + '>';
}
const voidTiles = n => '<div class="tile void"></div>'.repeat(Math.max(0, n));

/* ---------- карточка вещи (внизу окна) ---------- */
const stat = (l, v, d) => '<span>' + l + '<b>' + v + (d || '') + '</b></span>';
function pierceBars(W) {
  const nm = ['Лёгкая броня', 'Средняя', 'Тяжёлая'];
  return '<div class="pbars">' + [0, 1, 2].map(i => { const p = dtPierce(W.dt, [0, 20, 40][i], W.pb); return '<div>' + nm[i] + ' <b>' + pc(p) + '</b><i><u style="width:' + clamp(p / .55 * 100, 3, 100) + '%"></u></i></div>'; }).join('') + '</div>';
}
function cmpDelta(it, cur, key) { // насколько вещь лучше надетой в том же слоте
  const d = (it[key] || 0) - (cur ? cur[key] || 0 : 0); if (!d) return ''; const n = it.slot === 'shield' ? Math.round(d * 100) + '%' : Math.round(d * 10) / 10;
  return ' <small class="' + (d > 0 ? 'up' : 'dn') + '">' + (d > 0 ? '▲ +' : '▼ ') + n + '</small>';
}
function itemDock(it, o) {
  o = o || {}; const t = tierOf(it), cur = o.cmp ? eqItem(G.player.hero, it.slot) : null, st = [], tr = []; let sub;
  if (it.kind === 'goods') { sub = 'Товар'; st.push(stat('Вес', it.w), stat('Обычная цена', it.price)); }
  else {
    sub = SLOT_NAME[it.slot] + (it.dt ? ' · ' + WTYPE[it.wt] + ' · ' + DTYPE[it.dt].n.toLowerCase() + ' урон' : '') + ' · ' + t.n;
    if (it.dmg !== undefined) {
      st.push(stat('Урон', it.dmg, o.cmp ? cmpDelta(it, cur, 'dmg') : ''), stat('Хват', it.hands === 2 ? 'двуручное' : 'одноручное'));
      if (it.rng) st.push(stat('Дальность', it.range), stat('Перезарядка', it.cd + ' с')); else st.push(stat('Темп', swingLabel(it.spd)), stat('Длина', it.reach ? '+' + it.reach : 'обычная'));
    } else if (it.slot === 'shield') st.push(stat('Блок', pc(it.v), o.cmp ? cmpDelta(it, cur, 'v') : ''), stat('От стрел', '+' + pc(shieldArrow(it.look))));
    else if (it.slot === 'horse') st.push(stat('Скорость', it.v, o.cmp ? cmpDelta(it, cur, 'v') : ''));
    else st.push(stat('Броня', '+' + it.v, o.cmp ? cmpDelta(it, cur, 'v') : ''));
    if (it.w) st.push(stat('Вес', it.w));
    if (it.brk) tr.push('пробивает блок щитом'); if (it.kb >= 2) tr.push('сильно отбрасывает'); if (it.anticav) tr.push('бонус против конницы'); if (it.cleave >= 4) tr.push('задевает до ' + it.cleave + ' целей');
    if (it.dmg !== undefined && it.hands === 2 && !it.rng) tr.push('щит не носят'); if (it.rng && it.hands === 2) tr.push('щит уходит за спину'); if (it.rng) tr.push('боеприпасы бесконечные');
  }
  return '<div class="dock">' + tile({ it }) + '<div class="dinfo"><div class="dnm" style="color:' + (t ? t.c : 'var(--parch)') + '">' + it.name + '</div><div class="dsub">' + sub + (o.sub ? ' · ' + o.sub : '') + '</div><div class="dstats">' + st.join('') + '</div>' +
    (tr.length ? '<div class="ptags">' + tr.map(x => '<em>' + x + '</em>').join('') + '</div>' : '') + (it.dt ? pierceBars(it) : '') + (it.dt ? '<div class="dsub dnote" style="margin:4px 0 0">' + DTYPE[it.dt].note + '</div>' : '') + '</div>' +
    (o.acts ? '<div class="dacts">' + o.acts + '</div>' : '') + '</div>';
}
const dockHint = (txt, tl) => '<div class="dock hint">' + tile({ ghost: tl || 'bag' }) + '<div class="dinfo"><div class="note" style="margin:0">' + txt + '</div></div></div>';

/* ---------- вкладка «Торговля» в городе, замке и деревне ---------- */
function tradeTile(s, P, id, side) {
  const it = ITEM[id], m = marketOf(s), buy = side === 'buy', have = buy ? (m.stock[id] || 0) : invN(P, id), pr = buy ? buyPrice(P, s, id) : sellPrice(P, s, id), lv = priceLevel(s, id);
  const tone = !lv ? '' : (buy ? lv === 'low' : lv === 'high') ? 'cheap' : 'dear', can = buy ? P.gold >= pr : m.gold >= pr, on = UI.tsel && UI.tsel.side === side && UI.tsel.id === id;
  return tile({ it, on, qty: have, price: pr, tone: can ? tone : 'no', title: it.name, attr: 'data-act="tsel" data-side="' + side + '" data-id="' + id + '" data-n="1" data-dbl="' + (buy ? 'tbuy' : 'tsell') + '"' });
}
function tradeLists(s) {
  const P = G.player, m = marketOf(s), ord = (a, b) => (ITEM[a].kind === ITEM[b].kind ? (ITEM[a].kind === 'gear' ? slotOrd(a) - slotOrd(b) : 0) || ITEM[a].price - ITEM[b].price : ITEM[a].kind === 'goods' ? -1 : 1);
  return { mine: invIds(P, 'goods').concat(invIds(P, 'gear')).sort(ord), theirs: Object.keys(m.stock).filter(id => ITEM[id] && m.stock[id] > 0).sort(ord) };
}
function tradeBody(s) {
  const P = G.player; if (!hasMarket(s)) return '<div class="note">Здесь не торгуют.</div>';
  const m = marketOf(s), L = tradeLists(s);
  return '<div class="tbar"><div class="note" style="margin:0">Золото: <b>' + fmt(P.gold) + '</b> · у торговца: <b>' + fmt(m.gold) + '</b>. Цены зависят от края и от запаса на складе, крупная партия сдвигает цену. Надетое не продаётся: сними его в окне «Обоз».</div><div>' + cargoBar(P) + '</div></div>' +
    '<div class="trade"><div><h3>Торговец</h3><div class="igrid">' + L.theirs.map(id => tradeTile(s, P, id, 'buy')).join('') + voidTiles(12 - L.theirs.length) + '</div></div>' +
    '<div><h3>Твой обоз</h3><div class="igrid">' + L.mine.map(id => tradeTile(s, P, id, 'sell')).join('') + voidTiles(12 - L.mine.length) + '</div>' + (L.mine.length ? '' : '<div class="note">Обоз пуст. Купи товар или добудь трофеи в бою.</div>') + '</div></div>';
}
function tradeDock(s) {
  const P = G.player; if (!hasMarket(s)) return '';
  const m = marketOf(s), sel = UI.tsel, hint = dockHint('Выбери вещь на прилавке или в своём обозе. Двойной щелчок покупает или продаёт одну штуку.', 'coin');
  if (!sel || !ITEM[sel.id]) return hint;
  const it = ITEM[sel.id], buy = sel.side === 'buy', have = buy ? (m.stock[sel.id] || 0) : invN(P, sel.id); if (have < 1) { UI.tsel = null; return hint; }
  const pr = buy ? buyPrice(P, s, sel.id) : sellPrice(P, s, sel.id), lv = priceLevel(s, sel.id), ok = buy ? P.gold >= pr : m.gold >= pr, tone = !lv ? '' : (buy ? lv === 'low' : lv === 'high') ? 'cheap' : 'dear';
  const nn = it.kind === 'gear' ? [1] : [1, 5, 99], lab = n => n === 99 ? (buy ? 'Макс.' : 'Все') : (buy ? 'Купить' : 'Продать') + (n > 1 ? ' ×' + n : it.kind === 'gear' ? '' : ' ×1');
  const acts = '<div class="dprice ' + tone + '" title="' + (buy ? 'Цена покупки' : 'Цена продажи') + '">' + ic('coin') + '<b>' + fmt(pr) + '</b><small>' + (buy ? 'за штуку' : 'за штуку') + (lv ? ' · здесь ' + (lv === 'low' ? 'дёшево' : 'дорого') : '') + '</small></div>' +
    nn.map(n => '<button class="btn sm' + (n === 1 ? ' pri' : '') + '" data-act="' + (buy ? 'tbuy' : 'tsell') + '" data-id="' + sel.id + '" data-n="' + n + '" ' + (ok ? '' : 'disabled') + '>' + (n === 1 && it.kind === 'gear' ? (buy ? 'Купить' : 'Продать') : lab(n)) + '</button>').join('');
  return itemDock(it, { cmp: it.kind === 'gear', acts, sub: buy ? 'на прилавке: ' + have + ' · у тебя: ' + invN(P, sel.id) : 'у тебя: ' + have });
}
ACT.tsel = function (d) { const dbl = dblTap(d, 't|' + d.side + '|' + d.id); if (dbl) return dbl(d); UI.tsel = { side: d.side, id: d.id }; keepScroll(renderTown); };
ACT.tbuy = function (d) {
  if (NET.on) { NET.send({ t: 'tbuy', id: d.id, n: +d.n }); sfx('coin'); return; }
  const P = G.player, n = +d.n, r = doBuy(P, UI.town.s, d.id, n);
  if (r.n) { sfx('coin'); toast('Куплено: ' + ITEM[d.id].name + (r.n > 1 ? ' ×' + r.n : '') + ' за ' + fmt(r.sum)); if (r.n < n && n < 99) toast(TRADE_WHY[r.why] || ''); } else toast(TRADE_WHY[r.why] || 'Не вышло');
  keepScroll(renderTown);
};
ACT.tsell = function (d) {
  if (NET.on) { NET.send({ t: 'tsell', id: d.id, n: +d.n }); sfx('coin'); return; }
  const P = G.player, n = +d.n, r = doSell(P, UI.town.s, d.id, n);
  if (r.n) { sfx('coin'); toast('Продано: ' + ITEM[d.id].name + (r.n > 1 ? ' ×' + r.n : '') + ' за ' + fmt(r.sum)); if (r.n < n && n < 99 && r.why) toast(TRADE_WHY[r.why]); } else toast(TRADE_WHY[r.why] || 'Не вышло');
  keepScroll(renderTown);
};

/* ---------- ряд мини-плиток надетого (для окна героя) ---------- */
function miniGear(H) {
  return '<div class="mini">' + SLOTS.map(k => { const it = eqItem(H, k); return it ? '<span class="mt" style="--tc:' + tierOf(it).c + '" title="' + SLOT_NAME[k] + ': ' + it.name + '">' + itemIc(it) + '</span>' : '<span class="mt void" title="' + SLOT_NAME[k] + ': пусто">' + ic(SLOT_ICON[k]) + '</span>'; }).join('') + '</div>';
}

/* ---------- вкладка «Обоз»: кукла героя и рюкзак ---------- */
function slotTile(P, k) {
  const H = invWho(P), it = eqItem(H, k), w = heroWield(H), s = UI.isel, on = s && s.from === 'slot' && s.k === k, fit = s && s.from === 'bag' && ITEM[s.id] && ITEM[s.id].slot === k; let rib = null;
  if (it && (k === 'melee' || k === 'ranged')) rib = w === it ? ['в руках', 'g'] : ['за спиной'];
  if (it && k === 'shield' && heroShield(H) === null) rib = ['за спиной'];
  return tile({ it, on, fit, rib, ghost: SLOT_ICON[k], lab: it ? '' : SLOT_NAME[k], title: SLOT_NAME[k] + (it ? ': ' + it.name : ''), attr: 'data-act="isel" data-from="slot" data-k="' + k + '"' + (it ? ' data-dbl="unequip" data-slot="' + k + '"' : '') });
}
function bagTile(P, id) {
  const it = ITEM[id], s = UI.isel, on = s && s.from === 'bag' && s.id === id, fit = s && s.from === 'slot' && it.slot === s.k;
  return tile({ it, on, fit, qty: invN(P, id), title: it.name, attr: 'data-act="isel" data-from="bag" data-id="' + id + '"' + (it.kind === 'gear' ? ' data-dbl="equip"' : '') });
}
const BAG_FILTERS = [['all', 'Всё'], ['weapon', 'Оружие'], ['armor', 'Броня'], ['goods', 'Товары']];
function bagIds(P, f) {
  const gear = invIds(P, 'gear').sort(byGear), goods = invIds(P, 'goods'), wp = id => ITEM[id].slot === 'melee' || ITEM[id].slot === 'ranged';
  return f === 'weapon' ? gear.filter(wp) : f === 'armor' ? gear.filter(id => !wp(id)) : f === 'goods' ? goods : gear.concat(goods);
}
function invBody() {
  const P = G.player, H = invWho(P), hd = heroDef(H), W = hd.wpn, Gr = heroGear(H), sp = getHeroSprite(H, Gr.mounted); if (!sp.url) sp.url = sp.cv.toDataURL();
  const f = UI.bagF || 'all', ids = bagIds(P, f);
  const stt = [['Броня', hd.arm], ['Урон', Math.round(hd.dmg)], ['Блок', pc(Gr.block)], [W.rng ? 'Перезарядка' : 'Удар', Math.round(hd.cd * 100) / 100 + ' с'], [W.rng ? 'Дальность' : 'Длина', W.rng ? W.range : 30 + hd.reach], ['Урон по типу', DTYPE[W.dt].n]];
  return whoBar(P) + '<div class="inv"><div><div class="doll"><div class="col">' + ['head', 'body', 'hands', 'legs'].map(k => slotTile(P, k)).join('') + '</div>' +
    '<div class="fig"><img alt="" src="' + sp.url + '"><div class="who">' + H.name + '<small>Уровень ' + H.lvl + (Gr.mounted ? ' · верхом' : '') + '</small></div></div>' +
    '<div class="col">' + ['melee', 'ranged', 'shield', 'horse'].map(k => slotTile(P, k)).join('') + '</div></div>' +
    '<div class="stt">' + stt.map(x => '<div><span>' + x[0] + '</span><b>' + x[1] + '</b></div>').join('') + '</div></div>' +
    '<div><h3>Рюкзак<span class="fl">' + BAG_FILTERS.map(x => '<button class="fbtn' + (x[0] === f ? ' on' : '') + '" data-act="bagf" data-f="' + x[0] + '">' + x[1] + '</button>').join('') + '</span></h3>' + cargoBar(P) +
    '<div class="igrid">' + ids.map(id => bagTile(P, id)).join('') + voidTiles(Math.max(24, Math.ceil(ids.length / 6) * 6) - ids.length) + '</div>' +
    (ids.length ? '' : '<div class="note">' + (f === 'all' ? 'Обоз пуст.' : 'В этой вкладке пусто.') + '</div>') + '<div class="note">Провизия: ' + P.food + ' (вес не занимает). Двойной щелчок по вещи: надеть, по слоту: снять. В бою X меняет оружие.</div></div></div>';
}
function invDock() {
  const P = G.player, H = invWho(P), s = UI.isel, hint = dockHint('Выбери слот куклы или вещь в рюкзаке. Подходящие вещи подсветятся зелёной рамкой.', 'bag');
  if (!s) return hint;
  if (s.from === 'slot') {
    const it = eqItem(H, s.k), w = heroWield(H); let acts = '';
    if (!it) { const n = invIds(P, 'gear').filter(id => ITEM[id].slot === s.k).length; return '<div class="dock hint">' + tile({ ghost: SLOT_ICON[s.k] }) + '<div class="dinfo"><div class="dnm" style="color:var(--parch2)">' + SLOT_NAME[s.k] + ': пусто</div><div class="dsub">' + (n ? 'В рюкзаке подходящих вещей: ' + n + ' (подсвечены).' : 'В рюкзаке ничего подходящего.') + (s.k === 'melee' ? ' Без оружия герой дерётся кулаками.' : '') + '</div></div></div>'; }
    acts += '<button class="btn sm pri" data-act="unequip" data-slot="' + s.k + '">Снять</button>';
    if ((s.k === 'melee' || s.k === 'ranged') && w !== it) acts += '<button class="btn sm" data-act="wield" data-sel="' + s.k + '">Взять в руки</button>';
    return itemDock(it, { acts, sub: 'надето' });
  }
  const it = ITEM[s.id]; if (!it || invN(P, s.id) < 1) { UI.isel = null; return hint; }
  if (it.kind === 'goods') return itemDock(it, { sub: 'в обозе: ' + invN(P, s.id) + ' · общий вес ' + Math.round(it.w * invN(P, s.id) * 10) / 10 });
  const mel = eqItem(H, 'melee'), blocked = it.slot === 'shield' && mel && mel.hands === 2, hint2 = blocked ? '<div class="dsub dn">С двуручным оружием щит не носят.</div>' : it.slot === 'melee' && it.hands === 2 && eqItem(H, 'shield') ? '<div class="dsub">Щит уйдёт в рюкзак.</div>' : '';
  return itemDock(it, { cmp: true, sub: invN(P, s.id) > 1 ? 'в рюкзаке: ' + invN(P, s.id) : '', acts: hint2 + '<button class="btn sm pri" data-act="equip" data-id="' + s.id + '" ' + (blocked ? 'disabled' : '') + '>Надеть</button>' });
}
ACT.isel = function (d) { const dbl = dblTap(d, 'i|' + (d.id || d.k)); if (dbl) return dbl(d); UI.isel = d.from === 'slot' ? { from: 'slot', k: d.k } : { from: 'bag', id: d.id }; keepScroll(renderPanel); };
ACT.bagf = function (d) { UI.bagF = d.f; keepScroll(renderPanel); };
ACT.equip = function (d) { if (NET.on) { NET.send({ t: 'equip', id: d.id }); sfx('order'); return; } const it = ITEM[d.id], r = doEquip(G.player, d.id, invWho(G.player)); if (r.ok) { sfx('order'); UI.isel = { from: 'slot', k: it.slot }; if (r.note) toast(r.note); } else if (r.note) toast(r.note); keepScroll(renderPanel); };
ACT.unequip = function (d) { if (NET.on) { NET.send({ t: 'unequip', slot: d.slot }); sfx('click'); return; } const H = invWho(G.player), id = heroEq(H)[d.slot]; if (doUnequip(G.player, d.slot, H)) { sfx('click'); UI.isel = { from: 'bag', id }; } keepScroll(renderPanel); };
ACT.wield = function (d) { if (NET.on) { NET.send({ t: 'wield', sel: d.sel }); sfx('click'); return; } if (doWield(G.player, d.sel, invWho(G.player))) sfx('click'); keepScroll(renderPanel); };
ACT.inv = function () { openPanel('inv'); };
