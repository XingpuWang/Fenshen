extends SceneTree
const World=preload("res://scripts/world_model.gd")
const Rules=preload("res://scripts/battle_rules.gd")
const Catalog=preload("res://scripts/unit_catalog.gd")
var checks:=0
var failures: Array[String]=[]
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
func encounter(left:=2400,right:=3000) -> Dictionary:
	return {"title":"skills","player":{"id":"nezha","soldiers":left,"morale":0},"enemy":{"id":"wenzhong","soldiers":right,"morale":100}}
func put_next_to_enemy(world: World, unit: Dictionary) -> Dictionary:
	for poi in world.pois:
		if poi.owner!="shang": continue
		for ci in poi.cells:
			for adjacent in world.cells[int(ci)].n:
				if world.walkable(int(adjacent)) and not world.occupied(int(adjacent),unit.id):
					unit.cell=int(adjacent)
					if world.can_capture(unit,poi): return poi
	return {}
func _initialize() -> void:
	for id in Catalog.DATA.heroes:
		var profile: Dictionary=Catalog.DATA.heroes[id]
		check(Catalog.valid_stats(profile.stats),id+" has all six common attributes")
		check(profile.skills.size()==4 and profile.skills.has_all(Catalog.SKILL_KEYS),id+" has exactly four skill slots")
	check(Catalog.valid_stats(Catalog.DATA.troops.halberd.stats),"troops have the same six attribute fields")
	var base: Dictionary=Catalog.DATA.heroes.nezha.stats.duplicate(true)
	var defensive: Dictionary=base.duplicate(true)
	defensive.physical_defense+=100
	check(Catalog.damage(base,defensive,"physical")<Catalog.damage(base,base,"physical"),"physical defense mitigates physical attacks")
	check(is_equal_approx(Catalog.damage(base,defensive,"magic"),Catalog.damage(base,base,"magic")),"physical defense does not mitigate magic")
	defensive=base.duplicate(true)
	defensive.magic_defense+=100
	check(Catalog.damage(base,defensive,"magic")<Catalog.damage(base,base,"magic"),"magic defense mitigates spells")
	check(Catalog.effective_stats({"id":"nezha"}).magic_defense==30 and Catalog.skill({"id":"nezha"},"passive").id=="three_heads_six_arms","Nezha splash passive replaces the old magic-defense bonus")
	check(Catalog.effective_stats({"id":"vanguard"},"halberd").physical_defense==38,"army passive reaches infantry")
	check(Catalog.effective_stats({"id":"scouts"}).max_hp==950,"health passive changes maximum life")
	var sim:=Rules.new(encounter())
	check(sim.morale==[50.0,50.0],"both sides reset to 50 regardless of campaign morale")
	for f in sim.fighters: check(Catalog.valid_stats(f.attributes),"fighter attributes populated")
	var hero:=sim.hero_for(0)
	var target: Rules.Fighter=sim.sides[1][1]
	sim._damage(hero,target,target.max_hp*.5,"hit")
	check(sim.kills[0]==50 and is_equal_approx(sim.morale[0],55),"partial model casualties grant exact kill morale")
	sim._damage(hero,target,100000,"hit")
	var earned:=sim.morale[0]
	sim._damage(hero,target,100000,"hit")
	check(sim.kills[0]==100 and sim.morale[0]==earned,"overkill and duplicate corpse hits never farm morale")
	sim._damage(hero,sim.sides[0][1],100000,"hit")
	check(sim.kills[0]==100,"friendly targets do not generate kills")
	sim.elapsed=Rules.INTRO+.1
	check(not sim.use_finisher(0),"time alone never unlocks ultimate")
	for other in sim.sides[1]:
		if not other.hero and sim.kills[0]<500: sim._damage(hero,other,other.hp,"hit")
	check(is_equal_approx(sim.morale[0],100) and sim.kills[0]==500,"500 actual soldier kills fill initial 50 to 100")
	check(sim.use_finisher(0) and sim.morale[0]==0,"100 morale allows manual release immediately after formation")
	check(not sim.use_finisher(0),"cannot spend the same morale twice")
	hero.action="idle"
	for other in sim.sides[1]:
		if not other.hero and sim.kills[0]<1500: sim._damage(hero,other,other.hp,"hit")
	check(sim.morale[0]==100 and sim.use_finisher(0),"ultimate can recharge and release again")
	hero.action="idle"
	sim.morale[0]=100
	hero.hp=0
	check(not sim.use_finisher(0),"fallen commander cannot release ultimate")
	var physical:=Rules.new(encounter(100,100))
	var a:=physical.hero_for(0)
	var b: Rules.Fighter=physical.sides[1][1]
	a.pos=Vector2(900,200)
	b.pos=Vector2(970,200)
	physical._begin(a,b,"attack")
	var hp:=b.hp
	physical._resolve_attack(a)
	check(is_equal_approx(hp-b.hp,Catalog.damage(a.attributes,b.attributes,"physical")),"ordinary attacks consume actual physical stats")
	var world:=World.new()
	var unit: Dictionary=world.units[0]
	var ally: Dictionary=world.units[1]
	check(unit.max_ap==unit.stats.movement and world.units[2].max_ap==8,"movement controls world travel budget")
	unit.stats.movement=4
	world.next_turn()
	check(unit.ap==4 and world.search(unit.cell,unit.ap,unit.id).dist.values().max()<=4,"modified movement changes reachable range next turn")
	var snapshot:=JSON.stringify(world.units)
	check(not world.cast_map_skill(unit,-1).ok and JSON.stringify(world.units)==snapshot,"invalid skill is atomic and costs no action")
	var poi:=put_next_to_enemy(world,unit)
	check(not poi.is_empty(),"map AOE can target an actual enemy stronghold")
	var old_guard:=int(world.garrison(poi).soldiers)
	var cast:=world.cast_map_skill(unit,int(poi.cells[0]))
	check(cast.ok and int(world.garrison(poi).soldiers)<old_guard and poi.owner=="shang","AOE damages garrison without taking ownership")
	check(unit.ap==0 and unit.action_done,"successful cast completes this army's round")
	check(not world.cast_map_skill(unit,int(poi.cells[0])).ok and not world.can_capture(unit,poi),"cast army cannot act again this round")
	world.next_turn()
	check(unit.ap==4 and not unit.action_done,"next round restores movement and map skill eligibility")
	# Army buffs affect the hero and troops in the next real encounter.
	ally.cell=world.neighbors(unit.cell,ally.id)[0]
	var base_attack:=float(Catalog.effective_stats(unit).physical_attack)
	check(world.cast_map_skill(ally,unit.cell).ok,"group buff accepts an allied area")
	check(Catalog.effective_stats(unit).physical_attack==base_attack+12,"buff changes shared attributes")
	var entry:=world.begin_battle(unit,poi)
	var buff_battle:=Rules.new(entry)
	check(buff_battle.hero_for(0).attributes.physical_attack==base_attack+12,"buff reaches the hero")
	for soldier: Rules.Fighter in buff_battle.sides[0]:
		if not soldier.hero:
			check(soldier.attributes.physical_attack==Catalog.DATA.troops[soldier.troop_type].stats.physical_attack+12,"buff reaches each troop's own physical attack")
	world.pending_battle.clear()
	var save_path:="user://fengshen-skills-save.json"
	check(world.save_game(save_path)==OK,"new skill state saves")
	var loaded:=World.new()
	check(loaded.load_game(save_path),"current schema restores hero skills successfully")
	check(loaded.units[0].stats==unit.stats and loaded.units[0].effects==unit.effects and loaded.units[1].action_done,"stats, effects and spent turn survive reload")
	check(loaded.garrison(loaded.by_poi[poi.id]).soldiers==world.garrison(poi).soldiers,"AOE garrison damage survives reload")
	world.next_turn()
	check(Catalog.effective_stats(unit).physical_attack==base_attack+12,"buff lasts through the next round")
	world.next_turn()
	check(Catalog.effective_stats(unit).physical_attack==base_attack,"expired buff is removed before the following round")
	var healer: Dictionary=world.units[2]
	healer.cell=world.neighbors(unit.cell,healer.id)[0]
	unit.soldiers=int(unit.max_soldiers)-200
	unit.troops=Rules.roster(unit.soldiers)
	check(world.cast_map_skill(healer,unit.cell).ok and unit.soldiers==unit.max_soldiers,"group heal restores casualties without exceeding capacity")
	check(Rules.valid_roster(unit.troops,unit.soldiers),"healing preserves exact roster counts")
	# Same framework also exercises enemy debuffs and legal marching.
	world.next_turn()
	unit.hero_id="wenzhong"
	unit.stats=Catalog.profile(unit).stats.duplicate(true)
	check(world.cast_map_skill(unit,int(poi.cells[0])).ok,"debuff can target enemy garrisons")
	var weakened:=world.garrison(poi)
	check(Catalog.effective_stats(weakened,"halberd").magic_defense==13,"debuff changes real troop defense")
	world.next_turn()
	unit.hero_id="jifa"
	unit.stats=Catalog.profile(unit).stats.duplicate(true)
	var destination: int=world.neighbors(unit.cell,unit.id)[0]
	check(world.cast_map_skill(unit,destination).ok and unit.cell==destination and unit.ap==0,"march uses legal route and then ends round")
	world.next_turn()
	var impossible: int=-1
	for i in world.cells.size():
		if int(world.cells[i].t)!=0: impossible=i; break
	var before:=unit.duplicate(true)
	check(not world.cast_map_skill(unit,impossible).ok and unit==before,"march cannot bypass impassable terrain")
	world.pending_battle={"locked":true}
	check(not world.cast_map_skill(unit,destination).ok,"map spells are blocked by pending combat")
	world.pending_battle.clear()
	# Corrupt input rejection must not partially mutate campaign state.
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	saved.units[0].stats.magic_defense=-1
	FileAccess.open(save_path,FileAccess.WRITE).store_string(JSON.stringify(saved))
	var stable:=JSON.stringify(loaded.units)
	check(not loaded.load_game(save_path) and JSON.stringify(loaded.units)==stable,"invalid stats reject atomically")
	check(world.save_game(save_path)==OK,"fixture saves after skill sequence")
	saved=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	saved.schema=4
	for u in saved.units:
		for field in ["hero_id","stats","effects","action_done"]: u.erase(field)
		u.ap=0
	for key in saved.garrisons:
		for field in ["hero_id","stats","effects"]: saved.garrisons[key].erase(field)
	FileAccess.open(save_path,FileAccess.WRITE).store_string(JSON.stringify(saved))
	check(loaded.load_game(save_path) and loaded.units[0].hero_id=="nezha" and loaded.units[0].stats.movement==6,"schema 4 migrates to canonical hero attributes")
	var report: Dictionary={"checks":checks,"failures":failures,"heroes":Catalog.DATA.heroes.size(),"skill_slots":4,"morale_start":50,"morale_cost":100,"morale_per_kill":.1}
	DirAccess.make_dir_recursive_absolute("res://previews/skills")
	FileAccess.open("res://previews/skills/rules-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SKILLS_CHECK "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
