extends RefCounted
## Placeholder drawing and text used only by the current playable preview.

const HERO_DOWN := "Герой ранен — бой продолжается"
const VICTORY := "Победа"
const DEFEAT := "Поражение"
const IN_PROGRESS := "Бой"
const SOUND_HINT := " · M звук: %s · N музыка: %s"
const BLOOD_HINT := " · G кровь: %s"
const SOUND_ON := "вкл."
const SOUND_OFF := "выкл."
const HUD_TEXT := "%s  |  Свои: %d  Враги: %d  Силы: %d · Выбрано: %s · %s"
const WEAPON_HUD_TEXT := "\nОружие [X]: %s"
const CONTROL_HINT := "\nWASD ходить · Shift бег · ЛКМ удар · ПКМ блок · Колесо масштаб\n1–4 группа · Q держать · E за мной · R атаковать · F отход"

const GROUP_NAMES := ["Пехота", "Стрелки", "Конница", "Весь отряд"]
const ARROW_ARC_SCALE := 0.17
const BOLT_ARC_SCALE := 0.08
const PROJECTILE_TILT_SCALE := 1.2
const PROJECTILE_SHADOW_OFFSET := Vector2(0, 14)
const PROJECTILE_SHADOW_LENGTH := 8.0
const PROJECTILE_SHADOW_WIDTH := 1.5
const PROJECTILE_SHADOW_COLOR := Color(0, 0, 0, 0.25)
const PROJECTILE_COLOR := Color("#2a1c10")
const PROJECTILE_FLETCHING_COLOR := Color("#efe9d6")
const ARROW_LENGTH := 12.0
const JAVELIN_LENGTH := 22.0
const ARROW_WIDTH := 1.7
const JAVELIN_WIDTH := 2.6
const FLETCHING_START := 10.0
const FLETCHING_END := 13.0
const FLETCHING_WIDTH := 2.2

const FEEDBACK_LIFETIME := 0.9
const FEEDBACK_RISE_SPEED := 26.0
const FEEDBACK_OFFSET := Vector2(0, -44)
const FEEDBACK_FONT_SIZE := 18
const FEEDBACK_MAX_LABELS := 40
const BATTLE_LOG_MAX_ENTRIES := 3
const DAMAGE_RECEIVED_COLOR := Color("#e2503c")
const DAMAGE_DEALT_COLOR := Color("#f1e3b0")
const BLOCK_COLOR := Color("#d8d2c4")
const LAST_STAND_COLOR := Color("#f1d27a")
