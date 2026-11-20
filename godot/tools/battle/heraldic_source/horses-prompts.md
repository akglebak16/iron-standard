# Доминион: кони и всадники (промпты)

Что нужно: 7 мастей коня в новом heraldic-стиле, два конных бойца (Дружинник d2c и
Боярин d3c) и лэнс для Боярина. Кони длинные и низкие, без ног, срезаны по брюху.
Подставку и тени рисует код. Все промпты ниже — проверенные, с ними получились
финальные листы.

## Как генерировать

- Генератор тот же, что для пехоты (встроенный в ChatGPT/Кодекс). Ничего платного
  и ничего про отрубленное или кровь в промптах.
- На выходе PNG 1254×1254, **прозрачный фон**, сетка 3×3. Размер скрипт приведёт
  сам, руками ничего не режь.
- Плохой лист перегенерируй целиком, отдельные места не латай.
- Готовые файлы клади в `godot/tools/battle/heraldic_source/` под именами из
  заголовков и напиши ИИ: «кони Доминиона готовы». Сборку, код и тесты он сделает сам.

Порядок: лист 1 (кони), затем три листа частей всадников (раздел 2) и лэнс (раздел 3).

## Общий блок стиля

Вставляется в начало каждого промпта.

```
Production sprite sheet for an existing medieval strategy game. Attached body.png is the STYLE REFERENCE: match exactly its HERALDIC GRAPHIC style, deep navy outlines, bold flat planes, 3-tone cel shading, economical broad shapes, no realistic texture, not photorealistic, not glossy 3D. Faction colours of Myadel Dominion: dull ochre gold #AD883A and charcoal #343329, subdued steel, cream, dark brown leather. Square canvas with a STRICT 3x3 grid of equal cells, one isolated sprite centered in each used cell with generous transparent gaps. Fully transparent background. No text, numbers, cell borders, ground, oval bases or shadows. This is actual game production material.
```

## 1. `horses.png` — семь мастей (длинные и низкие)

Приложить: прежний `horses.png` (образец мастей и стиля) и `body.png`. Первая версия коней
«бюстом» (голова, шея и грудь столбиком) сливалась со всадником и заменена этой; она лежит
в `horses-tall.png`, а самая первая раскладка — в `horses-layout.png`.

```
Production sprite sheet for an existing medieval strategy game. Attached horses.png is the STYLE REFERENCE for the horses (same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same seven coats in the same cells, same bridle drawing). Attached body.png shows the riders' scale: the horses will carry busts of that size. Fully transparent background. No text, numbers, cell borders, ground, oval bases or shadows. Not photorealistic, not glossy 3D.

Square canvas, STRICT 3x3 grid of equal cells, one horse centered in each cell with generous transparent gaps, same cell order and coats as horses.png: top left BAY, top center CHESTNUT, top right DUN, middle left BLACK, middle center GREY, middle right BARDED (ochre #AD883A caparison with charcoal diamonds, steel chamfron, covering the body), bottom left BONE (gaunt pale undead horse, ribs showing). Bottom center and bottom right cells EMPTY.

NEW PROPORTIONS, critical: each horse is seen from the SIDE in a slight three-quarter view, facing RIGHT, and is LONG AND LOW: the visible body is about 1.7 times wider than it is tall. Show the WHOLE horse body from the rump with a short tail on the left, along the level back with the saddle in the MIDDLE, to the chest, an arched neck and the head on the right. The neck and head reach clearly forward and up, well in front of where the rider will sit, the head ends near the right edge of the cell. The body is cut off straight and flat at belly level: NO LEGS, no hooves. The saddle is an empty dark brown leather saddle with a plain DARK BROWN leather saddle cloth (not ochre, not charcoal), small brass fittings, no rider, no stirrups hanging, no weapons. All seven horses share exactly the same silhouette and pose, only the coat differs.
```

## 2. Всадники — сразу частями

Первый вариант (целиком `riders-body.png`, потом правками на части) дал голую шею,
стоячий воротник и бармицу, обрезанную у скул. Поэтому части генерируются с нуля, каждая
по образцу пехотного листа того же типа. Масштаб к пехоте подгоняет сборщик
(`render_heraldic_faction.cjs dominion`), плюмаж в высоту головы не считается.

### `riders-torsos.png` — приложить `torsos.png`, затем `body.png`

```
Production sprite sheet for an existing medieval strategy game. Attached torsos.png is the EXACT FORMAT AND STYLE REFERENCE: seven infantry TORSO LAYERS of the same game. Draw two new torso layers that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same size, same proportions, same front view, same shoulder width and belt height, same economical broad cloth folds. body.png shows the same figures with heads, for scale only. Myadel Dominion colours: dull ochre gold #AD883A, charcoal #343329, subdued grey steel, dark brown leather, brass buckle.

Square canvas, STRICT 3x3 grid of equal cells. Top left and top center cells hold one torso each, centered, with generous transparent gaps; all other cells are EMPTY. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No head, no neck, no arms, no hands, no legs, no shield, no weapon. Not photorealistic, not glossy 3D.

Each torso goes from the waist belt up to the shoulders. Rounded shoulders with short mail-covered upper-arm stubs exactly like the infantry torsos, no arms below them. The belt runs straight across the whole waist with ONE brass buckle in the middle.
NECK OPENING, critical: exactly like in torsos.png. The mail shoulder collar lies FLAT on the shoulders and ends at shoulder level in a low, wide, slightly oval opening seen from the front: a thin mail rim with a navy outline and a DARK, almost black hollow inside. NO stand-up collar, NO cloth ring, NO tube rising above the shoulders, nothing that could read as a neck.
top left d2c druzhinnik (mounted retainer): flat grey mail shoulder collar, grey mail hauberk with mail upper-arm stubs, ochre surcoat over it with one broad charcoal vertical band down the middle.
top center d3c boyar (heavy noble cavalry): flat grey mail shoulder collar, mail upper-arm stubs, rich ochre tabard with a short ochre shoulder cape edged by a thin gold trim, broad charcoal vertical stripe down the middle ending in a point.
```

### `riders-heads.png` — приложить `heads.png`, затем `body.png`

```
Production sprite sheet for an existing medieval strategy game. Attached heads.png is the EXACT FORMAT AND STYLE REFERENCE: seven infantry HEAD LAYERS of the same game. Draw two new head layers that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same head size, same three-quarter view turned to the VIEWER'S RIGHT, same face drawing (angular, lively but not angry, ordinary male face), same steel colours. body.png shows the same kind of figures assembled, for scale only.

Square canvas, STRICT 3x3 grid of equal cells. Top left and top center cells hold one head each, centered, with generous transparent gaps; all other cells are EMPTY. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No shoulders, no collar, no body, no shield. Not photorealistic, not glossy 3D.

Every head ends at the bottom in a SHORT NECK PART cut straight and slightly rounded a little below the chin, at the same height for both heads. NO BARE SKIN on the neck: the neck part is fully covered by mail.
top left d2c druzhinnik: steel nasal helmet with a riveted brow band, exactly like the infantry spearman in heads.png (middle left). A grey MAIL COIF hangs from the helmet rim, covers the ears, the sides of the head, the throat and the whole neck, falls straight down past the jaw and ends at the cut line. The coif must NOT stop at the cheeks and must NOT spread out like a cape. Short brown beard.
top center d3c boyar: CLOSED steel greathelm with a narrow eye slit and breathing holes, the same size and width as the infantry guard's greathelm in heads.png (top right), with a SMALL ochre #AD883A plume on top, no taller than half the helmet height. A short mail fringe under the helm hides the neck down to the cut line.
Both heads are no taller than about 1.3 times their helmet height, not counting the plume.
```

### `riders-shields.png` — приложить `shields.png`

```
Production sprite sheet for an existing medieval strategy game. Attached shields.png is the EXACT FORMAT AND STYLE REFERENCE: the infantry SHIELD LAYERS of the same game. Draw two new shields that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same size, same slight tilt and front view. Myadel Dominion colours: dull ochre gold #AD883A, charcoal #343329, brass, subdued steel.

Square canvas, STRICT 3x3 grid of equal cells. Top left and top center cells hold one shield each, centered, with generous transparent gaps; all other cells are EMPTY. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No hands, no arms, no figure. Each shield drawn COMPLETE with nothing overlapping it. Not photorealistic, not glossy 3D.
top left d2c: round shield quartered ochre and charcoal, brass rim with rivets, brass boss in the center, same size as the infantry round shields.
top center d3c: kite shield, ochre field with ONE bold charcoal chevron and a small gold oak leaf below it, STEEL rim with brass rivets, same size as the infantry guard's kite shield.
```

Если генератор вернул шахматку вместо прозрачности (RGB без альфы), фон вычищается
заливкой от краёв по светлым серым пикселям: контур фигуры её останавливает.

## 3. `lance.png` — лэнс

Приложить: `weapons.png` (стиль оружия).

```
Production sprite asset, transparent background, same clean HERALDIC GRAPHIC art style as the attached weapons.png: navy outlines, broad cel-shaded steel, dark brown wood, restrained dull brass, no realistic texture.
ONE upright cavalry LANCE in the center of a square canvas: long straight wooden shaft painted in ochre #AD883A and charcoal #343329 spiral bands, narrow steel point at the top, a small round steel vamplate (hand guard) near the lower third, short butt below it. The lance is long and fills most of the canvas height. No hands, no pennant, no labels, no frames, no shadows. Keep detail economical so it reads at 15-40px.
```

