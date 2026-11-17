extends SceneTree
const Commander=preload("res://scripts/commander_panel.gd")
var game: Node2D
var checks:=0
var failures: Array[String]=[]
var output:="res://previews/chaoge-test"

func _initialize() -> void: call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)

func settle(count: int=3) -> void:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw

func hover(point: Vector2) -> void:
	var event:=InputEventMouseMotion.new()
	event.position=point*Vector2(root.size)/Vector2(1920,1080)
	Input.parse_input_event(event)
	await settle()

func click(point: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	await hover(point)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=button
		event.position=point*Vector2(root.size)/Vector2(1920,1080)
		event.pressed=pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await settle()

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new()
		event.physical_keycode=code
		event.pressed=pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await settle()

func badge(index: int) -> Vector2:
	for entry in game.layer.unit_badges:
		if int(entry.unit)==index: return entry.rect.get_center()
	return Vector2.ZERO

func shot(name: String) -> void:
	await settle()
	var screenshot:=root.get_texture().get_image()
	screenshot.save_png(output.path_join(name+".png"))
	if name=="01-clean-map": screenshot.get_region(Rect2i(16,16,316,820)).save_png(output.path_join("commander-panel.png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1920,1080)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle(8)
	check(game.world.test_scenario and game.world.units.size()==2,"default game opens the two-army test scenario")
	check(game.layer.unit_badges.size()==2,"both real armies are visible at startup")
	for hit in game.hud.hits:
		check(str(hit.id).begins_with("commander_") or hit.id in ["minimap","end_turn"],"only commander, minimap and end-turn hit targets remain")
	for point in [Vector2(800,38),Vector2(1600,180),Vector2(1600,500),Vector2(500,995),Vector2(1100,985),Vector2(303,922),Vector2(600,115)]:
		check(game.hud.hit_test(point).is_empty(),"removed UI leaves no invisible input blocker")
	check(Commander.RECT.grow(-20).encloses(Commander.PORTRAIT_RECT),"portrait stays inside a twenty-pixel frame inset")
	check(not Commander.RECT.intersects(game.hud.MINI_FRAME),"longer portrait panel clears the minimap")
	for i in 4:
		check(Commander.skill_rect(i).size==Vector2(64,64),"skills are full square icons")
		check(Commander.artifact_rect(i).size==Vector2(56,56),"artifact slots are full square icons")
	await hover(Vector2(700,800))
	await shot("01-clean-map")
	for index in 2:
		await click(badge(index))
		check(game.selected_unit==index,"army badge selects the corresponding test commander")
		for i in 4:
			await hover(Commander.skill_rect(i).get_center())
			var ability: Dictionary=game.world.Catalog.skill(game.world.units[index],Commander.SKILL_SLOTS[i])
			check(game.hud.commander_tooltip.get("id","")==ability.id,"icon hover retains full skill name and description")
		if index==1: await shot("02-wenzhong-icons")
	for i in 4:
		await hover(Commander.artifact_rect(i).get_center())
		check(game.hud.commander_tooltip.get("name","")=="未装备","artifact artwork is an empty-slot motif, not fake equipment")
	# The one map-skill icon replaces the removed command button.
	await click(badge(0))
	var before: int=game.world.units[1].soldiers
	await click(Commander.skill_rect(2).get_center())
	check(game.map_skill_targeting,"clicking the map-skill illustration enters targeting")
	await hover(badge(1))
	await shot("03-map-skill-targeting")
	await click(badge(1))
	check(game.is_map_casting(),"clicking the enemy portrait targets the actual field army")
	while game.is_map_casting() and game.map_cast.age<1.15: await process_frame
	await shot("04-fire-field-impact")
	while game.is_map_casting(): await process_frame
	check(game.world.units[1].soldiers<before and game.world.units[0].soldiers==2400,"map fire field causes real enemy-only losses")
	await click(Vector2(1790,977))
	check(game.world.units[1].soldiers==2400 and not game.world.units[0].action_done,"end-turn button restores the repeatable test setup")
	await click(badge(1))
	await click(Commander.skill_rect(2).get_center())
	await click(badge(0))
	check(game.world.units[0].effects.size()==1 and game.world.units[1].effects.is_empty(),"Wen Zhong's map icon debuffs Nezha")
	await click(badge(0))
	await shot("05-enemy-map-skill")
	# Resized window still maps squares and minimap to their intended input regions.
	root.size=Vector2i(1280,720)
	await settle(6)
	await hover(Commander.skill_rect(3).get_center())
	check(game.hud.commander_tooltip.get("id","")=="three_heads_six_arms","passive hover works at 1280x720")
	await shot("06-1280x720")
	root.size=Vector2i(1920,1080)
	await settle(6)
	await click(badge(1),MOUSE_BUTTON_RIGHT)
	check(is_instance_valid(game.battle),"right-clicking adjacent enemy starts real field combat")
	if not is_instance_valid(game.battle): finish(); return
	var battle: Control=game.battle
	check(battle.sim.encounter.get("kind","")=="field" and battle.sim.encounter.enemy.id=="wenzhong","battle uses the clicked enemy, not a fixed exhibition")
	check(battle.sim.hero_for(0).attributes.physical_defense==16,"map debuff is present in the real battle")
	await shot("07-field-battle")
	# A focused input fixture verifies R interrupts an active action in the real view.
	# Resource is set only here for this deterministic UI test, not in game code.
	await key(KEY_SPACE)
	var hero=battle.sim.hero_for(0)
	var enemy=battle.sim.hero_for(1)
	battle.sim.elapsed=battle.Rules.INTRO+.1
	hero.pos=Vector2(900,300)
	enemy.pos=Vector2(1000,300)
	battle.sim._begin(hero,enemy,"attack")
	hero.age=.1
	battle.sim.morale[0]=100
	await key(KEY_SPACE)
	await key(KEY_R)
	check(hero.action=="finisher" and battle.sim.morale[0]==0,"R immediately interrupts an active normal attack")
	await shot("08-ultimate-interrupt")
	await key(KEY_X)
	while battle.sim.result.is_empty() and battle.sim.elapsed<100: await process_frame
	check(not battle.sim.result.is_empty(),"real field combat reaches a result after interruption")
	if battle.sim.result.is_empty(): finish(); return
	var result: Dictionary=battle.sim.result.duplicate(true)
	while battle.result_age<1.4: await process_frame
	await shot("09-field-result")
	await key(KEY_ENTER)
	check(not is_instance_valid(game.battle) and game.world.pending_battle.is_empty(),"return action settles and closes the field encounter")
	check(game.world.units[0].soldiers==int(result.player_remaining) and game.world.units[1].soldiers==int(result.enemy_remaining),"both actual result strengths return to the map")
	await shot("10-map-after-battle")
	await click(Vector2(1790,977))
	check(game.world.units[0].soldiers==2400 and game.world.units[1].soldiers==2400,"end turn restores both armies after a full real battle")
	finish()

func finish() -> void:
	var report:={"checks":checks,"failures":failures,"heroes":["nezha","wenzhong"],"resolutions":[[1920,1080],[1280,720]],"focused_interrupt_fixture":true}
	FileAccess.open(output.path_join("runtime-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CHAOGE_RUNTIME "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
