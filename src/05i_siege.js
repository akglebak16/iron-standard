/* ================= осада на карте: вылазки, подмога, пожары, итоги штурма =================
   Только одиночная игра (на сервер не грузить): общий код зовёт эти функции через typeof.
   Поля поселения: s.dmg (0..1 — повреждения стен и построек), s.fire (часов пожара).
   Поля осады s.siege: sally (число вылазок), rel (id лордов подмоги), relN (сколько раз звали), relAt.
   Лорд-подмога помечен p.relief = id поселения и p.army = true (как в походе), пока не дойдёт или осада не кончится. */
const SG = { DMG_H: 24 * 10 }; // за сколько часов стены полностью чинятся

// запасы обороны для боя (03c_siegedef.js) и поправка к силе защитников при расчёте
function sgDefCfg(s) { return s.kind === 'castle' ? { stones: 14, oil: 3 } : { stones: 10, oil: 2 }; }
function sgDefK(s) { return 1.5 - .4 * ((s && s.dmg) || 0); }
function sgNote(s) {
  const d = s.dmg || 0, c = sgDefCfg(s);
  return d > .15 ? '. Стены повреждены, проломы шире, а запасов камней и масла меньше' : '. На стенах котлы с кипящим маслом (' + c.oil + ') и запас камней: у проломов будет жарко';
}
const sgCut = (list, rate) => { for (const t of list.slice()) remT(list, t.type, Math.round(t.n * rate)); };
const sgDist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

// вызывается из siegeTick раз в 2 часа; true — осада закончилась (подмога разбила осаждающих)
function sgTick(s, sg, att, A, k) {
  const dur = nowH() - sg.t0, g = garrisonOf(s);
  s.dmg = Math.min(1, (s.dmg || 0) + .008 + .014 * clamp(k, 0, 2)); // обстрел и приступы портят стены
  if (!(s.fire > 0) && Math.random() < .04 + .05 * clamp(k, 0, 2)) { s.fire = rint(30, 70); wlog('В ' + (s.kind === 'castle' ? 'замке ' : 'городе ') + s.name + ' начался пожар.', 2); }
  sgSortie(s, sg, att, A, g, dur);
  return sgRelief(s, sg, att, A, dur);
}
function sgSortie(s, sg, att, A, g, dur) {
  if (dur < 6 || troopCount(g) < 10 || Math.random() > .12) return;
  const gs = strength(g) + 4, ratio = gs * 1.3 / Math.max(1, A), ok = Math.random() < clamp(.2 + .5 * ratio, .2, .8); sg.sally = (sg.sally || 0) + 1;
  if (ok) { for (const p of att) sgCut(p.troops, rnd(.05, .1)); sgCut(g, rnd(.02, .04)); wlog('Гарнизон ' + s.name + ' ночной вылазкой ударил по осаждающим: у них потери.', 2); }
  else { sgCut(g, rnd(.06, .1)); for (const p of att) sgCut(p.troops, rnd(.01, .02)); wlog('Вылазка гарнизона ' + s.name + ' отбита, защитники понесли потери.', 2); }
}
function sgRelief(s, sg, att, A, dur) {
  let rel = (sg.rel || []).map(partyById).filter(p => p && p.relief === s.id);
  if (!rel.length && dur >= 10 && (sg.relN || 0) < 2 && nowH() - (sg.relAt || -99) > 24) { // зовём лордов фракции города
    const c = G.parties.filter(p => p.kind === 'lord' && p.fac === s.fac && !p.hide && !p.army && !p.fight && !p.relief && troopCount(p.troops) >= 18 * MK() && sgDist(p, s) < 480).sort((a, b) => sgDist(a, s) - sgDist(b, s)).slice(0, 3);
    if (c.length) { sg.relN = (sg.relN || 0) + 1; sg.relAt = nowH(); sg.rel = c.map(p => p.id); for (const p of c) { p.relief = s.id; p.army = true; campGo(p, s); } wlog('К осаждённому городу ' + s.name + ' спешит подмога: ' + c.length + ' ' + (c.length === 1 ? 'отряд' : 'отряда') + '.', 2); rel = c; }
  }
  if (!rel.length) return false;
  const near = rel.filter(p => sgDist(p, s) < 130);
  if (near.length < Math.max(1, Math.ceil(rel.length * .6)) && nowH() - sg.relAt < 40) return false;
  const free = p => { p.army = false; p.relief = null; p.arrived = false; p.state = 'idle'; p.path = []; p.pi = 0; p.wait = rint(2, 6); };
  if (!near.length) { for (const p of rel) free(p); return false; }
  const R = near.reduce((a, p) => a + partyStr(p), 0) + .3 * strength(garrisonOf(s)), win = R * rnd(.8, 1.2) > A * rnd(.8, 1.2);
  if (win) { for (const p of att) sgCut(p.troops, rnd(.35, .55)); for (const p of near) sgCut(p.troops, rnd(.1, .2)); for (const p of rel) free(p); delete s.siege; wlog('Подмога разбила осаждающих: осада ' + s.name + ' снята.', 2); return true; }
  for (const p of near) sgCut(p.troops, rnd(.4, .6)); for (const p of att) sgCut(p.troops, rnd(.1, .18)); for (const p of rel) free(p);
  wlog('Подмога осаждённому ' + s.name + ' разбита.', 2); return false;
}
// раз в час: пожары гаснут, стены чинятся, лордов подмоги отзывают, если осада кончилась
function sgHour() {
  for (const s of G.settles) { if (s.fire > 0) s.fire--; if (!s.siege && s.dmg > 0) s.dmg = Math.max(0, s.dmg - 1 / SG.DMG_H); }
  for (const p of G.parties) if (p.relief) { const s = settleById(p.relief); if (!s || !s.siege) { p.army = false; p.relief = null; p.arrived = false; p.state = 'idle'; p.path = []; p.pi = 0; p.wait = rint(1, 4); } }
}
// лорды, взяв город, иногда его грабят
function sgSackAI(s, f) {
  if (Math.random() > .5) return;
  s.dmg = Math.max(s.dmg || 0, .5); s.fire = Math.max(s.fire || 0, rint(24, 60)); s.recruits = [];
  wlog((s.kind === 'castle' ? 'Замок ' : 'Город ') + s.name + ' разграблен.', 2);
}
// игрок взял город штурмом: решает, грабить ли его
function sgCaptured(P, s, was) { P.sgPend = !NET.on && typeof REAL_F !== 'undefined' && REAL_F.includes(was) ? s.id : null; }
function sgSack(P, s) {
  const loot = Math.round((s.kind === 'town' ? 300 : 220) * rnd(.8, 1.3) * MK()), cf = sCult(s); P.gold += loot;
  s.dmg = Math.max(s.dmg || 0, .6); s.fire = rint(36, 72); s.recruits = [];
  if (REAL_F.includes(cf)) P.rel[cf] = Math.max(-100, P.rel[cf] - 10);
  logW('Ты разграбил ' + s.name + ': +' + loot + ' золота. Город горит, а его жители тебя ненавидят: доход упал, пока стены не починят.', 3, P);
}
function sgSpare(P, s) {
  const gift = Math.round(40 * MK()), cf = sCult(s); P.gold += gift; s.dmg = Math.min(s.dmg || 0, .1);
  if (REAL_F.includes(cf)) P.rel[cf] = Math.min(100, P.rel[cf] + 6);
  logW('Ты пощадил жителей ' + s.name + '. Они подносят дары: +' + gift + ' золота, а отношение к их фракции стало лучше.', 3, P);
}
