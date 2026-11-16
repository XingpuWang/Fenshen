extends "res://tests/battle_runtime.gd"

func run(game: Node, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	game.get_window().size=Vector2i(1920,1080)
	await get_tree().process_frame
	await shot(game,dir,"01-four-skills-and-stats")
	var unit: Dictionary=game.world.units[0]
	var ap:=int(unit.ap)
	key(KEY_Q)
	await get_tree().process_frame
	check(game.map_skill_targeting and not game.skill_range_cells.is_empty(),"Q starts map spell targeting with visible range")
	game.cast_selected_map_skill(-1)
	check(game.map_skill_targeting and unit.ap==ap,"invalid target stays in targeting and preserves action")
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not game.map_skill_targeting and unit.ap==ap,"Esc cancels without spending action")
	# Put the real selected army on a legal land neighbor of an actual enemy.
	var poi: Dictionary={}
	for p in game.world.pois:
		if p.owner!="shang": continue
		for ci in p.cells:
			for adjacent in game.world.cells[int(ci)].n:
				if game.world.walkable(int(adjacent)) and not game.world.occupied(int(adjacent),unit.id):
					unit.cell=int(adjacent)
					if game.world.can_capture(unit,p): poi=p; break
			if not poi.is_empty(): break
		if not poi.is_empty(): break
	game.unit_nodes[0].position=game.world.center(unit.cell)
	game.action("focus")
	game.refresh()
	await get_tree().process_frame
	key(KEY_Q)
	await get_tree().process_frame
	var target:=int(poi.cells[0])
	game.hover_cell=target
	game.update_skill_preview()
	await shot(game,dir,"02-aoe-range-and-preview")
	var before:=int(game.world.garrison(poi).soldiers)
	click(game,game.world_to_screen(game.world.center(target)))
	await get_tree().process_frame
	check(not game.map_skill_targeting and unit.ap==0 and unit.action_done,"real left click casts and completes army action")
	check(game.world.garrison(poi).soldiers<before and not game.interior.visible,"AOE hit does not accidentally enter settlement")
	await shot(game,dir,"03-aoe-completes-action")
	key(KEY_Q)
	await get_tree().process_frame
	check(not game.map_skill_targeting,"spent unit cannot reopen targeting")
	key(KEY_E)
	await get_tree().process_frame
	check(not unit.action_done and unit.ap==unit.max_ap,"E refreshes round action")
	key(KEY_2)
	await get_tree().process_frame
	var ally: Dictionary=game.world.units[1]
	var attack_before:=float(game.world.Catalog.effective_stats(ally).physical_attack)
	key(KEY_Q)
	await get_tree().process_frame
	click(game,game.world_to_screen(game.world.center(ally.cell)))
	await get_tree().process_frame
	check(ally.action_done and game.world.Catalog.effective_stats(ally).physical_attack==attack_before+12,"second hero casts a real army buff")
	await shot(game,dir,"04-buff-and-effective-stats")
	key(KEY_3)
	await get_tree().process_frame
	var healer: Dictionary=game.world.units[2]
	var wounded:=int(healer.soldiers)
	key(KEY_Q)
	await get_tree().process_frame
	click(game,game.world_to_screen(game.world.center(healer.cell)))
	await get_tree().process_frame
	check(healer.action_done and healer.soldiers>wounded,"third hero restores soldiers through actual input")
	await shot(game,dir,"05-heal-and-completed-action")
	key(KEY_B)
	await get_tree().process_frame
	check(is_instance_valid(game.battle) and game.battle.sim.morale[0]==50,"battle opens at fixed 50 morale")
	check(game.battle.skill_name(0)=="攒心钉" and game.battle.finisher_name(0)=="神火破邪","battle HUD uses selected hero kit")
	key(KEY_SPACE)
	await shot(game,dir,"06-selected-hero-battle-kit")
	var report: Dictionary={"checks":checks,"failures":failures,"resolution":[1920,1080]}
	FileAccess.open(dir.path_join("ui-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SKILLS_RUNTIME "+JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
