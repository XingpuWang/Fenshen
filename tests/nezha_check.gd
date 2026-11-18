extends SceneTree
const Rules=preload("res://scripts/battle_rules.gd")
const Art=preload("res://scripts/nezha_art.gd")
const View=preload("res://scripts/battle_view.gd")
var checks:=0
var failures: Array[String]=[]

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok and not label in failures: failures.append(label)

func fixture() -> Rules:
	var sim:=Rules.new({"title":"哪吒规则验证","player":{"id":"nezha","soldiers":1000},"enemy":{"id":"wenzhong","soldiers":1000}})
	sim.elapsed=Rules.INTRO
	for f in sim.fighters:
		f.cooldown=9999
		f.skill_clock=9999
	var hero:=sim.hero_for(0)
	var target:=sim.hero_for(1)
	hero.pos=Vector2(1000,300)
	target.pos=Vector2(1100,300)
	target.hp=10000
	target.max_hp=10000
	return sim

func _initialize() -> void:
	var sim:=fixture()
	var hero:=sim.hero_for(0)
	var target:=sim.hero_for(1)
	sim._begin(hero,target,"attack")
	for i in 16: sim.advance()
	check(target.hp==10000,"normal attack causes no damage before contact")
	sim.advance()
	var first_hp:=target.hp
	check(first_hp<10000 and hero.normal_hits==1,"first spear strike lands on frame 6 at 0.27 seconds")
	for i in 10: sim.advance()
	check(target.hp==first_hp,"second strike does not land early")
	sim.advance()
	check(target.hp<first_hp and hero.normal_hits==2 and sim.burn_stacks(target)==0,"second strike lands on frame 10 at 0.465 seconds without early burn")
	sim._begin(hero,target,"attack")
	for i in 17: sim.advance()
	check(hero.normal_hits==3 and sim.burn_stacks(target)==1,"third successful contact adds one burn")
	target.pos=Vector2(1800,700)
	sim._begin(hero,target,"attack")
	for i in 29: sim.advance()
	check(hero.normal_hits==3,"missed or out-of-range strikes do not advance burn counter")
	check_splash()
	# Projectile release and the impact must follow simulation time, not draw FPS.
	sim=fixture(); hero=sim.hero_for(0); target=sim.hero_for(1)
	sim._begin(hero,target,"cast")
	for i in 21: sim.advance()
	check(not hero.released and target.hp==10000,"Qiankun waits for the release pose")
	sim.advance()
	check(hero.released and target.hp==10000,"Qiankun releases at 0.36 seconds without early impact")
	for i in 14: sim.advance()
	check(target.hp==10000,"Qiankun does not hit before reaching the far point")
	sim.advance()
	check(target.hp<10000 and sim.burn_stacks(target)==1,"Qiankun hits and burns at 0.61 seconds")
	for i in 26: sim.advance()
	check(sim.events.filter(func(e: Dictionary) -> bool: return e.kind=="ring").size()==1,"one cast emits exactly one returning ring")
	sim=fixture(); hero=sim.hero_for(0); target=sim.hero_for(1)
	sim._begin(hero,target,"finisher")
	for i in 50: sim.advance()
	check(target.hp==10000,"ultimate does not deal damage during the windup")
	sim.advance()
	check(target.hp<10000,"ultimate lands on the 0.84-second impact frame")
	# Reapplication caps at three and refreshes duration without delaying a tick.
	sim=fixture(); hero=sim.hero_for(0); target=sim.hero_for(1)
	sim.apply_burn(hero,target)
	for i in 30: sim._advance_burns()
	var tick: float=target.burns[hero.id].tick
	for i in 5: sim.apply_burn(hero,target)
	check(sim.burn_stacks(target)==3 and is_equal_approx(target.burns[hero.id].remaining,4),"burn cap is three and reapplication refreshes four-second expiry")
	check(is_equal_approx(tick,target.burns[hero.id].tick),"reapplication preserves next tick time")
	for i in 29: sim._advance_burns()
	check(target.hp==10000,"burn never ticks before one second")
	sim._advance_burns()
	var per_stack:=Rules.Catalog.damage(hero.attributes,target.attributes,"magic",.12)
	check(is_equal_approx(10000-target.hp,per_stack*3),"three stacks tick as mitigated magic damage")
	check(target.velocity==Vector2.ZERO and target.hit_age==99,"burn does not repeatedly knock back or interrupt animation")
	sim=fixture(); hero=sim.hero_for(0); target=sim.hero_for(1)
	sim.apply_burn(hero,target)
	for i in 240: sim._advance_burns()
	check(sim.burn_stacks(target)==0 and is_equal_approx(10000-target.hp,per_stack*4),"four ticks then burn expires exactly at four seconds")
	var expired_hp:=target.hp
	for i in 120: sim._advance_burns()
	check(target.hp==expired_hp,"expired burn deals no more damage")
	sim.apply_burn(hero,hero)
	sim.apply_burn(target,hero)
	check(sim.burn_stacks(hero)==0,"burn is restricted to Nezha against hostile living targets")
	# Qiankun hits the forward corridor, including more than one enemy.
	sim=fixture(); hero=sim.hero_for(0); target=sim.hero_for(1)
	var behind: Rules.Fighter=sim.sides[1][1]
	var outside: Rules.Fighter=sim.sides[1][2]
	var farther: Rules.Fighter=sim.sides[1][3]
	behind.pos=hero.pos-Vector2(100,0)
	outside.pos=hero.pos+Vector2(200,120)
	farther.pos=hero.pos+Vector2(300,0)
	sim._begin(hero,target,"cast")
	sim._resolve_attack(hero)
	check(sim.burn_stacks(target)==1 and sim.burn_stacks(farther)==1,"Qiankun pierces multiple enemies ahead")
	check(sim.burn_stacks(behind)==0 and sim.burn_stacks(outside)==0,"Qiankun excludes enemies behind or outside the corridor")
	sim=fixture(); hero=sim.hero_for(0); target=sim.hero_for(1)
	hero.facing=-1
	target.pos=hero.pos-Vector2(100,0)
	behind=sim.sides[1][1]; behind.pos=hero.pos+Vector2(100,0)
	sim._begin(hero,target,"cast")
	sim._resolve_attack(hero)
	check(sim.burn_stacks(target)==1 and sim.burn_stacks(behind)==0,"left-facing Qiankun uses the same directional hit rules")
	# Three stacks are consumed once; targets outside the impact radius retain them.
	sim=fixture(); hero=sim.hero_for(0); target=sim.hero_for(1)
	outside=sim.sides[1][1]; outside.pos=Vector2(20,20)
	for i in 3: sim.apply_burn(hero,target)
	sim.apply_burn(hero,outside)
	sim._begin(hero,target,"finisher")
	sim._resolve_attack(hero)
	var expected:=Rules.Catalog.damage(hero.attributes,target.attributes,"magic",2.6+3*.35)
	check(is_equal_approx(10000-target.hp,expected),"ultimate adds exactly three stacks of detonation damage")
	check(sim.burn_stacks(target)==0 and sim.burn_stacks(outside)==1,"ultimate consumes only affected target stacks")
	var after_burst:=target.hp
	for i in 60: sim._advance_burns()
	check(target.hp==after_burst,"consumed burns cannot tick after the ultimate")
	# DoT casualties award kill morale once, including when the source has fallen.
	sim=fixture(); hero=sim.hero_for(0); target=sim.sides[1][1]
	target.hp=1
	sim.apply_burn(hero,target)
	hero.hp=0
	var people:=ceili(target.people*target.hp/target.max_hp)
	for i in 60: sim._advance_burns()
	check(target.hp==0 and target.burns.is_empty() and sim.kills[0]==people,"ongoing burn resolves a casualty and clears dead-target effects")
	check(is_equal_approx(sim.morale[0],50+people*.1),"burn casualties award morale exactly once")
	for i in 120: sim._advance_burns()
	check(sim.kills[0]==people,"dead targets cannot award duplicate kills")
	# Sample every actual frame, including both facings at all battlefield corners.
	Art.prepare()
	var frame_count:=0
	for clip in Art.DATA.clips:
		var entry: Dictionary=Art.DATA.clips[clip]
		var time:=0.0
		for i in entry.frames.size():
			var f:=Art.frame_number(clip,i)
			frame_count+=1
			check(Art.frame_index(clip,time)==i,"animation boundary selects the intended frame: "+clip)
			check(Rect2(Vector2.ZERO,f.texture.get_size()).encloses(f.source),"atlas source remains inside texture: "+clip)
			time+=float(entry.durations_ms[i])/1000.0
			if clip.ends_with("_fx"): continue
			for point in [Vector2(55,-25),Vector2(1865,-25),Vector2(55,740),Vector2(1865,740)]:
				var at:=View.FEET_AREA.position+Vector2(point.x/1920.0,(point.y+25.0)/765.0)*View.FEET_AREA.size
				var height:=View.HERO_HEIGHT*lerpf(.88,1.03,(point.y+25.0)/765.0)
				for facing in [-1,1]:
					var g:=Art.geometry(f,at,height,facing)
					check(View.ACTOR_SAFE_AREA.encloses(g.visible_bounds),"complete Nezha silhouette fits battlefield: %s frame %d" % [clip,i])
	check(frame_count==138,"all 138 runtime clip entries, including sixteen-frame casting and effects, are sampled")
	check(Art.DATA.clips.attack.frames.size()==16,"ordinary attack contains sixteen authored poses")
	check(Art.DATA.portrait!=Art.DATA.sheets.actions.path,"portrait and battle actor use independent image resources")
	for clip in ["qiankun","samadhi","ring_fx","samadhi_fx"]:
		check(Art.DATA.clips[clip].frames.size()==16,"sixteen authored frames in "+clip)
	for pair in [["qiankun","battle"],["samadhi","ultimate"]]:
		check(is_equal_approx(Art.duration(pair[0]),Rules.Catalog.DATA.heroes.nezha.skills[pair[1]].duration),"skill action covers its full simulation duration: "+pair[0])
	check(Art.frame_index("qiankun",.36)==6 and Art.frame_index("qiankun",.86)==13,"ring release and catch align with the authored hand poses")
	check(Art.frame_index("samadhi",.84)==12,"ultimate damage lands on the command thrust frame")
	check(Art.frame_index("samadhi_fx",Art.event_time("samadhi_fx","lotus_burst"))==6,"lotus explosion starts on the seventh VFX frame")
	check(is_equal_approx(Art.event_time("samadhi","lotus_impact")-Art.event_time("samadhi","lotus_windup"),Art.event_time("samadhi_fx","lotus_burst")),"ultimate windup and impact share one continuous VFX timeline")
	check(is_equal_approx(Art.duration("ring_fx"),Rules.Catalog.DATA.heroes.nezha.skills.battle.return_time-Rules.Catalog.DATA.heroes.nezha.skills.battle.release),"sixteen ring frames cover the complete outward and return flight")
	check(is_equal_approx(Art.duration("attack"),Rules.Catalog.DATA.heroes.nezha.normal_attack.duration),"attack clip and combat recovery have identical timing")
	for i in 2:
		var contact: float=Rules.Catalog.DATA.heroes.nezha.normal_attack.hits[i]
		check(Art.frame_index("attack",contact)==[5,9][i],"contact resolves on the extended spear frame")
		check(is_equal_approx(contact,float(Art.DATA.clips.attack.events[i].at_ms)/1000),"weapon flare and actual damage share contact time")
		var contact_frame := Art.frame_index("attack",contact)
		var extension := Art.frame_number("attack",contact_frame)
		var windup := Art.frame_number("attack",contact_frame-1)
		var reach := extension.visible.end.x-extension.pivot.x
		var windup_reach := windup.visible.end.x-windup.pivot.x
		var socket: Array = Art.DATA.clips.attack.events[i].socket
		check(reach-windup_reach>15,"each spear contact visibly extends out of the preceding pose")
		check(absf(reach-float(socket[0])*extension.body_height)<4,"spear spark starts at the illustrated point")
		check(absf(extension.visible.end.y-extension.pivot.y)<=2,"striking boot stays on the contact plane")
	var guard := Art.frame_number("idle",0)
	for clip in ["qiankun","samadhi"]:
		var opening := Art.frame_number(clip,0)
		var guard_height := (guard.pivot.y-guard.visible.position.y)/guard.body_height
		var opening_height := (opening.pivot.y-opening.visible.position.y)/opening.body_height
		check(absf(guard_height-opening_height)<.07,"guard and cast share a consistent standing height: "+clip)
	check(Art.frame_index("idle",Art.duration("idle"))==0,"idle loops at exact duration")
	check(Art.frame_index("defeat",99)==3,"defeat holds the final frame")
	var view:=View.new()
	view.sim=fixture()
	view.sim.hero_for(0).magic_hit_age=0
	view.sim.hero_for(0).hit_age=0
	view.sim.result={"player_won":true}
	var hp_after_result: float=view.sim.hero_for(0).hp
	view.advance_effects(.7)
	check(view.sim.hero_for(0).magic_hit_age>=.7 and view.sim.hero_for(0).hit_age>=.7,"recovery finishes after battle ends")
	check(view.sim.hero_for(0).hp==hp_after_result,"post-result presentation cannot deal new damage")
	view.free()
	var report: Dictionary={"checks":checks,"failures":failures,"frames":frame_count,"burn_cap":3,"burn_seconds":4,"simulation_hz":60}
	DirAccess.make_dir_recursive_absolute("res://previews/nezha/v4")
	FileAccess.open("res://previews/nezha/v4/rules-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("NEZHA_CHECK "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func check_splash() -> void:
	var sim:=fixture()
	var hero:=sim.hero_for(0)
	var primary:=sim.hero_for(1)
	var near: Rules.Fighter=sim.sides[1][1]
	var edge: Rules.Fighter=sim.sides[1][2]
	var beyond: Rules.Fighter=sim.sides[1][3]
	var dead: Rules.Fighter=sim.sides[1][4]
	var ally: Rules.Fighter=sim.sides[0][1]
	for enemy in sim.sides[1]:
		if enemy!=primary: enemy.pos=Vector2(1800,700)
	near.pos=primary.pos+Vector2(0,60)
	edge.pos=primary.pos+Vector2(140,0)
	beyond.pos=primary.pos+Vector2(141,0)
	dead.pos=primary.pos+Vector2(30,0); dead.hp=0
	ally.pos=primary.pos+Vector2(0,40)
	var near_hp:=near.hp
	var edge_hp:=edge.hp
	var beyond_hp:=beyond.hp
	var ally_hp:=ally.hp
	sim._begin(hero,primary,"attack")
	sim._resolve_attack(hero,.5)
	var splashes:=sim.events.filter(func(e: Dictionary) -> bool: return e.kind=="splash_hit")
	check(splashes.size()==2,"one normal contact damages exactly the two secondary enemies in range")
	check(is_equal_approx(near_hp-near.hp,Rules.Catalog.damage(hero.attributes,near.attributes,"physical",.5*.35)),"splash uses 35 percent of the current attack segment and the victim's physical defense")
	check(edge.hp<edge_hp and beyond.hp==beyond_hp,"splash includes the radius boundary and never chains to adjacent out-of-range enemies")
	check(ally.hp==ally_hp and dead.hp==0,"splash excludes friendly and fallen units")
	check(is_equal_approx(10000-primary.hp,Rules.Catalog.damage(hero.attributes,primary.attributes,"physical",.5)),"primary receives one direct hit without duplicate splash")
	check(hero.normal_hits==1 and sim.burn_stacks(near)==0,"splash neither increments the normal hit counter nor spreads burns")
	check(near.velocity.length()<=24.001,"splash uses light normal-attack recoil")
	var no_hit_hp:=near.hp
	primary.pos=Vector2(1750,600)
	sim._resolve_attack(hero,.5)
	check(near.hp==no_hit_hp and sim.events.filter(func(e: Dictionary) -> bool: return e.kind=="splash_hit").size()==2,"out-of-reach primary cannot trigger splash")
	primary.pos=hero.pos+Vector2(100,0)
	primary.hp=1
	near.pos=primary.pos+Vector2(0,60)
	sim._resolve_attack(hero,.5)
	check(primary.hp==0 and near.hp<no_hit_hp,"a killing primary contact still triggers its splash")
	# Secondary casualties use the shared damage path, awarding morale once.
	primary.hp=10000
	edge.pos=Vector2(1800,700)
	near.hp=1
	var before_kills:=sim.kills[0]
	var before_morale:=sim.morale[0]
	var people:=ceili(near.people*near.hp/near.max_hp)
	sim._resolve_attack(hero,.5)
	check(near.hp==0 and sim.kills[0]==before_kills+people,"splash casualty awards its actual troop losses exactly once")
	check(is_equal_approx(sim.morale[0],before_morale+people*.1),"splash casualties award normal kill morale")
	sim._resolve_attack(hero,.5)
	check(sim.kills[0]==before_kills+people,"fallen secondary victims cannot award kills again")
	var count:=int(sim.stats.splash_hits)
	sim.kits[0]=sim.kits[0].duplicate(true)
	sim.kits[0].passive=Rules.Catalog.DATA.heroes.wenzhong.skills.passive
	sim._resolve_attack(hero,.5)
	check(sim.stats.splash_hits==count,"other passive skills do not trigger Nezha splash")
	# The same ability works when Nezha is on the defending side.
	sim=Rules.new({"title":"defending Nezha","player":{"id":"jifa","soldiers":1000},"enemy":{"id":"nezha","soldiers":1000}})
	hero=sim.hero_for(1); primary=sim.hero_for(0); near=sim.sides[0][1]
	hero.pos=Vector2(1000,300); primary.pos=Vector2(900,300); near.pos=Vector2(900,360)
	near_hp=near.hp
	sim._begin(hero,primary,"attack")
	sim._resolve_attack(hero,.5)
	check(near.hp<near_hp and sim.events.any(func(e: Dictionary) -> bool: return e.kind=="splash_hit" and e.side==1),"defending Nezha applies the same splash rules")
