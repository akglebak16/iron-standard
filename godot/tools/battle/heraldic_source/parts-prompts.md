# Доминион: промпты для отдельных частей бойцов

Зачем. Сейчас голова и щит нарисованы прямо на бюсте (`body.png`), и генератор
`render_dominion_heraldic.cjs` достраивает то, что под ними спрятано: торс под щитом
отражает другую половину, под голову вырезает «чашу». Отсюда швы и рваные места.
Если нарисовать части отдельно, достраивать ничего не нужно.

## Как генерировать

- Каждый промпт ниже — это **правка** готового `body.png`, а не новая картинка.
  Прикладывай `body.png` (1254×1254, прозрачный фон) как входное изображение и проси
  отредактировать именно его. Так сохраняются сетка, места и масштаб фигур, и части
  совпадут с бюстами без ручной подгонки.
- Генератор тот же, которым делали `body.png` (встроенный генератор картинок,
  см. `generation.json`). Платные сервисы не берём, пока Глеб не решит иначе: в игру
  идут только ассеты с правом коммерческого использования, источник и лицензию
  записываем в `godot/docs/ASSETS.md`.
- На выходе нужен PNG 1254×1254 с **прозрачным** фоном. Если генератор вернул другой
  размер, ничего не обрезай и не сдвигай вручную: скрипт приведёт размер сам, главное,
  чтобы сетка 3×3 и места фигур остались прежними.
- Готовые файлы клади рядом с `body.png` под именами из заголовков
  (`torsos.png`, `heads.png`, `shields.png`) и напиши ИИ: «части Доминиона готовы».
  Сборку и проверку он сделает сам.
- Если в каком-то промпте результат плохой, перегенерируй только его.

## Общий блок стиля

Вставляется в начало каждого промпта.

```
Edit this EXACT production sprite sheet of seven Dominion infantry busts for an existing medieval strategy game. It is the style and layout reference: keep the same HERALDIC GRAPHIC style, deep navy outlines, bold flat planes, 3-tone cel shading, same faces, helmets, armour, ochre #AD883A and charcoal #343329 faction colours, same subdued steel and cream. Keep the same 3x3 grid on a square canvas: every figure stays in its own cell, at the SAME position and SAME scale as in the input, on the same baseline. Bottom center and bottom right cells stay empty. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No arms, hands, legs or weapons. Not photorealistic, not glossy 3D. This is actual game production material that will be layered exactly over the input sheet.
```

## 1. `torsos.png` — бюсты без головы и без щита

```
[общий блок стиля]

Change each of the seven busts into its TORSO LAYER:
1. Remove the head completely: helmet, face, hair, beard, mail coif and the neck. Keep the collar, shoulders, chainmail shoulder collar, scarf and cloak exactly as they are. Where the head was, the collar ends in a clean, slightly oval NECK OPENING seen from the front: a smooth even rim with a thin dark inner edge, nothing sticking up above it, no stump, no blood.
2. On the four shield-bearers (top left militia, top center shieldman, top right closed-helmet guard, middle left spearman) remove the shield completely and PAINT THE TORSO THAT WAS HIDDEN BEHIND IT in the same style: the gambeson quilting, tabard stripes, mail collar, scarf, the left shoulder and the left side of the body, continuing naturally from the visible part. The belt runs across the whole waist with ONE buckle in its usual place, do not add a second buckle. The body outline on the viewer's left mirrors the visible right side.
3. Halberdier, crossbowman and forest marksman have no shield: only remove their heads. Keep their quivers.
Every torso stays exactly where it was in its cell, same width, same belt height.
```

## 2. `heads.png` — головы отдельно

```
[общий блок стиля]

Keep ONLY THE HEADS of the seven figures and erase everything else (torsos, shoulders, collars, shoulder mail, scarves, cloaks, shields, quivers).
Each head keeps its exact position and size in its cell: helmet, face, hair, beard and the mail coif that hangs from the helmet. Below the chin, finish each head with a SHORT NECK that ends in a clean, straight, slightly rounded cut a little below the jaw, the same height for all seven. Where the coif or hair hung onto the shoulders, end it neatly at the same cut line with a smooth edge, no ragged pieces, no floating bits.
Do not mirror or turn the heads, keep the facing direction of the input.
```

## 3. `shields.png` — щиты отдельно

```
[общий блок стиля]

Keep ONLY THE FOUR SHIELDS and erase everything else, including all figures. Cells top left, top center, top right and middle left keep their shield; middle center, middle right and bottom left become empty.
Each shield keeps its exact position, size and tilt in its cell, but is drawn COMPLETE: the full rim, all rivets and the whole face, with nothing overlapping it (no hair, collar or body parts in front of it, no body visible behind it). Round shields stay round ochre/charcoal with a brass boss, the guard keeps the gold oak emblem on its kite shield. Clean navy outline all around.
```

## Что сделает сборка

`render_dominion_heraldic.cjs` возьмёт те же ячейки сетки, что у `body.png`
(рамка ячейки и масштаб считаются по `body.png`), и положит части на те же места:
торс без головы и щита, голову (зеркалится обратно и садится на общую точку шеи
76×78), щит отдельным слоем для анимации блока. Достройка торса и вырез «чашей»
тогда больше не нужны.
