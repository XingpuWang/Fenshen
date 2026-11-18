extends SceneTree
const Art=preload("res://scripts/wenzhong_art.gd")
const View=preload("res://scripts/battle_view.gd")
const Rules=preload("res://scripts/battle_rules.gd")
const Game=preload("res://scripts/game.gd")
var checks:=0
var failures: Array[String]=[]

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok and not label in failures: failures.append(label)

func fixture(side: int=0) -> Rules:
	var left: String="wenzhong" if side==0 else "nezha"
	var right: String="nezha" if side==0 else "wenzhong"
	var sim:=Rules.new({"title":"Wen Zhong timing","player":{"id":left,"name":left,"soldiers":1000},"enemy":{"id":right,"name":right,"soldiers":1000}})
	sim.elapsed=Rules.INTRO
	sim.morale.assign([0.0,0.0])
	for f in sim.fighters:
		f.cooldown=9999
		f.skill_clock=9999
	var hero:=sim.hero_for(side)
	var target:=sim.hero_for(1-side)
	hero.pos=Vector2(1000,300)
	target.pos=Vector2(1100,300)
	target.hp=10000
	target.max_hp=10000
	return sim

func _initialize() -> void:
	Art.prepare()
	for sheet in ["actions","attack","thunder_whip","nine_thunders"]:
		var metadata: Dictionary=Art.DATA.sheets[sheet]
		var texture: Texture2D=Art.sheets[sheet][0].texture
		check(texture.get_size()==Vector2(metadata["size"][0],metadata["size"][1]),"loaded actor artwork matches its registered dimensions: "+sheet)
		var settings:=ConfigFile.new()
		check(settings.load("res://"+metadata.path+".import")==OK and settings.get_value("params","mipmaps/generate",false),"small-scale actor filtering has mipmaps: "+sheet)
	var guard:=Art.frame_number("idle",0)
	var guard_height:=guard.visible.size.y / guard.body_height
	for clip in ["attack","thunder_whip","nine_thunders","thunder_seal"]:
		for endpoint in [0,15]:
			var f:=Art.frame_number(clip,endpoint)
			check(absf(f.visible.size.y/f.body_height-guard_height)<.07,"action enters and leaves the resting guard at matching scale: "+clip)
	var count:=0
	for clip in Art.DATA.clips:
		var entry: Dictionary=Art.DATA.clips[clip]
		if clip not in ["idle","run","hit","defeat"]: check(entry.frames.size()==16,"sixteen authored frames: "+clip)
		for i in entry.frames.size():
			count+=1
			var f:=Art.frame_number(clip,i)
			check(f.texture!=null and Rect2(Vector2.ZERO,f.texture.get_size()).encloses(f.source),"frame stays within source texture: "+clip)
			check(f.source.size.x>0 and f.source.size.y>0 and f.visible.size.x>0 and f.visible.size.y>0,"frame has visible artwork: "+clip)
			if str(clip).ends_with("_fx"): continue
			if clip not in ["run","hit","defeat"]:
				check(absf(f.visible.end.y-f.pivot.y)<f.body_height*.015,"grounded soles stay registered through the full action: "+clip)
			for point in [Vector2(55,-25),Vector2(1865,-25),Vector2(55,740),Vector2(1865,740)]:
				var at:=View.FEET_AREA.position+Vector2(point.x/1920,(point.y+25)/765)*View.FEET_AREA.size
				var height:=View.WENZHONG_HEIGHT*lerpf(.88,1.03,clampf((point.y+25)/765,0,1))
				for facing in [-1,1]:
					var g:=Art.geometry(f,at,height,facing)
					check(View.ACTOR_SAFE_AREA.encloses(g.visible_bounds),"silhouette fits battlefield in both facings: %s frame %d" % [clip,i])
	check(count==144,"all actor and VFX timeline frames sampled")
	check(Art.DATA.portrait!=Art.DATA.sheets.actions.path,"portrait is independent from battle animation")
	for side in 2:
		for pair in [["attack","attack"],["cast","thunder_whip"],["finisher","nine_thunders"]]:
			var sim:=fixture(side)
			var hero:=sim.hero_for(side)
			var target:=sim.hero_for(1-side)
			sim._begin(hero,target,pair[0])
			check(is_equal_approx(hero.duration,Art.duration(pair[1])),"actor clip matches existing recovery time: "+pair[1])
			check(is_equal_approx(hero.impact,Art.event_time(pair[1],"impact")),"actor contact matches existing damage time: "+pair[1])
			check(Art.frame_index(pair[1],hero.impact)==(8 if pair[0]=="attack" else 10),"contact lands on authored strike pose: "+pair[1])
			var before_steps:=ceili(hero.impact/Rules.STEP)-1
			for i in before_steps: sim.advance()
			check(target.hp==10000,"no damage during anticipation on side %d: %s" % [side,pair[1]])
			sim.advance()
			check(target.hp<10000,"impact applies damage on side %d: %s" % [side,pair[1]])
			var hp_after:=target.hp
			for i in ceili((hero.duration-hero.impact)/Rules.STEP): sim.advance()
			check(target.hp==hp_after,"sixteen drawing frames do not repeat damage: "+pair[1])
			if pair[0]!="attack":
				check(is_equal_approx(Art.event_time(pair[1],"impact")-Art.event_time(pair[1],"charge_start"),Art.event_time(pair[1]+"_fx","impact")),"continuous charge / burst effect matches damage: "+pair[1])
		for phase in ["attack","cast"]:
			var sim:=fixture(side)
			var hero:=sim.hero_for(side)
			var target:=sim.hero_for(1-side)
			sim._begin(hero,target,phase)
			hero.age=.15
			sim.morale[side]=100
			check(sim.use_finisher(side) and hero.action=="finisher" and hero.age==0,"ultimate immediately cancels Wen Zhong "+phase)
			check(sim.morale[side]==0,"ultimate spends morale once")
			for i in 77: sim.advance()
			check(target.hp==10000,"cancelled contact never lands during new ultimate windup")
			sim.advance()
			check(target.hp<10000 and sim.stats.finishers==1,"replacement ultimate resolves once")
	check(is_equal_approx(Art.event_time("attack","impact")-Art.event_time("attack","arc_start"),Art.event_time("attack_fx","impact")),"baton arc contact aligns with physical hit")
	check(is_equal_approx(Art.event_time("thunder_seal","release"),Game.MAP_CAST_RELEASE),"map actor releases on the existing cast timeline")
	check(is_equal_approx(Game.MAP_CAST_RELEASE+Art.event_time("thunder_seal_fx","impact"),Game.MAP_CAST_IMPACT),"map lightning impact aligns with the actual debuff")
	check(Game.MAP_CAST_RELEASE+Art.duration("thunder_seal_fx")<=Game.MAP_CAST_END,"map effect completes before the cast unlocks")
	var view:=View.new()
	view.sim=fixture()
	var hero:=view.sim.hero_for(0)
	for phase in ["attack","cast","finisher"]:
		view.sim._begin(hero,view.sim.hero_for(1),phase)
		hero.age=.2
		check(view.wenzhong_pose(hero).clip=={"attack":"attack","cast":"thunder_whip","finisher":"nine_thunders"}[phase],"live view selects the separate new actor clip: "+phase)
		check(view.sprite_geometry(hero,Vector2i.ZERO).key=="wenzhong","live view uses registered Wen Zhong geometry")
	view.free()
	var report:={"checks":checks,"failures":failures,"sampled_frames":count,"facings":2,"battlefield_corners":4,"damage_sides":2,"balance_changes":false}
	DirAccess.make_dir_recursive_absolute("res://previews/wenzhong/v1")
	FileAccess.open("res://previews/wenzhong/v1/rules-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("WENZHONG_CHECK "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
