// Локальная проверка Pull Request вместо CI на GitHub (#255): тот же набор и та же логика выбора тестов, что в
// «Godot — архитектура и Windows» (.github/workflows/godot.yml) и «PR — привязка к issue», но на своём ПК.
// Результат вешается прямо на PR: галка `local/pr-check` на коммите головы и комментарий со сводкой.
//
//   node godot/tools/pr_check.cjs            — на Windows больше ничего не нужно: закреплённый Godot 4.7.2 с export
//                                              templates скрипт сам скачает один раз в dist/godot/engine/
//   node godot/tools/pr_check.cjs <Godot>    — свой Godot (или переменная окружения GODOT); для сборки ему нужны templates
//
//   --no-post                 только прогнать и напечатать сводку, на GitHub ничего не отправлять
//   --post-only               отправить на PR результат последнего прогона (godot/.godot/pr-check.json),
//                             если он сделан на том же коммите, что голова ветки; тесты заново не гоняются
//   --known-red=<тест>#<N>    тест красный и на main, по нему открыт issue #N (можно через запятую или несколько раз):
//                             его падение не валит проверку, но попадает в сводку. Issue должен быть открыт.
//
// Что делает:
// 1. Требует чистое дерево и свою ветку; берёт базу — merge-base с только что обновлённым origin/main.
// 2. Как job `godot-changes`: нет правок в godot/ (кроме godot/docs/*.md) и в godot.yml — Godot-проверки не нужны.
// 3. Иначе как `godot-architecture` и `godot-tests-and-release`: тесты инструментов, архитектура против базы,
//    Godot-тесты, выбранные по изменениям (`--changed=<база>`), сборка и release-smoke.
// 4. Как `pr-issue-link`: в описании PR есть «Closes #N» (или Fixes/Resolves).
// 5. Пишет godot/.godot/pr-check.json и, если ветка запушена и PR открыт, ставит статус и обновляет комментарий.
//    Godot на машине нет (облако): шаги без Godot идут, а на PR уходит «ожидает прогона на Windows», не зелёная галка.
const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const CONTEXT = 'local/pr-check';
const MARKER = '<!-- pr-check -->';
const ISSUE_LINK = /\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\s*:?\s+(#|https:\/\/github\.com\/[^\s]+\/issues\/)[0-9]+/i;
const ENGINE_VERSION = '4.7.2';  // как в engine_bootstrap.ps1 и бывшем CI
const pinnedEngine = repoRoot => path.join(repoRoot, 'dist', 'godot', 'engine', ENGINE_VERSION, `Godot_v${ENGINE_VERSION}-stable_win64_console.exe`);
// Запрос к API без gh: отдельный процесс node, чтобы весь скрипт оставался синхронным.
const FETCH = `const b = require('fs').readFileSync(0, 'utf8');
fetch(process.env.PR_CHECK_URL, {method: process.env.PR_CHECK_METHOD, body: b || undefined, headers: {
  Authorization: 'Bearer ' + process.env.PR_CHECK_TOKEN, Accept: 'application/vnd.github+json', 'User-Agent': 'iron-standard-pr-check'}})
  .then(async r => { const t = await r.text(); if (!r.ok) { process.stderr.write(r.status + ' ' + t); process.exit(1); } process.stdout.write(t); })
  .catch(e => { process.stderr.write(String(e)); process.exit(1); });`;
const TOOL_TESTS = ['architecture.test.cjs', 'test_selection.test.cjs', 'test_schedule.test.cjs', 'build_identity.test.cjs', 'pr_check.test.cjs'];

// ---- чистые функции (их проверяет pr_check.test.cjs) ----

function hasIssueLink(body) { return ISSUE_LINK.test(body || ''); }

// Та же логика, что в job `godot-changes`.
function needsGodot(changed) {
  return changed.filter(f => !/^godot\/docs\/.*\.md$/.test(f)).some(f => /^(godot\/|\.github\/workflows\/godot\.yml$)/.test(f));
}

function parseRepo(url) {
  const m = /github\.com[:/]([^/]+)\/([^/]+?)(\.git)?\/?$/.exec(url.trim());
  return m ? `${m[1]}/${m[2]}` : null;
}

// «tests/unit/a.gd#295,tests/b.gd#12» → [{test, issue}]
function parseKnownRed(values) {
  return values.flatMap(v => v.split(',')).map(s => s.trim()).filter(Boolean).map(s => {
    const m = /^(.+\.gd)#(\d+)$/.exec(s);
    if (!m) throw new Error(`--known-red: ожидаю «путь/test_x.gd#N», а не «${s}»`);
    return {test: m[1].replace(/^godot\//, ''), issue: Number(m[2])};
  });
}

// Падение из test-last-run.json выглядит как «tests/x.gd» или «tests/x.gd (timeout ...)».
function splitFailures(failures, knownRed) {
  const known = new Map(knownRed.map(k => [k.test, k.issue]));
  const allowed = [], real = [];
  for (const f of failures) {
    const test = f.split(' (')[0];
    if (known.has(test)) allowed.push({test, issue: known.get(test)}); else real.push(f);
  }
  return {allowed, real};
}

// Итог для статуса: success — всё зелёное; failure — что-то упало; pending — Godot-шаги не прогнаны.
function verdict(report) {
  if (report.steps.some(s => s.ok === false) || report.issueLink === false) return 'failure';
  if (report.godot && !report.engine) return 'pending';
  if (report.issueLink === null) return 'pending';
  return 'success';
}

function statusDescription(report) {
  const v = verdict(report);
  const failed = report.steps.find(s => s.ok === false);
  if (v === 'failure') return failed ? `Упало: ${failed.name}` : 'В описании PR нет «Closes #N»';
  if (v === 'pending') return report.godot && !report.engine ? 'Godot-тесты не прогнаны: нужен прогон на Windows' : 'PR ещё не открыт';
  const t = report.tests;
  return report.godot ? `Зелёная${t ? `: Godot-тесты ${t.passed} из ${t.selected}` : ''}` : 'Зелёная: правок в godot/ нет';
}

function summary(report) {
  const short = s => (s || '').slice(0, 10);
  const icon = {success: '✅', failure: '❌', pending: '⏳'}[verdict(report)];
  const lines = [MARKER, `## Локальная проверка ${icon}`, '',
    `\`node godot/tools/pr_check.cjs\` на коммите \`${short(report.head)}\` (база \`${short(report.base)}\` от \`origin/main\`), ${report.date.slice(0, 16).replace('T', ' ')} UTC` +
    (report.machine ? `, ${report.machine}` : '') + (report.engineVersion ? `, Godot ${report.engineVersion}` : '') + '.', ''];
  if (!report.godot) lines.push('- Правок в `godot/` нет (или только `godot/docs/*.md`) — Godot-проверки не нужны, как и в CI.');
  for (const s of report.steps) lines.push(`- ${s.ok ? '✓' : '✗'} ${s.name}${s.seconds != null ? ` — ${s.seconds} с` : ''}${s.note ? ` (${s.note})` : ''}`);
  if (report.godot && !report.engine) lines.push('- ⏳ Godot-тесты, сборка и release-smoke **не прогнаны**: на этой машине нет Godot. Нужен прогон на Windows-ПК.');
  if (report.tests) lines.push('', `Godot-тесты: ${report.tests.passed} из ${report.tests.selected} зелёные${report.tests.full ? ' (полный набор)' : ' (выбраны по изменениям)'}.`);
  if (report.failures?.length) lines.push('', '**Красные тесты:**', ...report.failures.map(f => `- \`${f}\``));
  if (report.knownRed?.length) lines.push('', 'Красные и на `main`, по ним открыт issue — проверку не валят:', ...report.knownRed.map(k => `- \`${k.test}\` (#${k.issue})`));
  if (report.issueLink === false) lines.push('', '✗ В описании PR нет строки `Closes #N` — допиши её, иначе issue не закроется при слиянии.');
  if (report.issueLink === null) lines.push('', '⏳ PR ещё не открыт: после `gh pr create` запусти `node godot/tools/pr_check.cjs --post-only`.');
  lines.push('', '_Новый пуш в ветку — нужен новый прогон: галка `local/pr-check` привязана к коммиту._');
  return lines.join('\n');
}

module.exports = {pinnedEngine, ENGINE_VERSION, hasIssueLink, needsGodot, parseRepo, parseKnownRed, splitFailures, verdict, statusDescription, summary, CONTEXT, MARKER};

// ---- запуск ----

if (require.main === module) main();

function main() {
  const repoRoot = path.resolve(__dirname, '..', '..');
  const godotDir = path.join(repoRoot, 'godot');
  const reportFile = path.join(godotDir, '.godot', 'pr-check.json');
  const args = process.argv.slice(2);
  const flag = name => args.includes(name);
  const values = name => args.filter(a => a.startsWith(`${name}=`)).map(a => a.slice(name.length + 1));
  const noPost = flag('--no-post'), postOnly = flag('--post-only');
  const run = (exe, a, opts = {}) => cp.spawnSync(exe, a, {cwd: repoRoot, encoding: 'utf8', windowsHide: true, ...opts});
  const git = (...a) => {
    const r = run('git', a);
    if (r.error || r.status !== 0) throw new Error(`git ${a.join(' ')}: ${(r.stderr || r.error?.message || '').trim()}`);
    return r.stdout.trim();
  };
  const fail = message => { console.error(`\n✗ ${message}`); process.exit(1); };

  // GitHub API для PR, статуса и комментария. Сначала gh (если он есть и в нём выполнен вход), иначе — токен из
  // GH_TOKEN / GITHUB_TOKEN или тот, что уже хранит git (Git Credential Manager на Windows): ставить и логинить gh не нужно.
  let apiMode;
  const credentialToken = () => {
    const r = run('git', ['credential', 'fill'], {input: 'protocol=https\nhost=github.com\n\n', timeout: 15000,
      env: {...process.env, GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'never'}});
    return r.status === 0 ? (/^password=(.+)$/m.exec(r.stdout) || [])[1] : null;
  };
  const api = (method, route, body) => {
    if (apiMode === undefined) {
      // Пробуем настоящим запросом, а не `gh auth status`: в облаке вход даёт прокси, и статус входа врёт.
      const g = run('gh', ['api', 'user'], {timeout: 30000});
      const ghOk = !g.error && g.status === 0;
      const token = ghOk ? null : process.env.GH_TOKEN || process.env.GITHUB_TOKEN || credentialToken();
      apiMode = ghOk ? {gh: true} : token ? {token} : null;
    }
    if (!apiMode) throw new Error('нет ни gh со входом, ни токена GitHub (GH_TOKEN или сохранённый вход git)');
    const input = body === undefined ? '' : JSON.stringify(body);
    const r = apiMode.gh
      ? run('gh', ['api', '-X', method, route, ...(input ? ['--input', '-'] : [])], {input})
      : run(process.execPath, ['-e', FETCH], {input, env: {...process.env, PR_CHECK_URL: `https://api.github.com/${route}`, PR_CHECK_METHOD: method, PR_CHECK_TOKEN: apiMode.token}});
    if (r.error || r.status !== 0) throw new Error(`${method} ${route.split('?')[0]}: ${(r.stderr || r.error?.message || '').trim().slice(0, 300)}`);
    return r.stdout ? JSON.parse(r.stdout) : null;
  };

  const dirty = git('status', '--porcelain', '--untracked-files=normal');
  if (dirty) fail(`Есть незакоммиченные изменения — закоммить их, иначе проверка не про то, что уйдёт в PR:\n${dirty}`);
  const branch = git('rev-parse', '--abbrev-ref', 'HEAD');
  if (branch === 'main' || branch === 'HEAD') fail('Проверка идёт на своей ветке задачи, не на main (навык git-flow).');
  const head = git('rev-parse', 'HEAD');
  const repo = parseRepo(git('remote', 'get-url', 'origin'));

  let report;
  if (postOnly) {
    try { report = JSON.parse(fs.readFileSync(reportFile, 'utf8')); } catch { fail(`Нет отчёта ${reportFile}: сначала обычный прогон.`); }
    if (report.head !== head) fail(`Отчёт сделан на ${report.head.slice(0, 10)}, а голова ветки ${head.slice(0, 10)}: нужен новый прогон.`);
  } else {
    report = check();
  }

  // PR и «Closes #N».
  let pr = null, postError = null;
  try {
    const owner = repo.split('/')[0];
    const list = api('GET', `repos/${repo}/pulls?state=open&head=${owner}:${encodeURIComponent(branch)}`);
    pr = list[0] || null;
  } catch (e) { postError = e.message; }
  report.pr = pr ? pr.number : null;
  report.issueLink = pr ? hasIssueLink(pr.body) : null;
  fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));

  const text = summary(report);
  const v = verdict(report);
  console.log(`\n${text}\n`);

  if (noPost) console.log('--no-post: на GitHub ничего не отправлено.');
  else if (postError) console.log(`! Не удалось связаться с GitHub (${postError}). Сводка выше — для комментария к PR.`);
  else if (!pr) console.log(`PR из ветки ${branch} не найден. Открой его (gh pr create) и запусти: node godot/tools/pr_check.cjs --post-only`);
  else {
    let remoteHead = '';
    try { remoteHead = git('ls-remote', 'origin', `refs/heads/${branch}`).split(/\s+/)[0]; } catch { /* ниже сообщим */ }
    if (remoteHead !== head) fail(`Голова ветки на GitHub (${(remoteHead || 'нет').slice(0, 10)}) не совпадает с проверенной ${head.slice(0, 10)}: запушь ветку и запусти --post-only.`);
    // Статус и комментарий — независимо: облачный прокси, например, пускает комментарии, но не статусы.
    try {
      api('POST', `repos/${repo}/statuses/${head}`, {state: v, context: CONTEXT, description: statusDescription(report).slice(0, 140)});
      console.log(`→ PR #${pr.number}: статус «${CONTEXT}» = ${v}.`);
    } catch (e) { console.log(`! Статус не поставлен (${e.message}). Сводка в комментарии всё равно говорит итог.`); }
    try {
      const me = api('GET', 'user').login;
      const comments = api('GET', `repos/${repo}/issues/${pr.number}/comments?per_page=100`);
      const own = comments.find(c => c.user?.login === me && (c.body || '').startsWith(MARKER));
      if (own) api('PATCH', `repos/${repo}/issues/comments/${own.id}`, {body: text});
      else api('POST', `repos/${repo}/issues/${pr.number}/comments`, {body: text});
      console.log(`→ PR #${pr.number}: сводка ${own ? 'обновлена' : 'добавлена'} в комментарии.`);
    } catch (e) { console.log(`! Комментарий не отправлен (${e.message}). Вставь сводку выше в PR руками.`); }
  }
  process.exit(v === 'failure' ? 1 : 0);

  // База PR — merge-base с origin/main. Явный refspec: в клоне одной ветки (`--branch X --single-branch`, облако)
  // `git fetch origin main` пишет только FETCH_HEAD и origin/main не появляется. В shallow-клоне общего предка
  // может не быть в загруженной истории — догружаем её частями, пока merge-base не найдётся.
  function mergeBase() {
    const MAIN = 'refs/remotes/origin/main';
    const shallow = () => { try { return git('rev-parse', '--is-shallow-repository') === 'true'; } catch { return false; } };
    const fetchMain = (...extra) => git('fetch', '--quiet', ...extra, 'origin', `+refs/heads/main:${MAIN}`);
    try { fetchMain(...(shallow() ? ['--depth=50'] : [])); }
    catch (e) { console.warn(`! Не удалось обновить origin/main (${e.message}); беру локальный.`); }
    const tryBase = () => { const r = run('git', ['merge-base', MAIN, 'HEAD']); return r.status === 0 ? r.stdout.trim() : null; };
    let base = tryBase();
    for (const depth of [200, 1000, 5000]) {
      if (base || !shallow()) break;
      try { git('fetch', '--quiet', `--deepen=${depth}`, 'origin', `+refs/heads/main:${MAIN}`, `+refs/heads/${branch}:refs/remotes/origin/${branch}`); }
      catch (e) { console.warn(`! Не удалось догрузить историю (${e.message}).`); break; }
      base = tryBase();
    }
    if (!base) fail('Не нашёл общего предка ветки и origin/main: нет origin/main или история обрезана (shallow-клон) — сделай `git fetch origin main` без --depth.');
    return base;
  }

  function check() {
    const base = mergeBase();
    const changed = git('diff', '--name-only', base, 'HEAD').split('\n').filter(Boolean);
    const godot = needsGodot(changed);
    let engine = args.find(a => !a.startsWith('--')) || process.env.GODOT || '';
    const knownRed = parseKnownRed(values('--known-red'));
    const r = {head, base, branch, godot, engine: null, engineVersion: null, steps: [], tests: null, failures: [], knownRed: [],
      machine: process.platform === 'win32' ? 'Windows' : process.platform, date: new Date().toISOString()};
    const save = () => { fs.mkdirSync(path.dirname(reportFile), {recursive: true}); fs.writeFileSync(reportFile, JSON.stringify(r, null, 2)); };
    // Шаг упал — дальше не идём, но результат всё равно уходит на PR.
    const step = (name, exe, a) => {
      console.log(`\n▶ ${name}`);
      const started = Date.now();
      const res = cp.spawnSync(exe, a, {cwd: repoRoot, stdio: 'inherit', windowsHide: true});
      const s = {name, ok: !res.error && res.status === 0, seconds: Math.round((Date.now() - started) / 1000)};
      r.steps.push(s);
      return s;
    };
    const node = process.execPath, tool = t => path.join(godotDir, 'tools', t);
    if (!godot) { console.log('Правок в godot/ нет (или только godot/docs/*.md) — Godot-проверки не нужны, как и в CI.'); save(); return r; }

    // godot-architecture: работает везде, Godot не нужен.
    for (const t of TOOL_TESTS) if (fs.existsSync(tool(t)) && !step(t, node, [tool(t)]).ok) { save(); return r; }
    if (!step('Архитектура и запрет новых исключений', node, [tool('architecture.cjs'), `--base=${base}`]).ok) { save(); return r; }

    // godot-tests-and-release. На Windows без явного Godot берём закреплённый, как CI: скрипт сам скачает его один раз
    // в dist/godot/engine/ (engine_bootstrap.ps1) и подготовит native-инструменты (native_bootstrap.ps1).
    if (process.platform === 'win32') {
      const ps = run('where', ['pwsh']).status === 0 ? 'pwsh' : 'powershell';
      const psFile = f => ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', tool(f)];
      if (!engine) {
        if (!step('Закреплённый Godot ' + ENGINE_VERSION + ' и export templates', ps, psFile('engine_bootstrap.ps1')).ok) { save(); return r; }
        engine = pinnedEngine(repoRoot);
      }
      if (!step('Пакетное ядро контактов (native_bootstrap)', ps, psFile('native_bootstrap.ps1')).ok) { save(); return r; }
    }
    if (!engine) {
      console.log('\n⏳ Это не Windows и Godot не указан (аргумент или GODOT) — Godot-тесты, сборка и release-smoke не прогнаны.');
      save(); return r;
    }
    r.engine = path.basename(engine);
    const ver = run(engine, ['--version', '--headless'], {timeout: 60000});
    r.engineVersion = (ver.stdout || '').trim().split('\n').pop() || null;
    for (const k of knownRed) {
      try {
        const issue = api('GET', `repos/${repo}/issues/${k.issue}`);
        if (issue.state !== 'open') fail(`--known-red: issue #${k.issue} закрыт — значит тест ${k.test} должен быть зелёным.`);
      } catch (e) { console.warn(`! Не проверил, что #${k.issue} открыт: ${e.message}`); }
    }
    const testStep = step('Godot-тесты, затронутые правкой', node, [tool('test.cjs'), engine, `--changed=${base}`]);
    try {
      const last = JSON.parse(fs.readFileSync(path.join(godotDir, '.godot', 'test-last-run.json'), 'utf8'));
      const {allowed, real} = splitFailures(last.failures || [], knownRed);
      r.tests = {selected: last.selected, passed: last.passed};
      r.failures = real; r.knownRed = allowed;
      // Упали только известные красные с открытым issue — шаг считаем пройденным.
      if (!testStep.ok && last.failures?.length && !real.length) { testStep.ok = true; testStep.note = `известные красные: ${allowed.length}`; }
    } catch { /* нет отчёта — значит упала подготовка, шаг уже красный */ }
    if (!testStep.ok) { save(); return r; }
    step('Сборка и release-smoke', node, [tool('release.cjs'), engine]);
    save(); return r;
  }
}
