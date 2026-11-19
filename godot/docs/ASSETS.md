# Ассеты Godot-версии

Журнал источников: что лежит в проекте как файл, откуда оно, на каких условиях можно использовать. Для каждого внешнего материала до коммита записывать источник, лицензию, условия указания автора и право на коммерческий релиз. По правилам проекта внешние ассеты только бесплатные; по умолчанию графику и звук делаем сами.

| Файл | Что это | Источник | Лицензия | Автор указывать | Коммерческий релиз |
| --- | --- | --- | --- | --- | --- |
| `apps/godot/presentation/battle/audio/assets/battle_theme.ogg` | Зацикленная музыка боя, 53 с | Собственная работа, рендерится `tools/battle/render_battle_theme.py` | CC0 | не нужно | да |
| `apps/godot/presentation/battle/terrain/wall/assets/wall_*.png` | Текстуры осадной стены: камень, зубцы, башня, створка ворот | Собственная работа, рендерится `tools/battle/render_wall_textures.py` | CC0 | не нужно | да |
| `apps/godot/presentation/campaign/assets/loading_art.png` | Арт экрана загрузки кампании (новая игра и загрузка сейва) | Предоставлен владельцем проекта (Глеб), 2026-11 | Права у команды проекта | не нужно | да |

## Как добавлять

Расчленение (#42): нога рисуется SVG-кодом в `presentation/battle/unit_art.gd`,
половины торса получаются из собственных атласов бойцов. Внешних материалов нет;
сохраняются права исходных авторов графики проекта. Готовые текстуры кэшируются в памяти.

### Геральдическая пехота Мядельского доминиона

`apps/godot/visuals/assets/dominion_heraldic_0.png` … `dominion_heraldic_3.png`
содержат семь пеших типов (`d1`, `d2`, `d3`, `d2s`, `d3s`, `d2x`, `d3x`),
четыре варианта оттенка лица и восемь слоёв/состояний каждого типа.
Иллюстрации созданы встроенным ImageGen по согласованному геральдическому
концепту проекта. Сторонние изображения не использованы; отдельная CC0-лицензия
на результат не назначается. Исходные листы и точные промпты находятся в
`tools/battle/heraldic_source/` (скрыты от импорта через `.gdignore`).
С ноября 2026 туловище, голова и щит каждого бойца нарисованы отдельными частями
(`heraldic_source/torsos.png`, `heads.png`, `shields.png`) генератором картинок OpenAI
(ChatGPT) правкой `body.png` по промптам из `heraldic_source/parts-prompts.md`; по условиям
OpenAI права на результат принадлежат пользователю, коммерческое использование разрешено.
Сборка накладывает части «кукольным» суставом: шея уходит в вырез воротника, щит —
отдельным слоем для блока; у тела без головы вырез залит кровью, у головы — низ шеи.
`body.png` остаётся эталоном стиля и масштаба.

Сборка: `node godot/tools/battle/render_dominion_heraldic.cjs` (инструмент sharp
0.35.5, только для подготовки ассетов; при необходимости задать NODE_PATH).
Скрипт кадрирует, ориентирует и укладывает готовые рисунки, не вызывает модель.
Генератор ставит голову шеей в общую точку (76, 78) в вырез воротника. Центры записываются в `dominion_heraldic_heads.gd`.
Штатная игра использует готовые PNG и прежний пакетный рендер. Отдельные кисти-варежки без манжет, предплечий и раздельных пальцев из heraldic_source/gloves.png укладываются в слой оружия вокруг точки хвата; сталь используется у кольчужной пехоты и тяжёлого стрелка, кожа — у лёгкой пехоты и арбалетчика; дополнительных объектов на бойца не создаётся. Во втором проходе уменьшены оружие, увеличены щиты и смягчены пропорции торса. При найме этих
войск сохраняется новый силуэт и применяется выбранное игроком знамя; герой,
спутники, конница и другие фракции используют прежние ассеты. Оружие и баланс
не менялись. `heraldic_xbow` — исключительно ключ визуальной отдачи.

Визуальная проверка: `--script res://tools/battle/dominion_preview.gd`;
`-- --capture --out=<папка>` сохраняет 90 кадров настоящего UnitView. Для полного
листа задать `--resolution 1600x900`.

Ассеты переноса исходной графики:

| Файлы | Источник | Условия |
| --- | --- | --- |
| `apps/godot/visuals/assets/*.png`, `icon_*.svg`, `item_*.svg`, `white_*.svg` | Canvas и окончательный CSS удалённой JS-версии; выгружены один раз и теперь правятся как файлы | Производные собственной графики репозитория; права исходных авторов сохраняются, новая лицензия не назначается |
| `apps/godot/presentation/battle/terrain/assets/ground_*.png` | `paintGround` удалённой JS-версии, seed 4017, 2600×1700 | Те же условия исходного проекта; внешний материал не используется |
| `apps/godot/visuals/assets/fonts/AlegreyaSC-Bold.ttf` | [Google Fonts / Alegreya SC](https://github.com/google/fonts/tree/main/ofl/alegreyasc) | SIL OFL 1.1, коммерческое использование разрешено; полная лицензия `AlegreyaSC-OFL.txt` включена |
| `apps/godot/visuals/assets/fonts/AlegreyaSans-Medium.ttf`, `AlegreyaSans-Bold.ttf` | [Google Fonts / Alegreya Sans](https://github.com/google/fonts/tree/main/ofl/alegreyasans) | SIL OFL 1.1, коммерческое использование разрешено; полная лицензия `AlegreyaSans-OFL.txt` включена |

- Звук кладём в `apps/godot/presentation/<режим>/audio/assets/`, картинки и сцены — рядом с кодом владельца (`terrain/wall/`). Общего каталога ассетов нет, пока второй потребитель не появился.
- Файл `*.import` коммитим вместе с ассетом, кэш `.godot/` — нет. `node godot/tools/test.cjs` перед тестами сам запускает импорт.
- Если ассет сделан скриптом, скрипт лежит в `tools/battle/`, а результат всё равно можно править руками.
- Скриншоты и эталоны для сравнения (`tools/baseline/`) скрыты от импорта файлом `.gdignore`.

`banner_*` — разреженные замены пикселей из шести BANNERS оригинала (выгружены из JS-версии, ныне удалённой); `input.png`, `modal_header.png`, `modal_footer.png` — снимки исходного CSS. Это производные собственной графики проекта с теми же правами.

Праздничный модуль: apps/godot/presentation/birthday/happy_birthday.wav — собственная синтезированная запись мелодии Happy Birthday to You, без сторонней фонограммы; генератор tools/birthday/render_music.cjs. Праздничный рисунок и конфетти создаются кодом поверх существующего облика Викентия. Условия исходного репозитория сохраняются.

### Конница Доминиона (d2c Дружинник, d3c Боярин)

`apps/godot/visuals/assets/dominion_heraldic_cavalry_0.png` … `_3.png` (2 бойца × 11 состояний,
кадр 240×244, якорь (112, 264) как у прежних конных) и `dominion_heraldic_horses.png` (7 мастей коня
без всадника). Части нарисованы генератором картинок OpenAI (ChatGPT) по промптам из
`tools/battle/heraldic_source/horses-prompts.md`: `horses.png` (длинные низкие кони без ног),
`riders-torsos.png`, `riders-heads.png`, `riders-shields.png` (с нуля по пехотным листам), `lance.png`.
Сборка: `node godot/tools/battle/render_dominion_cavalry.cjs` (sharp); голова лежит поверх торса и
заходит на кольчужный воротник на 3 px ниже переднего края выреза. Геометрия —
`apps/godot/visuals/dominion_heraldic_cavalry_geometry.gd`. 11-я строка — всадник без коня
(разрубленный падает отдельно, конь — из `dominion_heraldic_horses.png`).

### Нордмарк (n1 Бонд, n2 Секироносец, n3 Хускарл, n2s Копьеносец, n2a Охотник, n3a Следопыт, n3c Дружинник)

`apps/godot/visuals/assets/nord_heraldic_0.png` … `_3.png` (6 пеших × 10 состояний, 152×176) и
`nord_heraldic_cavalry_0.png` … `_3.png` (конный, 11 состояний, 240×244). Части нарисованы генератором
картинок OpenAI (ChatGPT) с нуля по листам Доминиона по промптам `tools/battle/heraldic_source/nord-prompts.md`
(шаблоны — `shareness/skills/unit-parts/PROMPTS.md`): `nord-torsos.png`, `nord-heads.png`, `nord-shields.png`,
`bow.png`; кони — общий `horses.png`, меч/топор/копьё — `weapons.png`. Сборка:
`node godot/tools/battle/render_heraldic_faction.cjs nord` (sharp), геометрия — `nord_heraldic_geometry.gd`.
Под знаменем игрока синее сукно перекрашивается в цвет знамени (`dominion_heraldic_art.gd`, `FACTIONS`).
Эталоны теста палитр знамени перенесены на f3 (`tests/unit/visuals/fixtures/banner_*_f3.png`): вырезаны из
`portrait.png` с наложением `banner_N_portrait_v0.png`, как это делает игра.

### Аурелийская империя (e1 Рекрут, e2 Легионер, e3 Триарий, e2s Пикинёр, e3s Алебардист, e2a Арбалетчик, e3a Стрелок-ветеран, e3c Катафракт)

`apps/godot/visuals/assets/emp_heraldic_0.png` … `_3.png` (7 пеших) и `emp_heraldic_cavalry_0.png` … `_3.png`
(Катафракт, 12 строк: десять обычных, всадник без коня и конь без всадника). Части — генератор картинок OpenAI
(ChatGPT) по `tools/battle/heraldic_source/emp-prompts.md`: `emp-torsos.png`, `emp-heads.png`, `emp-shields.png`,
`emp-horse.png` (свой бардированный конь: багряная попона с золотыми солнцами). Оружие — общее (`weapons.png`, `lance.png`).
Сборка: `node godot/tools/battle/render_heraldic_faction.cjs emp`, геометрия — `emp_heraldic_geometry.gd`.
Под знаменем игрока багряное сукно перекрашивается в цвет знамени; срез шеи не трогается (кровь того же оттенка).
Эталоны теста палитр знамени теперь на f3 (`tests/unit/visuals/fixtures/banner_*_f3.png`).

### Кеширское ханство (k1 Кочевник, k2 Степной копейщик, k2a Степной стрелок, k2c Всадник, k3h Конный лучник, k3c Нукер)

`apps/godot/visuals/assets/khan_heraldic_0.png` … `_3.png` (3 пеших) и `khan_heraldic_cavalry_0.png` … `_3.png`
(3 конных, 12 строк). Части — генератор картинок OpenAI (ChatGPT) по шаблонам `shareness/skills/unit-parts/PROMPTS.md`:
`khan-torsos.png`, `khan-heads.png`, `khan-shields.png` (малые круглые), `sabre.png`. Кони — общий `horses.png`.
Сборка: `node godot/tools/battle/render_heraldic_faction.cjs khan`, геометрия — `khan_heraldic_geometry.gd`.
Под знаменем игрока бирюзовое сукно перекрашивается в цвет знамени.

### Нежить (z1 Мертвец, s1 Скелет, s1a Скелет-лучник, s2 Мёртвый воин, s2c Мёртвый всадник, s3 Умертвие)

`apps/godot/visuals/assets/undead_heraldic_0.png` … `_3.png` (5 пеших) и `undead_heraldic_cavalry_0.png` … `_3.png`
(всадник на костяном коне из общего `horses.png`). Части — генератор картинок OpenAI (ChatGPT) по шаблонам
`shareness/skills/unit-parts/PROMPTS.md`: `undead-torsos.png`, `undead-heads.png` (у Скелета шея в тряпке, чтобы
не просвечивал вырез), `undead-shields.png`, `club.png`. Сборка: `node godot/tools/battle/render_heraldic_faction.cjs undead`.

### Главный герой и спутники (#232)

`apps/godot/visuals/assets/hero_heraldic_parts.png` (торсы 11 доспехов, 15 голов в шлемах, волосы, бороды, щиты,
оружие с перчаткой) и `hero_heraldic_mounted.png` (копьё и лэнс в седле). Части — генератор картинок OpenAI (ChatGPT)
по `godot/tools/battle/heraldic_source/hero-prompts.md`: `hero-torsos-a.png`, `hero-mail.png`, `hero-torsos-b.png`,
`hero-heads-a.png`, `hero-heads-b.png`, `hero-hair.png`, `hero-shields.png`. Нарисованы ключевыми цветами, игра
перекрашивает их под стяг, кожу и волосы (`hero_heraldic_art.gd`). Сборка: `node godot/tools/battle/render_heraldic_hero.cjs`.

