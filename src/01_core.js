'use strict';
/* ================= утилиты ================= */
const SERVER = typeof __SRV !== 'undefined';
const NET = { on: false, ws: null, avail: false, q: [] };
/* масштаб массовости боёв: в одиночной игре армии, гарнизоны и лимит отряда вдвое больше; сервер и сетевая игра живут по старым числам */
const MASS = 2, MK = () => SERVER || NET.on ? 1 : MASS;
const TAU = Math.PI * 2;
const rnd = (a = 1, b) => b === undefined ? Math.random() * a : a + Math.random() * (b - a);
const rint = (a, b) => Math.floor(rnd(a, b + 1));
const pick = a => a[Math.floor(Math.random() * a.length)];
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const lerp = (a, b, t) => a + (b - a) * t;
function mulberry(seed) { let a = seed >>> 0; return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function hashStr(s) { let h = 2166136261; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }
function angDiff(a, b) { let d = (a - b) % TAU; if (d > Math.PI) d -= TAU; if (d < -Math.PI) d += TAU; return d; }
function shade(hex, amt) {
  const n = parseInt(hex.slice(1), 16); let r = n >> 16, g = n >> 8 & 255, b = n & 255;
  if (amt < 0) { r *= 1 + amt; g *= 1 + amt; b *= 1 + amt; } else { r += (255 - r) * amt; g += (255 - g) * amt; b += (255 - b) * amt; }
  return 'rgb(' + (r | 0) + ',' + (g | 0) + ',' + (b | 0) + ')';
}
function mkCanvas(w, h) { const c = document.createElement('canvas'); c.width = Math.ceil(w); c.height = Math.ceil(h); return c; }
function makeNoise(seed) {
  const r = mulberry(seed), p = new Float32Array(4096);
  for (let i = 0; i < 4096; i++) p[i] = r();
  const at = (x, y) => p[((x & 63) + (y & 63) * 64)];
  const n1 = (x, y) => { const xi = Math.floor(x), yi = Math.floor(y); let fx = x - xi, fy = y - yi; fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy); return lerp(lerp(at(xi, yi), at(xi + 1, yi), fx), lerp(at(xi, yi + 1), at(xi + 1, yi + 1), fx), fy); };
  return (x, y) => (n1(x, y) * 0.55 + n1(x * 2.1 + 7, y * 2.1 + 3) * 0.3 + n1(x * 4.3 + 13, y * 4.3 + 9) * 0.15);
}
const $ = s => document.querySelector(s);
const fmt = n => String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
function plural(n, a, b, c) { const m = n % 100, k = n % 10; if (m > 10 && m < 20) return c; if (k === 1) return a; if (k > 1 && k < 5) return b; return c; }

/* ================= данные ================= */
const FACTIONS = {
  nord: { name: 'Нордмарк', gen: 'Нордмарка', c1: '#2f5a85', c2: '#dfe6ea', emblem: 'star', title: 'ярл', biome: 'snow',
    names: ['Эйнар', 'Бьорн', 'Ульф', 'Харальд', 'Сигурд', 'Торвальд', 'Гуннар', 'Хальфдан', 'Ивар', 'Олаф', 'Стейн', 'Кнуд', 'Асгейр', 'Фроди'],
    nicks: ['Бык', 'Седой', 'Кривой', 'Рыжий', 'Молчун', 'Долгий', 'Чёрный', 'Беззубый', 'Волчья Пасть', 'Каменный'] },
  emp: { name: 'Аурелийская империя', gen: 'Империи', c1: '#7d1f28', c2: '#d8a838', emblem: 'sun', title: 'легат', biome: 'grass',
    names: ['Луций', 'Марк', 'Кассий', 'Деций', 'Авл', 'Север', 'Валерий', 'Квинт', 'Флавий', 'Октав', 'Руф', 'Гордиан', 'Юст', 'Максим'],
    nicks: ['Старший', 'Меченый', 'Хромой', 'из Вентума', 'Железный', 'Счастливчик', 'Суровый', 'Младший'] },
  khan: { name: 'Кеширское ханство', gen: 'Ханства', c1: '#1e6a5e', c2: '#e6c868', emblem: 'moon', title: 'нойон', biome: 'steppe',
    names: ['Темир', 'Батур', 'Арслан', 'Тогрул', 'Алтан', 'Есен', 'Кайрат', 'Бори', 'Даян', 'Сартак', 'Очир', 'Мерген', 'Тархан', 'Булат'],
    nicks: ['Сокол', 'Быстрый', 'Косой', 'Степной Волк', 'Меткий', 'Молодой', 'Одноглазый', 'Буран'] },
  kin: { name: 'Королевство Галлия', gen: 'Королевства', c1: '#5a3a92', c2: '#f0e2a6', emblem: 'lily', title: 'граф', biome: 'grass',
    names: ['Гийом', 'Анри', 'Рено', 'Тибо', 'Ожье', 'Бертран', 'Гуго', 'Роже', 'Ги', 'Жеффруа', 'Ансельм', 'Эд', 'Рауль', 'Фульк'],
    nicks: ['Храбрый', 'Рыжий', 'Толстый', 'Благочестивый', 'Лысый', 'Добрый', 'Строитель', 'Сильный'] },
  emi: { name: 'Эмират Хайрат', gen: 'Эмирата', c1: '#c4571f', c2: '#f4e8c4', emblem: 'octa', title: 'эмир', biome: 'arid',
    names: ['Рашид', 'Хасан', 'Идрис', 'Тарик', 'Мусса', 'Юсуф', 'Ибрагим', 'Омар', 'Салим', 'Фарид', 'Захир', 'Малик', 'Джафар', 'Камиль'],
    nicks: ['Лев', 'Мудрый', 'Одноглазый', 'Золотой', 'Быстрый', 'Меченый', 'Щедрый', 'Пустынный'] },
  dom: { name: 'Мядельский доминион', gen: 'Доминиона', c1: '#b58a28', c2: '#2d2a22', emblem: 'oak', title: 'князь', biome: 'grass',
    names: ['Витовт', 'Гедымин', 'Миндовг', 'Ольгерд', 'Кейстут', 'Довмонт', 'Скирмунт', 'Радзивил', 'Збигнев', 'Ян', 'Юрий', 'Лев', 'Збышек', 'Казимир'],
    nicks: ['Лесной', 'Седой', 'Угрюмый', 'Строгий', 'Меткий', 'Рогатый', 'Крепкий', 'Болотный'] },
  pact: { name: 'Варшавско-Познаньский пакт', gen: 'Пакта', c1: '#dcd5c2', c2: '#b3262e', emblem: 'crown', title: 'воевода', biome: 'grass',
    names: ['Болеслав', 'Казимир', 'Мешко', 'Владислав', 'Зигмунт', 'Ежи', 'Стефан', 'Хенрик', 'Конрад', 'Лешек', 'Фридрих', 'Отто', 'Бернхард', 'Вацлав'],
    nicks: ['Храбрый', 'Кривоустый', 'Щедрый', 'Мудрый', 'Суровый', 'Белый', 'Старый', 'Рыжий'] },
  bandit: { name: 'Разбойники', gen: 'разбойников', c1: '#3b3a36', c2: '#9a2f24', emblem: 'skull', title: 'атаман', biome: 'grass',
    names: ['Гнус', 'Рябой', 'Хорёк', 'Кабан', 'Щербатый', 'Ворон', 'Клык', 'Лис', 'Шило', 'Горбун', 'Жбан', 'Косарь', 'Мясник', 'Тихон'],
    nicks: ['', '', '', 'Живодёр', 'Висельник', 'Душегуб', 'Беглый'] },
  undead: { name: 'Нежить', gen: 'нежити', c1: '#3f4636', c2: '#a9b98e', emblem: 'skull', title: 'некромант', biome: 'grass',
    names: ['Мордрек', 'Ваальтор', 'Зеферин', 'Карх', 'Ильвен', 'Горр', 'Мальтус', 'Сирах', 'Ортанд', 'Велиал'],
    nicks: ['Бледный', 'Гнилой', 'Безглазый', 'Чёрный', 'Древний', 'Шепчущий', 'Костяной'] },
  player: { name: 'Твой отряд', gen: 'твоего отряда', c1: '#c08a2e', c2: '#241a10', emblem: 'chevron', title: 'капитан', biome: 'grass' }
};
const BANNERS = [
  { n: 'Янтарь', c1: '#c08a2e', c2: '#241a10' }, { n: 'Изумруд', c1: '#3e7a3a', c2: '#ece6d2' },
  { n: 'Индиго', c1: '#3b3f94', c2: '#e3c15a' }, { n: 'Уголь', c1: '#2b2b31', c2: '#d8d2c4' },
  { n: 'Кость', c1: '#d6cfbc', c2: '#6a1f1f' }, { n: 'Пурпур', c1: '#6d2c74', c2: '#e6d08a' }
];
const BASE = {
  inf: [0, { hp: 46, arm: 8, dmg: 11, cd: 1.35, spd: 60, block: .22 }, { hp: 62, arm: 24, dmg: 15, cd: 1.2, spd: 58, block: .4 }, { hp: 84, arm: 42, dmg: 20, cd: 1.1, spd: 56, block: .5 }],
  spr: [0, 0, { hp: 56, arm: 18, dmg: 14, cd: 1.3, spd: 58, block: .32, reach: 14, anticav: 1 }, { hp: 74, arm: 34, dmg: 19, cd: 1.2, spd: 57, block: .3, reach: 16, anticav: 1 }],
  arc: [0, { hp: 36, arm: 4, dmg: 10, mdmg: 7, cd: 2.6, spd: 62, range: 660, acc: .065 }, { hp: 42, arm: 8, dmg: 13, mdmg: 8, cd: 2.4, spd: 62, range: 720, acc: .05 }, { hp: 52, arm: 18, dmg: 18, mdmg: 11, cd: 2.1, spd: 62, range: 800, acc: .036 }],
  cav: [0, 0, { hp: 74, arm: 20, dmg: 16, cd: 1.3, spd: 150, block: .3 }, { hp: 100, arm: 44, dmg: 22, cd: 1.2, spd: 142, block: .42 }],
  har: [0, 0, { hp: 58, arm: 10, dmg: 22, mdmg: 9, cd: 2.2, spd: 152, range: 580, acc: .08 }, { hp: 66, arm: 14, dmg: 28, mdmg: 11, cd: 1.95, spd: 156, range: 620, acc: .065 }]
};
const TROOPS = {};
/* Бой: дальность стрелков ×2 от прежней, разброс ×ACC_K, щит прибавляет шанс заблокировать снаряд (см. blocked в 03_battle.js) */
const ACC_K = 1.8, SHOT_V = 620, THROW_V = 460;
/* Подстройка живучести фракций после патча дальнобоя: множитель здоровья всех бойцов фракции (по боям 30/50/80 человек; пакт — самый слабый в среднем) */
const FAC_HP = { nord: 1.15, khan: .86 };
function shieldArrow(l) { return l === 'kite' ? .18 : l === 'round' ? .12 : l === 'small' ? .07 : 0; }
function T(id, name, fac, tier, cls, look, up, mod) {
  const t = Object.assign({ id, name, fac, tier, cls, look, up: up || [], reach: 0, block: 0, range: 0 }, BASE[cls][tier], mod || {});
  t.mounted = cls === 'cav' || cls === 'har'; if (FAC_HP[fac]) t.hp = Math.round(t.hp * FAC_HP[fac]); t.shb = shieldArrow(look.shield); t.acc = t.acc ? t.acc * (cls === 'har' ? 1.3 : ACC_K) : t.acc;
  t.grp = (cls === 'inf' || cls === 'spr') ? 0 : cls === 'arc' ? 1 : 2;
  t.cost = [0, 25, 60, 130][tier] + (t.mounted ? 50 : 0);
  t.upCost = [0, 35, 85, 0][tier];
  t.wage = [0, 2, 4, 7][tier] + (t.mounted ? 3 : 0);
  TROOPS[id] = t;
}
// Нордмарк — тяжёлая пехота
T('n1', 'Бонд', 'nord', 1, 'inf', { helm: 'none', armor: 'tunic', weapon: 'axe', shield: 'round', beard: .8 }, ['n2', 'n2s', 'n2a'], { hp: 50 });
T('n2', 'Секироносец', 'nord', 2, 'inf', { helm: 'nasal', armor: 'fur', weapon: 'axe', shield: 'round', beard: .9 }, ['n3'], { hp: 68, dmg: 17, arm: 18 });
T('n3', 'Хускарл', 'nord', 3, 'inf', { helm: 'spectacle', armor: 'mailfur', weapon: 'sword', shield: 'round', beard: 1 }, [], { hp: 94, dmg: 23, arm: 36 });
T('n2s', 'Копьеносец', 'nord', 2, 'spr', { helm: 'cap', armor: 'padded', weapon: 'spear', shield: 'round', beard: .8 }, ['n3c'], { arm: 12 });
T('n2a', 'Охотник', 'nord', 2, 'arc', { helm: 'hood', armor: 'fur', weapon: 'bow', beard: .7 }, ['n3a']);
T('n3a', 'Следопыт', 'nord', 3, 'arc', { helm: 'nasal', armor: 'fur', weapon: 'bow', beard: .9 }, [], { arm: 14 });
T('n3c', 'Дружинник', 'nord', 3, 'cav', { helm: 'spectacle', armor: 'mail', weapon: 'spear', shield: 'round', horse: 'bay', beard: .9 }, [], { spd: 132, hp: 104, arm: 32 });
// Империя — броня, арбалеты, катафракты
T('e1', 'Рекрут', 'emp', 1, 'inf', { helm: 'cap', armor: 'tunic', weapon: 'sword', shield: 'kite', beard: .2 }, ['e2', 'e2s', 'e2a']);
T('e2', 'Легионер', 'emp', 2, 'inf', { helm: 'flat', armor: 'mailtab', weapon: 'sword', shield: 'kite', beard: .3 }, ['e3', 'e3c'], { arm: 30 });
T('e3', 'Триарий', 'emp', 3, 'inf', { helm: 'crest', armor: 'scale', weapon: 'sword', shield: 'kite', beard: .3 }, [], { arm: 50 });
T('e2s', 'Пикинёр', 'emp', 2, 'spr', { helm: 'kettle', armor: 'padded', weapon: 'spear', shield: 'kite', beard: .3 }, ['e3s']);
T('e3s', 'Алебардист', 'emp', 3, 'spr', { helm: 'kettle', armor: 'mailtab', weapon: 'halberd', beard: .4 }, [], { dmg: 24, block: .12 });
T('e2a', 'Арбалетчик', 'emp', 2, 'arc', { helm: 'kettle', armor: 'padded', weapon: 'xbow', beard: .3 }, ['e3a'], { dmg: 19, cd: 3.4, pierce: .4 });
T('e3a', 'Стрелок-ветеран', 'emp', 3, 'arc', { helm: 'flat', armor: 'mailtab', weapon: 'xbow', beard: .4 }, [], { dmg: 25, cd: 3.1, pierce: .4, arm: 26 });
T('e3c', 'Катафракт', 'emp', 3, 'cav', { helm: 'mask', armor: 'goldscale', weapon: 'lance', shield: 'kite', horse: 'barded' }, [], { arm: 56, spd: 128, hp: 106 });
// Ханство — конница и конные лучники
T('k1', 'Кочевник', 'khan', 1, 'inf', { helm: 'furcap', armor: 'tunic', weapon: 'sabre', shield: 'small', beard: .5, stache: 1 }, ['k2', 'k2a', 'k2c'], { spd: 64 });
T('k2', 'Степной копейщик', 'khan', 2, 'spr', { helm: 'pointed', armor: 'lamellar', weapon: 'spear', shield: 'small', beard: .4, stache: 1 }, ['k3c']);
T('k2a', 'Степной стрелок', 'khan', 2, 'arc', { helm: 'furcap', armor: 'tunic', weapon: 'bow', beard: .4, stache: 1 }, ['k3h'], { acc: .042 });
T('k2c', 'Всадник', 'khan', 2, 'cav', { helm: 'furcap', armor: 'lamellar', weapon: 'sabre', shield: 'small', horse: 'dun', stache: 1 }, ['k3c'], { spd: 158 });
T('k3h', 'Конный лучник', 'khan', 3, 'har', { helm: 'pointed', armor: 'lamellar', weapon: 'bow', horse: 'dun', stache: 1 }, []);
T('k3c', 'Нукер', 'khan', 3, 'cav', { helm: 'pointed', armor: 'goldlam', weapon: 'lance', shield: 'small', horse: 'black', stache: 1 }, [], { spd: 154 });
// Королевство Галлия — рыцарская конница, сержанты и длинные луки
T('f1', 'Ополченец', 'kin', 1, 'inf', { helm: 'cap', armor: 'padded', weapon: 'sword', shield: 'round', beard: .3 }, ['f2', 'f2s', 'f2a', 'f2c']);
T('f2', 'Сержант', 'kin', 2, 'inf', { helm: 'kettle', armor: 'mail', weapon: 'sword', shield: 'kite', beard: .3 }, ['f3'], { arm: 30, hp: 66 });
T('f3', 'Латник', 'kin', 3, 'inf', { helm: 'great', armor: 'plate', weapon: 'sword', shield: 'kite', beard: .2 }, [], { arm: 55, hp: 92, dmg: 23 });
T('f2s', 'Копейщик', 'kin', 2, 'spr', { helm: 'kettle', armor: 'padded', weapon: 'spear', shield: 'round', beard: .4 }, ['f3s']);
T('f3s', 'Протазанщик', 'kin', 3, 'spr', { helm: 'coif', armor: 'mailtab', weapon: 'halberd', beard: .4 }, [], { dmg: 24, block: .12 });
T('f2a', 'Лучник', 'kin', 2, 'arc', { helm: 'cap', armor: 'padded', weapon: 'bow', beard: .5 }, ['f3a'], { range: 760 });
T('f3a', 'Йомен', 'kin', 3, 'arc', { helm: 'coif', armor: 'mail', weapon: 'bow', beard: .5 }, [], { dmg: 20, range: 840, arm: 22 });
T('f2c', 'Конный сержант', 'kin', 2, 'cav', { helm: 'kettle', armor: 'mail', weapon: 'sword', shield: 'kite', horse: 'chestnut', beard: .3 }, ['f3c'], { arm: 29, spd: 140, hp: 76 });
T('f3c', 'Рыцарь', 'kin', 3, 'cav', { helm: 'great', armor: 'plate', weapon: 'lance', shield: 'kite', horse: 'grey' }, [], { arm: 58, spd: 128, hp: 114, dmg: 25 });
// Эмират Хайрат — лёгкая конница, лучники и мамлюки
T('m1', 'Воин пустыни', 'emi', 1, 'inf', { helm: 'turban', armor: 'tunic', weapon: 'sabre', shield: 'small', beard: .8 }, ['m2', 'm2a', 'm2c'], { spd: 63 });
T('m2', 'Гулям', 'emi', 2, 'inf', { helm: 'turban', armor: 'padded', weapon: 'sabre', shield: 'round', beard: .8 }, ['m3'], { arm: 20 });
T('m3', 'Страж эмира', 'emi', 3, 'inf', { helm: 'turbanm', armor: 'mail', weapon: 'sabre', shield: 'round', beard: .9 }, [], { arm: 40, dmg: 22 });
T('m2s', 'Копейщик-бербер', 'emi', 2, 'spr', { helm: 'turban', armor: 'padded', weapon: 'spear', shield: 'small', beard: .8 }, ['m3c']);
T('m2a', 'Лучник пустыни', 'emi', 2, 'arc', { helm: 'turban', armor: 'tunic', weapon: 'bow', beard: .7 }, ['m3h'], { acc: .04 });
T('m2c', 'Лёгкий всадник', 'emi', 2, 'cav', { helm: 'turban', armor: 'padded', weapon: 'sabre', shield: 'small', horse: 'dun', beard: .7 }, ['m3c', 'm3h'], { spd: 158, arm: 16 });
T('m3h', 'Конный лучник', 'emi', 3, 'har', { helm: 'turbanm', armor: 'lamellar', weapon: 'bow', horse: 'dun', beard: .7 }, []);
T('m3c', 'Мамлюк', 'emi', 3, 'cav', { helm: 'turbanm', armor: 'goldlam', weapon: 'lance', shield: 'small', horse: 'black', beard: .6 }, [], { spd: 150, arm: 40, hp: 96 });
// Мядельский доминион — лесной оплот: стойкая пехота, арбалеты и лёгкая дружинная конница
T('d1', 'Ополченец', 'dom', 1, 'inf', { helm: 'cap', armor: 'padded', weapon: 'axe', shield: 'round', beard: .7 }, ['d2', 'd2s', 'd2x', 'd2c']);
T('d2', 'Щитник', 'dom', 2, 'inf', { helm: 'kettle', armor: 'mail', weapon: 'sword', shield: 'kite', beard: .6 }, ['d3'], { arm: 28, hp: 68 });
T('d3', 'Страж доминиона', 'dom', 3, 'inf', { helm: 'great', armor: 'mailtab', weapon: 'sword', shield: 'kite', beard: .5 }, [], { arm: 48, hp: 96, dmg: 22 });
T('d2s', 'Рогатинник', 'dom', 2, 'spr', { helm: 'nasal', armor: 'padded', weapon: 'spear', shield: 'round', beard: .7 }, ['d3s']);
T('d3s', 'Алебардист', 'dom', 3, 'spr', { helm: 'kettle', armor: 'mail', weapon: 'halberd', beard: .6 }, [], { dmg: 24, block: .12 });
T('d2x', 'Арбалетчик', 'dom', 2, 'arc', { helm: 'nasal', armor: 'padded', weapon: 'xbow', beard: .6 }, ['d3x'], { dmg: 19, cd: 3.4, pierce: .4 });
T('d3x', 'Лесной стрелок', 'dom', 3, 'arc', { helm: 'kettle', armor: 'mail', weapon: 'xbow', beard: .6 }, [], { dmg: 25, cd: 3.1, pierce: .4, arm: 24 });
T('d2c', 'Дружинник', 'dom', 2, 'cav', { helm: 'nasal', armor: 'mail', weapon: 'spear', shield: 'round', horse: 'bay', beard: .6 }, ['d3c'], { arm: 26, spd: 140, hp: 76 });
T('d3c', 'Боярин', 'dom', 3, 'cav', { helm: 'great', armor: 'mailtab', weapon: 'lance', shield: 'kite', horse: 'chestnut', beard: .5 }, [], { arm: 50, spd: 130, hp: 104, dmg: 24 });
// Варшавско-Познаньский пакт — тяжёлая конница, ландскнехты и лучники
T('p1', 'Ополченец', 'pact', 1, 'inf', { helm: 'cap', armor: 'padded', weapon: 'sword', shield: 'round', beard: .5 }, ['p2', 'p2s', 'p2a', 'p2c']);
T('p2', 'Пехотинец', 'pact', 2, 'inf', { helm: 'kettle', armor: 'mail', weapon: 'sword', shield: 'kite', beard: .4 }, ['p3'], { arm: 29, hp: 67 });
T('p3', 'Кнехт', 'pact', 3, 'inf', { helm: 'flat', armor: 'mailtab', weapon: 'sword', shield: 'kite', beard: .4 }, [], { arm: 50, hp: 94, dmg: 22 });
T('p2s', 'Пикинёр', 'pact', 2, 'spr', { helm: 'kettle', armor: 'padded', weapon: 'spear', shield: 'kite', beard: .5 }, ['p3s']);
T('p3s', 'Ландскнехт', 'pact', 3, 'spr', { helm: 'flat', armor: 'mailtab', weapon: 'halberd', beard: .5 }, [], { dmg: 24, block: .12 });
T('p2a', 'Лучник', 'pact', 2, 'arc', { helm: 'cap', armor: 'padded', weapon: 'bow', beard: .5 }, ['p3a'], { range: 760 });
T('p3a', 'Стрелок', 'pact', 3, 'arc', { helm: 'coif', armor: 'mail', weapon: 'bow', beard: .5 }, [], { dmg: 20, range: 840, arm: 22 });
T('p2c', 'Панцирный всадник', 'pact', 2, 'cav', { helm: 'kettle', armor: 'mail', weapon: 'lance', shield: 'kite', horse: 'bay', beard: .4 }, ['p3c'], { arm: 30, spd: 138, hp: 78 });
T('p3c', 'Гусар', 'pact', 3, 'cav', { helm: 'great', armor: 'plate', weapon: 'lance', shield: 'kite', horse: 'grey' }, [], { arm: 52, spd: 132, hp: 100, dmg: 25 });
// Разбойники
T('b1', 'Грабитель', 'bandit', 1, 'inf', { helm: 'hood', armor: 'tunic', weapon: 'club', beard: .6 }, [], { block: .08, hp: 40 });
T('b2', 'Разбойник', 'bandit', 2, 'inf', { helm: 'cap', armor: 'padded', weapon: 'axe', shield: 'round', beard: .7 }, [], { arm: 16 });
T('b1a', 'Браконьер', 'bandit', 1, 'arc', { helm: 'hood', armor: 'tunic', weapon: 'bow', beard: .5 }, []);
T('b3', 'Головорез', 'bandit', 3, 'inf', { helm: 'nasal', armor: 'mail', weapon: 'mace', shield: 'round', beard: .8 }, [], { arm: 34, hp: 78 });
T('b2c', 'Конный налётчик', 'bandit', 2, 'cav', { helm: 'hood', armor: 'padded', weapon: 'sword', horse: 'bay', beard: .6 }, [], { block: .12 });
// Нежить (кризис, 05f_undead.js): много и слабые. pw — множитель силы в расчётах (strength): мертвец считается почти вдвое слабее живого того же уровня.
// look.undead: 'zombie' — гнилая плоть, 'skel' — скелет (рисунок в 02_art.js). В бою не бегут; скелеты держат стрелы хуже живых, но крошатся от дробящего.
T('z1', 'Мертвец', 'undead', 1, 'inf', { helm: 'none', armor: 'rags', weapon: 'club', undead: 'zombie', beard: .3 }, [], { hp: 34, arm: 2, dmg: 7, cd: 1.7, spd: 42, block: 0, pw: .55 });
T('s1', 'Скелет', 'undead', 1, 'inf', { helm: 'none', armor: 'ribs', weapon: 'sword', shield: 'round', undead: 'skel' }, [], { hp: 24, arm: 6, dmg: 9, cd: 1.45, spd: 54, block: .12, pw: .6 });
T('s1a', 'Скелет-лучник', 'undead', 1, 'arc', { helm: 'hood', armor: 'ribs', weapon: 'bow', undead: 'skel' }, [], { hp: 22, arm: 3, dmg: 8, mdmg: 5, range: 580, acc: .085, pw: .6 });
T('s2', 'Мёртвый воин', 'undead', 2, 'inf', { helm: 'nasal', armor: 'mail', weapon: 'axe', shield: 'round', undead: 'skel' }, [], { hp: 40, arm: 16, dmg: 12, pw: .65 });
T('s2c', 'Мёртвый всадник', 'undead', 2, 'cav', { helm: 'nasal', armor: 'ribs', weapon: 'spear', horse: 'bone', undead: 'skel' }, [], { hp: 52, arm: 10, dmg: 12, spd: 118, pw: .65 });
T('s3', 'Умертвие', 'undead', 3, 'inf', { helm: 'great', armor: 'mail', weapon: 'sword', shield: 'kite', undead: 'skel' }, [], { hp: 68, arm: 30, dmg: 16, pw: .8 });

const GEAR = {
  weapon: [{ n: 'Старый меч', v: 20, p: 0 }, { n: 'Рыцарский меч', v: 28, p: 380 }, { n: 'Клинок мастера', v: 38, p: 1150 }, { n: 'Булатный клинок', v: 50, p: 2600 }],
  armor: [{ n: 'Стёганка', v: 12, p: 0 }, { n: 'Кольчуга', v: 30, p: 340 }, { n: 'Чешуйчатый доспех', v: 46, p: 900 }, { n: 'Латы', v: 64, p: 2100 }],
  shield: [{ n: 'Дощатый щит', v: .5, p: 0 }, { n: 'Окованный щит', v: .68, p: 240 }, { n: 'Гербовый щит', v: .84, p: 700 }],
  horse: [{ n: 'Пеший', v: 0, p: 0 }, { n: 'Походный конь', v: 150, p: 520 }, { n: 'Боевой скакун', v: 172, p: 1500 }]
};
const GEAR_LABEL = { weapon: 'Оружие', armor: 'Доспех', shield: 'Щит', horse: 'Конь' };
const GEAR_UNIT = { weapon: 'урон', armor: 'броня', shield: 'блок', horse: 'скорость' };
const ATTRS = { str: ['Сила', '+2,5 к урону за очко'], vit: ['Стойкость', '+14 к здоровью за очко'], agi: ['Ловкость', 'Быстрее удар и шаг'], int: ['Интеллект', '+3% к опыту, быстрее лечение'], cha: ['Харизма', '+5 к размеру отряда и +4 к морали за очко'] };
function unitName(fac) { const f = FACTIONS[fac] || FACTIONS.nord; const n = pick(f.names || FACTIONS.nord.names); const k = Math.random() < .45 ? pick(f.nicks || ['']) : ''; return k ? n + ' ' + k : n; }
function troopCount(list) { let n = 0; for (const s of list) n += s.n; return n; }
function strength(list) { let s = 0; for (const t of list) { const d = TROOPS[t.type]; s += t.n * (d.tier * d.tier * .6 + .8) * (d.mounted ? 1.35 : 1) * (d.pw || 1); } return s; }
function genTroops(fac, n, quality, raw) { // quality 0..1; raw — не масштабировать (быстрый бой, демо)
  if (!raw && MK() > 1 && n > 1) n = Math.round(n * (fac === 'bandit' || fac === 'undead' ? 1 + (MK() - 1) * .25 : MK())); // разбойники и нежить растут лишь на четверть, чтобы начало игры оставалось по силам
  const ids = Object.keys(TROOPS).filter(k => TROOPS[k].fac === fac), out = {};
  for (let i = 0; i < n; i++) {
    const r = Math.random() + (quality - .5) * .7; const tier = r < .38 ? 1 : r < .78 ? 2 : 3;
    let c = ids.filter(k => TROOPS[k].tier === tier); if (!c.length) c = ids;
    let id = pick(c); if (TROOPS[id].mounted && fac !== 'khan' && Math.random() < .55) id = pick(c);
    out[id] = (out[id] || 0) + 1;
  }
  return Object.keys(out).map(k => ({ type: k, n: out[k] }));
}
