# Измерения миграции

`initial-contact-release.json` — первая проверка настоящих 1000×1000:
120 измеренных тиков после 10 прогревочных, seed 4242, плотная расстановка,
Windows release, i5-14400F. Это **короткий диагностический baseline**, а не
полная матрица приёмки и не измерение FPS. Dirty=true отмечает изменения
до первого коммита миграции. В отчёте сохранены живые бойцы и реальные события.

Сборка: `node godot/tools/release.cjs <godot-console.exe>`.
Замер: `node godot/tools/benchmark.cjs dist/godot/migration-release/IronStandard.exe --n=1000 --scenario=contact --ticks=3600 --repeat=5`.
Другие сценарии: approach, volley, cavalry, siege. Сохранённые отчёты нельзя
обновлять автоматически при падении performance-проверки.

Обязательная итоговая приёмка, бюджеты и отсутствующие измерения перечислены
в `../architecture/MIGRATION.md`; короткий baseline не закрывает этап 0 целиком.
