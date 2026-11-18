extends RefCounted
## Deterministic, fixed-step combat. Ground coordinates drive both collision and rendering.
const STEP := 1.0 / 60.0
const INTRO := 3.0
const LIMIT := 75.0
const Catalog=preload("res://scripts/unit_catalog.gd")
const FINISHER_COST := 100
const PEOPLE_PER_MODEL := 100
const GROUND_MIN := Vector2(55, -25)
const GROUND_MAX := Vector2(1865, 740)
const INFANTRY_RADIUS := 32.0
const INFANTRY_SPEED := 160.0
const INFANTRY_REACH := 92.0
const SUPPORT_REACH := 145.0
const CONTACT_TOLERANCE := 20.0
# The collision disk includes stance and equipment. The thrust must clear the body inside it.
const TORSO_RADIUS_RATIO := .80
const LOOK_AHEAD := 82.0
# Reachable standing positions around an opponent, mirrored for the other army.
const CONTACT_OFFSETS := [
	Vector2(-83, 0), Vector2(-55, -64), Vector2(-55, 64),
	Vector2(0, -83), Vector2(0, 83), Vector2(53, -65), Vector2(53, 65),
]
const BYPASS_ANGLES := [PI / 4, PI * 0.40, PI * 0.5]
const TYPES := {
	"halberd": {"name":"戟兵", "share":3, "available":true},
	"archer": {"name":"弓兵", "share":2, "available":true},
	"cavalry": {"name":"骑兵", "share":1, "available":true},
}
const ARCHER_RANGE := 565.0
const ARCHER_RETREAT := 180.0
const ARROW_SPEED := 800.0
const RIDE_SPEED := 205.0
const CHARGE_SPEED := 340.0
const CHARGE_REACH := 111.0
const CHARGE_MULTIPLIER := 1.8
const CHARGE_LIMIT := 4.0

class Fighter:
	var id: int
	var side: int
	var hero := false
	var hero_id := ""
	var normal_attack: Dictionary = {}
	var normal_hits := 0
	var support_strike := false
	var hit_index := 0
	var released := false
	var cast_origin := Vector2.ZERO
	var cast_target := Vector2.ZERO
	var burns: Dictionary = {}
	var magic_hit_age := 99.0
	var slot := 0
	var troop_type := "halberd"
	var charge_ready := false
	var previous_pos := Vector2.ZERO
	var ground_velocity := Vector2.ZERO
	var people := 0
	var pos := Vector2.ZERO
	var radius := INFANTRY_RADIUS
	var hp := 100.0
	var max_hp := 100.0
	var facing := 1
	var cooldown := 0.0
	var skill_clock := 0.0
	var action := "idle"
	var age := 0.0
	var impact := 0.32
	var duration := 0.68
	var applied := false
	var target := -1
	var hit_age := 99.0
	var death_age := 0.0
	var walking := false
	var march_origin := Vector2.ZERO
	var heading := Vector2.ZERO
	var approach_enemy := -1
	var approach_offset := Vector2.ZERO
	var steer_in := 0.0
	var stride := 0.0
	var velocity := Vector2.ZERO
	var attributes: Dictionary={}

	func survivors() -> int:
		return clampi(ceili(hp), 0, people)

class Arrow:
	var source: Fighter
	var target: Fighter
	var origin: Vector2
	var destination: Vector2
	var age := 0.0
	var duration: float
	var facing: int

var arrows: Array[Arrow] = []
var fighters: Array[Fighter] = []
var sides: Array[Array] = [[],[]]
var events: Array[Dictionary] = []
var elapsed := 0.0
var initial: Array[int] = []
var opening_morale: Array[int] = []
var morale: Array[float] = []
var kills: Array[int]=[0,0]
var kits: Array[Dictionary]=[]
var next_contact_plan := INTRO
var result: Dictionary = {}
var encounter: Dictionary
var stats := {"attacks": 0, "skills": 0, "finishers": 0, "collisions": 0}

static func roster(count: int) -> Array:
	# Encounters and saves predating troop composition fielded only halberdiers.
	return [{"type": "halberd", "count": count}, {}, {}]

static func mixed_roster(count: int) -> Array:
	return resize_roster([{"type":"halberd","count":0}, {"type":"archer","count":0}, {"type":"cavalry","count":0}], count)

static func resize_roster(slots: Array, count: int, recruit := false) -> Array:
	var updated := slots.duplicate(true)
	if recruit:
		var present: Array = []
		for slot in updated:
			if not slot.is_empty(): present.append(slot.type)
		for kind in TYPES:
			if not kind in present: updated[updated.find({})] = {"type":kind, "count":0}
	var old := 0
	for slot in updated: old += int(slot.get("count", 0))
	var gain := count >= old
	var budget := count - old if gain else count
	var weights: Array[int] = []
	var total_weight := 0
	for slot in updated:
		var weight := 0
		if not slot.is_empty(): weight = int(TYPES[slot.type].share) if gain else int(slot.count)
		weights.append(weight)
		total_weight += weight
	if total_weight == 0: return updated
	# Largest remainders preserve the exact total, including the last individual.
	var residues: Array[int] = []
	var left := budget
	for i in updated.size():
		var product := budget * weights[i]
		var amount := product / total_weight
		residues.append(product % total_weight if weights[i] > 0 else -1)
		if not updated[i].is_empty(): updated[i].count = (int(updated[i].count) if gain else 0) + amount
		left -= amount
	for extra in left:
		var i := residues.find(residues.max())
		updated[i].count += 1
		residues[i] = -1
	return updated

static func valid_roster(slots: Variant, count := -1) -> bool:
	if not slots is Array or slots.size() != 3: return false
	var kinds: Array = []
	var total := 0
	for slot in slots:
		if not slot is Dictionary: return false
		if slot.is_empty(): continue
		if not TYPES.has(slot.get("type", "")) or slot.type in kinds: return false
		var n: Variant = slot.get("count", -1)
		if not (n is int or n is float) or not is_finite(float(n)) or float(n) != floor(float(n)) or n < 0 or n > 10000: return false
		kinds.append(slot.type)
		total += int(n)
	return not kinds.is_empty() and (count == -1 or total == count)

func _init(data: Dictionary) -> void:
	encounter = data.duplicate(true)
	initial.assign([int(data.player.soldiers), int(data.enemy.soldiers)])
	opening_morale.assign([int(Catalog.DATA.morale.opening),int(Catalog.DATA.morale.opening)])
	morale.assign(opening_morale)
	kits.assign([Catalog.profile(data.player).skills,Catalog.profile(data.enemy).skills])
	_spawn(0, initial[0])
	_spawn(1, initial[1])

func _spawn(side: int, count: int) -> void:
	var hero := Fighter.new()
	hero.id = fighters.size()
	hero.side = side
	hero.hero = true
	hero.radius = 38.0
	var commander: Dictionary=encounter.player if side==0 else encounter.enemy
	hero.hero_id = Catalog.hero_id(commander)
	hero.normal_attack = Catalog.profile(commander).get("normal_attack", {}).duplicate(true)
	hero.attributes=Catalog.effective_stats(commander)
	hero.hp = float(hero.attributes.max_hp)
	hero.max_hp = hero.hp
	hero.pos = Vector2(55 if side == 0 else 1865, 720)
	hero.facing = 1 if side == 0 else -1
	hero.cooldown = 0.2
	hero.skill_clock = 3.0 + side * 0.8
	fighters.append(hero)
	sides[side].append(hero)
	var slots: Variant = commander.get("troops", roster(count))
	if not valid_roster(slots, count):
		slots = resize_roster(slots, count) if valid_roster(slots) else roster(count)
	commander.troops = slots
	var troops: Array[Fighter] = []
	var mounted := 0
	var companies := 0
	for slot_index in slots.size():
		var slot: Dictionary = slots[slot_index]
		var people := int(slot.get("count", 0))
		if people > 0: companies += 1
		for model in ceili(people / float(PEOPLE_PER_MODEL)):
			var f := Fighter.new()
			f.slot = slot_index
			f.troop_type = slot.type
			f.people = mini(PEOPLE_PER_MODEL, people - model * PEOPLE_PER_MODEL)
			f.side = side
			f.facing = hero.facing
			f.attributes = Catalog.effective_stats(commander, f.troop_type)
			f.max_hp = float(f.people)
			f.attributes.max_hp = f.max_hp
			f.hp = f.max_hp
			f.charge_ready = f.troop_type == "cavalry"
			if f.charge_ready:
				mounted += 1
				f.radius = 36.0
			troops.append(f)
	var points := _deployment_points(troops.size())
	# Deep companies have less ground behind the rearmost rank. Tight files
	# keep their spacing rather than pushing neighbouring soldiers together.
	var rear_space := clampf((points.back().x - GROUND_MIN.x) / 256.0, 0.0, 1.0) if not points.is_empty() else 0.0
	var file_spacing := points[1].y - points[0].y if points.size() > 1 else 94.0
	var flank_space := clampf((file_spacing - 66.0) / 28.0, 0.0, 1.0)
	var flanks := points.duplicate()
	flanks.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x + absf(a.y - 350.0) > b.x + absf(b.y - 350.0))
	flanks.resize(mounted)
	for flank in flanks: points.erase(flank)
	# Cavalry have open lanes on the wings. Halberdiers take the forward
	# positions and archers the rear, independently of the order of roster slots.
	for kind in ["cavalry", "halberd", "archer"]:
		var file_index := 0
		for f in troops:
			if f.troop_type != kind: continue
			f.pos = flanks.pop_front() if f.charge_ready else points.pop_front()
			if companies > 1: f.pos = _stagger_company(f.pos, kind, side, file_index, rear_space, flank_space)
			if side == 1: f.pos.x = 1920.0 - f.pos.x
			file_index += 1
			var index := sides[side].size() - 1
			f.id = fighters.size()
			f.cooldown = (index % 7) * 0.07
			f.stride = index * 0.053
			fighters.append(f)
			sides[side].append(f)

func _stagger_company(point: Vector2, kind: String, side: int, file_index: int, room: float, flank_space: float) -> Vector2:
	# Echelon the actual ground slots. The bow line stands behind the pikes;
	# the nearest cavalry wing starts further forward and meets first.
	var depth := (point.y - 350.0) / 350.0
	if kind == "archer":
		point.x -= (112.0 + 40.0 * (file_index % 2) * flank_space) * room
		point.y += (20.0 - 26.0 * depth) * flank_space
	elif kind == "cavalry":
		point.x += (35.0 + 42.0 * depth) * room
	else:
		point.y -= 75.0 * depth * flank_space
	point.x += (1.0 if side == 0 else -1.0) * 99.0 * depth * room
	return point.clamp(GROUND_MIN, GROUND_MAX)

func _deployment_points(models: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var files := clampi(ceili(sqrt(models * 2.5)), 1, 11)
	var ranks := ceili(models / float(files))
	var file_spacing := minf(94.0, 660.0 / maxi(1, files - 1))
	var rank_spacing := minf(94.0, 625.0 / maxi(1, ranks - 1))
	for i in models:
		var rank := i / files
		var rank_size := mini(files, models - rank * files)
		var file := i % files + (files - rank_size) / 2
		var lane := file - (files - 1) * 0.5
		if ranks > 1: lane += 0.25 if rank % 2 else -0.25
		points.append(Vector2(700 - rank * rank_spacing, 350 + lane * file_spacing))
	return points

func remaining_roster(side: int) -> Array:
	var unit: Dictionary = encounter.player if side == 0 else encounter.enemy
	var slots: Array = unit.troops.duplicate(true)
	for slot in slots:
		if not slot.is_empty(): slot.count = 0
	for f: Fighter in sides[side]:
		if not f.hero: slots[f.slot].count += f.survivors()
	return slots

func hero_for(side: int) -> Fighter:
	for f in fighters:
		if f.hero and f.side == side: return f
	return null

func remaining(side: int) -> int:
	var count := 0
	for f: Fighter in sides[side]:
		count += f.survivors()
	return count

func finisher_reason(side: int) -> String:
	if not result.is_empty(): return "战斗已结束"
	if hero_for(side).hp <= 0: return "主将已退场"
	if elapsed<INTRO: return "列阵中"
	if morale[side]+.00001<FINISHER_COST: return "士气 %d / 100 · 击杀积累" % floori(morale[side]+.00001)
	if hero_for(side).action=="finisher": return "终结技施放中"
	return ""

func use_finisher(side: int) -> bool:
	if not finisher_reason(side).is_empty(): return false
	var hero := hero_for(side)
	var target := _nearest(hero)
	if target == null: return false
	morale[side] = maxf(0,morale[side]-FINISHER_COST)
	if hero.action in ["attack","cast"]:
		events.append({"kind":"interrupt","source":hero.id,"side":side})
	hero.walking=false
	hero.velocity=Vector2.ZERO
	hero.facing=1 if target.pos.x>=hero.pos.x else -1
	_begin(hero, target, "finisher")
	return true

func advance() -> void:
	if not result.is_empty(): return
	elapsed += STEP
	if elapsed < INTRO: return
	_advance_burns()
	_advance_arrows()
	if elapsed >= next_contact_plan:
		_assign_contacts(0)
		_assign_contacts(1)
		next_contact_plan = elapsed + 0.40
	# Enemy obeys the same kill-earned resource gate; player release stays manual.
	use_finisher(1)
	for f in fighters:
		f.previous_pos = f.pos
		f.hit_age += STEP
		f.magic_hit_age += STEP
		f.walking = false
		if f.hp <= 0:
			f.death_age += STEP
			continue
		f.cooldown -= STEP
		if f.hero: f.skill_clock -= STEP
		else: f.steer_in -= STEP
		f.pos += f.velocity * STEP
		f.velocity = f.velocity.move_toward(Vector2.ZERO, STEP * 500)
		if f.action in ["attack", "cast", "finisher", "charge_hit"]:
			f.age += STEP
			if f.hero_id == "nezha" and f.action == "cast" and not f.released and f.age >= float(kits[f.side].battle.release):
				f.released = true
				events.append({"kind":"ring", "source":f.id, "side":f.side, "from":f.cast_origin, "pos":f.cast_target,
					"facing":f.facing, "life":float(kits[f.side].battle.return_time)-float(kits[f.side].battle.release)})
			if f.action == "attack" and not f.normal_attack.is_empty():
				while f.hit_index < f.normal_attack.hits.size() and f.age + .000001 >= float(f.normal_attack.hits[f.hit_index]):
					_resolve_attack(f, float(f.normal_attack.multipliers[f.hit_index]))
					f.hit_index += 1
				f.applied = f.hit_index >= f.normal_attack.hits.size()
			elif not f.applied and f.age + .000001 >= f.impact:
				f.applied = true
				_resolve_attack(f)
			if f.age >= f.duration: f.action = "idle"
			continue
		var target := _nearest(f)
		if target == null: continue
		var delta := target.pos - f.pos
		f.facing = 1 if delta.x >= 0 else -1
		if not f.hero and f.troop_type == "archer":
			_archer_turn(f, target, delta)
			continue
		if f.charge_ready or f.action == "charge_run":
			_charge_turn(f, target, delta)
			continue
		var reach := 150.0 if f.hero else INFANTRY_REACH
		var distance_squared := delta.length_squared()
		if f.hero and f.skill_clock <= 0 and distance_squared <= 350.0*350.0:
			_begin(f, target, "cast")
		elif distance_squared <= reach*reach:
			if f.cooldown <= 0: _begin(f, target, "attack")
		else:
			_approach(f, target, delta)
	_resolve_bodies()
	for f in fighters:
		f.ground_velocity = (f.pos - f.previous_pos) / STEP
		if f.walking and not f.hero:
			var speed := CHARGE_SPEED if f.action == "charge_run" else (RIDE_SPEED if f.troop_type == "cavalry" else INFANTRY_SPEED)
			var travel := minf(f.march_origin.distance_to(f.pos), speed * STEP)
			f.walking = travel > .2
			f.stride += travel / speed
	if remaining(0) == 0 or remaining(1) == 0 or elapsed >= INTRO + LIMIT:
		_finish()

# Reserve distinct, unoccupied melee positions. A rear rank can take an open
# shoulder of a different opponent instead of following the same nearest body.
func _assign_contacts(side: int) -> void:
	var points := PackedVector2Array()
	var enemies := PackedInt32Array()
	var mirror := Vector2(1 if side == 0 else -1, 1)
	for enemy: Fighter in sides[1 - side]:
		if enemy.hp <= 0: continue
		# Only bodies within one weapon length plus a pair of radii can cover a site.
		var nearby: Array[Fighter] = []
		for body in fighters:
			if body.hp > 0 and body != enemy and enemy.pos.distance_squared_to(body.pos) < 156.0 * 156.0:
				nearby.append(body)
		for offset: Vector2 in CONTACT_OFFSETS:
			var point := enemy.pos + offset * mirror
			if point != point.clamp(GROUND_MIN, GROUND_MAX): continue
			if _free_contact(point, nearby):
				points.append(point)
				enemies.append(enemy.id)
	var taken := PackedByteArray()
	taken.resize(points.size())
	for f: Fighter in sides[side]:
		if f.hero or f.hp <= 0 or f.troop_type == "archer" or f.charge_ready or f.action != "idle": continue
		if f.target >= 0:
			var target := fighters[f.target]
			if target.hp > 0 and f.pos.distance_squared_to(target.pos) <= INFANTRY_REACH * INFANTRY_REACH:
				continue
		var best := -1
		var best_distance := INF
		for i in points.size():
			if taken[i]: continue
			var distance := f.pos.distance_to(points[i])
			if enemies[i] == f.approach_enemy: distance -= 26.0
			if distance < best_distance:
				best = i
				best_distance = distance
		f.approach_enemy = -1
		if best < 0: continue
		f.approach_enemy = enemies[best]
		f.approach_offset = points[best] - fighters[f.approach_enemy].pos
		for i in points.size():
			if points[best].distance_squared_to(points[i]) < (2.0 * INFANTRY_RADIUS) ** 2:
				taken[i] = 1

func _free_contact(point: Vector2, nearby: Array[Fighter]) -> bool:
	for body in nearby:
		var separation := INFANTRY_RADIUS + body.radius
		if point.distance_squared_to(body.pos) < separation * separation: return false
	return true

func _approach(f: Fighter, target: Fighter, delta: Vector2) -> void:
	var direction := delta.normalized()
	f.march_origin = f.pos
	if f.hero:
		f.pos += direction * 190.0 * STEP
		f.stride += STEP
	else:
		if f.approach_enemy >= 0 and fighters[f.approach_enemy].hp > 0:
			direction = f.pos.direction_to(fighters[f.approach_enemy].pos + f.approach_offset)
		if f.steer_in <= 0 or f.heading.dot(direction) < -.25:
			if f.troop_type == "halberd" and f.cooldown <= 0 and delta.length_squared() <= SUPPORT_REACH*SUPPORT_REACH:
				var support_target := _support_target(f, target)
				if support_target != null:
					f.facing = 1 if support_target.pos.x >= f.pos.x else -1
					_begin(f, support_target, "attack", true)
					return
			f.heading = _infantry_heading(f, direction)
			f.steer_in = (9 + f.id % 4) * STEP
		f.pos += f.heading * (RIDE_SPEED if f.troop_type == "cavalry" else INFANTRY_SPEED) * STEP
	f.walking = true

func _march(f: Fighter, direction: Vector2, speed: float) -> void:
	f.march_origin = f.pos
	if f.steer_in <= 0 or f.heading.dot(direction) < 0.0:
		f.heading = _infantry_heading(f, direction)
		f.steer_in = (6 + f.id % 4) * STEP
	f.pos += f.heading * speed * STEP
	f.walking = true

func _archer_turn(f: Fighter, target: Fighter, delta: Vector2) -> void:
	var distance := delta.length()
	if distance > ARCHER_RANGE:
		_march(f, delta.normalized(), INFANTRY_SPEED)
	elif f.cooldown <= 0:
		_begin(f, target, "attack")
	elif distance < ARCHER_RETREAT:
		_march(f, -delta.normalized(), INFANTRY_SPEED * 0.8)

func _charge_turn(f: Fighter, target: Fighter, delta: Vector2) -> void:
	if f.charge_ready:
		f.charge_ready = false
		f.action = "charge_run"
		f.age = 0
		f.steer_in = 0
		stats["charges"] = int(stats.get("charges", 0)) + 1
	f.age += STEP
	if delta.length_squared() <= CHARGE_REACH * CHARGE_REACH:
		_begin(f, target, "charge_hit")
	elif f.age >= CHARGE_LIMIT:
		f.action = "idle"
		f.steer_in = 0
	else:
		_march(f, delta.normalized(), CHARGE_SPEED)

func _release_arrow(f: Fighter, target: Fighter) -> void:
	if target.hp <= 0 or f.pos.distance_to(target.pos) > ARCHER_RANGE + CONTACT_TOLERANCE: return
	var arrow := Arrow.new()
	arrow.source = f
	arrow.target = target
	arrow.facing = 1 if target.pos.x >= f.pos.x else -1
	f.facing = arrow.facing
	arrow.origin = f.pos
	var flight := f.pos.distance_to(target.pos) / ARROW_SPEED
	var lead := target.ground_velocity.limit_length(CHARGE_SPEED) * flight * 0.75
	arrow.destination = (target.pos + lead).clamp(GROUND_MIN, GROUND_MAX)
	arrow.duration = maxf(0.12, f.pos.distance_to(arrow.destination) / ARROW_SPEED)
	arrows.append(arrow)
	events.append({"kind":"bow_release", "source":f.id, "side":f.side, "pos":arrow.origin})
	stats["arrows"] = int(stats.get("arrows", 0)) + 1

func _advance_arrows() -> void:
	for i in range(arrows.size() - 1, -1, -1):
		var arrow := arrows[i]
		arrow.age += STEP
		if arrow.age + 0.000001 < arrow.duration: continue
		arrows.remove_at(i)
		var target := arrow.target
		if target.hp <= 0 or target.pos.distance_to(arrow.destination) > target.radius + 15.0: continue
		_damage(arrow.source, target, Catalog.damage(arrow.source.attributes, target.attributes, "physical"), "arrow_hit", "physical", arrow.destination)
		arrow.source.normal_hits += 1
		stats["arrow_hits"] = int(stats.get("arrow_hits", 0)) + 1

# A second-rank halberd can reach through a gap beside an engaged ally. A
# friendly torso on the weapon segment blocks the thrust, including at impact.
func _thrust_lane(f: Fighter, target: Fighter, require_front: bool) -> bool:
	var delta := target.pos - f.pos
	var distance := delta.length()
	if distance <= .001: return false
	var direction := delta / distance
	var has_front := false
	for body in fighters:
		if body == f or body == target or body.hp <= 0: continue
		var offset := body.pos - f.pos
		var ahead := offset.dot(direction)
		if ahead <= 0 or ahead >= distance: continue
		if absf(offset.cross(direction)) < body.radius * TORSO_RADIUS_RATIO: return false
		if (require_front and body.side == f.side and offset.length_squared() <= 100.0 * 100.0
				and body.pos.distance_squared_to(target.pos) <= 100.0 * 100.0):
			has_front = true
	return has_front or not require_front

func _support_target(f: Fighter, nearest: Fighter) -> Fighter:
	if _thrust_lane(f, nearest, true): return nearest
	var best: Fighter
	var best_distance := SUPPORT_REACH * SUPPORT_REACH
	for enemy: Fighter in sides[1 - f.side]:
		if enemy == nearest or enemy.hp <= 0: continue
		var distance := f.pos.distance_squared_to(enemy.pos)
		if distance <= best_distance and _thrust_lane(f, enemy, true):
			best = enemy
			best_distance = distance
	return best

# Search short, body-wide paths around the soldiers immediately ahead. The
# physical separation solver remains authoritative at the end of every step.
func _infantry_heading(f: Fighter, forward: Vector2) -> Vector2:
	var nearby: Array[Fighter] = []
	for ally: Fighter in sides[f.side]:
		if ally != f and ally.hp > 0 and f.pos.distance_squared_to(ally.pos) < 155.0 * 155.0:
			nearby.append(ally)
	var open := _clearance(f, forward, nearby)
	if open >= LOOK_AHEAD * 0.8: return forward
	var best := forward if open > 1.0 else Vector2.ZERO
	var best_score := open + 26.0 + forward.dot(f.heading) * 9.0 if open > 1.0 else -INF
	var turn := 1 if (f.pos.y > 350) == (forward.x > 0) else -1
	for angle: float in BYPASS_ANGLES:
		for turn_sign: int in [turn, -turn]:
			var candidate := forward.rotated(turn_sign * angle)
			var clearance := _clearance(f, candidate, nearby)
			if clearance <= 1.0: continue
			var score := clearance + candidate.dot(forward) * 26.0 + candidate.dot(f.heading) * 9.0
			if score > best_score + 0.01:
				best_score = score
				best = candidate
	return best

func _clearance(f: Fighter, direction: Vector2, nearby: Array[Fighter]) -> float:
	var distance := LOOK_AHEAD
	if direction.y > .001: distance = minf(distance, (GROUND_MAX.y - f.pos.y) / direction.y)
	elif direction.y < -.001: distance = minf(distance, (GROUND_MIN.y - f.pos.y) / direction.y)
	if direction.x > .001: distance = minf(distance, (GROUND_MAX.x - f.pos.x) / direction.x)
	elif direction.x < -.001: distance = minf(distance, (GROUND_MIN.x - f.pos.x) / direction.x)
	for ally in nearby:
		var delta := ally.pos - f.pos
		var ahead := direction.dot(delta)
		if ahead <= 0: continue
		var across := direction.cross(delta)
		var width := f.radius + ally.radius
		if absf(across) >= width: continue
		distance = minf(distance, ahead - sqrt(maxf(0.0, width * width - across * across)))
	return maxf(0.0, distance)

func _nearest(f: Fighter) -> Fighter:
	var best: Fighter
	var distance := INF
	for other: Fighter in sides[1-f.side]:
		if other.hp <= 0: continue
		var d := f.pos.distance_squared_to(other.pos)
		if d < distance:
			distance = d
			best = other
	return best

func _begin(f: Fighter, target: Fighter, kind: String, support := false) -> void:
	f.action = kind
	f.support_strike = support
	f.steer_in = 0.0
	f.age = 0
	f.applied = false
	f.hit_index = 0
	f.released = false
	f.target = target.id
	f.cast_origin = f.pos
	f.cast_target = target.pos
	if not f.hero and f.troop_type != "halberd":
		match kind:
			"charge_hit":
				f.impact = 0.14
				f.duration = 0.46
			"attack":
				f.impact = 0.42 if f.troop_type == "archer" else 0.32
				f.duration = 0.85 if f.troop_type == "archer" else 0.68
		f.cooldown = f.duration + (0.85 if f.troop_type == "archer" else 0.7)
		return
	var ability: Dictionary=kits[f.side].ultimate if kind=="finisher" else kits[f.side].battle
	f.impact = float(ability.windup) if kind!="attack" else .32
	f.duration = f.impact + (0.55 if kind != "attack" else 0.36)
	if not f.normal_attack.is_empty() and kind == "attack":
		f.impact = float(f.normal_attack.hits[0])
		f.duration = float(f.normal_attack.duration)
	elif f.hero_id == "nezha":
		f.duration = float(ability.duration)
		if kind == "cast":
			var direction := (target.pos - f.pos).normalized()
			if direction == Vector2.ZERO: direction = Vector2(f.facing, 0)
			f.cast_target = f.pos + direction * float(ability.range)
	f.cooldown = f.duration + (0.4 if f.hero else 0.7)
	if kind == "cast": f.skill_clock = float(ability.cooldown)
	if kind != "attack": events.append({"kind": "windup", "source": f.id, "pos": f.pos, "side": f.side})

func _resolve_attack(f: Fighter, hit_multiplier: float = 1.0) -> void:
	var target: Fighter = fighters[f.target]
	if f.action == "charge_hit":
		if target.hp > 0 and f.pos.distance_to(target.pos) <= CHARGE_REACH + CONTACT_TOLERANCE:
			var normal := Catalog.damage(f.attributes, target.attributes, "physical")
			_damage(f, target, normal * CHARGE_MULTIPLIER, "charge_hit")
			stats["charge_hits"] = int(stats.get("charge_hits", 0)) + 1
		return
	if f.action == "attack":
		stats.attacks += 1
		if not f.hero and f.troop_type == "archer":
			_release_arrow(f, target)
			return
		# Damage belongs to the contact frame and still requires live reach.
		var reach := 174.0 if f.hero else INFANTRY_REACH+CONTACT_TOLERANCE
		if f.support_strike: reach=SUPPORT_REACH
		if target.hp > 0 and f.pos.distance_squared_to(target.pos) <= reach*reach and (not f.support_strike or _thrust_lane(f,target,false)):
			_damage(f,target,Catalog.damage(f.attributes,target.attributes,"physical",hit_multiplier),"hit")
			_resolve_splash(f,target,hit_multiplier)
			f.normal_hits += 1
			if f.hero_id == "nezha" and f.normal_hits % int(f.normal_attack.burn_every_hits) == 0:
				apply_burn(f, target)
		return
	var finisher := f.action == "finisher"
	stats["finishers" if finisher else "skills"] += 1
	var center := f.cast_target if f.hero_id == "nezha" else target.pos
	var ability: Dictionary=kits[f.side].ultimate if finisher else kits[f.side].battle
	events.append({"kind": "finisher" if finisher else "skill", "source": f.id, "pos": center, "side": f.side, "ability":ability.id})
	for enemy: Fighter in sides[1-f.side]:
		if enemy.hp <= 0: continue
		var in_area := enemy.pos.distance_to(center) <= float(ability.radius)
		if f.hero_id == "nezha" and not finisher:
			var segment := center - f.cast_origin
			var projection := (enemy.pos-f.cast_origin).dot(segment) / maxf(1.0,segment.length_squared())
			var closest := f.cast_origin + segment * clampf(projection,0,1)
			in_area = projection >= 0 and projection <= 1 and enemy.pos.distance_to(closest) <= float(ability.width)
		if not in_area: continue
		var multiplier := float(ability.multiplier)
		if finisher and f.hero_id == "nezha":
			var stacks := burn_stacks(enemy, f.id)
			multiplier += mini(stacks,int(ability.detonation_cap)) * float(ability.detonation_per_stack)
			enemy.burns.erase(f.id)
			if stacks > 0: events.append({"kind":"detonate", "pos":enemy.pos, "side":f.side, "source":f.id, "target":enemy.id, "stacks":stacks})
		_damage(f,enemy,Catalog.damage(f.attributes,enemy.attributes,ability.damage_type,multiplier),"finisher_hit" if finisher else "skill_hit", ability.damage_type)
		if not finisher and f.hero_id == "nezha": apply_burn(f, enemy)

func burn_stacks(target: Fighter, source_id: int = -1) -> int:
	if source_id >= 0: return int(target.burns.get(source_id, {}).get("stacks", 0))
	var total := 0
	for burn in target.burns.values(): total += int(burn.stacks)
	return total

func apply_burn(source: Fighter, target: Fighter) -> void:
	if target.hp <= 0 or source.side == target.side or source.hero_id != "nezha": return
	var spec: Dictionary = Catalog.DATA.heroes.nezha.burn
	var burn: Dictionary = target.burns.get(source.id, {"stacks":0, "tick":float(spec.interval)})
	burn.stacks = mini(int(spec.max_stacks), int(burn.stacks) + 1)
	burn.remaining = float(spec.duration)
	burn.damage = Catalog.damage(source.attributes,target.attributes,"magic",float(spec.multiplier_per_stack))
	target.burns[source.id] = burn

func _advance_burns() -> void:
	for target in fighters:
		if target.hp <= 0:
			target.burns.clear()
			continue
		for source_id in target.burns.keys():
			if target.hp <= 0: break
			var burn: Dictionary = target.burns[source_id]
			burn.remaining -= STEP
			burn.tick -= STEP
			if float(burn.tick) <= .000001 and float(burn.remaining) >= -.000001:
				burn.tick += float(Catalog.DATA.heroes.nezha.burn.interval)
				_damage(fighters[int(source_id)],target,float(burn.damage)*int(burn.stacks),"burn_hit","magic")
			if float(burn.remaining) <= .000001: target.burns.erase(source_id)

func _resolve_splash(source: Fighter, primary: Fighter, hit_multiplier: float) -> void:
	if not source.hero: return
	var passive: Dictionary=kits[source.side].passive
	if passive.id!="three_heads_six_arms": return
	# Resolve directly through damage: secondary contacts cannot trigger another
	# attack, burn counter or splash. A killing primary blow still splashes.
	for enemy: Fighter in sides[1-source.side]:
		if enemy.id==primary.id or enemy.hp<=0: continue
		if enemy.pos.distance_squared_to(primary.pos)>pow(float(passive.splash_radius),2): continue
		var amount:=Catalog.damage(source.attributes,enemy.attributes,"physical",hit_multiplier*float(passive.splash_multiplier))
		_damage(source,enemy,amount,"splash_hit")
		stats["splash_hits"]=int(stats.get("splash_hits",0))+1

func _damage(source: Fighter, target: Fighter, amount: float, kind: String, damage_type: String = "physical", contact: Vector2 = Vector2.INF) -> void:
	if target.hp<=0 or source.side==target.side: return
	var before:=target.survivors()
	var actual := minf(target.hp, amount)
	target.hp = maxf(0, target.hp - amount)
	var defeated:=before-target.survivors()
	kills[source.side]+=defeated
	morale[source.side]=minf(100,morale[source.side]+defeated*float(Catalog.DATA.morale.per_kill))
	if kind != "burn_hit":
		target.hit_age = 0
		target.velocity = (target.pos - source.pos).normalized() * (24.0 if kind in ["hit","splash_hit","arrow_hit"] else 110.0)
	if damage_type == "magic" and target.magic_hit_age >= .4: target.magic_hit_age = 0
	if target.hp <= 0:
		target.walking = false
		target.action = "fall"
		target.age = 0
		target.burns.clear()
	if contact == Vector2.INF:
		contact = target.pos + target.pos.direction_to(source.pos) * target.radius * .55
	var hit := {"kind":kind, "pos":target.pos, "contact":contact, "origin":source.pos, "facing":source.facing,
		"side":source.side, "source":source.id, "amount":roundi(actual) if target.hero else defeated, "target":target.id, "damage_type":damage_type}
	if source.hero_id=="nezha" and kind in ["hit","splash_hit"]:
		# Capture the contact before the attacker advances to the next drawing or changes target.
		hit.spear_beat=clampi(source.hit_index+1,1,2)
		if kind=="splash_hit" and source.target>=0:
			hit.splash_origin=fighters[source.target].pos
			hit.contact=target.pos+target.pos.direction_to(hit.splash_origin)*target.radius*.55
	events.append(hit)

func _resolve_bodies() -> void:
	# Symmetric circle separation for allies AND enemies, including heroes.
	# Iterating removes residual penetration from dense multi-body contacts.
	var active: Array[int] = []
	var positions:=PackedVector2Array()
	var radii:=PackedFloat32Array()
	positions.resize(fighters.size())
	radii.resize(fighters.size())
	for f in fighters:
		positions[f.id]=f.pos
		radii[f.id]=f.radius
		if f.hp>0:
			active.append(f.id)
	if active.size()<2: return
	var collision_count:=0
	var bucket_heads:=PackedInt32Array()
	var bucket_next:=PackedInt32Array()
	bucket_heads.resize(512)
	bucket_next.resize(fighters.size())
	var neighbor_offsets:=PackedInt32Array([-33,-32,-31,-1,0,1,31,32,33])
	# 80px cells exceed the maximum 76px combined radius. Only the 3x3
	# neighborhood can touch. Rebuild each pass as separation moves bodies.
	# Stable fighter IDs + fixed neighbor order keep the simulation deterministic.
	for iteration in 6:
		var collisions_before:=collision_count
		var clamped:=false
		bucket_heads.fill(-1)
		# A dense linked bucket table avoids allocating dictionaries and arrays
		# for every cell in every solver pass. Reverse insertion retains ID order.
		for index in range(active.size()-1,-1,-1):
			var id:=active[index]
			var pos:=positions[id]
			var cell:=2+floori(pos.x/80.0)+(2+floori((pos.y+25.0)/80.0))*32
			bucket_next[id]=bucket_heads[cell]
			bucket_heads[cell]=id
		for a in active:
			var a_pos:=positions[a]
			var a_radius:=radii[a]
			var cell:=2+floori(a_pos.x/80.0)+(2+floori((a_pos.y+25.0)/80.0))*32
			for neighbor in neighbor_offsets:
				var b:=bucket_heads[cell+neighbor]
				while b>=0:
					var next:=bucket_next[b]
					if b<=a:
						b=next
						continue
					var delta:=positions[b]-a_pos
					var required:=a_radius+radii[b]
					var dist_squared:=delta.length_squared()
					if dist_squared>=required*required:
						b=next
						continue
					var dist:=sqrt(dist_squared)
					var direction:=delta/dist if dist>.001 else Vector2(0,1 if a%2==0 else -1)
					var offset:=direction*(required-dist+.01)*.5
					a_pos-=offset
					positions[b]+=offset
					collision_count+=1
					b=next
			positions[a]=a_pos
		for id in active:
			var bounded:=positions[id].clamp(GROUND_MIN,GROUND_MAX)
			if bounded!=positions[id]: clamped=true
			positions[id]=bounded
		# With no separation or boundary correction, another pass cannot move
		# anything. Dense contacts still receive all six solver iterations.
		if collision_count==collisions_before and not clamped: break
	for id in active: fighters[id].pos=positions[id]
	stats.collisions+=collision_count

func _finish() -> void:
	var left := remaining(0)
	var right := remaining(1)
	var won := left > 0 and (right == 0 or float(left) / maxi(1, initial[0]) > float(right) / maxi(1, initial[1]))
	arrows.clear()
	result = {"player_won": won, "player_remaining": left, "enemy_remaining": right,
		"player_troops":remaining_roster(0), "enemy_troops":remaining_roster(1),
		"morale": floori(morale[0]+.00001),"enemy_morale": floori(morale[1]+.00001),"kills":kills.duplicate(),
		"reason": "敌阵溃散" if right == 0 else ("我军溃退" if left == 0 else "时限到达 · 按剩余兵力比例判定"),
		"elapsed": elapsed, "stats": stats.duplicate()}
