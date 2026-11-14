// Сборка страницы роудмапа из roadmap/tasks/*.md.
//   node roadmap/build.mjs                 — проверить задачи и собрать roadmap/index.html из текущей папки
//   node roadmap/build.mjs --check         — только проверить (CI падает, если задача оформлена неправильно)
//   node roadmap/build.mjs --branches out  — как в CI: main + свежие статусы из всех веток origin/*, запись в файл out
// Правила оформления задач — shareness/skills/роудмап-разработки/SKILL.md
import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';
import { fileURLToPath } from 'url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const TASKS = path.join(ROOT, 'tasks');
const REPO = 'akglebak16/iron-standard';
export const STATUSES = ['идея', 'можно брать', 'в работе', 'на проверке', 'готово'];
const PRIOR = ['высокий', 'обычный', 'низкий'];
const KEYS = ['title', 'status', 'owner', 'area', 'priority', 'created', 'done', 'pr', 'outside'];

const args = process.argv.slice(2);
const CHECK = args.includes('--check');
const BRANCHES = args.includes('--branches');
const OUT = args.filter(a => !a.startsWith('--'))[0] || path.join(ROOT, 'index.html');

function parse(text, id, where) {
  const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/.exec(text);
  const errs = [];
  if (!m) return { errs: [`${where}: нет шапки между строками ---`] };
  const t = { id, body: m[2].trim() };
  for (const line of m[1].split(/\r?\n/)) {
    if (!line.trim() || line.trim().startsWith('#')) continue;
    const kv = /^([a-z]+):\s*(.*)$/.exec(line);
    if (!kv) { errs.push(`${where}: непонятная строка «${line}»`); continue; }
    if (!KEYS.includes(kv[1])) errs.push(`${where}: неизвестное поле «${kv[1]}» (можно: ${KEYS.join(', ')})`);
    t[kv[1]] = kv[2].replace(/^["']|["']$/g, '').trim();
  }
  if (!t.title) errs.push(`${where}: нет title`);
  if (!STATUSES.includes(t.status)) errs.push(`${where}: status «${t.status || ''}», а можно: ${STATUSES.join(' / ')}`);
  if (t.priority && !PRIOR.includes(t.priority)) errs.push(`${where}: priority «${t.priority}», а можно: ${PRIOR.join(' / ')}`);
  if (t.status === 'в работе' && !t.owner) errs.push(`${where}: в работе, но не указан owner`);
  for (const k of ['created', 'done']) if (t[k] && !/^\d{4}-\d\d-\d\d$/.test(t[k])) errs.push(`${where}: ${k} должен быть ГГГГ-ММ-ДД`);
  if (t.pr && !/^\d+$/.test(t.pr.replace('#', ''))) errs.push(`${where}: pr — номер Pull Request, например 15`);
  t.pr = t.pr ? t.pr.replace('#', '') : '';
  t.outside = /^(да|yes|true)$/i.test(t.outside || '');
  t.priority = t.priority || 'обычный';
  return { t, errs };
}

const git = (...a) => execFileSync('git', a, { cwd: path.join(ROOT, '..'), encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
const SLUG = /^[a-z0-9][a-z0-9-]*\.md$/;

// задачи из рабочей папки
const errs = [];
const tasks = new Map();
for (const f of fs.readdirSync(TASKS).filter(f => f.endsWith('.md')).sort()) {
  if (!SLUG.test(f)) errs.push(`roadmap/tasks/${f}: имя файла — латиница, цифры и дефисы (пример: godot-port.md)`);
  const r = parse(fs.readFileSync(path.join(TASKS, f), 'utf8'), f.slice(0, -3), `roadmap/tasks/${f}`);
  errs.push(...r.errs);
  if (r.t) tasks.set(r.t.id, { ...r.t, branch: '' });
}
if (errs.length) { console.error('Роудмап: ошибки в задачах\n- ' + errs.join('\n- ')); process.exit(1); }
if (CHECK) { console.log(`Роудмап: ${tasks.size} задач, всё оформлено верно`); process.exit(0); }

// свежие статусы из веток: берём версию задачи из той ветки, где её меняли последней
if (BRANCHES) {
  const ctime = (ref, file) => +(git('log', '-1', '--format=%ct', ref, '--', file).trim() || 0);
  const refs = git('for-each-ref', '--format=%(refname:short)', 'refs/remotes/origin').split('\n')
    .filter(r => r && r !== 'origin/main' && r !== 'origin/HEAD' && r !== 'origin');
  const best = new Map(); // id -> {time, t}
  for (const t of tasks.values()) best.set(t.id, { time: ctime('HEAD', `roadmap/tasks/${t.id}.md`), t });
  for (const ref of refs) {
    let list = [];
    try { list = git('ls-tree', '-r', '--name-only', ref, 'roadmap/tasks/').split('\n').filter(f => f.endsWith('.md')); } catch { continue; }
    for (const file of list) {
      const id = path.basename(file, '.md');
      let text; try { text = git('show', `${ref}:${file}`); } catch { continue; }
      const main = tasks.get(id);
      if (main && main.status === 'готово') continue; // готовое в main не перебиваем
      const r = parse(text, id, `${ref}:${file}`);
      if (!r.t || r.errs.length) { console.warn(r.errs.join('\n')); continue; }
      if (main && r.t.status === main.status && r.t.owner === main.owner && r.t.title === main.title && r.t.body === main.body) continue;
      const time = ctime(ref, file);
      const cur = best.get(id);
      if (!cur || time > cur.time) best.set(id, { time, t: { ...r.t, branch: ref.replace(/^origin\//, '') } });
    }
  }
  tasks.clear();
  for (const [id, v] of best) tasks.set(id, v.t);
}

const data = { repo: REPO, built: new Date().toISOString(), statuses: STATUSES, tasks: [...tasks.values()] };
const page = fs.readFileSync(path.join(ROOT, 'page.html'), 'utf8')
  .replace('/*DATA*/null', () => JSON.stringify(data).replace(/</g, '\\u003c'));
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, page);
const by = s => data.tasks.filter(t => t.status === s).length;
console.log(`Роудмап: ${data.tasks.length} задач (${STATUSES.map(s => s + ' ' + by(s)).join(', ')}) → ${path.relative(process.cwd(), OUT)}`);
