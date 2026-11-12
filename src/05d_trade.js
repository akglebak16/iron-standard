/* ================= инвентарь и торговля: логика (без DOM) ================= */
/* Хранение: P.inv = { id: количество } — всё, что лежит в обозе (не надето).
   Рынок поселения: s.market = { day, gold, stock: { id: количество } }, создаётся лениво при первом заходе,
   поэтому старые сохранения грузятся без миграции. Надетое снаряжение по-прежнему хранится индексами
   в P.hero.weapon/armor/shield/horse, бой и сервер ничего не знают об обозе. */

const GOODS = {
  grain:   { n: 'Зерно',    p: 14,  w: 1,   c: '#c9a24a', raw: 1, make: ['emp'],  need: ['nord', 'khan'] },
  salt:    { n: 'Соль',     p: 40,  w: 1,   c: '#dfe3e6', make: ['khan'], need: ['nord', 'emp'] },
  ale:     { n: 'Эль',      p: 28,  w: 1.5, c: '#a8741f', make: ['nord'], need: ['emp', 'khan'] },
  iron:    { n: 'Железо',   p: 60,  w: 2,   c: '#7e868e', make: ['nord'], need: ['emp', 'khan'] },
  leather: { n: 'Кожа',     p: 45,  w: 1,   c: '#7a4e2c', raw: 1, make: ['khan'], need: ['nord', 'emp'] },
  furs:    { n: 'Меха',     p: 110, w: 1,   c: '#5b4636', raw: 1, make: ['nord'], need: ['emp', 'khan'] },
  cloth:   { n: 'Сукно',    p: 75,  w: 1,   c: '#6d5aa0', make: ['emp'],  need: ['nord', 'khan'] },
  wine:    { n: 'Вино',     p: 90,  w: 1.5, c: '#8a1f3a', lux: 1, make: ['emp'],  need: ['nord', 'khan'] },
  spice:   { n: 'Пряности', p: 220, w: .3,  c: '#c4622a', lux: 1, make: ['khan'], need: ['nord', 'emp'] }
};
const GEAR_W = { weapon: [3, 3.5, 3.5, 4], armor: [6, 14, 18, 26], shield: [3, 4, 5], horse: [0, 0, 0] };
const GEAR_BASE = { weapon: 40, armor: 35, shield: 25, horse: 0 }; // цена бесплатных стартовых вещей (в GEAR у них p: 0)
const GEAR_APPEAR = [.85, .6, .4, .22];  // шанс, что вещь такого уровня есть у торговца при создании рынка
const GEAR_DAILY = [.14, .1, .06, .03];  // шанс, что отсутствующая вещь появится за день
const MK_GOLD = { town: 2600, castle: 1400, village: 800 };
const MK_GOODS = { town: 16, castle: 5, village: 9 };

/* каталог: id → предмет. Снаряжение строится из GEAR (id вида 'weapon:2'), товары — из GOODS */
const ITEM = {};
for (const k of Object.keys(GEAR)) GEAR[k].forEach((g, i) => {
  if (k === 'horse' && !i) return; // «Пеший» — не предмет
  ITEM[k + ':' + i] = { id: k + ':' + i, kind: 'gear', slot: k, idx: i, name: g.n, v: g.v, price: g.p || GEAR_BASE[k], w: (GEAR_W[k] || [])[i] || 0 };
});
for (const k of Object.keys(GOODS)) ITEM[k] = { id: k, kind: 'goods', name: GOODS[k].n, price: GOODS[k].p, w: GOODS[k].w, c: GOODS[k].c };

/* ---------- обоз героя ---------- */
function invOf(P) { return P.inv || (P.inv = {}); }
function invN(P, id) { return invOf(P)[id] || 0; }
function invAdd(P, id, n) { const I = invOf(P), v = (I[id] || 0) + n; if (v > 0) I[id] = v; else delete I[id]; }
function invWeight(P) { const I = invOf(P); let w = 0; for (const id in I) if (ITEM[id]) w += ITEM[id].w * I[id]; return Math.round(w * 10) / 10; }
function cargoCap(P) { const H = P.hero; return 60 + troopCount(P.troops) * 3 + H.str * 6 + (H.horse ? 30 : 0); }
function invIds(P, kind) { return Object.keys(invOf(P)).filter(id => ITEM[id] && ITEM[id].kind === kind).sort((a, b) => ITEM[a].price - ITEM[b].price); }
function equippedId(P, slot) { const id = slot + ':' + P.hero[slot]; return ITEM[id] ? id : null; }

/* ---------- рынок поселения ---------- */
function hasMarket(s) { return s && s.kind !== 'camp' && s.fac !== 'bandit'; }
function goodTarget(s, id) {
  const g = GOODS[id]; let t = MK_GOODS[s.kind] || 8;
  if (g.make.includes(s.fac)) t *= 1.7; else if (g.need.includes(s.fac)) t *= .45;
  if (s.kind === 'village' && !g.raw) t *= .5;
  if (s.kind === 'castle' && !['grain', 'ale', 'salt', 'iron'].includes(id)) t *= .4;
  return Math.max(1, Math.round(t));
}
function gearPool(s) {
  const max = s.kind === 'village' ? 1 : s.kind === 'town' ? 2 : 3, out = [];
  for (const id in ITEM) { const it = ITEM[id]; if (it.kind !== 'gear') continue; if (it.slot === 'horse' ? (s.kind === 'village' ? it.idx <= 1 : true) : it.idx <= max) out.push(id); }
  return out;
}
function mkMarket(s) {
  const m = { day: G.day, gold: Math.round((MK_GOLD[s.kind] || 800) * rnd(.7, 1.1)), stock: {} };
  for (const id in GOODS) m.stock[id] = Math.round(goodTarget(s, id) * rnd(.6, 1.4));
  for (const id of gearPool(s)) if (Math.random() < GEAR_APPEAR[ITEM[id].idx]) m.stock[id] = rint(1, 2);
  return m;
}
function marketDay(s, m) {
  m.gold += Math.round(((MK_GOLD[s.kind] || 800) - m.gold) * .12) + 20;
  for (const id in GOODS) { const t = goodTarget(s, id), v = m.stock[id] || 0; m.stock[id] = Math.max(0, v + Math.round((t - v) * .22 + rnd(-1.4, 1.4))); }
  for (const id of gearPool(s)) { const v = m.stock[id] || 0; if (v > 3) m.stock[id] = v - 1; else if (!v && Math.random() < GEAR_DAILY[ITEM[id].idx]) m.stock[id] = 1; }
}
function marketOf(s) { // ленивое создание и догон по дням (до 20 дней за раз)
  if (NET.on && s.market) return s.market; // в сети рынком владеет сервер
  if (!s.market) s.market = mkMarket(s);
  const m = s.market, d = Math.min(20, Math.max(0, G.day - m.day));
  for (let k = 0; k < d; k++) marketDay(s, m);
  m.day = G.day; return m;
}

/* ---------- цены ---------- */
function regionMod(s, id) {
  const g = GOODS[id]; if (!g) return 1;
  let m = g.make.includes(s.fac) ? .78 : g.need.includes(s.fac) ? 1.22 : 1;
  if (s.kind === 'village' && g.raw) m *= .9; if (s.kind === 'town' && g.lux) m *= 1.08;
  return m;
}
function stockMod(s, id) { if (ITEM[id].kind !== 'goods') return 1; return clamp(1.5 - .5 * (marketOf(s).stock[id] || 0) / Math.max(12, goodTarget(s, id)), .6, 1.6); } // знаменатель не меньше 12, чтобы партия в 10 штук не обрушивала цену на «бедном» рынке
function relMod(P, s) { return clamp((P.rel && P.rel[s.fac]) || 0, -100, 100) * .0006; } // дружба до ±6% к цене
function buyPrice(P, s, id) { const it = ITEM[id]; return Math.max(1, Math.round(it.price * regionMod(s, id) * stockMod(s, id) * (it.kind === 'gear' ? 1.25 : 1.08) * (1 - relMod(P, s)))); }
function sellPrice(P, s, id) { const it = ITEM[id]; return Math.max(1, Math.round(it.price * regionMod(s, id) * stockMod(s, id) * (it.kind === 'gear' ? .5 : .92) * (1 + relMod(P, s)))); }
function priceLevel(s, id) { if (ITEM[id].kind !== 'goods') return ''; const r = regionMod(s, id) * stockMod(s, id); return r < .88 ? 'low' : r > 1.12 ? 'high' : ''; } // цена здесь ниже/выше обычной

/* ---------- сделки: цена пересчитывается на каждую единицу, поэтому крупная партия дорожает/дешевеет ---------- */
function doBuy(P, s, id, n) {
  const it = ITEM[id]; if (!it || !hasMarket(s)) return { n: 0, sum: 0, why: 'none' };
  const m = marketOf(s), cap = cargoCap(P); let w = invWeight(P), k = 0, sum = 0, why = '';
  while (k < n) {
    if ((m.stock[id] || 0) < 1) { why = 'stock'; break; }
    const pr = buyPrice(P, s, id);
    if (P.gold < pr) { why = 'gold'; break; }
    if (w + it.w > cap + 1e-6) { why = 'weight'; break; }
    P.gold -= pr; sum += pr; m.stock[id]--; m.gold += pr; w += it.w; invAdd(P, id, 1); k++;
  }
  return { n: k, sum, why };
}
function doSell(P, s, id, n) {
  const it = ITEM[id]; if (!it || !hasMarket(s)) return { n: 0, sum: 0, why: 'none' };
  const m = marketOf(s); let k = 0, sum = 0, why = '';
  while (k < n) {
    if (invN(P, id) < 1) break;
    const pr = sellPrice(P, s, id);
    if (m.gold < pr) { why = 'merchant'; break; }
    P.gold += pr; sum += pr; m.gold -= pr; m.stock[id] = (m.stock[id] || 0) + 1; invAdd(P, id, -1); k++;
  }
  return { n: k, sum, why };
}
const TRADE_WHY = { stock: 'У торговца больше нет этого товара.', gold: 'Не хватает золота.', weight: 'В обозе не хватает места.', merchant: 'У торговца кончились деньги.', none: 'Здесь не торгуют.' };

/* ---------- экипировка ---------- */
function doEquip(P, id) {
  const it = ITEM[id]; if (!it || it.kind !== 'gear' || invN(P, id) < 1) return false;
  const old = equippedId(P, it.slot); invAdd(P, id, -1); if (old) invAdd(P, old, 1); P.hero[it.slot] = it.idx; return true;
}
function doUnequipHorse(P) { const old = equippedId(P, 'horse'); if (!old) return false; invAdd(P, old, 1); P.hero.horse = 0; return true; }

/* ---------- трофеи после победы ---------- */
function rollLoot(P, p) {
  let tot = 0, tsum = 0, mounted = 0; for (const s of p.troops) { const t = TROOPS[s.type]; tot += s.n; tsum += t.tier * s.n; if (t.mounted) mounted += s.n; }
  if (!tot) return [];
  const avg = tsum / tot, rolls = clamp(Math.round(tot * .12), 1, 6), got = {}, ids = Object.keys(GOODS), cap = cargoCap(P); let w = invWeight(P);
  for (let i = 0; i < rolls; i++) {
    let id, n = 1;
    if (p.kind === 'caravan' || Math.random() < .3) {
      const own = ids.filter(g => GOODS[g].make.includes(p.fac)); id = pick(p.kind === 'caravan' && own.length ? own : ids); n = clamp(Math.round(rint(120, 300) / GOODS[id].p), 1, 14);
    } else {
      const slot = mounted && Math.random() < .12 ? 'horse' : pick(['weapon', 'weapon', 'armor', 'armor', 'shield']), top = Math.min(GEAR[slot].length - 1, Math.round(avg));
      let idx = Math.floor(Math.pow(Math.random(), 1.6) * (top + 1)); if (slot === 'horse') idx = Math.max(1, idx); id = slot + ':' + idx;
    }
    if (!ITEM[id]) continue;
    while (n > 0 && w + ITEM[id].w * n > cap + 1e-6) n--; // что не влезает в обоз, остаётся на поле
    if (n < 1) continue;
    w += ITEM[id].w * n; invAdd(P, id, n); got[id] = (got[id] || 0) + n;
  }
  return Object.keys(got).map(id => ({ id, n: got[id] }));
}
function dropText(list) { return list.map(d => ITEM[d.id].name + (d.n > 1 ? ' ×' + d.n : '')).join(', '); }
