/* ================= инвентарь и торговля: интерфейс ================= */
Object.assign(ICONS, {
  body: '<path d="M8 3l4 2 4-2 5 4-3 4-2-1v11H8V10l-2 1-3-4z"/>',
  hands: '<path d="M7 21v-8l-2-3 2-1 2 3V4h2v7V3h2v8V4h2v8V6h2v9l-2 6z"/>',
  legs: '<path d="M9 3h6v10l5 3v5H5v-4l4-2z"/>'
});
const SLOT_ICON = { head: 'helm', body: 'body', hands: 'hands', legs: 'legs', melee: 'sword', ranged: 'bow', shield: 'shield', horse: 'horse' };
const pc = v => Math.round(v * 100) + '%';
function itemSw(it) { return it.kind === 'goods' ? '<span class="isw" style="background:' + it.c + '"></span>' : '<span class="isw gear">' + ic(SLOT_ICON[it.slot], 16) + '</span>'; }
function cargoBar(P) { const w = invWeight(P), c = cargoCap(P); return '<div class="kv"><span>Обоз</span><b class="' + (w > c ? 'dn' : '') + '">' + w + ' / ' + c + '</b></div><div class="pbar cargo' + (w > c ? ' over' : '') + '"><i style="width:' + clamp(w / c * 100, 0, 100) + '%"></i></div>'; }
function swingLabel(spd) { return spd < 1 ? 'быстрое' : spd <= 1.1 ? 'обычное' : spd <= 1.35 ? 'медленное' : 'тяжёлое'; }
function pierceLine(W) { const p = [0, 1, 2].map(i => pc(dtPierce(W.dt, [0, 20, 40][i], W.pb))); return 'пробитие брони лёгкой / средней / тяжёлой: ' + p.join(' / '); }

/* строки с характеристиками предмета: основная и «особенности» */
function statLine(it) {
  if (it.kind !== 'gear') return '';
  if (it.slot === 'melee' || it.slot === 'ranged') return WTYPE[it.wt] + ' · ' + DTYPE[it.dt].n + ' · урон ' + it.dmg + ' · ' + (it.hands === 2 ? 'двуручное' : 'одноручное') + (it.rng ? ' · дальность ' + it.range + ' · перезарядка ' + it.cd + ' с' : (it.reach ? ' · длиннее на ' + it.reach : '') + ' · ' + swingLabel(it.spd) + ' удары');
  return it.slot === 'shield' ? 'блок ' + pc(it.v) : it.slot === 'horse' ? 'скорость ' + it.v : 'броня +' + it.v;
}
function traitLine(it) {
  if (it.kind !== 'gear' || !it.dt) return '';
  const t = [pierceLine(it)]; if (it.brk) t.push('пробивает блок щитом'); if (it.kb >= 2) t.push('сильно отбрасывает'); if (it.anticav) t.push('бонус против конницы'); if (it.cleave >= 4) t.push('задевает до ' + it.cleave + ' целей'); if (it.hands === 2 && !it.rng) t.push('щит не носят'); if (it.rng && it.hands === 2) t.push('щит за спиной');
  return t.join(' · ');
}
function gearDelta(P, it) { // насколько вещь лучше надетой в том же слоте
  const cur = eqItem(P.hero, it.slot), key = it.dmg !== undefined ? 'dmg' : 'v', d = (it[key] || 0) - (cur ? cur[key] || 0 : 0), sh = it.slot === 'shield', n = sh ? Math.round(d * 100) + '%' : Math.round(d * 10) / 10;
  return d > 0 ? '<b class="up">+' + n + '</b>' : d < 0 ? '<b class="dn">' + n + '</b>' : '<b>=</b>';
}
const slotOrd = id => SLOTS.indexOf(ITEM[id].slot);
function keepScroll(fn) { const b = document.querySelector('#modal .wbody'), t = b ? b.scrollTop : 0; fn(); const n = document.querySelector('#modal .wbody'); if (n) n.scrollTop = t; }

/* ---------- вкладка «Торговля» в городе, замке и деревне ---------- */
function tradeRow(s, P, id, side) {
  const it = ITEM[id], m = marketOf(s), buy = side === 'buy', have = buy ? (m.stock[id] || 0) : invN(P, id), pr = buy ? buyPrice(P, s, id) : sellPrice(P, s, id), lv = priceLevel(s, id);
  const tone = !lv ? '' : (buy ? lv === 'low' : lv === 'high') ? 'cheap' : 'dear';
  const ok = buy ? have > 0 && P.gold >= pr : have > 0 && m.gold >= pr;
  const note = it.kind === 'gear' ? SLOT_NAME[it.slot] + ' · ' + statLine(it) + ' (' + gearDelta(P, it) + ' к надетому) · вес ' + it.w : 'вес ' + it.w + (lv ? ' · здесь ' + (lv === 'low' ? 'дёшево' : 'дорого') : '');
  const nn = it.kind === 'gear' ? [1] : [1, 5, 99], lab = n => n === 99 ? (buy ? 'Макс.' : 'Все') : '×' + n;
  const btns = nn.map(n => '<button class="btn sm" data-act="' + (buy ? 'tbuy' : 'tsell') + '" data-id="' + id + '" data-n="' + n + '" ' + (ok ? '' : 'disabled') + '>' + lab(n) + '</button>').join('');
  return '<div class="row sm">' + itemSw(it) + '<div class="grow"><div class="nm">' + it.name + '</div><div class="ds">' + note + '</div>' + (it.kind === 'gear' && traitLine(it) ? '<div class="ds tr">' + traitLine(it) + '</div>' : '') + '</div><div class="cnt">' + have + '</div><span class="price ' + tone + '" title="' + (buy ? 'Цена покупки' : 'Цена продажи') + '">' + ic('coin') + pr + '</span><div class="acts">' + btns + '</div></div>';
}
function tradeBody(s) {
  const P = G.player; if (!hasMarket(s)) return '<div class="note">Здесь не торгуют.</div>';
  const m = marketOf(s), ord = (a, b) => (ITEM[a].kind === ITEM[b].kind ? (ITEM[a].kind === 'gear' ? slotOrd(a) - slotOrd(b) : 0) || ITEM[a].price - ITEM[b].price : ITEM[a].kind === 'goods' ? -1 : 1);
  const mine = invIds(P, 'goods').concat(invIds(P, 'gear')).sort(ord), theirs = Object.keys(m.stock).filter(id => ITEM[id] && m.stock[id] > 0).sort(ord);
  return '<div class="note">Золото: ' + fmt(P.gold) + ' · у торговца: ' + fmt(m.gold) + '. Цена зависит от края и от запаса на складе: вози дешёвое туда, где за него дают больше. Чем крупнее партия, тем сильнее она сдвигает цену. Надетое не продаётся: сначала сними его во вкладке «Обоз».</div>' + cargoBar(P) +
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

/* ---------- вкладка «Герой»: краткая сводка ---------- */
function gearCard(H) {
  const hd = heroDef(H), W = hd.wpn;
  return '<div class="card"><h3>Снаряжение</h3>' + SLOTS.map(k => { const it = eqItem(H, k); return '<div class="kv"><span>' + SLOT_NAME[k] + '</span><b>' + (it ? it.name : '—') + '</b></div>'; }).join('') +
    '<div class="kv"><span>Урон</span><b>' + Math.round(hd.dmg) + ' · ' + DTYPE[W.dt].n.toLowerCase() + '</b></div><p class="note">Одевайся во вкладке «Обоз» (клавиша I). В бою клавиша X меняет оружие.</p></div>';
}

/* ---------- вкладка «Обоз»: кукла героя и вещи ---------- */
function slotCard(P, k) {
  const H = P.hero, it = eqItem(H, k), wield = heroWield(H); let act = '';
  if (it) act += '<button class="btn sm" data-act="unequip" data-slot="' + k + '">Снять</button>';
  if ((k === 'melee' || k === 'ranged') && it && wield !== it) act += '<button class="btn sm" data-act="wield" data-sel="' + k + '">В руки</button>';
  const inHand = (k === 'melee' || k === 'ranged') && it && wield === it, idle = k === 'shield' && it && heroShield(H) === null;
  return '<div class="card slot"><h3>' + ic(SLOT_ICON[k], 18) + ' ' + SLOT_NAME[k] + (inHand ? ' <span class="tag g">в руках</span>' : '') + (idle ? ' <span class="tag">за спиной</span>' : '') + '</h3>' +
    (it ? '<div class="nm">' + it.name + '</div><div class="ds">' + statLine(it) + '</div>' + (traitLine(it) ? '<div class="ds tr">' + traitLine(it) + '</div>' : '') : '<div class="note">' + (k === 'horse' ? 'Пеший' : k === 'melee' ? 'Кулаки' : 'Пусто') + '</div>') +
    (act ? '<div class="acts" style="margin-top:6px">' + act + '</div>' : '') + '</div>';
}
function invBody() {
  const P = G.player, H = P.hero, hd = heroDef(H), W = hd.wpn, Gr = heroGear(H);
  let b = '<div class="note">Снаряжение героя и обоз. Провизия: ' + P.food + ' (вес не занимает). С двуручным оружием щит не носят, луки и арбалеты тоже двуручные. В бою клавиша X меняет ближнее оружие на дальнее.</div>';
  b += '<div class="cols"><div class="card"><h3>Сводка</h3><div class="kv"><span>Броня</span><b>' + hd.arm + '</b></div><div class="kv"><span>Урон</span><b>' + Math.round(hd.dmg) + ' · ' + DTYPE[W.dt].n.toLowerCase() + '</b></div>' +
    '<div class="kv"><span>' + (W.rng ? 'Перезарядка' : 'Время удара') + '</span><b>' + Math.round(hd.cd * 100) / 100 + ' с</b></div><div class="kv"><span>' + (W.rng ? 'Дальность' : 'Длина удара') + '</span><b>' + (W.rng ? W.range : 30 + hd.reach) + '</b></div><div class="kv"><span>Блок</span><b>' + pc(Gr.block) + (Gr.S ? ' (щит)' : ' (оружием)') + '</b></div>' +
    '<div class="ds" style="margin-top:4px">' + pierceLine(W) + '</div><div class="ds">' + DTYPE[W.dt].note + '</div></div></div>';
  b += '<h3 style="margin:14px 0 8px">Надето</h3><div class="cols">' + SLOTS.map(k => slotCard(P, k)).join('') + '</div><h3 style="margin:14px 0 4px">Обоз</h3>' + cargoBar(P);
  const gear = invIds(P, 'gear').sort((a, c) => slotOrd(a) - slotOrd(c) || ITEM[a].price - ITEM[c].price), goods = invIds(P, 'goods');
  if (!goods.length && !gear.length) b += '<div class="note">Обоз пуст.</div>';
  for (const id of gear) { const it = ITEM[id]; b += '<div class="row sm">' + itemSw(it) + '<div class="grow"><div class="nm">' + it.name + '</div><div class="ds">' + SLOT_NAME[it.slot] + ' · ' + statLine(it) + ' (' + gearDelta(P, it) + ' к надетому) · вес ' + it.w + '</div>' + (traitLine(it) ? '<div class="ds tr">' + traitLine(it) + '</div>' : '') + '</div><div class="cnt">' + invN(P, id) + '</div><div class="acts"><button class="btn sm" data-act="equip" data-id="' + id + '">Надеть</button></div></div>'; }
  for (const id of goods) { const it = ITEM[id], n = invN(P, id); b += '<div class="row sm">' + itemSw(it) + '<div class="grow"><div class="nm">' + it.name + '</div><div class="ds">Товар · вес ' + Math.round(it.w * n * 10) / 10 + ' · обычная цена ' + it.price + '</div></div><div class="cnt">' + n + '</div></div>'; }
  return b;
}
ACT.equip = function (d) { const r = doEquip(G.player, d.id); if (r.ok) { sfx('order'); toast('Надето: ' + ITEM[d.id].name); if (r.note) toast(r.note); } else if (r.note) toast(r.note); keepScroll(renderPanel); };
ACT.unequip = function (d) { if (doUnequip(G.player, d.slot)) sfx('click'); keepScroll(renderPanel); };
ACT.wield = function (d) { if (doWield(G.player, d.sel)) sfx('click'); keepScroll(renderPanel); };
ACT.inv = function () { openPanel('inv'); };
