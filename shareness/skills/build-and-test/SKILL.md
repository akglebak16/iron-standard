---
name: build-and-test
description: Проверить, протестировать, собрать и замерить Godot-версию перед пушем или после правки.
---
Команды выполняются из корня репозитория. `<Godot>` — путь к `Godot_v4.7.2-stable_win64_console.exe`. Закреплённый Godot с export templates лежит в `dist/godot/engine/4.7.2/` — его кладёт `pr_check.cjs` (или `powershell -File godot/tools/engine_bootstrap.ps1`).

1. Архитектура: `node godot/tools/architecture.test.cjs` и `node godot/tools/architecture.cjs`. Новые исключения запрещены.
2. Каталоги (`godot/content/gameplay/*.json`) — источник истины, их проверяют тесты каталогов (`test_catalog_validation.gd` и другие) в общем наборе.
3. Тесты: `node godot/tools/test.cjs <Godot>`. Для своей правки — `--changed=HEAD` (staged, unstaged, untracked), для ветки — `--changed=main`. `--jobs=N` задаёт потоки, по умолчанию до 4. Runner изолирует `user://`: тесты не трогают сохранения игрока. Отчёт — `godot/.godot/test-last-run.json`.
4. Сборка и smoke: `node godot/tools/release.cjs <Godot>`, игра — `dist/godot/migration-release/IronStandard.exe`.
5. Перед первым запуском в чистой Windows-копии: `pwsh -File godot/tools/native_bootstrap.ps1`. Runner сам собирает native DLL; бинарники и `dist/` в Git не добавляй. После правки native-кода обязательны `test_native_contacts` и release-smoke.
6. После правки runner или выбора тестов: `node godot/tools/test_selection.test.cjs` и `node godot/tools/test_schedule.test.cjs`.
7. Красный тест не обходи и не отключай: чини причину.
8. **Работа над PR закончена — проверка одной командой, ИИ запускает её сам:** `node godot/tools/pr_check.cjs` без аргументов: на Windows закреплённый Godot 4.7.2 с export templates скрипт один раз сам качает в `dist/godot/engine/` (`engine_bootstrap.ps1`, ~1 ГБ) и перед тестами гоняет `native_bootstrap.ps1`, как CI. Свой Godot — аргументом или `GODOT=`. Повторяет бывший CI (`godot-changes` → `godot-architecture` → `godot-tests-and-release`) против merge-base со свежим `origin/main` и проверку `Closes #N`, требует чистое дерево, пишет `godot/.godot/pr-check.json`, ставит на коммит головы PR статус `local/pr-check` и обновляет комментарий со сводкой. Флаги: `--no-post` — не отправлять на GitHub; `--post-only` — отправить последний прогон того же коммита (если PR открыли после прогона); `--known-red=tests/…/test_x.gd#N` — тест красный и на `main`, issue #N открыт. Без Godot (облако) шаги Godot пропускаются, статус — «ожидает», а не зелёный. На GitHub пишет через `gh`, если в нём есть вход, иначе через `GH_TOKEN`/`GITHUB_TOKEN` или вход, который хранит git (`git credential fill`, Git Credential Manager) — отдельно логиниться не нужно.

## CI
- С #255 CI на GitHub для PR не запускается (бюджет Actions): «Godot — архитектура и Windows» — только по кнопке, полный набор. Проверка PR — `pr_check.cjs`, сливаем только с зелёным `local/pr-check` на последнем коммите.
- Godot-тесты для PR выбираются по графу ссылок `res://` от изменённых файлов; правка `project.godot`, автозагрузок или native-кода запускает полный набор. Полный набор — `node godot/tools/test.cjs <Godot>` без `--changed` или CI по кнопке.
- Бюджет полного набора — 3 минуты на тесты. Новый тест не должен зависеть от порядка запуска и писать вне `user://`.

## Замеры производительности
- Сначала функциональные и differential-тесты, затем release-smoke, затем отдельный benchmark без параллельных сборок и проверок.
- Benchmark сверяет SHA exe, DLL и исходников; backend сравнивай `--contacts=gdscript` / `--contacts=native` на одной release-сборке.
- В отчёте сохраняй методику, параметры, фактическую численность, SHA и все повторы. Старые отчёты не переписываются, смена методики фиксируется явно.
- Не объявляй FPS по CPU/headless-прогону и не подменяй 60 секунд × пять повторов коротким замером. Affinity — только как помеченная диагностика. Пороги и матрица — в `godot/docs/architecture/MIGRATION.md`, методика — `godot/docs/benchmarks/README.md`.
- После смены алгоритма запускай frozen reference tests: сохраняй их исходный режим и проверяй новое поведение отдельным сценарием.
