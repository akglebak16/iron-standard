# Возможности JS → Godot → проверка

Таблица для удаления браузерной версии: что из `src/` есть в Godot, где лежит и чем проверено.
Мультиплеер (`src/08_net.js`, `src/09_netui.js`, `server/`) и новые возможности из issues (#82 осадные машины и
лестницы, #83 скорость по местности) сюда не входят. Сенсорное управление по решению владельца не переносим:
игра делается для компьютера.

Статусы:
- **совпадает и проверено** — поведение сверено с кодом JS, есть Godot-тест или сверка экспортёром;
- **отличается** — есть в Godot, но заметно не так, как в JS (что именно — в последнем столбце);
- **отсутствует** — в Godot этого нет;
- **не проверено** — в Godot есть, но построчно с JS не сверено.

Сверка 2026-11-16: 554 функции JS (без мультиплеера); 250 из них Godot-код прямо называет в комментариях,
остальные просмотрены по смыслу. Строки ниже — возможности для игрока, а не функции. Пути относительно `godot/`.

## Итог

| Статус | Строк |
| --- | --- |
| совпадает и проверено | 22 |
| отличается | 9 |
| отсутствует | 4 |
| не проверено | 40 |
| не переносим | 2 |

Чтобы удалить JS, все строки должны стать «совпадает и проверено» (или «не переносим» по решению владельца).

## Данные и графика

| Возможность | JS | Godot | Проверка | Статус | Что не так |
| --- | --- | --- | --- | --- | --- |
| 67 типов войск | `01_core.js` `TROOPS` | `content/gameplay/troops/troops.json`, `core/troops/data/catalog.gd` | `tools/troops/export_troops.cjs --check`, `test_catalog_validation.gd` | совпадает и проверено | |
| Фракции, знамёна и цвета игрока | `01_core.js` `FACTIONS`, `BANNERS` | `content/gameplay/campaign/factions.json`, `visuals/assets/banner_*` | `test_banner_palettes.gd` | совпадает и проверено | |
| 55 предметов снаряжения, типы урона | `01b_gear.js` | `core/equipment/` | `export_gear.cjs --check`, `test_gear_catalog.gd`, `test_damage_type.gd` | совпадает и проверено | |
| Атрибуты, 20 перков и их эффекты | `01c_perks.js` | `core/characters/rules/perk_effects.gd` | `export_perks.cjs --check`, `test_perk_effects.gd`, `test_hero_strike.gd` | совпадает и проверено | |
| Починка старых героев (`heroFix`) | `01c_perks.js` | `core/campaign/world/world_save.gd` | `test_save_v2.gd` | не проверено | Набор подставляемых полей не сверен |
| Спрайты войск (536 вариантов) и составная экипировка | `02_art.js` `buildSprite` | PNG-атласы `visuals/assets/`, `original_art.gd` | экспорт из JS, `test_banner_palettes.gd` | совпадает и проверено | |
| Лица героя и спутников | `02_art.js` `makeVariant`, `drawHead`, `drawHelm` | `visuals/face_variant.gd`, `faces_0.png` | `test_face_variant.gd` | отличается | Мелкие случайные детали шлема и цвет кистей рук общие для всех (seed 7) |
| Нежить: черепа и гнилые лица | `02_art.js` `drawUndeadHead` | атлас `components_*` | — | не проверено | |
| Земля поля боя по биомам | `02_art.js` `paintGround` | `presentation/battle/terrain/ground.gdshader` | — | отличается | Шейдер вместо холста; точного совпадения рисунка нет |
| Деревья и кусты | `02_art.js` `treeSprite`, `bushSprite` | атласы `tree_*`, `bush_*`, `vegetation_view.gd` | `test_vegetation.gd` | отличается | В JS каждое дерево своё (по seed), в Godot 3 дерева и 2 куста на биом |
| Гербы, поселения, караван | `02_art.js` `crestCanvas`, `05b_worldart.js` | атласы `crest_*`, `settlements.png`, `caravan.png` | экспорт из JS | совпадает и проверено | |

## Бой

| Возможность | JS | Godot | Проверка | Статус | Что не так |
| --- | --- | --- | --- | --- | --- |
| Создание и расстановка армий | `03_battle.js` `startBattle`, `mkUnit`, `layout` | `core/battle/application/factory.gd`, `core/battle/model/group.gd` | `test_groups.gd`, `test_hero_factory.gd`, `test_catalog_spawn.gd` | не проверено | В чек-листе паритета «Частично» |
| Группы, приказы, перестроение | `03_battle.js` `giveOrder`, `slotPos` | `core/battle/model/group.gd` | `test_groups.gd`, `test_tactics.gd` | не проверено | |
| ИИ бойцов: движение и режимы | `03_battle.js` `steer`, `aiUnit` | `core/battle/rules/ai_decision.gd`, `movement.gd` | `test_ai_decision.gd`, `test_movement.gd`, отпечатки | не проверено | |
| Ближний бой, блок, натиск | `03_battle.js` `strike`, `undeadMul` | `core/battle/rules/combat.gd` | `test_combat.gd`, `test_block.gd`, `test_charge.gd` | не проверено | |
| Стрельба и снаряды | `03_battle.js` `shoot`, `B.arrows` | `core/battle/rules/combat.gd`, `combat_step.gd` | `test_projectile.gd` | не проверено | |
| Ранения, смерть, мораль, «Последний рубеж» | `03_battle.js` `hurt`, `kill` | `core/battle/model/state.gd`, `core/battle/rules/morale.gd` | `test_morale.gd`, `test_battle_state.gd` | не проверено | |
| Управление героем, замах, выстрел | `03_battle.js` `heroControl`, `heroStrike`, `heroShoot` | `core/battle/rules/hero_control.gd` | `test_hero_control.gd`, `test_hero_strike.gd` | не проверено | |
| Смена оружия (X) | `03_battle.js` `swapWield` | `core/battle/application/session.gd` | `test_scene.gd`, `test_session.gd` | совпадает и проверено | |
| Подкрепления волнами | `03_battle.js` (резерв) | `core/battle/model/state.gd`, `session.gd` | `test_reserve_waves.gd` | совпадает и проверено | |
| Итог боя: потери, раненые, опыт | `03_battle.js` `finishBattle`, `05c_logic.js` | `core/battle/rules/result.gd`, `core/campaign/rules/battle_aftermath.gd` | `test_result.gd`, `test_battle_aftermath.gd` | не проверено | |
| Стена, проходы, обход, укрытие | `03_battle.js` `siegeSetup`, `inGap`, `wallPush`, `wallVia`, `wallCover`, `siegeBrain` | `core/battle/model/siege_wall.gd`, `data/siege_setup.gd`, `rules/ai_decision.gd` | `test_siege.gd`, `test_siege_setup.gd` | отличается | Проходы всегда открыты (см. строку ниже) |
| Ворота с прочностью: их выбивают, «Ворота пали!», гарнизон через 45 с сам выходит из главных ворот, пролом в сильно побитой стене | `03_battle.js` `gateBreak`, `B.wall.gates`, `paintRubble` | — | — | отсутствует | В Godot проходы открыты с начала боя, ворот нет; побитая стена только расширяет главный проход |
| Камни и кипящее масло со стены | `03c_siegedef.js` | `core/battle/model/siege_defense.gd`, `siege_defense_view.gd` | `test_siege_defense.gd` | совпадает и проверено | |
| Кровь, брызги, лужи, отлетающие части | `03b_gore.js` | `impact_effects.gd`, `detached_parts.gd` | `test_impact_effects.gd` | отличается | По чек-листу паритета: не все эффекты и детали |
| Реплики и перепалки спутников | `03b_gore.js` `voiceSay`, `banterSay` | `companion_dialogue.gd`, `banter_lines.gd` | `test_companion_dialogue.gd` | не проверено | |
| Камера боя, тряска, стрелка к врагу за экраном, миникарта | `03_battle.js` `battleCamera`, `drawFoeArrow`, `drawMinimap` | `battle_camera.gd`, `hud/navigation_hud.gd` | `test_navigation_hud.gd` | не проверено | |
| Журнал боя и всплывающие числа | `03_battle.js` `blog`, `ftext` | `combat_feedback.gd`, `view.gd` | `test_scene.gd` | не проверено | |
| Боевой HUD: здоровье, силы, броня, мораль, группы, уровень героя | `07_main.js` `buildBattleHud`, `updateBattleHud` | `hud/battle_controls.gd` | `test_hud_layout.gd`, `test_autosave_music_hud.gd` | не проверено | Уровень героя и «[X]» сверены, остальное нет |
| Призрачный строй выбранных групп на «Стоять» | `06h_polish.js` `commandDraw` | `hud/order_marker.gd` | — | отличается | В Godot флажок исчезает через 4 с; в JS кольцо, направление и пунктир к строю видны, пока группа выбрана |
| Пыль из-под копыт и блики удара | `06h_polish.js` `unitPolish` | — | — | отсутствует | |
| Звуки боя | `04_audio.js` `sfx`, `tone`, `noise` | `presentation/battle/audio/` | `test_scene.gd` | не проверено | |
| Музыка боя | `04_audio.js` `musicTick(dt, 'battle')` | `audio/battle_music.gd` | — | отличается | Godot по умолчанию играет записанную дорожку `battle_theme.ogg`; процедурная музыка JS — запасной вариант |

## Карта и кампания

| Возможность | JS | Godot | Проверка | Статус | Что не так |
| --- | --- | --- | --- | --- | --- |
| Генерация Европы: берега, хребты, реки, мосты, биомы | `05_world.js` `genWorldV2` | `core/campaign/world/terrain_generator.gd`, `world_map.gd` | `test_world_map_parity.gd`, `test_terrain_parity.gd` | совпадает и проверено | |
| Старая карта первой версии для давних сохранений | `05_world.js` `genWorldV1`, `mapVer` | — | — | отсутствует | Нужна, только если переносим сохранения браузера с картой v1 |
| Поиск пути, дороги дешевле | `05_world.js` `cellCost`, `findPath` | `pathfinder.gd` | `test_terrain_parity.gd` | совпадает и проверено | |
| Рисунок карты: рельеф, дороги, реки, леса | `05b_worldart.js` | `presentation/campaign/*_layer.gd`, шейдеры | `test_campaign_render_cache.gd` | отличается | Видеокарта рисует по-своему; по чек-листу не все детали |
| Подписи поселений без наложения | `06h_polish.js` `settlementLabels` | `settlement_layer.gd` | — | не проверено | Тот же перебор смещений, сверки нет |
| Время, сутки, провизия, жалованье | `05_world.js` `dayTick`, `playerDay` | `world_state.gd`, `party_economy.gd` | `test_party_economy.gd`, `test_world_state.gd` | не проверено | |
| Отряды на карте и их ИИ, караваны, лагеря | `05_world.js` | `party_ai.gd`, `party_roster.gd` | `test_party_ai.gd` | не проверено | |
| Набор рекрутов в поселениях | `05_world.js` `genRecruits` | `world_state.gd`, `town_window.gd` | — | не проверено | |
| Задания: генерация, типы, сдача | `05_world.js`, `05c_logic.js` | `world_quests.gd` | `test_world_quests.gd` | не проверено | |
| Рынок, цены, сделки, трофеи, обоз, провизия | `05d_trade.js` | `core/campaign/economy/market.gd` | `test_market.gd`, `test_gear_and_menu.gd` | не проверено | |
| Спутники: таверны, найм, умения, ранения, рост | `05e_comps.js` | `world_companions.gd`, `companion_profile.gd` | `test_companion_profile.gd` | не проверено | |
| Кризис нежити, курганы, подъём мёртвых | `05f_undead.js` | `world_undead.gd` | `test_world_undead.gd` | не проверено | |
| Войны, походы, захват, падение государств | `05g_war.js` | `world_wars.gd` | `test_world_wars.gd` | не проверено | |
| Роды, правители, переход родов, выманивание | `05g_war.js` | `world_clans.gd` | `test_world_clans.gd` | не проверено | |
| Присяга и служба | `05g_war.js` `oathCan`, `leaveService` | `world_state.gd`, `town_window.gd` | — | не проверено | |
| Вассалы и наделы | `05h_vassals.js` | `world_vassals.gd` | `test_world_vassals.gd` | не проверено | |
| Осада на карте: блокада, голод, вылазки, деблокада, переговоры, разграбление | `05i_siege.js` | `world_siege.gd`, `world_wars.gd`, `siege_window.gd` | `test_world_siege.gd`, `test_siege_window.gd` | не проверено | |
| Расчётный бой | `05c_logic.js` `autoResult` | `auto_battle.gd` | `test_auto_battle.gd` | не проверено | |
| Встреча с отрядом, переговоры | `06_ui.js` `openEncounter`, `06e_war.js` `parleyBody` | `encounter_dialog.gd` | `test_encounter_aftermath.gd` | не проверено | |
| Плавное движение отрядов между тиками | `07_main.js` `snapWorld`, `rpos` | `party_layer.gd` | — | не проверено | |

## Окна и меню

| Возможность | JS | Godot | Проверка | Статус | Что не так |
| --- | --- | --- | --- | --- | --- |
| Главное меню, новая игра, имя, знамя, культура, «Как играть» | `06_ui.js` `renderCreate`, `07_main.js` `buildTitleMenu` | `main_menu.gd` | `test_ui_smoke.gd` | совпадает и проверено | |
| Быстрый бой: стороны и размер | `06_ui.js` `renderQuick` | `main_menu.gd`, `quick_battle_setup.gd` | `test_ui_smoke.gd` | совпадает и проверено | |
| Демо-бой на фоне меню | `07_main.js` `startDemo` | `main_menu.gd` | `test_ui_smoke.gd` | совпадает и проверено | |
| Пауза и настройки: звук, музыка, расчленёнка | `06_ui.js` `openMenu` | `pause_menu.gd` | `test_gear_and_menu.gd` | совпадает и проверено | |
| Окно поселения: найм, таверна, рынок, гарнизон, ожидание | `06_ui.js` `renderTown`, `06d_comps.js` `tavernBody` | `town_window.gd` | `test_gear_and_menu.gd` | не проверено | |
| Окно отряда: войска, характеристики, улучшение | `06_ui.js` `renderPanel`, `troopRow` | `party_window.gd` | `test_ui_smoke.gd` | не проверено | |
| Окно героя: атрибуты и перки | `06c_hero.js` | `party_window.gd` | `test_visual_interface.gd` | не проверено | |
| Обоз, кукла, сравнение вещей | `06b_inventory.js`, `06h_polish.js` `gearComparison` | `party_window.gd`, `gear_comparison.gd` | `test_gear_comparison_chronicle.gd` | совпадает и проверено | |
| Карточка вещи: назначение, урон и разница с надетым, хват, темп, длина, дальность, перезарядка, блок, защита от стрел, вес, свойства, пробитие по трём видам брони, тип урона | `06b_inventory.js` `itemDock`, `pierceBars`, `swingLabel`, `cmpDelta` | `presentation/campaign/item_card.gd`, `party_window.gd` | `test_item_card.gd` | отличается | В обозе карточка как в JS; на рынке города (`tradeDock`) пока строка с названием, видом и ценой |
| Окно спутников | `06d_comps.js` | `party_window.gd` | — | не проверено | |
| Хроника журнала | `06f_jquests.js` `jqChronicle` | `party_window.gd` | `test_gear_comparison_chronicle.gd` | совпадает и проверено | |
| Задания в журнале | `06f_jquests.js` `jqCard` | `party_window.gd` `_quests` | — | отличается | Нет типа и значка, меток «срочно», «просрочено», «готово к сдаче», заказчика с гербом, расстояния, прогресса, предупреждений и полосы времени |
| Фракции в журнале | `06g_jfactions.js` | `party_window.gd` `_factions_tab` | — | не проверено | |
| Окно осады и итог захвата | `06i_siege.js` | `siege_window.gd` | `test_siege_window.gd` | не проверено | |
| Окно итогов боя с выходом | `07_main.js` `showResult`, `quickEnded` | `battle_result_window.gd` | `test_autosave_music_hud.gd` | совпадает и проверено | |
| HUD карты, подсказки, уведомления | `07_main.js` `updateWorldHud`, `06_ui.js` `toast`, `worldTip` | `world_hud.gd`, `world_tips.gd` | `test_gear_and_menu.gd` | не проверено | |
| Маркер «Цель пути» | `06h_polish.js` `routeFinish` | `world_marks_layer.gd` | `test_autosave_music_hud.gd` | совпадает и проверено | |
| Музыка карты и меню | `04_audio.js` `musicTick(dt, 'world')` | `world_music.gd` | `test_autosave_music_hud.gd` | совпадает и проверено | |
| Ручное сохранение и загрузка | `07_main.js` `saveGame`, `loadGame` | `adapters/persistence/save_store.gd`, `world_save.gd` | `test_world_save.gd`, `test_save_v2.gd` | совпадает и проверено | |
| Автосохранение: после боя, в поселении, при выходе, в полночь | `07_main.js`, `06_ui.js` `saveGame(true)` | `composition/autosave.gd` | `test_autosave_music_hud.gd` | совпадает и проверено | |
| Перенос сохранения из браузера | `07_main.js` `loadGame` | `world_save.gd` (формат v1) | `test_save_v2.gd` | не проверено | Карта v1 не поддерживается (см. выше) |
| Управление с клавиатуры и мыши | `07_main.js` `bindInput`, `readHeroInput`, `worldKeyPan` | `world_demo.gd`, `world_camera.gd`, `view.gd` | `test_battle_controls.gd` | не проверено | |
| Сенсорное управление | `07_main.js` (touch) | — | — | не переносим | Решение владельца: игра для компьютера |
| Мультиплеер | `08_net.js`, `09_netui.js`, `server/` | — | — | не переносим | Пока не трогаем |

## Что закрыть, по порядку

1. **Ворота в осадном бою** (отсутствует): прочность ворот, выбивание пехотой, «Ворота пали!», выход гарнизона, пролом.
2. ~~Карточка вещи в обозе~~ — перенесено; на рынке города осталась короткая строка.
3. **Пыль из-под копыт и блики удара** (отсутствует).
4. **Карточки заданий** (отличается).
5. **Призрачный строй выбранных групп** (отличается).
6. Остальные «отличается»: решить, где нужно точное совпадение (земля, деревья, кровь, рисунок карты), а где Godot-вариант оставить (записанная музыка боя).
7. «Не проверено»: построчная сверка с JS по разделам, каждая сверка — тест или отметка в этой таблице.
8. Карта v1 для старых сохранений браузера — только если владелец решит переносить такие сохранения.
