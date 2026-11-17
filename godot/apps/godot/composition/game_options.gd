extends RefCounted
## Choices made on the start screen, read once by the world scene.
static var seed_value := 0       # 0 = random
static var culture := "emp"
static var hero_name := "Безымянный"
## The hero's face picked on the start screen ({skin, hair, beard, stache, bald, scar}); empty = from the seed.
static var hero_face := {}
static var continue_game := false
## Which save slot to continue from; "" = the most recent one.
static var load_slot := ""
static var banner := 0
## The hero's background (hero_origin.gd) and the start points spent on the start screen: attribute -> points.
static var origin := "smith"
static var attrs := {}
