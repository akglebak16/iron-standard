/* ================= окна спутников: таверна в городе, вкладка «Спутники», выбор, кого одевать в обозе =================
   Логика и каталог: 05e_comps.js. */
const ATTR_SHORT = { str: 'Сил', vit: 'Сто', agi: 'Лов', int: 'Инт', cha: 'Хар' };
function compImg(c) { const sp = getHeroSprite(c, !!heroEq(c).horse); if (!sp.url) sp.url = sp.cv.toDataURL(); return sp.url; }
function compAttrs(c) { return Object.keys(ATTR_SHORT).map(k => '<span title="' + ATTRS[k][0] + '">' + ATTR_SHORT[k] + ' <b>' + c[k] + '</b></span>').join(''); }
function compGearLine(c) { const W = heroWield(c), S = heroShield(c), hd = heroDef(c); return W.name + (S ? ', ' + S.name.toLowerCase() : '') + (heroEq(c).horse ? ', верхом' : '') + ' · здор. ' + hd.hp + ' · урон ' + Math.round(hd.dmg) + ' · броня ' + hd.arm; }
function compSkillHtml(c) { const d = COMP[c.id], r = compRank(c); return '<span class="tag sk">' + d.skn + ' ' + ['I', 'II', 'III'][r - 1] + '</span>' + compSkillText(c, r) + (r < 3 ? ' <span class="dim">(крепнет на ' + (r === 1 ? 4 : 7) + '-м уровне)</span>' : ''); }

function tavernBody(s) {
  const P = G.player, here = compsAt(s), n = compsOf(P).length; let b = '';
  b += '<div class="note">Наёмники-одиночки сидят по тавернам и переходят из города в город. Спутник сражается рядом с тобой, растёт в уровнях и даёт отряду своё умение. Спутников в отряде: ' + n + ' из ' + COMP_MAX + '.</div>';
  if (!here.length) b += '<div class="note">Сегодня здесь только местные пьяницы и игроки в кости.</div>';
  for (const c of here) {
    const d = COMP[c.id], can = P.gold >= d.price && n < COMP_MAX;
    b += '<div class="row comp"><img alt="" src="' + compImg(c) + '"><div class="grow"><div class="nm">' + c.name + ' <span class="tag">' + d.role + '</span><span class="tag">' + FACTIONS[d.fac].name + '</span>' + (c.lvl > 1 ? '<span class="tag">Ур. ' + c.lvl + '</span>' : '') + '</div>' +
      '<div class="ds story">«' + d.story + '»</div><div class="ds attrs">' + compAttrs(c) + '</div><div class="ds">' + compGearLine(c) + '</div><div class="ds skill">' + compSkillHtml(c) + '</div></div>' +
      '<div class="acts col"><span class="price ' + (P.gold < d.price ? 'no' : '') + '">' + ic('coin') + d.price + '</span><span class="ds">жалованье ' + d.wage + '/день</span><button class="btn sm pri" data-act="chire" data-id="' + c.id + '" ' + (can ? '' : 'disabled') + '>Нанять</button></div></div>';
  }
  const rm = compRumor(s); if (rm) b += '<div class="note rumor">Трактирщик шепчет: «' + rm.c.name + ' (' + rm.c.role.toLowerCase() + ') сейчас в ' + rm.t.name + '. Ищет, к кому бы пристать».</div>';
  return b;
}
function compsBody() {
  const P = G.player, L = compsOf(P); let b = '<div class="note">Спутники бьются сами в своей группе (пехота, стрелки или конница) и слушаются приказов. В бою их не убивают, а ранят: раненый ниже ' + Math.round(COMP_FIT * 100) + '% здоровья пропускает бои, пока не подлечится. Жалованье спутников: ' + compWage(P) + ' в день.</div>';
  if (!L.length) b += '<div class="note">Спутников нет. Ищи их в тавернах городов.</div>';
  for (const c of L) {
    const d = COMP[c.id], hd = heroDef(c), ok = compFit(c), conf = UI.cfire === c.id;
    b += '<div class="row comp"><img alt="" src="' + compImg(c) + '"><div class="grow"><div class="nm">' + c.name + ' <span class="tag">' + d.role + '</span><span class="tag">Ур. ' + c.lvl + '</span>' + (ok ? '' : '<span class="tag r">ранен</span>') + '</div>' +
      '<div class="ds attrs">' + compAttrs(c) + '<span>Опыт <b>' + c.xp + ' / ' + xpNeed(c.lvl) + '</b></span></div><div class="pbar hp"><i style="width:' + Math.round(c.hp * 100) + '%"></i></div><div class="ds">Здоровье ' + Math.round(c.hp * hd.hp) + ' / ' + hd.hp + ' · ' + compGearLine(c).split(' · здор.')[0] + '</div><div class="ds skill">' + compSkillHtml(c) + '</div></div>' +
      '<div class="acts col"><span class="ds">' + d.wage + '/день</span><button class="btn sm" data-act="cgear" data-id="' + c.id + '">Снаряжение</button>' +
      (conf ? '<button class="btn sm danger" data-act="cfireok" data-id="' + c.id + '">Точно отпустить?</button>' : '<button class="btn sm danger" data-act="cfire" data-id="' + c.id + '">Отпустить</button>') + '</div></div>';
  }
  return b;
}
/* в обозе: чью куклу показываем — героя (UI.who = null) или спутника */
function invWho(P) { const c = UI.who ? compById(P, UI.who) : null; if (!c) UI.who = null; return c || P.hero; }
function whoBar(P) {
  const L = compsOf(P); if (!L.length) return '';
  const chip = (id, nm, src) => '<button class="who' + ((UI.who || null) === id ? ' on' : '') + '" data-act="cwho" data-id="' + (id || '') + '"><img alt="" src="' + src + '">' + nm + '</button>';
  const H = P.hero, hs = getHeroSprite(H, !!heroEq(H).horse); if (!hs.url) hs.url = hs.cv.toDataURL();
  return '<div class="whobar">' + chip(null, H.name, hs.url) + L.map(c => chip(c.id, c.name.split(' ')[0], compImg(c))).join('') + '</div>';
}
ACT.chire = function (d) { const r = doCompHire(G.player, UI.town.s, d.id); if (r) toast(r); else { sfx('coin'); toast(COMP[d.id].name + ' теперь в твоём отряде'); } keepScroll(renderTown); };
ACT.cfire = function (d) { UI.cfire = d.id; keepScroll(renderPanel); };
ACT.cfireok = function (d) { UI.cfire = null; if (doCompFire(G.player, d.id)) sfx('click'); if (!compsOf(G.player).length) UI.panel = 'troops'; keepScroll(renderPanel); };
ACT.cgear = function (d) { UI.who = d.id; UI.isel = null; openPanel('inv'); };
ACT.cwho = function (d) { UI.who = d.id || null; UI.isel = null; keepScroll(renderPanel); };
