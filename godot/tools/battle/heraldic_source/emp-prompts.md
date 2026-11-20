# Аурелийская империя: промпты для частей бойцов (#225)

Восемь бойцов в сетке 3×3 (порядок клеток во всех листах одинаковый):

| клетка | id | боец | шлем | доспех | щит | оружие |
|---|---|---|---|---|---|---|
| верх слева | e1 | Рекрут | стёганая шапка | туника | каплевидный | меч |
| верх центр | e2 | Легионер | плоский шлем | кольчуга с табардом | каплевидный | меч |
| верх справа | e3 | Триарий | шлем с гребнем | чешуя | каплевидный | меч |
| середина слева | e2s | Пикинёр | шапель | стёганка | каплевидный | копьё |
| середина центр | e3s | Алебардист | шапель | кольчуга с табардом | нет | алебарда |
| середина справа | e2a | Арбалетчик | шапель | стёганка | нет | арбалет |
| низ слева | e3a | Стрелок-ветеран | плоский шлем | кольчуга с табардом | нет | арбалет |
| низ центр | e3c | Катафракт (конный) | шлем с маской | золочёная чешуя | каплевидный | лэнс |

Цвета: багряный #7D1F28 и золото #D8A838, сталь, бронза, тёмная кожа. Герб — солнце.
Кони общие (`horses.png`, бардированный), попону сборщик перекрашивает в багряный.
Оружие всё есть: меч, копьё, алебарда, арбалет (`weapons.png`), лэнс (`lance.png`).

## 1. `emp-torsos.png` — приложить `torsos.png`, затем `body.png`

```
Production sprite sheet for an existing medieval strategy game. Attached torsos.png is the EXACT FORMAT AND STYLE REFERENCE: seven TORSO LAYERS of the same game. Draw eight new torso layers for another faction that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same size, same proportions, same front view, same shoulder width and belt height, same economical broad cloth folds. body.png shows figures of the same game with heads, for scale only.
Faction: AURELIAN EMPIRE, a disciplined imperial army with legion traditions. Colours: deep crimson #7D1F28 and gold #D8A838, subdued grey steel, warm bronze, dark brown leather, brass buckle. NOT ochre-and-charcoal like the reference.

Square canvas, STRICT 3x3 grid of equal cells, one torso centered in each used cell with generous transparent gaps. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No head, no neck, no arms, no hands, no legs, no shield, no weapon. Not photorealistic, not glossy 3D.

Each torso goes from the waist belt up to the shoulders, rounded shoulders with short upper-arm stubs exactly like the reference torsos, no arms below them. The belt runs straight across the whole waist with ONE buckle in the middle.
NECK OPENING, critical: exactly like in torsos.png. The collar lies FLAT on the shoulders and ends at shoulder level in a low, wide, slightly oval opening seen from the front: a thin rim with a navy outline and a DARK, almost black hollow inside. NO stand-up collar, NO cloth ring rising above the shoulders, nothing that could read as a neck.
Cells in reading order:
top left e1 recruit: plain crimson wool tunic with a thin gold hem at the shoulders, plain leather belt.
top center e2 legionary: grey mail hauberk with mail upper-arm stubs, crimson tabard with a gold border.
top right e3 triarius (veteran): bronze-and-steel scale armour over the chest and shoulders, crimson cloth showing at the arm stubs, a gold sun disc on the chest.
middle left e2s pikeman: quilted padded gambeson in crimson with gold quilting lines.
middle center e3s halberdier: grey mail hauberk, crimson tabard with one broad gold vertical band.
middle right e2a crossbowman: quilted padded gambeson in crimson, small bolt pouch on the belt.
bottom left e3a veteran marksman: grey mail hauberk, crimson tabard with a gold border, bolt pouch on the belt.
bottom center e3c cataphract (mounted, heavy): gilded gold scale armour covering chest and shoulders, crimson cloth trim, gold sun disc on the chest.
bottom right EMPTY.
```

## 2. `emp-heads.png` — приложить `heads.png`, затем `body.png`

```
Production sprite sheet for an existing medieval strategy game. Attached heads.png is the EXACT FORMAT AND STYLE REFERENCE: seven HEAD LAYERS of the same game. Draw eight new head layers for another faction that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same head size, same three-quarter view turned to the VIEWER'S RIGHT, same face drawing (angular, lively but not angry, ordinary male faces, all different). body.png shows assembled figures of the same game, for scale only.
Faction: AURELIAN EMPIRE, southern imperial soldiers: dark and brown hair, mostly clean-shaven or short stubble, a few short beards. Steel is subdued grey, bronze warm, cloth deep crimson #7D1F28, trim gold #D8A838.

Square canvas, STRICT 3x3 grid of equal cells, one head centered in each used cell with generous transparent gaps. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No shoulders, no collar, no body, no shield. Not photorealistic, not glossy 3D.

Every head ends at the bottom in a SHORT NECK PART cut straight and slightly rounded a little below the chin, at the same height for all eight. NO BARE SKIN on the neck part: it is covered by a mail coif, a padded cap's flaps, a cloth neck guard or a beard down to the cut line. A mail coif hangs from the helmet rim, covers the sides of the head, the throat and the whole neck, ends at the cut line; it must NOT stop at the cheeks and must NOT spread out like a cape. All heads are no taller than about 1.3 times their helmet height, not counting a crest.
Cells in reading order:
top left e1 recruit: round quilted padded cloth cap in crimson with cheek flaps tied under the chin covering the throat, young clean-shaven face.
top center e2 legionary: steel FLAT-TOPPED helmet (cylindrical cap with a flat top and a riveted brow band) with a grey mail coif covering the neck, short stubble.
top right e3 triarius: rounded steel helmet with a tall transverse CREST of crimson horsehair in a gold holder, bronze cheek guards, mail coif covering the neck, short dark beard. The crest no taller than half the helmet height.
middle left e2s pikeman: steel KETTLE HAT (wide flat brim) over a crimson padded coif that covers the neck, clean-shaven.
middle center e3s halberdier: steel KETTLE HAT over a grey mail coif covering the neck, short brown beard.
middle right e2a crossbowman: steel KETTLE HAT over a crimson padded coif covering the neck, stubble.
bottom left e3a veteran marksman: steel FLAT-TOPPED helmet like the legionary's, mail coif covering the neck, grey-streaked short beard.
bottom center e3c cataphract: closed steel helmet with a gilded FACE MASK (stern calm sculpted face in gold-tinted steel, narrow eye slits) and a grey mail aventail covering the neck down to the cut line, small crimson plume no taller than half the helmet height.
bottom right EMPTY.
```

## 3. `emp-shields.png` — приложить `shields.png`

```
Production sprite sheet for an existing medieval strategy game. Attached shields.png is the EXACT FORMAT AND STYLE REFERENCE: the SHIELD LAYERS of the same game. Draw new shields for another faction that could sit in that sheet unnoticed: same HERALDIC GRAPHIC style, deep navy outlines of the same thickness, bold flat planes, 3-tone cel shading, same size as the reference KITE shields, same slight tilt and front view.
Faction: AURELIAN EMPIRE. Colours: deep crimson #7D1F28, gold #D8A838, steel, bronze.

Square canvas, STRICT 3x3 grid of equal cells, one shield centered in each used cell with generous transparent gaps; unused cells EMPTY. Fully transparent background. No text, numbers, cell borders, ground, bases or shadows. No hands, no arms, no figure. Each shield drawn COMPLETE with nothing overlapping it. Not photorealistic, not glossy 3D. All five are KITE shields like the reference kite shields.
top left e1 recruit: plain crimson field, rawhide rim, no emblem.
top center e2 legionary: crimson field with a gold sun (disc with straight rays) in the upper half, steel rim.
top right e3 triarius: crimson field with a gold sun, gold border stripe, steel rim with rivets.
middle left e2s pikeman: crimson and gold halves divided vertically, rawhide rim.
middle center, middle right, bottom left: EMPTY.
bottom center e3c cataphract: crimson field with a large gold sun, gilded rim with rivets.
bottom right EMPTY.
```

## Варианты

Листы `emp-torsos-v1…v3.png` и `emp-heads-v1…v3.png` — правка `emp-torsos.png` / `emp-heads.png` (вложение) тем же
генератором, по образцу вариантов Галлии (`kin-prompts.md`): те же восемь бойцов в тех же клетках, тот же тип доспеха,
цвета и силуэт, меняются только детали и люди. Туловища: v1 — поношенное сукно с тёмными заплатами, отделка тонкими
полосами, простые железные пряжки, завязанный кушак; v2 — кожаные ремни или небольшие наплечники, кайма с шашечным или
геометрическим узором, заклёпки, поясные сумки; v3 — выцветшее сукно, контрастная отделка ворота, перевязь через грудь у
суконных бойцов, круглые бляхи, видны ряды заклёпок на пластинах и кольчуге. В промпт добавлено «The rim at the back of
the neck opening keeps the colour it has in the attached sheet, NOT grey». Головы: v1 — пожилые ветераны с проседью в
бородах, обветренные лица; v2 — молодые, бритые или с лёгкой щетиной, светлее волосы; v3 — широкие лица, тёмные волосы,
густые усы или полные бороды, кое-где шрам. Закрывающий лицо шлем катафракта меняет одну мелочь: v1 — другой цвет
плюмажа, v2 — тонкая полосатая лента, v3 — металлическое навершие.
