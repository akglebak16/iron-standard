/* ================= окно героя: атрибуты и перки =================
   Пять строк: слева атрибут (значение и «+»), справа четыре перка по три уровня. Каждый уровень перка требует своего
   значения атрибута и стоит очко перков. Логика и каталог перков: 01c_perks.js. */
const ATTR_ICON = { str: 'hands', vit: 'heart', agi: 'charge', int: 'book', cha: 'flag' };
const ATTR_NOW = {
  str: H => '+' + H.str * 3 + ' к урону',
  vit: H => '+' + H.vit * 14 + ' к здоровью',
  agi: H => '+' + H.agi * 3 + ' к скорости бега',
  int: H => '+' + (H.int - 1) * 3 + '% к опыту',
  cha: H => '+' + H.cha * 5 + ' к отряду, мораль +' + H.cha * 4
};
const ROMAN = ['I', 'II', 'III'];

/* Описание перка для всех трёх рангов: «бьёт сильнее на 6 / 12 / 18%», значение текущего ранга золотое, следующего подчёркнуто */
function perkDescHtml(p, rank) {
  return perkParts(p).map(x => x.t + ' ' + x.v.map((v, i) => '<b class="' + (i === rank - 1 ? 'cur' : i === rank ? 'nxt' : '') + '">' + v + '</b>').join('<i>/</i>') + x.u).join(', ') + '.';
}
function perkCard(H, p) {
  const rank = perkRank(H, p.id), maxed = rank >= PERK_MAX, why = maxed ? '' : perkWhy(H, p.id), can = !maxed && !why, met = !maxed && H[p.a] >= p.req[rank];
  const cls = 'perk' + (rank ? ' on' : '') + (maxed ? ' max' : '') + (can ? ' av' : met ? ' rd' : !maxed ? ' lk' : '');
  const foot = maxed ? 'Максимум' : can ? (rank ? 'Улучшить до ' + ROMAN[rank] : 'Изучить') + ' · 1 очко' : why.replace(/\.$/, '');
  const pips = ROMAN.map((r, i) => '<i class="' + (i < rank ? 'on' : '') + '"></i>').join('');
  const reqs = p.req.map((q, i) => '<u class="' + (i < rank ? 'd' : i === rank ? (H[p.a] >= q ? 'ok' : 'n') : '') + '">' + q + '</u>').join(' · ');
  const tip = ROMAN.map((r, i) => 'Уровень ' + r + ' (' + ATTRS[p.a][0] + ' ' + p.req[i] + '): ' + perkText(p, i + 1)).join('\n');
  return '<button class="' + cls + '" title="' + tip + '" ' + (can ? 'data-act="perk" data-id="' + p.id + '"' : 'disabled') + '><span class="pt"><span class="pips">' + pips + '</span><span class="rq" title="Нужный уровень атрибута для каждого ранга">' + reqs + '</span></span><b class="pn">' + p.n + '</b><span class="pd">' + perkDescHtml(p, rank) + '</span><span class="pf">' + foot + '</span></button>';
}
function attrRow(H, k) {
  const list = PERKS.filter(p => p.a === k), pend = list.filter(p => perkRank(H, p.id) < PERK_MAX).map(p => p.req[perkRank(H, p.id)]), lock = pend.filter(q => H[k] > 0 && H[k] < q);
  const nxt = !pend.length ? 'Все перки на максимуме' : lock.length ? 'Следующий уровень перка на ' + Math.min(...lock) + ' (ещё ' + (Math.min(...lock) - H[k]) + ')' : 'Все доступные уровни перков открыты';
  return '<div class="arow"><div class="acell"><div class="ahd">' + ic(ATTR_ICON[k], 26) + '<b>' + ATTRS[k][0] + '</b><span class="v">' + H[k] + '</span>' +
    '<button class="btn sm" data-act="attr" data-k="' + k + '" ' + (H.pts ? '' : 'disabled') + ' title="Потратить очко атрибутов">+</button></div>' +
    '<div class="ad">' + ATTRS[k][1] + '. Сейчас: ' + ATTR_NOW[k](H) + '.</div><div class="nx">' + nxt + '</div></div>' +
    '<div class="perks">' + list.map(p => perkCard(H, p)).join('') + '</div></div>';
}
function heroBody() {
  const P = G.player, H = heroFix(P.hero), hd = heroDef(H), Gr = heroGear(H), sp = getHeroSprite(H, Gr.mounted); if (!sp.url) sp.url = sp.cv.toDataURL();
  const cnt = troopCount(P.troops), F = perkFx(H);
  return '<div class="hhead"><img alt="" src="' + sp.url + '"><div><div class="hn">' + H.name + '<small>Уровень ' + H.lvl + '</small></div>' +
    '<div class="pbar"><i style="width:' + clamp(H.xp / xpNeed(H.lvl) * 100, 0, 100) + '%"></i></div>' +
    '<div class="hst"><span>Опыт<b>' + H.xp + ' / ' + xpNeed(H.lvl) + '</b></span><span>Здоровье<b>' + Math.round(H.hp * hd.hp) + ' / ' + hd.hp + '</b></span><span>Урон<b>' + Math.round(hd.dmg) + '</b></span><span>Броня<b>' + hd.arm + '</b></span><span>Отряд<b>' + cnt + ' / ' + sizeCap(H) + '</b></span></div>' +
    miniGear(H) + '</div>' +
    '<div class="hpts"><div class="pchip' + (H.pts ? ' hot' : '') + '">Очки атрибутов<b>' + H.pts + '</b></div><div class="pchip' + (H.pp ? ' hot' : '') + '">Очки перков<b>' + H.pp + '</b></div>' +
    '<button class="btn sm" data-act="ptab" data-t="inv">Открыть обоз</button></div></div>' +
    '<div class="note" style="margin:10px 0 0">Все перки доступны сразу. У каждого три уровня: следующий уровень требует более высокого значения атрибута и стоит одно очко перков. За уровень героя: +' + PTS_LEVEL + ' очка атрибутов и +' + PP_LEVEL + ' очко перков. В бою оружие меняется клавишей X или кнопкой в панели героя.</div>' +
    Object.keys(ATTRS).map(k => attrRow(H, k)).join('');
}
ACT.perk = function (d) {
  if (NET.on) { NET.send({ t: 'perk', id: d.id }); sfx('order'); return; }
  if (doPerk(G.player, d.id)) { sfx('level'); toast('Перк изучен: ' + PERK[d.id].n); }
  keepScroll(renderPanel);
};
