extends SceneTree
const World=preload("res://scripts/world_model.gd")
const Tactics=preload("res://scripts/map_tactics.gd")
var checks:=0
var failures: Array[String]=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)

func store_save(path: String,value: Dictionary) -> void:
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(value))

func _initialize() -> void:
	var world:=World.new(false)
	check(is_equal_approx(world.grid_y_scale,cos(PI/4)),"grid alone uses a 45 degree projection")
	check(is_equal_approx(world.radius,80.0),"hex radius is 25 percent larger than the previous 64-unit grid")
	# Shared edges must meet exactly, including across the nine map regions.
	for ci in range(0,world.cells.size(),47):
		var cell: Dictionary=world.cells[ci]
		var points:=Tactics.hexagon(world,world.center(ci),world.radius)
		for edge in 6:
			var direction: Vector2i=world.DIRECTIONS[(6-edge)%6]
			var next: int=world.by_hex.get(Vector2i(int(cell.q),int(cell.r))+direction,-1)
			if next<0: continue
			var neighbor:=Tactics.hexagon(world,world.center(next),world.radius)
			for vertex in [points[edge],points[(edge+1)%6]]:
				var match_found:=false
				for other in neighbor:
					if vertex.distance_to(other)<.01: match_found=true; break
				check(match_found,"projected neighboring hexagons share their border")
	for poi in world.pois:
		if poi.type=="ferry": continue
		var position:=Vector2(poi.position[0],poi.position[1])
		var half:=Vector2(poi.half_size[0],poi.half_size[1])
		for ci in poi.cells:
			check(Rect2(position-half,half*2).grow(.01).has_point(world.center(int(ci))),"settlement footprint remains on the original painting: "+poi.id)
	var path:="user://grid-projection-test.json"
	var capital: Dictionary=world.by_poi.wanluo_city_0
	check(world.economy.build(capital,6,"farm",world.by_poi).is_empty(),"legacy fixture includes paid construction in progress")
	check(world.save_game(path)==OK,"new grid save succeeds")
	var current: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(current.schema==6 and current.grid_revision==3,"new saves identify the enlarged grid and reject loading in old clients")
	var cells: Array=[]
	for unit in world.units: cells.append(int(unit.cell))
	check(world.load_game(path),"new grid save reloads")
	for i in 3: check(int(world.units[i].cell)==cells[i],"new grid round trip preserves exact cell indices")
	var old_cells: Array[int]=[5328,7356,4417]
	var old_positions: Array[Vector2]=[Vector2(2050.7481561615505,1440),Vector2(1829.0456527927342,3360),Vector2(2327.876285372571,576)]
	var legacy:=current.duplicate(true)
	legacy.schema=5
	legacy.erase("grid_revision")
	for i in 3: legacy.units[i].cell=old_cells[i]
	for schema in [1,2,3,4,5]:
		var fixture:=legacy.duplicate(true)
		fixture.schema=schema
		if schema==2:
			for poi in world.pois:
				if poi.type=="city": fixture.economy.settlements[poi.id].plots=fixture.economy.settlements[poi.id].plots.slice(0,19)
		store_save(path,fixture)
		check(world.load_game(path),"schema %d legacy grid migrates" % schema)
		for i in 3:
			check(world.center(int(world.units[i].cell)).distance_to(old_positions[i])<=world.radius*3,"legacy unit stays near its original map location")
			check(world.units[i].soldiers==fixture.units[i].soldiers,"legacy migration preserves troop strength")
		check(world.units[0].cell!=world.units[1].cell and world.units[1].cell!=world.units[2].cell,"legacy migration keeps armies on distinct cells")
		if schema>=2:
			check(world.economy.treasury==fixture.economy.treasury,"grid migration preserves paid resources")
			check(world.economy.settlements[capital.id].jobs==fixture.economy.settlements[capital.id].jobs,"grid migration preserves pending construction")
	# The immediately preceding release already had tilted cells, with radius 64.
	var previous:=current.duplicate(true)
	previous.grid_revision=2
	var previous_cells: Array[int]=[7562,10300,6143]
	var previous_positions: Array[Vector2]=[Vector2(2106.1737820037547,1493.4095218659884),Vector2(1829.0456527927342,3326.2302987015196),Vector2(2327.876285372571,543.0580079512686)]
	for i in 3: previous.units[i].cell=previous_cells[i]
	store_save(path,previous)
	check(world.load_game(path),"schema 6 grid v2 migrates into the larger grid")
	for i in 3:
		check(world.center(int(world.units[i].cell)).distance_to(previous_positions[i])<=world.radius*3,"grid v2 migration retains the original location")
		check(world.units[i].soldiers==previous.units[i].soldiers,"grid v2 migration retains soldier strength")
	check(world.economy.treasury==previous.economy.treasury and world.economy.settlements[capital.id].jobs==previous.economy.settlements[capital.id].jobs,"grid v2 migration preserves resources and construction")
	check(world.save_game(path)==OK,"migrated grid v2 campaign can be saved")
	var migrated_cells: Array=[]
	for unit in world.units: migrated_cells.append(int(unit.cell))
	check(world.load_game(path),"migrated campaign reloads on the current grid")
	for i in 3: check(int(world.units[i].cell)==migrated_cells[i],"resaving a migrated campaign does not move the army again")
	var snapshot:=JSON.stringify([world.units,world.economy.serialize(),world.turn])
	var bad: Array[Dictionary]=[]
	var duplicate:=legacy.duplicate(true)
	duplicate.units[1].cell=duplicate.units[0].cell
	bad.append(duplicate)
	var outside:=legacy.duplicate(true)
	outside.units[0].cell=999999
	bad.append(outside)
	var unknown:=current.duplicate(true)
	unknown.grid_revision=4
	bad.append(unknown)
	var missing:=current.duplicate(true)
	missing.erase("grid_revision")
	bad.append(missing)
	var old_grid: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/legacy_grid_v1.json"))
	var water:=legacy.duplicate(true)
	for i in old_grid.size():
		if int(old_grid[i][2])==1: water.units[0].cell=i; break
	bad.append(water)
	for fixture in bad:
		store_save(path,fixture)
		check(not world.load_game(path),"invalid grid save is rejected")
		check(JSON.stringify([world.units,world.economy.serialize(),world.turn])==snapshot,"failed migration leaves the live campaign unchanged")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var report:={"checks":checks,"failures":failures,"cells":world.cells.size(),"radius":world.radius,"grid_y_scale":world.grid_y_scale,"grid_revision":world.data.grid_revision,"legacy_schemas":[1,2,3,4,5,6],"legacy_grids":[1,2]}
	DirAccess.make_dir_recursive_absolute("res://previews/map-tactical")
	FileAccess.open("res://previews/map-tactical/grid-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("GRID_PROJECTION_CHECK "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
