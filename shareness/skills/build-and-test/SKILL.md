---
name: build-and-test
description: Собрать игру в index.html, прогнать смоук-тесты и снять скриншоты экранов. Применять перед любым пушем.
---
1. Собрать: `node build.mjs` (склеивает `src/*.js`, `style.css`, `shell.html` в `index.html`).
2. Тесты: `npm test` (Playwright, нужен Chrome; на ИИ-машине: `NODE_PATH=<путь к playwright> CHROME_PATH=/usr/bin/google-chrome node tests/smoke.cjs`). Успех — строка «Всё прошло».
3. Посмотреть глазами: открыть `index.html` в браузере, пройти новую игру → карта → город → быстрый бой. Для скриншотов используй Playwright с `viewport 1366×768`.
4. Красный тест не обходить, а чинить причину.
