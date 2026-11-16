---
name: build-and-test
description: Собрать и проверить Godot или браузерную игру, измерить производительность и проверить готовность перед пушем.
---
Для Godot-миграции действуют отдельные проверки: `node godot/tools/architecture.test.cjs`,
`node godot/tools/architecture.cjs`, пять экспортёров каталогов с `--check`,
`node godot/tools/test.cjs <Godot-console.exe>` и `node godot/tools/release.cjs <Godot-console.exe>`.
Runner изолирует `user://`; не запускай тесты сохранений на данных игрока.
Для локальной итерации используй `--changed=HEAD` (включает staged/unstaged/untracked),
для проверки ветки — `--changed=main`; native-изменения требуют полного набора.
`--jobs=N` задаёт параллелизм; по умолчанию до 4. Долгие тесты идут первыми,
кеш хранит только длительность, не результаты. Отчёт — godot/.godot/test-last-run.json.
После изменения runner/выбора запускай также test_selection.test.cjs и test_schedule.test.cjs.
Перед первым запуском в чистой Windows-копии: `pwsh -File godot/tools/native_bootstrap.ps1`.
Архивы проверяются по SHA256; compiler/Python/godot-cpp остаются в dist.
Runner сам собирает native DLL; не добавляй бинарники или dist в Git.
После изменения native-кода обязательны test_native_contacts и release-smoke.
Benchmark сверяет SHA exe, DLL и исходников; для сравнения backend используй
`--contacts=gdscript` / `--contacts=native` на одной release-сборке.
Для performance-правки сначала запусти функциональные/differential-тесты,
затем release-smoke и отдельный benchmark без параллельных сборок или проверок.
В отчёте сохраняй методику, параметры, фактическую численность, SHA и все повторы.
Sampling v2 прогревает снимки и исключает события прогрева. Старые отчёты
не переписываются; смена методики фиксируется явно. Affinity допустима только
как явно помеченная диагностика с восстановлением прежней маски процесса;
приёмка должна включать обычный Windows scheduler.
Не объявляй FPS по CPU/headless-прогону и не подменяй 60 секунд × пять повторов
коротким замером. Пороги и матрица — в godot/docs/architecture/MIGRATION.md.
После смены алгоритма запускай также frozen reference tests: сохраняй их
исходный режим и явно проверяй допустимое новое поведение отдельным сценарием.
Локальные браузерные проверки для этой работы оставлены GitHub по решению владельца.
Список ниже применяется к браузерной версии.

1. Собрать: `node build.mjs` (склеивает `src/*.js`, `style.css`, `shell.html` в `index.html`).
2. Тесты: `npm test` (Playwright, нужен Chrome; на ИИ-машине: `NODE_PATH=<путь к playwright> CHROME_PATH=/usr/bin/google-chrome node tests/smoke.cjs`). Успех — строка «Всё прошло».
3. Посмотреть глазами: открыть `index.html` в браузере, пройти новую игру → карта → город → быстрый бой. Для скриншотов используй Playwright с `viewport 1366×768`.
4. Красный тест не обходить, а чинить причину.
