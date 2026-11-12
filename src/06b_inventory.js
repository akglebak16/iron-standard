/* ================= инвентарь и торговля: интерфейс ================= */
const SLOT_ORDER = ['weapon', 'armor', 'shield', 'horse'];
const SLOT_ICON = { weapon: 'sword', armor: 'helm', shield: 'shield', horse: 'horse' };
function statText(it) { return it.kind === 'gear' ? GEAR_UNIT[it.slot] + ' ' + (it.slot === 'shield' ? Math.round(it.v * 100) + '%' : it.v) : ''; }
function itemSw(it) { return it.kind === 'goods' ? '<span class="isw" style="background:' + it.c + '"></span>' : '<span class="isw gear">' + ic(SLOT_ICON[it.slot], 16) + '</span>'; }
function cargoBar(P) { const w = invWeight(P), c = cargoCap(P); return '<div class="kv"><span>Обоз</span><b class="' + (w > c ? 'dn' : '') + '">' + w + ' / ' + c + '</b></div><div class="pbar cargo' + (w > c ? ' over' : '') + '"><i style="width:' + clamp(w / c * 100, 0, 100) + '%"></i></div>'; }
function gearDelta(P, it) { // насколько вещь лучше надетой
  const eq = equippedId(P, it.slot), cur = eq ? ITEM[eq].v : 0, d = it.v - cur, sh = it.slot === 'shield', n = sh ? Math.round(d * 100) + '%' : Math.round(d * 10) / 10;
  return d > 0 ? '<b class="up">+' + n + '</b>' : d < 0 ? '<b class="dn">' + n + '</b>' : '<b>=</b>';
}
function keepScroll(fn) { const b = document.querySelector('#modal .wbody'), t = b ? b.scrollTop : 0; fn(); const n = document.querySelector('#modal .wbody'); if (n) n.scrollTop = t; }

/* ---------- вкладка «Торговля» в городе, замке и деревне ---------- */
function tradeRow(s, P, id, side) {
  const it = ITEM[id], m = marketOf(s), buy = side === 'buy', have = buy ? (m.stock[id] || 0) : invN(P, id), pr = buy ? buyPrice(P, s, id) : sellPrice(P, s, id), lv = priceLevel(s, id);
  const tone = !lv ? '' : (buy ? lv === 'low' : lv === 'high') ? 'cheap' : 'dear';
  const ok = buy ? have > 0 && P.gold >= pr : have > 0 && m.gold >= pr;
  const note = it.kind === 'gear' ? statText(it) + ' (' + gearDelta(P, it) + ' к надетому) · вес ' + it.w : 'вес ' + it.w + (lv ? ' · здесь ' + (lv === 'low' ? 'дёшево' : 'дорого') : '');
  const nn = it.kind === 'gear' ? [1] : [1, 5, 99], lab = n => n === 99 ? (buy ? 'Макс.' : 'Все') : '×' + n;
  const btns = nn.map(n => '<button class="btn sm" data-act="' + (buy ? 'tbuy' : 'tsell') + '" data-id="' + id + '" data-n="' + n + '" ' + (ok ? '' : 'disabled') + '>' + lab(n) + '</button>').join('');
  return '<div class="row sm">' + itemSw(it) + '<div class="grow"><div class="nm">' + it.name + '</div><div class="ds">' + note + '</div></div><div class="cnt">' + have + '</div><span class="price ' + tone + '" title="' + (buy ? 'Цена покупки' : 'Цена продажи') + '">' + ic('coin') + pr + '</span><div class="acts">' + btns + '</div></div>';
}
function tradeBody(s) {
  const P = G.player; if (!hasMarket(s)) return '<div class="note">Здесь не торгуют.</div>';
  const m = marketOf(s), ord = (a, b) => (ITEM[a].kind === ITEM[b].kind ? ITEM[a].price - ITEM[b].price : ITEM[a].kind === 'goods' ? -1 : 1);
  const mine = invIds(P, 'goods').concat(invIds(P, 'gear')), theirs = Object.keys(m.stock).filter(id => ITEM[id] && m.stock[id] > 0).sort(ord);
  return '<div class="note">Золото: ' + fmt(P.gold) + ' · у торговца: ' + fmt(m.gold) + '. Цена зависит от края и от запаса на складе: вози дешёвое туда, где за него дают больше. Чем крупнее партия, тем сильнее она сдвигает цену.</div>' + cargoBar(P) +
    '<div class="trade"><div><h3>Твой обоз</h3>' + (mine.length ? mine.map(id => tradeRow(s, P, id, 'sell')).join('') : '<div class="note">Обоз пуст. Купи товар здесь или добудь трофеи в бою.</div>') + '</div>' +
    '<div><h3>Торговец</h3>' + (theirs.length ? theirs.map(id => tradeRow(s, P, id, 'buy')).join('') : '<div class="note">Прилавок пуст.</div>') + '</div></div>';
}
ACT.tbuy = function (d) {
  const P = G.player, n = +d.n, r = doBuy(P, UI.town.s, d.id, n);
  if (r.n) { sfx('coin'); toast('Куплено: ' + ITEM[d.id].name + (r.n > 1 ? ' ×' + r.n : '') + ' за ' + fmt(r.sum)); if (r.n < n && n < 99) toast(TRADE_WHY[r.why] || ''); } else toast(TRADE_WHY[r.why] || 'Не вышло');
  keepScroll(renderTown);
};
ACT.tsell = function (d) {
  const P = G.player, n = +d.n, r = doSell(P, UI.town.s, d.id, n);
  if (r.n) { sfx('coin'); toast('Продано: ' + ITEM[d.id].name + (r.n > 1 ? ' ×' + r.n : '') + ' за ' + fmt(r.sum)); if (r.n < n && n < 99 && r.why) toast(TRADE_WHY[r.why]); } else toast(TRADE_WHY[r.why] || 'Не вышло');
  keepScroll(renderTown);
};

/* ---------- вкладка «Обоз» в панели героя ---------- */
function invBody() {
  const P = G.player, H = P.hero;
  let b = '<div class="note">Снаряжение героя и обоз. Провизия: ' + P.food + ' (вес не занимает). Продавать вещи можно в городах, замках и деревнях, а добычу из боёв стоит нести туда, где за неё дают больше.</div><h3>Надето</h3><div class="cols">';
  for (const k of SLOT_ORDER) {
    const id = equippedId(P, k), it = id && ITEM[id];
    b += '<div class="card"><h3>' + GEAR_LABEL[k] + '</h3>' + (it ? '<div class="kv"><span>' + it.name + '</span><b>' + statText(it) + '</b></div>' : '<div class="note">' + (k === 'horse' ? 'Пеший' : 'Пусто') + '</div>') + (k === 'horse' && it ? '<button class="btn sm" data-act="unhorse">Спешиться и убрать в обоз</button>' : '') + '</div>';
  }
  b += '</div><h3 style="margin-top:14px">Обоз</h3>' + cargoBar(P);
  const goods = invIds(P, 'goods'), gear = invIds(P, 'gear');
  if (!goods.length && !gear.length) b += '<div class="note">Обоз пуст.</div>';
  for (const id of gear) { const it = ITEM[id]; b += '<div class="row sm">' + itemSw(it) + '<div class="grow"><div class="nm">' + it.name + '</div><div class="ds">' + GEAR_LABEL[it.slot] + ' · ' + statText(it) + ' (' + gearDelta(P, it) + ' к надетому) · вес ' + it.w + '</div></div><div class="cnt">' + invN(P, id) + '</div><div class="acts"><button class="btn sm" data-act="equip" data-id="' + id + '">Надеть</button></div></div>'; }
  for (const id of goods) { const it = ITEM[id], n = invN(P, id); b += '<div class="row sm">' + itemSw(it) + '<div class="grow"><div class="nm">' + it.name + '</div><div class="ds">Товар · вес ' + Math.round(it.w * n * 10) / 10 + ' · обычная цена ' + it.price + '</div></div><div class="cnt">' + n + '</div></div>'; }
  return b;
}
ACT.equip = function (d) { if (doEquip(G.player, d.id)) { sfx('order'); toast('Надето: ' + ITEM[d.id].name); } keepScroll(renderPanel); };
ACT.unhorse = function () { if (doUnequipHorse(G.player)) { sfx('click'); toast('Конь отправлен в обоз'); } keepScroll(renderPanel); };
ACT.inv = function () { openPanel('inv'); };
