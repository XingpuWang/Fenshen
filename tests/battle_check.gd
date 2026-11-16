extends SceneTree
const Rules = preload("res://scripts/battle_rules.gd")
const World = preload("res://scripts/world_model.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func encounter(left := 2400, right := 2200, morale := 80) -> Dictionary:
	return {"title":"test","player":{"id":"nezha","name":"哪吒","soldiers":left,"morale":morale},"enemy":{"id":"wenzhong","name":"闻仲","soldiers":right,"morale":75}}
func run_to_end(sim: Rules, use_ultimate := true) -> void:
	for i in 5000:
		if use_ultimate: sim.use_finisher(0)
		sim.advance()
		sim.events.clear()
		if not sim.result.is_empty(): return
func _initialize() -> void:
	var sim := Rules.new(encounter(1250, 1200))
	check(sim.remaining(0)==1250 and sim.fighters.size()==27,"partial model preserves exact people count")
	var first_pos := sim.fighters[1].pos
	for i in 170: sim.advance()
	check(sim.fighters[1].pos==first_pos and sim.stats.attacks==0,"prebattle split formation has no combat")
	check(not sim.use_finisher(0),"finisher unavailable during formation / below 100 morale")
	for i in 100: sim.advance()
	check(sim.fighters[1].pos.x>first_pos.x,"both armies charge after introduction")
	check(sim.stats.attacks==0,"damage does not precede contact")
	run_to_end(sim)
	check(not sim.result.is_empty(),"battle terminates within bound")
	check(sim.stats.attacks>0 and sim.stats.skills>0 and sim.stats.finishers>0,"normal strikes, automatic casts and finishers execute")
	check(sim.stats.collisions>0,"physical body collision is exercised")
	check(not sim.use_finisher(0),"cannot release finisher after result")
	check(sim.result.player_remaining<=1250 and sim.result.enemy_remaining<=1200,"casualties do not create soldiers")
	var same := Rules.new(encounter(1250,1200))
	run_to_end(same)
	check(same.result==sim.result,"same encounter and commands produce deterministic result")
	var low := Rules.new(encounter(1000,1000,69))
	low.elapsed=Rules.INTRO+.1
	check(low.morale[0]==50 and not low.use_finisher(0),"every battle starts at 50 independent of previous morale")
	var enough := Rules.new(encounter(1000,1000,70))
	enough.elapsed=Rules.INTRO+.1
	for enemy in enough.sides[1]:
		if not enemy.hero and enough.kills[0]<500: enough._damage(enough.hero_for(0),enemy,enemy.hp,"hit")
	check(enough.use_finisher(0) and enough.morale[0]==0,"exact threshold consumes morale once")
	check(not enough.use_finisher(0),"repeat finisher needs replenished morale")
	var contact := Rules.new(encounter(100,100))
	var a: Rules.Fighter=contact.fighters[1]
	var b: Rules.Fighter=contact.fighters[3]
	a.pos=Vector2(900,100); b.pos=Vector2(970,100)
	contact._begin(a,b,"attack")
	contact.elapsed=Rules.INTRO
	var hp := b.hp
	for i in 18: contact.advance()
	check(b.hp==hp,"melee windup has no early damage")
	for i in 3: contact.advance()
	check(b.hp<hp,"damage applied on attack contact frame")
	a.pos=Vector2(900,100); b.pos=Vector2(901,100)
	contact._resolve_bodies()
	check(a.pos.distance_to(b.pos)>=a.radius+b.radius-0.1,"opponents cannot overlap body volumes")
	contact.fighters[0].pos=a.pos
	contact._resolve_bodies()
	check(a.pos.distance_to(contact.fighters[0].pos)>60,"hero and friendly infantry also collide")
	check(Rules.valid_roster(Rules.roster(1234),1234),"one halberd company and two empty slots form valid MVP roster")
	check(not Rules.valid_roster([{"type":"halberd","count":500},{"type":"halberd","count":500},{}],1000),"duplicate troop types rejected")
	check(not Rules.valid_roster([{"type":"archer","count":1000},{},{}],1000),"unimplemented troop types cannot enter MVP")
	check(not Rules.valid_roster(Rules.roster(1000),999),"troop total must match campaign soldiers")
	# Full campaign transaction, loss/retry/win and save roundtrip.
	var world := World.new()
	var u: Dictionary=world.units[0]
	var poi: Dictionary=world.by_poi.guanzhong_pass_0
	var found := false
	for p in world.pois:
		if p.owner!="shang": continue
		for ci in p.cells:
			for n in world.cells[int(ci)].n:
				if not world.walkable(int(n)) or world.occupied(int(n),u.id): continue
				u.cell=int(n)
				if world.can_capture(u,p):
					poi=p
					found=true
					break
			if found: break
		if found: break
	check(found,"enemy contact reachable on real map land edge")
	check(not world.capture(u,poi),"guarded enemy cannot be captured without battle")
	var before := u.duplicate(true)
	var e := world.begin_battle(u,poi)
	check(not e.is_empty() and u==before and poi.owner=="shang","encounter does not mutate campaign before outcome")
	check(world.begin_battle(u,poi).is_empty(),"only one battle can be pending")
	var turn := world.turn
	world.next_turn()
	check(world.turn==turn and world.save_game("/private/tmp/battle-busy.json")==ERR_BUSY,"campaign mutations and saving blocked in combat")
	var loss := {"player_won":false,"player_remaining":3400,"enemy_remaining":800,"morale":30,"enemy_morale":55}
	check(world.finish_battle(loss),"loss result applies")
	check(u.soldiers==3400 and u.morale==30 and u.ap==before.ap-1 and u.cell==before.cell and poi.owner=="shang","loss keeps origin and spends one AP with real casualties")
	check(world.garrison(poi).soldiers==800,"enemy survivors persist for next assault")
	check(not world.finish_battle(loss),"result cannot be applied twice")
	var save_path := "/private/tmp/fengshen-battle-save.json"
	check(world.save_game(save_path)==OK,"battle state saves atomically")
	var loaded := World.new()
	check(loaded.load_game(save_path) and loaded.units[0].troops==u.troops and loaded.units[0].morale==30 and loaded.garrison(loaded.by_poi[poi.id]).soldiers==800,"save restores morale roster and damaged garrison")
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	saved.units[0].troops[0].count+=1
	FileAccess.open(save_path,FileAccess.WRITE).store_string(JSON.stringify(saved))
	check(not loaded.load_game(save_path) and loaded.units[0].soldiers==3400,"corrupt troop totals rejected without mutation")
	world.begin_battle(u,poi)
	var win := {"player_won":true,"player_remaining":3000,"enemy_remaining":0,"morale":42,"enemy_morale":0}
	check(world.finish_battle(win) and poi.owner=="player" and world.captured==1,"victory changes ownership exactly once")
	world.next_turn()
	check(u.morale==50,"new battle morale resets to the 50 point base")
	var time_start := Time.get_ticks_usec()
	var stress := Rules.new(encounter(6000,6000))
	var max_penetration := 0.0
	for i in 900:
		stress.advance()
		stress.events.clear()
		if i%60==0:
			for j in stress.fighters.size():
				var f := stress.fighters[j]
				if f.hp<=0: continue
				for k in range(j+1,stress.fighters.size()):
					var other := stress.fighters[k]
					if other.hp>0: max_penetration=maxf(max_penetration,f.radius+other.radius-f.pos.distance_to(other.pos))
	var ms := (Time.get_ticks_usec()-time_start)/1000.0
	check(max_penetration<6,"dense formations resolve overlaps within six ground pixels")
	var report := {"checks":checks,"failures":failures,"example_result":sim.result,"stress_actors":stress.fighters.size(),"stress_900_steps_ms":ms,"max_penetration":max_penetration}
	FileAccess.open("res://previews/battle/rules-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
