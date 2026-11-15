# Godot: документация проекта

Единая точка входа для разработки Godot-версии. Пути к коду в документации
отсчитываются от `godot/`, команды выполняются из корня репозитория.

Перед изменениями прочитай:

1. [Blueprint](architecture/BLUEPRINT.md) — целевая архитектура и обязательные границы.
2. [План миграции](architecture/MIGRATION.md) — этапы, незакрытые требования и критерии приёмки.
3. [Правила разработки](architecture/DEVELOPMENT.md) — размещение кода, контент и проверки.
4. [Манифест модулей](architecture/modules.json), [требования](architecture/requirements.json)
   и соответствующие ADR в `architecture/` — исполняемый контракт и решения.

Изменение архитектурного контракта требует ADR и автоматической проверки.
Обычный зелёный architecture gate не означает завершение blueprint: полный
статус проверяется с `--acceptance`. Не возвращай старые планы и правила в корень Godot.

Кампания уже содержит карту Европы, торговлю, задания, войны, осады, кланы,
спутников, вассалов и сохранения. Их нельзя считать отсутствующими или удалять
при миграции. Подробности: [паритет механик](modules/PARITY_CHECKLIST.md),
[сводка боя](modules/battle/PARITY.md). Производительность 1000×1000 пока не принята.

## Запуск и управление

Проект открывается через `godot/project.godot`, обычный запуск показывает меню.
Собранная игра: `dist/godot/migration-release/IronStandard.exe`; её можно запустить
двойным кликом. `dist/` и импортированный кэш не коммитятся.

На карте WASD/перетаскивание двигают камеру, C возвращает её к отряду,
колёсико меняет масштаб, пробел ставит время на паузу, 1/2/3 меняют скорость.
В бою WASD двигает героя, камера следует за ним; Shift — бег, ЛКМ — удар,
ПКМ — блок, X — оружие, 1–4 — группы, Q/E/R/F — приказы,
P — пауза, T — скорость. M/N/G переключают эффекты звука, музыку и кровь.

## Проверки и сборка

```text
node godot/tools/architecture.test.cjs
node godot/tools/architecture.cjs
node godot/tools/test.cjs <Godot-console.exe>
node godot/tools/release.cjs <Godot-console.exe>
```

Runner изолирует сохранения и настройки от данных игрока. Release-smoke
проверяет также переход Campaign → Battle → Campaign и владельца камеры.
Каталоги проверяются пятью экспортёрами с `--check`: `tools/troops/export_troops.cjs`,
`tools/equipment/export_gear.cjs`, `tools/characters/export_perks.cjs`,
`tools/characters/export_companions.cjs`, `tools/campaign/export_goods.cjs`.

Методика измерений и ограничения отчётов: [benchmarks](benchmarks/README.md).
Вспомогательные библиотеки и сборка: [зависимости](DEPENDENCIES.md).
Источники и лицензии графики/звука: [ассеты](ASSETS.md).
