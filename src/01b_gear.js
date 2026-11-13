/* ================= снаряжение героя: слоты, оружие, типы урона =================
   Общий для клиента и сервера: без DOM. Герой носит предметы в слотах H.eq = { slot: id|null },
   какое оружие в руках — H.sel ('melee' | 'ranged'). Старые герои (индексы armor/weapon/shield/horse)
   переезжают в слоты лениво при первом обращении к heroEq(H), поэтому старые сохранения грузятся без миграции. */

const SLOTS = ['head', 'body', 'hands', 'legs', 'melee', 'ranged', 'shield', 'horse'];
const SLOT_NAME = { head: 'Голова', body: 'Тело', hands: 'Руки', legs: 'Ноги', melee: 'Ближний бой', ranged: 'Дальний бой', shield: 'Щит', horse: 'Конь' };
const WTYPE = { sword: 'Меч', axe: 'Топор', mace: 'Булава', spear: 'Копьё', twohand: 'Двуручное', polearm: 'Древковое', bow: 'Лук', xbow: 'Арбалет', throw: 'Метательное', fist: 'Кулаки' };

/* Тип урона → доля брони, которую удар игнорирует, по классу брони цели: лёгкая (<18), средняя (18–37), тяжёлая (38+) */
const DTYPE = {
  cut:    { n: 'Рубящий', p: [0, .06, 0],     note: '+15% урона по лёгкой броне, тяжёлую почти не берёт' },
  pierce: { n: 'Колющий', p: [.18, .38, .22], note: 'лучше всех пробивает среднюю броню (кольчуги)' },
  blunt:  { n: 'Дробящий', p: [.10, .26, .42], note: 'лучше всех пробивает латы, сильнее отбрасывает' }
};
function armClass(a) { return a < 18 ? 0 : a < 38 ? 1 : 2; }
function dtPierce(dt, arm, extra) { const d = DTYPE[dt]; return clamp((d ? d.p[armClass(arm)] : 0) + (extra || 0), 0, .8); }
function dtMul(dt, arm) { return dt === 'cut' && armClass(arm) === 0 ? 1.15 : 1; }

/* ---------- каталог ---------- */
const EQ = {};
{ // помощники каталога живут в блоке, чтобы не занимать глобальные имена (PA, SP и т. п. уже есть в других файлах)
function E(id, name, slot, tier, price, w, o) { return (EQ[id] = Object.assign({ id, name, slot, tier, price, w }, o || {})); }
const armorPiece = (slot, tier, list) => list.forEach((a, i) => E(a[0], a[1], slot, i, a[2], a[3], { v: a[4], look: a[5], f: a[6] }));
// голова: v — броня, look — рисунок шлема
armorPiece('head', 0, [['head_cap', 'Кожаный подшлемник', 30, 1, 3, 'cap'], ['head_nasal', 'Шлем с наносником', 140, 2.5, 6, 'nasal'], ['head_kettle', 'Шлем-котелок', 380, 3.5, 9, 'kettle'], ['head_great', 'Закрытый шлем', 950, 5, 13, 'great']]);
armorPiece('body', 0, [['body_padded', 'Стёганка', 35, 6, 12, 'padded'], ['body_mail', 'Кольчуга', 340, 14, 30, 'mail'], ['body_scale', 'Чешуйчатый доспех', 900, 18, 46, 'scale'], ['body_plate', 'Латы', 2100, 26, 64, 'plate']]);
armorPiece('hands', 0, [['hands_leather', 'Кожаные перчатки', 25, .5, 2], ['hands_reinf', 'Усиленные рукавицы', 110, 1, 3], ['hands_mail', 'Кольчужные перчатки', 300, 1.5, 5], ['hands_plate', 'Латные перчатки', 720, 2, 7]]);
armorPiece('legs', 0, [['legs_boots', 'Кожаные сапоги', 35, 1.5, 3], ['legs_greaves', 'Сапоги с наколенниками', 150, 2.5, 5], ['legs_mail', 'Кольчужные чулки', 400, 4, 7], ['legs_plate', 'Латные поножи', 900, 6, 10]]);
E('head_turban', 'Тюрбан', 'head', 1, 130, 1, { v: 5, look: 'turban', f: ['emi'] }); E('head_turbanm', 'Шлем-тюрбан с бармицей', 'head', 2, 420, 3, { v: 10, look: 'turbanm', f: ['emi'] });
// щиты: v — шанс блока
E('shield_buckler', 'Баклер', 'shield', 0, 60, 2, { v: .42, look: 'small' });
E('shield_plank', 'Дощатый щит', 'shield', 0, 25, 3, { v: .5, look: 'round' });
E('shield_banded', 'Окованный щит', 'shield', 1, 240, 4, { v: .68, look: 'round' });
E('shield_heraldic', 'Гербовый щит', 'shield', 2, 700, 5.5, { v: .84, look: 'kite' });
// кони: v — скорость
E('horse_riding', 'Походный конь', 'horse', 1, 520, 0, { v: 150, look: 'chestnut' });
E('horse_steppe', 'Степной конь', 'horse', 2, 800, 0, { v: 160, look: 'dun', f: ['khan', 'emi'] });
E('horse_war', 'Боевой скакун', 'horse', 2, 1500, 0, { v: 172, look: 'barded' });

/* Оружие ближнего боя. dmg — урон; spd — множитель времени замаха (больше = медленнее); reach — прибавка к дальности;
   hands — 1 или 2 (с двуручным нельзя щит); arc — ширина удара; cleave — сколько целей заденет; brk — пробивает блок щитом;
   kb — отбрасывание; anticav — бонус против конницы; parry — шанс блока оружием без щита */
const melee = (o, base) => (id, name, tier, price, dmg, w, x) => E(id, name, 'melee', tier, price, w, Object.assign({ dmg, spd: 1, reach: 0, hands: 1, arc: 1, cleave: 3, fall: .7 }, base, o, x));
const SW = melee({}, { wt: 'sword', dt: 'cut', parry: .22, look: 'sword' });
const AX = melee({}, { wt: 'axe', dt: 'cut', spd: 1.1, brk: .4, parry: .12, look: 'axe' });
const MC = melee({}, { wt: 'mace', dt: 'blunt', spd: 1.1, kb: 2.2, parry: .12, look: 'mace' });
const SP = melee({}, { wt: 'spear', dt: 'pierce', spd: 1.1, reach: 20, arc: .7, cleave: 2, anticav: 1, parry: .2, look: 'spear' });
const TH = melee({}, { wt: 'twohand', hands: 2, spd: 1.4, reach: 8, arc: 1.25, cleave: 4, fall: .8, parry: .32 });
const PA = melee({}, { wt: 'polearm', dt: 'pierce', hands: 2, spd: 1.5, reach: 36, arc: .5, cleave: 2, anticav: 1, parry: .3 });
SW('sword_old', 'Старый меч', 0, 40, 20, 3); SW('sword_knight', 'Рыцарский меч', 1, 380, 28, 3.5, { f: ['emp', 'kin'] });
SW('sword_master', 'Клинок мастера', 2, 1150, 38, 3.5); SW('sword_damask', 'Булатный клинок', 3, 2600, 50, 3.5, { f: ['khan', 'emi'] });
SW('sabre', 'Сабля', 1, 330, 27, 3, { spd: .92, look: 'sabre', f: ['khan', 'emi'] });
AX('axe_work', 'Рабочий топор', 0, 90, 24, 3.5, { f: ['nord'] }); AX('axe_battle', 'Боевой топор', 1, 420, 34, 4, { f: ['nord'] }); AX('axe_bearded', 'Бородатая секира', 2, 1250, 44, 4.5, { f: ['nord'] });
MC('club', 'Дубина', 0, 60, 22, 4, { look: 'club' }); MC('mace', 'Булава', 1, 400, 31, 4); MC('mace_flanged', 'Шестопёр', 2, 1100, 41, 4.5);
SP('spear_hunt', 'Охотничье копьё', 0, 80, 24, 3.5); SP('spear_war', 'Боевое копьё', 1, 340, 33, 4, { f: ['emp', 'nord', 'kin'] });
TH('tw_sword', 'Двуручный меч', 2, 1300, 56, 7, { dt: 'cut', look: 'sword' }); TH('tw_claymore', 'Клеймор', 3, 2800, 68, 8, { dt: 'cut', spd: 1.45, reach: 10, look: 'sword' });
TH('tw_axe', 'Двуручная секира', 2, 1500, 62, 8, { dt: 'cut', spd: 1.5, brk: .5, look: 'axe', f: ['nord'] }); TH('tw_hammer', 'Боевой молот', 2, 1400, 60, 9, { dt: 'blunt', spd: 1.5, kb: 2.8, look: 'mace' });
PA('pike', 'Пика', 1, 600, 42, 6, { reach: 40, look: 'spear', f: ['emp', 'kin'] }); PA('halberd', 'Алебарда', 2, 950, 48, 7, { dt: 'cut', spd: 1.35, reach: 28, arc: .7, cleave: 3, look: 'halberd', f: ['emp', 'kin'] });

/* Оружие дальнего боя (боеприпасы бесконечные). cd — перезарядка, сек; range — дальность; acc — разброс; pb — доп. пробитие;
   bs — сколько урона даёт каждая единица силы */
const ranged = (id, name, tier, price, dmg, w, o) => E(id, name, 'ranged', tier, price, w, Object.assign({ rng: 1, dt: 'pierce', dmg, hands: 2, parry: 0, bs: 1.2 }, o));
ranged('bow_hunt', 'Охотничий лук', 0, 120, 17, 1.5, { wt: 'bow', cd: .9, range: 660, acc: .05, look: 'bow', f: ['nord'] });
ranged('bow_long', 'Длинный лук', 1, 560, 26, 2, { wt: 'bow', cd: 1.15, range: 840, acc: .04, look: 'bow', f: ['nord', 'kin'] });
ranged('bow_comp', 'Составной лук', 2, 1300, 33, 2, { wt: 'bow', cd: 1, range: 800, acc: .035, look: 'bow', f: ['khan', 'emi'] });
ranged('xbow_light', 'Лёгкий арбалет', 1, 700, 30, 4, { wt: 'xbow', cd: 2, range: 720, acc: .03, pb: .12, bs: 0, look: 'xbow', f: ['emp', 'kin'] });
ranged('xbow_heavy', 'Тяжёлый арбалет', 2, 1700, 46, 6, { wt: 'xbow', cd: 2.9, range: 760, acc: .025, pb: .22, bs: 0, look: 'xbow', f: ['emp', 'kin'] });
ranged('jav_dart', 'Дротики', 0, 110, 26, 2.5, { wt: 'throw', hands: 1, cd: 1.2, range: 420, acc: .06, bs: 2, look: 'spear' });
ranged('jav_spear', 'Метательные копья', 1, 420, 38, 3.5, { wt: 'throw', hands: 1, cd: 1.4, range: 460, acc: .05, bs: 2, look: 'spear', f: ['nord', 'khan', 'emi'] });
ranged('jav_heavy', 'Тяжёлые метательные копья', 2, 980, 50, 4.5, { wt: 'throw', hands: 1, cd: 1.6, range: 480, acc: .045, pb: .1, bs: 2, look: 'spear', f: ['khan', 'emi'] });
}

/* ---------- герой и его слоты ---------- */
const LEGACY_EQ = { weapon: ['sword_old', 'sword_knight', 'sword_master', 'sword_damask'], armor: ['body_padded', 'body_mail', 'body_scale', 'body_plate'], shield: ['shield_plank', 'shield_banded', 'shield_heraldic'], horse: [null, 'horse_riding', 'horse_war'] };
function syncLegacy(H) { H.horse = H.eq.horse ? (H.eq.horse === 'horse_war' ? 2 : 1) : 0; } // индекс коня нужен карте мира (скорость отряда) и старому коду
function heroEq(H) {
  if (H.eq) return H.eq;
  H.eq = { head: 'head_cap', body: LEGACY_EQ.armor[H.armor] || null, hands: null, legs: null, melee: LEGACY_EQ.weapon[H.weapon] || 'sword_old', ranged: null, shield: LEGACY_EQ.shield[H.shield] || null, horse: LEGACY_EQ.horse[H.horse] || null };
  H.sel = 'melee'; syncLegacy(H); return H.eq;
}
function eqItem(H, slot) { const id = heroEq(H)[slot]; return id && EQ[id] ? EQ[id] : null; }
const FIST = { id: 'fist', name: 'Кулаки', slot: 'melee', wt: 'fist', dt: 'blunt', dmg: 8, spd: .9, reach: -3, hands: 1, arc: 1, cleave: 3, fall: .7, parry: .1, look: null };
function heroWield(H) { const eq = heroEq(H); if (H.sel === 'ranged' && eq.ranged && EQ[eq.ranged]) return EQ[eq.ranged]; return (eq.melee && EQ[eq.melee]) || FIST; }
function heroShield(H) { const s = eqItem(H, 'shield'); return s && heroWield(H).hands < 2 ? s : null; } // двуручное оружие и щит несовместимы
function heroArmor(H) { let a = 0; for (const k of ['head', 'body', 'hands', 'legs']) { const it = eqItem(H, k); if (it) a += it.v; } return a; }
function heroGear(H) { const W = heroWield(H), S = heroShield(H), horse = eqItem(H, 'horse'); return { W, S, horse, mounted: !!horse, arm: heroArmor(H), block: S ? S.v : (W.parry || 0) }; }
