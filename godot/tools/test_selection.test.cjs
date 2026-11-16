// Проверка выбора тестов по графу ссылок на искусственном проекте.
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { selectTests, changedFiles } = require('./test_selection.cjs');
const { execFileSync } = require('child_process');

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
assert.deepStrictEqual(pick(['tools/anything.cjs']), ['tests/architecture/test_boundaries.gd'], 'Node scripts have their own checks');
assert.strictEqual(pick(['tools/native_build.cjs']), 'FULL', 'The native kernel changes every battle');
// Godot-скрипт в tools/, на который не ссылается ни один тест, запускает только проверку границ
assert.deepStrictEqual(pick(['tools/anything.gd']), ['tests/architecture/test_boundaries.gd'], 'Tool scripts go through the graph');
assert.strictEqual(pick(['tools/native_bootstrap.ps1']), 'FULL', 'Native toolchain changes every battle');
// превью и эталонные кадры в tools/ не трогают игру: полный набор из-за картинки не нужен
assert.deepStrictEqual(pick(['tools/previews/birthday.png', 'tools/baseline/main_0300.png', 'tools/baseline/README.md']), ['tests/architecture/test_boundaries.gd']);
assert.strictEqual(pick(['apps/godot/composition/theme.gd']), 'FULL');
assert.strictEqual(pick(['apps/godot/composition/game.tscn']), 'FULL');
assert.strictEqual(pick(['core/battle/api/native/movement_kernel.hpp']), 'FULL', 'Native headers have no res:// edge');
assert.strictEqual(pick(['apps/godot/presentation/battle/native/battle_sprites.cpp']), 'FULL', 'Native presentation must run the suite too');
const git = args => execFileSync('git', args, { cwd: root, stdio: 'pipe' });
git(['init']);
git(['add', '.']);
git(['-c', 'user.name=Test fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'fixture']);
put('core/equipment/rules/gear.gd', '# staged change');
git(['add', '.']);
put('core/battle/model/unit.gd', '# unstaged change');
put('tests/unit/test_new.gd', '# untracked test');
assert.deepStrictEqual(changedFiles(root, 'HEAD').sort(), ['core/battle/model/unit.gd', 'core/equipment/rules/gear.gd', 'tests/unit/test_new.gd']);
assert.strictEqual(changedFiles(root, 'nonexistent-base'), null, 'Bad base must request the full suite, not skip checks');
console.log('Test selection tests passed');
