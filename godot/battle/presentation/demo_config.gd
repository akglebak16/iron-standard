extends RefCounted
## Placeholder drawing and text used only by the current playable preview.

const CAMERA_ZOOM := 0.75
const GROUND_COLOR := Color("#78845d")
const PLAYER_COLOR := Color("#285a83")
const ENEMY_COLOR := Color("#9b3f38")
const DEAD_COLOR := Color("#42362d")
const HERO_DOWN := "Герой ранен — бой продолжается"
const VICTORY := "Победа"
const DEFEAT := "Поражение"
const IN_PROGRESS := "Бой"
const HUD_TEXT := "%s  |  Свои: %d  Враги: %d  Силы: %d\nWASD ходить · Shift бег · ЛКМ удар · ПКМ блок · 1–4 группа · Q держать · E за мной · R атаковать · F отход"

const HERO_RING_PADDING := 3.0
const HERO_RING_SEGMENTS := 20
const HERO_RING_WIDTH := 2.0
const COMPANION_RING_COLOR := Color("#e4bf70")
const PROJECTILE_RADIUS := 3.0
