# Железный Стяг на Godot

Проект переноса находится на начальном этапе. Перенесены формула снижения урона бронёй, базовые правила получения урона, смерти, убийства и реакции морали ближайших бойцов, а также три группы бойцов, их построение и приказы. Игровой бой и кампания ещё не перенесены.

Версия движка: Godot 4.7.2. Откройте эту папку в редакторе Godot.

Проверки из корня репозитория:

```text
godot --headless --path godot --script res://tests/test_damage.gd
godot --headless --path godot --script res://tests/test_battle_state.gd
godot --headless --path godot --script res://tests/test_groups.gd
```
