extends SceneTree
const Rules = preload("res://scripts/battle_rules.gd")
const World = preload("res://scripts/world_model.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func duel(kind: String, distance: float) -> Rules:
	var troops := [{"type":kind,"count":100},{},{}]
	var sim := Rules.new({"player":{"id":"nezha","soldiers":100,"troops":troops},
		"enemy":{"id":"wenzhong","soldiers":100}})
	sim.elapsed = Rules.INTRO
	for side in 2: sim.hero_for(side).hp = 0
	var actor: Rules.Fighter = sim.sides[0][1]
	var target: Rules.Fighter = sim.sides[1][1]
	actor.pos = Vector2(570,350)
	target.pos = actor.pos + Vector2.RIGHT * distance
	target.action = "attack"
	target.applied = true
	target.duration = 1000
	return sim

func archer_checks() -> void:
	var sim := duel("archer",480)
	var archer: Rules.Fighter = sim.sides[0][1]
	var target: Rules.Fighter = sim.sides[1][1]
	var start := archer.pos
	for i in 25: sim.advance()
	check(sim.arrows.is_empty() and target.hp==100 and archer.action=="attack","drawing the bow at range causes no damage")
	for i in 2: sim.advance()
	check(sim.arrows.size()==1 and archer.pos==start and target.hp==100,"release creates one arrow while the archer holds position")
	if sim.arrows.is_empty(): return
	var arrow := sim.arrows[0]
	check(arrow.origin==start and arrow.destination==target.pos and is_equal_approx(arrow.duration,480.0 / Rules.ARROW_SPEED),"shot travels between fixed world positions at its configured speed")
	# A released projectile outlives its shooter.
	archer.hp=0
	while arrow.age+Rules.STEP+.000001 < arrow.duration: sim._advance_arrows()
	check(target.hp==100 and sim.arrows.size()==1,"arrows in flight have not dealt damage")
	sim._advance_arrows()
	var damage := Rules.Catalog.damage(archer.attributes,target.attributes,"physical")
	check(is_equal_approx(100-target.hp,damage) and sim.arrows.is_empty(),"one physical hit lands when the arrow reaches its target")
	var health := target.hp
	sim._advance_arrows()
	check(target.hp==health and sim.kills[0]==100-target.survivors(),"arrival accounts for exact casualties once")
	var miss := duel("archer",480)
	archer=miss.sides[0][1]
	target=miss.sides[1][1]
	target.ground_velocity=Vector2(0,100)
	miss._release_arrow(archer,target)
	var aimed := miss.arrows[0].destination
	check(aimed.y>target.pos.y,"the archer leads a moving target when releasing the arrow")
	target.pos.y-=160
	for i in 90: miss._advance_arrows()
	check(miss.arrows.is_empty() and target.hp==100 and miss.kills[0]==0,"moving clear of a fixed trajectory evades the shot")
	target.pos=archer.pos + Vector2.RIGHT * (Rules.ARCHER_RANGE+100)
	miss.advance()
	check(archer.pos.x>start.x and archer.walking and miss.arrows.is_empty(),"an out-of-range archer moves up without firing")

func cavalry_checks() -> void:
	var sim:=duel("cavalry",340)
	var rider: Rules.Fighter=sim.sides[0][1]
	var target: Rules.Fighter=sim.sides[1][1]
	var start:=rider.pos
	sim.advance()
	check(rider.action=="charge_run" and not rider.charge_ready and rider.pos.distance_to(start)>Rules.RIDE_SPEED*Rules.STEP,"opening charge consumes one opportunity and outruns normal riding")
	for i in 120:
		if rider.action=="charge_hit": break
		sim.advance()
	check(rider.action=="charge_hit" and target.hp==100,"closing the distance switches to a dedicated impact action")
	var normal:=Rules.Catalog.damage(rider.attributes,target.attributes,"physical")
	for i in 8: sim.advance()
	check(target.hp==100,"bonus is withheld through the charge windup")
	sim.advance()
	check(is_equal_approx(100-target.hp,normal*Rules.CHARGE_MULTIPLIER),"charge contact deals exactly the configured bonus")
	var health:=target.hp
	for i in 180:
		if target.hp<health: break
		sim.advance()
	check(is_equal_approx(health-target.hp,normal) and sim.stats.charges==1 and sim.stats.charge_hits==1,"the next mounted attack deals ordinary damage without another charge")
	var miss:=duel("cavalry",100)
	rider=miss.sides[0][1]
	target=miss.sides[1][1]
	miss.advance()
	target.pos.x+=280
	for i in 35: miss.advance()
	check(target.hp==100 and not rider.charge_ready and not miss.stats.has("charge_hits"),"a missed charge spends the opening opportunity")
	for i in 160: miss.advance()
	check(int(miss.stats.charges)==1 and not miss.stats.has("charge_hits"),"regaining contact cannot rearm a spent charge")

func roster_checks() -> void:
	var odd := [{"type":"archer","count":137},{},{"type":"cavalry","count":3}]
	var sim := Rules.new({"player":{"id":"nezha","soldiers":140,"troops":odd},"enemy":{"id":"wenzhong","soldiers":1}})
	var models: Array[int]=[]
	for f: Rules.Fighter in sim.sides[0]:
		if f.hero: continue
		models.append(int(f.max_hp))
		check(f.max_hp==f.people and odd[f.slot].type==f.troop_type,"each model belongs to its original slot and starts at one HP per person")
		if f.troop_type=="cavalry": f.hp=0
	models.sort()
	check(models==[3,37,100] and sim.remaining_roster(0)==[odd[0],{},{"type":"cavalry","count":0}],"partial groups and actual losses stay within their original companies")
	check(Rules.resize_roster(Rules.roster(400),406,true)==[{"type":"halberd","count":403},{"type":"archer","count":2},{"type":"cavalry","count":1}],"legacy halberd armies can recruit both new types without converting survivors")
	for n in [0,1,17,138,140,142,5200]:
		var resized:=Rules.resize_roster(odd,n)
		check(Rules.valid_roster(resized,n) and resized[1].is_empty(),"resizing preserves slot identity and total %d"%n)

func battle_checks() -> Dictionary:
	var world:=World.new(false)
	world.setup_chaoge_test()
	var encounter:=world.begin_field_battle(world.units[0],world.units[1])
	var sim:=Rules.new(encounter)
	for side in 2:
		check(sim.remaining_roster(side)==[{"type":"halberd","count":1200},{"type":"archer","count":800},{"type":"cavalry","count":400}],"Chaoge deploys all three companies on each side")
		var furthest_archer:=-INF
		var rearmost_infantry:=INF
		for f: Rules.Fighter in sim.sides[side]:
			var advance:=f.pos.x if side==0 else 1920.0-f.pos.x
			if f.troop_type=="archer": furthest_archer=maxf(furthest_archer,advance)
			if not f.hero and f.troop_type=="halberd": rearmost_infantry=minf(rearmost_infantry,advance)
		check(furthest_archer<=rearmost_infantry,"archers start behind the halberds for both facings")
	var peak:=0
	var chargers:={}
	var first_wing_time:=[INF,INF]
	var first_wing_contact:=[Vector2.ZERO,Vector2.ZERO]
	for i in 5000:
		sim.advance()
		peak=maxi(peak,sim.arrows.size())
		for e in sim.events:
			if e.kind=="charge_hit":
				check(not chargers.has(e.source),"one impact per cavalry model during the entire battle")
				chargers[e.source]=true
				var contact: Vector2=sim.fighters[e.source].pos.lerp(sim.fighters[e.target].pos,.5)
				var wing:=0 if contact.y>350.0 else 1
				if is_inf(first_wing_time[wing]):
					first_wing_time[wing]=sim.elapsed
					first_wing_contact[wing]=contact
		sim.events.clear()
		if not sim.result.is_empty(): break
	check(not sim.result.is_empty() and sim.stats.charges==8 and chargers.size()==8,"both wings complete all eight distinct opening charges in the live scenario")
	check(first_wing_time[1]-first_wing_time[0]>=.1,"the foreground cavalry wing makes real contact before the far wing")
	check(first_wing_contact[0].x-first_wing_contact[1].x>100.0,"the two opening collisions land on distinct parts of the battlefield")
	check(peak>1 and int(sim.stats.arrow_hits)>0 and sim.stats.arrows>=sim.stats.arrow_hits,"multiple physical arrows fly simultaneously and resolve independently")
	var again:=Rules.new(encounter)
	for i in 5000:
		again.advance()
		again.events.clear()
		if not again.result.is_empty(): break
	check(sim.result==again.result,"identical mixed battles produce identical per-slot casualties, arrows and charges")
	var malformed:=sim.result.duplicate(true)
	malformed.enemy_troops.reverse()
	check(not world.finish_battle(malformed) and world.units[0].soldiers==2400,"an invalid defending roster leaves both armies untouched")
	check(world.finish_battle(sim.result) and world.units[0].troops==sim.result.player_troops and world.units[1].troops==sim.result.enemy_troops,"the real field encounter carries both surviving rosters back to the map")
	return {"arrows":sim.stats.arrows,"arrow_hits":sim.stats.arrow_hits,"peak_in_flight":peak,"charges":sim.stats.charges,"charge_hits":chargers.size()}

func _initialize() -> void:
	archer_checks()
	cavalry_checks()
	roster_checks()
	var sample:=battle_checks()
	print("COMBINED_ARMS_CHECK ",JSON.stringify({"checks":checks,"failures":failures,"chaoge":sample}))
	quit(0 if failures.is_empty() else 1)
