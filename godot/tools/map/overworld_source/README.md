# Набор глобальной карты в геральдическом стиле

Картинки для новой карты Захара (этап C, #188/#189) в стиле бойцов и поселений игры: тёмно-синяя обводка, плоские
цвета, cel-шейдинг в 3 тона. Форматы и раскладка повторяют его файлы из `presentation/overworld/art`, чтобы их можно
было подставить вместо них. Генератор — OpenAI ImageGen (ChatGPT/Codex), промпты — ниже.

| Файл | Формат | Аналог у Захара | Содержимое |
|---|---|---|---|
| `landforms.png` | 1536×1024 RGBA, сетка 3×2 (512×512) | `landforms.png` | рыжие холмы, снежные горы, скалы с ельником, полоса леса, роща (кипарисы и дуб), поля |
| `massifs.png` | 1536×1024 RGBA, сетка 2×2 (768×512) | `massifs.png` | снежная гряда, рыжая гряда, два травяных склона; концы гряд сходят на нет, их можно ставить встык |
| `textures/meadow.png` | 1254×1254 RGB, бесшовная | `meadow.png` | луг |
| `textures/foothills.png` | 1254×1254 RGB, бесшовная | `foothill_ground.png` | предгорья, уступы, камни |
| `textures/steppe.png` | 1254×1254 RGB, бесшовная | — | степь |
| `textures/snow.png` | 1254×1254 RGB, бесшовная | — | снег |
| `textures/sand_coast.png` | 1254×1254 RGB, бесшовная | — | песчаный берег |
| `textures/sea.png` | 1254×1254 RGB, бесшовная | — | море |
| `textures/swamp.png` | 1254×1254 RGB, бесшовная | — | болото |

Поселения (города, замки, деревни семи культур, логово) — `godot/apps/godot/visuals/assets/settlements_heraldic.png`
с геометрией `settlements_heraldic_geometry.gd` (кадр 220×220, якорь на земле (110, 180), шест флага владельца).

Цвета, с которыми сверялись (из `overworld-reference-study.md`): трава `#8A8A3A`, лес `#424B21`, камень `#837270` /
`#E5C5AA`, вода `#1D505A`.

## Промпты

- `landforms.png` — вложения: `landforms.png` Захара (раскладка), `towns.png` поселений (стиль). «STRICT 3x2 grid …
  redraw everything in the style of attached towns.png: HERALDIC GRAPHIC style, deep navy outlines …», шесть клеток
  по списку выше.
- `massifs.png` — вложения: `massifs.png` Захара, наш `landforms.png`. «The left and right ends of every item fade
  out low and thin, so that several of them can be laid end to end into one long mountain range».
- Текстуры — по одной на генерацию, вложения: `meadow.png` Захара (формат), наш `landforms.png` (стиль). «Seamless
  tileable ground texture … repeats without visible seams on all four edges … flat planes of colour, 3-tone cel
  shading, a FEW economical broad shapes … NO fine hatching, NO noise … calm and quiet under the town and army
  icons. Surface: …». Codex сам сверяет противоположные края и проверяет повтор 2×2.
