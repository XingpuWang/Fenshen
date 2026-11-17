extends SceneTree
## Real-window coverage for oblique map projection, army badges and map input.
var game: Node2D
var checks:=0
var failures: Array[String]=[]
var output:="res://previews/map-tactical/presentation"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview-dir="): output=arg.trim_prefix("--preview-dir=")
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)

func settle(frames: int=4) -> void:
	for i in frames:
		await process_frame
		await RenderingServer.frame_post_draw

func shot(name: String) -> void:
	await settle()
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func click(point: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	var physical:=point*Vector2(root.size)/Vector2(1920,1080)
	var motion:=InputEventMouseMotion.new()
	motion.position=physical
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=physical
		event.button_index=button
		event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
	await settle()

func badge(index: int) -> Dictionary:
	for entry in game.layer.unit_badges:
		if int(entry.unit)==index: return entry
	return {}

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1920,1080)
	game=load("res://scenes/main.tscn").instantiate()
	game.start_in_test_scenario=false
	root.add_child(game)
	await settle(8)
	game.toast=""
	game.refresh()
	await shot("01-armies-and-oblique-grid")
	check(game.layer.unit_badges.size()==3,"all starting army badges are visible")
	var initial_camera: Vector2=game.camera.position
	var cells: Array[int]=[]
	for unit in game.world.units: cells.append(int(unit.cell))
	for zoom in [.16,.28,.5,.9,1.4]:
		game.set_map_zoom(zoom)
		game.camera.force_update_scroll()
		await settle()
		for cell in cells:
			var center: Vector2=game.world.center(cell)
			var screen: Vector2=game.world_to_screen(center)
			check(game.world.cell_at(game.screen_to_world(screen))==cell,"cell round trip at zoom %.2f" % zoom)
		var origin: Vector2=game.world.center(cells[0])
		var x: Vector2=game.world_to_screen(origin+Vector2(100,0))-game.world_to_screen(origin)
		var y: Vector2=game.world_to_screen(origin+Vector2(0,100))-game.world_to_screen(origin)
		check(absf(y.length()/x.length()-1.0)<.001,"original map artwork remains uniformly scaled at zoom %.2f" % zoom)
		var polygon: PackedVector2Array=game.layer.hexagon(origin,game.world.radius)
		var bounds:=Rect2(game.world_to_screen(polygon[0]),Vector2.ZERO)
		for vertex in polygon: bounds=bounds.expand(game.world_to_screen(vertex))
		check(absf(bounds.size.x-sqrt(3.0)*80.0*zoom)<.01,"enlarged hexagons render at the correct width at zoom %.2f" % zoom)
		check(absf(bounds.size.y/bounds.size.x-2.0/sqrt(3.0)*cos(PI/4))<.001,"only the hexagon geometry has a 45 degree pitch at zoom %.2f" % zoom)
		for child in game.get_children():
			if child is Sprite2D and child!=game.terrain_overlay:
				check(child.scale==Vector2.ONE and child.rotation==0,"map chunk retains its original transform")
	game.set_map_zoom(.5)
	game.camera.position=initial_camera
	await settle()
	for index in [1,2,0]:
		var entry:=badge(index)
		check(not entry.is_empty(),"hero %d has a clickable badge" % index)
		if entry.is_empty(): continue
		await click(entry.rect.get_center())
		check(game.selected_unit==index,"portrait/nameplate selects hero %d" % index)
		check(game.camera.position.is_equal_approx(initial_camera),"badge selection does not jump the map")
	var army: Sprite2D=game.unit_nodes[0].get_node("Soldiers")
	check(not army.contains_formation_point(Vector2(150,-300)),"transparent formation corner does not intercept ground clicks")
	var opaque_hit:=false
	for entry in army.hit_frames:
		var point: Vector2=entry.slot+(Vector2(158,140)-entry.pivot)*float(entry.ratio)
		if army.contains_formation_point(point): opaque_hit=true; break
	check(opaque_hit,"visible soldier body can be selected")
	# Ground just outside an army's hex must still accept movement clicks.
	var border_probe_found:=false
	var origin: Vector2=game.world.center(cells[0])
	for ci in game.world.cells[cells[0]].n:
		if not game.world.walkable(int(ci)) or game.world.occupied(int(ci),""): continue
		var direction: Vector2=game.world.center(int(ci))-origin
		var probe: Vector2=origin+direction*.5+direction.normalized()*6.0
		var screen: Vector2=game.world_to_screen(probe)
		if game.world.cell_at(probe)!=int(ci) or not game.poi_at(probe).is_empty(): continue
		if not game.hud.hit_test(screen).is_empty() or game.layer.badge_at_screen(screen)>=0: continue
		if army.contains_formation_point(army.to_local(probe)): continue
		border_probe_found=true
		await click(screen)
		check(game.path.size()>1 and game.path.back()==int(ci),"empty neighboring ground plans movement instead of reselecting the army")
		game.select_unit(0,false)
		break
	check(border_probe_found,"neighboring ground click fixture exists")
	var unit: Dictionary=game.world.units[0]
	var full_count: int=army.hit_frames.size()
	var people:=int(unit.soldiers)
	unit.soldiers=1700
	game.refresh()
	await settle()
	check(int(badge(0).soldiers)==1700,"nameplate reads current soldier strength")
	check(army.hit_frames.size()<full_count,"losses reduce visible formation size")
	unit.soldiers=people
	game.refresh()
	await settle()
	# A buff cast through the badge must target its army, not the terrain below it.
	await click(badge(1).rect.get_center())
	game.action("map_skill")
	await settle()
	await click(badge(1).rect.get_center())
	check(game.world.units[1].action_done,"skill targeting through a badge reaches the correct army")
	game.action("end_turn")
	game.select_unit(0,false)
	game.camera.position=initial_camera
	game.set_map_zoom(.8)
	await shot("02-formation-closeup")
	game.set_map_zoom(.5)
	await settle()
	# Place the three armies on legal adjacent land to exercise badge collision layout.
	var nearby: Array[int]=[cells[0]]
	for ci in game.world.cells[cells[0]].n:
		if game.world.walkable(int(ci)) and not game.world.occupied(int(ci),""): nearby.append(int(ci))
		if nearby.size()==3: break
	check(nearby.size()==3,"adjacent-land layout fixture exists")
	if nearby.size()==3:
		for i in 3:
			game.world.units[i].cell=nearby[i]
			game.unit_nodes[i].position=game.world.center(nearby[i])
		game.refresh()
		await settle()
		for a in 3:
			for b in range(a+1,3):
				check(not badge(a).rect.intersects(badge(b).rect),"adjacent army badges %d/%d do not overlap" % [a,b])
		await shot("03-adjacent-armies")
	for i in 3:
		game.world.units[i].cell=cells[i]
		game.unit_nodes[i].position=game.world.center(cells[i])
	game.refresh()
	await settle()
	var target:=-1
	var best_score:=-INF
	for ci in game.reachable.dist:
		if int(game.reachable.dist[ci]) not in [4,5,6]: continue
		var point: Vector2=game.world_to_screen(game.world.center(int(ci)))
		var start: Vector2=game.world_to_screen(game.unit_nodes[0].position)
		if point.x<start.x+130 or absf(point.y-start.y)>95: continue
		if not Rect2(500,250,1040,560).has_point(point): continue
		if not game.hud.hit_test(point).is_empty() or game.layer.badge_at_screen(point)>=0: continue
		if not game.poi_at(game.world.center(int(ci))).is_empty(): continue
		var score:=point.x-start.x-absf(point.y-start.y)*2.0
		if score>best_score:
			best_score=score
			target=int(ci)
	check(target>=0,"visible ground movement target exists")
	if target>=0:
		await click(game.world_to_screen(game.world.center(target)))
		check(game.path.size()>1 and game.path.back()==target,"projected ground click plans the intended route")
		await shot("04-movement-route")
		var before_ap:=int(unit.ap)
		var cost:=int(game.path_cost)
		game.action("move")
		while game.moving: await process_frame
		check(int(unit.cell)==target and int(unit.ap)==before_ap-cost,"march reaches clicked cell and spends exact movement cost")
		await shot("05-army-arrived")
	var cursor:=Vector2(1130,620)
	var anchored: Vector2=game.screen_to_world(cursor)
	await click(cursor,MOUSE_BUTTON_WHEEL_UP)
	check(game.screen_to_world(cursor).distance_to(anchored)<.1,"wheel zoom preserves the point beneath the cursor")
	var before_pan: Vector2=game.camera.position
	var begin:=InputEventMouseButton.new()
	begin.button_index=MOUSE_BUTTON_MIDDLE
	begin.position=cursor
	begin.pressed=true
	Input.parse_input_event(begin)
	await process_frame
	var motion:=InputEventMouseMotion.new()
	motion.position=cursor+Vector2(80,60)
	motion.relative=Vector2(80,60)
	Input.parse_input_event(motion)
	await process_frame
	begin.pressed=false
	Input.parse_input_event(begin)
	await settle()
	check(((before_pan-game.camera.position)*game.camera.zoom).distance_to(Vector2(80,60))<.1,"drag follows the pointer equally on both projected axes")
	game.action("focus")
	game.select_unit(1,false)
	root.size=Vector2i(1280,720)
	await settle(8)
	await click(badge(0).rect.get_center())
	check(game.selected_unit==0,"badge input scales with a 1280 by 720 window")
	await shot("06-window-1280x720")
	var report:={"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"radius":game.world.radius,"grid_y_scale":game.world.grid_y_scale,"map_aspect_unchanged":game.camera.zoom.x==game.camera.zoom.y,"captures":6}
	FileAccess.open(output.path_join("runtime-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MAP_PRESENTATION_RUNTIME "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
