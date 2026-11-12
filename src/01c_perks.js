/* ================= герой: атрибуты, перки, очки =================
   Общий для клиента и сервера: без DOM. Пять атрибутов (ATTRS в 01_core.js), у каждого четыре перка с порогами.
   Перк берётся за очко перков, когда атрибут достиг порога. Очки: за уровень +2 очка атрибутов и +1 очко перков.
   Герой хранит: H.str/vit/agi/int/cha, H.pts (очки атрибутов), H.pp (очки перков), H.perks (список id изученных).
   Старые герои (Лидерство, без Интеллекта и перков) чинятся лениво через heroFix(H), поэтому старые сохранения грузятся без миграции. */

const PTS_LEVEL = 2, PP_LEVEL = 1, PTS_START = 2, PP_START = 1; // очки за уровень и на старте
const PERK_REQ = [3, 5, 8, 11];                                 // пороги атрибута для 1–4 перка (справочно, у каждого перка своё поле req)

/* fx — что перк прибавляет (складывается по всем изученным). Значения в долях (0.12 = +12%), кроме arm, size, morale (единицы). */
const PERKS = [
  // Сила
  { id: 'grip',      a: 'str', req: 3,  n: 'Крепкая хватка',    d: 'Двуручное и древковое оружие бьёт на 12% сильнее.', fx: { heavy: .12 } },
  { id: 'packhorse', a: 'str', req: 5,  n: 'Тяжеловоз',         d: 'Обоз вмещает на 25% больше груза.', fx: { cargo: .25 } },
  { id: 'breaker',   a: 'str', req: 8,  n: 'Сокрушитель',       d: 'Удары ближнего боя игнорируют ещё 8% брони.', fx: { mpierce: .08 } },
  { id: 'butcher',   a: 'str', req: 11, n: 'Мясник',            d: 'За каждого сражённого врага герой восстанавливает 4% здоровья.', fx: { killHeal: .04 } },
  // Стойкость
  { id: 'tough',     a: 'vit', req: 3,  n: 'Закалка',           d: 'Здоровье героя выше на 12%.', fx: { hp: .12 } },
  { id: 'hide',      a: 'vit', req: 5,  n: 'Толстая кожа',      d: 'Броня героя выше на 5.', fx: { arm: 5 } },
  { id: 'recover',   a: 'vit', req: 8,  n: 'Живучий',           d: 'Герой лечится на карте на 60% быстрее.', fx: { heal: .6 } },
  { id: 'lastStand', a: 'vit', req: 11, n: 'Последний рубеж',   d: 'Раз за бой, когда здоровье падает до нуля, герой встаёт с 30% здоровья.', fx: { lastStand: .3 } },
  // Ловкость
  { id: 'quick',     a: 'agi', req: 3,  n: 'Быстрые руки',      d: 'Удары и выстрелы на 8% быстрее.', fx: { cd: .08 } },
  { id: 'eagle',     a: 'agi', req: 5,  n: 'Меткий глаз',       d: 'Разброс стрел и болтов меньше на 35%, дальность больше на 10%.', fx: { acc: .35, range: .1 } },
  { id: 'light',     a: 'agi', req: 8,  n: 'Лёгкая поступь',    d: 'Отряд идёт по карте на 8% быстрее, погоню легче оставить позади, бег в бою быстрее на 5%.', fx: { map: .08, flee: .1, run: .05 } },
  { id: 'master',    a: 'agi', req: 11, n: 'Мастер оружия',     d: 'Любое оружие бьёт на 12% сильнее.', fx: { dmg: .12 } },
  // Интеллект
  { id: 'surgery',   a: 'int', req: 3,  n: 'Хирургия',          d: 'Среди павших бойцов больше остаются ранеными и возвращаются в строй (+20% к доле раненых).', fx: { surv: .2 } },
  { id: 'learner',   a: 'int', req: 5,  n: 'Сообразительный',   d: 'Опыта за бои на 15% больше.', fx: { xp: .15 } },
  { id: 'merchant',  a: 'int', req: 8,  n: 'Торговец',          d: 'Покупаешь на 5% дешевле, продаёшь на 5% дороже.', fx: { buy: .05, sell: .05 } },
  { id: 'tactician', a: 'int', req: 11, n: 'Тактик',            d: 'Бойцы отряда бьют на 8% сильнее и держатся твёрже (мораль +6).', fx: { ally: .08, morale: 6 } },
  // Харизма
  { id: 'inspire',   a: 'cha', req: 3,  n: 'Вдохновляющий',     d: 'Мораль бойцов отряда выше на 12.', fx: { morale: 12 } },
  { id: 'recruiter', a: 'cha', req: 5,  n: 'Вербовщик',         d: 'Найм и улучшение войск дешевле на 15%.', fx: { hire: .15 } },
  { id: 'commander', a: 'cha', req: 8,  n: 'Командир',          d: 'Отряд больше на 10 бойцов, жалованье ниже на 10%.', fx: { size: 10, wage: .1 } },
  { id: 'famous',    a: 'cha', req: 11, n: 'Знаменитый наёмник', d: 'Награды за задания и добыча после боя больше на 20%.', fx: { quest: .2, loot: .2 } }
];
const PERK = {}; for (const p of PERKS) PERK[p.id] = p;
const FX_ZERO = Object.freeze({ heavy: 0, cargo: 0, mpierce: 0, killHeal: 0, hp: 0, arm: 0, heal: 0, lastStand: 0, cd: 0, acc: 0, range: 0, map: 0, flee: 0, run: 0, dmg: 0, surv: 0, xp: 0, buy: 0, sell: 0, ally: 0, morale: 0, hire: 0, size: 0, wage: 0, quest: 0, loot: 0 });

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

/* Сумма эффектов изученных перков. Кэш в WeakMap, а не в самом герое, чтобы в сохранение и в сеть не попадало лишнего. */
const FXC = new WeakMap();
function perkFx(H) {
  const ids = H && H.perks; if (!ids || !ids.length) return FX_ZERO;
  const key = ids.join(','), c = FXC.get(H); if (c && c.k === key) return c.f;
  const f = Object.assign({}, FX_ZERO); for (const id of ids) { const p = PERK[id]; if (p) for (const k in p.fx) f[k] += p.fx[k]; }
  FXC.set(H, { k: key, f }); return f;
}
const hasPerk = (H, id) => !!(H && H.perks && H.perks.includes(id));

/* Можно ли взять перк: '' если да, иначе причина (для кнопок и подсказок) */
function perkWhy(H, id) {
  heroFix(H); const p = PERK[id]; if (!p) return 'Нет такого перка.';
  if (H.perks.includes(id)) return 'Уже изучено.';
  if (H[p.a] < p.req) return 'Нужно: ' + ATTRS[p.a][0] + ' ' + p.req + '.';
  if (H.pp < 1) return 'Нет очков перков.';
  return '';
}

/* Цены найма и улучшения с учётом перка «Вербовщик» */
const hireCost = (P, type) => Math.max(1, Math.round(TROOPS[type].cost * (1 - perkFx(P.hero).hire)));
const upgCost = (P, type) => Math.max(1, Math.round(TROOPS[type].upCost * (1 - perkFx(P.hero).hire)));
