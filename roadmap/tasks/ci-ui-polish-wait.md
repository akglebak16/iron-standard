---
title: Починить гонку в tests/ui-polish.cjs (main краснеет на CI)
status: на проверке
owner: Глеб
area: процесс
priority: высокий
created: 2026-11-14
pr: 20
done:
outside: да
---
После слияния #19 `npm test` на main падает: `loadGame()` грузит мир через `setTimeout`, а тест сразу проверяет `MODE === 'world'`, на CI там ещё `loading`. Тест теперь ждёт режим (`waitForFunction`), проверка не ослаблена. Красный main блокировал выкладку сайта, в том числе доски роудмапа.
