extends SceneTree
const View=preload("res://scripts/battle_view.gd")
const Rules=preload("res://scripts/battle_rules.gd")
var checks:=0
var failures: Array[String]=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok and not label in failures: failures.append(label)

func check_troop_attack(view: View, side: int, kind: String) -> void:
	var soldier := Rules.Fighter.new()
	soldier.side = side
	soldier.troop_type = kind
	var enemy: Rules.Fighter = view.sim.sides[1 - side][1]
	var key := view.sprite_key(soldier)
	var image: Image = View.TEXTURES[key].get_image()
	var drawings := {}
	var poses := {}
	view.sim._begin(soldier, enemy, "attack")
	for step in ceili(soldier.duration / Rules.STEP) + 1:
		soldier.age = minf(soldier.duration, step * Rules.STEP)
		var pose := view.animation(soldier)
		if poses.has(pose): continue
		poses[pose] = true
		var frame: View.SpriteFrame = view.draw_frames[key][pose.y * 4 + pose.x]
		var pixels := image.get_region(Rect2i(frame.source)).get_data()
		drawings[hash(pixels)] = true
	check(poses.size() == 16 and drawings.size() == 16, "sixteen distinct normal attack drawings play at 60 Hz for " + key)
	soldier.age = soldier.impact - 0.001
	check(view.animation(soldier) == Vector2i(3,5), "frame eight is the last windup for " + key)
	soldier.age = soldier.impact
	check(view.animation(soldier) == Vector2i(0,6), "frame nine coincides with real contact for " + key)
	soldier.age = soldier.duration
	check(view.animation(soldier) == Vector2i(3,7), "recovery reaches frame sixteen for " + key)
	if kind != "cavalry": return
	poses.clear()
	soldier.action = "charge_run"
	for step in 32:
		soldier.stride = step * Rules.STEP
		poses[view.animation(soldier)] = true
	view.sim._begin(soldier, enemy, "charge_hit")
	for step in ceili(soldier.duration / Rules.STEP) + 1:
		soldier.age = minf(soldier.duration, step * Rules.STEP)
		poses[view.animation(soldier)] = true
	for pose: Vector2i in poses:
		var frame: View.SpriteFrame = view.draw_frames[key][pose.y * 4 + pose.x]
		var signature := hash(image.get_region(Rect2i(frame.source)).get_data())
		check(pose.y >= 8 and not drawings.has(signature), "charge uses its own gallop and contact drawings for " + key)
		drawings[signature] = true
	check(poses.size() == 16 and drawings.size() == 32, "sixteen charge poses are distinct from sixteen mounted attacks for " + key)
	soldier.age = soldier.impact
	check(view.animation(soldier) == Vector2i(3,10), "charge frame twelve coincides with bonus damage for " + key)

func _initialize() -> void:
	check(ProjectSettings.get_setting("display/window/size/window_width_override")==1920 and ProjectSettings.get_setting("display/window/size/window_height_override")==1080,"default output is native 1920x1080")
	check(ProjectSettings.get_setting("application/run/max_fps")==60 and is_equal_approx(Rules.STEP,1.0/60.0),"60fps presentation cap and 60Hz combat simulation")
	var view:=View.new()
	view.setup({"title":"layout","player":{"id":"nezha","name":"哪吒","soldiers":6000,"troops":Rules.mixed_roster(6000),"morale":80},"enemy":{"id":"wenzhong","name":"闻仲","soldiers":6000,"troops":Rules.mixed_roster(6000),"morale":75}})
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
	var frames_checked := 0
	for kind: String in view.draw_frames:
		var rows := int(view.frame_catalog[kind].rows)
		frames_checked += rows * 4
		var f:=Rules.Fighter.new()
		f.hero=kind=="general"
		f.side=1 if kind.begins_with("shang") else 0
		if kind.contains("_"): f.troop_type=kind.get_slice("_",1)
		view.sim.encounter.player.id="vanguard"
		for point in [Vector2(55,-25),Vector2(1865,-25),Vector2(55,740),Vector2(1865,740)]:
			f.pos=point
			for facing in [-1,1]:
				f.facing=facing
				for row in rows:
					for col in 4:
						var g:=view.sprite_geometry(f,Vector2i(col,row))
						check(View.ACTOR_SAFE_AREA.encloses(g.visible_bounds),"body, weapon and cape fit above HUD / within screen: "+kind)
						check(is_equal_approx(g.rect.size.x/g.source.size.x,g.rect.size.y/g.source.size.y),"no nonuniform stretching: "+kind)
						var cached: View.SpriteFrame=view.draw_frames[kind][row*4+col]
						var depth:=lerpf(.88,1.03,clampf((f.pos.y+25.0)/765.0,0,1))
						check(cached.source==g.source and (cached.rect.position*depth).is_equal_approx(g.rect.position) and (cached.rect.size*depth).is_equal_approx(g.rect.size),"compiled draw regions match inspected layout bounds: "+kind)
	view.sim.encounter.player.id="nezha"
	for side in 2:
		for kind in Rules.TYPES: check_troop_attack(view, side, kind)
	for i in 1000:
		view.sim.advance()
		view.sim.events.clear()
		if i%60!=0: continue
		for f in view.sim.fighters:
			check(View.FEET_AREA.grow(0.1).has_point(view.ground(f.pos)),"live crowd feet stay on the land rectangle")
	view.free()
	var report: Dictionary={"checks":checks,"failures":failures,"frames_checked":frames_checked,"facings":2,"battlefield_corners":4,"max_actors":122,"feet_area":[160,500,1600,300],"standard_body_heights":{"soldier":View.SOLDIER_HEIGHT,"cavalry":View.CAVALRY_HEIGHT,"hero":View.HERO_HEIGHT,"wenzhong":View.WENZHONG_HEIGHT}}
	FileAccess.open("res://previews/battle/layout-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BATTLE_LAYOUT "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
