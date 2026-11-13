/* ================= инвентарь и торговля: логика (без DOM) ================= */
/* Хранение: P.inv = { id: количество } — всё, что лежит в обозе (не надето).
   Рынок поселения: s.market = { day, gold, stock: { id: количество } }, создаётся лениво при первом заходе,
   поэтому старые сохранения грузятся без миграции. Надетое хранится в слотах героя P.hero.eq (см. 01b_gear.js),
   бой и сервер ничего не знают об обозе. */

const GOODS = {
  grain:   { n: 'Зерно',    p: 14,  w: 1,   c: '#c9a24a', raw: 1, make: ['emp', 'kin'],  need: ['nord', 'khan', 'emi'] },
  salt:    { n: 'Соль',     p: 40,  w: 1,   c: '#dfe3e6', make: ['khan', 'emi'], need: ['nord', 'emp', 'kin', 'dom', 'pact'] },
  ale:     { n: 'Эль',      p: 28,  w: 1.5, c: '#a8741f', make: ['nord', 'kin', 'dom', 'pact'], need: ['emp', 'khan', 'emi'] },
  iron:    { n: 'Железо',   p: 60,  w: 2,   c: '#7e868e', make: ['nord'], need: ['emp', 'khan', 'kin', 'emi', 'dom', 'pact'] },
  leather: { n: 'Кожа',     p: 45,  w: 1,   c: '#7a4e2c', raw: 1, make: ['khan', 'emi'], need: ['nord', 'emp', 'kin'] },
  furs:    { n: 'Меха',     p: 110, w: 1,   c: '#5b4636', raw: 1, make: ['nord', 'dom'], need: ['emp', 'khan', 'kin', 'emi', 'pact'] },
  cloth:   { n: 'Сукно',    p: 75,  w: 1,   c: '#6d5aa0', make: ['emp', 'kin'],  need: ['nord', 'khan', 'emi', 'dom', 'pact'] },
  wine:    { n: 'Вино',     p: 90,  w: 1.5, c: '#8a1f3a', lux: 1, make: ['emp', 'kin'],  need: ['nord', 'khan', 'emi', 'dom', 'pact'] },
  spice:   { n: 'Пряности', p: 220, w: .3,  c: '#c4622a', lux: 1, make: ['khan', 'emi'], need: ['nord', 'emp', 'kin', 'dom', 'pact'] },
  potato:  { n: 'Картошка', p: 12,  w: 1,   c: '#b99a5b', raw: 1, make: ['dom'], need: ['nord', 'emp', 'khan', 'kin', 'emi', 'pact'] }, // особый товар Мядельского доминиона
  zurek:   { n: 'Журек',    p: 46,  w: 1.5, c: '#d8d0a2', make: ['pact'], need: ['nord', 'emp', 'khan', 'kin', 'emi', 'dom'] } // особый товар Варшавско-Познаньского пакта
};
const GEAR_APPEAR = [.6, .42, .28, .16];  // шанс, что вещь такого уровня есть у торговца при создании рынка (до поправки на фракцию)
const GEAR_DAILY = [.13, .09, .06, .035]; // шанс, что отсутствующая вещь появится за день
const MK_GOLD = { town: 2600, castle: 1400, village: 800 };
const MK_GOODS = { town: 16, castle: 5, village: 9 };

/* каталог: id → предмет. Снаряжение берётся из EQ (01b_gear.js), товары — из GOODS */
const ITEM = {};
for (const id in EQ) ITEM[id] = Object.assign({ kind: 'gear' }, EQ[id]);
for (const k of Object.keys(GOODS)) ITEM[k] = { id: k, kind: 'goods', name: GOODS[k].n, price: GOODS[k].p, w: GOODS[k].w, c: GOODS[k].c };

/* ---------- обоз героя ---------- */
function invOf(P) { return P.inv || (P.inv = {}); }
function invN(P, id) { return invOf(P)[id] || 0; }
function invAdd(P, id, n) { const I = invOf(P), v = (I[id] || 0) + n; if (v > 0) I[id] = v; else delete I[id]; }
function invWeight(P) { const I = invOf(P); let w = 0; for (const id in I) if (ITEM[id]) w += ITEM[id].w * I[id]; return Math.round(w * 10) / 10; }
function cargoCap(P) { const H = P.hero; return Math.round((60 + troopCount(P.troops) * 3 + H.str * 6 + (eqItem(H, 'horse') ? 30 : 0)) * (1 + perkFx(H).cargo)); }
function invIds(P, kind) { return Object.keys(invOf(P)).filter(id => ITEM[id] && ITEM[id].kind === kind).sort((a, b) => ITEM[a].price - ITEM[b].price); }
function equippedId(P, slot) { const id = heroEq(P.hero)[slot]; return id && ITEM[id] ? id : null; }

/* ---------- рынок поселения ---------- */
function hasMarket(s) { return s && s.kind !== 'camp' && s.fac !== 'bandit'; }
function goodTarget(s, id) {
  const g = GOODS[id]; let t = MK_GOODS[s.kind] || 8;
  if (g.make.includes(sCult(s))) t *= 1.7; else if (g.need.includes(sCult(s))) t *= .45;
  if (s.kind === 'village' && !g.raw) t *= .5;
  if (s.kind === 'castle' && !['grain', 'ale', 'salt', 'iron'].includes(id)) t *= .4;
  return Math.max(1, Math.round(t));
}
function gearPool(s) { // что вообще может продаваться в поселении: деревня до 1 уровня, город до 2, замок до 3
  const max = s.kind === 'village' ? 1 : s.kind === 'town' ? 2 : 3, out = [];
  for (const id in ITEM) { const it = ITEM[id]; if (it.kind === 'gear' && it.tier <= max) out.push(id); }
  return out;
}
function gearOdds(s, id, table) { const it = ITEM[id]; return table[it.tier] * (it.f ? (it.f.includes(sCult(s)) ? 1.5 : .45) : 1); } // местные товары попадаются чаще
function mkMarket(s) {
  const m = { day: G.day, gold: Math.round((MK_GOLD[s.kind] || 800) * rnd(.7, 1.1)), stock: {} };
  for (const id in GOODS) m.stock[id] = Math.round(goodTarget(s, id) * rnd(.6, 1.4));
  for (const id of gearPool(s)) if (Math.random() < gearOdds(s, id, GEAR_APPEAR)) m.stock[id] = rint(1, 2);
  return m;
}
function marketDay(s, m) {
  m.gold += Math.round(((MK_GOLD[s.kind] || 800) - m.gold) * .12) + 20;
  for (const id in GOODS) { const t = goodTarget(s, id), v = m.stock[id] || 0; m.stock[id] = Math.max(0, v + Math.round((t - v) * .22 + rnd(-1.4, 1.4))); }
  for (const id of gearPool(s)) { const v = m.stock[id] || 0; if (v > 3) m.stock[id] = v - 1; else if (!v && Math.random() < gearOdds(s, id, GEAR_DAILY)) m.stock[id] = 1; }
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
  let m = g.make.includes(sCult(s)) ? .78 : g.need.includes(sCult(s)) ? 1.22 : 1;
  if (s.kind === 'village' && g.raw) m *= .9; if (s.kind === 'town' && g.lux) m *= 1.08;
  return m;
}
function stockMod(s, id) { if (ITEM[id].kind !== 'goods') return 1; return clamp(1.5 - .5 * (marketOf(s).stock[id] || 0) / Math.max(12, goodTarget(s, id)), .6, 1.6); } // знаменатель не меньше 12, чтобы партия в 10 штук не обрушивала цену на «бедном» рынке
function relMod(P, s) { return clamp((P.rel && P.rel[s.fac]) || 0, -100, 100) * .0006; } // дружба до ±6% к цене
function buyPrice(P, s, id) { const it = ITEM[id]; return Math.max(1, Math.round(it.price * regionMod(s, id) * stockMod(s, id) * (it.kind === 'gear' ? 1.25 : 1.08) * (1 - relMod(P, s)) * (1 - perkFx(P.hero).buy))); }
function sellPrice(P, s, id) { // продажа никогда не выгоднее покупки в том же городе: дружба и перк «Торговец» не должны давать вечный двигатель
  const it = ITEM[id], raw = Math.round(it.price * regionMod(s, id) * stockMod(s, id) * (it.kind === 'gear' ? .5 : .92) * (1 + relMod(P, s)) * (1 + perkFx(P.hero).sell));
  return Math.max(1, Math.min(raw, Math.floor(buyPrice(P, s, id) * .93)));
}
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
function doEquip(P, id) { // → { ok, note }; предмет берётся из обоза, прежний из слота уходит в обоз
  const it = ITEM[id], H = P.hero; if (!it || it.kind !== 'gear' || invN(P, id) < 1) return { ok: false, note: '' };
  const eq = heroEq(H), melee = eq.melee && EQ[eq.melee]; let note = '';
  if (it.slot === 'shield' && melee && melee.hands === 2) return { ok: false, note: 'Со двуручным оружием щит не носят.' };
  const old = eq[it.slot]; invAdd(P, id, -1); if (old) invAdd(P, old, 1); eq[it.slot] = id;
  if (it.slot === 'melee' && it.hands === 2 && eq.shield) { invAdd(P, eq.shield, 1); eq.shield = null; note = 'Щит убран в обоз: двуручное оружие.'; }
  if (it.slot === 'horse') syncLegacy(H);
  return { ok: true, note };
}
function doUnequip(P, slot) { const H = P.hero, eq = heroEq(H), id = eq[slot]; if (!id) return false; invAdd(P, id, 1); eq[slot] = null; if (slot === 'horse') syncLegacy(H); if (slot === 'ranged' && H.sel === 'ranged') H.sel = 'melee'; return true; }
function doUnequipHorse(P) { return doUnequip(P, 'horse'); } // оставлено для сервера (server/sim.js импортирует эту функцию)
function doWield(P, sel) { const H = P.hero; if (sel === 'ranged' && !heroEq(H).ranged) return false; H.sel = sel; return true; } // какое оружие в руках в начале боя

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
      const top = clamp(Math.round(avg), 0, 3), pool = Object.keys(ITEM).filter(k => ITEM[k].kind === 'gear' && ITEM[k].tier <= top && (ITEM[k].slot !== 'horse' || mounted)), ws = pool.map(k => (ITEM[k].f && ITEM[k].f.includes(p.fac) ? 2.2 : 1) / (1 + ITEM[k].tier));
      let r = Math.random() * ws.reduce((a, b) => a + b, 0), j = 0; while (j < pool.length - 1 && (r -= ws[j]) > 0) j++; id = pool[j];
    }
    if (!ITEM[id]) continue;
    while (n > 0 && w + ITEM[id].w * n > cap + 1e-6) n--; // что не влезает в обоз, остаётся на поле
    if (n < 1) continue;
    w += ITEM[id].w * n; invAdd(P, id, n); got[id] = (got[id] || 0) + n;
  }
  return Object.keys(got).map(id => ({ id, n: got[id] }));
}
function dropText(list) { return list.map(d => ITEM[d.id].name + (d.n > 1 ? ' ×' + d.n : '')).join(', '); }
