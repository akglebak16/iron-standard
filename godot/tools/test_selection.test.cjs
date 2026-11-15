// Проверка выбора тестов по графу ссылок на искусственном проекте.
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { selectTests } = require('./test_selection.cjs');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'selection-'));
const put = (file, text = '') => { fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true }); fs.writeFileSync(path.join(root, file), text); };
put('project.godot', 'GameTheme="*res://apps/godot/composition/theme.gd"\nrun/main_scene="res://apps/godot/composition/game.tscn"');
put('apps/godot/composition/theme.gd');
put('apps/godot/composition/game.tscn', 'path="res://core/battle/model/unit.gd"');
put('core/equipment/rules/gear.gd');
put('core/equipment/data/catalog.json');
put('core/battle/model/unit.gd', 'const G = preload("res://core/equipment/rules/gear.gd")');
put('core/troops/rules/troop.gd');
put('core/loader.gd', 'var dir = "res://core/equipment/data/"');
put('tests/architecture/test_boundaries.gd');
put('tests/unit/equipment/test_gear.gd', 'preload("res://core/equipment/rules/gear.gd")');
put('tests/unit/battle/test_unit.gd', 'preload("res://core/battle/model/unit.gd")');
put('tests/unit/troops/test_troop.gd', 'preload("res://core/troops/rules/troop.gd")');
put('tests/unit/loader/test_loader.gd', 'preload("res://core/loader.gd")');
const pick = changed => { const r = selectTests(root, changed); return r.full ? 'FULL' : [...r.tests].sort(); };

// правка идёт вверх по цепочке ссылок: gear <- unit <- тесты и gear <- свой тест; чужой модуль не задет
assert.deepStrictEqual(pick(['core/equipment/rules/gear.gd']), ['tests/architecture/test_boundaries.gd', 'tests/unit/battle/test_unit.gd', 'tests/unit/equipment/test_gear.gd']);
assert.deepStrictEqual(pick(['core/troops/rules/troop.gd']), ['tests/architecture/test_boundaries.gd', 'tests/unit/troops/test_troop.gd']);
// ссылка на каталог целиком считается ссылкой на файлы в нём
assert.ok(pick(['core/equipment/data/catalog.json']).includes('tests/unit/loader/test_loader.gd'));
// изменённый тест запускается сам, документация и .uid ничего не запускают
assert.ok(pick(['tests/unit/troops/test_troop.gd']).includes('tests/unit/troops/test_troop.gd'));
assert.deepStrictEqual(pick(['docs/README.md', 'core/troops/rules/troop.gd.uid']), ['tests/architecture/test_boundaries.gd']);
// общее и невидимое графу даёт полный набор, в том числе автозагрузки и main_scene
assert.strictEqual(pick(['project.godot']), 'FULL');
assert.strictEqual(pick(['tools/anything.cjs']), 'FULL');
assert.strictEqual(pick(['apps/godot/composition/theme.gd']), 'FULL');
assert.strictEqual(pick(['apps/godot/composition/game.tscn']), 'FULL');
console.log('Test selection tests passed');
