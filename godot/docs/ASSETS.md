# Ассеты Godot-версии

Журнал источников: что лежит в проекте как файл, откуда оно, на каких условиях можно использовать. Для каждого внешнего материала до коммита записывать источник, лицензию, условия указания автора и право на коммерческий релиз. По правилам проекта внешние ассеты только бесплатные; по умолчанию графику и звук делаем сами.

| Файл | Что это | Источник | Лицензия | Автор указывать | Коммерческий релиз |
| --- | --- | --- | --- | --- | --- |
| `apps/godot/presentation/battle/audio/assets/battle_theme.ogg` | Зацикленная музыка боя, 53 с | Собственная работа, рендерится `tools/battle/render_battle_theme.py` | CC0 | не нужно | да |
| `apps/godot/presentation/battle/terrain/wall/assets/wall_*.png` | Текстуры осадной стены: камень, зубцы, башня, створка ворот | Собственная работа, рендерится `tools/battle/render_wall_textures.py` | CC0 | не нужно | да |

## Как добавлять

Ассеты переноса исходной графики:

| Файлы | Источник | Условия |
| --- | --- | --- |
| `apps/godot/visuals/assets/*.png`, `icon_*.svg`, `item_*.svg`, `white_*.svg` | Canvas и окончательный CSS из `src/`; экспортёры в `tools/` | Производные собственной графики репозитория; права исходных авторов сохраняются, новая лицензия не назначается |
| `apps/godot/presentation/battle/terrain/assets/ground_*.png` | `src/02_art.js: paintGround`, seed 4017, 2600×1700 | Те же условия исходного проекта; внешний материал не используется |
| `apps/godot/visuals/assets/fonts/AlegreyaSC-Bold.ttf` | [Google Fonts / Alegreya SC](https://github.com/google/fonts/tree/main/ofl/alegreyasc) | SIL OFL 1.1, коммерческое использование разрешено; полная лицензия `AlegreyaSC-OFL.txt` включена |
| `apps/godot/visuals/assets/fonts/AlegreyaSans-Medium.ttf`, `AlegreyaSans-Bold.ttf` | [Google Fonts / Alegreya Sans](https://github.com/google/fonts/tree/main/ofl/alegreyasans) | SIL OFL 1.1, коммерческое использование разрешено; полная лицензия `AlegreyaSans-OFL.txt` включена |

- Звук кладём в `apps/godot/presentation/<режим>/audio/assets/`, картинки и сцены — рядом с кодом владельца (`terrain/wall/`). Общего каталога ассетов нет, пока второй потребитель не появился.
- Файл `*.import` коммитим вместе с ассетом, кэш `.godot/` — нет. `node godot/tools/test.cjs` перед тестами сам запускает импорт.
- Если ассет сделан скриптом, скрипт лежит в `tools/battle/`, а результат всё равно можно править руками.
- Скриншоты и эталоны для сравнения (`tools/baseline/`) скрыты от импорта файлом `.gdignore`.
