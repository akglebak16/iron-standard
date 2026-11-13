/* ================= интерфейс ================= */
const el = id => document.getElementById(id);
const ICONS = {
  coin: '<ellipse cx="8.5" cy="18" rx="6.5" ry="2.8"/><ellipse cx="8.5" cy="15.4" rx="6.5" ry="2.8" stroke="#0009" stroke-width="1"/><circle cx="14.5" cy="9.5" r="7.3" stroke="#0009" stroke-width="1"/><circle cx="14.5" cy="9.5" r="5" fill="none" stroke="#0007" stroke-width="1.1"/><path d="M14.5 6.300l.95 2 2.150.25-1.600 1.500.45 2.150-1.950-1.100-1.950 1.100.45-2.150-1.600-1.500 2.150-.25z" fill="#0007"/><path d="M9.800 6.200a6 6 0 0 1 4-2.600" fill="none" stroke="#fff6" stroke-width="1.200" stroke-linecap="round"/>',
  food: '<path d="M2.500 14.500c0-4.600 4.200-7.700 9.500-7.700s9.500 3.100 9.500 7.700c0 2.300-1.700 3.700-4 3.700h-11c-2.300 0-4-1.400-4-3.700z"/><path d="M7.300 9.300l2.100 3.700M11.600 8.300l1.400 4.200M16 9l.7 3.700" stroke="#0009" stroke-width="1.500" stroke-linecap="round" fill="none"/><path d="M3.300 15.800c2.400 1.500 15 1.500 17.400 0" stroke="#0006" stroke-width="1.200" fill="none"/><path d="M5 12c1-2 3-3.300 5.500-3.800" stroke="#fff5" stroke-width="1.100" stroke-linecap="round" fill="none"/>',
  men: '<path d="M13.500 20.500c0-3.300 1.900-5.300 4.400-5.300s4.600 2 4.600 5.300z" opacity=".7"/><path d="M15.200 11.400c0-1.900 1.200-3.200 2.800-3.200s2.800 1.300 2.800 3.200v.9h-5.600z" opacity=".7"/><circle cx="18" cy="12.600" r="2.300" opacity=".7"/><path d="M1.500 20.500c0-4.200 2.800-6.800 6.500-6.800s6.500 2.600 6.500 6.800z"/><circle cx="8" cy="10.300" r="3.200"/><path d="M4.300 9.300c0-2.800 1.600-4.600 3.700-4.600s3.700 1.800 3.700 4.600v.7H4.300z"/><path d="M4 9.400h8v1.200H4zM7.400 10.400h1.200v3H7.400z" fill="#0009"/><path d="M5.400 16.500l2.600 2.200 2.600-2.200" stroke="#0007" stroke-width="1" fill="none"/>',
  sword: '<g transform="rotate(45 12 12)"><path d="M12 .5l1.900 2.700v12.300h-3.800V3.200z"/><path d="M12 3.200v11.800" stroke="#0007" stroke-width=".9"/><path d="M12 .5l1.900 2.700v12.300H12z" fill="#0003"/><path d="M6.500 15.300h11c.6 0 .9.400.9 1s-.3 1-.9 1h-11c-.6 0-.9-.4-.9-1s.3-1 .9-1z"/><path d="M10.900 17.300h2.200v4h-2.200z"/><path d="M10.900 18.300h2.200M10.900 19.600h2.200" stroke="#0008" stroke-width=".7"/><circle cx="12" cy="22.400" r="1.600"/></g>',
  helm: '<path d="M4.500 14.200c0-6.300 3-10.700 7.500-10.700s7.500 4.400 7.500 10.700z"/><path d="M12 3.500c4.500 0 7.500 4.400 7.500 10.700h-4c0-5-1.200-8.700-3.500-10.700z" fill="#0003"/><path d="M12 3.500v10.700" stroke="#0007" stroke-width="1"/><path d="M3.400 14h17.200v2.600H3.400z"/><path d="M3.400 15.300h17.200" stroke="#0006" stroke-width=".7"/><circle cx="6.600" cy="14.800" r=".6" fill="#0009"/><circle cx="17.400" cy="14.800" r=".6" fill="#0009"/><path d="M10.800 16.600h2.400l-.3 5.200h-1.800z"/><path d="M4.800 16.600c0 3.200 1.300 4.900 3.300 5.400l.7-5.400zM19.200 16.600c0 3.200-1.300 4.900-3.300 5.400l-.7-5.400z" opacity=".8"/><path d="M7 8.500c.6-1.700 1.600-2.900 2.800-3.500" stroke="#fff6" stroke-width="1.100" stroke-linecap="round" fill="none"/>',
  heart: '<path d="M12 21C5 15.500 2.500 12 2.500 8.500A4.800 4.800 0 0 1 7.500 4c2 0 3.600 1.100 4.500 2.700C12.900 5.100 14.500 4 16.500 4a4.800 4.800 0 0 1 5 4.500C21.500 12 19 15.500 12 21z"/><path d="M12 6.700C12.900 5.100 14.500 4 16.500 4a4.800 4.800 0 0 1 5 4.500C21.500 12 19 15.500 12 21z" fill="#0003"/><path d="M5 8.600c0-1.500 1-2.500 2.400-2.600" stroke="#fff7" stroke-width="1.300" stroke-linecap="round" fill="none"/>',
  hourglass: '<path d="M5 1.800h14v2.400H5zM5 19.800h14v2.400H5z"/><path d="M7 4.200h10v1.600c0 2.600-2.600 4.400-3.600 6.200 1 1.800 3.600 3.600 3.600 6.200v1.600H7v-1.600c0-2.600 2.600-4.400 3.600-6.200C9.600 10.200 7 8.400 7 5.800z" opacity=".55"/><path d="M8.600 6.800h6.800c-.6 1.700-2.400 2.900-3.400 4.400-1-1.500-2.800-2.700-3.400-4.400zM8.300 19.800c.3-1.900 2-2.900 3.700-4 1.700 1.100 3.400 2.100 3.700 4z"/><path d="M12 11.200v4.600" stroke="currentColor" stroke-width=".9"/>',
  flag: '<path d="M4.600 3h1.900v19H4.600z"/><circle cx="5.550" cy="2.200" r="1.400"/><path d="M6.500 4c3.300-1.500 6 1.500 9.500.2 1.500-.5 2.900-.9 4.500-.4l-2.700 4.200 2.700 4.400c-1.600-.5-3 0-4.500.5-3.500 1.200-6.200-1.700-9.500-.3z"/><path d="M11 6.200l2.200 2.300L11 10.800 8.800 8.500z" fill="#0008"/><path d="M6.500 12.600c3.300-1.400 6 1.500 9.500.3" stroke="#0006" stroke-width="1" fill="none"/>',
  skull: '<path d="M12 2C7 2 3.800 5.400 3.800 10c0 2.500 1 4.300 2.700 5.300V18.500h11V15.300c1.700-1 2.700-2.800 2.700-5.300 0-4.600-3.200-8-8.200-8z"/><path d="M7 18.500h10v2.300c0 .7-.5 1.200-1.200 1.200H8.200c-.7 0-1.200-.5-1.200-1.200z"/><ellipse cx="8.400" cy="10.800" rx="2.300" ry="2.500" fill="#000b"/><ellipse cx="15.600" cy="10.800" rx="2.300" ry="2.500" fill="#000b"/><path d="M12 13l1.300 2.600h-2.600z" fill="#000b"/><path d="M9.500 18.300v3.500M12 18.300v3.500M14.500 18.300v3.500M6.600 18.500h10.800" stroke="#000a" stroke-width=".9"/><path d="M6.200 7.600C7 5.400 8.800 4 11 3.700" stroke="#fff5" stroke-width="1.100" stroke-linecap="round" fill="none"/>',
  gear: '<path d="M12 8.500a3.500 3.500 0 1 0 0 7 3.500 3.500 0 0 0 0-7zM10.500 2h3l.5 2.600 1.800.8 2.200-1.500 2.100 2.100-1.500 2.200.8 1.800L22 10.500v3l-2.600.5-.8 1.800 1.500 2.200-2.100 2.100-2.200-1.500-1.800.8-.5 2.600h-3l-.5-2.600-1.800-.8-2.200 1.500-2.100-2.100 1.500-2.200-.8-1.800L2 13.500v-3l2.600-.5.8-1.800-1.500-2.200L6 3.900l2.200 1.500 1.800-.8z"/>',
  pause: '<path d="M6 4h4v16H6zm8 0h4v16h-4z"/>', play: '<path d="M7 4l13 8-13 8z"/>',
  book: '<path d="M4 4.500A2.500 2.500 0 0 1 6.500 2H19v16H6.500A2.500 2.500 0 0 0 4 20.500z"/><path d="M4 20.500A2.500 2.500 0 0 1 6.500 18H20v4H6.500A2.500 2.500 0 0 1 4 20.500z" opacity=".6"/><path d="M6.800 2v16" stroke="#0008" stroke-width="1"/><path d="M12.800 6.200l2.700 3.300-2.700 3.300-2.700-3.300z" fill="#0008"/><path d="M6.600 19.400h12.700M6.600 20.800h12.700" stroke="#0007" stroke-width=".7"/><path d="M19 8.500h2v3h-2z"/>',
  shield: '<path d="M12 1.800l8.200 2.800v6.200c0 5.300-3.500 9.300-8.200 11.400-4.700-2.100-8.200-6.100-8.200-11.400V4.600z"/><path d="M12 1.800l8.200 2.800v6.200c0 5.300-3.500 9.300-8.200 11.400z" fill="#0003"/><path d="M12 4.300l5.800 2v4.600c0 3.900-2.400 6.900-5.800 8.700-3.400-1.800-5.800-4.800-5.800-8.700V6.300z" fill="none" stroke="#0007" stroke-width="1"/><circle cx="12" cy="11" r="2.200" fill="#0008"/><circle cx="12" cy="11" r="1" />',
  hold: '<path d="M12 1.800l8.200 2.800v6.200c0 5.300-3.500 9.300-8.200 11.400-4.700-2.100-8.200-6.100-8.200-11.400V4.600z"/><path d="M12 1.800l8.200 2.800v6.200c0 5.300-3.500 9.300-8.200 11.400z" fill="#0003"/><path d="M7.800 11.800l3 3.100 5.400-6.400" fill="none" stroke="#000b" stroke-width="2.300" stroke-linecap="round" stroke-linejoin="round"/>',
  follow: '<path d="M12 3l7 9h-4.500v9h-5v-9H5z"/>',
  charge: '<path d="M2 11h12V6l8 6-8 6v-5H2z"/>',
  back: '<path d="M22 11H10V6L2 12l8 6v-5h12z"/>',
  retreat: '<path d="M4 3h11v4h-2V5H6v14h7v-2h2v4H4zm12 4l5 5-5 5v-3h-6v-4h6z"/>',
  zoom: '<circle cx="10" cy="10" r="6" fill="none" stroke="currentColor" stroke-width="2.400"/><path d="M15 15l6 6" stroke="currentColor" stroke-width="3"/>',
  snd: '<path d="M3 9h4l5-4v14l-5-4H3zm13-1c2 1.500 2 6.500 0 8m3-11c4 3 4 11 0 14" fill="none" stroke="currentColor" stroke-width="2"/>',
  bag: '<path d="M8.200 7.500C5 9.500 3.200 13 3.200 16.500c0 3.500 2.500 5.500 8.800 5.500s8.800-2 8.800-5.500c0-3.500-1.800-7-5-9z"/><path d="M15.800 7.500c3.200 2 5 5.500 5 9 0 3.500-2.500 5.500-8.800 5.500z" fill="#0003"/><path d="M8.700 3.300c1-1.300 2.100-.3 3.300-.3s2.300-1 3.300.3L14.200 6.500H9.800z"/><path d="M7.800 6.300h8.400v1.900H7.800z" fill="#000a"/><path d="M14.500 7.800c1.500 1.300 1.700 3 1 4.200" stroke="#000a" stroke-width="1" fill="none"/><path d="M9.500 14.500l2.500-2.300 2.500 2.300-2.500 2.300z" fill="#0007"/>',
  horse: '<path d="M5.500 22c-.3-4.500.6-8 2.900-10.600L7.300 6.700l3 1.500c1.300-1.400 2.900-2.300 4.900-2.600l1-3.100 1.500 3.300c2.600 1.900 3.600 5 3.800 8.700l-2.300 2.200-2.100-.5-2.200-3.300c-1 2.700-.8 5.700 0 9.100z"/><path d="M7.300 6.700c-1 2.600-2.300 5.500-2.900 8.800-.3 2-.2 4.100.4 6.500h.7c-.3-4.500.6-8 2.900-10.600z" fill="#0005"/><circle cx="16.800" cy="9.400" r=".9" fill="#000b"/><path d="M20.300 14.200l-.9.9" stroke="#000a" stroke-width="1"/><path d="M14 13c-1.600.5-3 .4-4.300-.3" stroke="#0007" stroke-width="1" fill="none"/>',
  bow: '<path d="M7 2c1 .2 2 .7 2.800 1.500 4.800 4.700 4.800 12.300 0 17C9 21.300 8 21.800 7 22l-.5-1.500c.7-.2 1.300-.5 1.800-1 4-4 4-11 0-15-.5-.5-1.100-.8-1.800-1z"/><path d="M6.800 2.700v18.600" stroke="currentColor" stroke-width=".9" fill="none"/><path d="M3 11.300h13.500v1.400H3z"/><path d="M16 9l5.500 3-5.500 3 1.300-3z"/><path d="M3 12l2.500-2.300v4.600z"/>',
  tent: '<path d="M12 4L2 20h20z"/><path d="M12 4l10 16h-6z" fill="#0004"/><path d="M12 11l-3 9h6z" fill="#000b"/><path d="M11.400 1h1.200v4h-1.200z"/><path d="M12.600 1l4.400 1.500-4.400 1.500z"/><path d="M12 4L2 20" stroke="#fff4" stroke-width=".9" fill="none"/>'
};
const ic = (n, s) => '<svg class="ico" viewBox="0 0 24 24"' + (s ? ' style="width:' + s + 'px;height:' + s + 'px"' : '') + '>' + (ICONS[n] || '') + '</svg>';
const CLS = { inf: 'Пехота', spr: 'Копейщик', arc: 'Стрелок', cav: 'Кавалерия', har: 'Конный стрелок' };
const KIND = { town: 'Город', castle: 'Замок', village: 'Деревня', camp: 'Логово разбойников' };
const FEAT = ['inf', 'arc', 'cav'];
const crestCache = {}; const crestURL = f => { const k = f + FACTIONS[f].c1; return crestCache[k] || (crestCache[k] = crestCanvas(f, 96).toDataURL()); };
function toast(s) { const o = document.createElement('div'); o.id = 'toast'; o.className = 'plank'; o.textContent = s; document.body.appendChild(o); setTimeout(() => o.remove(), 2200); }
function troopStats(t) { return 'здор. ' + t.hp + ' · урон ' + t.dmg + ' · броня ' + t.arm + (t.range ? ' · дальн.' : '') + (t.anticav ? ' · против конницы' : ''); }
function troopRow(s, extra) { const t = TROOPS[s.type]; return '<div class="row"><img alt="" src="' + portrait(s.type, 'player') + '"><div class="grow"><div class="nm">' + t.name + '</div><div class="ds"><span class="tag">Ур. ' + t.tier + '</span>' + CLS[t.cls] + ' · ' + troopStats(t) + '</div></div>' + (extra || '') + '</div>'; }

let UI = { open: null, town: null, enc: null, tab: 'troops' };
function openModal(html, cls) { const m = el('modal'); m.innerHTML = '<div class="win plank ' + (cls || '') + '">' + html + '</div>'; m.hidden = false; UI.open = true; m.scrollTop = 0; }
function closeModal() { if (NET.on && G && G.player && G.player.in) NET.send({ t: 'leave' }); el('modal').hidden = true; el('modal').innerHTML = ''; UI.open = false; UI.town = null; UI.enc = null; UI.panel = null; UI.res = null; UI.back = null; UI.isel = null; UI.tsel = null; UI.who = null; UI.cfire = null; if (G && G.player) G.player.in = null; }
function mmode() { return MODE; }

/* ---------- город ---------- */
function openTown(s) {
  if (NET.on) { NET.send({ t: 'enter', id: s.id }); return; }
  if (settleHostile(s, G.player)) { G.player.path = []; if (s.kind === 'village') toast(s.name + ': жители заперлись — ' + FACTIONS[s.fac].name + ' враждебен тебе.'); else openSiege(s); return; }
  const P = G.player; townEnter(P, s); G.wait = false; UI.town = { s, tab: 'recruit' }; sfx('click'); renderTown(); saveGame(true);
}
function renderTown() {
  const { s, tab } = UI.town, P = G.player, H = P.hero, f = FACTIONS[s.fac], cap = sizeCap(H), cnt = troopCount(P.troops);
  let body = '';
  if (tab === 'recruit') {
    body += '<div class="note">В отряде ' + cnt + ' из ' + cap + ' бойцов. Свободных рекрутов: ' + troopCount(s.recruits) + '. Новые люди приходят каждые три дня.</div>';
    if (!s.recruits.length) body += '<div class="note">Сегодня здесь никто не хочет воевать.</div>';
    for (const r of s.recruits) { const t = TROOPS[r.type], hc = hireCost(P, r.type), ok = P.gold >= hc && cnt < cap; body += troopRow(r, '<div class="cnt">' + r.n + '</div><div class="acts"><span class="price ' + (P.gold < hc ? 'no' : '') + '">' + ic('coin') + hc + '</span><button class="btn sm" data-act="hire" data-t="' + r.type + '" data-n="1" ' + (ok ? '' : 'disabled') + '>Нанять</button><button class="btn sm" data-act="hire" data-t="' + r.type + '" data-n="99" ' + (ok ? '' : 'disabled') + '>Всех</button></div>'); }
    body += '<div class="card" style="margin-top:10px"><h3>Отдых</h3><p class="note">Восемь часов в таверне: герой залечивает раны. Отряд за это время ест.</p><button class="btn sm" data-act="rest">Отдохнуть</button></div>';
  } else if (tab === 'trade') {
    body += tradeBody(s);
  } else if (tab === 'garrison') {
    const g = garrisonOf(s); body += '<div class="note">Гарнизон защищает владение, пока тебя нет: враждебные лорды могут прийти и взять его штурмом. Против лорда в 160–190 бойцов нужно около 110 человек. В гарнизоне ' + troopCount(g) + ' бойцов, в отряде ' + cnt + ' из ' + cap + '.</div>' + garMoney(s, P) + '<h3 style="margin:10px 0 6px">В гарнизоне</h3>';
    if (!g.length) body += '<div class="note">Пусто. Оставь здесь бойцов из отряда.</div>';
    for (const t of g) body += troopRow(t, '<div class="cnt">' + t.n + '</div><div class="acts"><button class="btn sm" data-act="gar" data-t="' + t.type + '" data-n="1" ' + (cnt < cap ? '' : 'disabled') + '>Забрать</button><button class="btn sm" data-act="gar" data-t="' + t.type + '" data-n="99" ' + (cnt < cap ? '' : 'disabled') + '>Всех</button></div>');
    body += '<h3 style="margin:14px 0 6px">Твой отряд</h3>';
    for (const t of P.troops) body += troopRow(t, '<div class="cnt">' + t.n + '</div><div class="acts"><button class="btn sm" data-act="gar" data-t="' + t.type + '" data-n="1" data-to="1" ' + (cnt > 1 ? '' : 'disabled') + '>Оставить</button><button class="btn sm" data-act="gar" data-t="' + t.type + '" data-n="99" data-to="1" ' + (cnt > 1 ? '' : 'disabled') + '>Всех</button></div>');
  } else if (tab === 'oath') {
    body += oathBody(s);
  } else if (tab === 'tavern') {
    body += tavernBody(s);
  } else if (tab === 'quests') {
    const bd = s.board || []; body += '<div class="note">Заказы города. Награду выплачивают сразу, как дело сделано.</div>';
    if (!bd.length) body += '<div class="note">Доска пуста.</div>';
    for (const q of bd) body += '<div class="row"><div class="grow"><div class="nm">' + questText(q) + '</div><div class="ds">Срок: до дня ' + q.dl + ' · ' + questDetail(q, s) + '</div></div><span class="price">' + ic('coin') + q.reward + '</span><button class="btn sm" data-act="accept" data-q="' + q.id + '">Взять</button></div>';
    if (G.player.quests.length) { body += '<h3 style="margin:14px 0 6px">Твои задания</h3>'; for (const q of G.player.quests) body += '<div class="row"><div class="grow"><div class="nm">' + questText(q) + '</div><div class="ds">До дня ' + q.dl + '</div></div><span class="price">' + ic('coin') + q.reward + '</span></div>'; }
  }
  const mine = s.fac === 'player', tabs = [['recruit', 'Рекруты'], ['trade', 'Рынок']].concat(s.kind === 'town' && !NET.on ? [['tavern', 'Таверна']] : [], s.kind === 'town' && !NET.on && REAL_F.includes(s.fac) && typeof oathBody === 'function' ? [['oath', 'Служба']] : [], mine ? [['garrison', 'Гарнизон']] : [['quests', 'Задания']]), canSiege = !mine && !NET.on && REAL_F.includes(s.fac) && (s.kind === 'town' || s.kind === 'castle');
  openModal('<div class="whead"><img alt="" src="' + crestURL(s.fac) + '"><h2>' + s.name + '<span class="sub">' + KIND[s.kind] + ' · ' + (mine ? 'твоё владение · доход ' + settleIncome(s) + ', гарнизон ' + troopCount(garrisonOf(s)) + ' (−' + garUp(s, P) + ')/день' : f.gen + ' · отношение: ' + relName(G.player.rel[s.fac])) + '</span></h2><span class="stat">' + ic('coin') + fmt(P.gold) + '</span></div><div class="tabs">' + tabs.map(t => '<button class="tab ' + (t[0] === tab ? 'on' : '') + '" data-act="ttab" data-t="' + t[0] + '">' + t[1] + '</button>').join('') + '</div><div class="wbody">' + body + '</div>' + (tab === 'trade' ? tradeDock(s) : '') + '<div class="wfoot">' + (canSiege ? '<button class="btn danger" data-act="siegeask" style="margin-right:auto">Осадить</button>' : '') + '<button class="btn" data-act="party">Отряд</button><button class="btn pri" data-act="leave">Покинуть ' + (s.kind === 'town' ? 'город' : s.kind === 'castle' ? 'замок' : 'деревню') + '</button></div>');
}

const garUp = (s, P) => Math.round(garUpkeep(s) * (1 - perkFx(P.hero).wage));
function garMoney(s, P) { const inc = settleIncome(s), up = garUp(s, P), nv = settleVillages(s), net = inc - up; return '<div class="cols"><div class="card"><h3>Казна владения</h3><div class="kv"><span>' + (s.kind === 'town' ? 'Город' : 'Замок') + '</span><b>+' + (inc - nv * INC_VILLAGE) + '</b></div><div class="kv"><span>Подати с деревень (' + nv + ')</span><b>+' + nv * INC_VILLAGE + '</b></div><div class="kv"><span>Жалованье гарнизона (половина полевого)</span><b class="dn">−' + up + '</b></div><div class="kv"><span>Итого в день</span><b class="' + (net >= 0 ? 'up' : 'dn') + '">' + (net >= 0 ? '+' : '') + net + '</b></div></div></div>'; }

/* ---------- отряд и герой ---------- */
function openPanel(tab) { UI.panel = tab || UI.panel || 'troops'; renderPanel(); }
function renderPanel() {
  const P = G.player, H = P.hero, tab = UI.panel, cap = sizeCap(H), cnt = troopCount(P.troops); let body = '';
  if (tab === 'troops') {
    body += '<div class="note">Бойцов: ' + cnt + ' из ' + cap + ' · Жалованье: ' + wageDay(G.player) + ' в день · Улучшение стоит золота, но делает бойца сильнее.</div>';
    sortT(P.troops); if (!P.troops.length) body += '<div class="note">У тебя нет отряда. Найми людей в городе.</div>';
    for (const s of P.troops) { const t = TROOPS[s.type]; let acts = ''; for (const u of t.up) { const ut = TROOPS[u], c = upgCost(P, s.type); acts += '<button class="btn sm" data-act="upg" data-t="' + s.type + '" data-u="' + u + '" ' + (P.gold >= c ? '' : 'disabled') + '>В ' + ut.name.toLowerCase() + ' (' + c + ')</button>'; } acts += '<button class="btn sm danger" data-act="dismiss" data-t="' + s.type + '">Распустить</button>';
      body += troopRow(s, '<div class="cnt">' + s.n + '</div><div class="acts">' + acts + '</div>'); }
  } else if (tab === 'hero') {
    body += heroBody();
  } else if (tab === 'comps') {
    body += compsBody();
  } else if (tab === 'ally') {
    body += allyBody();
  } else if (tab === 'inv') {
    body += invBody();
  } else if (tab === 'journal') {
    body += '<h3>Задания</h3>'; if (!G.player.quests.length) body += '<div class="note">Нет активных заданий. Загляни на доску в городе.</div>'; for (const q of G.player.quests) { const s = settleById(q.sid); body += '<div class="row"><div class="grow"><div class="nm">' + questText(q) + '</div><div class="ds">Заказчик: ' + FACTIONS[q.fac].name + ' · срок: день ' + q.dl + '</div></div><span class="price">' + ic('coin') + q.reward + '</span></div>'; }
    body += '<h3 style="margin-top:14px">Отношения</h3><div class="cols">' + worldF().map(f => '<div class="card' + (relHostile(G.player, f) ? ' hostile' : '') + '"><h3>' + FACTIONS[f].name + (relHostile(G.player, f) ? ' <span class="tag r">враг</span>' : '') + '</h3><div class="kv"><span>Отношение</span><b' + (relHostile(G.player, f) ? ' class="dn"' : '') + '>' + relName(G.player.rel[f]) + ' (' + Math.round(G.player.rel[f]) + ')</b></div><div class="kv"><span>Воюет с</span><b>' + (worldF().filter(o => atWar(f, o)).map(o => FACTIONS[o].name).join(', ') || 'ни с кем') + '</b></div>' + (typeof holdOf === 'function' ? '<div class="kv"><span>Владения</span><b>' + (facAlive(f) ? holdOf(f).all : 'государство пало') + '</b></div>' : '') + (G.player.liege === f ? '<div class="kv"><span>Сюзерен</span><b class="up">ты на службе</b></div>' : '') + '</div>').join('') + '</div>' +
      '<h3 style="margin-top:14px">Хроника</h3>' + G.player.log.slice(-12).reverse().map(l => '<div class="kv"><span>День ' + l.d + '</span><b style="font-weight:500;text-align:right">' + l.txt + '</b></div>').join('');
  }
  const tabs = [['troops', 'Отряд'], ['hero', 'Герой'], ['inv', 'Обоз'], ['journal', 'Журнал']]; if (!NET.on && (P.comps || []).length) tabs.splice(1, 0, ['comps', 'Спутники']); if (NET.on) tabs.push(['ally', 'Союз']);
  openModal('<div class="whead"><img alt="" src="' + crestURL('player') + '"><h2>' + P.name + '<span class="sub">Уровень ' + H.lvl + ' · ' + fmt(P.gold) + ' золота · провизии ' + provOf(P) + '</span></h2></div><div class="tabs">' + tabs.map(t => '<button class="tab ' + (t[0] === tab ? 'on' : '') + '" data-act="ptab" data-t="' + t[0] + '">' + t[1] + '</button>').join('') + '</div><div class="wbody">' + body + '</div>' + (tab === 'inv' ? invDock() : '') + '<div class="wfoot"><button class="btn pri" data-act="closepanel">Закрыть</button></div>', 'wide');
}

/* ---------- встреча ---------- */
function relativePowerOld(p) { const a = strength(G.player.troops) + 8, b = partyStr(p); const r = a / Math.max(1, b); return r > 2 ? ['Мы сильнее', 'g'] : r > 1.15 ? ['Мы чуть сильнее', 'g'] : r > .8 ? ['Силы равны', 'b'] : r > .45 ? ['Они сильнее', 'r'] : ['Они намного сильнее', 'r']; }
function openEncounter(p, forced) {
  const hostileP = isHostileToPlayer(p, G.player) || p.kind === 'camp'; UI.enc = { p, forced, hostile: hostileP }; G.player.path = []; G.player.tid = null; G.wait = false;
  const pw = relativePowerOf(G.player, p), list = p.troops.slice().sort((a, b) => TROOPS[b.type].tier - TROOPS[a.type].tier);
  const title = p.kind === 'camp' ? (p.fac === 'undead' ? 'Чёрный курган' : 'Логово разбойников') : p.kind === 'caravan' ? 'Караван' : p.kind === 'bandit' ? 'Разбойники' : p.name;
  let btns;
  if (hostileP) btns = '<button class="btn" data-act="flee">Бежать</button><button class="btn" data-act="auto">Рассчитать бой</button><button class="btn pri" data-act="fight">В бой!</button>';
  else btns = '<button class="btn pri" data-act="greet">Разойтись с миром</button><button class="btn danger" data-act="attack">Напасть</button>';
  openModal('<div class="whead"><img alt="" src="' + crestURL(p.fac) + '"><h2>' + title + '<span class="sub">' + FACTIONS[p.fac].name + ' · ' + troopCount(p.troops) + ' бойцов</span></h2><span class="tag ' + pw[1] + '">' + pw[0] + '</span></div><div class="wbody"><div class="note">' + (hostileP ? (forced ? 'Они заметили тебя и идут в атаку.' : 'Ты настиг врага.') : 'Они не враждуют с тобой. Нападение испортит отношения с ' + FACTIONS[p.fac].gen + '.') + '</div>' +
    list.map(s => troopRow(s, '<div class="cnt">' + s.n + '</div>')).join('') + '</div><div class="wfoot">' + btns + '</div>', 'narrow');
}

/* ---------- действия по клику ---------- */
const ACT = {
  gore() { GORE.on = !GORE.on; try { localStorage.setItem('zs-gore', GORE.on ? '1' : '0'); } catch (e) { } openMenu(); },
  gar(d) { const s = UI.town && UI.town.s, n = garMove(G.player, s, d.t, +d.n, d.to === '1'); if (n) { sfx('click'); renderTown(); } },
  siegeask() { const s = UI.town.s; openModal('<div class="whead"><img alt="" src="' + crestURL(s.fac) + '"><h2>Осадить ' + s.name + '?<span class="sub">Это объявление войны</span></h2></div><div class="wbody"><div class="note">Отношения с ' + FACTIONS[s.fac].gen + ' станут враждебными: их лорды начнут охотиться за тобой, ворота их городов закроются.</div></div><div class="wfoot"><button class="btn" data-act="siegeno" data-s="' + s.id + '">Передумал</button><button class="btn danger" data-act="siegeyes" data-s="' + s.id + '">Объявить войну</button></div>', 'narrow'); },
  siegeno(d) { openTown(settleById(+d.s)); },
  siegeyes(d) { const s = settleById(+d.s); declareWar(G.player, s.fac); openSiege(s); },
  siegeatk() { const p = UI.siege.p; closeModal(); launchSiege(p); },
  siegeauto() { const p = UI.siege.p; closeModal(); battleEnded(autoResult(G.player, p), p); },
  siegeoff() { closeModal(); },
  ttab(d) { UI.town.tab = d.t; renderTown(); },
  leave() { closeModal(); },
  hire(d) { if (NET.on) { NET.send({ t: 'hire', type: d.t, n: +d.n }); sfx('coin'); return; } if (doHire(G.player, UI.town.s, d.t, +d.n)) { sfx('coin'); renderTown(); } },
  buygear(d) { if (NET.on) { NET.send({ t: 'gear', k: d.k }); sfx('coin'); return; } if (doGear(G.player, d.k)) { sfx('coin'); renderTown(); } },
  food(d) { if (NET.on) { NET.send({ t: 'food', n: +d.n, p: +d.p }); sfx('coin'); return; } if (doFood(G.player, +d.n, +d.p)) { sfx('coin'); renderTown(); } },
  rest() { if (NET.on) { toast('В сетевой игре отдых недоступен'); return; } const P = G.player; for (let i = 0; i < 8; i++) { stepWorld(1); hourTick(); } sfx('click'); toast('Ты отдохнул. Герой здоров на ' + Math.round(P.hero.hp * 100) + '%'); renderTown(); },
  accept(d) { if (NET.on) { NET.send({ t: 'accept', q: +d.q }); sfx('order'); return; } const r = doAccept(G.player, UI.town.s, +d.q); if (r) toast(r); else sfx('order'); renderTown(); },
  party() { const back = UI.town; UI.back = back; openPanel('troops'); },
  hero() { openPanel('hero'); }, journal() { openPanel('journal'); },
  ptab(d) { UI.panel = d.t; renderPanel(); },
  closepanel() { if (UI.back) { const b = UI.back; UI.back = null; UI.panel = null; UI.town = b; G.player.in = b.s.id; renderTown(); } else closeModal(); },
  upg(d) { if (NET.on) { NET.send({ t: 'upg', type: d.t, up: d.u }); sfx('coin'); return; } const n = doUpgrade(G.player, d.t, d.u); if (n) { sfx('coin'); toast(n + ' × ' + TROOPS[d.u].name); } renderPanel(); },
  dismiss(d) { if (NET.on) { NET.send({ t: 'dismiss', type: d.t }); return; } remT(G.player.troops, d.t, 1); renderPanel(); },
  attr(d) { if (NET.on) { NET.send({ t: 'attr', k: d.k }); sfx('order'); return; } if (doAttr(G.player, d.k)) { sfx('order'); keepScroll(renderPanel); } },
  menu() { openMenu(); },
  greet() { if (NET.on) { NET.send({ t: 'enc', a: 'greet' }); closeModal(); return; } const p = UI.enc.p; p.cd = 3; closeModal(); },
  attack() { if (NET.on) { NET.send({ t: 'enc', a: 'attack' }); closeModal(); return; } const e = UI.enc; encAttack(G.player, e.p); e.hostile = true; ACT.fight(); },
  fight() { if (NET.on) { NET.send({ t: 'enc', a: 'fight' }); closeModal(); return; } const p = UI.enc.p; closeModal(); launchBattle(p); },
  auto() { if (NET.on) { NET.send({ t: 'enc', a: 'auto' }); closeModal(); return; } const p = UI.enc.p; closeModal(); autoPlayer(p); },
  flee() { if (NET.on) { NET.send({ t: 'enc', a: 'flee' }); closeModal(); return; } const p = UI.enc.p; if (encFlee(G.player, p)) { closeModal(); toast('Ты оторвался от погони'); } else { toast('Не вышло уйти!'); closeModal(); launchBattle(p); } },
  resume() { closeModal(); }, save() { saveGame(); toast('Игра сохранена'); },
  snd() { auSetOn(!AU.on); openMenu(); }, mus() { auSetMusic(!AU.music); openMenu(); },
  tomenu(d) {
    if (NET.on) { netLeave(); closeModal(); gotoTitle(); return; }
    // из идущего боя — только после подтверждения: бой не сохраняется
    if (MODE === 'battle' && B && !B.cfg.demo && !B.cfg.quick && !B.over && !(d && d.ok)) { openModal('<div class="whead"><h2>Выйти из боя?<span class="sub">Бой не сохраняется. При «Продолжить» ты вернёшься к моменту перед этим боем.</span></h2></div><div class="wfoot"><button class="btn" data-act="resume">Остаться</button><button class="btn danger" data-act="tomenu" data-ok="1">Выйти в меню</button></div>', 'narrow'); return; }
    if (MODE === 'world' && G) { saveGame(true); toast('Игра сохранена'); } // карта: сохраняем перед выходом, чтобы не терять прогресс
    closeModal(); gotoTitle();
  },
  newgame() { CR.mp = false; openCreate(); }, mp() { CR.mp = true; openCreate(); },
  mpgo() { const rep = el('crrep') ? el('crrep').checked : false, nm = (el('crname') ? el('crname').value : CR.name).trim() || 'Безымянный', code = el('crcode') ? el('crcode').value.trim() : ''; try { localStorage.setItem('zs-mp', JSON.stringify({ name: nm, code })); } catch (e) { } closeModal(); netStart({ name: nm, code, banner: CR.banner, culture: CR.culture, replace: rep }); },
  vyes() { NET.send({ t: 'vote', yes: 1 }); }, vno() { NET.send({ t: 'vote', yes: 0 }); }, cont() { loadGame(); }, quick() { openQuick(); },
  pickb(d) { CR.banner = +d.i; renderCreate(); }, pickc(d) { CR.culture = d.c; renderCreate(); },
  begin() { const nm = (el('crname') ? el('crname').value : CR.name).trim() || 'Безымянный'; closeModal(); startNew({ name: nm, banner: CR.banner, culture: CR.culture }); },
  qpick(d) { QK[d.k] = d.k === 'size' ? +d.v : d.v; renderQuick(); }, qgo() { closeModal(); startQuick(); },
  again() { closeModal(); startQuick(); }, endq() { closeModal(); gotoTitle(); },
  help() { openModal('<div class="whead"><h2>Как играть<span class="sub">Игра только для компьютера: клавиатура и мышь</span></h2></div><div class="wbody"><div class="cols"><div class="card"><h3>Карта мира</h3><div class="kv"><span>Идти</span><b>клик</b></div><div class="kv"><span>Пауза</span><b>Пробел</b></div><div class="kv"><span>Ждать на месте</span><b>Z</b></div><div class="kv"><span>Отряд / герой / обоз / журнал</span><b>P / H / I / J</b></div><div class="kv"><span>Скорость</span><b>1, 2, 3</b></div><p class="note">Клик по лагерю или отряду начнёт погоню. Деньги уходят на жалованье, еду берут в городах.</p></div><div class="card"><h3>В бою</h3><div class="kv"><span>Движение</span><b>W A S D</b></div><div class="kv"><span>Удар</span><b>левая кнопка</b></div><div class="kv"><span>Блок щитом</span><b>правая кнопка</b></div><div class="kv"><span>Бег</span><b>Shift</b></div><div class="kv"><span>Сменить оружие</span><b>X</b></div><div class="kv"><span>Выбрать отряд</span><b>1 2 3 4</b></div><div class="kv"><span>Приказы</span><b>Q держать · E за мной · R атака · F отход</b></div><p class="note">Блок работает только по лицу. Удар в спину бьёт сильнее. Конница ломает строй на разгоне, копейщики её останавливают.</p></div></div></div><div class="wfoot"><button class="btn pri" data-act="tomenu">Понятно</button></div>'); },
  cont2() { closeModal(); afterBattle(); }
};
document.addEventListener('click', e => { const t = e.target.closest('[data-act]'); if (!t || t.disabled) return; auInit(); const a = t.dataset.act; if (ACT[a]) { ACT[a](t.dataset, t); } });

/* ---------- меню, создание, быстрый бой ---------- */
function openMenu() { openModal('<div class="whead"><h2>Пауза</h2></div><div class="wbody" style="display:flex;flex-direction:column;gap:10px"><button class="btn pri" data-act="resume">Продолжить</button>' + (MODE === 'world' && !NET.on ? '<button class="btn" data-act="save">Сохранить игру</button>' : '') + '<button class="btn" data-act="snd">Звук: ' + (AU.on ? 'включён' : 'выключен') + '</button><button class="btn" data-act="mus">Музыка: ' + (AU.music ? 'включена' : 'выключена') + '</button><button class="btn" data-act="gore">Расчленёнка: ' + (GORE.on ? 'включена' : 'выключена') + '</button><button class="btn danger" data-act="tomenu">В главное меню</button></div>', 'narrow'); }
let CR = { banner: 0, culture: 'nord', name: 'Ярослав', mp: false, code: '' }; try { const sv = JSON.parse(localStorage.getItem('zs-mp') || 'null'); if (sv) { CR.name = sv.name || CR.name; CR.code = sv.code || ''; } } catch (e) { }
function renderCreate() {
  const nm = el('crname') ? el('crname').value : CR.name; CR.name = nm; if (el('crcode')) CR.code = el('crcode').value; if (el('crrep')) CR.rep = el('crrep').checked;
  openModal('<div class="whead"><h2>Создай героя<span class="sub">Ты командир наёмного отряда без земли и титула</span></h2></div><div class="wbody"><div class="note">Имя</div><input type="text" id="crname" maxlength="18" value="' + CR.name.replace(/"/g, '') + '" autocomplete="off">' + (CR.mp ? '<div class="note" style="margin-top:14px">Код комнаты (если задан на сервере)</div><input type="text" id="crcode" maxlength="40" value="' + (CR.code || '').replace(/"/g, '') + '" autocomplete="off"><label class="note" style="display:block;margin-top:10px"><input type="checkbox" id="crrep"' + (CR.rep ? ' checked' : '') + '> Если в мире уже двое — заменить того, кто сейчас не в игре (его персонаж удалится)</label>' : '') + '<div class="note" style="margin-top:14px">Цвета твоего стяга</div><div style="display:flex;gap:10px;flex-wrap:wrap">' + BANNERS.map((b, i) => '<button class="sw ' + (i === CR.banner ? 'on' : '') + '" style="background:' + b.c1 + ';--c2:' + b.c2 + '" data-act="pickb" data-i="' + i + '" title="' + b.n + '" aria-label="' + b.n + '"></button>').join('') + '</div><div class="note" style="margin-top:14px">Откуда ты родом</div><div style="display:flex;gap:10px;flex-wrap:wrap">' +
    FAC_V[DEFAULT_MAPV].map(c => '<button class="cult ' + (c === CR.culture ? 'on' : '') + '" data-act="pickc" data-c="' + c + '"><h3>' + FACTIONS[c].name + '</h3><p>' + { nord: 'Крепкая пехота, секиры и щиты. Охотники-лучники.', emp: 'Броня, дисциплина и арбалеты. Дорогие, но стойкие бойцы.', khan: 'Быстрые всадники и конные лучники. Ты начинаешь верхом.', kin: 'Рыцарская конница, длинные луки и крепкие сержанты. Сильны в прямой схватке.', emi: 'Лёгкая конница, лучники и мамлюки. Быстрые, ты начинаешь верхом.' , dom: 'Стойкая лесная пехота, арбалеты и дружинная конница. Сильны в обороне и засадах.', pact: 'Тяжёлая конница гусар, ландскнехты и лучники. Мощный удар, дорогие бойцы.'}[c] + '</p></button>').join('') + '</div></div><div class="wfoot"><button class="btn" data-act="tomenu">Назад</button><button class="btn pri" data-act="' + (CR.mp ? 'mpgo' : 'begin') + '">' + (CR.mp ? 'В мир' : 'В путь') + '</button></div>');
}
function openCreate() { FACTIONS.player.c1 = BANNERS[CR.banner].c1; FACTIONS.player.c2 = BANNERS[CR.banner].c2; renderCreate(); }
let QK = { me: 'nord', foe: 'emp', size: 50 };
function renderQuick() {
  const pick = (k, arr) => '<div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:12px">' + arr.map(a => '<button class="btn sm ' + (QK[k] === a[0] ? 'pri' : '') + '" data-act="qpick" data-k="' + k + '" data-v="' + a[0] + '">' + a[1] + '</button>').join('') + '</div>';
  openModal('<div class="whead"><h2>Быстрый бой<span class="sub">Сразу на поле: ты ведёшь своего героя, остальные слушаются приказов</span></h2></div><div class="wbody"><div class="note">Твоя армия</div>' + pick('me', [['nord', 'Нордмарк'], ['emp', 'Империя'], ['khan', 'Ханство'], ['kin', 'Галлия'], ['emi', 'Эмират'], ['dom', 'Доминион'], ['pact', 'Пакт']]) + '<div class="note">Противник</div>' + pick('foe', [['nord', 'Нордмарк'], ['emp', 'Империя'], ['khan', 'Ханство'], ['kin', 'Галлия'], ['emi', 'Эмират'], ['dom', 'Доминион'], ['pact', 'Пакт'], ['bandit', 'Разбойники']]) + '<div class="note">Размер армий</div>' + pick('size', [[50, 'Отряд (50)'], [100, 'Войско (100)'], [200, 'Великая битва (200)']]) + '</div><div class="wfoot"><button class="btn" data-act="tomenu">Назад</button><button class="btn pri" data-act="qgo">В бой</button></div>', 'narrow');
}
function openQuick() { renderQuick(); }

/* ---------- осада ---------- */
function openSiege(s) {
  const P = G.player, p = siegeParty(s), pw = relativePowerOf(P, Object.assign({}, p, { troops: p.troops.map(t => ({ type: t.type, n: Math.round(t.n * 1.35) })) })); P.path = []; P.tid = null; G.wait = false;
  UI.siege = { s, p }; const n = troopCount(p.troops), list = p.troops.slice().sort((a, b) => TROOPS[b.type].tier - TROOPS[a.type].tier);
  openModal('<div class="whead"><img alt="" src="' + crestURL(s.fac) + '"><h2>Осада: ' + s.name + '<span class="sub">' + KIND[s.kind] + ' · ' + FACTIONS[s.fac].name + ' · ' + n + ' защитников' + (p.lord ? ' · в стенах ' + p.lord : '') + '</span></h2><span class="tag ' + pw[1] + '">' + pw[0] + '</span></div>' +
    '<div class="wbody"><div class="note">Ворота закрыты. Защитники держат проломы в стене, их стрелки бьют из-за зубцов. Если возьмёшь ' + (s.kind === 'town' ? 'город' : 'замок') + ', он станет твоим и будет приносить ' + settleIncome(s) + ' золота в день.</div>' +
    list.map(t => troopRow(t, '<div class="cnt">' + t.n + '</div>')).join('') + '</div><div class="wfoot"><button class="btn" data-act="siegeoff">Отойти</button><button class="btn" data-act="siegeauto">Рассчитать штурм</button><button class="btn danger" data-act="siegeatk">На штурм!</button></div>', 'narrow');
}
