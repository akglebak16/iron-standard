extends RefCounted
## File boundary. Domain catalogs only validate supplied values; paths live here.
const Troops = preload("res://core/troops/data/catalog.gd")
const Gear = preload("res://core/equipment/data/gear_catalog.gd")
const Perks = preload("res://core/characters/data/perk_catalog.gd")
const Companions = preload("res://core/characters/data/companion_catalog.gd")
const Goods = preload("res://core/campaign/data/goods_catalog.gd")
const Factions = preload("res://core/campaign/data/faction_catalog.gd")
const PATHS := {
	"troops": "res://content/gameplay/troops/troops.json", "gear": "res://content/gameplay/equipment/items.json",
	"perks": "res://content/gameplay/characters/perks.json", "companions": "res://content/gameplay/characters/companions.json",
	"goods": "res://content/gameplay/campaign/goods.json", "factions": "res://content/gameplay/campaign/factions.json",
	"europe": "res://content/gameplay/campaign/europe.json",
}

static func populate(catalog: RefCounted) -> bool:
	var path: String = PATHS.get(catalog.CONTENT_KEY, "")
	if path.is_empty(): return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return false
	return catalog.replace_data(JSON.parse_string(file.get_as_text()))

## Fresh definitions per context; failed loading never publishes a partial registry.
static func registry() -> Dictionary:
	var catalogs := {"troops": Troops.new(), "gear": Gear.new(), "perks": Perks.new(),
		"companions": Companions.new(), "goods": Goods.new(), "factions": Factions.new()}
	for catalog in catalogs.values():
		if not populate(catalog): return {}
	for catalog in catalogs.values(): catalog.seal()
	catalogs.make_read_only()
	return catalogs
