extends SceneTree
const World=preload("res://scripts/world_model.gd")
const Rules=preload("res://scripts/battle_rules.gd")
const View=preload("res://scripts/battle_view.gd")
var checks:=0
var failures: Array[String]=[]

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)

func fixture() -> Rules:
	var sim:=Rules.new({"title":"priority","player":{"id":"nezha","name":"哪吒","soldiers":1000},"enemy":{"id":"wenzhong","name":"闻仲","soldiers":1000}})
	sim.elapsed=Rules.INTRO
	for f in sim.fighters:
		f.cooldown=999
		f.skill_clock=999
	var hero:=sim.hero_for(0)
	var enemy:=sim.hero_for(1)
	hero.pos=Vector2(900,300)
	enemy.pos=Vector2(1000,300)
	enemy.hp=100000
	enemy.max_hp=100000
	sim.morale[0]=100
	return sim

func _initialize() -> void:
	var w:=World.new()
	check(w.units.size()==3 and not w.test_scenario,"campaign remains separately available")
	w.setup_chaoge_test()
	var a: Dictionary=w.units[0]
	var b: Dictionary=w.units[1]
	check(w.units.size()==2 and a.id=="nezha" and b.id=="wenzhong","test scenario contains exactly Nezha and Wen Zhong")
	check(w.faction(a)!=w.faction(b),"the two test armies are opponents")
	check(w.by_poi[w.test_city_id].name=="朝歌" and w.hex_distance(a.cell,b.cell)==1,"test armies are adjacent near Chaoge")
	for u in w.units:
		var p: Array=w.by_poi[w.test_city_id].position
		check(w.walkable(u.cell,w.faction(u)) and w.center(u.cell).distance_to(Vector2(p[0],p[1]))<900,"spawn stays on legal nearby land")
		check(w.search(u.cell,u.ap,u.id).dist.size()>1,"both factions can move from their starting cells")
	var targets:=w.map_skill_targets(a,b.cell)
	check(targets.units==["wenzhong"] and targets.garrisons.is_empty(),"Nezha targets only the visible enemy army")
	var before:=int(b.soldiers)
	var cast:=w.cast_map_skill(a,b.cell)
	check(cast.ok and b.soldiers<before and a.soldiers==2400,"fire field damages the actual opposing army only")
	check(Rules.valid_roster(b.troops,b.soldiers) and b.troops[1].count<800 and b.troops[2].count<400 and a.action_done and a.ap==0,"map damage updates the mixed roster and spends the caster action")
	check(w.begin_field_battle(a,b).is_empty(),"spent army cannot start another action")
	w.next_turn()
	check(b.soldiers==2400 and a.ap==a.max_ap and not a.action_done,"end turn replenishes test strength and actions")
	var defense: float=w.Catalog.effective_stats(a).physical_defense
	var debuff:=w.cast_map_skill(b,a.cell)
	check(debuff.ok and w.Catalog.effective_stats(a).physical_defense==defense-12,"Wen Zhong debuffs Nezha instead of his own faction")
	check(b.effects.is_empty(),"enemy-targeted debuff cannot hit the caster")
	var encounter:=w.begin_field_battle(a,b)
	check(not encounter.is_empty() and encounter.enemy.id=="wenzhong" and encounter.player.effects.size()==1,"battle uses the actual armies and map effects")
	var sim:=Rules.new(encounter)
	check(sim.hero_for(0).attributes.physical_defense==defense-12,"map debuff reaches battle attributes")
	check(not w.finish_battle({"player_remaining":99999,"enemy_remaining":0,"morale":50,"enemy_morale":50,"player_won":true}),"invalid field results are rejected")
	var result:={"player_remaining":1900,"enemy_remaining":0,"morale":65,"enemy_morale":30,"player_won":true}
	check(w.finish_battle(result) and a.soldiers==1900 and b.soldiers==0,"field result updates both map armies")
	check(w.pending_battle.is_empty() and a.action_done and not w.finish_battle(result),"result settles once and completes the attacker action")
	w.next_turn()
	check(a.soldiers==2400 and b.soldiers==2400 and a.effects.size()==1,"retesting replenishes troops without shortening a two-turn debuff")
	w.next_turn()
	check(a.effects.is_empty(),"map debuff expires at its authored turn boundary")
	check(w.begin_field_battle(a,a).is_empty(),"friendly/self field combat is rejected")
	var old_cell: int=b.cell
	b.cell=0
	check(w.begin_field_battle(a,b).is_empty(),"distant opponents cannot start melee combat")
	b.cell=old_cell
	var reversed:=w.begin_field_battle(b,a)
	var faction_view:=View.new()
	faction_view.setup(reversed)
	for side in 2:
		for soldier: Rules.Fighter in faction_view.sim.sides[side]:
			if soldier.hero: continue
			var prefix := "shang" if side == 0 else "zhou"
			var suffix := "" if soldier.troop_type == "halberd" else "_" + soldier.troop_type
			check(faction_view.sprite_key(soldier)==prefix+suffix,"choosing Wen Zhong preserves each troop's faction artwork")
	check(faction_view.army_name(0)=="商军" and faction_view.army_name(1)=="西岐","battle army labels follow faction rather than screen side")
	faction_view.free()
	# Ultimate interrupts each lower-priority phase, including an already released ring.
	for phase in ["idle","run","hit","attack_start","attack_between","cast_start","cast_released","cast_recovery"]:
		sim=fixture()
		var hero:=sim.hero_for(0)
		var enemy:=sim.hero_for(1)
		if phase.begins_with("attack"):
			sim._begin(hero,enemy,"attack")
			hero.age=.31 if phase=="attack_between" else .1
			if phase=="attack_between":
				sim._resolve_attack(hero,.5)
				hero.hit_index=1
		elif phase.begins_with("cast"):
			sim._begin(hero,enemy,"cast")
			hero.age=.9 if phase=="cast_recovery" else (.4 if phase=="cast_released" else .1)
			hero.released=phase!="cast_start"
			if phase=="cast_recovery":
				sim._resolve_attack(hero)
				hero.applied=true
		elif phase=="run": hero.walking=true
		elif phase=="hit": hero.hit_age=0
		hero.velocity=Vector2(20,0)
		var hp_before:=enemy.hp
		var hits_before:=hero.normal_hits
		var attacks_before:=int(sim.stats.attacks)
		var casts_before:=int(sim.stats.skills)
		check(sim.finisher_reason(0).is_empty() and sim.use_finisher(0),"ultimate immediately preempts "+phase)
		check(hero.action=="finisher" and hero.age==0 and hero.velocity==Vector2.ZERO and not hero.walking,"ultimate replaces the action and stops movement: "+phase)
		check(sim.morale[0]==0 and not sim.use_finisher(0),"one activation consumes morale once: "+phase)
		sim.morale[0]=100
		check(not sim.use_finisher(0) and sim.morale[0]==100,"an active ultimate cannot restart itself: "+phase)
		sim.morale[0]=0
		sim.events.clear()
		for i in 49: sim.advance()
		check(enemy.hp==hp_before and hero.normal_hits==hits_before and sim.stats.attacks==attacks_before and sim.stats.skills==casts_before,"cancelled contacts never land during ultimate windup: "+phase)
		for i in 2: sim.advance()
		check(sim.stats.finishers==1 and enemy.hp<hp_before,"ultimate resolves its own impact exactly once: "+phase)
	# Enemy AI follows the same priority, while resource/life/intro gates remain.
	sim=fixture()
	sim.morale[1]=100
	sim._begin(sim.hero_for(1),sim.hero_for(0),"cast")
	sim.advance()
	check(sim.hero_for(1).action=="finisher" and sim.morale[1]==0,"enemy ultimate also interrupts its cast immediately")
	for gate in ["morale","dead","intro","result"]:
		sim=fixture()
		match gate:
			"morale": sim.morale[0]=99
			"dead": sim.hero_for(0).hp=0
			"intro": sim.elapsed=0
			"result": sim.result={"player_won":true}
		check(not sim.use_finisher(0),"priority does not bypass "+gate)
	var view:=View.new()
	view.sim=fixture()
	var hero:=view.sim.hero_for(0)
	view.sim._begin(hero,view.sim.hero_for(1),"cast")
	view.effects=[{"kind":"ring","source":hero.id,"age":0.0,"life":1.0},{"kind":"hit","source":hero.id,"age":0.0,"life":1.0}]
	view.sim.use_finisher(0)
	view.advance_effects(0)
	check(not view.effects.any(func(e: Dictionary)->bool: return e.kind=="ring") and view.effects.any(func(e: Dictionary)->bool: return e.kind=="hit"),"interruption removes cancelled projectile visuals but preserves settled hit feedback")
	view.effects.clear()
	# Keep the test armies in combat through both impact frames.
	for fighter in view.sim.fighters:
		fighter.hp=5000
		fighter.max_hp=5000
	view.sim.morale[1]=100
	check(view.sim.use_finisher(1) and hero.age==0,"opposing ultimate can start immediately while the first camera cue is active")
	var previous_point:=Vector2(960,500)
	var largest_step:=0.0
	var peak_zoom:=1.0
	var spells:={}
	for i in 155:
		view.sim.advance()
		view.advance_effects(Rules.STEP)
		peak_zoom=maxf(peak_zoom,view.scale.x)
		var point:=view.get_transform()*Vector2(960,500)
		largest_step=maxf(largest_step,point.distance_to(previous_point))
		previous_point=point
		for fx in view.effects:
			if fx.kind=="finisher" and fx.age==0:
				spells[fx.ability]=fx
	check(peak_zoom>1.04 and peak_zoom<=1.076 and largest_step<8 and view.scale==Vector2.ONE,"overlapping ultimates share a bounded smooth camera and return to the tactical view")
	check(spells.has("samadhi") and spells.has("nine_thunders"),"both simultaneous impacts keep their own visual cue")
	for fx in spells.values():
		var center:=view.ground(fx.pos)
		check(fx.weapon!=center and fx.branches.size()<=2,"each cue freezes its impact-time source and limited secondary targets")
	view.free()
	var report:={"checks":checks,"failures":failures,"scenario":"chaoge_test","priority_phases":8}
	DirAccess.make_dir_recursive_absolute("res://previews/chaoge-test")
	FileAccess.open("res://previews/chaoge-test/rules-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CHAOGE_CHECK "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
