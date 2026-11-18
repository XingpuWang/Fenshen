extends SceneTree
const View=preload("res://scripts/battle_view.gd")
const Rules=preload("res://scripts/battle_rules.gd")

var failures: Array[String]=[]
var checks:=0

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)

func _initialize() -> void:
	var view:=View.new()
	var force:=[{"type":"cavalry","count":300},{"type":"archer","count":100},{}]
	view.setup({"player":{"id":"nezha","soldiers":400,"troops":force},"enemy":{"id":"wenzhong","soldiers":400,"troops":force}})
	var sim:=view.sim
	var rider: Rules.Fighter=sim.sides[0][1]
	var left: Rules.Fighter=sim.sides[1][1]
	var right: Rules.Fighter=sim.sides[1][2]
	var distant: Rules.Fighter=sim.sides[1][3]
	var archer: Rules.Fighter=sim.sides[0][4]
	var other_slot: Rules.Fighter=sim.sides[1][4]
	rider.pos=Vector2(800,350)
	left.pos=Vector2(900,350)
	right.pos=Vector2(955,350)
	distant.pos=Vector2(1320,350)
	other_slot.pos=Vector2(940,335)
	sim._damage(rider,left,11,"charge_hit")
	sim._damage(rider,right,12,"charge_hit")
	view.advance_effects(0)
	check(view.effects.size()==2 and view.floating_numbers.size()==1,"adjacent simultaneous charge hits retain independent sparks and share one number")
	check(view.floating_numbers[0].amount==23 and sim.kills[0]==23,"grouped text totals actual resolved casualties")
	var stamp: Vector2=view.effects[0].strike
	var expected_contact:=left.pos+left.pos.direction_to(rider.pos)*left.radius*.55
	check(stamp.is_equal_approx(view.ground(expected_contact)-Vector2(0,view._chest_height(left,expected_contact.y))),"charge flash anchors on the defender's near side at the weapon contact height")
	view.show_damage_numbers=false
	view.advance_effects(.05)
	check(view.effects[0].strike==stamp and view.floating_numbers[0].age>0,"number drift or hidden numbers cannot displace the spark")
	sim._damage(rider,distant,9,"charge_hit")
	sim._damage(rider,other_slot,6,"charge_hit")
	view.advance_effects(0)
	check(view.floating_numbers.size()==3,"different companies and distant fights on one front retain separate totals")
	view.advance_effects(.15)
	sim._damage(rider,left,5,"charge_hit")
	view.advance_effects(0)
	check(view.floating_numbers.size()==4,"the first impact defines a bounded grouping window")
	view.advance_effects(.80)
	check(view.effects.is_empty() and view.floating_numbers.is_empty(),"all local effects expire on simulation time")
	archer.pos=Vector2(580,350)
	sim._release_arrow(archer,left)
	check(sim.events.size()==1 and sim.events[0].kind=="bow_release","release is delivered when a physical arrow is created")
	view.advance_effects(0)
	check(view.last_sound.has(4) and not view.last_sound.has(5),"only the string sounds while the arrow is airborne")
	var arrow:=sim.arrows[0]
	var endpoint:=view.arrow_screen_point(arrow,1.0)
	left.pos.y+=15
	for tick in ceili(arrow.duration/Rules.STEP): sim._advance_arrows()
	view.advance_effects(0)
	check(view.effects.size()==1 and view.effects[0].strike.is_equal_approx(endpoint) and view.last_sound.has(5),"the arrival cue and flash use the visible arrow endpoint even if the target moves")
	check(view.draw_frames.shang_cavalry[43].cloth!=null and view.draw_frames.zhou_cavalry[44].cloth!=null and view.draw_frames.zhou_cavalry[31].cloth==null,"cloth follow-through is confined to the cavalry charge contact and recovery poses")
	view.free()
	check_spear_contacts()
	print("TROOP_FEEDBACK_CHECK ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func check_spear_contacts() -> void:
	var view:=View.new()
	view.setup({"player":{"id":"nezha","soldiers":300},"enemy":{"id":"wenzhong","soldiers":300}})
	var sim:=view.sim
	var hero:=sim.hero_for(0)
	var primary: Rules.Fighter=sim.sides[1][1]
	var adjacent: Rules.Fighter=sim.sides[1][2]
	var distant: Rules.Fighter=sim.sides[1][3]
	hero.pos=Vector2(800,350)
	primary.pos=hero.pos+Vector2(100,0)
	adjacent.pos=primary.pos+Vector2(-48,40)
	distant.pos=primary.pos+Vector2(290,0)
	sim.sides[0][1].pos=adjacent.pos
	sim.hero_for(1).pos=distant.pos
	sim._begin(hero,primary,"attack")
	for beat in [1,2]:
		hero.hit_index=beat-1
		sim._resolve_attack(hero,.5)
		var after_damage:=Vector2(primary.hp,adjacent.hp)
		view.advance_effects(0)
		check(view.troop_impacts.size()==2 and view.troop_impacts.has(primary.id) and view.troop_impacts.has(adjacent.id),"only the two actually hit enemy bodies react")
		var thrust: Dictionary=view.troop_impacts[primary.id]
		var splash: Dictionary=view.troop_impacts[adjacent.id]
		check(view.spear_marks.size()==2 and is_same(view.spear_marks[primary.id],thrust) and is_same(view.spear_marks[adjacent.id],splash),"each spark is drawn in its victim's depth layer")
		check(thrust.kind=="hit" and splash.kind=="splash_hit" and thrust.spear_beat==beat and splash.spear_beat==beat,"both victim events retain their originating jab")
		check(splash.splash_origin==primary.pos and thrust.incoming.x>0 and splash.incoming.x<0,"neighbour recoils away from the struck soldier")
		check(thrust.recoil>splash.recoil,"primary thrust reads more strongly than a splash")
		var ground_point:=view.ground(primary.pos)
		for flip in [true,false]:
			var recoil:=View.ImpactArt.recoil_transform(ground_point,1,flip,View.SOLDIER_HEIGHT,thrust)
			check(recoil*Vector2.ZERO==ground_point and (recoil*Vector2(0,-84)).x>ground_point.x,"grounded soles and forward impulse in both sprite facings")
		view.advance_effects(.24)
		check(view.troop_impacts.is_empty() and view.spear_marks.is_empty() and Vector2(primary.hp,adjacent.hp)==after_damage,"local recovery expires without further damage")
	primary.pos=distant.pos
	sim._resolve_attack(hero,.5)
	view.advance_effects(0)
	check(view.troop_impacts.is_empty() and view.effects.is_empty(),"missed spear produces no contact or splash")
	view.free()
