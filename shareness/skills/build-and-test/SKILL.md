---
name: build-and-test
description: Проверить, протестировать, собрать и замерить Godot-версию перед пушем или после правки.
---
Команды выполняются из корня репозитория. `<Godot>` — путь к `Godot_v4.7.2-stable_win64_console.exe`.

1. Архитектура: `node godot/tools/architecture.test.cjs` и `node godot/tools/architecture.cjs`. Новые исключения запрещены.
2. Каталоги: пять экспортёров с `--check` (`tools/troops/export_troops.cjs`, `tools/equipment/export_gear.cjs`, `tools/characters/export_perks.cjs`, `tools/characters/export_companions.cjs`, `tools/campaign/export_goods.cjs`).
3. Тесты: `node godot/tools/test.cjs <Godot>`. Для своей правки — `--changed=HEAD` (staged, unstaged, untracked), для ветки — `--changed=main`. `--jobs=N` задаёт потоки, по умолчанию до 4. Runner изолирует `user://`: тесты не трогают сохранения игрока. Отчёт — `godot/.godot/test-last-run.json`.
4. Сборка и smoke: `node godot/tools/release.cjs <Godot>`, игра — `dist/godot/migration-release/IronStandard.exe`.
5. Перед первым запуском в чистой Windows-копии: `pwsh -File godot/tools/native_bootstrap.ps1`. Runner сам собирает native DLL; бинарники и `dist/` в Git не добавляй. После правки native-кода обязательны `test_native_contacts` и release-smoke.
6. После правки runner или выбора тестов: `node godot/tools/test_selection.test.cjs` и `node godot/tools/test_schedule.test.cjs`.
7. Красный тест не обходи и не отключай: чини причину.

## CI
- В PR Godot-тесты выбираются по графу ссылок `res://` от изменённых файлов; правка `project.godot`, автозагрузок или native-кода запускает полный набор. Полный набор идёт ночью и по кнопке.
- Бюджет полного набора — 3 минуты на тесты. Новый тест не должен зависеть от порядка запуска и писать вне `user://`.

## Замеры производительности
- Сначала функциональные и differential-тесты, затем release-smoke, затем отдельный benchmark без параллельных сборок и проверок.
- Benchmark сверяет SHA exe, DLL и исходников; backend сравнивай `--contacts=gdscript` / `--contacts=native` на одной release-сборке.
- В отчёте сохраняй методику, параметры, фактическую численность, SHA и все повторы. Старые отчёты не переписываются, смена методики фиксируется явно.
- Не объявляй FPS по CPU/headless-прогону и не подменяй 60 секунд × пять повторов коротким замером. Affinity — только как помеченная диагностика. Пороги и матрица — в `godot/docs/architecture/MIGRATION.md`, методика — `godot/docs/benchmarks/README.md`.
- После смены алгоритма запускай frozen reference tests: сохраняй их исходный режим и проверяй новое поведение отдельным сценарием.
