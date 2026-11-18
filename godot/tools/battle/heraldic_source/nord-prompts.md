# Нордмарк: промпты для частей бойцов

Семь бойцов в одной сетке 3×3 (порядок клеток везде одинаковый):

| клетка | id | боец | шлем | доспех | щит |
|---|---|---|---|---|---|
| верх слева | n1 | Бонд | нет (волосы) | туника | круглый |
| верх центр | n2 | Секироносец | наносник | мех | круглый |
| верх справа | n3 | Хускарл | очковый шлем | кольчуга с мехом | круглый |
| середина слева | n2s | Копьеносец | стёганая шапка | стёганка | круглый |
| середина центр | n2a | Охотник | капюшон | мех, колчан | нет |
| середина справа | n3a | Следопыт | наносник | мех, колчан | нет |
| низ слева | n3c | Дружинник (конный) | очковый шлем | кольчуга | круглый |

Цвета фракции: синий #2F5A85 и белёсо-серебристый #DFE6EA, мех, тёмная кожа, сталь.
Коней берём готовых (`horses.png`, попона у них нейтральная тёмная), копьё, меч и топор —
из `weapons.png`. Новое оружие одно: лук.

Части генерируются с нуля по листам Доминиона того же типа (правка цельного бюста давала
голую шею и стоячий воротник). Голова в сборке ложится поверх торса.

## 1. `nord-torsos.png` — приложить `torsos.png`, затем `body.png`

```
Production sprite sheet for an existing medieval strategy game. Attached torsos.png is the EXACT FORMAT AND STYLE REFERENCE: seven TORSO LAYERS of the same game. Draw seven new torso layers for another faction that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same size, same proportions, same front view, same shoulder width and belt height, same economical broad cloth folds. body.png shows figures of the same game with heads, for scale only.
Faction: NORDMARK, a northern kingdom of snow and fur. Colours: deep blue #2F5A85 and pale silvery white #DFE6EA, grey and brown fur, dark brown leather, subdued grey steel, brass or iron buckle. NOT ochre, NOT charcoal-and-gold like the reference.

Square canvas, STRICT 3x3 grid of equal cells, one torso centered in each used cell with generous transparent gaps. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No head, no neck, no arms, no hands, no legs, no shield, no weapon. Not photorealistic, not glossy 3D.

Each torso goes from the waist belt up to the shoulders, rounded shoulders with short upper-arm stubs exactly like the reference torsos, no arms below them. The belt runs straight across the whole waist with ONE buckle in the middle.
NECK OPENING, critical: exactly like in torsos.png. The collar lies FLAT on the shoulders and ends at shoulder level in a low, wide, slightly oval opening seen from the front: a thin rim with a navy outline and a DARK, almost black hollow inside. NO stand-up collar, NO cloth ring or fur roll rising above the shoulders, nothing that could read as a neck.
Cells in reading order:
top left n1 bondi (peasant levy): simple blue wool tunic with a pale white trim at the hem of the shoulders, plain leather belt.
top center n2 axeman: blue tunic over padding, a grey wolf-fur mantle lying flat over both shoulders.
top right n3 huscarl (elite): grey mail hauberk, a short dark-brown fur collar lying flat on the shoulders, deep blue surcoat with one broad pale white vertical band.
middle left n2s spearman: quilted padded gambeson in blue with pale white quilting lines.
middle center n2a hunter: brown leather and grey fur vest over a blue tunic, small arrow quiver with white fletching showing behind the LEFT shoulder (viewer's left).
middle right n3a pathfinder: dark fur cloak over blue tunic and leather, a white fur trim, arrow quiver behind the LEFT shoulder.
bottom left n3c mounted retainer: grey mail hauberk with mail upper-arm stubs, blue surcoat with a pale white vertical band.
bottom center and bottom right cells EMPTY.
```

## 2. `nord-heads.png` — приложить `heads.png`, затем `body.png`

```
Production sprite sheet for an existing medieval strategy game. Attached heads.png is the EXACT FORMAT AND STYLE REFERENCE: seven HEAD LAYERS of the same game. Draw seven new head layers for another faction that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same head size, same three-quarter view turned to the VIEWER'S RIGHT, same face drawing (angular, lively but not angry, ordinary male faces, all different). body.png shows assembled figures of the same game, for scale only.
Faction: NORDMARK, northerners with fair, red and brown hair and full beards. Steel is subdued grey, cloth deep blue #2F5A85, fur grey and brown.

Square canvas, STRICT 3x3 grid of equal cells, one head centered in each used cell with generous transparent gaps. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No shoulders, no collar, no body, no shield. Not photorealistic, not glossy 3D.

Every head ends at the bottom in a SHORT NECK PART cut straight and slightly rounded a little below the chin, at the same height for all seven. NO BARE SKIN on the neck part: it is covered by the beard, a hood or mail. Beards end at the cut line, they do not hang below it. All heads are no taller than about 1.3 times the head height without the neck part.
Cells in reading order:
top left n1 bondi: NO helmet, shaggy shoulder-length fair hair tucked behind the ears, big full blond beard covering the throat.
top center n2 axeman: steel nasal helmet with a riveted brow band like the reference, braided red-brown beard covering the throat.
top right n3 huscarl: steel SPECTACLE HELMET (rounded cap with riveted eye-and-nose guard shaped like spectacles) with a short grey mail aventail hanging from the rim around the cheeks and neck down to the cut line, full dark beard.
middle left n2s spearman: round quilted padded cloth cap in blue, short brown beard covering the throat.
middle center n2a hunter: grey-brown fur-lined hood drawn up over the head and around the neck down to the cut line, young face, light stubble.
middle right n3a pathfinder: steel nasal helmet worn over a dark fur hood that wraps the neck down to the cut line, grey-streaked beard.
bottom left n3c mounted retainer: steel SPECTACLE HELMET like the huscarl's with a mail aventail covering the neck down to the cut line, blond beard.
bottom center and bottom right cells EMPTY.
```

## 3. `nord-shields.png` — приложить `shields.png`

```
Production sprite sheet for an existing medieval strategy game. Attached shields.png is the EXACT FORMAT AND STYLE REFERENCE: the SHIELD LAYERS of the same game. Draw new shields for another faction that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same size as the reference round shields, same slight tilt and front view.
Faction: NORDMARK. Colours: deep blue #2F5A85, pale silvery white #DFE6EA, wood brown, iron.

Square canvas, STRICT 3x3 grid of equal cells, one shield centered in each used cell with generous transparent gaps; unused cells EMPTY. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No hands, no arms, no figure. Each shield drawn COMPLETE with nothing overlapping it. Not photorealistic, not glossy 3D. All five are ROUND wooden shields with a domed iron boss in the center.
top left n1 bondi: plain wooden planks, faded blue paint, rawhide rim, no rivets.
top center n2 axeman: halves of deep blue and pale white divided vertically, rawhide rim.
top right n3 huscarl: deep blue field with a pale white eight-pointed star around the boss, iron rim with rivets.
middle left n2s spearman: quartered deep blue and pale white, rawhide rim.
middle center, middle right: EMPTY.
bottom left n3c mounted retainer: deep blue field with a pale white eight-pointed star around the boss, iron rim with rivets.
bottom center and bottom right: EMPTY.
```

## 4. `bow.png` — приложить `weapons.png`

```
Production sprite asset, transparent background, same clean HERALDIC GRAPHIC art style as the attached weapons.png: navy outlines, broad cel-shaded steel, dark brown wood, restrained dull brass, no realistic texture.
ONE upright wooden hunting BOW in the center of a square canvas, seen from the side as held in battle: the bow stave is a tall gentle D-curve bulging to the RIGHT, dark brown wood with a wrapped leather grip in the middle, the taut string runs straight and vertical along the LEFT side, one arrow nocked across the grip pointing RIGHT with a steel head and white fletching. The bow fills most of the canvas height. No hands, no quiver, no labels, no frames, no shadows. Keep detail economical so it reads at 15-40px.
```

Если генератор вернул шахматку вместо прозрачности — ничего, фон вычищается заливкой от краёв.
