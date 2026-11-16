extends RefCounted
## The item card of the cargo hold and the market (itemDock, pierceBars, swingLabel, cmpDelta in src/06b_inventory.js):
## what the thing is, its figures against what is worn in the same slot, its traits and how it pierces armour.
const DamageType = preload("res://core/equipment/rules/damage_type.gd")
const Economy = preload("res://core/campaign/economy/party_economy.gd")

const SLOT_NAMES := {"head": "Голова", "body": "Тело", "hands": "Руки", "legs": "Ноги", "melee": "Ближний бой", "ranged": "Дальний бой", "shield": "Щит", "horse": "Конь"}
const WEAPON_TYPES := {"sword": "Меч", "axe": "Топор", "mace": "Булава", "spear": "Копьё", "twohand": "Двуручное", "polearm": "Древковое", "bow": "Лук", "xbow": "Арбалет", "throw": "Метательное", "fist": "Кулаки"}
const DAMAGE_TYPES := {
	"cut": ["Рубящий", "+15% урона по лёгкой броне, тяжёлую почти не берёт"],
	"pierce": ["Колющий", "лучше всех пробивает среднюю броню (кольчуги)"],
	"blunt": ["Дробящий", "лучше всех пробивает латы, сильнее отбрасывает"],
}
const TIERS := [["Простое", "#a89f8a"], ["Добротное", "#8fc24f"], ["Редкое", "#5fa0e6"], ["Мастерское", "#e5902a"]]
const ARMOR_CLASSES := [["Лёгкая броня", 0.0], ["Средняя", 20.0], ["Тяжёлая", 40.0]]
const PIERCE_FULL_BAR := 0.55

## Temp of a melee swing by its speed factor.
static func swing_label(speed: float) -> String:
	if speed < 1.0:
		return "быстрый"
	if speed <= 1.1:
		return "обычный"
	return "медленный" if speed <= 1.35 else "тяжёлый"

static func percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)

static func _number(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0")

## «▲ +5» / «▼ −0.2» against the item worn in the same slot; empty when equal or nothing to compare.
static func delta(item: Dictionary, current: Dictionary, key: String) -> Dictionary:
	var d := float(item.get(key, 0.0)) - float(current.get(key, 0.0))
	if is_zero_approx(d):
		return {}
	var amount := percent(d) if item.get("slot") == "shield" else _number(d)
	return {"text": ("▲ +" if d > 0.0 else "▼ ") + amount, "trend": 1 if d > 0.0 else -1}

## {title, color, subtitle, stats: [{label, value, delta}], traits, pierce: [{label, value, fill}], note}.
## `current` is the item worn in that slot, compared only when `compare` is on (cargo items, not the doll).
static func describe(item: Dictionary, current: Dictionary = {}, compare := false) -> Dictionary:
	var stats: Array = []
	var traits: Array = []
	var pierce: Array = []
	var note := ""
	if not item.has("slot"):
		var food: int = int(Economy.FOOD_VALUE.get(String(item.get("id", "")), 0))
		stats.append({"label": "Вес", "value": _number(float(item.get("w", 0))), "delta": {}})
		stats.append({"label": "Обычная цена", "value": str(int(item.get("p", item.get("price", 0)))), "delta": {}})
		if food > 0:
			stats.append({"label": "Провизия", "value": "+%d порц." % food, "delta": {}})
		return {"title": String(item.get("n", item.get("name", ""))), "color": Color("#e8d6ac"), "subtitle": "Товар · провизия" if food > 0 else "Товар",
			"stats": stats, "traits": traits, "pierce": pierce, "note": note}
	var cmp := current if compare else {}
	var tier: Array = TIERS[clampi(int(item.get("tier", 0)), 0, 3)]
	var damage_type := String(item.get("dt", ""))
	var subtitle: String = SLOT_NAMES.get(item.slot, "")
	if damage_type != "":
		subtitle += " · %s · %s урон" % [WEAPON_TYPES.get(item.get("wt", ""), ""), String(DAMAGE_TYPES.get(damage_type, [""])[0]).to_lower()]
	subtitle += " · " + String(tier[0])
	var ranged := bool(item.get("rng", false))
	if item.has("dmg"):
		stats.append({"label": "Урон", "value": _number(float(item.dmg)), "delta": delta(item, cmp, "dmg") if compare else {}})
		stats.append({"label": "Хват", "value": "двуручное" if int(item.get("hands", 1)) == 2 else "одноручное", "delta": {}})
		if ranged:
			stats.append({"label": "Дальность", "value": str(int(item.get("range", 0))), "delta": {}})
			stats.append({"label": "Перезарядка", "value": _number(float(item.get("cd", 0))) + " с", "delta": {}})
		else:
			stats.append({"label": "Темп", "value": swing_label(float(item.get("spd", 1.0))), "delta": {}})
			var reach := float(item.get("reach", 0))
			stats.append({"label": "Длина", "value": ("+" + _number(reach)) if reach != 0.0 else "обычная", "delta": {}})
	elif item.slot == "shield":
		stats.append({"label": "Блок", "value": percent(float(item.get("v", 0))), "delta": delta(item, cmp, "v") if compare else {}})
		stats.append({"label": "От стрел", "value": "+" + percent(float(item.get("projectile_block_bonus", 0))), "delta": {}})
	elif item.slot == "horse":
		stats.append({"label": "Скорость", "value": _number(float(item.get("v", 0))), "delta": delta(item, cmp, "v") if compare else {}})
	else:
		stats.append({"label": "Броня", "value": "+" + _number(float(item.get("v", 0))), "delta": delta(item, cmp, "v") if compare else {}})
	if float(item.get("w", 0)) != 0.0:
		stats.append({"label": "Вес", "value": _number(float(item.w)), "delta": {}})
	if item.get("brk", false):
		traits.append("пробивает блок щитом")
	if float(item.get("kb", 0)) >= 2.0:
		traits.append("сильно отбрасывает")
	if item.get("anticav", false):
		traits.append("бонус против конницы")
	if int(item.get("cleave", 0)) >= 4:
		traits.append("задевает до %d целей" % int(item.cleave))
	if item.has("dmg") and int(item.get("hands", 1)) == 2 and not ranged:
		traits.append("щит не носят")
	if ranged and int(item.get("hands", 1)) == 2:
		traits.append("щит уходит за спину")
	if ranged:
		traits.append("боеприпасы бесконечные")
	if DAMAGE_TYPES.has(damage_type):
		for armor_class in ARMOR_CLASSES:
			var p := DamageType.pierce(damage_type, float(armor_class[1]), float(item.get("pb", 0.0)))
			pierce.append({"label": armor_class[0], "value": percent(p), "fill": clampf(p / PIERCE_FULL_BAR, 0.03, 1.0)})
		note = DAMAGE_TYPES[damage_type][1]
	return {"title": String(item.get("name", "")), "color": Color(tier[1]), "subtitle": subtitle, "stats": stats, "traits": traits, "pierce": pierce, "note": note}
