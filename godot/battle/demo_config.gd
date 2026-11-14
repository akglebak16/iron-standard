extends RefCounted
## Encounter and placeholder drawing used only by the current playable preview.

const SEED := 4017
const PLAYER_INFANTRY := 18
const PLAYER_ARCHERS := 5
const ENEMY_INFANTRY := 20
const ENEMY_ARCHERS := 4
const HERO_POSITION := Vector2(780, 850)
const HERO_TROOP := "n3"
const PLAYER_INFANTRY_TROOP := "n1"
const PLAYER_ARCHER_TROOP := "n2a"
const ENEMY_INFANTRY_TROOP := "e1"
const ENEMY_ARCHER_TROOP := "e2a"
const CAMERA_ZOOM := 0.75
const GROUND_COLOR := Color("#78845d")
const PLAYER_COLOR := Color("#285a83")
const ENEMY_COLOR := Color("#9b3f38")
const DEAD_COLOR := Color("#42362d")
const PLAYER_FACTION := "nord"
const ENEMY_FACTION := "emp"
const CATALOG_ERROR := "Не удалось загрузить каталог войск"
const HERO_DOWN := "Герой пал"
const VICTORY := "Победа"
const DEFEAT := "Поражение"
const IN_PROGRESS := "Бой"
const HUD_TEXT := "%s  |  Свои: %d  Враги: %d  Силы: %d\nWASD ходить · Shift бег · ЛКМ удар · ПКМ блок · 1–4 группа · Q держать · E за мной · R атаковать · F отход"
