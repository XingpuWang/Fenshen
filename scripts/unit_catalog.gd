extends RefCounted
## Shared authoritative definitions for hero kits, troop attributes and temporary effects.
static var DATA: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/unit_catalog.json"))
const STAT_KEYS=["physical_attack","physical_defense","magic_attack","magic_defense","max_hp","movement"]
const SKILL_KEYS=["battle","ultimate","map","passive"]

static func hero_id(unit: Dictionary) -> String:
	var id:=str(unit.get("hero_id",unit.get("id","jifa")))
	id=str(DATA.aliases.get(id,id))
	return id if DATA.heroes.has(id) else "jifa"

static func profile(unit: Dictionary) -> Dictionary:
	return DATA.heroes[hero_id(unit)]

static func skill(unit: Dictionary, slot: String) -> Dictionary:
	return profile(unit).skills[slot]

static func base_stats(unit: Dictionary) -> Dictionary:
	return canonical_stats(unit.get("stats",profile(unit).stats))

static func canonical_stats(values: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in STAT_KEYS: result[key]=int(values[key]) if key=="movement" else float(values[key])
	return result

static func canonical_effects(values: Array) -> Array:
	var result:=values.duplicate(true)
	for effect in result:
		effect.expires_turn=int(effect.expires_turn)
		for key in effect.bonuses: effect.bonuses[key]=float(effect.bonuses[key])
	return result

static func apply_bonuses(values: Dictionary, bonuses: Dictionary) -> void:
	for key in bonuses:
		if values.has(key): values[key]=maxf(1.0 if key in ["max_hp","movement"] else 0.0,float(values[key])+float(bonuses[key]))

static func effective_stats(unit: Dictionary, troop_type: String="") -> Dictionary:
	var values: Dictionary=base_stats(unit) if troop_type.is_empty() else DATA.troops[troop_type].stats.duplicate(true)
	var passive:=skill(unit,"passive")
	if troop_type.is_empty() or passive.scope=="army": apply_bonuses(values,passive.bonuses)
	for effect in unit.get("effects",[]): apply_bonuses(values,effect.bonuses)
	values.movement=clampi(int(values.movement),1,30)
	return values

static func movement(unit: Dictionary) -> int:
	return int(effective_stats(unit).movement)

static func damage(attacker: Dictionary, defender: Dictionary, damage_type: String, multiplier: float=1.0) -> float:
	var attack_key: String="magic_attack" if damage_type=="magic" else "physical_attack"
	var defense_key: String="magic_defense" if damage_type=="magic" else "physical_defense"
	return maxf(1.0,float(attacker[attack_key])*multiplier*100.0/(100.0+float(defender[defense_key])))

static func valid_stats(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=STAT_KEYS.size(): return false
	for key in STAT_KEYS:
		var n: Variant=value.get(key)
		if not (n is int or n is float) or not is_finite(float(n)): return false
		if float(n)<(1 if key in ["max_hp","movement"] else 0) or float(n)>(30 if key=="movement" else 10000): return false
		if key=="movement" and float(n)!=floor(float(n)): return false
	return true

static func valid_effects(value: Variant, turn: int) -> bool:
	if not value is Array or value.size()>32: return false
	var ids: Array=[]
	for effect in value:
		if not effect is Dictionary or not effect.get("id") is String or effect.id in ids: return false
		ids.append(effect.id)
		var until: Variant=effect.get("expires_turn")
		if not (until is int or until is float) or float(until)!=floor(float(until)) or until<=turn or until>turn+10: return false
		if not effect.get("bonuses") is Dictionary: return false
		for key in effect.bonuses:
			var n: Variant=effect.bonuses[key]
			if not key in STAT_KEYS or not (n is int or n is float) or not is_finite(float(n)) or absf(float(n))>1000: return false
	return true
