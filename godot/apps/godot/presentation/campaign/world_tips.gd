extends RefCounted
## Text of the map tooltip for a party or a settlement under the mouse (worldTip in src/07_main.js).
const Rules = preload("res://core/campaign/world/party_rules.gd")
const WorldSiege = preload("res://core/campaign/world/world_siege.gd")
const AutoBattle = preload("res://core/campaign/world/auto_battle.gd")
const SettlementLayer = preload("res://apps/godot/presentation/campaign/settlement_layer.gd")

static func rel_name(v: float) -> String:
	if v < -20.0:
		return "Враждебные"
	if v < -5.0:
		return "Недружелюбные"
	if v < 20.0:
		return "Нейтральные"
	if v < 50.0:
		return "Дружелюбные"
	return "Союзные"

static func party_tip(state: RefCounted, p: Dictionary, factions) -> String:
	var undead: bool = p.fac == "undead"
	var what: String
	if undead:
		what = "Армия мертвецов" if p.kind == "dead" else ("Разъезд мертвецов" if p.kind == "raid" else "Стража кургана")
	elif p.kind == "cvass":
		what = "Твой вассал"
	else:
		what = factions.get_faction(p.fac).get("name", p.fac)
	var title: String = ("Крупная банда" if p.get("big", false) else "Разбойники") if p.kind == "bandit" else p.name
	var lines := [title, "%s · %d %s" % [what, Rules.troop_count(p.troops), "мертвецов" if undead else "бойцов"]]
	var house: Dictionary = state.clans.clan_of(p) if state.clans != null else {}
	if not house.is_empty():
		lines.append(house.name)
	var power: Array = AutoBattle.relative_power(state.player.troops, p.troops, state.roster.info)
	lines.append(power[0] + ("  ·  враг" if Rules.hostile_to_player(p, state.player.rel) else ""))
	return "\n".join(lines)

static func settlement_tip(state: RefCounted, s: Dictionary, factions) -> String:
	var lines := [s.name]
	var kind: String = SettlementLayer.KIND_NAMES.get(s.kind, "")
	if s.fac == "player":
		lines.append("%s · твоё владение · гарнизон %d" % [kind, Rules.troop_count(state.wars.garrison_of(s))])
	else:
		lines.append("%s · %s" % [kind, factions.get_faction(s.fac).get("gen", s.fac)])
	if WorldSiege.hostile(s, state.player.rel):
		lines.append("враждебен · " + ("ворота закрыты" if s.kind == "village" else "клик — осада, гарнизон %d" % Rules.troop_count(state.wars.garrison_of(s))))
	if s.kind == "camp":
		var c: Dictionary = state.roster.party_by_id(s.camp) if s.get("camp") != null else {}
		lines.append(("Охраняет %d головорезов" % Rules.troop_count(c.troops)) if not c.is_empty() else "Опустошено")
	elif s.fac != "player" and s.fac in Rules.REAL_FACTIONS:
		lines.append("Отношение: " + rel_name(float(state.player.rel.get(s.fac, 0))))
	if int(s.get("burnt", 0)) > 0:
		lines.append("Сожжена, отстраивается")
	if int(s.get("ruin", 0)) > 0 and s.fac != "undead":
		lines.append("Восстанавливается после руин")
	return "\n".join(lines)
