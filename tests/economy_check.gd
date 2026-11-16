extends SceneTree
const World=preload("res://scripts/world_model.gd")
var checks: int=0
var failures: Array[String]=[]
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
func rich(e) -> void:
	for key in e.KEYS: e.treasury[key]=100000
func write_json(path: String, content: Dictionary) -> void:
	var f=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(content))
func _initialize() -> void:
	var w=World.new()
	var e=w.economy
	var cap: Dictionary=w.by_poi.guanzhong_city_0
	var village: Dictionary=w.by_poi.guanzhong_village_0
	var enemy: Dictionary=w.by_poi.wanluo_city_0
	check(cap.name=="西岐" and cap.owner=="player" and enemy.name=="朝歌" and enemy.owner=="shang","Fengshen western campaign starts correctly")
	check(e.settlements.size()==125,"every city, village, pass and ferry has independent interior state")
	check(e.settlements[cap.id].plots.size()==31 and e.settlements[village.id].plots.size()==12,"settlement footprints differ by type")
	var income: Dictionary=e.income(w.by_poi)
	var sum: Dictionary={}
	for key in e.KEYS: sum[key]=0
	for p in w.pois:
		if p.owner=="player":
			var local: Dictionary=e.local_income(p.id)
			for key in e.KEYS: sum[key]+=local[key]
	check(income==sum,"shared treasury receives all owned settlements, without road or ferry connectivity requirement")
	var snapshot: Dictionary=e.serialize()
	check(not e.build(enemy,5,"farm",w.by_poi).is_empty(),"enemy construction rejected")
	check(not e.demolish(enemy,0),"enemy demolition rejected")
	check(not e.restore_landmark(enemy,"lutai").is_empty(),"enemy landmark repair rejected")
	check(e.serialize()==snapshot,"denied actions cannot mutate shared resources or settlements")
	check(not e.build(village,5,"barracks",w.by_poi).is_empty(),"military buildings require city or pass")
	check(not e.build(cap,6,"alchemy",w.by_poi).is_empty(),"immortal buildings require landmark unlock")
	var wood: int=int(e.treasury.wood)
	var gold: int=int(e.treasury.gold)
	check(e.build(cap,6,"farm",w.by_poi).is_empty(),"construct on empty plot")
	check(int(e.treasury.wood)==wood-100 and int(e.treasury.gold)==gold-120,"all costs deducted exactly once")
	check(not e.build(cap,6,"farm",w.by_poi).is_empty(),"duplicate job on same plot rejected")
	check(e.build(cap,7,"market",w.by_poi).is_empty(),"city permits two simultaneous projects")
	check(not e.build(cap,8,"farm",w.by_poi).is_empty(),"city construction queue limit enforced")
	check(e.build(village,4,"farm",w.by_poi).is_empty(),"another settlement uses shared treasury and own queue")
	check(not e.build(village,5,"lumber",w.by_poi).is_empty(),"village has one construction slot")
	var before: Dictionary=e.treasury.duplicate()
	w.next_turn()
	for key in e.KEYS: check(int(e.treasury[key])==int(before[key])+int(income[key]),"completed buildings do not produce early: "+key)
	check(e.settlements[cap.id].plots[6].level==1 and e.settlements[cap.id].jobs.is_empty(),"one-turn projects complete together")
	check(e.income(w.by_poi).grain>income.grain,"completed farm appears in next-turn forecast")
	var old_detail: Dictionary=e.yield_detail(cap.id,6)
	check(e.build(cap,6,"farm",w.by_poi).is_empty(),"upgrade existing building")
	check(e.yield_detail(cap.id,6)==old_detail,"upgrade retains previous output while under construction")
	w.next_turn()
	check(e.settlements[cap.id].plots[6].level==1 and e.job_at(cap.id,6).remaining==1,"level two takes two turns")
	w.next_turn()
	check(e.settlements[cap.id].plots[6].level==2 and e.yield_detail(cap.id,6).amount==old_detail.amount*2,"level-two output doubles base, with adjacency")
	rich(e)
	check(e.build(cap,6,"farm",w.by_poi).is_empty(),"level-three upgrade starts")
	for i in 3: w.next_turn()
	check(e.settlements[cap.id].plots[6].level==3 and not e.build(cap,6,"farm",w.by_poi).is_empty(),"level three is maximum")
	# Isolated fixture verifies geometry, strongest donor, cap and removal.
	var plots: Array=e.settlements[cap.id].plots
	for p in plots:
		p.building=""
		p.level=0
		p.terrain=3
	plots[0].building="farm"; plots[0].level=1
	plots[1].building="granary"; plots[1].level=1
	plots[2].building="granary"; plots[2].level=2
	var detail: Dictionary=e.yield_detail(cap.id,0)
	check(is_equal_approx(detail.bonus,.35),"same donor type uses strongest adjacent building, not sum")
	plots[3].building="altar"; plots[3].level=3
	check(is_equal_approx(e.yield_detail(cap.id,0).bonus,.6),"different adjacency effects share 60 percent cap")
	plots[2].building=""; plots[2].level=0
	plots[3].building=""; plots[3].level=0
	check(is_equal_approx(e.yield_detail(cap.id,0).bonus,.25),"removing donor immediately recalculates output")
	plots[0].terrain=0
	check(is_equal_approx(e.yield_detail(cap.id,0).bonus,.4),"terrain and adjacency combine")
	# Resume a clean campaign for persisted terrain validation.
	w=World.new(); e=w.economy; cap=w.by_poi.guanzhong_city_0; village=w.by_poi.guanzhong_village_0
	rich(e)
	check(e.restore_landmark(cap,"lingtai").is_empty(),"unique local landmark restoration starts")
	check(not e.restore_landmark(village,"lingtai").is_empty(),"cannot relocate or duplicate unique landmark")
	var base_gold: int=int(e.income(w.by_poi).gold)
	w.next_turn(); w.next_turn()
	check(e.settlements[cap.id].landmarks.lingtai and e.income(w.by_poi).gold==floori(base_gold*1.1),"Ling Tai grants actual faction-wide gold bonus")
	cap.owner="shang"
	check(e.income(w.by_poi).gold==e.local_income(village.id).gold+e.local_income("guanzhong_village_2").gold+e.local_income("guanzhong_ferry_1").gold,"lost landmark stops bonus and lost city's income")
	cap.owner="player"
	check(e.settlements[cap.id].landmarks.lingtai,"recapture preserves physical landmark")
	var qishan: Dictionary=w.by_poi.guanzhong_city_1
	qishan.owner="player"
	check(e.restore_landmark(qishan,"fengshentai").is_empty(),"Fengshen platform starts after occupation")
	for i in 3: w.next_turn()
	check(e.unlocked("immortal",w.by_poi) and e.build(cap,8,"alchemy",w.by_poi).is_empty(),"completed landmark unlocks immortal building across faction")
	check(e.cancel(cap,0),"construction can be cancelled")
	check(e.build(cap,9,"mine",w.by_poi).is_empty(),"new queue after cancellation")
	var remaining: int=int(e.job_at(cap.id,9).remaining)
	var reserved_gold: int=int(e.treasury.gold)
	cap.owner="shang"
	w.next_turn()
	check(e.job_at(cap.id,9).remaining==remaining,"captured-away jobs pause, preventing enemy spending player resources")
	check(not e.cancel(cap,0),"cannot cancel job after ownership loss")
	cap.owner="player"
	var gold_before_cancel: int=int(e.treasury.gold)
	check(e.cancel(cap,0) and e.treasury.gold==gold_before_cancel+90,"cancellation refunds exactly half of original cost")
	var old: Dictionary=e.treasury.duplicate()
	e.treasury.wood=0
	check(not e.build(cap,10,"mine",w.by_poi).is_empty() and e.treasury.gold==old.gold,"insufficient cost is atomic")
	e.treasury=old
	# Recruitment consumes shared reserves but requires local army presence.
	var u: Dictionary=w.units[0]
	u.cell=int(cap.cells[0]); u.ap=6
	var soldiers: int=int(u.soldiers)
	var grain: int=int(e.treasury.grain)
	check(w.recruit(u,cap)==500 and int(u.soldiers)==soldiers+500 and int(e.treasury.grain)==grain-1000 and u.ap==5,"recruitment consumes exact reserves, grain and AP")
	u.cell=int(w.by_poi.wuyue_city_0.cells[0])
	check(w.recruit(u,cap)==0,"global resources do not allow remote reinforcement")
	u.cell=int(cap.cells[0])
	# Save pending construction, ownership, landmark, resources and troops together.
	check(e.build(cap,6,"farm",w.by_poi).is_empty(),"queue persists fixture")
	var path: String="user://economy-test.json"
	check(w.save_game(path)==OK,"schema two save writes")
	var good: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	w.next_turn(); e.treasury.gold=0; cap.owner="shang"
	check(w.load_game(path),"schema two complete state restores")
	check(e.treasury.gold==good.economy.treasury.gold and cap.owner=="player" and e.job_at(cap.id,6).remaining==1 and u.soldiers==good.units[0].soldiers,"roundtrip includes pending jobs, shared pool, ownership, troops")
	var bad_cases: Array=[]
	var bad: Dictionary=good.duplicate(true); bad.economy.treasury.gold=-1; bad_cases.append(bad)
	bad=good.duplicate(true); bad.economy.settlements[cap.id].jobs[0].cost.gold=99999; bad_cases.append(bad)
	bad=good.duplicate(true); bad.economy.settlements[cap.id].jobs[0].remaining=0; bad_cases.append(bad)
	bad=good.duplicate(true); bad.economy.settlements[cap.id].jobs.append(bad.economy.settlements[cap.id].jobs[0].duplicate()); bad_cases.append(bad)
	bad=good.duplicate(true); bad.economy.settlements[cap.id].plots[0].level=4; bad_cases.append(bad)
	bad=good.duplicate(true); bad.economy.settlements[cap.id].plots[0].terrain=99; bad_cases.append(bad)
	bad=good.duplicate(true); bad.units[0].ap="six"; bad_cases.append(bad)
	bad=good.duplicate(true); bad.units[1].cell=bad.units[0].cell; bad_cases.append(bad)
	bad=good.duplicate(true); bad.owners[cap.id]="invalid"; bad_cases.append(bad)
	bad=good.duplicate(true); bad.turn="tomorrow"; bad_cases.append(bad)
	bad=good.duplicate(true); bad.economy="invalid"; bad_cases.append(bad)
	for i in bad_cases.size():
		var before_invalid: String=JSON.stringify(e.serialize())
		var turn_before: int=w.turn
		write_json(path,bad_cases[i])
		check(not w.load_game(path),"reject malformed save %d" % i)
		check(JSON.stringify(e.serialize())==before_invalid and w.turn==turn_before and cap.owner=="player","invalid load cannot partially mutate live campaign %d" % i)
	var legacy: Dictionary=good.duplicate(true); legacy.schema=1; legacy.erase("economy")
	write_json(path,legacy)
	check(w.load_game(path) and e.settlements.size()==125 and e.treasury.gold==3600,"schema one navigation saves migrate with starter economy")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var report: Dictionary={"engine":Engine.get_version_info().string,"checks":checks,"failures":failures}
	write_json("res://previews/economy-tests.json",report)
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
