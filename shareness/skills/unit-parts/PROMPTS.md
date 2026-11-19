# Проверенные промпты для частей бойцов

Эти промпты дали годные листы с первого-второго раза (Доминион, ноябрь 2026). Для новой фракции
копируй шаблон, меняй только блок «Faction» и список клеток. Генератор — OpenAI (ChatGPT/Кодекс).
Конкретные наборы: `godot/tools/battle/heraldic_source/horses-prompts.md` (конница Доминиона),
`nord-prompts.md` (Нордмарк).

## Как давать пользователю
- Промпт целиком текстом, готовым к копированию.
- Файлы-образцы — вложениями, и порядок вложений словами: «сначала `torsos.png`, потом `body.png`».
- Один лист — один промпт. Можно просить все части одной картинкой: сборщик их разрежет.

## Что работает в формулировках
- Первое вложение — **лист того же типа** («EXACT FORMAT AND STYLE REFERENCE … could sit in that
  sheet unnoticed»). Второе — `body.png`, «for scale only».
- Явно запрещать то, что ломалось, заглавными: `NO stand-up collar`, `NO BARE SKIN`, `NO LEGS`,
  `must NOT stop at the cheeks`, `EMPTY` для пустых клеток.
- Пропорции числами: «no taller than about 1.3 times the helmet height», «about 1.7 times wider
  than it is tall», «plume no taller than half the helmet height».
- Цвета hex-кодами и «NOT <цвета образца>», иначе генератор копирует палитру образца.
- Никаких слов про кровь, отрубание и смерть: модерация режет, это рисует код.

## Торсы (`<фракция>-torsos.png`) — вложения: `torsos.png`, `body.png`

```
Production sprite sheet for an existing medieval strategy game. Attached torsos.png is the EXACT FORMAT AND STYLE REFERENCE: seven TORSO LAYERS of the same game. Draw <N> new torso layers that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same size, same proportions, same front view, same shoulder width and belt height, same economical broad cloth folds. body.png shows figures of the same game with heads, for scale only.
Faction: <ИМЯ, 1 фраза о культуре>. Colours: <hex основной>, <hex отделки>, <материалы>. NOT <цвета образца>.

Square canvas, STRICT 3x3 grid of equal cells, one torso centered in each used cell with generous transparent gaps. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No head, no neck, no arms, no hands, no legs, no shield, no weapon. Not photorealistic, not glossy 3D.

Each torso goes from the waist belt up to the shoulders, rounded shoulders with short upper-arm stubs exactly like the reference torsos, no arms below them. The belt runs straight across the whole waist with ONE buckle in the middle.
NECK OPENING, critical: exactly like in torsos.png. The collar lies FLAT on the shoulders and ends at shoulder level in a low, wide, slightly oval opening seen from the front: a thin rim with a navy outline and a DARK, almost black hollow inside. NO stand-up collar, NO cloth ring or fur roll rising above the shoulders, nothing that could read as a neck.
Cells in reading order:
<клетка> <id> <боец>: <одежда; колчан — «behind the LEFT shoulder (viewer's left)»>.
...
<пустые клетки> EMPTY.
```

## Головы (`<фракция>-heads.png`) — вложения: `heads.png`, `body.png`

```
Production sprite sheet for an existing medieval strategy game. Attached heads.png is the EXACT FORMAT AND STYLE REFERENCE: seven HEAD LAYERS of the same game. Draw <N> new head layers that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same head size, same three-quarter view turned to the VIEWER'S RIGHT, same face drawing (angular, lively but not angry, ordinary male faces, all different). body.png shows assembled figures of the same game, for scale only.
Faction: <ИМЯ, волосы/бороды>. Steel is subdued grey, cloth <hex>.

Square canvas, STRICT 3x3 grid of equal cells, one head centered in each used cell with generous transparent gaps. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No shoulders, no collar, no body, no shield. Not photorealistic, not glossy 3D.

Every head ends at the bottom in a SHORT NECK PART cut straight and slightly rounded a little below the chin, at the same height for all. NO BARE SKIN on the neck part: it is covered by mail, a beard or a hood down to the cut line. A mail coif hangs from the helmet rim, covers the ears, the sides of the head, the throat and the whole neck, falls straight down past the jaw and ends at the cut line; it must NOT stop at the cheeks and must NOT spread out like a cape. All heads are no taller than about 1.3 times their helmet height, not counting a plume; a plume is SMALL, no taller than half the helmet height.
Cells in reading order:
<клетка> <id>: <шлем как у пехотинца X в heads.png; бармица/борода/капюшон>.
...
<пустые клетки> EMPTY.
```

## Щиты (`<фракция>-shields.png`) — вложение: `shields.png`

```
Production sprite sheet for an existing medieval strategy game. Attached shields.png is the EXACT FORMAT AND STYLE REFERENCE: the SHIELD LAYERS of the same game. Draw new shields that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same size, same slight tilt and front view.
Faction: <ИМЯ>. Colours: <hex>, <hex>, <металл обода>.

Square canvas, STRICT 3x3 grid of equal cells, one shield centered in each used cell with generous transparent gaps; unused cells EMPTY. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No hands, no arms, no figure. Each shield drawn COMPLETE with nothing overlapping it. Not photorealistic, not glossy 3D.
<клетка> <id>: <форма, поле, герб, обод, умбон>.
```

## Кони (`horses.png`) — вложения: текущий `horses.png` (стиль мастей), `body.png`

Кони общие для всех фракций (попона нейтральная). Перегенерировать только если нужна новая масть.

```
Production sprite sheet for an existing medieval strategy game. Attached horses.png is the STYLE REFERENCE for the horses (same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same seven coats in the same cells, same bridle drawing). Attached body.png shows the riders' scale: the horses will carry busts of that size. Fully transparent background. No text, numbers, cell borders, ground, oval bases or shadows. Not photorealistic, not glossy 3D.

Square canvas, STRICT 3x3 grid of equal cells, one horse centered in each cell with generous transparent gaps, same cell order and coats as horses.png: top left BAY, top center CHESTNUT, top right DUN, middle left BLACK, middle center GREY, middle right BARDED (ochre #AD883A caparison with charcoal diamonds, steel chamfron, covering the body), bottom left BONE (gaunt pale undead horse, ribs showing). Bottom center and bottom right cells EMPTY.

NEW PROPORTIONS, critical: each horse is seen from the SIDE in a slight three-quarter view, facing RIGHT, and is LONG AND LOW: the visible body is about 1.7 times wider than it is tall. Show the WHOLE horse body from the rump with a short tail on the left, along the level back with the saddle in the MIDDLE, to the chest, an arched neck and the head on the right. The neck and head reach clearly forward and up, well in front of where the rider will sit, the head ends near the right edge of the cell. The body is cut off straight and flat at belly level: NO LEGS, no hooves. The saddle is an empty dark brown leather saddle with a plain DARK BROWN leather saddle cloth (not ochre, not charcoal), small brass fittings, no rider, no stirrups hanging, no weapons. All seven horses share exactly the same silhouette and pose, only the coat differs.
```

## Оружие (одно на картинку) — вложение: `weapons.png`

```
Production sprite asset, transparent background, same clean HERALDIC GRAPHIC art style as the attached weapons.png: navy outlines, broad cel-shaded steel, dark brown wood, restrained dull brass, no realistic texture.
ONE upright <ОРУЖИЕ> in the center of a square canvas: <форма, древко/клинок, где хват, цвета фракции hex>. It fills most of the canvas height. No hands, no labels, no frames, no shadows. Keep detail economical so it reads at 15-40px.
```
Пример удачного: лэнс — «long straight wooden shaft painted in ochre #AD883A and charcoal #343329 spiral bands, narrow steel point at the top, a small round steel vamplate (hand guard) near the lower third, short butt below it».

## Что не сработало (не повторять)
- Правка цельного бюста (`riders-body.png` → торсы/головы правкой): стоячий воротник, голая шея,
  бармица обрезана у скул, щит другой формы, чем на бюсте.
- Конь «бюстом» без корпуса: высокий столбик за плечом всадника, сливается с ним.
- Большой плюмаж «small ochre plume» без ограничения высоты — генератор рисует перо на полшлема и выше.
- Все части фракции одной картинкой (торсы, головы, щиты, оружие в сетке 6×3): части выходят мельче, после
  сборки голова не закрывает вырез воротника — видна тёмная щель. Генерировать листы по отдельности.
