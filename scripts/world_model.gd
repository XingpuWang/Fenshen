class_name ShanheWorld
extends RefCounted

const DIRECTIONS = [Vector2i(1,0),Vector2i(1,-1),Vector2i(0,-1),Vector2i(-1,0),Vector2i(-1,1),Vector2i(0,1)]
const Economy = preload("res://scripts/settlement_economy.gd")
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
var bounds := Rect2(-3584,-3584,11264,11264)
var turn: int = 1
var revision: int = 0
var captured: int = 0
var crossed: int = 0

func _init(setup_campaign: bool = true) -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
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
		u.ap = int(u.max_ap)
		u.guarding = false
		u.max_soldiers = int(u.soldiers)+800
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

func center(id: int) -> Vector2:
	var c: Dictionary = cells[id]
	return radius * Vector2(sqrt(3.0)*(float(c.q)+float(c.r)*0.5),1.5*float(c.r))

func hex_at(p: Vector2) -> Vector2i:
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
	if not walkable(a) or not walkable(b) or occupied(b,unit_id): return -1
	if cells[a].n.has(float(b)) or cells[a].n.has(b):
		var guards: Array = cells[a].get("g",{}).get(str(b),[])
		for pid in guards:
			if by_poi[pid].owner != "player": return -1
		return 1
	var fid := ferry_between(a,b)
	if not fid.is_empty() and by_poi[fid].owner=="player": return 2
	return -1

func neighbors(a: int, uid: String = "") -> Array:
	var result: Array = []
	for b in cells[a].n:
		if edge_cost(a,int(b),uid)>0: result.append(int(b))
	var pid: String = cells[a].p
	if not pid.is_empty():
		var p: Dictionary = by_poi[pid]
		if p.type=="ferry" and p.owner=="player":
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
	if poi.owner=="player" or int(unit.ap)<1: return false
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
	if not can_capture(unit,poi): return false
	poi.owner="player"
	unit.ap=int(unit.ap)-1
	revision+=1
	captured+=1
	return true

func next_turn() -> void:
	economy.next_turn(by_poi)
	turn+=1
	for u in units:
		u.ap=int(u.max_ap)
		u.guarding=false
	revision+=1

func recruit_reason(unit: Dictionary, poi: Dictionary) -> String:
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
	unit.ap = int(unit.ap)-1
	return count

func save_game(file_path: String = "user://campaign.json") -> Error:
	var owners: Dictionary={}
	for p in pois: owners[p.id]=p.owner
	var save={"schema":2,"art_revision":data.art_revision,"turn":turn,"captured":captured,"crossed":crossed,"owners":owners,"units":units,"economy":economy.serialize()}
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
	if not FileAccess.file_exists(file_path): return false
	var saved = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if not saved is Dictionary or (saved.get("schema",0)!=1 and saved.get("schema",0)!=2) or saved.get("art_revision","")!=data.art_revision: return false
	# Validate the complete state before mutating the live campaign.
	if not saved.get("owners",{}) is Dictionary or not saved.get("units",[]) is Array or saved.units.size()!=units.size(): return false
	for p in pois:
		if not saved.owners.get(p.id,"") in ["player","shang","neutral"]: return false
	for key in ["turn","captured","crossed"]:
		if not Economy.integer(saved.get(key),1 if key=="turn" else 0,1000000000): return false
	var used_cells: Array = []
	for i in units.size():
		var u=saved.units[i]
		if not u is Dictionary or u.get("id","")!=units[i].id: return false
		if not Economy.integer(u.get("cell"),0,cells.size()-1): return false
		var ci=int(u.cell)
		if ci in used_cells: return false
		used_cells.append(ci)
		if ci<0 or ci>=cells.size() or cells[ci].t!=0: return false
		if not str(cells[ci].p).is_empty() and saved.owners[cells[ci].p]!="player": return false
		if not Economy.integer(u.get("ap"),0,int(units[i].max_ap)): return false
		if not Economy.integer(u.get("soldiers"),0,int(units[i].max_soldiers)): return false
		if u.has("guarding") and not u.guarding is bool: return false
	var loaded_economy: Variant = saved.get("economy",{}) if saved.schema==2 else Economy.new(pois,theme).serialize()
	if not economy.validate(loaded_economy,by_poi): return false
	economy.restore(loaded_economy)
	for p in pois: p.owner=saved.owners[p.id]
	for i in units.size():
		units[i].cell=int(saved.units[i].cell)
		units[i].ap=int(saved.units[i].ap)
		units[i].soldiers=int(saved.units[i].soldiers)
		units[i].guarding=bool(saved.units[i].get("guarding",false))
	turn=maxi(1,int(saved.get("turn",1)))
	captured=int(saved.get("captured",0))
	crossed=int(saved.get("crossed",0))
	revision+=1
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
