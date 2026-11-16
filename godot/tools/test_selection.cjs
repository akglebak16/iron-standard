// Какие Godot-тесты гонять при правке: по графу ссылок `res://...` (preload, load, .tscn, .tres, json-каталоги).
// Тест выбирается, если от него по ссылкам можно дойти до изменённого файла. Всё, чего граф не видит,
// даёт полный набор: безопаснее потратить время, чем пропустить сломанный тест.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// Include committed changes since base, the index, working tree and new files.
function changedFiles(root, base) {
  const run = args => spawnSync('git', args, { cwd: root, encoding: 'utf8', windowsHide: true });
  const diff = run(['diff', '--name-only', '-z', '--relative', base, '--', '.']);
  const untracked = run(['ls-files', '--others', '--exclude-standard', '-z', '--', '.']);
  if (diff.error || diff.status !== 0 || untracked.error || untracked.status !== 0) return null;
  return [...new Set([...diff.stdout.split('\0'), ...untracked.stdout.split('\0')].filter(Boolean))];
}

const SKIP_DIRS = new Set(['.godot', '.git', 'dist', 'node_modules']);
const TEXT = /\.(gd|tscn|tres|gdextension|gdshader|json|cfg)$/;
const IGNORED = /^docs\/.*\.md$|\.uid$|\.import$/;
// Node and PowerShell authoring scripts have their own checks and never run inside Godot tests;
// the native kernel build is the exception: it changes what every battle test runs on.
// Картинки и заметки в tools/ (превью для PR, эталонные кадры) читают только сами авторские скрипты;
// ни игра, ни Godot-тесты на них не ссылаются (tools/previews и tools/baseline закрыты .gdignore или не входят в res:// граф).
const TOOL_ARTIFACTS = /^tools\/.*\.(png|gif|jpg|jpeg|webp|md|gdignore)$/;
const NODE_TOOLS = /^tools\/(?!native_)[^/]*\.(cjs|js|mjs|ps1|py|md|json)$|^tools\/[a-z_]+\/[^/]*\.(cjs|js|mjs|py|json)$/;
// Правка этих файлов может изменить поведение всего проекта.
const GLOBAL = new Set(['project.godot', 'export_presets.cfg']);
// Только эти папки видит граф; правка в другом месте (tools, нативные исходники и т.п.) = полный набор.
const GRAPH_DIRS = /^(core|apps|adapters|content|runtime|tests)\//;
const TEST_FILE = /^tests\/.*\btest_[^/]*\.gd$/;
const ALWAYS = /^tests\/architecture\//;

function walk(root, dir = '', out = []) {
  for (const entry of fs.readdirSync(path.join(root, dir), { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!SKIP_DIRS.has(entry.name)) walk(root, dir + entry.name + '/', out);
    } else out.push(dir + entry.name);
  }
  return out;
}

/** dependents: путь -> множество файлов, которые на него ссылаются. */
function buildGraph(root) {
  const files = walk(root);
  const dirs = new Set();
  for (const file of files) {
    const parts = file.split('/');
    for (let i = 1; i < parts.length; i++) dirs.add(parts.slice(0, i).join('/') + '/');
  }
  const dependents = new Map();
  const link = (target, source) => {
    if (target === source) return;
    if (!dependents.has(target)) dependents.set(target, new Set());
    dependents.get(target).add(source);
  };
  for (const file of files) {
    if (!TEXT.test(file) && file !== 'project.godot') continue;
    const text = fs.readFileSync(path.join(root, file), 'utf8');
    for (const match of text.matchAll(/res:\/\/([^"'\s)\]}]+)/g)) {
      let ref = match[1].replace(/[.,;]+$/, '');
      if (ref.includes('%')) ref = ref.slice(0, ref.indexOf('%')).replace(/[^/]*$/, '');
      if (ref.endsWith('/') || dirs.has(ref + '/')) {
        const prefix = ref.endsWith('/') ? ref : ref + '/';
        for (const other of files) if (other.startsWith(prefix)) link(other, file);
      } else link(ref, file);
    }
  }
  return { files, dependents };
}

/** {full: true, reason} или {full: false, tests: Set<путь теста>}. */
function selectTests(root, changed) {
  const { dependents } = buildGraph(root);
  const tests = new Set();
  const seen = new Set();
  const queue = [];
  for (const file of changed) {
    if (!file || IGNORED.test(file) || NODE_TOOLS.test(file) || TOOL_ARTIFACTS.test(file)) continue;
    if (/\.(cpp|hpp|h|c)$/.test(file)) return { full: true, reason: `${file}: native-зависимости вне res:// графа` };
    if (!GRAPH_DIRS.test(file) && !GLOBAL.has(file)) return { full: true, reason: `${file} вне графа зависимостей` };
    if (GLOBAL.has(file)) return { full: true, reason: `${file} влияет на весь проект` };
    for (const source of dependents.get(file) || []) if (GLOBAL.has(source)) return { full: true, reason: `${file} подключён в ${source}` };
    queue.push(file);
  }
  while (queue.length) {
    const file = queue.pop();
    if (seen.has(file)) continue;
    seen.add(file);
    if (TEST_FILE.test(file)) tests.add(file);
    for (const source of dependents.get(file) || []) if (!GLOBAL.has(source)) queue.push(source);
  }
  for (const file of walk(root, 'tests/')) if (ALWAYS.test(file) && TEST_FILE.test(file)) tests.add(file);
  return { full: false, tests };
}

module.exports = { buildGraph, selectTests, changedFiles };
