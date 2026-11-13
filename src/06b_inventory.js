/* ================= инвентарь и торговля: интерфейс =================
   Окно «Обоз»: кукла героя со слотами по бокам, рюкзак сеткой плиток и карточка выбранной вещи внизу окна.
   Вкладка «Торговля»: те же плитки, цена на плитке, карточка внизу с кнопками. Двойной щелчок по плитке:
   надеть / снять, купить / продать одну штуку. Выбор хранится в UI.isel (обоз) и UI.tsel (торговля). */

/* ---------- иконки предметов ---------- */
// Силуэт красится цветом плитки (currentColor), правая половина притенена, детали — тёмной линией, блик — светлой.
const bodyBase = '<path d="M8.200 2.500l3.800 1.800 3.800-1.800 5.200 4-2.800 4.300-2.200-1.100v11.800H8.200V9.700L6 10.800 3.200 6.500z"/><path d="M12 4.300l3.800-1.800 5.200 4-2.800 4.300-2.200-1.100v11.800H12z" fill="#0003"/><path d="M9.500 3.200c.7 1.800 4.300 1.800 5 0" fill="none" stroke="#0009" stroke-width="1"/>';
const beltLn = '<path d="M8.200 15.400h7.600v1.800H8.200z" fill="#000a"/><path d="M11.200 15.100h1.600v2.400h-1.600z"/>';
const dotsAt = (xs, ys, r) => ys.map(y => xs.map(x => '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>').join('')).join('');
const arcsAt = (xs, ys, r) => '<path d="' + ys.map((y, k) => xs.map(x => 'M' + (x + (k % 2) * r - r).toFixed(1) + ' ' + y + 'a' + r + ' ' + r + ' 0 0 0 ' + (r * 2) + ' 0').join('')).join('') + '" fill="none" stroke="#0009" stroke-width=".8"/>';
const shaft = (y0, y1, w) => '<path d="M' + (12 - w / 2) + ' ' + y0 + 'h' + w + 'V' + y1 + 'h-' + w + 'z"/><path d="M12 ' + y0 + 'h' + (w / 2) + 'V' + y1 + 'H12z" fill="#0004"/>';
Object.assign(ICONS, {
  body: bodyBase + beltLn,
  hands: '<path d="M6.500 21.500v-4.200l-2.300-4.800c-.5-1.100 1-1.900 1.700-.9l1.600 2.300V5.300c0-1.400 2-1.400 2 0v5.200V3.500c0-1.400 2-1.400 2 0v7V4.300c0-1.400 2-1.400 2 0v6.500V6.300c0-1.400 2-1.400 2 0v9.200l-1.300 6z"/><path d="M13.500 3v18.500h4.700l1.300-6V6.300c0-1.400-2-1.400-2 0v4.500V4.300c0-1.400-2-1.400-2 0v6.200V3.500c0-.4-.2-.7-.4-.9z" fill="#0003"/><path d="M6.300 17.300h13.200M6.400 19.300h12.800" fill="none" stroke="#0009" stroke-width="1"/><path d="M9.500 11v3.500M11.500 11v3.500M13.500 11v3.500" fill="none" stroke="#0007" stroke-width=".8"/>',
  legs: '<path d="M8.500 2h7v10.800l5.200 3.200c.8.500 1.300 1.300 1.300 2.200v1.800H4.500v-3.500l4-2.700z"/><path d="M12 2h3.500v10.800l5.200 3.200c.8.500 1.300 1.300 1.300 2.200v1.800H12z" fill="#0003"/><path d="M4.500 20h17.500v2H4.500z" fill="#000b"/><path d="M8.500 4.800h7M8.500 6.200h7" fill="none" stroke="#0009" stroke-width=".9"/><path d="M9 12.800l6 1.700M10.500 14.800l-1.600 2.600" fill="none" stroke="#0008" stroke-width=".9" stroke-linecap="round"/><path d="M9.700 3.300v6" fill="none" stroke="#fff5" stroke-width="1" stroke-linecap="round"/>',
  // доспехи
  b_padded: bodyBase + '<path d="M10 5.300v16.200M12 4.800v16.700M14 5.300v16.200M8.200 12h7.600M8.200 18.500h7.600M5 5.300l2 3.800M19 5.300l-2 3.800" fill="none" stroke="#0008" stroke-width=".9"/>' + beltLn,
  b_mail: bodyBase + arcsAt([9.5, 11.5, 13.5, 15.5], [7, 8.500, 10, 11.500, 13, 14.500, 16, 17.500, 19, 20.500], .8) + arcsAt([5.5, 19.3], [6, 7.500, 9], .8) + '<path d="M8.200 20.300l1.200 1.200 1.300-1.200 1.300 1.200 1.300-1.200 1.300 1.200 1.200-1.200" fill="none" stroke="#000a" stroke-width="1"/>',
  b_scale: bodyBase + arcsAt([9.5, 12, 14.5], [7, 9.200, 11.400, 13.600, 15.800, 18, 20.200], 1.25) + '<path d="M4.800 5.800l2.400 4M19.200 5.800l-2.400 4" fill="none" stroke="#0008" stroke-width=".9"/>',
  b_plate: '<circle cx="5.300" cy="6.800" r="3.400"/><circle cx="18.700" cy="6.800" r="3.400"/><path d="M18.700 3.400a3.400 3.400 0 0 1 0 6.800z" fill="#0003"/><path d="M7.300 4.300c2-1.600 7.400-1.600 9.400 0l.9 6.700c0 2.300-.9 4.300-2.300 5.900H8.700c-1.400-1.600-2.300-3.600-2.300-5.900z"/><path d="M12 3.100c2 0 3.800.4 4.700 1.200l.9 6.700c0 2.300-.9 4.300-2.300 5.900H12z" fill="#0003"/><path d="M8.300 17.600h7.400l1.300 4.200H7z"/><path d="M7.800 19h8.400M7.400 20.400h9.200M12 4.800v12" fill="none" stroke="#0009" stroke-width=".9"/><path d="M9.300 4.200c.7 1.500 4.700 1.500 5.400 0" fill="none" stroke="#0009" stroke-width="1"/><path d="M8.600 7c.2 2.500.5 4.300 1.100 6" fill="none" stroke="#fff6" stroke-width="1.100" stroke-linecap="round"/><circle cx="5.300" cy="6.800" r=".7" fill="#000a"/><circle cx="18.700" cy="6.800" r=".7" fill="#000a"/>',
  b_habit: '<path d="M8.500 2.500c1.500 1.300 5.500 1.300 7 0l4.500 3.800-2 4-1.600-.8.900 12.500H6.700l.9-12.500-1.600.8-2-4z"/><path d="M12 3.400c1.400 0 2.800-.3 3.500-.9l4.500 3.800-2 4-1.600-.8.900 12.500H12z" fill="#0003"/><path d="M9.300 3c.8 2.300 1.700 3.400 2.700 3.800 1-.4 1.900-1.500 2.700-3.800" fill="none" stroke="#0009" stroke-width="1"/><path d="M7.400 13.300c3 .9 6.200.9 9.200 0" fill="none" stroke="#000b" stroke-width="1.300"/><path d="M14.300 13.900l.6 4.600M14.500 18.300l.9 1.500" fill="none" stroke="#000b" stroke-width="1" stroke-linecap="round"/><path d="M12 8v3.400M10.700 9.200h2.600" fill="none" stroke="#fff7" stroke-width="1"/><path d="M9 14.500l-.6 7.500M12 14.500V22" fill="none" stroke="#0006" stroke-width=".8"/>',
  // шлемы
  h_cap: '<path d="M4 15.500C4 9 7.300 4.500 12 4.500s8 4.500 8 11z"/><path d="M12 4.500c4.700 0 8 4.500 8 11h-8z" fill="#0003"/><path d="M3.500 15.500h17v2.300h-17z"/><path d="M12 4.500v11M8 5.800c-1 2.700-1.300 6-1.200 9.700M16 5.800c1 2.700 1.300 6 1.200 9.700" fill="none" stroke="#0008" stroke-width=".9" stroke-dasharray="1.400 1.200"/><path d="M5.500 17.800c0 2.200.8 3.300 2.200 4l.6-4zM18.500 17.800c0 2.200-.8 3.300-2.200 4l-.6-4z" opacity=".8"/><circle cx="12" cy="4.500" r="1.100"/>',
  h_nasal: ICONS.helm,
  h_kettle: '<path d="M6 12.500c0-4.800 2.500-8.300 6-8.300s6 3.500 6 8.300z"/><path d="M12 4.200c3.500 0 6 3.500 6 8.300h-6z" fill="#0003"/><path d="M1 12.300c3-1.300 19-1.300 22 0 .3 1.700-.5 3-2 3.700H3c-1.500-.7-2.300-2-2-3.700z"/><path d="M12 11.300c4 0 9 .3 11 1 .3 1.700-.5 3-2 3.700h-9z" fill="#0003"/><path d="M2.300 14.300c4.500 1 14.900 1 19.400 0M12 4.200v7" fill="none" stroke="#0009" stroke-width=".9"/><path d="M8 7.500c.5-1.200 1.300-2 2.300-2.500" fill="none" stroke="#fff6" stroke-width="1.100" stroke-linecap="round"/><circle cx="6" cy="13.300" r=".55" fill="#000a"/><circle cx="18" cy="13.300" r=".55" fill="#000a"/><circle cx="12" cy="13.700" r=".55" fill="#000a"/>',
  h_great: '<path d="M5.300 4c0-1 .8-1.800 1.800-1.800h9.800c1 0 1.800.8 1.800 1.800v12l-2.900 5.800H8.200L5.300 16z"/><path d="M12 2.200h4.900c1 0 1.800.8 1.800 1.800v12l-2.900 5.800H12z" fill="#0003"/><path d="M10.900 2.200h2.200v19.600h-2.200z" fill="#fff3"/><path d="M5.300 9h13.400v2.600H5.300z" fill="#fff3"/><path d="M6.600 9.700h3.700v1.200H6.600zM13.700 9.700h3.700v1.200h-3.700z" fill="#000d"/>' + '<g fill="#000b">' + dotsAt([14.6, 16.2], [14, 15.700, 17.400], .5) + '</g><path d="M5.300 4.800h13.400" fill="none" stroke="#0008" stroke-width=".8"/>',
  h_hood: '<path d="M3.500 21.500C3 11 6.500 2.500 12 2.500s9 8.500 8.500 19z"/><path d="M12 2.500c5.500 0 9 8.500 8.500 19H12z" fill="#0003"/><path d="M7.300 21.500C6.800 13.500 8.800 8.300 12 8.300s5.200 5.200 4.700 13.200z" fill="#000c"/><path d="M5.300 14c.3-5 2.300-9 5-10.500M4.500 18.500c1 .8 2 1.200 3 1.400M19.500 18.500c-1 .8-2 1.200-3 1.400" fill="none" stroke="#0007" stroke-width=".9" stroke-linecap="round"/>',
  h_turban: '<path d="M3 14c-.8-6 3.300-10.500 9-10.500S21.800 8 21 14c-5.500-2-12.500-2-18 0z"/><path d="M12 3.500c5.700 0 9.800 4.500 9 10.500-2.700-1-5.800-1.500-9-1.500z" fill="#0003"/><path d="M4 9.500c5-2.700 11-2.700 16 0M3.300 12c5.500-2.500 12-2.500 17.400 0M6.500 6c3.500-1.700 7.500-1.700 11 0" fill="none" stroke="#0008" stroke-width=".9"/><path d="M3 14c5.500-2 12.500-2 18 0v2.300c-5.500-2-12.500-2-18 0z" fill="#000a"/><circle cx="12" cy="13.200" r="1.500"/><path d="M15.500 15.600c.8 2 .8 4.300-.3 6.400l2.800-.8c.8-1.700.8-3.600 0-5.200z" opacity=".85"/>',
  h_turbanm: '<path d="M11.200 5.500L12 .5l.8 5z"/><path d="M5.300 12.500c0-4.300 2.800-7.500 6.700-7.500s6.700 3.200 6.700 7.500z" opacity=".75"/><path d="M3.300 14.300c-.5-4 3-6.800 8.700-6.800s9.200 2.800 8.700 6.800c-5.500-1.800-11.900-1.800-17.400 0z"/><path d="M12 7.500c5.700 0 9.200 2.800 8.700 6.800-2.700-.9-5.700-1.300-8.700-1.300z" fill="#0003"/><path d="M4 11.500c5-2.200 11-2.200 16 0M5.500 9.300c4-1.600 9-1.600 13 0" fill="none" stroke="#0008" stroke-width=".9"/><path d="M4.300 14.800c-.3 3 .5 5.300 2.200 7l2-6.800zM19.700 14.800c.3 3-.5 5.300-2.200 7l-2-6.800z" opacity=".8"/>' + arcsAt([5.6, 18.200], [16.500, 18, 19.500], .7) + '<circle cx="12" cy="13" r="1.300"/>',
  // щиты
  sh_round: '<circle cx="12" cy="12" r="10.300"/><path d="M12 1.700a10.300 10.300 0 0 1 0 20.600z" fill="#0003"/><circle cx="12" cy="12" r="8.600" fill="none" stroke="#000a" stroke-width="1.100"/><path d="M7.500 4.700v14.600M12 3.400v5M12 15.600v5M16.500 4.700v14.600" fill="none" stroke="#0007" stroke-width=".8"/><circle cx="12" cy="12" r="3.500" fill="#000a"/><circle cx="12" cy="12" r="2.300"/><circle cx="11.300" cy="11.300" r=".8" fill="#fff7"/>' + '<g fill="#000b">' + dotsAt([12], [2.600, 21.400], .55) + dotsAt([2.600, 21.400], [12], .55) + '</g><path d="M4.800 7.300A8.800 8.800 0 0 1 9 3.700" fill="none" stroke="#fff5" stroke-width="1.100" stroke-linecap="round"/>',
  sh_small: '<circle cx="12" cy="12" r="8"/><path d="M12 4a8 8 0 0 1 0 16z" fill="#0003"/><circle cx="12" cy="12" r="6.200" fill="none" stroke="#0009" stroke-width="1"/><circle cx="12" cy="12" r="3.400" fill="#000a"/><circle cx="12" cy="12" r="2.200"/><circle cx="11.300" cy="11.300" r=".8" fill="#fff7"/><path d="M12 5.800v2.600M12 15.600v2.600M5.800 12h2.600M15.600 12h2.600" fill="none" stroke="#0009" stroke-width="1"/>',
  // оружие
  sabre: '<g transform="rotate(40 12 12)"><path d="M11 15.500C10 10 10.500 5 13.500.8c1.300 5 1 10-.3 14.700z"/><path d="M12.300 4.500c.5 3.600.3 7.200-.4 11" fill="none" stroke="#0007" stroke-width=".8"/><path d="M7.500 15.300h9c.6 0 .9.400.9 1s-.3 1-.9 1h-9c-.6 0-.9-.4-.9-1s.3-1 .9-1z"/><path d="M10.900 17.300h2.200v3.700c0 1.200-.6 1.800-1.700 1.800l-.5-.9z"/><path d="M10.900 18.500h2.200M10.900 19.800h2.200" fill="none" stroke="#0008" stroke-width=".7"/></g>',
  twohand: '<g transform="rotate(45 12 12)"><path d="M12-2.500l1.900 2.800v12.900h-3.800V.3z"/><path d="M12-2.500l1.900 2.800v12.900H12z" fill="#0003"/><path d="M12 .3v12.400" fill="none" stroke="#0007" stroke-width=".9"/><path d="M10.600 11h2.800l.6 2.200h-4z"/><path d="M5.500 13.200h13c.6 0 .9.400.9 1s-.3 1-.9 1h-13c-.6 0-.9-.4-.9-1s.3-1 .9-1z"/><path d="M10.900 15.200h2.200v6.300h-2.200z"/><path d="M10.900 16.500h2.200M10.900 17.800h2.200M10.900 19.100h2.200M10.900 20.400h2.200" fill="none" stroke="#0008" stroke-width=".7"/><circle cx="12" cy="22.800" r="1.700"/></g>',
  axe: '<g transform="rotate(35 12 12)">' + shaft(1.5, 23, 2.200) + '<path d="M13.100 3c5.300.3 8.400 2.800 8.400 6.900s-3.100 6.600-8.400 6.900c1.900-2.200 1.900-11.600 0-13.800z"/><path d="M16.500 4.200c3.200 1 5 2.900 5 5.700s-1.800 4.700-5 5.700c1.800-3 1.800-8.400 0-11.400z" fill="#fff4"/><path d="M13.100 3c-1.100 1-1.100 2.500-1.100 3M13.100 16.800c-1.100-1-1.100-2.500-1.100-3" fill="none" stroke="#0008" stroke-width=".8"/><path d="M10.900 6.500h2.200v6.800h-2.200z" fill="#000a"/><path d="M10.900 18.500h2.200M10.900 20h2.200" fill="none" stroke="#0008" stroke-width=".7"/></g>',
  hammer: '<g transform="rotate(35 12 12)">' + shaft(4, 23, 2.200) + '<path d="M5.500 2.300h10.300l3.700 2.900-3.700 2.900H5.500z"/><path d="M12 2.300h3.800l3.700 2.900-3.700 2.900H12z" fill="#0003"/><path d="M4.300 1.800h1.800v6.800H4.300z"/><path d="M11 .2l1-1.800 1 1.800v2.100h-2z"/><path d="M10.900 8.100h2.200v2.200h-2.200z" fill="#000a"/><path d="M7 3.500h4" fill="none" stroke="#fff6" stroke-width="1" stroke-linecap="round"/><path d="M10.900 18.500h2.200M10.900 20h2.200" fill="none" stroke="#0008" stroke-width=".7"/></g>',
  mace: '<g transform="rotate(35 12 12)">' + shaft(8, 23, 2.200) + '<path d="M12-.5l1.300 2.100h-2.600z"/><path d="M12 1l4.500 2.300v5.400L12 11 7.500 8.700V3.300z"/><path d="M12 1l4.500 2.300v5.400L12 11z" fill="#0003"/><path d="M5.300 6l2.200-1.700v3.400zM18.700 6l-2.200-1.700v3.400z"/><path d="M12 1v10M7.500 3.300L12 6l4.500-2.700M7.500 8.700L12 6l4.500 2.700" fill="none" stroke="#0008" stroke-width=".8"/><path d="M10.700 11h2.600v1.300h-2.600z" fill="#000a"/><path d="M10.900 18.500h2.200M10.900 20h2.200" fill="none" stroke="#0008" stroke-width=".7"/></g>',
  club: '<g transform="rotate(35 12 12)"><path d="M12 1c3 0 4.500 2.100 4.500 5 0 2.700-1.300 4.400-2.300 5.400L13.500 22.500h-3L9.800 11.400c-1-1-2.300-2.700-2.300-5.400 0-2.900 1.500-5 4.500-5z"/><path d="M12 1c3 0 4.500 2.100 4.500 5 0 2.700-1.300 4.400-2.300 5.400L13.500 22.500H12z" fill="#0003"/><path d="M10.300 3.500c-.5 2 .1 4.700 1 6.500M13 5c.3 1.700 0 3.500-.5 5M11.700 12.500l.3 8" fill="none" stroke="#0008" stroke-width=".8" stroke-linecap="round"/><g fill="#000b"><circle cx="9.700" cy="5.500" r=".7"/><circle cx="14.300" cy="4.300" r=".7"/><circle cx="13.600" cy="8" r=".7"/><circle cx="10.300" cy="8.700" r=".7"/></g><path d="M10.500 19h3M10.400 20.500h3.200" fill="none" stroke="#0008" stroke-width=".8"/></g>',
  spear: '<g transform="rotate(35 12 12)">' + shaft(7.500, 23.500, 1.700) + '<path d="M12-.5c2.200 2.700 3.200 5.200 3.200 7.300 0 .9-.6 1.400-1.500 1.400h-3.400c-.9 0-1.500-.5-1.500-1.400 0-2.100 1-4.600 3.200-7.300z"/><path d="M12-.5c2.200 2.700 3.200 5.200 3.200 7.300 0 .9-.6 1.400-1.500 1.400H12z" fill="#0003"/><path d="M12 .8v7.400" fill="none" stroke="#0008" stroke-width=".8"/><path d="M10.800 8.200h2.400v1.800h-2.400z" fill="#000a"/><path d="M11.150 11.500h1.700M11.150 12.700h1.700" fill="none" stroke="#0008" stroke-width=".7"/></g>',
  pike: '<g transform="rotate(35 12 12)">' + shaft(4.500, 24.500, 1.300) + '<path d="M12-2.200c1.300 2.200 1.800 4 1.800 5.700 0 .6-.4 1-1 1h-1.600c-.6 0-1-.4-1-1 0-1.700.5-3.500 1.800-5.700z"/><path d="M12-1v5" fill="none" stroke="#0008" stroke-width=".7"/><path d="M10.800 4.500h2.400v5.500h-2.400z" opacity=".8"/><path d="M10.800 6.300h2.400M10.800 8.200h2.400" fill="none" stroke="#0009" stroke-width=".7"/><path d="M9.300 10h5.400v1.200H9.300z"/></g>',
  halberd: '<g transform="rotate(35 12 12)">' + shaft(4, 24.500, 1.700) + '<path d="M12-2.500l1.600 6.200h-3.200z"/><path d="M12.800 4.700c4.600.2 6.900 2 6.900 4.800s-2.300 4.600-6.900 4.800c1.500-2.300 1.500-7.300 0-9.600z"/><path d="M16 5.700c2.400.8 3.700 2 3.700 3.800s-1.300 3-3.700 3.800c1.300-2.200 1.300-5.400 0-7.600z" fill="#fff4"/><path d="M11.200 6.500L6 7.500c1.500.6 2.300 1.500 2.300 2.500s-.8 1.900-2.300 2.500l5.200-.5z"/><path d="M10.800 4.700h2.400v9.800h-2.400z" fill="#000a"/></g>',
  jav: '<g transform="rotate(45 12 12)">' + shaft(5.500, 21, 1.300) + '<path d="M12-.8l2.300 5.300c.2.600-.2 1.200-.8 1.200h-3c-.6 0-1-.6-.8-1.200z"/><path d="M12 .5v4.700" fill="none" stroke="#0008" stroke-width=".7"/><path d="M11.350 12h1.300v3.500h-1.300z" fill="#000a"/><path d="M12 16.500l-3 5.500 3-1.200 3 1.200z"/><path d="M12 16.500l3 5.500-3-1.200z" fill="#0004"/></g>',
  xbow: '<path d="M1.300 10.300C5.500 3.300 18.500 3.300 22.700 10.300l-1.500.9C17.500 5.300 6.500 5.300 2.800 11.200z"/><path d="M12 5.100c4.500 0 8.800 1.800 10.700 5.200l-1.500.9C19.300 8.300 15.800 6.800 12 6.800z" fill="#0003"/><path d="M2 10.700L12 14l10-3.300" fill="none" stroke="currentColor" stroke-width=".9"/><path d="M10.700 4.500h2.600v14.500l-1.300 3.500-1.300-3.500z"/><path d="M12 4.500h1.300v14.500L12 22.500z" fill="#0004"/><path d="M12 .3l1.700 3.600h-3.400z"/><path d="M10 2.500a2 1.500 0 0 1 4 0" fill="none" stroke="currentColor" stroke-width="1.100"/><path d="M10.700 14h2.600M10.700 16h2.600" fill="none" stroke="#0009" stroke-width=".8"/><path d="M13.300 15.500l2.200 2.800" fill="none" stroke="currentColor" stroke-width="1.200" stroke-linecap="round"/>',
  // товары
  grain: '<path d="M11.300 12h1.400v10.500h-1.400z"/><path d="M12 .5c1.800 1.700 1.800 3.800 0 5.500-1.800-1.700-1.800-3.800 0-5.500zM12 6.300c1.800 1.700 1.800 3.800 0 5.500-1.800-1.700-1.800-3.800 0-5.500zM7.300 3.800c2.300.2 3.800 1.700 4.300 4-2.300-.2-3.900-1.700-4.300-4zM16.700 3.800c-2.300.2-3.800 1.700-4.300 4 2.300-.2 3.900-1.700 4.300-4zM7.300 9.300c2.300.2 3.800 1.700 4.300 4-2.300-.2-3.900-1.700-4.300-4zM16.700 9.300c-2.300.2-3.800 1.700-4.300 4 2.300-.2 3.900-1.700 4.300-4zM7.800 14.800c2 .2 3.300 1.500 3.800 3.500-2-.2-3.400-1.500-3.800-3.500zM16.200 14.800c-2 .2-3.300 1.500-3.800 3.500 2-.2 3.400-1.500 3.800-3.500z"/><path d="M12 1.800v3M12 7.600v3M8.300 4.800l2.300 2M15.700 4.800l-2.300 2M8.300 10.300l2.300 2M15.700 10.300l-2.300 2" fill="none" stroke="#0007" stroke-width=".7"/><path d="M12 .5L11 -1.800M12 .5l1-2.300M7.300 3.800L5.500 2M16.700 3.800L18.500 2" fill="none" stroke="currentColor" stroke-width=".7" stroke-linecap="round"/>',
  sack: '<path d="M8.300 7.500C5 9.500 3.300 13 3.300 16.500c0 3.500 2.400 5.500 8.700 5.500s8.700-2 8.700-5.500c0-3.500-1.700-7-5-9z"/><path d="M12 7.500h3.700c3.300 2 5 5.500 5 9 0 3.500-2.400 5.500-8.700 5.500z" fill="#0003"/><path d="M8.300 2.800c1.200-.8 2.400 0 3.700 0s2.500-.8 3.700 0L14.300 6.300H9.700z"/><path d="M7.800 6.200h8.400v1.800H7.800z" fill="#000b"/><path d="M8.500 13h4.500v4.500H8.500z" fill="none" stroke="#0009" stroke-width=".9" stroke-dasharray="1.200 1"/><path d="M5.300 14c.5-2.200 1.600-4 3.200-5.300" fill="none" stroke="#fff5" stroke-width="1.100" stroke-linecap="round"/>',
  ale: '<path d="M4 7.500h12v11.800a2.200 2.200 0 0 1-2.200 2.200H6.200A2.200 2.200 0 0 1 4 19.300z"/><path d="M10 7.500h6v11.800a2.200 2.200 0 0 1-2.200 2.200H10z" fill="#0003"/><path d="M16 9.500h2.800a2.900 2.900 0 0 1 0 5.800H16v-2h2.600a.9.900 0 0 0 0-1.800H16z"/><path d="M3.300 7.500c-.6-2.700 1.500-4 3.500-3.600.8-1.700 3.200-2.100 4.500-.8 1.500-1.300 4.200-.6 4.300 1.600 1.200.4 1.600 1.700 1 2.800z"/><path d="M6.800 3.900c.8-1.700 3.200-2.100 4.500-.8M5 6.300c.3-.9 1-1.500 1.800-1.500" fill="none" stroke="#0007" stroke-width=".8" stroke-linecap="round"/><path d="M7 9.500v12M10 9.500v12M13 9.500v12M4 11.500h12M4 18h12" fill="none" stroke="#0008" stroke-width=".8"/>',
  ingot: '<path d="M9.500 13.500l1.800-5.500h8l1.800 5.500z"/><path d="M11.300 8h8l1.800 5.500h-6z" fill="#0003"/><path d="M12 9.300h6.500" fill="none" stroke="#fff7" stroke-width="1" stroke-linecap="round"/><path d="M1.500 21l2.200-6h8.600l2.200 6z"/><path d="M8 15h4.300l2.200 6H8z" fill="#0003"/><path d="M4.500 16.300h7" fill="none" stroke="#fff7" stroke-width="1" stroke-linecap="round"/><path d="M13.500 21l1.300-3.500h6l1.700 3.500z" opacity=".7"/><path d="M1.500 21h13M9.500 13.500h11.600" fill="none" stroke="#000a" stroke-width=".8"/>',
  hide: '<path d="M5 3.500l4 2.200h6l4-2.200 3 5-3 3 1.300 3-3.300 1.200.7 5.300H7.300L8 15.700l-3.300-1.200 1.300-3-3-3z"/><path d="M12 5.700h3l4-2.200 3 5-3 3 1.300 3-3.300 1.200.7 5.300H12z" fill="#0003"/><path d="M9.300 8c1.700 1.200 3.700 1.200 5.400 0M9.500 17.500h5M12 9v8.500" fill="none" stroke="#0007" stroke-width=".8" stroke-linecap="round"/><g fill="#000a"><circle cx="5.300" cy="5.300" r=".6"/><circle cx="18.700" cy="5.300" r=".6"/><circle cx="8.300" cy="20" r=".6"/><circle cx="15.700" cy="20" r=".6"/></g>',
  pelt: '<path d="M7 2.500c2 1.700 8 1.700 10 0l4.300 6.300-3.100 3 2.100 6.200-4.200-1-1 5.500H8.900l-1-5.500-4.200 1 2.100-6.200-3.100-3z"/><path d="M12 3.700c2 0 4-.4 5-1.200l4.300 6.300-3.100 3 2.100 6.200-4.200-1-1 5.500H12z" fill="#0003"/><path d="M9 6l.5 1.600M12 6.500v1.800M15 6l-.5 1.600M8 10.500l.8 1.500M12 11v1.800M16 10.500l-.8 1.500M9.500 15l.4 1.700M12 15.500v1.800M14.500 15l-.4 1.700M10.500 19.500l.3 1.500M13.500 19.500l-.3 1.500" fill="none" stroke="#0009" stroke-width=".9" stroke-linecap="round"/><path d="M5.500 7l1 1.300M18.500 7l-1 1.300" fill="none" stroke="#0008" stroke-width=".9" stroke-linecap="round"/>',
  roll: '<path d="M7 4.500h10.500c1.900 0 3.500 3.400 3.500 7.500s-1.600 7.500-3.500 7.500H7z"/><path d="M7 12h14c0 4.100-1.600 7.500-3.500 7.500H7z" fill="#0003"/><ellipse cx="7" cy="12" rx="3.500" ry="7.500"/><ellipse cx="7" cy="12" rx="3.500" ry="7.500" fill="#0005"/><path d="M7 8.500c1 .6 1.500 1.900 1.500 3.500S8 14.900 7 15.500c-1-.6-1.500-1.900-1.500-3.500S6 9.100 7 8.500z" fill="#000a"/><path d="M11 5v14M14.500 4.700v14.600M17.500 5v14" fill="none" stroke="#0006" stroke-width=".8"/><path d="M17.500 19.500l2.500 2.500h-6z" opacity=".8"/>',
  bottle: '<path d="M10.300 1.500h3.400v1.800h-3.400z" opacity=".75"/><path d="M10.300 3.300h3.400v3.900c2.100 1 3.300 2.700 3.300 5.300v7.800a2.200 2.200 0 0 1-2.200 2.200H9.200A2.200 2.200 0 0 1 7 20.300v-7.800c0-2.600 1.200-4.300 3.300-5.300z"/><path d="M12 3.300h1.700v3.900c2.100 1 3.300 2.700 3.300 5.300v7.800a2.200 2.200 0 0 1-2.200 2.200H12z" fill="#0003"/><path d="M7 13.500h10v5H7z" fill="#000a"/><path d="M9 15.300h6M9 16.800h4" fill="none" stroke="#fff6" stroke-width=".8"/><path d="M9 9.700c.3-.7.9-1.300 1.700-1.700" fill="none" stroke="#fff6" stroke-width="1.100" stroke-linecap="round"/><path d="M10.300 5h3.400" fill="none" stroke="#0008" stroke-width=".8"/>',
  jar: '<path d="M8 1.800h8v2.800H8z"/><path d="M7.300 4.600h9.400v1.600H7.300z" fill="#000a"/><path d="M6.500 6.200h11c1.100 2 1.700 4.200 1.700 6.600 0 3.900-1.900 7.300-4 9.400H8.800c-2.100-2.100-4-5.500-4-9.400 0-2.400.6-4.600 1.700-6.600z"/><path d="M12 6.200h5.500c1.100 2 1.700 4.200 1.700 6.600 0 3.900-1.900 7.300-4 9.400H12z" fill="#0003"/><path d="M8.300 11h7.400v5.500H8.300z" fill="#000a"/><path d="M12 12l.9 1.500 1.600.3-1.100 1.200.2 1.700-1.600-.8-1.600.8.200-1.700-1.100-1.200 1.600-.3z" fill="#fff8"/><path d="M6.800 10c.2-1 .5-1.900.9-2.700" fill="none" stroke="#fff6" stroke-width="1.100" stroke-linecap="round"/>'
});
const SLOT_ICON = { head: 'helm', body: 'body', hands: 'hands', legs: 'legs', melee: 'sword', ranged: 'bow', shield: 'shield', horse: 'horse' };
const GOOD_IC = { grain: 'grain', salt: 'sack', ale: 'ale', iron: 'ingot', leather: 'hide', furs: 'pelt', cloth: 'roll', wine: 'bottle', spice: 'jar' };
const TIER = [{ n: 'Простое', c: '#a89f8a' }, { n: 'Добротное', c: '#8fc24f' }, { n: 'Редкое', c: '#5fa0e6' }, { n: 'Мастерское', c: '#e5902a' }];
const tierOf = it => it && it.slot ? TIER[Math.min(3, it.tier || 0)] : null; // предметы каталога (EQ) и вещи из ITEM; у товаров слота нет
function iconKey(it) {
  if (it.kind === 'goods') return GOOD_IC[it.id] || 'sack';
  switch (it.slot) {
    case 'melee': case 'ranged':
      if (it.wt === 'twohand') return it.look === 'axe' ? 'axe' : it.look === 'mace' ? 'hammer' : 'twohand';
      if (it.wt === 'polearm') return it.look === 'halberd' ? 'halberd' : 'pike';
      if (it.wt === 'mace') return it.look === 'club' ? 'club' : 'mace';
      if (it.look === 'sabre') return 'sabre';
      return { sword: 'sword', axe: 'axe', spear: 'spear', bow: 'bow', xbow: 'xbow', throw: 'jav' }[it.wt] || 'sword';
    case 'head': return 'h_' + it.look;
    case 'body': return 'b_' + it.look;
    case 'shield': return it.look === 'round' ? 'sh_round' : it.look === 'small' ? 'sh_small' : 'shield';
    default: return SLOT_ICON[it.slot];
  }
}
function itemIc(it, s) { const k = iconKey(it); return ic(ICONS[k] ? k : (SLOT_ICON[it.slot] || 'bag'), s); }

const pc = v => Math.round(v * 100) + '%';
function cargoBar(P) { const w = invWeight(P), c = cargoCap(P); return '<div class="kv"><span>Обоз</span><b class="' + (w > c ? 'dn' : '') + '">' + w + ' / ' + c + '</b></div><div class="pbar cargo' + (w > c ? ' over' : '') + '"><i style="width:' + clamp(w / c * 100, 0, 100) + '%"></i></div>'; }
function swingLabel(spd) { return spd < 1 ? 'быстрый' : spd <= 1.1 ? 'обычный' : spd <= 1.35 ? 'медленный' : 'тяжёлый'; }
function keepScroll(fn) { const b = document.querySelector('#modal .wbody'), t = b ? b.scrollTop : 0; fn(); const n = document.querySelector('#modal .wbody'); if (n) n.scrollTop = t; }
const slotOrd = id => SLOTS.indexOf(ITEM[id].slot);
const byGear = (a, c) => slotOrd(a) - slotOrd(c) || ITEM[a].price - ITEM[c].price;

/* Двойной щелчок считаем сами: после первого щелчка окно перерисовывается, и родное событие dblclick до новой плитки не доходит.
   Плитка с data-dbl="действие" по второму быстрому нажатию выполняет это действие. */
let lastTap = { k: '', t: 0 };
function dblTap(d, key) { const now = Date.now(), hit = lastTap.k === key && now - lastTap.t < 420; lastTap = hit ? { k: '', t: 0 } : { k: key, t: now }; return hit && d.dbl && ACT[d.dbl]; }

/* ---------- плитка предмета ---------- */
function tile(o) {
  const it = o.it, t = tierOf(it), cls = ['tile'];
  if (o.on) cls.push('on'); if (o.fit) cls.push('fit'); if (!it) cls.push('empty'); if (it && it.kind === 'goods') cls.push('g'); if (o.price !== undefined) cls.push('hp');
  const st = '--tc:' + (t ? t.c : it ? '#8a7a58' : '#ffffff22') + (it && it.kind === 'goods' ? ';--ic:' + it.c : ''), tag = o.attr ? 'button' : 'div';
  let h = '<' + tag + ' class="' + cls.join(' ') + '" style="' + st + '"' + (o.title ? ' title="' + o.title + '"' : '') + ' ' + (o.attr || '') + '>' + (it ? itemIc(it) : ic(o.ghost || 'bag'));
  if (o.qty > 1) h += '<b class="qty">' + o.qty + '</b>';
  if (o.price !== undefined) h += '<span class="pr ' + (o.tone || '') + '">' + ic('coin') + fmt(o.price) + '</span>';
  if (o.rib) h += '<i class="rib ' + (o.rib[1] || '') + '">' + o.rib[0] + '</i>';
  if (o.lab) h += '<span class="lab">' + o.lab + '</span>';
  return h + '</' + tag + '>';
}
const voidTiles = n => '<div class="tile void"></div>'.repeat(Math.max(0, n));

/* ---------- карточка вещи (внизу окна) ---------- */
const stat = (l, v, d) => '<span>' + l + '<b>' + v + (d || '') + '</b></span>';
function pierceBars(W) {
  const nm = ['Лёгкая броня', 'Средняя', 'Тяжёлая'];
  return '<div class="pbars">' + [0, 1, 2].map(i => { const p = dtPierce(W.dt, [0, 20, 40][i], W.pb); return '<div>' + nm[i] + ' <b>' + pc(p) + '</b><i><u style="width:' + clamp(p / .55 * 100, 3, 100) + '%"></u></i></div>'; }).join('') + '</div>';
}
function cmpDelta(it, cur, key) { // насколько вещь лучше надетой в том же слоте
  const d = (it[key] || 0) - (cur ? cur[key] || 0 : 0); if (!d) return ''; const n = it.slot === 'shield' ? Math.round(d * 100) + '%' : Math.round(d * 10) / 10;
  return ' <small class="' + (d > 0 ? 'up' : 'dn') + '">' + (d > 0 ? '▲ +' : '▼ ') + n + '</small>';
}
function itemDock(it, o) {
  o = o || {}; const t = tierOf(it), cur = o.cmp ? eqItem(G.player.hero, it.slot) : null, st = [], tr = []; let sub;
  if (it.kind === 'goods') { sub = FOODV[it.id] ? 'Товар · провизия' : 'Товар'; st.push(stat('Вес', it.w), stat('Обычная цена', it.price)); if (FOODV[it.id]) st.push(stat('Провизия', '+' + FOODV[it.id] + ' порц.')); }
  else {
    sub = SLOT_NAME[it.slot] + (it.dt ? ' · ' + WTYPE[it.wt] + ' · ' + DTYPE[it.dt].n.toLowerCase() + ' урон' : '') + ' · ' + t.n;
    if (it.dmg !== undefined) {
      st.push(stat('Урон', it.dmg, o.cmp ? cmpDelta(it, cur, 'dmg') : ''), stat('Хват', it.hands === 2 ? 'двуручное' : 'одноручное'));
      if (it.rng) st.push(stat('Дальность', it.range), stat('Перезарядка', it.cd + ' с')); else st.push(stat('Темп', swingLabel(it.spd)), stat('Длина', it.reach ? '+' + it.reach : 'обычная'));
    } else if (it.slot === 'shield') st.push(stat('Блок', pc(it.v), o.cmp ? cmpDelta(it, cur, 'v') : ''), stat('От стрел', '+' + pc(shieldArrow(it.look))));
    else if (it.slot === 'horse') st.push(stat('Скорость', it.v, o.cmp ? cmpDelta(it, cur, 'v') : ''));
    else st.push(stat('Броня', '+' + it.v, o.cmp ? cmpDelta(it, cur, 'v') : ''));
    if (it.w) st.push(stat('Вес', it.w));
    if (it.brk) tr.push('пробивает блок щитом'); if (it.kb >= 2) tr.push('сильно отбрасывает'); if (it.anticav) tr.push('бонус против конницы'); if (it.cleave >= 4) tr.push('задевает до ' + it.cleave + ' целей');
    if (it.dmg !== undefined && it.hands === 2 && !it.rng) tr.push('щит не носят'); if (it.rng && it.hands === 2) tr.push('щит уходит за спину'); if (it.rng) tr.push('боеприпасы бесконечные');
  }
  return '<div class="dock">' + tile({ it }) + '<div class="dinfo"><div class="dnm" style="color:' + (t ? t.c : 'var(--parch)') + '">' + it.name + '</div><div class="dsub">' + sub + (o.sub ? ' · ' + o.sub : '') + '</div><div class="dstats">' + st.join('') + '</div>' +
    (tr.length ? '<div class="ptags">' + tr.map(x => '<em>' + x + '</em>').join('') + '</div>' : '') + (it.dt ? pierceBars(it) : '') + (it.dt ? '<div class="dsub dnote" style="margin:4px 0 0">' + DTYPE[it.dt].note + '</div>' : '') + '</div>' +
    (o.acts ? '<div class="dacts">' + o.acts + '</div>' : '') + '</div>';
}
const dockHint = (txt, tl) => '<div class="dock hint">' + tile({ ghost: tl || 'bag' }) + '<div class="dinfo"><div class="note" style="margin:0">' + txt + '</div></div></div>';

/* ---------- вкладка «Торговля» в городе, замке и деревне ---------- */
function tradeTile(s, P, id, side) {
  const it = ITEM[id], m = marketOf(s), buy = side === 'buy', have = buy ? (m.stock[id] || 0) : invN(P, id), pr = buy ? buyPrice(P, s, id) : sellPrice(P, s, id), lv = priceLevel(s, id);
  const tone = !lv ? '' : (buy ? lv === 'low' : lv === 'high') ? 'cheap' : 'dear', can = buy ? P.gold >= pr : m.gold >= pr, on = UI.tsel && UI.tsel.side === side && UI.tsel.id === id;
  return tile({ it, on, qty: have, price: pr, tone: can ? tone : 'no', title: it.name, attr: 'data-act="tsel" data-side="' + side + '" data-id="' + id + '" data-n="1" data-dbl="' + (buy ? 'tbuy' : 'tsell') + '"' });
}
function tradeLists(s) {
  const P = G.player, m = marketOf(s), ord = (a, b) => (ITEM[a].kind === ITEM[b].kind ? (ITEM[a].kind === 'gear' ? slotOrd(a) - slotOrd(b) : 0) || ITEM[a].price - ITEM[b].price : ITEM[a].kind === 'goods' ? -1 : 1);
  return { mine: invIds(P, 'goods').concat(invIds(P, 'gear')).sort(ord), theirs: Object.keys(m.stock).filter(id => ITEM[id] && m.stock[id] > 0).sort(ord) };
}
function tradeBody(s) {
  const P = G.player; if (!hasMarket(s)) return '<div class="note">Здесь не торгуют.</div>';
  const m = marketOf(s), L = tradeLists(s);
  return '<div class="tbar"><div class="note" style="margin:0"><span class="tgold" title="Твоё золото">' + ic('coin') + ' Твоё: <b>' + fmt(P.gold) + '</b></span> <span class="tgold" title="Золото города: столько торговец может заплатить за твои товары">' + ic('coin') + ' У города: <b>' + fmt(m.gold) + '</b></span><br>Цены зависят от края и от запаса на складе, крупная партия сдвигает цену. Надетое не продаётся: сними его в окне «Обоз».</div><div>' + cargoBar(P) + '</div></div>' +
    '<div class="trade"><div><h3>Торговец</h3><div class="igrid">' + L.theirs.map(id => tradeTile(s, P, id, 'buy')).join('') + voidTiles(12 - L.theirs.length) + '</div></div>' +
    '<div><h3>Твой обоз</h3><div class="igrid">' + L.mine.map(id => tradeTile(s, P, id, 'sell')).join('') + voidTiles(12 - L.mine.length) + '</div>' + (L.mine.length ? '' : '<div class="note">Обоз пуст. Купи товар или добудь трофеи в бою.</div>') + '</div></div>';
}
function tradeDock(s) {
  const P = G.player; if (!hasMarket(s)) return '';
  const m = marketOf(s), sel = UI.tsel, hint = dockHint('Выбери вещь на прилавке или в своём обозе. Двойной щелчок покупает или продаёт одну штуку.', 'coin');
  if (!sel || !ITEM[sel.id]) return hint;
  const it = ITEM[sel.id], buy = sel.side === 'buy', have = buy ? (m.stock[sel.id] || 0) : invN(P, sel.id); if (have < 1) { UI.tsel = null; return hint; }
  const pr = buy ? buyPrice(P, s, sel.id) : sellPrice(P, s, sel.id), lv = priceLevel(s, sel.id), ok = buy ? P.gold >= pr : m.gold >= pr, tone = !lv ? '' : (buy ? lv === 'low' : lv === 'high') ? 'cheap' : 'dear';
  const nn = it.kind === 'gear' ? [1] : [1, 5, 99], lab = n => n === 99 ? (buy ? 'Макс.' : 'Все') : (buy ? 'Купить' : 'Продать') + (n > 1 ? ' ×' + n : it.kind === 'gear' ? '' : ' ×1');
  const acts = '<div class="dprice ' + tone + '" title="' + (buy ? 'Цена покупки' : 'Цена продажи') + '">' + ic('coin') + '<b>' + fmt(pr) + '</b><small>' + (buy ? 'за штуку' : 'за штуку') + (lv ? ' · здесь ' + (lv === 'low' ? 'дёшево' : 'дорого') : '') + '</small></div>' +
    '<div class="dprice" title="Золото города: столько торговец может заплатить">' + ic('coin') + '<b>' + fmt(m.gold) + '</b><small>у города</small></div>' + nn.map(n => '<button class="btn sm' + (n === 1 ? ' pri' : '') + '" data-act="' + (buy ? 'tbuy' : 'tsell') + '" data-id="' + sel.id + '" data-n="' + n + '" ' + (ok ? '' : 'disabled') + '>' + (n === 1 && it.kind === 'gear' ? (buy ? 'Купить' : 'Продать') : lab(n)) + '</button>').join('');
  return itemDock(it, { cmp: it.kind === 'gear', acts, sub: buy ? 'на прилавке: ' + have + ' · у тебя: ' + invN(P, sel.id) : 'у тебя: ' + have });
}
ACT.tsel = function (d) { const dbl = dblTap(d, 't|' + d.side + '|' + d.id); if (dbl) return dbl(d); UI.tsel = { side: d.side, id: d.id }; keepScroll(renderTown); };
ACT.tbuy = function (d) {
  if (NET.on) { NET.send({ t: 'tbuy', id: d.id, n: +d.n }); sfx('coin'); return; }
  const P = G.player, n = +d.n, r = doBuy(P, UI.town.s, d.id, n);
  if (r.n) { sfx('coin'); toast('Куплено: ' + ITEM[d.id].name + (r.n > 1 ? ' ×' + r.n : '') + ' за ' + fmt(r.sum)); if (r.n < n && n < 99) toast(TRADE_WHY[r.why] || ''); } else toast(TRADE_WHY[r.why] || 'Не вышло');
  keepScroll(renderTown);
};
ACT.tsell = function (d) {
  if (NET.on) { NET.send({ t: 'tsell', id: d.id, n: +d.n }); sfx('coin'); return; }
  const P = G.player, n = +d.n, r = doSell(P, UI.town.s, d.id, n);
  if (r.n) { sfx('coin'); toast('Продано: ' + ITEM[d.id].name + (r.n > 1 ? ' ×' + r.n : '') + ' за ' + fmt(r.sum)); if (r.n < n && n < 99 && r.why) toast(TRADE_WHY[r.why]); } else toast(TRADE_WHY[r.why] || 'Не вышло');
  keepScroll(renderTown);
};

/* ---------- ряд мини-плиток надетого (для окна героя) ---------- */
function miniGear(H) {
  return '<div class="mini">' + SLOTS.map(k => { const it = eqItem(H, k); return it ? '<span class="mt" style="--tc:' + tierOf(it).c + '" title="' + SLOT_NAME[k] + ': ' + it.name + '">' + itemIc(it) + '</span>' : '<span class="mt void" title="' + SLOT_NAME[k] + ': пусто">' + ic(SLOT_ICON[k]) + '</span>'; }).join('') + '</div>';
}

/* ---------- вкладка «Обоз»: кукла героя и рюкзак ---------- */
function slotTile(P, k) {
  const H = invWho(P), it = eqItem(H, k), w = heroWield(H), s = UI.isel, on = s && s.from === 'slot' && s.k === k, fit = s && s.from === 'bag' && ITEM[s.id] && ITEM[s.id].slot === k; let rib = null;
  if (it && (k === 'melee' || k === 'ranged')) rib = w === it ? ['в руках', 'g'] : ['за спиной'];
  if (it && k === 'shield' && heroShield(H) === null) rib = ['за спиной'];
  return tile({ it, on, fit, rib, ghost: SLOT_ICON[k], lab: it ? '' : SLOT_NAME[k], title: SLOT_NAME[k] + (it ? ': ' + it.name : ''), attr: 'data-act="isel" data-from="slot" data-k="' + k + '"' + (it ? ' data-dbl="unequip" data-slot="' + k + '"' : '') });
}
function bagTile(P, id) {
  const it = ITEM[id], s = UI.isel, on = s && s.from === 'bag' && s.id === id, fit = s && s.from === 'slot' && it.slot === s.k;
  return tile({ it, on, fit, qty: invN(P, id), title: it.name, attr: 'data-act="isel" data-from="bag" data-id="' + id + '"' + (it.kind === 'gear' ? ' data-dbl="equip"' : '') });
}
const BAG_FILTERS = [['all', 'Всё'], ['weapon', 'Оружие'], ['armor', 'Броня'], ['goods', 'Товары']];
function bagIds(P, f) {
  const gear = invIds(P, 'gear').sort(byGear), goods = invIds(P, 'goods'), wp = id => ITEM[id].slot === 'melee' || ITEM[id].slot === 'ranged';
  return f === 'weapon' ? gear.filter(wp) : f === 'armor' ? gear.filter(id => !wp(id)) : f === 'goods' ? goods : gear.concat(goods);
}
function invBody() {
  const P = G.player, H = invWho(P), hd = heroDef(H), W = hd.wpn, Gr = heroGear(H), sp = getHeroSprite(H, Gr.mounted); if (!sp.url) sp.url = sp.cv.toDataURL();
  const f = UI.bagF || 'all', ids = bagIds(P, f);
  const stt = [['Броня', hd.arm], ['Урон', Math.round(hd.dmg)], ['Блок', pc(Gr.block)], [W.rng ? 'Перезарядка' : 'Удар', Math.round(hd.cd * 100) / 100 + ' с'], [W.rng ? 'Дальность' : 'Длина', W.rng ? W.range : 30 + hd.reach], ['Урон по типу', DTYPE[W.dt].n]];
  return whoBar(P) + '<div class="inv"><div><div class="doll"><div class="col">' + ['head', 'body', 'hands', 'legs'].map(k => slotTile(P, k)).join('') + '</div>' +
    '<div class="fig"><img alt="" src="' + sp.url + '"><div class="who">' + H.name + '<small>Уровень ' + H.lvl + (Gr.mounted ? ' · верхом' : '') + '</small></div></div>' +
    '<div class="col">' + ['melee', 'ranged', 'shield', 'horse'].map(k => slotTile(P, k)).join('') + '</div></div>' +
    '<div class="stt">' + stt.map(x => '<div><span>' + x[0] + '</span><b>' + x[1] + '</b></div>').join('') + '</div></div>' +
    '<div><h3>Рюкзак<span class="fl">' + BAG_FILTERS.map(x => '<button class="fbtn' + (x[0] === f ? ' on' : '') + '" data-act="bagf" data-f="' + x[0] + '">' + x[1] + '</button>').join('') + '</span></h3>' + cargoBar(P) +
    '<div class="igrid">' + ids.map(id => bagTile(P, id)).join('') + voidTiles(Math.max(24, Math.ceil(ids.length / 6) * 6) - ids.length) + '</div>' +
    (ids.length ? '' : '<div class="note">' + (f === 'all' ? 'Обоз пуст.' : 'В этой вкладке пусто.') + '</div>') + '<div class="note">Провизия: ' + provOf(P) + ' порций — это зерно, картошка, журек и эль из обоза, отряд съедает их по дороге. Двойной щелчок по вещи: надеть, по слоту: снять. В бою X меняет оружие.</div></div></div>';
}
function invDock() {
  const P = G.player, H = invWho(P), s = UI.isel, hint = dockHint('Выбери слот куклы или вещь в рюкзаке. Подходящие вещи подсветятся зелёной рамкой.', 'bag');
  if (!s) return hint;
  if (s.from === 'slot') {
    const it = eqItem(H, s.k), w = heroWield(H); let acts = '';
    if (!it) { const n = invIds(P, 'gear').filter(id => ITEM[id].slot === s.k).length; return '<div class="dock hint">' + tile({ ghost: SLOT_ICON[s.k] }) + '<div class="dinfo"><div class="dnm" style="color:var(--parch2)">' + SLOT_NAME[s.k] + ': пусто</div><div class="dsub">' + (n ? 'В рюкзаке подходящих вещей: ' + n + ' (подсвечены).' : 'В рюкзаке ничего подходящего.') + (s.k === 'melee' ? ' Без оружия герой дерётся кулаками.' : '') + '</div></div></div>'; }
    acts += '<button class="btn sm pri" data-act="unequip" data-slot="' + s.k + '">Снять</button>';
    if ((s.k === 'melee' || s.k === 'ranged') && w !== it) acts += '<button class="btn sm" data-act="wield" data-sel="' + s.k + '">Взять в руки</button>';
    return itemDock(it, { acts, sub: 'надето' });
  }
  const it = ITEM[s.id]; if (!it || invN(P, s.id) < 1) { UI.isel = null; return hint; }
  if (it.kind === 'goods') return itemDock(it, { sub: 'в обозе: ' + invN(P, s.id) + ' · общий вес ' + Math.round(it.w * invN(P, s.id) * 10) / 10 });
  const mel = eqItem(H, 'melee'), blocked = it.slot === 'shield' && mel && mel.hands === 2, hint2 = blocked ? '<div class="dsub dn">С двуручным оружием щит не носят.</div>' : it.slot === 'melee' && it.hands === 2 && eqItem(H, 'shield') ? '<div class="dsub">Щит уйдёт в рюкзак.</div>' : '';
  return itemDock(it, { cmp: true, sub: invN(P, s.id) > 1 ? 'в рюкзаке: ' + invN(P, s.id) : '', acts: hint2 + '<button class="btn sm pri" data-act="equip" data-id="' + s.id + '" ' + (blocked ? 'disabled' : '') + '>Надеть</button>' });
}
ACT.isel = function (d) { const dbl = dblTap(d, 'i|' + (d.id || d.k)); if (dbl) return dbl(d); UI.isel = d.from === 'slot' ? { from: 'slot', k: d.k } : { from: 'bag', id: d.id }; keepScroll(renderPanel); };
ACT.bagf = function (d) { UI.bagF = d.f; keepScroll(renderPanel); };
ACT.equip = function (d) { if (NET.on) { NET.send({ t: 'equip', id: d.id }); sfx('order'); return; } const it = ITEM[d.id], r = doEquip(G.player, d.id, invWho(G.player)); if (r.ok) { sfx('order'); UI.isel = { from: 'slot', k: it.slot }; if (r.note) toast(r.note); } else if (r.note) toast(r.note); keepScroll(renderPanel); };
ACT.unequip = function (d) { if (NET.on) { NET.send({ t: 'unequip', slot: d.slot }); sfx('click'); return; } const H = invWho(G.player), id = heroEq(H)[d.slot]; if (doUnequip(G.player, d.slot, H)) { sfx('click'); UI.isel = { from: 'bag', id }; } keepScroll(renderPanel); };
ACT.wield = function (d) { if (NET.on) { NET.send({ t: 'wield', sel: d.sel }); sfx('click'); return; } if (doWield(G.player, d.sel, invWho(G.player))) sfx('click'); keepScroll(renderPanel); };
ACT.inv = function () { openPanel('inv'); };
