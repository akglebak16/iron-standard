---
name: build-and-test
description: Собрать игру в index.html, прогнать смоук-тесты и снять скриншоты экранов. Применять перед любым пушем.
---
Для Godot-миграции действуют отдельные проверки: `node godot/tools/architecture.test.cjs`,
`node godot/tools/architecture.cjs`, пять экспортёров каталогов с `--check`,
`node godot/tools/test.cjs <Godot-console.exe>` и `node godot/tools/release.cjs <Godot-console.exe>`.
Runner изолирует `user://`; не запускай тесты сохранений на данных игрока.
Перед первым запуском в чистой Windows-копии: `pwsh -File godot/tools/native_bootstrap.ps1`.
Архивы проверяются по SHA256; compiler/Python/godot-cpp остаются в dist.
Runner сам собирает native DLL; не добавляй бинарники или dist в Git.
После изменения native-кода обязательны test_native_contacts и release-smoke.
Benchmark сверяет SHA exe, DLL и исходников; для сравнения backend используй
`--contacts=gdscript` / `--contacts=native` на одной release-сборке.
Локальные браузерные проверки для этой работы оставлены GitHub по решению владельца.
Список ниже применяется к браузерной версии.

1. Собрать: `node build.mjs` (склеивает `src/*.js`, `style.css`, `shell.html` в `index.html`).
2. Тесты: `npm test` (Playwright, нужен Chrome; на ИИ-машине: `NODE_PATH=<путь к playwright> CHROME_PATH=/usr/bin/google-chrome node tests/smoke.cjs`). Успех — строка «Всё прошло».
3. Посмотреть глазами: открыть `index.html` в браузере, пройти новую игру → карта → город → быстрый бой. Для скриншотов используй Playwright с `viewport 1366×768`.
4. Красный тест не обходить, а чинить причину.
