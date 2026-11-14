/* ================= осада: интерфейс и картинка на карте мира =================
   Выбор после штурма (разграбить или пощадить) и пожары на карте. Только клиент. */
ACT.sgsack = function () { const P = G.player, s = settleById(P.sgPend); P.sgPend = null; if (s) sgSack(P, s); sfx('coin'); closeModal(); afterBattle(); };
ACT.sgspare = function () { const P = G.player, s = settleById(P.sgPend); P.sgPend = null; if (s) sgSpare(P, s); sfx('click'); closeModal(); afterBattle(); };
// пламя над горящими поселениями, дым над сильно повреждёнными; зовётся из drawWar
function sgDraw(g, t, label) {
  for (const s of G.settles) {
    const fire = s.fire > 0, smoke = !fire && (s.dmg || 0) > .3; if (!fire && !smoke) continue;
    const bx = s.x, by = s.y - 8;
    g.save();
    for (let i = 0; i < 3; i++) { const p = (t * .35 + i / 3 + s.id * .13) % 1; g.globalAlpha = (1 - p) * (fire ? .5 : .35); g.fillStyle = '#4a4540'; g.beginPath(); g.arc(bx + Math.sin(p * 5 + i) * 8 + (i - 1) * 8, by - 18 - p * 46, 7 + p * 11, 0, TAU); g.fill(); }
    if (fire) for (let i = 0; i < 6; i++) {
      const ox = (i - 2.5) * 8 + Math.sin(s.id + i * 2) * 3, h = 13 + 7 * Math.sin(t * 3.2 + i * 2.1 + s.id), x = bx + ox, y = by + Math.abs(Math.cos(s.id * 3 + i)) * 6;
      g.globalAlpha = .9; g.fillStyle = i % 2 ? '#ff9a2e' : '#ffd26a'; g.beginPath(); g.moveTo(x - 5, y); g.quadraticCurveTo(x - 3, y - h * .6, x + Math.sin(t * 2 + i) * 2.5, y - h); g.quadraticCurveTo(x + 3, y - h * .5, x + 5, y); g.closePath(); g.fill();
    }
    g.restore();
    if (fire && typeof label === 'function') label('Пожар', s.x, s.y - 74, '#ffb066', 12);
  }
}
