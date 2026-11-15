extends "res://tests/runtime_check.gd"

func ui(game: Node,id: String) -> void:
	if id.begins_with("settlement:") and not game.interior.settlement_menu:
		await ui(game,"settlements")
	await settle(game,2)
	for hit in game.interior.hits:
		if hit.id==id:
			check(bool(hit.enabled),"UI enabled: "+id)
			await click(game,hit.rect.get_center())
			return
	check(false,"UI hit exists: "+id)

func run(game: Node,dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await settle(game,8)
	var w=game.world
	var econ=w.economy
	var capital: Dictionary=w.by_poi.guanzhong_city_0
	await shot(game,dir,"01-xiqi-campaign")
	# Enter through the actual world HUD, then place a building through actual clicks.
	await click(game,Vector2(1710,290))
	check(game.interior.visible and game.interior.poi_id==capital.id,"world capital button opens independent settlement scene")
	await ui(game,"plot:6")
	await ui(game,"blueprint:farm")
	await shot(game,dir,"02-xiqi-building-preview")
	var wood_before: int=int(econ.treasury.wood)
	await ui(game,"build")
	check(econ.settlements[capital.id].jobs.size()==1 and int(econ.treasury.wood)==wood_before-100,"UI construction spends shared resources")
	await ui(game,"end_turn")
	check(econ.settlements[capital.id].plots[6].building=="farm" and econ.settlements[capital.id].plots[6].level==1,"UI end-turn completes farm")
	await ui(game,"build")
	await ui(game,"end_turn")
	check(econ.settlements[capital.id].plots[6].level==1,"upgrade remains at old level before completion")
	await ui(game,"end_turn")
	check(econ.settlements[capital.id].plots[6].level==2,"two-turn upgrade completes through UI")
	await shot(game,dir,"03-upgraded-farm")
	await ui(game,"landmark:lingtai")
	await ui(game,"restore")
	await ui(game,"end_turn")
	await ui(game,"end_turn")
	check(econ.settlements[capital.id].landmarks.lingtai,"landmark restoration completes through UI")
	await shot(game,dir,"04-lingtai-restored")
	# Place a valid nearby unit fixture to exercise the reinforcement button itself.
	var nearby_unit: Dictionary=w.units[0]
	nearby_unit.cell=int(capital.cells[0])
	game.unit_nodes[0].position=w.center(int(nearby_unit.cell))
	game.refresh()
	var strength_before: int=int(nearby_unit.soldiers)
	await ui(game,"recruit")
	check(int(nearby_unit.soldiers)==strength_before+500,"reinforcement button updates actual army strength")
	var cap_plots: String=JSON.stringify(econ.settlements[capital.id].plots)
	await ui(game,"settlement:guanzhong_village_0")
	check(game.interior.poi_id=="guanzhong_village_0","owned-settlement switcher opens village")
	await ui(game,"plot:4")
	await ui(game,"blueprint:lumber")
	var gold_before: int=int(econ.treasury.gold)
	await ui(game,"build")
	check(econ.treasury.gold==gold_before-140 and JSON.stringify(econ.settlements[capital.id].plots)==cap_plots,"village consumes same treasury without changing capital plots")
	await shot(game,dir,"05-village-construction")
	# Save a live project, move time forward, then restore it with the actual top bar.
	await ui(game,"save")
	var saved_turn: int=w.turn
	await ui(game,"end_turn")
	await ui(game,"load")
	check(w.turn==saved_turn and econ.settlements.guanzhong_village_0.jobs.size()==1,"UI save/load restores pending project and turn")
	await ui(game,"settlement:guanzhong_ferry_1")
	await shot(game,dir,"06-ferry-interior")
	await ui(game,"back")
	check(not game.interior.visible and game.hud.visible,"back returns to world HUD")
	# Actual map click opens an enemy pass; economic actions are not offered.
	var gate: Dictionary=w.by_poi.guanzhong_pass_1
	game.camera.position=Vector2(gate.position[0],gate.position[1])+Vector2(0,150)
	game.camera.force_update_scroll()
	await settle(game)
	await click(game,game.world_to_screen(Vector2(gate.position[0],gate.position[1])))
	check(game.interior.visible and game.interior.poi_id==gate.id,"map click opens pass interior")
	var forbidden: bool=false
	for hit in game.interior.hits:
		if hit.id in ["build","restore","demolish"] and hit.enabled: forbidden=true
	check(not forbidden,"enemy pass cannot build or upgrade through UI")
	await shot(game,dir,"07-sishui-pass")
	await ui(game,"approach_here")
	check(not game.interior.visible and (game.path.size()>1 or w.can_capture(w.units[game.selected_unit],gate)),"interior approach keeps world route instead of clearing it on refresh")
	game.select_unit(0)
	game.action("end_turn")
	game.travel_speed=.15
	var u: Dictionary=w.units[0]
	var target: int=-1
	for ci in game.reachable.dist:
		if int(game.reachable.dist[ci])==2 and str(w.cells[ci].p).is_empty():
			var point: Vector2=game.world_to_screen(w.center(ci))
			if Rect2(440,240,1000,470).has_point(point) and game.poi_at(w.center(ci)).is_empty():
				target=ci
				break
	check(target>=0,"army still has reachable open land after economy actions")
	if target>=0:
		await click(game,game.world_to_screen(w.center(target)))
		check(game.path.size()>1,"map route preview still works")
		await click(game,Vector2(1085,983))
		var frames: int=0
		while game.moving and frames<600:
			await game.get_tree().process_frame
			frames+=1
		check(u.cell==target and int(u.ap)==int(u.max_ap)-2,"army movement and economy coexist")
	await shot(game,dir,"08-return-to-campaign")
	# Reference-style presentation checks, using actual completed construction.
	for kind in ["city","village","pass","ferry"]:
		var chosen: String=""
		for p in w.pois:
			if p.type==kind and p.region=="guanzhong":
				chosen=p.id
				break
		game.open_settlement(chosen)
		await ui(game,"layout")
		await settle(game)
		check(game.interior.plot_views.size()==econ.settlements[chosen].plots.size(),"all stable plot IDs exposed by layout: "+kind)
		await ui(game,"layout")
		await ui(game,"back")
	var village: Dictionary=w.by_poi.guanzhong_village_0
	var pass_poi: Dictionary=w.by_poi.guanzhong_pass_1
	pass_poi.owner="player"
	for key in econ.KEYS: econ.treasury[key]=20000
	for fixture in [[village,[[2,"homes"],[3,"market"],[5,"granary"],[6,"jade"],[7,"farm"]]],[pass_poi,[[2,"forge"],[4,"mine"],[6,"granary"],[7,"market"],[8,"homes"],[9,"lumber"]]]]:
		var p: Dictionary=fixture[0]
		for placement in fixture[1]:
			var idx: int=int(placement[0])
			while not econ.settlements[p.id].jobs.is_empty(): w.next_turn()
			if econ.settlements[p.id].plots[idx].building.is_empty():
				check(econ.build(p,idx,placement[1],w.by_poi).is_empty(),"gallery construction succeeds: "+placement[1])
				w.next_turn()
		game.open_settlement(p.id)
		game.interior.selected_plot=5 if p.type=="village" else 0
		game.toast=""
		game.refresh()
		await shot(game,dir,"09-developed-village" if p.type=="village" else "10-developed-pass")
		await ui(game,"back")
	game.open_settlement(capital.id)
	game.interior.selected_plot=4
	game.toast=""
	await shot(game,dir,"11-city-overview")
	await ui(game,"links")
	check(game.interior.show_links,"collaboration overlay toggles through toolbar")
	await ui(game,"zoom_in")
	check(game.interior.view_zoom>1.0,"interior zoom control works")
	await ui(game,"reset_view")
	check(game.interior.view_zoom==1.0 and game.interior.view_pan==Vector2.ZERO,"interior view resets")
	await ui(game,"back")
	var report: Dictionary={"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_video_adapter_name(),"checks":checks,"failures":failures,"captures":11}
	FileAccess.open(dir.path_join("settlement-runtime-tests.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SETTLEMENT_RUNTIME "+JSON.stringify(report))
	game.get_tree().quit(0 if failures.is_empty() else 1)
