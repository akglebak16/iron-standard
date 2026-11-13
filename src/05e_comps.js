/* ================= спутники (компаньоны) =================
   Общий для клиента и сервера: без DOM. Одиннадцать уникальных героев сидят по тавернам городов и переходят из города в город.
   Нанятый спутник идёт в отряде: в бою сражается сам (ИИ) в своей группе (пехота, стрелки или конница) и слушается приказов,
   на карте даёт отряду своё умение. Спутники не погибают: в бою их только ранят и выносят с поля, раненый (< 25% здоровья)
   пропускает бои, пока не подлечится. Спутник растёт в уровнях от боёв, на каждом уровне +1 к атрибуту по своему пути,
   а умение крепнет на 4-м и 7-м уровне (ранги I, II, III, как у перков).
   Хранение: P.comps = [спутник] — объект героя (атрибуты, eq, sel, hp, lvl, xp), к нему подходят heroDef/heroEq/getHeroSprite.
   G.cpos = { id: id города } — где сидят ненанятые; G.cstate = { id: спутник } — те, кого отпустили (уровень и вещи сохраняются).
   Старые сохранения: полей нет — всё заводится лениво. Сервер для игры вдвоём спутников не раздаёт (у игроков нет P.comps). */

const COMP_MAX = 5;            // больше спутников в отряде не берут
const COMP_FIT = .25;          // ниже этой доли здоровья спутник в бой не идёт
const COMP_EQ = (head, body, hands, legs, melee, ranged, shield, horse) => ({ head, body, hands, legs, melee, ranged: ranged || null, shield: shield || null, horse: horse || null });
/* sk — умение: ключи как у перков (см. FX_ZERO), значения для рангов I/II/III. grow — по какому атрибуту растёт на уровнях (по кругу). */
const COMPS = [
  { id: 'ingrid', name: 'Ингрид Ворона', fac: 'nord', beard: 0, role: 'Лучница', skn: 'Следопыт', price: 350, wage: 6,
    a: [2, 2, 4, 2, 1], perks: ['eagle'], eq: COMP_EQ('head_cap', 'body_padded', 'hands_leather', 'legs_boots', 'axe_work', 'bow_hunt'), sel: 'ranged', sk: { map: [.05, .08, .12] }, grow: ['agi', 'str', 'vit'],
    story: 'Охотница с северных фьордов. Ярл сжёг её деревню, и с тех пор она ищет отряд, который не боится крови.' },
  { id: 'halvdan', name: 'Хальвдан Секира', fac: 'nord', role: 'Тяжёлый пехотинец', skn: 'Носильщик', price: 800, wage: 9,
    a: [4, 4, 1, 1, 1], perks: ['grip'], eq: COMP_EQ('head_nasal', 'body_mail', 'hands_reinf', 'legs_boots', 'tw_axe'), sel: 'melee', sk: { cargo: [.12, .22, .35] }, grow: ['str', 'vit', 'str'],
    story: 'Бывший хускарл. Говорит, что ярл выгнал его за пьянство. Ярл говорит — за то, что Хальвдан выпил его мёд вместе с бочкой.' },
  { id: 'anselm', name: 'Брат Ансельм', fac: 'kin', role: 'Лекарь', skn: 'Лекарь', price: 450, wage: 7,
    a: [2, 3, 1, 4, 2], perks: [], eq: COMP_EQ('head_cap', 'body_padded', 'hands_leather', 'legs_boots', 'mace', null, 'shield_plank'), sel: 'melee', sk: { surv: [.08, .15, .22], heal: [.25, .5, .8] }, grow: ['int', 'vit', 'str'],
    story: 'Монах, сбежавший из обители с сумкой трав и пилой для костей. Неплохо машет булавой — говорит, что так написано в Писании.' },
  { id: 'cassia', name: 'Кассия Вента', fac: 'emp', beard: 0, role: 'Арбалетчица', skn: 'Казначей', price: 500, wage: 7,
    a: [1, 2, 3, 4, 2], perks: [], eq: COMP_EQ('head_cap', 'body_padded', 'hands_leather', 'legs_boots', 'sword_old', 'xbow_light'), sel: 'ranged', sk: { wage: [.06, .1, .15], buy: [.03, .05, .08] }, grow: ['int', 'agi', 'vit'],
    story: 'Дочь разорившегося купца из Вентума. Считает быстрее любого казначея и не прощает ни одной недостачи.' },
  { id: 'marcell', name: 'Марцелл Хромой', fac: 'emp', role: 'Ветеран-копейщик', skn: 'Наставник', price: 750, wage: 10,
    a: [3, 4, 1, 2, 3], perks: ['hide'], eq: COMP_EQ('head_kettle', 'body_mail', 'hands_mail', 'legs_greaves', 'spear_war', null, 'shield_banded'), sel: 'melee', sk: { hire: [.06, .1, .15] }, grow: ['vit', 'str', 'cha'],
    story: 'Двадцать лет в легионе, из них три — в плену у кочевников. Хромает, но учит новобранцев держать строй лучше любого центуриона.' },
  { id: 'tului', name: 'Тулуй', fac: 'khan', role: 'Конный лучник', skn: 'Степной разведчик', price: 800, wage: 11,
    a: [2, 2, 5, 1, 1], perks: ['eagle'], eq: COMP_EQ('head_cap', 'body_padded', 'hands_leather', 'legs_boots', 'sabre', 'bow_comp', null, 'horse_steppe'), sel: 'ranged', sk: { flee: [.06, .1, .15], map: [.03, .05, .08] }, grow: ['agi', 'str', 'vit'],
    story: 'Младший сын нойона. Наследства не дождался, зато лук натягивает на полном скаку с десяти лет.' },
  { id: 'aigerim', name: 'Айгерим', fac: 'khan', beard: 0, role: 'Лёгкая всадница', skn: 'Добытчица', price: 650, wage: 10,
    a: [3, 2, 4, 2, 2], perks: [], eq: COMP_EQ('head_cap', 'body_padded', 'hands_leather', 'legs_boots', 'sabre', null, 'shield_buckler', 'horse_steppe'), sel: 'melee', sk: { loot: [.08, .15, .22] }, grow: ['agi', 'str', 'vit'],
    story: 'Ушла из становища с отцовской саблей. Торгуется за трофеи так же лихо, как рубит.' },
  { id: 'geoffroi', name: 'Жоффруа де Бо', fac: 'kin', role: 'Рыцарь', skn: 'Знаменосец', price: 1400, wage: 16,
    a: [4, 4, 2, 1, 3], perks: ['tough'], eq: COMP_EQ('head_great', 'body_mail', 'hands_mail', 'legs_mail', 'sword_knight', null, 'shield_heraldic', 'horse_riding'), sel: 'melee', sk: { size: [4, 8, 12] }, grow: ['str', 'vit', 'cha'],
    story: 'Рыцарь без земли: замок отца проигран в кости. Мечтает его вернуть — желательно на твои деньги.' },
  { id: 'zeynab', name: 'Зейнаб', fac: 'emi', beard: 0, role: 'Метательница дротиков', skn: 'Торговка', price: 500, wage: 8,
    a: [2, 2, 3, 3, 3], perks: [], eq: COMP_EQ('head_turban', 'body_padded', 'hands_leather', 'legs_boots', 'sabre', 'jav_dart', 'shield_buckler'), sel: 'ranged', sk: { sell: [.04, .07, .1], quest: [.08, .15, .22] }, grow: ['agi', 'int', 'cha'],
    story: 'Водила караваны через пустыню, пока не лишилась последнего верблюда. Знает цену каждой вещи и каждому человеку.' },
  { id: 'vikenty', name: 'Викентий Де Будетон', fac: 'kin', role: 'Монах-арбалетчик', skn: 'Осадный лекарь', price: 650, wage: 9,
    a: [1, 3, 3, 5, 1], perks: ['surgery', 'eagle'], eq: COMP_EQ('head_hood', 'body_habit', 'hands_leather', 'legs_boots', 'club', 'xbow_light'), sel: 'ranged', sk: { heal: [.15, .3, .5], surv: [.05, .1, .15], siege: [.25, .45, .7] }, grow: ['int', 'agi', 'vit'],
    story: 'Сэр Викентий Де Будетон: монах, знаток осадных машин и лекарь. Лучше всех знает, где у стены слабое место, а у человека — больное. Ищет таблетки, которые дадут ему счастье. Пока не нашёл, поэтому грустит.',
    voice: {
      start: ['Опять драться. А таблеток всё нет…', 'Господи, пошли мне хоть одну таблетку счастья.', 'Ну, пойдём. Всё равно ничего не радует.', 'Сэр Викентий к бою готов. К радости — нет.'],
      siege: ['Стена. Хоть что-то в этом мире держится.', 'Каждая стена слаба там, где слаба душа. У меня — везде.', 'Осада: можно долго ждать и грустить. Мой жанр.'],
      kill: ['Прости, брат. Мне и самому невесело.', 'Минус один. Грусть на месте.', 'Это не та таблетка…', 'Болт нашёл цель. Хоть кто-то нашёл.', 'Тебе уже не больно. Мне — всё ещё.', 'Аминь. Вздох.'],
      killUndead: ['Вам хорошо: вы ничего не чувствуете.', 'Лежи спокойно. Завидую.', 'Вернись в могилу. Там тихо и не грустно.'],
      taunt: ['У кого есть таблетки? Не для боя. Для счастья.', 'Вы не видели аптекаря? Мне очень нужен аптекарь…', 'Может, вы что-то принимаете? Поделитесь.', 'Сдавайтесь. Мне и так тоскливо.'],
      hurt: ['Ай. Ну вот, и тут не повезло.', 'Больно. Как всегда.', 'Благословен будь… ох.'],
      down: ['Лекарство… найдите мне лекарство…', 'Всё как всегда. Несите к лекарю. То есть ко мне.']
    } },
  { id: 'idris', name: 'Идрис Песчаный', fac: 'emi', role: 'Мечник', skn: 'Учитель фехтования', price: 1000, wage: 13,
    a: [4, 3, 3, 1, 1], perks: ['master'], eq: COMP_EQ('head_turbanm', 'body_mail', 'hands_reinf', 'legs_greaves', 'sword_master', null, 'shield_banded'), sel: 'melee', sk: { xp: [.05, .1, .15] }, grow: ['str', 'agi', 'vit'],
    story: 'Бывший страж эмира. Молчит неделями, но враги его отряда почему-то не доживают до разговора.' }
];
/* Пасхалка: пан Глебио Кемейшалес. Всегда сидит в таверне Мяделя (на старой карте и в старых сохранениях Европы — в ближайшем к Нарочи городе),
   идёт в отряд бесплатно и без жалованья. Бьётся двуручником и в бою орёт (реплики над головой, см. 03b_gore.js). */
COMPS.push({ id: 'glebio', name: 'Глебио Кемейшалес', fac: 'kin', role: 'Шляхтич с двуручником', skn: 'Шляхетский размах', price: 0, wage: 0, fixed: 'Мядель',
  a: [6, 5, 3, 1, 2], perks: ['grip', 'grip', 'tough'], eq: COMP_EQ('head_kettle', 'body_scale', 'hands_mail', 'legs_mail', 'tw_claymore'), sel: 'melee', sk: { loot: [.1, .18, .25] }, grow: ['str', 'vit', 'str'],
  story: 'Польский шляхтич из-под Мяделя. Родовой герб, фамильный клеймор и ни гроша за душой. Служить готов даром — лишь бы рубить. Говорит, что за честь. Врёт: за веселье.',
  voice: {
    start: ['Ну пизда вам, сучары!', 'Пан Глебио пришёл — всем лечь!', 'Курва, ну и рожи… Поехали!', 'Сейчас будет шляхетский мордобой!', 'Кто не спрятался — я не виноват, бля!'],
    kill: ['Сюда, бля, малышок, епта — минус один!', 'Резать! Резать! Резать!', 'СВИННОЕ ПЕКЛО!', 'Курва мать, ещё один!', 'Лежать, холоп!', 'Это тебе за Мядель, сука!', 'Ещё! Дайте ещё!', 'Пиздец тебе, родной.', 'Кто следующий, ёб твою мать?!', 'Мой клеймор голоден!', 'Готов, голубчик!', 'Ох, хорошо пошло!'],
    killUndead: ['Лежи и не вставай, жмурик!', 'Обратно в могилу, сука!', 'Кости в кучу, курва!'],
    taunt: ['Вы чё, ссыте?!', 'Иди сюда, иди сюда, сучара!', 'Я ж вас всех на шашлык порежу!', 'Шляхта не отступает, бля!', 'Ну давай, давай, родной!'],
    hurt: ['Ай, сука!', 'Царапина, бля!', 'Ах ты ж падла!'],
    down: ['Курва… я ещё вернусь…', 'Пиздец… несите к лекарю…']
  } });
/* Захарий Коричневая Лужа: деревенский здоровяк без мозгов, сидит в Полоцке (там его знают как «мистера Лужу»). Бьётся одноручной дубиной «Головка» со щитом из досок и сыплет тупыми шутками. */
COMPS.push({ id: 'zahariy', name: 'Захарий Коричневая Лужа', fac: 'dom', role: 'Деревенский здоровяк с дубиной', skn: 'Деревенская сила', price: 228, wage: 4, fixed: 'Полоцк',
  a: [9, 9, 2, 1, 1], perks: ['tough'], eq: COMP_EQ(null, 'body_padded', null, null, 'club_head', null, 'shield_plank'), sel: 'melee', sk: { cargo: [.1, .18, .28] }, grow: ['str', 'vit', 'str'],
  story: 'Тридцатилетний грязный оборванный крестьянин из-под Полоцка: мозгов нет, зато силы на троих. В Полоцке его зовут мистер Лужа. Ходит с дубиной по имени Головка и страшно не любит выходить из дома, но за 228 монет согласился.',
  voice: {
    start: ['Хуле стоишь, чё не дудишь?', 'Я хочу домой…', 'Головка, пошли!', 'Мамка сказала не выходить, а я вышел. Хы хы.', 'Ну чё, кто тут самый красный?'],
    siege: ['Это чё, огромный забор?', 'Давай я стену головой, а? Или Головкой!', 'Дома лучше, чем у стены…'],
    kill: ['Затормози в говно!', 'Я пукнул, хы хы!', 'Ты чего такой красный, ты помидор?!', 'Хы хы, он упал!', 'Головка сказала: привет!', 'Бух! Ой.', 'Не дудишь, да? Ну и лежи.', 'Я его, это, пришиб. Я молодец?', 'Ха! Чё, лужа тебе в лицо!', 'Спасибо, Головка!'],
    killUndead: ['Дядя, ты чего такой бледный?', 'Он встал! Хы хы, я его снова!', 'Фу, мёртвый, воняет почти как я.'],
    taunt: ['Эй, красный, ты помидор?!', 'Хуле стоишь, чё не дудишь?', 'Я пукнул! Это в вашу сторону!', 'У меня дубина, а у тебя чё?', 'Сдавайтесь, а то Головка сердится!', 'Я не злой, я просто так!'],
    hurt: ['Ай! Головка, он дерётся!', 'Больно, как коленкой об стул!', 'Хочу домой!'],
    down: ['Мамка… я вышел из дома, а зря…', 'Головка, я тут полежу…']
  } });
const COMP = {}; for (const c of COMPS) COMP[c.id] = c;
const SK_TXT = { map: 'отряд идёт по карте быстрее', cargo: 'обоз вмещает больше', surv: 'из павших бойцов больше раненых', heal: 'герой лечится быстрее', wage: 'жалованье ниже', buy: 'покупка дешевле',
  hire: 'найм и улучшение войск дешевле', flee: 'шанс уйти от погони выше', loot: 'добыча после боя больше', size: 'отряд больше на', sell: 'продажа дороже', quest: 'награды за задания больше', xp: 'герой получает больше опыта', siege: 'штурм легче: защита стен слабее на' };

function compRank(c) { return Math.min(3, 1 + Math.floor(((c.lvl || 1) - 1) / 3)); } // ранг умения: 1–3 уровни I, 4–6 II, 7+ III
function compSkillText(c, rank) { const d = COMP[c.id], r = rank || compRank(c); return Object.keys(d.sk).map(k => SK_TXT[k] + ' ' + (k === 'size' ? '+' + d.sk[k][r - 1] : '+' + Math.round(d.sk[k][r - 1] * 100) + '%')).join(', '); }
function compNew(id) {
  const d = COMP[id], a = d.a;
  return { id, name: d.name, lvl: 1, xp: 0, str: a[0], vit: a[1], agi: a[2], int: a[3], cha: a[4], pts: 0, pp: 0, perks: d.perks.slice(), eq: Object.assign({}, d.eq), sel: d.sel, hp: 1, seed: hashStr(id) % 99999 + 1, beard: d.beard === undefined ? 1 : d.beard };
}
const compsOf = P => P.comps || (P.comps = []);
const compFit = c => c.hp >= COMP_FIT;
function compWage(P) { let w = 0; for (const c of P.comps || []) w += COMP[c.id].wage; return w; }
function compById(P, id) { return (P.comps || []).find(c => c.id === id) || null; }

/* Сумма умений спутников игрока; кэш по составу и уровням. Подмешивается в perkFx(герой игрока), поэтому действует везде,
   где уже работают перки (скорость на карте, жалованье, торговля, найм, добыча, размер отряда, опыт героя). */
const CFX = new WeakMap();
function compFx(P) {
  const L = P && P.comps; if (!L || !L.length) return null;
  const key = L.map(c => c.id + compRank(c)).join(','), c0 = CFX.get(P); if (c0 && c0.k === key) return c0;
  const f = Object.assign({}, FX_ZERO); for (const c of L) { const d = COMP[c.id], r = compRank(c); if (d) for (const k in d.sk) f[k] += d.sk[k][r - 1]; }
  const o = { k: key, f }; CFX.set(P, o); return o;
}
function compFxForHero(H) { if (typeof G === 'undefined' || !G || !G.players) return null; for (const P of G.players) if (P.hero === H) return compFx(P); return null; }
/* Сила спутников для расчётного боя и оценки сил: крепче бойца 3-го уровня и растёт с уровнем */
function compStr(P) { let s = 0; for (const c of P.comps || []) if (compFit(c)) s += (8 + c.lvl * .8) * (heroEq(c).horse ? 1.35 : 1); return s; }

/* ---------- таверны ---------- */
function compTowns() { return G.settles.filter(s => s.kind === 'town' && s.fac !== 'bandit'); }
function compHired(id) { for (const P of G.players) if (compById(P, id)) return true; return false; }
function compFixedTown(d) { // город пасхального спутника: по имени, иначе ближайший к его родным местам (Нарочь), на старой карте — первый город
  const all = compTowns(), byName = all.find(s => s.name === d.fixed); if (byName) return byName;
  if (isEU()) { const x = euX(26.85), y = euY(54.88); return all.slice().sort((a, b) => Math.hypot(a.x - x, a.y - y) - Math.hypot(b.x - x, b.y - y))[0]; }
  return all[0];
}
function compPlace(id, avoid) {
  const all = compTowns(), d = COMP[id]; if (!all.length) return;
  if (d.fixed) { const t = compFixedTown(d); if (t) { G.cpos[id] = t.id; return; } }
  const busy = new Set(Object.values(G.cpos)), home = all.filter(s => sCult(s) === d.fac && s.id !== avoid && !busy.has(s.id)), free = all.filter(s => s.id !== avoid && !busy.has(s.id));
  const s = pick(home.length && Math.random() < .6 ? home : free.length ? free : all); G.cpos[id] = s.id;
}
function compsInit() { if (!G.cpos) G.cpos = {}; if (!G.cstate) G.cstate = {}; for (const c of COMPS) if (!compHired(c.id) && (G.cpos[c.id] === undefined || !settleById(G.cpos[c.id]))) compPlace(c.id); }
function compsAt(s) { compsInit(); return COMPS.filter(c => G.cpos[c.id] === s.id && !compHired(c.id)).map(c => G.cstate[c.id] || compNew(c.id)); }
function compsDay() { compsInit(); if (G.day % 4) return; for (const c of COMPS) if (!c.fixed && !compHired(c.id) && Math.random() < .5) { const was = G.cpos[c.id]; delete G.cpos[c.id]; compPlace(c.id, was); } } // раз в 4 дня половина бродяг меняет город
function compRumor(s) { // слух в таверне: где сейчас ближайший свободный спутник из другого города
  compsInit(); let best = null, bd = 1e9; for (const c of COMPS) { const sid = G.cpos[c.id]; if (sid === undefined || sid === s.id || compHired(c.id)) continue; const t = settleById(sid); if (!t) continue; const d = Math.hypot(t.x - s.x, t.y - s.y); if (d < bd) { bd = d; best = { c: COMP[c.id], t }; } }
  return best;
}
function doCompHire(P, s, id) {
  compsInit(); const d = COMP[id]; if (!d || G.cpos[id] !== s.id || compHired(id)) return 'Этого человека здесь уже нет.';
  if (compsOf(P).length >= COMP_MAX) return 'Больше ' + COMP_MAX + ' спутников в отряде не уживутся.';
  if (P.gold < d.price) return 'Не хватает золота.';
  P.gold -= d.price; const c = G.cstate[id] || compNew(id); delete G.cstate[id]; delete G.cpos[id]; compsOf(P).push(c);
  logW(c.name + ' присоединяется к отряду.', 3, P); return '';
}
function doCompFire(P, id, why) {
  const c = compById(P, id); if (!c) return false; compsInit(); P.comps.splice(P.comps.indexOf(c), 1); G.cstate[id] = c;
  const near = COMP[id].fixed ? compFixedTown(COMP[id]) : compTowns().sort((a, b) => Math.hypot(a.x - P.x, a.y - P.y) - Math.hypot(b.x - P.x, b.y - P.y))[0]; // пасхальный спутник возвращается домой if (near) G.cpos[id] = near.id;
  logW(c.name + (why || ' уходит из отряда') + (near ? ' и будет ждать в таверне ' + near.name : '') + '.', 1, P); return true;
}

/* ---------- бой и рост ---------- */
function compsBattle(P) { return (P.comps || []).filter(compFit).map(c => Object.assign(heroBattle(c), { id: c.id, beard: c.beard })); } // кого взять в бой (копии, как heroBattle)
function compsAuto(P, res) { // расчётный бой: спутники теряют здоровье как герой
  res.comps = {}; for (const c of P.comps || []) if (compFit(c)) res.comps[c.id] = { hp: clamp(c.hp - (res.win ? rnd(.05, .35) : rnd(.35, .6)), 0, 1), down: false, kills: 0 };
}
function compsAfter(P, res) { // → список строк для итогов боя
  const out = [], R = res.comps; if (!R) return out;
  for (const id in R) {
    const c = compById(P, id), r = R[id]; if (!c) continue;
    c.hp = r.down ? .1 : clamp(r.hp, .1, 1);
    const gx = Math.round(((res.win ? 1 : .5) * (res.xp || 0) * .3 + r.kills * 12 + 8) * xpMul(c)); c.xp += gx; let up = 0;
    while (c.xp >= xpNeed(c.lvl)) { c.xp -= xpNeed(c.lvl); c.lvl++; const d = COMP[id]; c[d.grow[(c.lvl - 2) % d.grow.length]]++; up++; if (c.lvl === 4 || c.lvl === 7) logW(c.name + ': умение «' + d.skn + '» окрепло (ранг ' + ['I', 'II', 'III'][compRank(c) - 1] + ').', 3, P); }
    if (up) logW(c.name + ' достигает уровня ' + c.lvl + '.', 3, P);
    out.push({ c, down: r.down, kills: r.kills, gx, up });
  }
  return out;
}
function compsHeal(P, heal) { for (const c of P.comps || []) c.hp = Math.min(1, c.hp + heal); }
function compsUnpaid(P) { // не хватило на жалованье: спутник может уйти
  const L = P.comps || []; if (!L.length || Math.random() > .25) return; doCompFire(P, pick(L).id, ' ушёл: жалованье не плачено,');
}
