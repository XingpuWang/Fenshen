class_name ShanheWorld
extends RefCounted

const DIRECTIONS = [Vector2i(1,0),Vector2i(1,-1),Vector2i(0,-1),Vector2i(-1,0),Vector2i(-1,1),Vector2i(0,1)]
const Economy = preload("res://scripts/settlement_economy.gd")
const BattleRules = preload("res://scripts/battle_rules.gd")
const Catalog=preload("res://scripts/unit_catalog.gd")
var pending_battle: Dictionary = {}
var garrisons: Dictionary = {}
var economy: SettlementEconomy
var theme: Dictionary
var data: Dictionary
var cells: Array
var pois: Array
var units: Array
var regions: Array
var by_hex: Dictionary = {}
var by_poi: Dictionary = {}
var radius: float = 64.0
var grid_y_scale: float=1.0
var bounds := Rect2(-3584,-3584,11264,11264)
var turn: int = 1
var revision: int = 0
var captured: int = 0
var crossed: int = 0
var test_scenario:=false
var test_city_id:=""

func _init(setup_campaign: bool = true) -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	radius=float(data.radius)
	grid_y_scale=float(data.get("grid_y_scale",1.0))
	theme = JSON.parse_string(FileAccess.get_file_as_string("res://data/fengshen.json"))
	cells = data.cells
	pois = data.pois
	units = data.units
	regions = data.regions
	for i in cells.size():
		var c: Dictionary = cells[i]
		by_hex[Vector2i(int(c.q),int(c.r))] = i
	for p in pois:
		by_poi[p.id] = p
		p.name = theme.names[p.id].name
		if setup_campaign: p.owner = "player" if p.id in theme.owned else ("shang" if p.type in ["city","pass"] else "neutral")
	for u in units:
		u.cell = int(u.cell)
		u.hero_id=Catalog.hero_id(u)
		u.stats=Catalog.canonical_stats(Catalog.profile(u).stats)
		u.effects=[]
		u.action_done=false
		u.max_ap=Catalog.movement(u)
		u.ap = int(u.max_ap)
		u.guarding = false
		u.max_soldiers = int(u.soldiers)+800
		u.morale = 50
		u.troops = BattleRules.mixed_roster(int(u.soldiers))
	if setup_campaign:
		var targets: Array = [Vector2(-1500,2010), Vector2(-1050,2460), Vector2(-2675,1440)]
		for i in units.size():
			var best: int = -1
			var distance: float = INF
			for ci in cells.size():
				if not walkable(ci) or occupied(ci,units[i].id): continue
				var d: float = center(ci).distance_squared_to(targets[i])
				if d < distance:
					distance = d
					best = ci
			units[i].cell = best
		units[1].name = "南宫适"
		units[1].title = "西岐先锋 · 镇守渭滨"
		units[2].name = "黄天化"
		units[2].title = "西岐先锋 · 北巡关津"
	economy = Economy.new(pois,theme)

func setup_chaoge_test() -> void:
	# An isolated, repeatable scenario. The campaign definition and saves stay intact.
	test_scenario=true
	for poi in pois:
		if poi.name=="朝歌": test_city_id=poi.id; break
	assert(not test_city_id.is_empty(),"Chaoge must exist on the real map")
	var city: Dictionary=by_poi[test_city_id]
	var desired:=Vector2(city.position[0],city.position[1])+Vector2(0,500)
	var first:=-1
	var second:=-1
	var best:=INF
	for a in cells.size():
		if not walkable(a) or not str(cells[a].p).is_empty(): continue
		if center(a).distance_squared_to(desired)>900*900: continue
		for candidate in cells[a].n:
			var b:=int(candidate)
			if not walkable(b,"shang") or not str(cells[b].p).is_empty() or center(b).x<=center(a).x: continue
			if not cells[a].get("g",{}).get(str(b),[]).is_empty(): continue
			var score: float=((center(a)+center(b))*.5).distance_squared_to(desired)
			if score<best: best=score; first=a; second=b
	assert(first>=0 and second>=0,"Chaoge needs two adjacent legal land tiles")
	units=[]
	for i in 2:
		var id: String=["nezha","wenzhong"][i]
		var unit: Dictionary={"id":id,"hero_id":id,"name":Catalog.DATA.heroes[id].name,"title":["西岐先锋","殷商太师"][i],"faction":["player","shang"][i],"cell":[first,second][i],"soldiers":2400,"max_soldiers":2400,"effects":[],"action_done":false,"guarding":false,"morale":50}
		unit.stats=Catalog.canonical_stats(Catalog.profile(unit).stats)
		unit.max_ap=Catalog.movement(unit)
		unit.ap=unit.max_ap
		unit.troops=BattleRules.mixed_roster(int(unit.soldiers))
		units.append(unit)

func faction(unit: Dictionary) -> String:
	return str(unit.get("faction","player"))

func faction_for_unit(id: String) -> String:
	for unit in units:
		if unit.id==id: return faction(unit)
	return "player"

func field_battle_reason(unit: Dictionary,enemy: Dictionary) -> String:
	if not pending_battle.is_empty(): return "交战中"
	if not units.has(unit) or not units.has(enemy) or faction(unit)==faction(enemy): return "请选择敌方部队"
	if int(unit.soldiers)<=0 or int(enemy.soldiers)<=0: return "部队已退场，结束回合后可重新测试"
	if int(unit.ap)<1 or unit.action_done: return "本轮行动已结束"
	if not cells[int(unit.cell)].n.has(int(enemy.cell)) and not cells[int(unit.cell)].n.has(float(enemy.cell)): return "需先行军到敌军相邻陆地"
	return ""

func begin_field_battle(unit: Dictionary,enemy: Dictionary) -> Dictionary:
	if not field_battle_reason(unit,enemy).is_empty(): return {}
	pending_battle={"kind":"field","test_scenario":test_scenario,"unit_id":unit.id,"enemy_unit_id":enemy.id,"origin":int(unit.cell),"enemy_origin":int(enemy.cell),"player":unit.duplicate(true),"enemy":enemy.duplicate(true),"title":"朝歌 · 阵前交锋"}
	return pending_battle.duplicate(true)

func _battle_survivors(result: Dictionary, side: String) -> Array:
	var army: Dictionary = pending_battle[side]
	var original: Array = army.get("troops", BattleRules.roster(int(army.soldiers)))
	var total := int(result[side + "_remaining"])
	if not result.has(side + "_troops"): return BattleRules.resize_roster(original, total)
	var slots: Variant = result[side + "_troops"]
	if not BattleRules.valid_roster(slots, total): return []
	for i in original.size():
		if original[i].get("type") != slots[i].get("type"): return []
		if int(slots[i].get("count",0)) > int(original[i].get("count",0)): return []
	return slots.duplicate(true)

func finish_field_battle(result: Dictionary) -> bool:
	var attacker: Dictionary={}
	var defender: Dictionary={}
	for unit in units:
		if unit.id==pending_battle.unit_id: attacker=unit
		if unit.id==pending_battle.enemy_unit_id: defender=unit
	if attacker.is_empty() or defender.is_empty() or int(attacker.cell)!=pending_battle.origin or int(defender.cell)!=pending_battle.enemy_origin: return false
	for key in ["player_remaining","enemy_remaining","morale","enemy_morale"]:
		var maximum:=100 if key in ["morale","enemy_morale"] else int(pending_battle.player.soldiers if key=="player_remaining" else pending_battle.enemy.soldiers)
		if not Economy.integer(result.get(key),0,maximum): return false
	if not result.get("player_won") is bool or (result.player_won and int(result.player_remaining)<=0): return false
	var rosters := [_battle_survivors(result, "player"), _battle_survivors(result, "enemy")]
	if rosters[0].is_empty() or rosters[1].is_empty(): return false
	for i in 2:
		var unit: Dictionary=[attacker,defender][i]
		unit.soldiers=int(result["player_remaining" if i==0 else "enemy_remaining"])
		unit.troops=rosters[i]
		unit.morale=int(result["morale" if i==0 else "enemy_morale"])
		unit.guarding=false
	attacker.ap=0
	attacker.action_done=true
	pending_battle.clear()
	revision+=1
	return true

func center(id: int) -> Vector2:
	var c: Dictionary = cells[id]
	return radius * Vector2(sqrt(3.0)*(float(c.q)+float(c.r)*0.5),1.5*float(c.r)*grid_y_scale)

func hex_at(p: Vector2) -> Vector2i:
	p.y/=grid_y_scale
	var q := (p.x/sqrt(3.0)-p.y/3.0)/radius
	var r := (p.y*2.0/3.0)/radius
	var s := -q-r
	var a := roundi(q)
	var b := roundi(r)
	var c := roundi(s)
	var delta := Vector3(abs(a-q),abs(b-r),abs(c-s))
	if delta.x > delta.y and delta.x > delta.z: a = -b-c
	elif delta.y > delta.z: b = -a-c
	return Vector2i(a,b)

func cell_at(p: Vector2) -> int:
	return int(by_hex.get(hex_at(p),-1))

func hex_distance(a: int,b: int) -> int:
	var d := Vector2i(int(cells[a].q-cells[b].q),int(cells[a].r-cells[b].r))
	return (abs(d.x)+abs(d.y)+abs(d.x+d.y))/2

func walkable(id: int, faction: String = "player") -> bool:
	if id < 0 or id >= cells.size() or int(cells[id].t) != 0: return false
	var pid: String = cells[id].p
	return pid.is_empty() or by_poi[pid].owner == faction

func occupied(id: int, except_unit: String = "") -> bool:
	for u in units:
		if int(u.cell)==id and u.id != except_unit: return true
	return false

func reason(id: int) -> String:
	if id < 0: return "地图边界"
	if int(cells[id].t)==1: return "水域不可通行 · 请从已占领的渡口过河"
	if int(cells[id].t)==2: return "山脉不可通行 · 沿谷地与关隘行军"
	var pid: String = cells[id].p
	if not pid.is_empty() and by_poi[pid].owner != "player":
		return "%s尚未占领 · 相邻后可占领" % by_poi[pid].name
	if occupied(id): return "我方部队驻扎中"
	return "平原 · 行军消耗 1 点"

func ferry_between(a: int,b: int) -> String:
	for p in pois:
		if p.type=="ferry" and ((int(p.banks[0])==a and int(p.banks[1])==b) or (int(p.banks[1])==a and int(p.banks[0])==b)):
			return p.id
	return ""

func edge_cost(a: int,b: int, unit_id: String = "") -> int:
	var owner:=faction_for_unit(unit_id)
	if not walkable(a,owner) or not walkable(b,owner) or occupied(b,unit_id): return -1
	if cells[a].n.has(float(b)) or cells[a].n.has(b):
		var guards: Array = cells[a].get("g",{}).get(str(b),[])
		for pid in guards:
			if by_poi[pid].owner != owner: return -1
		return 1
	var fid := ferry_between(a,b)
	if not fid.is_empty() and by_poi[fid].owner==owner: return 2
	return -1

func neighbors(a: int, uid: String = "") -> Array:
	var result: Array = []
	for b in cells[a].n:
		if edge_cost(a,int(b),uid)>0: result.append(int(b))
	var pid: String = cells[a].p
	if not pid.is_empty():
		var p: Dictionary = by_poi[pid]
		if p.type=="ferry" and p.owner==faction_for_unit(uid):
			var b: int = int(p.banks[1]) if int(p.banks[0])==a else int(p.banks[0])
			if edge_cost(a,b,uid)>0: result.append(b)
	return result

# Dijkstra is used instead of a geometric A* heuristic: ferry links can be long
# and a straight-line heuristic would overestimate their two-point cost.
func search(start: int, budget: int, uid: String = "", target: int = -1) -> Dictionary:
	var dist: Dictionary = {start:0}
	var prev: Dictionary = {}
	var heap: Array = [[0,start]]
	while not heap.is_empty():
		var entry: Array = heap_pop(heap)
		var cost: int = int(entry[0])
		var current: int = int(entry[1])
		if cost != int(dist.get(current,999999)): continue
		if current==target: break
		for next in neighbors(current,uid):
			var new_cost: int = cost+edge_cost(current,next,uid)
			if new_cost > budget or new_cost >= int(dist.get(next,999999)): continue
			dist[next] = new_cost
			prev[next] = current
			heap_push(heap,[new_cost,next])
	return {"dist":dist,"prev":prev,"start":start}

func route(result: Dictionary, target: int) -> Array[int]:
	var path: Array[int] = []
	if not result.dist.has(target): return path
	var c := target
	while c != int(result.start):
		path.push_front(c)
		c = int(result.prev[c])
	path.push_front(c)
	return path

func can_capture(unit: Dictionary, poi: Dictionary) -> bool:
	if not pending_battle.is_empty() or poi.owner=="player" or int(unit.ap)<1 or int(unit.soldiers)<=0: return false
	var a: int = int(unit.cell)
	for b in poi.cells:
		# Require a real land adjacency. No capture through a river or mountain.
		if cells[a].n.has(b) or cells[a].n.has(int(b)):
			var other_guard := false
			for pid in cells[a].get("g",{}).get(str(int(b)),[]):
				if pid!=poi.id and by_poi[pid].owner!="player": other_guard=true
			if not other_guard: return true
	return false

func capture(unit: Dictionary, poi: Dictionary) -> bool:
	if not can_capture(unit,poi) or poi.owner=="shang": return false
	poi.owner="player"
	unit.ap=int(unit.ap)-1
	revision+=1
	captured+=1
	return true

func garrison(poi: Dictionary) -> Dictionary:
	var count: int = {"city":4200,"pass":2800,"village":1200,"ferry":1500}[poi.type]
	var value: Dictionary=garrisons.get(poi.id,{"soldiers":count,"morale":50}).duplicate(true)
	if not value.has("troops"):
		value.troops = BattleRules.roster(int(value.soldiers)) if garrisons.has(poi.id) else BattleRules.mixed_roster(count)
	value.hero_id=value.get("hero_id","wenzhong")
	value.stats=Catalog.canonical_stats(value.get("stats",Catalog.profile(value).stats))
	value.effects=Catalog.canonical_effects(value.get("effects",[]))
	return value

func begin_battle(unit: Dictionary, poi: Dictionary) -> Dictionary:
	if poi.owner != "shang" or not can_capture(unit,poi): return {}
	var defender := garrison(poi)
	pending_battle = {"unit_id":unit.id,"poi_id":poi.id,"origin":int(unit.cell),"owner":poi.owner,
		"player":unit.duplicate(true),"enemy":{"id":defender.hero_id,"hero_id":defender.hero_id,"name":Catalog.profile(defender).name,"soldiers":defender.soldiers,"troops":defender.troops,"morale":50,"stats":defender.stats,"effects":defender.effects},"title":poi.name+" · 阵前交锋"}
	return pending_battle.duplicate(true)

func finish_battle(result: Dictionary) -> bool:
	if pending_battle.is_empty(): return false
	if pending_battle.get("kind","")=="field": return finish_field_battle(result)
	var unit: Dictionary = {}
	for u in units:
		if u.id == pending_battle.unit_id: unit = u
	var poi: Dictionary = by_poi[pending_battle.poi_id]
	if unit.is_empty() or int(unit.cell) != pending_battle.origin or poi.owner != pending_battle.owner: return false
	for key in ["player_remaining","enemy_remaining","morale","enemy_morale"]:
		var maximum: int = 100 if key in ["morale","enemy_morale"] else int(pending_battle.player.soldiers if key=="player_remaining" else pending_battle.enemy.soldiers)
		if not Economy.integer(result.get(key),0,maximum): return false
	if not result.get("player_won") is bool: return false
	if result.player_won and int(result.player_remaining)<=0: return false
	var player_troops := _battle_survivors(result, "player")
	var enemy_troops := _battle_survivors(result, "enemy")
	if player_troops.is_empty() or enemy_troops.is_empty(): return false
	unit.soldiers = int(result.player_remaining)
	unit.troops = player_troops
	unit.morale = int(result.morale)
	unit.ap = maxi(0,int(unit.ap)-1)
	unit.guarding = false
	if result.player_won:
		poi.owner = "player"
		captured += 1
		garrisons.erase(poi.id)
	else:
		var defender:=garrison(poi)
		defender.soldiers=int(result.enemy_remaining)
		defender.troops=enemy_troops
		defender.morale=int(result.enemy_morale)
		garrisons[poi.id]=defender
	pending_battle.clear()
	revision += 1
	return true

func next_turn() -> void:
	if not pending_battle.is_empty(): return
	economy.next_turn(by_poi)
	turn+=1
	for u in units:
		if test_scenario:
			u.soldiers=int(u.max_soldiers)
			u.troops=BattleRules.mixed_roster(u.soldiers)
		u.effects=u.effects.filter(func(effect: Dictionary)->bool: return int(effect.expires_turn)>turn)
		u.max_ap=Catalog.movement(u)
		u.ap=int(u.max_ap)
		u.morale=50
		u.action_done=false
		u.guarding=false
	for pid in garrisons:
		garrisons[pid].effects=garrisons[pid].get("effects",[]).filter(func(effect: Dictionary)->bool: return int(effect.expires_turn)>turn)
	revision+=1

func map_skill(unit: Dictionary) -> Dictionary:
	return Catalog.skill(unit,"map")

func map_skill_ready_reason(unit: Dictionary) -> String:
	if not pending_battle.is_empty(): return "交战中无法施放地图技能"
	if not units.has(unit): return "请选择我方部队"
	if int(unit.soldiers)<=0: return "部队无可用兵力"
	if unit.get("action_done",false) or int(unit.ap)<=0: return "本轮行动已结束"
	return ""

func map_skill_targets(unit: Dictionary, target: int) -> Dictionary:
	var result: Dictionary={"units":[],"garrisons":[],"cells":[]}
	if target<0 or target>=cells.size(): return result
	var ability:=map_skill(unit)
	var radius_cells:=int(ability.radius)
	result.cells=hex_disk(target,radius_cells)
	if ability.effect in ["heal","buff"]:
		for other in units:
			if faction(other)!=faction(unit): continue
			if hex_distance(int(other.cell),target)<=radius_cells:
				if ability.effect!="heal" or int(other.soldiers)<int(other.max_soldiers): result.units.append(other.id)
	elif ability.effect in ["aoe","debuff"]:
		for other in units:
			if faction(other)!=faction(unit) and int(other.soldiers)>0 and hex_distance(int(other.cell),target)<=radius_cells:
				result.units.append(other.id)
		if test_scenario: return result
		for poi in pois:
			if poi.owner not in ["player","shang"] or poi.owner==faction(unit): continue
			for ci in poi.cells:
				if hex_distance(int(ci),target)<=radius_cells:
					if int(garrison(poi).soldiers)>0: result.garrisons.append(poi.id)
					break
	return result

func hex_disk(target: int, radius_cells: int) -> Array[int]:
	var result: Array[int]=[]
	if target<0 or target>=cells.size(): return result
	# Enumerate the small hex disk, not the entire world grid.
	var hex:=Vector2i(int(cells[target].q),int(cells[target].r))
	for dq in range(-radius_cells,radius_cells+1):
		for dr in range(maxi(-radius_cells,-dq-radius_cells),mini(radius_cells,-dq+radius_cells)+1):
			var id: int=by_hex.get(hex+Vector2i(dq,dr),-1)
			if id>=0: result.append(id)
	return result

func map_skill_reason(unit: Dictionary, target: int) -> String:
	var reason_text:=map_skill_ready_reason(unit)
	if not reason_text.is_empty(): return reason_text
	if target<0 or target>=cells.size(): return "请选择地图上的目标格"
	var ability:=map_skill(unit)
	if ability.effect=="march":
		if target==int(unit.cell): return "请选择新的落点"
		if not search(int(unit.cell),int(ability.march_range),unit.id,target).dist.has(target): return "目标不在合法行军范围内"
		return ""
	if hex_distance(int(unit.cell),target)>int(ability.range): return "超出技能射程"
	var targets:=map_skill_targets(unit,target)
	if targets.units.is_empty() and targets.garrisons.is_empty(): return "范围内没有有效目标"
	return ""

func add_map_effect(unit: Dictionary, ability: Dictionary) -> void:
	var effects: Array=unit.get("effects",[])
	effects=effects.filter(func(effect: Dictionary)->bool: return effect.id!=ability.id)
	effects.append({"id":ability.id,"name":ability.name,"expires_turn":turn+int(ability.duration),"bonuses":ability.bonuses.duplicate(true)})
	unit.effects=effects
	if unit.has("ap"):
		unit.max_ap=Catalog.movement(unit)
		unit.ap=mini(int(unit.ap),int(unit.max_ap))

func _map_aoe_damage(caster: Dictionary, army: Dictionary, ability: Dictionary) -> int:
	var weighted := 0.0
	var strength := 0
	var attacker := Catalog.effective_stats(caster)
	for slot in army.troops:
		if slot.is_empty() or int(slot.count) == 0: continue
		strength += int(slot.count)
		weighted += int(slot.count) * Catalog.damage(attacker, Catalog.effective_stats(army, slot.type), "magic", float(ability.power))
	return mini(int(army.soldiers), roundi(5.0 * weighted / maxi(1, strength)))

func cast_map_skill(unit: Dictionary, target: int) -> Dictionary:
	var reason_text:=map_skill_reason(unit,target)
	if not reason_text.is_empty(): return {"ok":false,"reason":reason_text}
	var ability:=map_skill(unit)
	var targets:=map_skill_targets(unit,target)
	var amount:=0
	match ability.effect:
		"march": unit.cell=target
		"heal","buff":
			for other in units:
				if not other.id in targets.units: continue
				if ability.effect=="heal":
					var healed:=mini(int(ability.heal_soldiers),int(other.max_soldiers)-int(other.soldiers))
					other.soldiers+=healed
					other.troops=BattleRules.resize_roster(other.troops, int(other.soldiers))
					amount+=healed
				else: add_map_effect(other,ability)
		"aoe","debuff":
			for other in units:
				if not other.id in targets.units: continue
				if ability.effect=="aoe":
					var damage:=_map_aoe_damage(unit,other,ability)
					other.soldiers-=damage
					other.troops=BattleRules.resize_roster(other.troops, int(other.soldiers))
					amount+=damage
				else: add_map_effect(other,ability)
			for pid in targets.garrisons:
				var defender:=garrison(by_poi[pid])
				if ability.effect=="aoe":
					var damage:=_map_aoe_damage(unit,defender,ability)
					defender.soldiers-=damage
					defender.troops=BattleRules.resize_roster(defender.troops, int(defender.soldiers))
					amount+=damage
				else: add_map_effect(defender,ability)
				garrisons[pid]=defender
	unit.ap=0
	unit.action_done=true
	unit.guarding=false
	revision+=1
	return {"ok":true,"skill":ability.name,"effect":ability.effect,"amount":amount,"targets":targets}

func recruit_reason(unit: Dictionary, poi: Dictionary) -> String:
	if not pending_battle.is_empty(): return "交战中无法补兵"
	if poi.owner != "player": return "占领后可补充兵员"
	var has_camp: bool = false
	for plot in economy.settlements[poi.id].plots:
		if plot.building == "barracks": has_camp=true
	if not has_camp: return "此地需要建成军营"
	var nearby: bool = false
	var supply_route: Dictionary = search(int(unit.cell),2,unit.id)
	for ci in poi.cells:
		if supply_route.dist.has(int(ci)): nearby=true
	if not nearby: return "部队须在本地两步可通行范围内"
	if int(unit.ap) < 1: return "补兵需要 1 点行动力"
	if int(unit.soldiers) >= int(unit.max_soldiers): return "兵力已满"
	if int(economy.treasury.reserve) < 1 or int(economy.treasury.grain) < 2: return "共享兵员或粮草不足"
	return ""

func recruit(unit: Dictionary, poi: Dictionary) -> int:
	if not recruit_reason(unit,poi).is_empty(): return 0
	var count: int = mini(500,mini(int(unit.max_soldiers)-int(unit.soldiers),mini(int(economy.treasury.reserve),int(economy.treasury.grain)/2)))
	economy.treasury.reserve -= count
	economy.treasury.grain -= count*2
	unit.soldiers = int(unit.soldiers)+count
	unit.troops = BattleRules.resize_roster(unit.troops, int(unit.soldiers), true)
	unit.ap = int(unit.ap)-1
	return count

func save_game(file_path: String = "user://campaign.json") -> Error:
	if not pending_battle.is_empty(): return ERR_BUSY
	var owners: Dictionary={}
	for p in pois: owners[p.id]=p.owner
	var saved_garrisons: Dictionary={}
	for pid in garrisons: saved_garrisons[pid]=garrison(by_poi[pid])
	var save={"schema":7,"grid_revision":data.get("grid_revision",1),"art_revision":data.art_revision,"turn":turn,"captured":captured,"crossed":crossed,"owners":owners,"units":units,"economy":economy.serialize(),"garrisons":saved_garrisons}
	var temp_path: String=file_path+".tmp"
	var f=FileAccess.open(temp_path,FileAccess.WRITE)
	if f==null: return FileAccess.get_open_error()
	f.store_string(JSON.stringify(save,"\t"))
	f.flush()
	var error: Error=f.get_error()
	f.close()
	if error!=OK: return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path),ProjectSettings.globalize_path(file_path))

func load_game(file_path: String = "user://campaign.json") -> bool:
	if not pending_battle.is_empty(): return false
	if not FileAccess.file_exists(file_path): return false
	var saved = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if not saved is Dictionary or not Economy.integer(saved.get("schema"),1,7) or saved.get("art_revision","")!=data.art_revision: return false
	# Older clients must reject new cell indices rather than read them as grid v1.
	if int(saved.schema)>=6 and not saved.has("grid_revision"): return false
	# Validate the complete state before mutating the live campaign.
	if not saved.get("owners",{}) is Dictionary or not saved.get("units",[]) is Array or saved.units.size()!=units.size(): return false
	for p in pois:
		if not saved.owners.get(p.id,"") in ["player","shang","neutral"]: return false
	if not Economy.integer(saved.get("grid_revision",1),1,int(data.grid_revision)): return false
	if int(saved.get("grid_revision",1))!=int(data.grid_revision) and not _migrate_legacy_grid(saved): return false
	for key in ["turn","captured","crossed"]:
		if not Economy.integer(saved.get(key),1 if key=="turn" else 0,1000000000): return false
	var used_cells: Array = []
	var loaded_units: Array=[]
	for i in units.size():
		var u=saved.units[i]
		if not u is Dictionary or u.get("id","")!=units[i].id: return false
		if not Economy.integer(u.get("cell"),0,cells.size()-1): return false
		var ci=int(u.cell)
		if ci in used_cells: return false
		used_cells.append(ci)
		if ci<0 or ci>=cells.size() or cells[ci].t!=0: return false
		if not str(cells[ci].p).is_empty() and saved.owners[cells[ci].p]!="player": return false
		var candidate: Dictionary=units[i].duplicate(true)
		candidate.hero_id=Catalog.hero_id({"id":u.id})
		candidate.stats=Catalog.canonical_stats(Catalog.profile(candidate).stats)
		candidate.effects=[]
		candidate.action_done=false
		if saved.schema>=5:
			if not Catalog.DATA.heroes.has(u.get("hero_id","")) or not Catalog.valid_stats(u.get("stats")): return false
			if not Catalog.valid_effects(u.get("effects"),int(saved.turn)) or not u.get("action_done") is bool: return false
			candidate.hero_id=u.hero_id
			candidate.stats=Catalog.canonical_stats(u.stats)
			candidate.effects=Catalog.canonical_effects(u.effects)
			candidate.action_done=u.action_done
		candidate.max_ap=Catalog.movement(candidate)
		if not Economy.integer(u.get("ap"),0,int(candidate.max_ap)): return false
		if candidate.action_done and int(u.ap)!=0: return false
		if not Economy.integer(u.get("soldiers"),0,int(units[i].max_soldiers)): return false
		if u.has("guarding") and not u.guarding is bool: return false
		if saved.schema >= 4:
			if not Economy.integer(u.get("morale"),0,100): return false
			if not BattleRules.valid_roster(u.get("troops"),int(u.soldiers)): return false
		candidate.cell=ci
		candidate.ap=int(u.ap)
		candidate.soldiers=int(u.soldiers)
		candidate.guarding=bool(u.get("guarding",false))
		candidate.morale=int(u.morale) if saved.schema>=4 else 50
		candidate.troops=u.troops.duplicate(true) if saved.schema>=4 else BattleRules.roster(int(u.soldiers))
		for troop in candidate.troops:
			if not troop.is_empty(): troop.count=int(troop.count)
		loaded_units.append(candidate)
	var loaded_garrisons: Variant = saved.get("garrisons",{}) if saved.schema>=4 else {}
	if not loaded_garrisons is Dictionary: return false
	for pid in loaded_garrisons:
		if not by_poi.has(pid) or saved.owners[pid]!="shang" or not loaded_garrisons[pid] is Dictionary: return false
		if not Economy.integer(loaded_garrisons[pid].get("soldiers"),0,10000) or not Economy.integer(loaded_garrisons[pid].get("morale"),0,100): return false
		if saved.schema >= 7 or loaded_garrisons[pid].has("troops"):
			if not BattleRules.valid_roster(loaded_garrisons[pid].get("troops"), int(loaded_garrisons[pid].soldiers)): return false
			for slot in loaded_garrisons[pid].troops:
				if not slot.is_empty(): slot.count=int(slot.count)
		if saved.schema>=5:
			var defender: Dictionary=loaded_garrisons[pid]
			if not Catalog.DATA.heroes.has(defender.get("hero_id","")) or not Catalog.valid_stats(defender.get("stats")): return false
			if not Catalog.valid_effects(defender.get("effects"),int(saved.turn)): return false
	var loaded_economy: Variant = saved.get("economy",{}) if saved.schema>=2 else Economy.new(pois,theme).serialize()
	if saved.schema==2: loaded_economy=economy.migrate_legacy(loaded_economy,by_poi)
	if not economy.validate(loaded_economy,by_poi): return false
	economy.restore(loaded_economy)
	for p in pois: p.owner=saved.owners[p.id]
	for i in units.size():
		units[i].clear()
		units[i].merge(loaded_units[i],true)
	garrisons=loaded_garrisons.duplicate(true)
	turn=maxi(1,int(saved.get("turn",1)))
	captured=int(saved.get("captured",0))
	crossed=int(saved.get("crossed",0))
	revision+=1
	return true

func _migrate_legacy_grid(saved: Dictionary) -> bool:
	# Old saves store cell indices. Resolve their original artwork coordinates
	# before selecting nearby legal cells in the independently projected grid.
	var legacy: Array
	var legacy_radius:=64.0
	var legacy_y_scale:=1.0
	match int(saved.get("grid_revision",1)):
		1: legacy=JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy_grid_v1.json"))
		2:
			var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy_grid_v2.json"))
			legacy=source.cells
			legacy_radius=float(source.radius)
			legacy_y_scale=float(source.grid_y_scale)
		_: return false
	var used: Array[int]=[]
	var original_cells: Array[int]=[]
	for unit in saved.units:
		if not unit is Dictionary or not Economy.integer(unit.get("cell"),0,legacy.size()-1): return false
		var old_id:=int(unit.cell)
		if old_id in original_cells: return false
		original_cells.append(old_id)
		var old: Array=legacy[old_id]
		if int(old[2])!=0 or (not str(old[3]).is_empty() and saved.owners.get(old[3],"")!="player"): return false
		var position:=legacy_radius*Vector2(sqrt(3.0)*(float(old[0])+float(old[1])*.5),1.5*float(old[1])*legacy_y_scale)
		var best:=-1
		var distance:=pow(radius*3.0,2)
		for ci in cells.size():
			if int(cells[ci].t)!=0 or ci in used: continue
			if not str(cells[ci].p).is_empty() and saved.owners.get(cells[ci].p,"")!="player": continue
			var candidate:=center(ci).distance_squared_to(position)
			if candidate<distance:
				best=ci
				distance=candidate
		if best<0: return false
		unit.cell=best
		used.append(best)
	saved.grid_revision=int(data.grid_revision)
	return true

static func heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var i: int=heap.size()-1
	while i>0:
		var p: int=(i-1)/2
		if int(heap[p][0])<=int(entry[0]): break
		heap[i]=heap[p]
		i=p
	heap[i]=entry

static func heap_pop(heap: Array) -> Array:
	var top: Array=heap[0]
	var last: Array=heap.pop_back()
	if heap.is_empty(): return top
	var i: int=0
	while i*2+1<heap.size():
		var child: int=i*2+1
		if child+1<heap.size() and int(heap[child+1][0])<int(heap[child][0]): child+=1
		if int(last[0])<=int(heap[child][0]): break
		heap[i]=heap[child]
		i=child
	heap[i]=last
	return top
