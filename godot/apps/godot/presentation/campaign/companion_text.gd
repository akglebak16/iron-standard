extends RefCounted
## Companion skill lines shared by the tavern and the party window (SK_TXT, compRank, compSkillText in src/05e_comps.js).
const SK_TXT := {"map": "отряд идёт по карте быстрее", "cargo": "обоз вмещает больше", "surv": "из павших бойцов больше раненых", "heal": "герой лечится быстрее",
	"wage": "жалованье ниже", "buy": "покупка дешевле", "hire": "найм и улучшение войск дешевле", "flee": "шанс уйти от погони выше", "loot": "добыча после боя больше",
	"size": "отряд больше на", "sell": "продажа дороже", "quest": "награды за задания больше", "xp": "герой получает больше опыта", "siege": "штурм легче: защита стен слабее на"}

static func rank(c: Dictionary) -> int:
	return mini(3, 1 + floori((int(c.get("lvl", 1)) - 1) / 3.0))

static func skill_text(d: Dictionary, c: Dictionary) -> String:
	var r := rank(c)
	var parts: Array = []
	for k in d.sk:
		var v: float = float(d.sk[k][r - 1])
		parts.append("%s %s" % [SK_TXT.get(k, k), ("+%d" % roundi(v)) if k == "size" else ("+%d%%" % roundi(v * 100.0))])
	return ", ".join(parts) + " (ранг %s)" % ["I", "II", "III"][r - 1]
