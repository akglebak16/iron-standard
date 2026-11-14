# Железный Стяг на Godot

Проект переноса находится на начальном этапе. Перенесены расчёт урона и морали, три группы и приказы, каталог из 67 типов войск, создание армий, движение, выбор цели, ближние удары и полёт стрел. Управление героем, отображение боя и кампания ещё не перенесены.

Расположение кода и правила для разработчиков описаны в `ARCHITECTURE.md`. Всё, что относится к бою, лежит внутри `battle/`, включая данные, тесты и инструменты переноса.

Баланс боя хранится в `battle/config.gd`: размеры поля, построение, приказы, мораль, лимиты армий. Параметры каждого типа войск хранятся в `battle/data/troops.json`. Меняйте значения там, сохраняя поля и идентификаторы. Загрузчик каталога проверяет обязательные поля и допустимые параметры. Названия войск в JSON пока взяты из русской версии; при переносе интерфейса они получат ключи локализации.

`node godot/battle/tools/export_troops.cjs --check` сверяет каталог с исходным прототипом. Эта проверка полезна для контроля точности переноса и ожидаемо покажет разницу после намеренной правки баланса в Godot.

Версия движка: Godot 4.7.2. Откройте эту папку в редакторе Godot.

Проверка всех тестов Godot из корня репозитория: `powershell -File godot/tools/test.ps1 -EnginePath <путь-к-godot.exe>`. Скрипт считает ошибки компиляции провалом теста, даже если Godot вернул код 0.

Отдельные проверки:

```text
godot --headless --path godot --script res://battle/tests/test_damage.gd
godot --headless --path godot --script res://battle/tests/test_battle_state.gd
godot --headless --path godot --script res://battle/tests/test_groups.gd
godot --headless --path godot --script res://battle/tests/test_catalog_spawn.gd
godot --headless --path godot --script res://battle/tests/test_movement.gd
godot --headless --path godot --script res://battle/tests/test_combat.gd
```
