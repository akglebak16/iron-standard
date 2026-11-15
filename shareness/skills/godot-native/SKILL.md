---
name: godot-native
description: Пересобрать нативное ядро боя Godot-версии (godot/native, GDExtension) и обновить библиотеки в godot/bin для Windows, Linux и macOS.
---

# Нативное ядро боя: сборка и обновление

Ядро (`godot/native/src`) — C++ на godot-cpp ветки 4.5. Проект Godot без библиотеки из `godot/bin/` не запустится.

## Локально (для тестов)
1. `git clone -b 4.5 https://github.com/godotengine/godot-cpp` (коммит — `GODOT_CPP_REF` в `.github/workflows/godot-native.yml`).
2. `cmake -S godot/native -B build -DGODOT_CPP_DIR=<путь к godot-cpp> -DCMAKE_BUILD_TYPE=Release`
3. `cmake --build build --config Release -j` — библиотека твоей ОС попадает в `godot/bin/`.
4. `node godot/tools/test.cjs <godot>` — обязательно проходит `battle/tests/rules/test_native_core.gd` (сверка с GDScript бит в бит).

## Правила
- Меняешь правило боя — меняй и GDScript-эталон (`battle/rules/*.gd`), и C++, потом тест сверки.
- Флаги `-ffp-contract=off -fno-fast-math` не убирать: без них ядро расходится с GDScript.
- Новые поля бойца, которые читает ядро, — свойства `BattleUnit` (`battle_unit.h/.cpp`), а не словари.

## Библиотеки в репозиторий
1. Запушь ветку: workflow «Godot native core» соберёт три платформы.
2. `gh run list --workflow godot-native.yml --branch <ветка>` → `gh run download <id> -D /tmp/native`.
3. Скопируй `libbattle_core.*` из всех артефактов в `godot/bin/` и закоммить в тот же PR.
