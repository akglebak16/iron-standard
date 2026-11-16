extends RefCounted
## Companion remarks outside the battle field: after a win or a loss and on entering a town.
## Lines live in the companion's `voice` in companions.json under "win", "lose" and "town";
## a companion without such lines stays silent.
const WIN := "win"
const LOSE := "lose"
const TOWN := "town"
const TOWN_CHANCE := 0.3 # a remark on most visits would turn into noise
const LINE := "%s: «%s»"
const Banter = preload("res://apps/godot/presentation/battle/banter_lines.gd")
const CAMP := "camp"
const CAMP_EVERY_HOURS := 8 # while the party waits, a pair may talk once in this many hours
const CAMP_CHANCE := 0.4

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

## Two lines of a pair talking ("camp", "win", "lose"), when both are among `present` (companion ids).
## `hired` are the player's companion rows (id, lvl, name): the pair's stage follows their levels.
static func pair_exchange(hired: Array, present: Array, catalog: RefCounted, kind: String, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	var level := {}
	for c in hired:
		level[String(c.id)] = int(c.get("lvl", 1))
	var options: Array = []
	for pair: Dictionary in Banter.PAIRS:
		if not (pair.first in present and pair.second in present and level.has(pair.first) and level.has(pair.second)):
			continue
		var exchanges: Array = Banter.lines_for(pair, kind, Banter.stage(level[pair.first], level[pair.second]))
		if not exchanges.is_empty():
			options.append([pair, exchanges])
	if options.is_empty():
		return out
	var chosen: Array = options[rng.randi_range(0, options.size() - 1)]
	var pair: Dictionary = chosen[0]
	var exchange: Array = chosen[1][rng.randi_range(0, chosen[1].size() - 1)]
	var opener: String = pair.first if exchange[0] == pair.tags[0] else pair.second
	var other: String = pair.second if opener == pair.first else pair.first
	out.append(LINE % [String(catalog.get_companion(opener).get("name", opener)), exchange[1]])
	out.append(LINE % [String(catalog.get_companion(other).get("name", other)), exchange[2]])
	return out
