extends RefCounted
## The player's party on the world map: position, route and walking speed (speedOf / moveAlong / pathTo in src/05_world.js).
const Pathfinder = preload("res://campaign/world/pathfinder.gd")

var name := "Отряд"
var x := 0.0
var y := 0.0
var fx := 1.0
var path: Array = []    # Vector2 points
var pi := 0
var troops: Array = []
var culture := "emp"
var gold := 650
var enter_id := -1  # settlement to enter on arrival
var food := 0
var inv := {"grain": 10}
var comps: Array = []
var quests: Array = []
var stats := {"wins": 0, "kills": 0}
var hero := {}
var rel: Dictionary = {"nord": 0, "emp": 0, "khan": 0, "kin": 0, "emi": 0, "dom": 0, "pact": 0, "bandit": -100}
var busy := ""      # "enc" / "battle" while a meeting or fight is running
var inside := false # inside a settlement
var away := false

func has_route() -> bool:
	return pi < path.size()

## Walking speed in map units per hour. Troop and perk modifiers come with the party rules.
func speed_of(paths: Pathfinder) -> float:
	var world := paths.world
	var k := world.cell_of(x, y)
	var t: int = world.cells[k]
	var m := 0.72 if t == 2 else 0.78 if t == 3 else 1.0
	if world.bio[k] == 1:
		m *= 0.85
	if paths.road[k] != 0:
		m *= 1.3
	return 18.0 * m

## Moves along the route; returns true once it is finished.
func move_along(paths: Pathfinder, dh: float) -> bool:
	var rem := speed_of(paths) * dh
	while rem > 0.0 and pi < path.size():
		var t: Vector2 = path[pi]
		var dx := t.x - x
		var dy := t.y - y
		var d := sqrt(dx * dx + dy * dy)
		if d <= rem:
			x = t.x
			y = t.y
			pi += 1
			rem -= d
		else:
			x += dx / d * rem
			y += dy / d * rem
			fx = dx / d
			rem = 0.0
	return pi >= path.size()

func path_to(paths: Pathfinder, tx: float, ty: float) -> bool:
	var found = paths.find_path(x, y, tx, ty)
	path = found if found != null else []
	pi = 0
	return found != null

func stop() -> void:
	path = []
	pi = 0
