/* ================= окно героя: атрибуты и перки =================
   Пять строк: слева атрибут (значение и «+»), справа четыре перка с порогами. Перк берётся за очко перков,
   когда атрибут достиг порога. Логика и каталог перков: 01c_perks.js. */
const ATTR_ICON = { str: 'hands', vit: 'heart', agi: 'charge', int: 'book', cha: 'flag' };
const ATTR_NOW = {
  str: H => '+' + H.str * 3 + ' к урону',
  vit: H => '+' + H.vit * 14 + ' к здоровью',
  agi: H => '+' + H.agi * 3 + ' к скорости бега',
  int: H => '+' + (H.int - 1) * 3 + '% к опыту',
  cha: H => '+' + H.cha * 5 + ' к отряду, мораль +' + H.cha * 4
};
const ROMAN = ['I', 'II', 'III', 'IV'];

function perkCard(H, p, i) {
  const learned = H.perks.includes(p.id), why = learned ? '' : perkWhy(H, p.id), can = !learned && !why, ready = !learned && H[p.a] >= p.req;
  const cls = 'perk ' + (learned ? 'on' : can ? 'av' : ready ? 'rd' : 'lk'), foot = learned ? 'Изучено' : can ? 'Изучить · 1 очко' : why.replace(/\.$/, '');
  return '<button class="' + cls + '" ' + (can ? 'data-act="perk" data-id="' + p.id + '"' : 'disabled') + '><span class="pt">' + ROMAN[i] + ' · ' + ATTRS[p.a][0] + ' ' + p.req + '</span><b class="pn">' + p.n + '</b><span class="pd">' + p.d + '</span><span class="pf">' + foot + '</span></button>';
}
function attrRow(H, k) {
  const list = PERKS.filter(p => p.a === k), nx = list.find(p => !H.perks.includes(p.id) && H[k] < p.req);
  return '<div class="arow"><div class="acell"><div class="ahd">' + ic(ATTR_ICON[k], 26) + '<b>' + ATTRS[k][0] + '</b><span class="v">' + H[k] + '</span>' +
    '<button class="btn sm" data-act="attr" data-k="' + k + '" ' + (H.pts ? '' : 'disabled') + ' title="Потратить очко атрибутов">+</button></div>' +
    '<div class="ad">' + ATTRS[k][1] + '. Сейчас: ' + ATTR_NOW[k](H) + '.</div>' + (nx ? '<div class="nx">Следующий перк на ' + nx.req + ' (ещё ' + (nx.req - H[k]) + ')</div>' : '<div class="nx">Все перки доступны</div>') + '</div>' +
    '<div class="perks">' + list.map((p, i) => perkCard(H, p, i)).join('') + '</div></div>';
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
    '<div class="note" style="margin:10px 0 0">За уровень: +' + PTS_LEVEL + ' очка атрибутов и +' + PP_LEVEL + ' очко перков. Перк открывается, когда атрибут дорастёт до порога, и стоит одно очко перков. В бою клавиша X меняет оружие.</div>' +
    Object.keys(ATTRS).map(k => attrRow(H, k)).join('');
}
ACT.perk = function (d) {
  if (NET.on) { NET.send({ t: 'perk', id: d.id }); sfx('order'); return; }
  if (doPerk(G.player, d.id)) { sfx('level'); toast('Перк изучен: ' + PERK[d.id].n); }
  keepScroll(renderPanel);
};
