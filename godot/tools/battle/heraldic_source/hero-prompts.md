# Герой (#232) — промпты частей

Цвета стяга игрок выбирает сам, поэтому ткань рисуется КЛЮЧЕВЫМИ цветами: основной — чистый красный
#C62828 (→ c1 стяга), отделка — чистый зелёный #2E7D32 (→ c2). Код перекрашивает их в цвета стяга.

## Торсы, лист A (`hero-torsos-a.png`) — вложения: `torsos.png`, `body.png`

```
Production sprite sheet for an existing medieval strategy game. Attached torsos.png is the EXACT FORMAT AND STYLE REFERENCE: seven TORSO LAYERS of the same game. Draw 6 new torso layers that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same size, same proportions, same front view, same shoulder width and belt height, same economical broad cloth folds. body.png shows figures of the same game with heads, for scale only.
Character: the player's hero, a mercenary captain. His heraldic colours are painted as KEY COLOURS that the game recolours later, so use them EXACTLY and only as flat cloth colours: main cloth PURE RED #C62828 (with its own darker and lighter cel tones of the same red), trim and second field PURE GREEN #2E7D32. Leather is dark brown #4a3020, steel subdued grey, brass dull. Do NOT use red or green anywhere else (no red leather, no green steel tint). NOT the colours of the reference.

Square canvas, STRICT 3x3 grid of equal cells, one torso centered in each used cell with generous transparent gaps. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No head, no neck, no arms, no hands, no legs, no shield, no weapon. Not photorealistic, not glossy 3D.

Each torso goes from the waist belt up to the shoulders, rounded shoulders with short upper-arm stubs exactly like the reference torsos, no arms below them. The belt runs straight across the whole waist with ONE buckle in the middle.
NECK OPENING, critical: exactly like in torsos.png. The collar lies FLAT on the shoulders and ends at shoulder level in a low, wide, slightly oval opening seen from the front: a thin rim with a navy outline and a DARK, almost black hollow inside. NO stand-up collar, NO cloth ring or fur roll rising above the shoulders, nothing that could read as a neck.
Cells in reading order:
1 tunic: plain wool tunic in red, green hem and cuffs, leather belt.
2 fur: red tunic with a brown fur mantle over the shoulders lying flat (no fur roll at the neck).
3 mailfur: mail shirt with a brown fur mantle over the shoulders and a red sash.
4 padded: quilted gambeson in red with vertical quilting lines, green collar rim.
5 mail: long-sleeved mail hauberk, red cloth showing only at the belt edge.
6 mailtab: mail hauberk under a sleeveless tabard split down the middle, left half red, right half green.
7, 8, 9 EMPTY.
```

## Торсы, лист B (`hero-torsos-b.png`) — вложения: `torsos.png`, `body.png`

Тот же промпт, «Draw 5 new torso layers», клетки:
```
1 scale: coat of steel scales over a red tunic showing at the shoulders and hem.
2 goldscale: coat of gilded brass scales over a red tunic, green trim.
3 lamellar: steel lamellar cuirass laced with red cords over a green padded tunic.
4 goldlam: gilded lamellar cuirass laced with red cords, red shoulder cloth.
5 plate: steel plate breastplate with round pauldrons over a red surcoat with a green border.
6, 7, 8, 9 EMPTY.
```

## Головы, волосы, щиты, кольчуги

Итоговые промпты — в истории #232; суть:
- `hero-heads-a.png` / `hero-heads-b.png`: ОДИН И ТОТ ЖЕ мужчина во всех клетках, бритый, без волос и бороды, кожа
  только оттенками #E2B48C, шея закрыта тёмно-коричневым шарфом #4A3020 или бармицей. Второй лист — с первым листом
  первым вложением («THE SAME MAN with EXACTLY THE SAME FACE»). Добавить «Strictly medieval … nothing Roman or ancient»,
  иначе гребень выходит римским.
- `hero-hair.png`: та же лысая голова, волосы/борода/усы ЧИСТЫМ СИНИМ #1E5AC8 (ключ под цвет волос).
- `hero-shields.png`: поле красным #C62828 и зелёным #2E7D32.
- `hero-mail.png`: кольчуги заново — «RIVETED MAIL RINGS, NOT fish scales», иначе кольчуга = чешуя.

Совмещение голов с лысой головой по лицу: `python3 godot/tools/battle/hero_register.py` (вход — части, вырезанные
сборщиком; результат — `hero-registration.json`). Закрытые шлемы (great, flat, mask) ставятся по шарфу.
