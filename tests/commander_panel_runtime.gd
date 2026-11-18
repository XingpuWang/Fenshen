extends SceneTree
## Exercise real HUD hover/input and preserve the three roster-slot positions.
const Commander=preload("res://scripts/commander_panel.gd")
var game: Node2D
var checks:=0
var failures: Array[String]=[]
var output:="res://previews/commander-panel/skills-and-formations"

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

func hover(point: Vector2) -> void:
	var event:=InputEventMouseMotion.new()
	event.position=point*Vector2(root.size)/Vector2(1920,1080)
	Input.parse_input_event(event)
	await settle()

func click(point: Vector2) -> void:
	await hover(point)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.position=point*Vector2(root.size)/Vector2(1920,1080)
		event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
	await settle()

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new()
		event.physical_keycode=code
		event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
	await settle()

func shot(name: String,panel: bool=false) -> void:
	await settle()
	var screenshot:=root.get_texture().get_image()
	screenshot.save_png(output.path_join(name+".png"))
	if panel: screenshot.get_region(Rect2i(Commander.RECT.grow(2))).save_png(output.path_join(name+"-panel.png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1920,1080)
	game=load("res://scenes/main.tscn").instantiate()
	game.start_in_test_scenario=false
	root.add_child(game)
	await settle(8)
	game.toast=""
	game.refresh()
	await settle()
	var original: Array=game.world.units[0].troops.duplicate(true)
	check(game.hud.commander_formations.size()==3,"all three formation rows are displayed")
	check(Commander.SKILL_SLOTS.size()==4 and Commander.SKILL_SLOTS[3]=="passive","four skill slots include the passive")
	check(Commander.ARTIFACT_SLOTS==4,"artifact capacity is four")
	for i in Commander.ARTIFACT_SLOTS:
		check(Commander.RECT.encloses(Commander.artifact_rect(i)),"all artifact slots fit inside the panel")
		if i>0: check(not Commander.artifact_rect(i).intersects(Commander.artifact_rect(i-1)),"artifact slots do not overlap")
	check(Commander.skill_rect(3).end.y<568,"extended skill section clears the formations heading")
	for i in 3:
		var row: Dictionary=game.hud.commander_formations[i]
		check(row.name==["戟兵","弓兵","骑兵"][i] and row.count==str(original[i].count),"starting formation displays each troop type and its strength")
	await shot("01-three-formations-and-skills",true)
	# Legal rosters may have holes. Do not compact their displayed slot numbers.
	for occupied in [1,2]:
		var roster: Array=[{},{},{}]
		roster[occupied]={"type":"halberd","count":5200}
		game.world.units[0].troops=roster
		game.refresh()
		await settle()
		check(game.world.BattleRules.valid_roster(roster,5200),"sparse roster fixture remains legal")
		for i in 3:
			var row: Dictionary=game.hud.commander_formations[i]
			check(row.label=="编队%d" % (i+1),"formation labels retain their slot positions")
			check(row.count==("5200" if i==occupied else ""),"occupied formation stays in its original row")
			if i!=occupied: check(row.name=="","unoccupied formation name stays blank")
		if occupied==2: await shot("02-sparse-third-formation",true)
	game.world.units[0].troops=original
	game.refresh()
	await settle()
	for hero_index in 3:
		await key([KEY_1,KEY_2,KEY_3][hero_index])
		var unit: Dictionary=game.world.units[hero_index]
		for index in Commander.SKILL_SLOTS.size():
			var slot: String=Commander.SKILL_SLOTS[index]
			var ability: Dictionary=game.world.Catalog.skill(unit,slot)
			await hover(Commander.skill_rect(index).get_center())
			var tooltip: Dictionary=game.hud.commander_tooltip
			check(not tooltip.is_empty(),"real pointer hover opens the skill tooltip")
			if tooltip.is_empty(): continue
			check(tooltip.id==ability.id and tooltip.name==ability.name,"tooltip follows the selected hero and skill")
			check(not tooltip.description.is_empty() and not tooltip.details.is_empty(),"every skill has a description and gameplay details")
			if ability.has("description"): check(tooltip.description==ability.description,"authored skill description is preserved")
			check(Rect2(0,78,1920,1002).encloses(tooltip.rect),"skill tooltip stays inside the logical viewport")
			var before:=JSON.stringify([game.world.units,game.world.turn,game.path,game.map_skill_targeting])
			await click(Commander.skill_rect(index).get_center())
			if slot=="map":
				check(game.map_skill_targeting and not unit.action_done,"map icon starts targeting without spending the action")
				await key(KEY_ESCAPE)
				await hover(Commander.skill_rect(index).get_center())
			else: check(JSON.stringify([game.world.units,game.world.turn,game.path,game.map_skill_targeting])==before,"battle and passive icons inspect without clicking through to the map")
			if hero_index==0: await shot("03-nezha-"+slot+"-tooltip")
			if hero_index==1 and index==2: await shot("04-nangongshi-tooltip")
			if hero_index==2 and index==2: await shot("05-huangtianhua-tooltip")
	# Switching units under a stationary pointer must refresh the open description.
	await key(KEY_1)
	check(game.hud.commander_tooltip.get("id","")=="three_heads_six_arms","keyboard selection updates the passive tooltip beneath a stationary pointer")
	await hover(Vector2(880,700))
	check(game.hud.commander_tooltip.is_empty(),"tooltip disappears on leaving the skill card")
	await hover(Commander.skill_rect(1).get_center())
	root.emit_signal("mouse_exited")
	await settle()
	check(game.hud.commander_tooltip.is_empty(),"tooltip clears when the pointer leaves the window")
	root.size=Vector2i(1280,720)
	await settle(8)
	await hover(Commander.skill_rect(1).get_center())
	check(game.hud.commander_tooltip.get("id","")=="samadhi","skill hover tracks canvas scaling at 1280 by 720")
	await shot("06-window-1280x720-tooltip")
	var report:={"checks":checks,"failures":failures,"heroes":3,"skill_tooltips":12,"artifact_slots":4,"formation_slots":3,"resolutions":[[1920,1080],[1280,720]],"sparse_rosters_preserved":true}
	FileAccess.open(output.path_join("runtime-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COMMANDER_PANEL_RUNTIME "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
