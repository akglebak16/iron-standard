'use strict';
/* ================= утилиты ================= */
const SERVER = typeof __SRV !== 'undefined';
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
  bandit: { name: 'Разбойники', gen: 'разбойников', c1: '#3b3a36', c2: '#9a2f24', emblem: 'skull', title: 'атаман', biome: 'grass',
    names: ['Гнус', 'Рябой', 'Хорёк', 'Кабан', 'Щербатый', 'Ворон', 'Клык', 'Лис', 'Шило', 'Горбун', 'Жбан', 'Косарь', 'Мясник', 'Тихон'],
    nicks: ['', '', '', 'Живодёр', 'Висельник', 'Душегуб', 'Беглый'] },
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
  arc: [0, { hp: 36, arm: 4, dmg: 10, mdmg: 7, cd: 2.6, spd: 62, range: 330, acc: .065 }, { hp: 42, arm: 8, dmg: 13, mdmg: 8, cd: 2.4, spd: 62, range: 360, acc: .05 }, { hp: 52, arm: 18, dmg: 18, mdmg: 11, cd: 2.1, spd: 62, range: 400, acc: .036 }],
  cav: [0, 0, { hp: 74, arm: 20, dmg: 16, cd: 1.3, spd: 150, block: .3 }, { hp: 100, arm: 44, dmg: 22, cd: 1.2, spd: 142, block: .42 }],
  har: [0, 0, { hp: 58, arm: 10, dmg: 11, mdmg: 9, cd: 2.5, spd: 152, range: 290, acc: .08 }, { hp: 66, arm: 14, dmg: 14, mdmg: 11, cd: 2.2, spd: 156, range: 310, acc: .065 }]
};
const TROOPS = {};
function T(id, name, fac, tier, cls, look, up, mod) {
  const t = Object.assign({ id, name, fac, tier, cls, look, up: up || [], reach: 0, block: 0, range: 0 }, BASE[cls][tier], mod || {});
  t.mounted = cls === 'cav' || cls === 'har';
  t.grp = (cls === 'inf' || cls === 'spr') ? 0 : cls === 'arc' ? 1 : 2;
  t.cost = [0, 25, 60, 130][tier] + (t.mounted ? 50 : 0);
  t.upCost = [0, 35, 85, 0][tier];
  t.wage = [0, 2, 4, 7][tier] + (t.mounted ? 3 : 0);
  TROOPS[id] = t;
}
// Нордмарк — тяжёлая пехота
T('n1', 'Бонд', 'nord', 1, 'inf', { helm: 'none', armor: 'tunic', weapon: 'axe', shield: 'round', beard: .8 }, ['n2', 'n2s', 'n2a'], { hp: 50 });
T('n2', 'Секироносец', 'nord', 2, 'inf', { helm: 'nasal', armor: 'fur', weapon: 'axe', shield: 'round', beard: .9 }, ['n3'], { hp: 68, dmg: 17 });
T('n3', 'Хускарл', 'nord', 3, 'inf', { helm: 'spectacle', armor: 'mailfur', weapon: 'sword', shield: 'round', beard: 1 }, [], { hp: 94, dmg: 23 });
T('n2s', 'Копьеносец', 'nord', 2, 'spr', { helm: 'cap', armor: 'padded', weapon: 'spear', shield: 'round', beard: .8 }, ['n3c']);
T('n2a', 'Охотник', 'nord', 2, 'arc', { helm: 'hood', armor: 'fur', weapon: 'bow', beard: .7 }, ['n3a']);
T('n3a', 'Следопыт', 'nord', 3, 'arc', { helm: 'nasal', armor: 'fur', weapon: 'bow', beard: .9 }, []);
T('n3c', 'Дружинник', 'nord', 3, 'cav', { helm: 'spectacle', armor: 'mail', weapon: 'spear', shield: 'round', horse: 'bay', beard: .9 }, [], { spd: 132, hp: 104 });
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
// Разбойники
T('b1', 'Грабитель', 'bandit', 1, 'inf', { helm: 'hood', armor: 'tunic', weapon: 'club', beard: .6 }, [], { block: .08, hp: 40 });
T('b2', 'Разбойник', 'bandit', 2, 'inf', { helm: 'cap', armor: 'padded', weapon: 'axe', shield: 'round', beard: .7 }, [], { arm: 16 });
T('b1a', 'Браконьер', 'bandit', 1, 'arc', { helm: 'hood', armor: 'tunic', weapon: 'bow', beard: .5 }, []);
T('b3', 'Головорез', 'bandit', 3, 'inf', { helm: 'nasal', armor: 'mail', weapon: 'mace', shield: 'round', beard: .8 }, [], { arm: 34, hp: 78 });
T('b2c', 'Конный налётчик', 'bandit', 2, 'cav', { helm: 'hood', armor: 'padded', weapon: 'sword', horse: 'bay', beard: .6 }, [], { block: .12 });

const GEAR = {
  weapon: [{ n: 'Старый меч', v: 20, p: 0 }, { n: 'Рыцарский меч', v: 28, p: 380 }, { n: 'Клинок мастера', v: 38, p: 1150 }, { n: 'Булатный клинок', v: 50, p: 2600 }],
  armor: [{ n: 'Стёганка', v: 12, p: 0 }, { n: 'Кольчуга', v: 30, p: 340 }, { n: 'Чешуйчатый доспех', v: 46, p: 900 }, { n: 'Латы', v: 64, p: 2100 }],
  shield: [{ n: 'Дощатый щит', v: .5, p: 0 }, { n: 'Окованный щит', v: .68, p: 240 }, { n: 'Гербовый щит', v: .84, p: 700 }],
  horse: [{ n: 'Пеший', v: 0, p: 0 }, { n: 'Походный конь', v: 150, p: 520 }, { n: 'Боевой скакун', v: 172, p: 1500 }]
};
const GEAR_LABEL = { weapon: 'Оружие', armor: 'Доспех', shield: 'Щит', horse: 'Конь' };
const GEAR_UNIT = { weapon: 'урон', armor: 'броня', shield: 'блок', horse: 'скорость' };
const ATTRS = { str: ['Сила', '+3 к урону'], vit: ['Стойкость', '+14 к здоровью'], agi: ['Ловкость', 'быстрее удар и шаг'], lead: ['Лидерство', '+5 к размеру отряда, выше мораль'] };
function unitName(fac) { const f = FACTIONS[fac] || FACTIONS.nord; const n = pick(f.names || FACTIONS.nord.names); const k = Math.random() < .45 ? pick(f.nicks || ['']) : ''; return k ? n + ' ' + k : n; }
function troopCount(list) { let n = 0; for (const s of list) n += s.n; return n; }
function strength(list) { let s = 0; for (const t of list) { const d = TROOPS[t.type]; s += t.n * (d.tier * d.tier * .6 + .8) * (d.mounted ? 1.35 : 1); } return s; }
function genTroops(fac, n, quality) { // quality 0..1
  const ids = Object.keys(TROOPS).filter(k => TROOPS[k].fac === fac), out = {};
  for (let i = 0; i < n; i++) {
    const r = Math.random() + (quality - .5) * .7; const tier = r < .38 ? 1 : r < .78 ? 2 : 3;
    let c = ids.filter(k => TROOPS[k].tier === tier); if (!c.length) c = ids;
    let id = pick(c); if (TROOPS[id].mounted && fac !== 'khan' && Math.random() < .55) id = pick(c);
    out[id] = (out[id] || 0) + 1;
  }
  return Object.keys(out).map(k => ({ type: k, n: out[k] }));
}
