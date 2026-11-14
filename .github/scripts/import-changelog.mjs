// Разовый перенос старого CHANGELOG.md в GitHub Releases.
// Вход: путь к CHANGELOG.md, выход: releases.json [{tag, name, body}] от старых к новым.
import { readFileSync, writeFileSync } from 'node:fs';
const src = readFileSync(process.argv[2], 'utf8');
const out = [];
for (const part of src.split(/^## /m).slice(1)) {
  const nl = part.indexOf('\n'), head = part.slice(0, nl), body = part.slice(nl + 1).trim() + '\n';
  const m = head.match(/^(\d+\.\d+\.\d+) — (\S+)/);
  if (m) out.push({ tag: 'v' + m[1], name: `${m[1]} — ${m[2]}`, body });
  else out.push({ tag: 'v0.18.0', name: '0.18.0 — 2026-11-14', body }); // раздел «Не выпущено» на момент переноса
}
out.reverse();
writeFileSync(process.argv[3], JSON.stringify(out, null, 1));
console.log(out.map(r => r.tag).join(' '));
