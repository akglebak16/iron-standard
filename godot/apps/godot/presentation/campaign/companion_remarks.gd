extends RefCounted
## Companion remarks outside the battle field: after a win or a loss and on entering a town.
## Lines live in the companion's `voice` in companions.json under "win", "lose" and "town";
## a companion without such lines stays silent.
const WIN := "win"
const LOSE := "lose"
const TOWN := "town"
const TOWN_CHANCE := 0.3 # a remark on most visits would turn into noise
const LINE := "%s: «%s»"

## "Name: «line»" from a random companion among `ids` that has lines of `kind`, or "".
static func pick(ids: Array, catalog: RefCounted, kind: String, rng: RandomNumberGenerator) -> String:
	var speakers: Array = []
	for id in ids:
		var definition: Dictionary = catalog.get_companion(String(id))
		var lines: Array = definition.get("voice", {}).get(kind, [])
		if not lines.is_empty():
			speakers.append([String(definition.get("name", id)), lines])
	if speakers.is_empty():
		return ""
	var chosen: Array = speakers[rng.randi_range(0, speakers.size() - 1)]
	var lines: Array = chosen[1]
	return LINE % [chosen[0], lines[rng.randi_range(0, lines.size() - 1)]]
