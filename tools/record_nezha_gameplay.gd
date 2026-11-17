extends SceneTree
## Records the real game viewport with Godot Movie Maker; no balance overrides.
## godot --path . --script res://tools/record_nezha_gameplay.gd \
##   --write-movie /tmp/nezha-gameplay.avi --fixed-fps 30 --disable-vsync
const FPS:=30
var markers: Array[Dictionary]=[]
var report_path:="res://previews/nezha/v4/gameplay-recording.json"
var capture_dir:=""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--record-report="): report_path=arg.trim_prefix("--record-report=")
		if arg.begins_with("--capture-dir="): capture_dir=arg.trim_prefix("--capture-dir=")
	call_deferred("record")

func mark(label: String) -> void:
	markers.append({"name":label,"frame":Engine.get_frames_drawn(),"seconds":Engine.get_frames_drawn()/float(FPS)})
	print("RECORD_MARK "+JSON.stringify(markers.back()))
	if not capture_dir.is_empty():
		root.get_texture().get_image().save_png(capture_dir.path_join("%02d.png" % markers.size()))

func hold(seconds: float) -> void:
	for i in roundi(seconds*FPS): await process_frame

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new()
		event.physical_keycode=code
		event.pressed=pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func record() -> void:
	Engine.max_fps=0
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	root.size=Vector2i(1920,1080)
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	# Use the default two-army Chaoge scenario, with normal stats and earned morale.
	var unit: Dictionary=game.world.units[0]
	var opposing_army: Dictionary=game.world.units[1]
	assert(game.world.test_scenario,"Recording expects the default Chaoge test scenario")
	game.say("哪吒 · 火莲焚阵")
	await RenderingServer.frame_post_draw
	mark("大地图 · 哪吒头像与四技能")
	await hold(1.5)
	var hover:=InputEventMouseMotion.new()
	hover.position=Vector2(266,494)
	Input.parse_input_event(hover)
	await hold(.5)
	mark("三头六臂 · 被动说明")
	await hold(1.5)
	hover=InputEventMouseMotion.new()
	hover.position=Vector2(850,750)
	Input.parse_input_event(hover)
	key(KEY_Q)
	var target:=int(opposing_army.cell)
	game.hover_cell=target
	game.update_skill_preview()
	mark("火莲焚阵 · 目标范围")
	await hold(1.5)
	var soldiers_before:=int(opposing_army.soldiers)
	game.cast_selected_map_skill(target)
	mark("火莲焚阵 · 结印与火柱")
	while game.is_map_casting(): await process_frame
	var map_damage:=soldiers_before-int(opposing_army.soldiers)
	assert(map_damage>0 and unit.action_done,"Map skill must damage the actual enemy army and spend the action")
	await hold(1.0)
	key(KEY_E)
	key(KEY_B)
	var battle: Control=game.battle
	assert(is_instance_valid(battle),"Field battle must open through normal game input")
	await RenderingServer.frame_post_draw
	mark("朝歌交锋 · 双方列阵")
	var seen_effects: Array=[]
	var seen_burn:=false
	var seen_attack:=false
	var seen_spirit:=false
	var seen_splash:=false
	var released:=0
	var impacts:=0
	while battle.sim.result.is_empty() and battle.sim.elapsed<80:
		await RenderingServer.frame_post_draw
		var hero=battle.sim.hero_for(0)
		if hero.action=="attack" and not seen_attack:
			seen_attack=true
			mark("火尖枪 · 普攻连刺")
		if hero.action=="attack" and hero.age>=.30 and not seen_spirit:
			seen_spirit=true
			mark("三头六臂 · 金色法相")
		if int(battle.sim.stats.get("splash_hits",0))>0 and not seen_splash:
			seen_splash=true
			mark("三头六臂 · 范围溅射命中")
		if not seen_burn:
			for enemy in battle.sim.sides[1]:
				if battle.sim.burn_stacks(enemy)>0:
					seen_burn=true
					mark("灼烧 · 持续伤害")
					break
		for effect in battle.effects:
			if int(effect.side)!=0 or effect.kind not in ["ring","finisher"] or effect in seen_effects: continue
			seen_effects.append(effect)
			if effect.kind=="ring": mark("乾坤圈 · 投出与回收")
			else:
				impacts+=1
				mark("三昧真火 · 火莲引爆")
		if battle.sim.finisher_reason(0).is_empty():
			key(KEY_R)
			if hero.action=="finisher":
				released+=1
				mark("士气满额 · R 释放终结技")
	assert(impacts>0 and seen_attack and seen_burn and seen_spirit and seen_splash,"Recording must include normal attacks, passive spirit, actual splash damage, burns and ultimate impact")
	var result: Dictionary=battle.sim.result.duplicate(true)
	assert(not result.is_empty(),"Battle did not reach its result")
	mark("战斗结算")
	await hold(2.8)
	key(KEY_ENTER)
	assert(not is_instance_valid(game.battle),"Result must return to the map")
	mark("返回大地图")
	await hold(1.5)
	var report: Dictionary={"source":"actual Godot game viewport / Movie Maker","engine":Engine.get_version_info().string,
		"resolution":[1920,1080],"capture_fps":FPS,"simulation_hz":60,"battle_speed":1,"map_damage":map_damage,
		"ultimate_releases":released,"ultimate_impacts":impacts,"ordinary_attack_seen":seen_attack,"burn_seen":seen_burn,
		"passive_spirit_seen":seen_spirit,"splash_seen":seen_splash,"attack_frames":16,"battle_skill_frames":16,"ultimate_frames":16,"art_version":4,
		"demo_start":"default Chaoge two-army scenario; normal end-turn refill before battle","balance_overrides":false,"saved_campaign":false,
		"markers":markers,"result":result,"frames":Engine.get_frames_drawn(),"seconds":Engine.get_frames_drawn()/float(FPS)}
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("GAMEPLAY_RECORDING "+JSON.stringify(report))
	quit()
