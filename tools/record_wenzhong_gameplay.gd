extends SceneTree
## Capture the default Chaoge game at normal speed, with earned ultimate morale.
const FPS:=30
var markers: Array[Dictionary]=[]
var output:="res://previews/wenzhong/v1"
var capture_dir:=""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir=arg.trim_prefix("--capture-dir=")
	call_deferred("record")

func mark(label: String) -> void:
	markers.append({"name":label,"frame":Engine.get_frames_drawn(),"seconds":Engine.get_frames_drawn()/float(FPS)})
	print("RECORD_MARK "+JSON.stringify(markers.back()))
	if not capture_dir.is_empty(): root.get_texture().get_image().save_png(capture_dir.path_join("%02d.png" % markers.size()))

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
	DirAccess.make_dir_recursive_absolute(output)
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	root.size=Vector2i(1920,1080)
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	assert(game.world.test_scenario,"Use the default Chaoge scenario")
	game.select_unit(1,false)
	await RenderingServer.frame_post_draw
	mark("闻仲 · 白发紫金甲立绘")
	await hold(2)
	var hover:=InputEventMouseMotion.new()
	hover.position=Vector2(260,482)
	Input.parse_input_event(hover)
	await hold(.5)
	mark("雷法精通 · 被动说明")
	await hold(1)
	key(KEY_Q)
	var target: int=game.world.units[0].cell
	game.hover_cell=target
	game.update_skill_preview()
	mark("雷印镇军 · 目标范围")
	await hold(1)
	game.cast_selected_map_skill(target)
	assert(game.is_map_casting(),"Wen Zhong map cast must animate")
	while game.is_map_casting() and game.map_cast.age<1.13: await process_frame
	mark("雷印镇军 · 落雷与减防")
	while game.is_map_casting(): await process_frame
	assert(game.world.units[0].effects.size()==1 and game.world.units[1].effects.is_empty(),"Thunder seal affects the enemy only")
	await hold(1)
	key(KEY_E)
	key(KEY_B)
	var battle: Control=game.battle
	assert(is_instance_valid(battle) and battle.sim.hero_for(0).hero_id=="wenzhong","Normal input opens the actual army's field battle")
	await RenderingServer.frame_post_draw
	mark("朝歌交锋 · 闻仲迎战哪吒")
	var attack_seen:=false
	var skill_seen:=false
	var releases:=0
	var impacts:=0
	var seen: Array=[]
	while battle.sim.result.is_empty() and battle.sim.elapsed<80:
		await RenderingServer.frame_post_draw
		var hero=battle.sim.hero_for(0)
		if hero.action=="attack" and hero.age>=.32 and not attack_seen:
			attack_seen=true
			mark("双鞭普攻 · 电弧命中")
		for effect in battle.effects:
			if int(effect.side)!=0 or effect.kind not in ["skill","finisher"] or effect in seen: continue
			seen.append(effect)
			if effect.kind=="skill":
				skill_seen=true
				mark("雷鞭震阵 · 双雷震击")
			else:
				impacts+=1
				mark("九霄雷殛 · 多重落雷")
		if battle.sim.finisher_reason(0).is_empty():
			key(KEY_R)
			if hero.action=="finisher":
				releases+=1
				mark("士气积满 · R 释放终结技")
	assert(attack_seen and skill_seen and impacts>0,"Video must include attack, battle skill and actual ultimate impact")
	var result: Dictionary=battle.sim.result.duplicate(true)
	assert(not result.is_empty(),"Real battle must finish")
	mark("战斗结算")
	await hold(2.2)
	key(KEY_ENTER)
	assert(not is_instance_valid(game.battle),"Return to the map through normal input")
	mark("返回大地图")
	await hold(1.3)
	var report:={"source":"actual Godot game viewport / Movie Maker","engine":Engine.get_version_info().string,
		"hero":"wenzhong","art_version":1,"resolution":[1920,1080],"capture_fps":FPS,"simulation_hz":60,
		"battle_speed":1,"balance_overrides":false,"saved_campaign":false,"map_debuff_seen":true,
		"ordinary_attack_seen":attack_seen,"battle_skill_seen":skill_seen,"ultimate_releases":releases,"ultimate_impacts":impacts,
		"attack_frames":16,"battle_skill_frames":16,"ultimate_frames":16,"map_cast_frames":16,"vfx_frames_per_clip":16,
		"markers":markers,"result":result,"frames":Engine.get_frames_drawn(),"seconds":Engine.get_frames_drawn()/float(FPS)}
	FileAccess.open(output.path_join("gameplay-recording.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WENZHONG_GAMEPLAY "+JSON.stringify(report))
	quit()
