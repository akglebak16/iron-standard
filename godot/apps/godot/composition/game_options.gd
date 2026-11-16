extends RefCounted
## Choices made on the start screen, read once by the world scene.
static var seed_value := 0       # 0 = random
static var culture := "emp"
static var hero_name := "Безымянный"
static var continue_game := false
## Which save slot to continue from; "" = the most recent one.
static var load_slot := ""
static var banner := 0
