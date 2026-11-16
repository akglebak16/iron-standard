extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const CompanionCatalog = preload("res://core/characters/data/companion_catalog.gd")
const Remarks = preload("res://apps/godot/presentation/campaign/companion_remarks.gd")

func _initialize() -> void:
	var catalog := CompanionCatalog.new()
	assert(ContentLoader.populate(catalog))
	var z: Dictionary = catalog.get_companion("zahariy")
	# a homebody with an opinion on every prince: lines for battle, town and both outcomes
	for kind in ["start", "siege", "kill", "killUndead", "taunt", "hurt", "down", "win", "lose", "town"]:
		var lines: Array = z.voice.get(kind, [])
		assert(lines.size() >= 3, "Zahariy needs several %s lines" % kind)
		var seen := {}
		for line in lines:
			assert(not seen.has(line), "No repeated %s line: %s" % [kind, line])
			seen[line] = true
			assert(String(line).length() <= 64, "Fits a speech bubble: %s" % line)
	assert("Жалею о том дне, когда впервые вышел из дома." in z.voice.start)
	# remarks outside battle come from companions that have such lines
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var win := Remarks.pick(["zahariy"], catalog, Remarks.WIN, rng)
	assert(win.begins_with(String(z.name) + ": «") and win.trim_prefix(String(z.name) + ": «").trim_suffix("»") in z.voice.win)
	assert(Remarks.pick([], catalog, Remarks.TOWN, rng) == "", "Nobody hired, nobody speaks")
	assert(Remarks.pick(["no_such_companion"], catalog, Remarks.LOSE, rng) == "")
	print("Zahariy lines tests passed")
	quit(0)
