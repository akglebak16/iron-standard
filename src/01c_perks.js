/* ================= герой: атрибуты, перки, очки =================
   Общий для клиента и сервера: без DOM. Пять атрибутов (ATTRS в 01_core.js), у каждого четыре перка.
   Все перки доступны с самого начала, у каждого три ранга (уровня). Каждый следующий ранг требует своего уровня атрибута
   и стоит одно очко перков. Очки: за уровень +2 очка атрибутов и +1 очко перков.
   Герой хранит: H.str/vit/agi/int/cha, H.pts (очки атрибутов), H.pp (очки перков), H.perks (список id изученных).
   Ранг перка = сколько раз его id встречается в H.perks: ['grip', 'grip', 'tough'] это «Крепкая хватка» II и «Закалка» I.
   Так формат совместим с первой версией перков (там каждый id был один раз = ранг I) и с сохранениями и сетью.
   Старые герои (Лидерство, без Интеллекта и перков) чинятся лениво через heroFix(H), поэтому старые сохранения грузятся без миграции. */

const PTS_LEVEL = 2, PP_LEVEL = 1, PTS_START = 2, PP_START = 1; // очки за уровень и на старте
const PERK_MAX = 3;                                              // рангов у каждого перка

/* req: уровень атрибута для рангов I, II, III. «Обычные» перки 3/6/9, самые сильные 4/7/10.
   fx: что перк даёт на каждом ранге (итоговое значение на этом ранге, не прибавка). Доли: 0.12 = +12%; arm, size, morale в единицах. */
const REQ_A = [3, 6, 9], REQ_B = [4, 7, 10];
const PERKS = [
  // Сила
  { id: 'grip',      a: 'str', n: 'Крепкая хватка',     req: REQ_A, fx: { heavy: [.06, .12, .18] } },
  { id: 'packhorse', a: 'str', n: 'Тяжеловоз',          req: REQ_A, fx: { cargo: [.12, .25, .4] } },
  { id: 'breaker',   a: 'str', n: 'Сокрушитель',        req: REQ_A, fx: { mpierce: [.04, .08, .12] } },
  { id: 'butcher',   a: 'str', n: 'Мясник',             req: REQ_B, fx: { killHeal: [.02, .04, .06] } },
  // Стойкость
  { id: 'tough',     a: 'vit', n: 'Закалка',            req: REQ_A, fx: { hp: [.06, .12, .18] } },
  { id: 'hide',      a: 'vit', n: 'Толстая кожа',       req: REQ_A, fx: { arm: [3, 6, 9] } },
  { id: 'recover',   a: 'vit', n: 'Живучий',            req: REQ_A, fx: { heal: [.3, .6, 1] } },
  { id: 'lastStand', a: 'vit', n: 'Последний рубеж',    req: REQ_B, fx: { lastStand: [.2, .3, .45] } },
  // Ловкость
  { id: 'quick',     a: 'agi', n: 'Быстрые руки',       req: REQ_A, fx: { cd: [.04, .08, .12] } },
  { id: 'eagle',     a: 'agi', n: 'Меткий глаз',        req: REQ_A, fx: { acc: [.2, .35, .5], range: [.05, .1, .15] } },
  { id: 'light',     a: 'agi', n: 'Лёгкая поступь',     req: REQ_A, fx: { map: [.04, .08, .12], flee: [.05, .1, .15], run: [.03, .05, .08] } },
  { id: 'master',    a: 'agi', n: 'Мастер оружия',      req: REQ_B, fx: { dmg: [.06, .12, .18] } },
  // Интеллект
  { id: 'surgery',   a: 'int', n: 'Хирургия',           req: REQ_A, fx: { surv: [.1, .2, .3] } },
  { id: 'learner',   a: 'int', n: 'Сообразительный',    req: REQ_A, fx: { xp: [.08, .15, .25] } },
  { id: 'merchant',  a: 'int', n: 'Торговец',           req: REQ_A, fx: { buy: [.03, .05, .08], sell: [.03, .05, .08] } },
  { id: 'tactician', a: 'int', n: 'Тактик',             req: REQ_B, fx: { ally: [.04, .08, .12], morale: [3, 6, 9] } },
  // Харизма
  { id: 'inspire',   a: 'cha', n: 'Вдохновляющий',      req: REQ_A, fx: { morale: [6, 12, 18] } },
  { id: 'recruiter', a: 'cha', n: 'Вербовщик',          req: REQ_A, fx: { hire: [.08, .15, .25] } },
  { id: 'commander', a: 'cha', n: 'Командир',           req: REQ_A, fx: { size: [5, 10, 15], wage: [.05, .1, .15] } },
  { id: 'famous',    a: 'cha', n: 'Знаменитый наёмник', req: REQ_B, fx: { quest: [.1, .2, .3], loot: [.1, .2, .3] } }
];
const PERK = {}; for (const p of PERKS) PERK[p.id] = p;
const FX_ZERO = Object.freeze({ heavy: 0, cargo: 0, mpierce: 0, killHeal: 0, hp: 0, arm: 0, heal: 0, lastStand: 0, cd: 0, acc: 0, range: 0, map: 0, flee: 0, run: 0, dmg: 0, surv: 0, xp: 0, buy: 0, sell: 0, ally: 0, morale: 0, hire: 0, size: 0, wage: 0, quest: 0, loot: 0, siege: 0 });

/* Как эффект выглядит в тексте: t — фраза, u — единица, m — множитель (доли показываем в процентах).
   Из этого собирается описание перка сразу для всех трёх рангов: «бьёт сильнее на 6 / 12 / 18%». */
const FX_TXT = {
  heavy: { t: 'Двуручное и древковое оружие бьёт сильнее на', u: '%', m: 100 },
  cargo: { t: 'Обоз вмещает больше груза на', u: '%', m: 100 },
  mpierce: { t: 'Удары ближнего боя игнорируют ещё', u: '% брони', m: 100 },
  killHeal: { t: 'За каждого сражённого врага здоровье растёт на', u: '%', m: 100 },
  hp: { t: 'Здоровье героя выше на', u: '%', m: 100 },
  arm: { t: 'Броня героя выше на', u: '', m: 1 },
  heal: { t: 'Герой лечится на карте быстрее на', u: '%', m: 100 },
  lastStand: { t: 'Раз за бой при смертельном ударе герой встаёт со здоровьем', u: '%', m: 100 },
  cd: { t: 'Удары и выстрелы быстрее на', u: '%', m: 100 },
  acc: { t: 'Разброс стрел и болтов меньше на', u: '%', m: 100 },
  range: { t: 'дальность стрельбы больше на', u: '%', m: 100 },
  map: { t: 'Отряд идёт по карте быстрее на', u: '%', m: 100 },
  flee: { t: 'шанс уйти от погони выше на', u: '%', m: 100 },
  run: { t: 'бег в бою быстрее на', u: '%', m: 100 },
  dmg: { t: 'Любое оружие бьёт сильнее на', u: '%', m: 100 },
  surv: { t: 'Среди павших бойцов больше раненых, которые вернутся в строй:', u: '%', m: 100 },
  xp: { t: 'Опыта за бои больше на', u: '%', m: 100 },
  buy: { t: 'Покупка дешевле на', u: '%', m: 100 },
  sell: { t: 'продажа дороже на', u: '%', m: 100 },
  ally: { t: 'Бойцы отряда бьют сильнее на', u: '%', m: 100 },
  morale: { t: 'мораль бойцов выше на', u: '', m: 1 },
  hire: { t: 'Найм и улучшение войск дешевле на', u: '%', m: 100 },
  size: { t: 'Отряд больше на', u: '', m: 1 },
  wage: { t: 'жалованье ниже на', u: '%', m: 100 },
  quest: { t: 'Награды за задания больше на', u: '%', m: 100 },
  loot: { t: 'добыча после боя больше на', u: '%', m: 100 }
};
/* Описание перка кусками: [{ t, v: [значение I, II, III], u }]. Интерфейс сам подсвечивает значение текущего ранга. */
function perkParts(p) { return Object.keys(p.fx).map((k, i) => { const f = FX_TXT[k]; return { t: i ? f.t : f.t[0].toUpperCase() + f.t.slice(1), v: p.fx[k].map(x => Math.round(x * f.m)), u: f.u }; }); }
/* Описание одним текстом для выбранного ранга (1..3): удобно для подсказок и проверок */
function perkText(p, rank) { return perkParts(p).map(x => x.t + ' ' + x.v[rank - 1] + x.u).join(', ') + '.'; }

/* Старые герои: Лидерство стало Харизмой, Интеллекта не было, перков не было.
   Очки перков за уже набранные уровни выдаются задним числом (по одному за уровень). */
function heroFix(H) {
  if (!H) return H;
  if (H.cha === undefined) H.cha = H.lead || 1;
  if (H.int === undefined) H.int = 1;
  if (!H.perks) H.perks = [];
  if (H.pp === undefined) H.pp = Math.max(0, (H.lvl || 1) - H.perks.length);
  return H;
}

/* Ранг перка у героя: 0 (не изучен) .. PERK_MAX */
function perkRank(H, id) { let n = 0; const a = H && H.perks; if (a) for (let i = 0; i < a.length; i++) if (a[i] === id) n++; return Math.min(n, PERK_MAX); }
const hasPerk = (H, id) => perkRank(H, id) > 0;

/* Сумма эффектов изученных перков. Кэш в WeakMap, а не в самом герое, чтобы в сохранение и в сеть не попадало лишнего. */
const FXC = new WeakMap();
const FXP = new WeakMap();
function perkFx(H) { // перки героя плюс умения его спутников (05e_comps.js): спутники есть только у героя игрока в одиночной игре
  const own = ownPerkFx(H), cf = H ? compFxForHero(H) : null; if (!cf) return own;
  const c = FXP.get(H); if (c && c.own === own && c.k === cf.k) return c.f;
  const f = Object.assign({}, own); for (const k in cf.f) f[k] += cf.f[k]; FXP.set(H, { own, k: cf.k, f }); return f;
}
function ownPerkFx(H) {
  const ids = H && H.perks; if (!ids || !ids.length) return FX_ZERO;
  const key = ids.join(','), c = FXC.get(H); if (c && c.k === key) return c.f;
  const f = Object.assign({}, FX_ZERO), seen = {};
  for (const id of ids) { const p = PERK[id]; if (!p || seen[id]) continue; seen[id] = 1; const r = perkRank(H, id); if (r > 0) for (const k in p.fx) f[k] += p.fx[k][r - 1]; }
  FXC.set(H, { k: key, f }); return f;
}

/* Можно ли поднять перк на следующий ранг: '' если да, иначе причина (для кнопок и подсказок) */
function perkWhy(H, id) {
  heroFix(H); const p = PERK[id]; if (!p) return 'Нет такого перка.';
  const r = perkRank(H, id); if (r >= PERK_MAX) return 'Максимальный уровень.';
  if (H[p.a] < p.req[r]) return 'Нужно: ' + ATTRS[p.a][0] + ' ' + p.req[r] + '.';
  if (H.pp < 1) return 'Нет очков перков.';
  return '';
}

/* Цены найма и улучшения с учётом перка «Вербовщик» */
const hireCost = (P, type) => Math.max(1, Math.round(TROOPS[type].cost * (1 - perkFx(P.hero).hire)));
const upgCost = (P, type) => Math.max(1, Math.round(TROOPS[type].upCost * (1 - perkFx(P.hero).hire)));
