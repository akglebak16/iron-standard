/* ================= оборона стен в штурме: камни и котлы с кипящим маслом =================
   Только клиент (одиночная игра), на сервер не грузить: общий код боя зовёт sdUpdate / sdDraw через typeof.
   Состояние: B.sd = { stones, cd, shots[], fires[], oil[{ g, ch, cd }] }.
   Запасы задаёт sgDefCfg (05i_siege.js), повреждённые стены (B.cfg.dmg) их урезают. Осадное дело спутника
   (B.siegeF) ослабляет урон: он знает, куда бьют защитники. Камень падает с задержкой и отмечен кольцом: от него можно отбежать. */
function sdInit() {
  const c = B.cfg.sdef || { stones: 10, oil: 2 }, dm = clamp(B.cfg.dmg || 0, 0, 1), k = 1 - dm * .6;
  B.sd = { stones: Math.round(c.stones * k), cd: 5, shots: [], fires: [], said: 0,
    oil: B.wall.gaps.map((g, i) => ({ g, ch: Math.max(i ? (c.oil >= 3 ? 1 : 0) : 1, Math.round(c.oil * k * (i ? .67 : 1))), cd: 4 + i * 2 })) };
}
function sdUpdate(dt) {
  if (!B.wall) return; if (!B.sd) sdInit();
  const S = B.sd, w = B.wall, kk = 1 - (B.siegeF || 0) * .5, atk = [];
  let ndef = 0; for (const u of B.units) { if (u.side === 1 && fit(u) && u.x > w.x - 10) ndef++; else if (u.side === 0 && fit(u)) atk.push(u); }
  S.cd -= dt;
  if (S.stones > 0 && S.cd <= 0 && ndef >= 6) { // камень по самой плотной кучке у стены
    let best = null, bn = 0;
    for (const u of atk) { if (u.x > w.x - 8 || u.x < w.x - 320) continue; let n = 0; for (const v of atk) if (Math.abs(v.x - u.x) < 60 && Math.abs(v.y - u.y) < 60) n++; if (n > bn) { bn = n; best = u; } }
    if (best && bn >= 2) {
      const tx = best.x + best.vx * .6, ty = best.y + best.vy * .6;
      S.shots.push({ x0: w.x + 18, y0: clamp(ty, 60, B.H - 60), tx, ty, t: 0, dur: .95 }); S.stones--; S.cd = rnd(4.5, 7) / (.6 + .4 * Math.min(1, ndef / 25)); sfx('swing');
      if (!S.said && !B.cfg.demo) { S.said = 1; blog('Со стены летят камни', 1); }
    } else S.cd = 1.2;
  }
  for (let i = S.shots.length - 1; i >= 0; i--) { // падение камней
    const s = S.shots[i]; s.t += dt; if (s.t < s.dur) continue; S.shots.splice(i, 1);
    const R = 52; for (const u of atk) { const d = Math.hypot(u.x - s.tx, u.y - s.ty); if (d < R && fit(u)) { hurt(u, Math.round(32 * (1 - d / R * .5) * kk), null, 0); u.morale -= 4; } }
    fxSpark(s.tx, s.ty - 6); for (let j = 0; j < 4; j++) fxDust(s.tx + rnd(-20, 20), s.ty + rnd(-12, 12)); sfx('thud');
    for (const u of atk) if (u.isHero && !u.ai && Math.hypot(u.x - s.tx, u.y - s.ty) < 170) B.shake = Math.max(B.shake || 0, .22);
    if (B.gg) { const g = B.gg; g.save(); g.fillStyle = 'rgba(40,30,20,.45)'; ell(g, s.tx, s.ty, 17, 9); g.fill(); g.fillStyle = '#6d6252'; for (let j = 0; j < 4; j++) { ell(g, s.tx + rnd(-14, 14), s.ty + rnd(-7, 7), rnd(2, 4), rnd(1.5, 3)); g.fill(); } g.restore(); }
  }
  for (const o of S.oil) { // котлы: льют, когда у пролома скопились враги
    o.cd -= dt; if (o.ch <= 0 || o.cd > 0 || ndef < 4) continue;
    const g0 = o.g[0], g1 = o.g[1]; let n = 0; for (const u of atk) if (u.x > w.x - 140 && u.x < w.x + w.hw && u.y > g0 - 40 && u.y < g1 + 40) n++;
    if (n < 3) continue;
    o.ch--; o.cd = 14; S.fires.push({ x: w.x - 36, y: (g0 + g1) / 2, hw: 64, hh: Math.max(46, (g1 - g0) / 2 + 12), t: 0, dur: 6, hit: 0, y0: g0 }); sfx('clang');
    for (const u of atk) if (Math.abs(u.x - (w.x - 36)) < 64 && Math.abs(u.y - (g0 + g1) / 2) < Math.max(46, (g1 - g0) / 2 + 12)) u.morale -= 6;
    if (!B.cfg.demo && S.said < 2) { S.said = 2; blog('Со стены льют кипящее масло!', 1); }
  }
  for (let i = S.fires.length - 1; i >= 0; i--) {
    const f = S.fires[i]; f.t += dt; f.hit -= dt; if (f.t >= f.dur) { S.fires.splice(i, 1); continue; }
    if (f.hit <= 0) { f.hit = .5; for (const u of atk) if (fit(u) && Math.abs(u.x - f.x) < f.hw && Math.abs(u.y - f.y) < f.hh) { hurt(u, Math.round(6 * kk), null, .5); u.morale -= 1.6; } }
  }
}
// слой 0 — под фигурками (огонь, котлы), слой 1 — над ними (летящие камни и кольца падения)
function sdDraw(g, layer) {
  const S = B.sd, w = B.wall; if (!S || !w) return;
  if (layer === 0) {
    for (const o of S.oil) { const x = w.x + 6, y = o.g[0] - 12; // котёл на стене у пролома
      g.fillStyle = 'rgba(0,0,0,.3)'; ell(g, x + 3, y + 8, 15, 7); g.fill();
      g.fillStyle = o.ch > 0 ? '#2b2824' : '#4a4640'; ell(g, x, y, 13, 11); g.fill(); g.strokeStyle = '#14100c'; g.lineWidth = 2; g.stroke();
      g.fillStyle = o.ch > 0 ? '#d9822b' : '#6d6252'; ell(g, x, y - 3, 9, 5); g.fill();
      if (o.ch > 0) { g.globalAlpha = .6 + .3 * Math.sin(B.t * 8 + y); g.fillStyle = '#ffd26a'; ell(g, x, y + 10, 5, 3); g.fill(); g.globalAlpha = 1; } }
    for (const f of S.fires) {
      const life = clamp((f.dur - f.t) / 2, 0, 1), pour = clamp(1 - f.t / .9, 0, 1);
      g.save(); g.globalAlpha = life * .45; g.fillStyle = '#c4551a'; ell(g, f.x, f.y, f.hw, f.hh); g.fill(); g.restore();
      if (pour > 0) { g.save(); g.globalAlpha = pour; g.strokeStyle = '#e08a2c'; g.lineWidth = 5; g.beginPath(); g.moveTo(w.x + 6, f.y0 - 10); g.lineTo(f.x + 10, f.y - f.hh * .4); g.stroke(); g.restore(); }
      for (let i = 0; i < 14; i++) { const px = f.x + Math.sin(i * 7.1) * f.hw * .8, py = f.y + Math.cos(i * 3.3) * f.hh * .8, h = 15 + 8 * Math.sin(B.t * 9 + i * 1.7);
        g.save(); g.globalAlpha = life * .85; g.fillStyle = i % 3 ? '#ff9a2e' : '#ffd26a'; g.beginPath(); g.moveTo(px - 6, py); g.quadraticCurveTo(px - 3, py - h * .6, px + Math.sin(B.t * 7 + i) * 3, py - h); g.quadraticCurveTo(px + 3, py - h * .5, px + 6, py); g.closePath(); g.fill(); g.restore(); }
    }
  } else {
    for (const s of S.shots) {
      const p = s.t / s.dur, x = lerp(s.x0, s.tx, p), yg = lerp(s.y0, s.ty, p), y = yg - Math.sin(p * Math.PI) * 110;
      g.save(); g.globalAlpha = .35 + .3 * p; g.strokeStyle = '#e2503c'; g.lineWidth = 2; ell(g, s.tx, s.ty, 52 * (.5 + .5 * p), 52 * (.5 + .5 * p) * .45); g.stroke(); g.restore(); // куда упадёт
      g.fillStyle = 'rgba(0,0,0,.3)'; ell(g, x, yg + 4, 8, 4); g.fill();
      g.fillStyle = '#7c7364'; ell(g, x, y, 8, 8); g.fill(); g.strokeStyle = '#2a2219'; g.lineWidth = 1.6; g.stroke();
    }
  }
}
