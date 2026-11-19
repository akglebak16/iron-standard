# Поселения карты (#254) — промпты

Генератор — OpenAI (ChatGPT). Один лист — один вид поселения, семь культур в одном порядке:
Нордмарк, Аурелийская империя, Кеширское ханство, Галлия, Эмират Хайрат, Мядельский доминион, Пакт.
Флаги не рисовать — флаг владельца ставит код. Сборка: `node godot/tools/map/render_heraldic_settlements.cjs`.

1. `towns.png` — вложения: старые иконки карты (`settlements-old.png`, вырезка из `settlements.png`), `body.png` бойцов
   для стиля. «Draw a WALLED TOWN … ONE tall landmark building in the middle», по культуре: Нордмарк — тёмные срубы и
   ставкирха с частоколом; империя — светлый камень, черепица, базилика с куполом; ханство — юрты, глинобитные дома,
   деревянная вышка с бирюзовой крышей, вал с частоколом; Галлия — известняк, сланец, готический собор со шпилем;
   эмират — беленые и охристые саманные дома, мечеть с куполом и минаретом; доминион — срубы под соломой, кирпичный
   готический донжон; пакт — красный кирпич, черепица, кирпичный костёл. «NO flags or banners anywhere», «small flat
   oval patch of packed earth with a soft dark shadow, the same size in every cell».
2. `castles.png` — вложения: готовый `towns.png` первым («SAME cell order, SAME materials and colours per culture,
   SAME overall size»), старые иконки вторым. «A castle is a military stronghold, NOT a town: no houses and no church».
3. `villages.png` — вложения те же. «NOT fortified: no walls, no towers», «about two thirds of the width of a town»;
   восьмая клетка — логово разбойников: «three ragged dark canvas tents, a crude palisade of sharpened stakes, a campfire».
