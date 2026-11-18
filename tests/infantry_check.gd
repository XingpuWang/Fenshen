extends SceneTree
const Rules = preload("res://scripts/battle_rules.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func battle(left: int, right: int) -> Rules:
	return Rules.new({"title":"朝歌","player":{"id":"nezha","soldiers":left},
		"enemy":{"id":"wenzhong","soldiers":right}})

func health_and_casualties() -> void:
	for strength in [0,1,99,100,101,237,10000]:
		var sim := battle(strength,600)
		var valid := true
		for soldier: Rules.Fighter in sim.sides[0]:
			if soldier.hero: continue
			valid = valid and soldier.people<=100 and soldier.hp==soldier.people and soldier.max_hp==soldier.people
		check(valid and sim.remaining(0)==strength,"one point per deployed soldier for strength %d" % strength)
	var sim := battle(237,100)
	var last: Rules.Fighter=sim.sides[0].back()
	var enemy:=sim.hero_for(1)
	check(last.hp==37 and sim.sides[0].size()==4,"237 soldiers deploy as 100, 100 and 37")
	sim._damage(enemy,last,12.75,"hit")
	check(last.hp==24.25 and sim.remaining(0)==225 and sim.kills[1]==12 and sim.events.back().amount==12,"fractional damage carries until a whole soldier is lost")
	sim._damage(enemy,last,.25,"burn_hit")
	check(last.hp==24 and sim.remaining(0)==224 and sim.events.back().amount==1,"successive hits, floating numbers and the army count agree")
	sim._damage(enemy,last,500,"finisher_hit")
	sim._damage(enemy,last,500,"hit")
	check(sim.remaining(0)==200 and sim.kills[1]==37 and is_equal_approx(sim.morale[1],53.7),"overkill and subsequent hits only award real casualties")
	var hero:=sim.hero_for(0)
	check(hero.max_hp==Rules.Catalog.effective_stats(sim.encounter.player).max_hp,"the commander's own health is independent")
	sim._damage(enemy,hero,hero.max_hp,"hit")
	check(sim.remaining(0)==200 and sim.kills[1]==37,"a fallen commander isn't counted as a formation loss")

func blocked_file(side: int) -> void:
	var sim:=battle(200,200)
	sim.elapsed=Rules.INTRO
	var front: Rules.Fighter=sim.sides[side][1]
	var rear: Rules.Fighter=sim.sides[side][2]
	var target: Rules.Fighter=sim.sides[1-side][1]
	sim.sides[1-side][2].hp=0
	var sign_x:=1.0 if side==0 else -1.0
	var start:=Vector2(960-sign_x*90,350)
	rear.pos=start
	front.pos=start+Vector2(sign_x*66,0)
	target.pos=front.pos+Vector2(sign_x*76,0)
	front.cooldown=100
	target.cooldown=100
	for army in sim.sides:
		army[0].skill_clock=100
		army[0].cooldown=100
	check(not sim._thrust_lane(rear,target,true),"a screened enemy cannot be struck through a friendly body on side %d" % side)
	var hit:=false
	var lateral:=0.0
	var min_gap:=INF
	for i in 180:
		sim.advance()
		min_gap=minf(min_gap,rear.pos.distance_to(front.pos))
		lateral=maxf(lateral,absf(rear.pos.y-start.y))
		for e in sim.events:
			if e.kind=="hit" and e.source==rear.id and e.target==target.id: hit=true
		sim.events.clear()
		if hit: break
	check(hit and lateral>20,"the rear soldier actually moves around the blocker and hits on side %d" % side)
	check(min_gap>=front.radius+rear.radius-1,"bypassing retains allied body separation")

func contact_frame() -> void:
	var sim:=battle(200,100)
	var front: Rules.Fighter=sim.sides[0][1]
	var rear: Rules.Fighter=sim.sides[0][2]
	var target: Rules.Fighter=sim.sides[1][1]
	rear.pos=Vector2(900,400)
	front.pos=Vector2(962,338)
	target.pos=Vector2(1031,350)
	check(sim._support_target(rear,target)==target,"a halberd has an open path alongside the front rank")
	sim._begin(rear,target,"attack",true)
	var initial_hp:=target.hp
	front.pos=(rear.pos+target.pos)*.5
	sim._resolve_attack(rear)
	check(target.hp==initial_hp,"an ally stepping into the stroke during windup prevents damage")
	front.pos=Vector2(962,338)
	target.pos=Vector2(1200,350)
	sim._resolve_attack(rear)
	check(target.hp==initial_hp,"a retreating target is out of reach at contact")
	front.hp=0
	target.pos=Vector2(1031,350)
	check(sim._support_target(rear,target)==null,"a lone model closes the normal melee distance")

func participation() -> Dictionary:
	var sim:=battle(2400,2400)
	var hits: Array=[{},{}]
	var rear_hits: Array=[{},{}]
	var rear_ids: Array=[{},{}]
	for side in 2:
		var last: Rules.Fighter=sim.sides[side].back()
		for soldier: Rules.Fighter in sim.sides[side]:
			if not soldier.hero and is_equal_approx(soldier.pos.x,last.pos.x): rear_ids[side][soldier.id]=true
	for i in 481:
		sim.advance()
		for event in sim.events:
			if event.kind!="hit": continue
			var fighter:=sim.fighters[int(event.source)]
			if fighter.hero: continue
			hits[fighter.side][fighter.id]=true
			if rear_ids[fighter.side].has(fighter.id): rear_hits[fighter.side][fighter.id]=true
		sim.events.clear()
	for side in 2:
		check(hits[side].size()>=14,"more than half the army have landed a strike after five seconds of melee")
		check(rear_hits[side].size()>=2,"the original rear rank reaches actual contact on both sides")
		check(sim.kills[1-side]==sim.initial[side]-sim.remaining(side),"displayed casualties conserve deployed strength")
	return {"distinct_infantry":[hits[0].size(),hits[1].size()],"last_rank":[rear_hits[0].size(),rear_hits[1].size()]}

func _initialize() -> void:
	health_and_casualties()
	blocked_file(0)
	blocked_file(1)
	contact_frame()
	var participants:=participation()
	print("INFANTRY_CHECK ",JSON.stringify({"checks":checks,"failures":failures,"at_8s":participants}))
	quit(0 if failures.is_empty() else 1)
