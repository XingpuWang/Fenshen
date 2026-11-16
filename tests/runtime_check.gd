extends Node
var failures: Array[String]=[]
var checks: int=0
func check(ok: bool,msg: String) -> void:
	checks+=1
	if not ok: failures.append(msg)
func settle(game: Node,frames: int=3) -> void:
	for i in frames:
		await game.get_tree().process_frame
		await RenderingServer.frame_post_draw
func shot(game: Node,dir: String,name: String) -> void:
	await settle(game)
	var img=game.get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name+".png"))
func click(game: Node,p: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	p=p*Vector2(game.get_window().size)/Vector2(1920,1080)
	var motion=InputEventMouseMotion.new()
	motion.position=p
	Input.parse_input_event(motion)
	var e=InputEventMouseButton.new()
	e.button_index=button
	e.position=p
	e.pressed=true
	Input.parse_input_event(e)
	await game.get_tree().process_frame
	e=InputEventMouseButton.new()
	e.button_index=button
	e.position=p
	e.pressed=false
	Input.parse_input_event(e)
	await game.get_tree().process_frame
func run(game: Node,dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await settle(game,8)
	var u: Dictionary=game.world.units[0]
	var start=int(u.cell)
	var target=-1
	for ci in game.reachable.dist:
		if int(game.reachable.dist[ci])==4 and game.world.center(ci).x>game.world.center(start).x+100 and game.world.center(ci).y<game.world.center(start).y+100:
			target=int(ci)
			break
	check(target>=0,"visible movement target available")
	await click(game,game.world_to_screen(game.world.center(target)))
	check(game.path.size()>1,"left click creates route")
	await shot(game,dir,"01-movement-preview")
	await click(game,Vector2(1085,983))
	var timeout: int=0
	while game.moving and timeout<600:
		await game.get_tree().process_frame
		timeout+=1
	check(int(u.cell)==target,"UI Move executes complete path")
	check(int(u.ap)==2,"movement deducts exact action points")
	await shot(game,dir,"02-army-arrived")
	await click(game,Vector2(1790,977))
	check(int(u.ap)==6 and game.world.turn==2,"End turn button restores action points")
	# Select a second army through the actual bottom card.
	await click(game,Vector2(375+2*180+80,1003))
	check(game.selected_unit==2,"army card switches active unit")
	var ferry: Dictionary=game.world.by_poi.wanluo_ferry_0
	var north_unit: Dictionary=game.world.units[2]
	game.selected_poi=ferry.id
	game.approach_selected()
	check(game.path.size()>1,"approach computes route to adjacent bank")
	game.execute_move()
	while game.moving: await game.get_tree().process_frame
	if not game.world.can_capture(north_unit,ferry):
		game.action("end_turn")
		game.approach_selected()
		game.execute_move()
		while game.moving: await game.get_tree().process_frame
	game.action("end_turn")
	check(game.world.can_capture(north_unit,ferry),"army reached land adjacency")
	await shot(game,dir,"03-ferry-before-capture")
	await click(game,Vector2(1197,983))
	check(ferry.owner=="player","Capture button changes ferry ownership")
	var start_bank=int(ferry.banks[1])
	var opposite=int(ferry.banks[0])
	game.choose_cell(opposite)
	check(game.path.has(start_bank) and game.path.has(opposite),"route uses explicit ferry link")
	await shot(game,dir,"04-ferry-route")
	game.execute_move()
	var boat_seen: bool=false
	while game.moving:
		if game.unit_nodes[game.selected_unit].get_node("Boat").visible and not boat_seen:
			boat_seen=true
			await game.get_tree().create_timer(.35).timeout
			await shot(game,dir,"05a-ferry-underway")
		await game.get_tree().process_frame
	check(boat_seen,"crossing uses visible ferry boat")
	check(int(north_unit.cell)==opposite and game.world.crossed==1,"army crosses owned ferry")
	check(int(game.world.cells[opposite].t)==0,"army ends on dry land")
	await shot(game,dir,"05-ferry-crossed")
	game.action("overview")
	await shot(game,dir,"06-nine-regions")
	# A route invalidated by loss of ownership must be rejected before animation.
	game.world.next_turn()
	game.refresh()
	game.choose_cell(start_bank)
	ferry.owner="shang"
	var before=int(north_unit.cell)
	game.execute_move()
	await settle(game)
	check(not game.moving and int(north_unit.cell)==before,"stale route stops when ferry changes owner")
	ferry.owner="player"
	# Verify a mountain pass using the same player-facing approach and capture actions.
	game.select_unit(0)
	game.selected_poi="wanluo_pass_2"
	var gate: Dictionary=game.world.by_poi[game.selected_poi]
	for attempt in 5:
		game.action("end_turn")
		if game.world.can_capture(u,gate): break
		game.approach_selected()
		game.execute_move()
		while game.moving: await game.get_tree().process_frame
	game.action("end_turn")
	check(game.world.can_capture(u,gate),"army reaches adjacent mountain pass")
	game.action("capture")
	if is_instance_valid(game.battle):
		game.battle.paused=true
		for i in 5000:
			game.battle.sim.use_finisher(0)
			game.battle.sim.advance()
			game.battle.sim.events.clear()
			if not game.battle.sim.result.is_empty(): break
		game.battle.result_age=2.0
		game.battle.activate("return")
		await settle(game)
	check(gate.owner=="player","mountain pass changes ownership")
	var south_target: int=-1
	for ci in game.reachable.dist:
		if game.world.center(ci).y>float(gate.position[1])+150 and abs(game.world.center(ci).x-float(gate.position[0]))<150:
			south_target=int(ci)
			break
	check(south_target>=0,"owned pass opens route through mountains")
	if south_target>=0:
		game.choose_cell(south_target)
		game.execute_move()
		while game.moving: await game.get_tree().process_frame
		check(game.world.center(int(u.cell)).y>float(gate.position[1])+150,"army passed through owned gate")
	game.action("focus")
	await shot(game,dir,"08-pass-captured")
	# Real input: cursor-anchored zoom and minimap repositioning.
	var old_zoom: float=game.camera.zoom.x
	await click(game,Vector2(1100,500),MOUSE_BUTTON_WHEEL_UP)
	check(game.camera.zoom.x>old_zoom,"mouse wheel zoom")
	var old_camera: Vector2=game.camera.position
	await click(game,Vector2(110,900))
	check(game.camera.position.distance_to(old_camera)>500,"minimap click navigates world")
	game.action("region:bashu")
	game.selected_poi=""
	game.path.clear()
	game.toast=""
	game.hover_cell=-1
	await shot(game,dir,"07-shu-road")
	var report={"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_video_adapter_name(),"checks":checks,"failures":failures,"captures":9}
	FileAccess.open(dir.path_join("runtime-tests.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RUNTIME_CHECK "+JSON.stringify(report))
	game.get_tree().quit(0 if failures.is_empty() else 1)
