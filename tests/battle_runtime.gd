extends Node
const Rules = preload("res://scripts/battle_rules.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
func key(code: Key) -> void:
	var e:=InputEventKey.new()
	e.physical_keycode=code
	e.pressed=true
	Input.parse_input_event(e)
	e=InputEventKey.new()
	e.physical_keycode=code
	e.pressed=false
	Input.parse_input_event(e)
	# Synthetic input must be dispatched before another fixed simulation step
	# can start an automatic action and invalidate the displayed release window.
	Input.flush_buffered_events()
func click(game: Node, point: Vector2) -> void:
	var e:=InputEventMouseButton.new()
	e.button_index=MOUSE_BUTTON_LEFT
	e.position=point*Vector2(game.get_window().size)/Vector2(1920,1080)
	e.pressed=true
	Input.parse_input_event(e)
	e=InputEventMouseButton.new()
	e.button_index=MOUSE_BUTTON_LEFT
	e.position=point*Vector2(game.get_window().size)/Vector2(1920,1080)
	e.pressed=false
	Input.parse_input_event(e)
func shot(game: Node, dir: String, name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	game.get_viewport().get_texture().get_image().save_png(dir.path_join(name+".png"))
func run(game: Node, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	var original: Array=game.world.units.duplicate(true)
	key(KEY_B)
	await get_tree().process_frame
	check(is_instance_valid(game.battle),"B opens exhibition through actual input")
	var battle: Control=game.battle
	await shot(game,dir,"01-split-formation")
	key(KEY_SPACE)
	var before: float=battle.sim.elapsed
	for i in 10: await get_tree().process_frame
	check(battle.sim.elapsed==before,"pause freezes simulation and animation clock")
	var normal_sim: Rules=battle.sim
	var crowd_encounter: Dictionary=normal_sim.encounter.duplicate(true)
	crowd_encounter.player.soldiers=6000
	crowd_encounter.enemy.soldiers=6000
	battle.sim=Rules.new(crowd_encounter)
	await shot(game,dir,"01d-full-armies")
	battle.debug_bodies=true
	await shot(game,dir,"01e-ground-footprints")
	battle.debug_bodies=false
	battle.sim=normal_sim
	var original_id: String=battle.sim.encounter.player.id
	var original_hero_id: String=battle.sim.hero_for(0).hero_id
	battle.sim.encounter.player.id="vanguard"
	battle.sim.hero_for(0).hero_id="nangongshi"
	await shot(game,dir,"01f-general-full-body")
	battle.sim.encounter.player.id=original_id
	battle.sim.hero_for(0).hero_id=original_hero_id
	game.get_window().size=Vector2i(1280,720)
	await shot(game,dir,"01b-split-1280")
	click(game,Vector2(1093,1012))
	await get_tree().process_frame
	check(battle.speed==2,"battle button accepts mouse input at resized window")
	key(KEY_X)
	game.get_window().size=Vector2i(1920,1080)
	await shot(game,dir,"01c-split-1920")
	game.get_window().size=Vector2i(1920,1080)
	var turn: int=game.world.turn
	key(KEY_E); key(KEY_C); key(KEY_F9)
	game.action("end_turn")
	check(game.world.turn==turn and game.world.units==original,"map hotkeys and actions cannot leak through battle")
	key(KEY_SPACE)
	var captured_charge:=false
	var captured_cast:=false
	var captured_ultimate:=false
	var paused_burn:=false
	var released:=false
	var started:=Time.get_ticks_msec()
	while battle.sim.result.is_empty() and Time.get_ticks_msec()-started<180000:
		await get_tree().process_frame
		if battle.sim.elapsed>4.0 and not captured_charge:
			captured_charge=true
			await shot(game,dir,"02-charge")
		if battle.sim.hero_for(0).action=="cast" and battle.sim.hero_for(0).age>0.4 and not captured_cast:
			captured_cast=true
			await shot(game,dir,"03-automatic-cast")
		if battle.sim.finisher_reason(0).is_empty() and not released:
			key(KEY_R)
			released=battle.sim.hero_for(0).action=="finisher"
		if not paused_burn:
			for target: Rules.Fighter in battle.sim.sides[1]:
				if target.burns.is_empty(): continue
				key(KEY_SPACE)
				await get_tree().process_frame
				var paused_time: float=battle.sim.elapsed
				var paused_effects: Array=battle.effects.duplicate(true)
				var paused_stacks: Dictionary=target.burns.duplicate(true)
				for i in 5: await get_tree().process_frame
				check(battle.sim.elapsed==paused_time and target.burns==paused_stacks and battle.effects==paused_effects,"pause freezes burn expiry and active effects as well as simulation")
				key(KEY_SPACE)
				paused_burn=true
				break
		if battle.effects.any(func(e: Dictionary) -> bool: return e.kind=="finisher" and int(e.side)==0) and not captured_ultimate:
			captured_ultimate=true
			await shot(game,dir,"04-morale-finisher")
			key(KEY_X)
	check(released and captured_ultimate,"R triggers available finisher and effects")
	check(captured_cast,"hero automatically casts with visible windup")
	check(paused_burn,"real combat applies visible burning to enemy units")
	check(not battle.sim.result.is_empty(),"live battle reaches result")
	while battle.result_age<1.5: await get_tree().process_frame
	await shot(game,dir,"05-result")
	var fps: float=battle.total_frames/maxf(0.01,battle.wall_time)
	key(KEY_ENTER)
	await get_tree().process_frame
	check(not is_instance_valid(game.battle) and game.hud.visible and game.world.units==original,"return restores map and exhibition preserves campaign")
	# Real map attack via actual campaign action, resolve with the real simulator.
	var u: Dictionary=game.world.units[0]
	var target: Dictionary={}
	var route: Dictionary=game.world.search(int(u.cell),99999,u.id)
	var best_cost:=999999
	for poi in game.world.pois:
		if poi.owner!="shang": continue
		for ci in poi.cells:
			for n in game.world.cells[int(ci)].n:
				if not route.dist.has(int(n)) or int(route.dist[int(n)])>=best_cost: continue
				var probe: Dictionary=u.duplicate(true)
				probe.cell=int(n)
				if game.world.can_capture(probe,poi):
					target=poi
					best_cost=int(route.dist[int(n)])
	check(not target.is_empty(),"a guarded target is reachable from the real campaign start")
	game.selected_poi=target.id
	game.travel_speed=0.01
	for attempt in 30:
		if game.world.can_capture(u,target): break
		game.approach_selected()
		game.execute_move()
		while game.moving: await get_tree().process_frame
		if game.world.can_capture(u,target): break
		game.action("end_turn")
	check(game.world.can_capture(u,target),"actual multi-turn march reaches guarded land adjacency")
	await shot(game,dir,"06a-map-before-engagement")
	game.action("capture")
	check(is_instance_valid(game.battle) and not game.world.pending_battle.is_empty(),"map engagement opens real battle")
	battle=game.battle
	battle.paused=true
	for i in 5000:
		battle.sim.use_finisher(0)
		battle.sim.advance()
		battle.advance_effects(Rules.STEP)
		if not battle.sim.result.is_empty(): break
	var result: Dictionary=battle.sim.result.duplicate(true)
	battle.result_age=2.0
	battle.activate("return")
	await get_tree().process_frame
	check(u.soldiers==result.player_remaining and u.morale==result.morale,"real battle writes casualties and morale to correct army")
	check(target.owner==("player" if result.player_won else "shang"),"ownership follows actual combat result")
	game.refresh()
	game.action("focus")
	await shot(game,dir,"06-map-return")
	var report: Dictionary={"checks":checks,"failures":failures,"fps_average":fps,"renderer":RenderingServer.get_video_adapter_name(),"result":result}
	FileAccess.open(dir.path_join("runtime-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BATTLE_RUNTIME "+JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
