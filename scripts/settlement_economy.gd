class_name SettlementEconomy
extends RefCounted

const KEYS = ["grain", "wood", "iron", "jade", "gold", "reserve"]
const NAMES = {"grain":"粮草", "wood":"木材", "iron":"金铁", "jade":"玉石", "gold":"钱帛", "reserve":"兵员"}
const TERRAIN = ["沃土", "林地", "矿脉", "平地", "灵地"]
var treasury: Dictionary = {"grain":6000, "wood":2400, "iron":1200, "jade":450, "gold":3600, "reserve":600}
var prestige: int = 120
var settlements: Dictionary = {}
var definitions: Dictionary = {}
var catalog: Array = []
var landmarks: Dictionary = {}
var last_report: Dictionary = {}
var large_cities: Array = []

func layout_kind(poi: Dictionary) -> String:
	if poi.type == "city": return "city_large" if poi.id in large_cities else "city_small"
	return poi.type

func plot_count(poi: Dictionary) -> int:
	return {"city_large":31,"city_small":19,"village":12,"pass":10,"ferry":7}[layout_kind(poi)]

func _init(pois: Array = [], theme: Dictionary = {}) -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))
	for d in catalog: definitions[d.id] = d
	landmarks = theme.get("landmarks", {})
	large_cities = theme.get("large_cities", [])
	for p in pois:
		var plots: Array = []
		var coords: Array = [Vector2i.ZERO]
		for radius in [1, 2, 3]:
			for r in range(-radius, radius+1):
				for q in range(-radius, radius+1):
					if maxi(abs(q), maxi(abs(r), abs(q+r))) == radius: coords.append(Vector2i(q,r))
		var count: int = plot_count(p)
		for i in count:
			plots.append({"q":coords[i].x,"r":coords[i].y,"terrain":(i+int(str(p.id).hash()%5))%5,"building":"","level":0})
		var marks: Dictionary = {}
		for key in landmarks:
			if landmarks[key].poi == p.id: marks[key] = false
		settlements[p.id] = {"plots":plots, "jobs":[], "landmarks":marks}
		# Conquered settlements keep their existing physical buildings.
		var initial: Array = {"city":["market","homes","farm"],"village":["farm","lumber"],"pass":["barracks","drill"],"ferry":["market"]}[p.type]
		for i in initial.size():
			plots[i].building = initial[i]
			plots[i].level = 1
	if settlements.has("guanzhong_city_0"):
		var plots: Array = settlements.guanzhong_city_0.plots
		for pair in [[0,"granary"],[1,"farm"],[2,"farm"],[3,"homes"],[4,"market"],[5,"barracks"]]:
			plots[pair[0]].building = pair[1]
			plots[pair[0]].level = 1

func queue_limit(poi: Dictionary) -> int:
	return 2 if poi.type == "city" else 1

func adjacent(a: Dictionary, b: Dictionary) -> bool:
	var q: int = int(a.q)-int(b.q)
	var r: int = int(a.r)-int(b.r)
	return maxi(abs(q),maxi(abs(r),abs(q+r))) == 1

func job_at(pid: String, index: int) -> Dictionary:
	for job in settlements[pid].jobs:
		if int(job.plot) == index: return job
	return {}

func unlocked(tag: String, pois: Dictionary) -> bool:
	if tag.is_empty(): return true
	for id in landmarks:
		var d: Dictionary = landmarks[id]
		if d.unlock == tag and pois[d.poi].owner == "player" and settlements[d.poi].landmarks[id]: return true
	return false

func cost_for(id: String, target: int = 1) -> Dictionary:
	var out: Dictionary = {}
	for key in definitions[id].cost: out[key] = int(definitions[id].cost[key])*target
	return out

func can_pay(cost: Dictionary) -> bool:
	for key in cost:
		if int(treasury[key]) < int(cost[key]): return false
	return true

func pay(cost: Dictionary) -> void:
	for key in cost: treasury[key] = int(treasury[key])-int(cost[key])

func build_reason(poi: Dictionary, index: int, id: String, pois: Dictionary) -> String:
	if poi.owner != "player": return "占领此地后方可建设"
	if not definitions.has(id) or index < 0 or index >= settlements[poi.id].plots.size(): return "请选择有效地块与建筑"
	var plot: Dictionary = settlements[poi.id].plots[index]
	if not plot.building.is_empty() and plot.building != id: return "此地已有建筑"
	if int(plot.level) >= 3: return "已达最高三级"
	if not job_at(poi.id,index).is_empty(): return "此地正在施工"
	if settlements[poi.id].jobs.size() >= queue_limit(poi): return "本地工匠已全部开工"
	var d: Dictionary = definitions[id]
	if not poi.type in d.types: return "此类据点不可建造该建筑"
	if not unlocked(d.unlock,pois): return "修复封神台或金光洞后解锁"
	if not can_pay(cost_for(id,int(plot.level)+1)): return "共享资源不足"
	return ""

func build(poi: Dictionary, index: int, id: String, pois: Dictionary) -> String:
	var reason: String = build_reason(poi,index,id,pois)
	if not reason.is_empty(): return reason
	var target: int = int(settlements[poi.id].plots[index].level)+1
	var cost: Dictionary = cost_for(id,target)
	pay(cost)
	settlements[poi.id].jobs.append({"plot":index,"building":id,"target":target,"remaining":target,"cost":cost,"landmark":""})
	return ""

func landmark_reason(poi: Dictionary, id: String) -> String:
	if poi.owner != "player": return "占领此地后方可修复"
	if not landmarks.has(id) or landmarks[id].poi != poi.id: return "地标不属于此地"
	if settlements[poi.id].landmarks[id]: return "地标已修复"
	for job in settlements[poi.id].jobs:
		if job.landmark == id: return "地标正在修复"
	if settlements[poi.id].jobs.size() >= queue_limit(poi): return "本地工匠已全部开工"
	if not can_pay(landmarks[id].cost): return "共享资源不足"
	return ""

func restore_landmark(poi: Dictionary, id: String) -> String:
	var reason: String = landmark_reason(poi,id)
	if not reason.is_empty(): return reason
	var d: Dictionary = landmarks[id]
	pay(d.cost)
	settlements[poi.id].jobs.append({"plot":-1,"building":"","target":1,"remaining":int(d.turns),"cost":d.cost.duplicate(),"landmark":id})
	return ""

func cancel(poi: Dictionary, job_index: int) -> bool:
	var jobs: Array = settlements[poi.id].jobs
	if poi.owner != "player" or job_index < 0 or job_index >= jobs.size(): return false
	for key in jobs[job_index].cost: treasury[key] = int(treasury[key])+int(jobs[job_index].cost[key])/2
	jobs.remove_at(job_index)
	return true

func demolish(poi: Dictionary, index: int) -> bool:
	if poi.owner != "player" or index < 0 or index >= settlements[poi.id].plots.size() or not job_at(poi.id,index).is_empty(): return false
	settlements[poi.id].plots[index].building = ""
	settlements[poi.id].plots[index].level = 0
	return true

func yield_detail(pid: String, index: int, preview: String = "", preview_level: int = 1) -> Dictionary:
	var plots: Array = settlements[pid].plots
	var plot: Dictionary = plots[index]
	var id: String = plot.building if preview.is_empty() else preview
	var level: int = int(plot.level) if preview.is_empty() else preview_level
	if id.is_empty(): return {"amount":0,"base":0,"bonus":0.0,"sources":[],"resource":""}
	var d: Dictionary = definitions[id]
	var bonus: float = 0.0
	var sources: Array = []
	var terrain: int = int(plot.terrain)
	if (id=="farm" and terrain==0) or (id=="lumber" and terrain==1) or (id=="mine" and terrain==2) or (id=="jade" and terrain==4):
		bonus += .15
		sources.append(TERRAIN[terrain]+" +15%")
	var donors: Dictionary = {}
	for other in plots:
		if other.building.is_empty() or not adjacent(plot,other): continue
		var buffs: Dictionary = definitions[other.building].buffs
		var buff: float = float(buffs.get(id,buffs.get("*",0.0)))
		if buff > 0: donors[other.building] = maxf(float(donors.get(other.building,0.0)),buff+.1*(int(other.level)-1))
	for donor in donors:
		bonus += float(donors[donor])
		sources.append(definitions[donor].name+" +%d%%" % roundi(float(donors[donor])*100))
	bonus = minf(.6,bonus)
	var base: int = int(d.base)*level
	return {"amount":floori(base*(1.0+bonus)),"base":base,"bonus":bonus,"sources":sources,"resource":d.resource}

func local_income(pid: String) -> Dictionary:
	var result: Dictionary = {}
	for key in KEYS: result[key] = 0
	for i in settlements[pid].plots.size():
		var detail: Dictionary = yield_detail(pid,i)
		if not detail.resource.is_empty(): result[detail.resource] += int(detail.amount)
	return result

func income(pois: Dictionary) -> Dictionary:
	var total: Dictionary = {}
	for key in KEYS: total[key] = 0
	for pid in settlements:
		if pois[pid].owner != "player": continue
		var local: Dictionary = local_income(pid)
		for key in KEYS: total[key] += int(local[key])
	var bonuses: Dictionary = {}
	for id in landmarks:
		var d: Dictionary = landmarks[id]
		if pois[d.poi].owner == "player" and settlements[d.poi].landmarks[id] and d.resource != "prestige":
			bonuses[d.resource] = float(bonuses.get(d.resource,0.0))+float(d.bonus)
	for key in bonuses: total[key] = floori(int(total[key])*(1.0+minf(.6,float(bonuses[key]))))
	return total

func next_turn(pois: Dictionary) -> Dictionary:
	# Snapshot output BEFORE completion; new buildings first produce next turn.
	var gain: Dictionary = income(pois)
	for key in KEYS: treasury[key] = int(treasury[key])+int(gain[key])
	for id in landmarks:
		var d: Dictionary = landmarks[id]
		if d.resource == "prestige" and pois[d.poi].owner == "player" and settlements[d.poi].landmarks[id]: prestige += int(d.bonus)
	var completed: Array = []
	for pid in settlements:
		if pois[pid].owner != "player": continue
		var s: Dictionary = settlements[pid]
		for i in range(s.jobs.size()-1,-1,-1):
			var job: Dictionary = s.jobs[i]
			job.remaining = int(job.remaining)-1
			if int(job.remaining) > 0: continue
			if job.landmark.is_empty():
				s.plots[int(job.plot)].building = job.building
				s.plots[int(job.plot)].level = int(job.target)
				completed.append(pois[pid].name+"·"+definitions[job.building].name)
			else:
				s.landmarks[job.landmark] = true
				completed.append(pois[pid].name+"·"+landmarks[job.landmark].name)
			s.jobs.remove_at(i)
	last_report = {"income":gain,"completed":completed}
	return last_report

func serialize() -> Dictionary:
	return {"treasury":treasury.duplicate(true),"prestige":prestige,"settlements":settlements.duplicate(true)}

# Schema 2 had nineteen plots in every city. Keep their indices, buildings,
# terrain and construction jobs intact; only large cities gain new empty land.
func migrate_legacy(saved: Variant, pois: Dictionary) -> Variant:
	if not saved is Dictionary or not saved.get("settlements") is Dictionary: return saved
	var migrated: Dictionary = saved.duplicate(true)
	for pid in settlements:
		var state: Variant = migrated.settlements.get(pid)
		if not state is Dictionary or not state.get("plots") is Array: continue
		if pois[pid].type == "city" and state.plots.size() == 19:
			for i in range(19, settlements[pid].plots.size()):
				var plot: Dictionary=settlements[pid].plots[i].duplicate(true)
				plot.building=""
				plot.level=0
				state.plots.append(plot)
	return migrated

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and float(value)>=low and float(value)<=high

func validate(saved: Variant, pois: Dictionary) -> bool:
	if not saved is Dictionary or not saved.get("treasury") is Dictionary or not saved.get("settlements") is Dictionary: return false
	for key in KEYS:
		if not integer(saved.treasury.get(key),0,1000000000): return false
	if not integer(saved.get("prestige"),0,1000000000) or saved.settlements.size()!=settlements.size(): return false
	for pid in settlements:
		var s: Variant = saved.settlements.get(pid)
		if not s is Dictionary or not s.get("plots") is Array or not s.get("jobs") is Array or not s.get("landmarks") is Dictionary: return false
		var original: Dictionary = settlements[pid]
		if s.plots.size()!=original.plots.size() or s.jobs.size()>queue_limit(pois[pid]) or s.landmarks.size()!=original.landmarks.size(): return false
		for i in s.plots.size():
			var p: Variant = s.plots[i]
			if not p is Dictionary or p.get("q")!=original.plots[i].q or p.get("r")!=original.plots[i].r or p.get("terrain")!=original.plots[i].terrain: return false
			if not p.get("building") is String or not integer(p.get("level"),0,3): return false
			if p.building.is_empty():
				if int(p.level)!=0: return false
			elif not definitions.has(p.building) or int(p.level)<1 or not pois[pid].type in definitions[p.building].types: return false
		for key in original.landmarks:
			if not s.landmarks.get(key) is bool: return false
		var seen: Array = []
		for job in s.jobs:
			if not job is Dictionary or not integer(job.get("plot"),-1,s.plots.size()-1) or not integer(job.get("target"),1,3) or not integer(job.get("remaining"),1,3): return false
			if not job.get("building") is String or not job.get("landmark") is String or not job.get("cost") is Dictionary: return false
			var token: String = str(job.plot) if job.landmark.is_empty() else job.landmark
			if token in seen: return false
			seen.append(token)
			var expected: Dictionary
			if job.landmark.is_empty():
				if int(job.plot)<0 or not definitions.has(job.building): return false
				var p: Dictionary = s.plots[int(job.plot)]
				if int(job.target)!=int(p.level)+1 or (not p.building.is_empty() and p.building!=job.building) or not pois[pid].type in definitions[job.building].types or int(job.remaining)>int(job.target): return false
				expected=cost_for(job.building,int(job.target))
			else:
				if not original.landmarks.has(job.landmark) or s.landmarks[job.landmark] or int(job.plot)!=-1 or not job.building.is_empty() or int(job.target)!=1 or int(job.remaining)>int(landmarks[job.landmark].turns): return false
				expected=landmarks[job.landmark].cost
			if job.cost.size()!=expected.size(): return false
			for key in expected:
				if job.cost.get(key)!=expected[key]: return false
	return true

func restore(saved: Dictionary) -> void:
	treasury=saved.treasury.duplicate(true)
	prestige=int(saved.prestige)
	settlements=saved.settlements.duplicate(true)
	last_report={}
