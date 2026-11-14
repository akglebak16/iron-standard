// Собирает заметки к релизу из PR, слитых в main после прошлого релиза.
// Из описания каждого PR берётся раздел «## Для игрока» (до следующего заголовка ##).
// Вход: prs.json (gh pr list --json number,title,body,mergedAt,url), выход: notes.md
import { readFileSync, writeFileSync } from 'node:fs';
const prs = JSON.parse(readFileSync(process.argv[2], 'utf8')).sort((a, b) => a.mergedAt.localeCompare(b.mergedAt));
const lines = [], dev = [];
for (const pr of prs) {
  const body = (pr.body || '').replace(/\r/g, '');
  const m = body.match(/^##\s*Для игрока\s*\n([\s\S]*?)(?=^##\s|(?![\s\S]))/m);
  const txt = m ? m[1].replace(/<!--[\s\S]*?-->/g, '').trim() : '';
  if (txt && !/^[-*]?\s*(нет|ничего|—|-)\.?$/i.test(txt)) lines.push(txt.split('\n').map(l => l.trimEnd()).join('\n') + ` (#${pr.number})`);
  else dev.push(`- ${pr.title} (#${pr.number})`);
}
let md = lines.length ? lines.join('\n') + '\n' : '- Изменений для игрока нет.\n';
if (dev.length) md += '\n### Без изменений для игрока\n' + dev.join('\n') + '\n';
writeFileSync(process.argv[3], md);
console.log(md);
