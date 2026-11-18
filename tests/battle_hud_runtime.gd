extends SceneTree
## Run with a native renderer. Optional --capture-dir=... saves the actual viewports.
const Hud = preload("res://scripts/battle_hud.gd")
const Rules = preload("res://scripts/battle_rules.gd")
var failures: Array[String] = []
var checks := 0
var capture_dir := ""
var expect_source := false
var game: Node

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--expect-source-art": expect_source=true
		if arg.begins_with("--capture-dir="):
			capture_dir=arg.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(capture_dir)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func enter_battle(side: int) -> Control:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.select_unit(side,false)
	game.start_exhibition()
	game.battle.set_process(false)
	# This fixture steps simulation faster than wall time. Only the real-time recording plays its audio.
	for player: AudioStreamPlayer in game.battle.audio: player.stop()
	game.battle.audio.clear()
	return game.battle

func draw_frame(battle: Control) -> void:
	battle.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw

func shot(filename: String) -> void:
	if not capture_dir.is_empty():
		root.get_texture().get_image().save_png(capture_dir.path_join(filename+".png"))

func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point*Vector2(root.size)/Vector2(1920,1080)
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func hover(point: Vector2) -> void:
	var move:=InputEventMouseMotion.new()
	move.position=point*Vector2(root.size)/Vector2(1920,1080)
	Input.parse_input_event(move)
	Input.flush_buffered_events()

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new()
		event.physical_keycode=code
		event.pressed=pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func step(battle: Control) -> void:
	battle.sim.advance()
	battle.advance_effects(Rules.STEP)

func visible_health_ratio(screen: Image, side: int) -> float:
	var card: Rect2=Hud.CARDS[side]
	var left:=roundi(card.position.x+195+61+3)
	var width:=roundi(card.size.x-28-195-145-6)
	var green:=0
	for x in range(left,left+width):
		var pixel:=screen.get_pixel(x,894)
		if pixel.g>pixel.r*1.05 and pixel.g>pixel.b*1.1: green+=1
	return float(green)/width

func ring_luminance(screen: Image, radius: float) -> float:
	# The lower-right arc is clear of the R badge and the cloud at the foot of the ring.
	var light := 0.0
	for i in 19:
		var point := Hud.RING_CENTER + Vector2.from_angle(.1 + i*.045) * radius
		light += screen.get_pixelv(Vector2i(point.round())).get_luminance()
	return light / 19.0

func check_finisher_cues(battle: Control) -> void:
	var morale: Array = battle.sim.morale.duplicate()
	battle.sim.morale[0] = Rules.FINISHER_COST-1
	battle.sim.morale[1] = 0.0
	await draw_frame(battle)
	var charging := root.get_texture().get_image()
	shot("wen-charging")
	battle.sim.morale[1] = Rules.FINISHER_COST
	hover(Hud.RING_CENTER)
	await draw_frame(battle)
	var hovered := root.get_texture().get_image()
	for radius in [Hud.RING_RADIUS, Hud.RING_RADIUS+8]:
		check(absf(ring_luminance(charging,radius)-ring_luminance(hovered,radius))<.02,"hover and enemy morale leave the charging ring dim")
	hover(Vector2(1300,600))
	battle.sim.morale[0] = Rules.FINISHER_COST
	await draw_frame(battle)
	var ready := root.get_texture().get_image()
	var full := ring_luminance(ready,Hud.RING_RADIUS)
	check(full > ring_luminance(charging,Hud.RING_RADIUS)+.065,"ring brightens when the player's own ultimate becomes available")
	var glow: Array[float] = [ring_luminance(ready,Hud.RING_RADIUS+8)]
	for i in 3:
		await create_timer(Hud.READY_PULSE_MS / 4000.0).timeout
		await draw_frame(battle)
		glow.append(ring_luminance(root.get_texture().get_image(),Hud.RING_RADIUS+8))
	check(glow.max()-glow.min()>.025,"ready ring breathes while the combat simulation is held still")
	key(KEY_SPACE)
	await draw_frame(battle)
	shot("wen-paused")
	check(full > ring_luminance(root.get_texture().get_image(),Hud.RING_RADIUS)+.065,"pausing dims the ring even at full morale")
	key(KEY_R)
	check(battle.paused and battle.sim.morale[0]==Rules.FINISHER_COST,"paused R preserves the fully charged ultimate")
	key(KEY_SPACE)
	battle.sim.morale.assign(morale)

func leave_battle() -> void:
	game.queue_free()
	# Allow the audio mixer and deferred scene deletion to finish before the next encounter.
	await create_timer(.18).timeout

func run() -> void:
	root.size=Vector2i(1280,720)
	var battle:=enter_battle(1)
	await draw_frame(battle)
	check(battle.sim.hero_for(0).hero_id=="wenzhong","real field battle opens for selected commander")
	check(battle.battle_hud.atlas.get_size()==Vector2(1448,1086),"painted frame atlas loads")
	if expect_source:
		for path in ["assets/ui/battle/hud_kit.png","assets/ui/skills/hero_icons.png","assets/characters/nezha/v3/portrait.png","assets/characters/wenzhong/v1/portrait.png"]:
			check(("res://"+path) in Hud.Textures.source_fallbacks,"source fallback for "+path)
	check(battle.hit_at(Hud.ULTIMATE.position+Vector2(3,3)).is_empty(),"corners outside the ring are clear")
	click(Hud.RING_CENTER)
	check(battle.sim.stats.finishers==0 and battle.sim.morale[0]==50,"disabled ring preserves morale")
	click(Vector2(1093,1012))
	check(battle.speed==2,"speed mouse target works at 720p")
	key(KEY_X)
	check(battle.speed==1,"X restores normal speed")
	click(Vector2(832,1023))
	check(battle.paused,"painted pause target accepts mouse input")
	key(KEY_SPACE)
	check(not battle.paused,"Space resumes from the same control")
	while battle.sim.elapsed<6.95: step(battle)
	await draw_frame(battle)
	shot("wen-720")
	hover(Hud.AUTO.get_center())
	await draw_frame(battle)
	check(battle.hovered=="auto","automatic skill tooltip follows the scaled square")
	hover(Hud.CARDS[1].get_center())
	await draw_frame(battle)
	check(battle.hovered=="commander_1","opposing commander tooltip is reachable")
	hover(Vector2(1300,600))
	check(battle.sim.remaining(0)<battle.sim.initial[0] and battle.sim.kills[0]>0,"shown troop count and kills have changed in combat")
	root.size=Vector2i(1920,1080)
	await draw_frame(battle)
	await draw_frame(battle)
	shot("wen-1080")
	check(root.get_texture().get_size()==Vector2(1920,1080),"native 1080p view renders")
	await check_finisher_cues(battle)
	while battle.sim.result.is_empty():
		var hero:=battle.sim.hero_for(0) as Rules.Fighter
		if battle.sim.finisher_reason(0).is_empty() and hero.action in ["cast","attack"]: break
		step(battle)
	check(battle.sim.result.is_empty(),"earned full morale during an interruptible action")
	await draw_frame(battle)
	shot("wen-ready")
	var current_hero: Rules.Fighter=battle.sim.hero_for(0)
	var before: Array=[current_hero.action,current_hero.age,battle.sim.morale[0],battle.sim.stats.finishers]
	click(Hud.ULTIMATE.position+Vector2(3,3))
	check(before==[current_hero.action,current_hero.age,battle.sim.morale[0],battle.sim.stats.finishers],"click outside ready ring leaves current action and morale intact")
	click(Hud.R_BADGE.get_center())
	check(battle.sim.hero_for(0).action=="finisher" and battle.sim.morale[0]==0,"R badge immediately interrupts and spends earned morale")
	while battle.sim.elapsed<13.9 and battle.sim.result.is_empty(): step(battle)
	await draw_frame(battle)
	shot("wen-in-combat")
	var screen:=root.get_texture().get_image()
	for side in 2:
		var hero: Rules.Fighter=battle.sim.hero_for(side)
		check(absf(visible_health_ratio(screen,side)-hero.hp/hero.max_hp)<.06,"painted health bar matches actual commander health on each side")
	await leave_battle()
	battle=enter_battle(0)
	await draw_frame(battle)
	check(battle.sim.hero_for(0).hero_id=="nezha" and battle.battle_hud.circle_art_id=="samadhi","switching commanders binds the matching ultimate painting")
	check(Hud.purple_theme("wenzhong","player") and not Hud.purple_theme("nezha","shang"),"personal frames follow the hero on either side")
	while battle.sim.elapsed<6.95: step(battle)
	await draw_frame(battle)
	shot("nezha-1080")
	while battle.sim.finisher_reason(0)!="" and battle.sim.result.is_empty(): step(battle)
	await draw_frame(battle)
	shot("nezha-ready")
	click(Hud.RING_CENTER)
	check(battle.sim.hero_for(0).action=="finisher" and battle.sim.morale[0]==0,"clicking ring center releases Nezha's ultimate")
	await leave_battle()
	print("BATTLE_HUD_RUNTIME ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
