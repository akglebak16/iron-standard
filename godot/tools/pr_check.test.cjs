const assert = require('node:assert/strict');
const p = require('./pr_check.cjs');

// «Closes #N» — та же проверка, что была в pr-issue.yml.
for (const ok of ['Closes #255', 'closes #1', 'Fixes #12', 'Resolved: #3', 'resolves https://github.com/a/b/issues/7']) assert.ok(p.hasIssueLink(ok), ok);
for (const bad of ['', null, 'Closes #', 'см. #255', 'Refs #255', 'enclosesh #2']) assert.ok(!p.hasIssueLink(bad), String(bad));

// Выбор как в job `godot-changes`.
assert.equal(p.needsGodot(['README.md', 'shareness/lessons.md']), false);
assert.equal(p.needsGodot(['godot/docs/modules/ai/DESIGN.md']), false);
assert.equal(p.needsGodot(['godot/docs/benchmarks/x.json']), true, 'в docs не-.md файлы проверяются');
assert.equal(p.needsGodot(['godot/core/battle/config.gd']), true);
assert.equal(p.needsGodot(['.github/workflows/godot.yml']), true);
assert.equal(p.needsGodot(['.github/workflows/release.yml']), false);

assert.equal(p.parseRepo('https://github.com/akglebak16/iron-standard'), 'akglebak16/iron-standard');
assert.equal(p.parseRepo('git@github.com:akglebak16/iron-standard.git'), 'akglebak16/iron-standard');
assert.equal(p.parseRepo('http://127.0.0.1:1/git/akglebak16/iron-standard'), null);

const known = p.parseKnownRed(['godot/tests/unit/a.gd#295,tests/b.gd#12', 'tests/c.gd#4']);
assert.deepEqual(known, [{test: 'tests/unit/a.gd', issue: 295}, {test: 'tests/b.gd', issue: 12}, {test: 'tests/c.gd', issue: 4}]);
assert.throws(() => p.parseKnownRed(['tests/a.gd']));
assert.throws(() => p.parseKnownRed(['tests/a.gd#x']));

const split = p.splitFailures(['tests/unit/a.gd', 'tests/b.gd (timeout 90000 ms)', 'tests/d.gd'], known);
assert.deepEqual(split.allowed, [{test: 'tests/unit/a.gd', issue: 295}, {test: 'tests/b.gd', issue: 12}]);
assert.deepEqual(split.real, ['tests/d.gd']);

// Итог: зелёная только при прогнанном Godot и открытом PR с Closes.
const base = {head: 'a'.repeat(40), base: 'b'.repeat(40), date: '2026-11-24T15:00:00.000Z', godot: true, engine: 'Godot.exe',
  steps: [{name: 'x', ok: true, seconds: 1}], tests: {selected: 10, passed: 10}, failures: [], knownRed: [], issueLink: true};
assert.equal(p.verdict(base), 'success');
assert.equal(p.verdict({...base, engine: null, tests: null}), 'pending', 'без Godot — не зелёная');
assert.equal(p.verdict({...base, issueLink: null}), 'pending', 'PR не открыт');
assert.equal(p.verdict({...base, issueLink: false}), 'failure');
assert.equal(p.verdict({...base, steps: [{name: 'x', ok: false}]}), 'failure');
assert.equal(p.verdict({...base, engine: null, steps: [{name: 'x', ok: false}]}), 'failure', 'красный шаг важнее отсутствия Godot');
assert.equal(p.verdict({...base, godot: false, engine: null, tests: null}), 'success', 'правок в godot/ нет — Godot не нужен');

for (const r of [base, {...base, engine: null}, {...base, issueLink: false}, {...base, steps: [{name: 'Сборка', ok: false}]}])
  assert.ok(p.statusDescription(r).length <= 140);
assert.match(p.statusDescription({...base, steps: [{name: 'Сборка', ok: false}]}), /Сборка/);

const text = p.summary({...base, failures: ['tests/d.gd'], knownRed: [{test: 'tests/a.gd', issue: 295}]});
assert.ok(text.startsWith(p.MARKER), 'по метке скрипт находит и обновляет свой комментарий');
assert.match(text, /aaaaaaaaaa/);
assert.match(text, /tests\/d\.gd/);
assert.match(text, /#295/);
assert.match(p.summary({...base, engine: null, tests: null}), /не прогнаны/);
console.log('PR check helpers passed');
