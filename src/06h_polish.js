/* Читаемость боя, карты и экипировки. Только клиентская отрисовка. */
const COMMAND_LABEL = { hold: 'Держать', follow: 'За мной', charge: 'В атаку', back: 'Отойти' };
function selectedGroups() { return B.groups[0].filter(g => g.own === myPid() && (B.sel === 3 || g.k === B.sel) && g.units.some(fit)); }
function commandHud() {
  const groups = selectedGroups(), orders = new Set(groups.map(g => g.back ? 'back' : g.order));
  for (const b of document.querySelectorAll('#bgroups .grp')) b.setAttribute('aria-pressed', String(+b.dataset.g === B.sel));
  for (const b of document.querySelectorAll('#bords .ord')) {
    const active = orders.size === 1 && orders.has(b.dataset.o);
    b.classList.toggle('on', active); b.setAttribute('aria-pressed', String(active)); b.disabled = !groups.length;
  }
  const label = el('commandState');
  if (label) label.textContent = ['Пехота', 'Стрелки', 'Конница', 'Все отряды'][B.sel] + ' · ' + (!groups.length ? 'нет бойцов' : orders.size > 1 ? 'разные приказы' : ORD_NAME[[...orders][0]] || 'Ждут приказа');
}
function commandDraw(g) {
  if (B.cfg.demo) return;
  g.save(); const foe = centroid(1);
  for (const group of selectedGroups()) {
    const c = centroidOf(group); let target;
    if (group.order === 'hold') target = { x: group.cx, y: group.cy };
    else if (group.order === 'follow') target = B.hero;
    else if (foe) { const a = Math.atan2(foe.y - c.y, foe.x - c.x); target = { x: c.x + Math.cos(a) * 100, y: c.y + Math.sin(a) * 100 }; }
    if (!target) continue;
    const a = Math.atan2(target.y - c.y, target.x - c.x), col = group.back ? '#a9d1dc' : '#edcf7b';
    g.strokeStyle = 'rgba(20,14,6,.65)'; g.lineWidth = 5; g.beginPath(); g.moveTo(c.x, c.y); g.lineTo(target.x, target.y); g.stroke();
    g.strokeStyle = col; g.lineWidth = 2; g.setLineDash([9, 7]); g.stroke(); g.setLineDash([]);
    line(g, [target.x - Math.cos(a - .5) * 13, target.y - Math.sin(a - .5) * 13, target.x, target.y, target.x - Math.cos(a + .5) * 13, target.y - Math.sin(a + .5) * 13], col, 2);
    if (group.order === 'hold') { ell(g, target.x, target.y, 24, 10); g.stroke(); const d = group.dir || 0; line(g, [target.x, target.y, target.x + Math.cos(d) * 32, target.y + Math.sin(d) * 32], col, 2); }
  }
  g.restore();
}
function unitPolish(g, u, moving) {
  if (B.cfg.demo) return;
  g.save();
  /* Частицы вычисляются из времени и id: RNG боя и сетевые поля не меняются. */
  if (u.t.mounted && moving > 35 && u.id % 3 === 0) {
    const t = (B.t * 2.3 + u.ph) % 1, dx = -u.vx / moving, dy = -u.vy / moving;
    g.fillStyle = B.cfg.biome === 'snow' ? 'rgba(241,246,247,.28)' : 'rgba(191,168,113,.24)';
    for (let k = 0; k < 3; k++) { ell(g, u.x + dx * (t * 30 + k * 5) + k * 3, u.y + dy * (t * 30 + k * 5), 3 + t * 5, 1.5 + t * 2); g.fill(); }
  }
  if (u.flash > 0) {
    g.globalAlpha = clamp(u.flash / .13, 0, 1) * .8;
    const x = u.x - Math.cos(u.face) * 7, y = u.y - 22;
    for (let k = 0; k < 3; k++) { const a = u.ph + k * 2.1; line(g, [x + Math.cos(a) * 4, y + Math.sin(a) * 4, x + Math.cos(a) * 10, y + Math.sin(a) * 10], '#ffe5a0', 1.5); }
  }
  g.restore();
}
/* Раздвигаем только названия, не поселения. Важные подписи размещаются первыми. */
function settlementLabels(g, labels, label) {
  const boxes = [], z = WC.z;
  for (const l of labels.slice().sort((a, b) => b[4] - a[4])) {
    const [text, x, y, col, size] = l; g.font = '700 ' + size + 'px "Alegreya Sans SC","Alegreya Sans",sans-serif';
    const w = g.measureText(text).width + 12, h = size + 6; let placed = null;
    for (const offset of [0, 24, -24, 48, -48, 72, -72, 96, -96]) {
      const box = { x: x - w / 2, y: y + offset - h, w, h };
      if (boxes.some(b => box.x < b.x + b.w && box.x + box.w > b.x && box.y < b.y + b.h && box.y + box.h > b.y)) continue;
      placed = box; boxes.push(box); break;
    }
    if (!placed) continue; /* Значок остаётся кликабельным, полное имя — в подсказке. */
    const yy = placed.y + h;
    if (Math.abs(yy - y) > 2) line(g, [x, y - 10, x, yy - h / 2], 'rgba(232,214,166,.5)', 1 / z);
    g.fillStyle = 'rgba(29,24,14,.65)'; g.fillRect(placed.x, placed.y + 2, w, h);
    label(text, x, yy, col, size);
  }
}
function routeFinish(g, P) {
  if (!P.path.length || P.pi >= P.path.length) return;
  const e = P.path[P.path.length - 1], s = 1 / WC.z;
  g.save(); g.fillStyle = '#ffe9a0'; g.strokeStyle = '#292013'; g.lineWidth = 2 * s;
  poly(g, [e.x, e.y - 9 * s, e.x + 7 * s, e.y, e.x, e.y + 9 * s, e.x - 7 * s, e.y]); g.fill(); g.stroke();
  g.font = '700 ' + (12 * s) + 'px "Alegreya Sans",sans-serif'; g.textAlign = 'center'; g.lineWidth = 3 * s; g.strokeText('Цель пути', e.x, e.y - 16 * s); g.fillText('Цель пути', e.x, e.y - 16 * s); g.restore();
}
function gearComparison(it, H) {
  if (!it.slot) return '';
  const before = Object.assign({}, H, { eq: Object.assign({}, heroEq(H)) });
  const after = Object.assign({}, before, { eq: Object.assign({}, before.eq, { [it.slot]: it.id }) });
  if (it.slot === 'shield' && eqItem(before, 'melee')?.hands === 2) return '<p class="dn">С двуручным оружием щит не носят.</p>';
  if (it.slot === 'melee' && it.hands === 2) after.eq.shield = null;
  if (it.slot === 'melee' || it.slot === 'ranged') before.sel = after.sel = it.slot;
  const a = heroDef(before), b = heroDef(after), current = eqItem(before, it.slot);
  const rows = [['Урон', 'dmg', false], ['Броня', 'arm', false], ['Скорость', 'spd', false], ['Удар / перезарядка, с', 'cd', true], ['Блок, %', 'block', false]];
  return '<div class="gearcompare"><small>' + H.name + ' · вместо: ' + (current ? current.name : 'пустого слота') + '</small>' + rows.map(([name, k, lower]) => {
    const mul = k === 'block' ? 100 : 1, old = Math.round(a[k] * mul * 10) / 10, next = Math.round(b[k] * mul * 10) / 10, delta = Math.round((next - old) * 10) / 10;
    return '<div><span>' + name + '</span><b>' + old + ' → ' + next + '</b><em class="' + (!delta ? 'same' : (lower ? delta < 0 : delta > 0) ? 'up' : 'dn') + '">' + (delta > 0 ? '+' : '') + delta + '</em></div>';
  }).join('') + (it.slot === 'melee' && it.hands === 2 && before.eq.shield ? '<small>Щит уйдёт в рюкзак.</small>' : '') + '</div>';
}
function bindGearPeek() {
  const peek = document.createElement('div'); peek.id = 'gearPeek'; peek.hidden = true; peek.setAttribute('role', 'tooltip'); document.body.append(peek);
  let anchor;
  const hide = () => { peek.hidden = true; anchor = null; };
  const show = target => {
    const tile = target.closest('.tile[data-item]'); if (!tile || !UI.open || !G) return hide();
    const it = ITEM[tile.dataset.item]; if (!it) return hide(); anchor = tile;
    const tier = tierOf(it), H = invWho(G.player);
    peek.innerHTML = '<strong style="color:' + (tier?.c || '#e8d6ac') + '">' + it.name + '</strong><small>' + (tier ? tier.n : 'Товар') + '</small>' + (it.slot ? gearComparison(it, H) : '<p>Вес: ' + it.w + ' · обычная цена: ' + it.price + '</p>');
    peek.hidden = false; const r = tile.getBoundingClientRect(), w = peek.offsetWidth, h = peek.offsetHeight;
    peek.style.left = Math.max(8, Math.min(r.right + 12, innerWidth - w - 8)) + 'px'; peek.style.top = Math.max(8, Math.min(r.top, innerHeight - h - 8)) + 'px';
  };
  document.addEventListener('pointerover', e => show(e.target)); document.addEventListener('focusin', e => show(e.target));
  document.addEventListener('pointerout', e => { if (anchor && !anchor.contains(e.relatedTarget)) hide(); });
  document.addEventListener('focusout', hide); document.addEventListener('scroll', hide, true); document.addEventListener('keydown', e => { if (e.key === 'Escape') hide(); });
  new MutationObserver(() => { if (anchor && (!anchor.isConnected || !UI.open)) hide(); }).observe(el('modal'), { childList: true, subtree: true, attributes: true, attributeFilter: ['hidden'] });
}
