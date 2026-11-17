extends SceneTree
const View=preload("res://scripts/battle_view.gd")
const Rules=preload("res://scripts/battle_rules.gd")
var checks:=0
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok and not label in failures: failures.append(label)
func _initialize() -> void:
	check(ProjectSettings.get_setting("display/window/size/window_width_override")==1920 and ProjectSettings.get_setting("display/window/size/window_height_override")==1080,"default output is native 1920x1080")
	check(ProjectSettings.get_setting("application/run/max_fps")==60 and is_equal_approx(Rules.STEP,1.0/60.0),"60fps presentation cap and 60Hz combat simulation")
	var view:=View.new()
	view.setup({"title":"layout","player":{"id":"nezha","name":"哪吒","soldiers":6000,"morale":80},"enemy":{"id":"wenzhong","name":"闻仲","soldiers":6000,"morale":75}})
	# Land horizon measured at source y=560 of the 941px background, including camera framing.
	var land_top:=View.BACKDROP.position.y+560.0/941.0*View.BACKDROP.size.y
	check(View.FEET_AREA.position.y-16>land_top,"all feet and shadows stay below the actual backdrop land horizon")
	for key in view.frame_catalog:
		var entry: Dictionary=view.frame_catalog[key]
		for frame in entry.frames:
			var src: Array=frame.source
			var visible: Array=frame.opaque
			check(visible[0]>0 and visible[1]>0 and visible[0]+visible[2]<src[2] and visible[1]+visible[3]<src[3],"complete silhouettes have transparent gutters: "+key)
	# Both facings, every animation frame, all four battlefield corners, every character type.
	# The variable-sized hero atlases are exercised in nezha_check / wenzhong_check.
	for kind in ["zhou","shang","general"]:
		var f:=Rules.Fighter.new()
		f.hero=not kind in ["zhou","shang"]
		f.side=1 if kind in ["shang","wenzhong"] else 0
		view.sim.encounter.player.id="nezha" if kind=="nezha" else "vanguard"
		for point in [Vector2(55,-25),Vector2(1865,-25),Vector2(55,740),Vector2(1865,740)]:
			f.pos=point
			for facing in [-1,1]:
				f.facing=facing
				for row in (6 if f.hero else 5):
					for col in 4:
						var g:=view.sprite_geometry(f,Vector2i(col,row))
						check(View.ACTOR_SAFE_AREA.encloses(g.visible_bounds),"body, weapon and cape fit above HUD / within screen: "+kind)
						check(is_equal_approx(g.rect.size.x/g.source.size.x,g.rect.size.y/g.source.size.y),"no nonuniform stretching: "+kind)
						var cached: View.SpriteFrame=view.draw_frames[kind][row*4+col]
						var depth:=lerpf(.88,1.03,clampf((f.pos.y+25.0)/765.0,0,1))
						check(cached.source==g.source and (cached.rect.position*depth).is_equal_approx(g.rect.position) and (cached.rect.size*depth).is_equal_approx(g.rect.size),"compiled draw regions match inspected layout bounds: "+kind)
	view.sim.encounter.player.id="nezha"
	for i in 1000:
		view.sim.advance()
		view.sim.events.clear()
		if i%60!=0: continue
		for f in view.sim.fighters:
			check(View.FEET_AREA.grow(0.1).has_point(view.ground(f.pos)),"live crowd feet stay on the land rectangle")
	view.free()
	var report: Dictionary={"checks":checks,"failures":failures,"frames_checked":64,"facings":2,"battlefield_corners":4,"max_actors":122,"feet_area":[160,500,1600,300],"standard_body_heights":{"soldier":108,"hero":180,"wenzhong":194}}
	FileAccess.open("res://previews/battle/layout-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BATTLE_LAYOUT "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
