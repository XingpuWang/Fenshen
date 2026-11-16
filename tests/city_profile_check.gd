extends SceneTree

const World=preload("res://scripts/world_model.gd")
var checks: int=0
var failures: Array[String]=[]
var save_path: String="/tmp/fenshen-city-profile-test.json"

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)

func write_save(value: Dictionary) -> void:
	FileAccess.open(save_path,FileAccess.WRITE).store_string(JSON.stringify(value))

func _initialize() -> void:
	var w=World.new()
	var econ=w.economy
	var counts: Dictionary={"city_large":0,"city_small":0,"village":0,"pass":0,"ferry":0}
	var layouts: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/interior_layouts.json"))
	for p in w.pois:
		var kind: String=econ.layout_kind(p)
		counts[kind]+=1
		var expected: int={"city_large":31,"city_small":19,"village":12,"pass":10,"ferry":7}[kind]
		check(econ.settlements[p.id].plots.size()==expected,"capacity: "+p.id)
		check(layouts[kind].sites.size()==expected,"every plot has a landscape position: "+p.id)
	check(counts=={"city_large":9,"city_small":31,"village":33,"pass":27,"ferry":25},"nine regional capitals are large; 31 other cities are small")
	for kind in layouts:
		var sites: Array=layouts[kind].sites
		for i in sites.size():
			var a:=Vector2(sites[i][0],sites[i][1])
			check(a.x>.08 and a.x<.91 and a.y>.12 and a.y<.9,"site within usable landscape: "+kind)
			for j in i:
				var b:=Vector2(sites[j][0],sites[j][1])
				check(a.distance_to(b)>.04,"distinct nonoverlapping site anchors: "+kind)
	var cap: Dictionary=w.by_poi.guanzhong_city_0
	check(econ.build(cap,30,"farm",w.by_poi).is_empty(),"large city's added plot is buildable")
	w.next_turn()
	check(econ.settlements[cap.id].plots[30].level==1,"added plot completes and produces")
	check(w.save_game(save_path)==OK,"current schema saves expanded capacity")
	var fresh=World.new()
	check(fresh.load_game(save_path) and fresh.economy.settlements[cap.id].plots[30].building=="farm","current schema restores extra plot")
	# Construct an actual schema 2 fixture with an in-progress job and 19 city plots.
	w=World.new(); econ=w.economy; cap=w.by_poi.guanzhong_city_0
	check(econ.build(cap,6,"farm",w.by_poi).is_empty(),"legacy fixture construction")
	w.save_game(save_path)
	var legacy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	legacy.schema=2
	for p in w.pois:
		if p.type=="city": legacy.economy.settlements[p.id].plots=legacy.economy.settlements[p.id].plots.slice(0,19)
	write_save(legacy)
	check(econ.build(cap,30,"farm",w.by_poi).is_empty(),"prepare live new-land building before loading an old save")
	w.next_turn()
	check(econ.settlements[cap.id].plots[30].level==1,"live extra plot is occupied before migration")
	check(w.load_game(save_path),"schema 2 is migrated")
	check(econ.settlements[cap.id].plots.size()==31,"legacy capital expands")
	check(econ.settlements[cap.id].plots.slice(0,19)==legacy.economy.settlements[cap.id].plots,"all original plot IDs and terrain preserved")
	check(econ.settlements[cap.id].jobs==legacy.economy.settlements[cap.id].jobs,"legacy construction queue preserved")
	check(econ.treasury==legacy.economy.treasury,"migration does not charge resources")
	for i in range(19,31): check(econ.settlements[cap.id].plots[i].building.is_empty(),"new land is empty")
	var before: String=JSON.stringify(econ.serialize())
	var malformed: Dictionary=legacy.duplicate(true)
	malformed.schema=3
	write_save(malformed)
	check(not w.load_game(save_path),"truncated schema 3 rejected instead of silently expanded")
	check(JSON.stringify(econ.serialize())==before,"invalid load is atomic")
	malformed=legacy.duplicate(true)
	malformed.economy.settlements[cap.id].plots[3].q=1000
	write_save(malformed)
	check(not w.load_game(save_path),"migration does not bypass terrain validation")
	check(JSON.stringify(econ.serialize())==before,"invalid legacy load is atomic")
	DirAccess.remove_absolute(save_path)
	DirAccess.make_dir_recursive_absolute("res://previews/warm-settlements")
	var report: Dictionary={"checks":checks,"failures":failures,"settlement_counts":counts}
	FileAccess.open("res://previews/warm-settlements/city-profile-tests.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
