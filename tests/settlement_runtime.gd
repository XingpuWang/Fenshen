extends "res://tests/runtime_check.gd"

# Representative capital: homes by northern lanes, farms beside the southwest
# gardens, shops at junctions, workshops and stores near the southern gate.
const LARGE_CITY_GALLERY=["granary","farm","farm","homes","market","barracks","farm","homes","homes","homes","market","forge","granary","homes","market","forge","granary","granary","forge","homes","homes","barracks","forge","market","drill","homes","market","lumber","lumber","homes","homes"]

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
	check(not game.layer.visible and not game.grid.visible,"covered world stops rendering behind the interior")
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
	check(game.interior.economy_display_cache.current==econ.yield_detail(capital.id,6),"upgrade invalidates the displayed yield cache")
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
	check(game.interior.economy_display_cache.income==econ.local_income("guanzhong_village_0"),"switching settlement refreshes local output")
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
	check(game.layer.visible and game.grid.visible==game.grid_visible and not game.terrain_overlay.visible,"return restores world visibility without enabling the terrain debug mask")
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
	# Exercise the five landscape templates and every clickable construction site.
	var profiles: Array=[["guanzhong_city_0","large-city"],["guanzhong_city_1","small-city"],["guanzhong_village_0","village"],["guanzhong_pass_1","pass"],["guanzhong_ferry_1","ferry"]]
	for k in profiles.size():
		var pid: String=profiles[k][0]
		var poi: Dictionary=w.by_poi[pid]
		poi.owner="player"
		for key in econ.KEYS: econ.treasury[key]=1000000
		game.open_settlement(pid)
		game.toast=""
		await shot(game,dir,"%02d-%s" % [12+k,profiles[k][1]])
		var original_positions: Dictionary=game.interior.plot_views.duplicate(true)
		await ui(game,"layout")
		check(game.interior.plot_views==original_positions,"layout toggle never moves buildings: "+pid)
		await ui(game,"layout")
		for i in econ.settlements[pid].plots.size():
			if game.interior.build_mode: await ui(game,"close_catalog")
			await ui(game,"plot:"+str(i))
			check(game.interior.selected_plot==i,"individual plot click reaches correct stable ID: %s/%d" % [pid,i])
			check(game.interior.plot_views==original_positions,"catalogue does not rearrange plots: %s/%d" % [pid,i])
			var plot: Dictionary=econ.settlements[pid].plots[i]
			if plot.building.is_empty():
				while not econ.settlements[pid].jobs.is_empty(): w.next_turn()
				var building: String=["farm","lumber","mine","market","jade"][int(plot.terrain)]
				if econ.layout_kind(poi)=="city_large": building=LARGE_CITY_GALLERY[i]
				check(econ.build(poi,i,building,w.by_poi).is_empty(),"full-capacity construction succeeds: %s/%d" % [pid,i])
				w.next_turn()
		if game.interior.build_mode: await ui(game,"close_catalog")
		game.interior.selected_plot=0
		game.toast=""
		game.refresh()
		await shot(game,dir,"%02d-%s-developed" % [17+k,profiles[k][1]])
		check(game.interior.plot_views==original_positions,"full development preserves natural layout: "+pid)
		for i in econ.settlements[pid].plots.size():
			var point: Vector2=game.interior.plot_views[i].position+Vector2(0,19)
			check(game.interior.hit_test(point).get("id","")=="plot:"+str(i),"developed nameplate remains individually accessible: %s/%d" % [pid,i])
		await ui(game,"back")
	# A battle can follow an interior; both full-screen views share world coverage.
	game.open_settlement(capital.id)
	game.start_exhibition()
	check(is_instance_valid(game.battle) and not game.layer.visible,"battle entered from interior keeps world covered")
	game.close_battle({})
	await settle(game)
	check(game.hud.visible and game.layer.visible and game.covered_world_visibility.is_empty(),"battle return restores the world after interior coverage")
	var report: Dictionary={"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_video_adapter_name(),"checks":checks,"failures":failures,"captures":21}
	FileAccess.open(dir.path_join("settlement-runtime-tests.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SETTLEMENT_RUNTIME "+JSON.stringify(report))
	game.get_tree().quit(0 if failures.is_empty() else 1)
