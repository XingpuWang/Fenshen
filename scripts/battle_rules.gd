extends RefCounted
## Deterministic, fixed-step combat. Ground coordinates drive both collision and rendering.
const STEP := 1.0 / 60.0
const INTRO := 3.0
const LIMIT := 75.0
const Catalog=preload("res://scripts/unit_catalog.gd")
const FINISHER_COST := 100
const PEOPLE_PER_MODEL := 100
const TYPES := {"halberd": {"name": "戟兵", "available": true}, "archer": {"name": "弓兵", "available": false}, "cavalry": {"name": "骑兵", "available": false}}

class Fighter:
	var id: int
	var side: int
	var hero := false
	var slot := 0
	var people := 0
	var pos := Vector2.ZERO
	var radius := 32.0
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
	var stride := 0.0
	var velocity := Vector2.ZERO
	var attributes: Dictionary={}

var fighters: Array[Fighter] = []
var sides: Array[Array] = [[],[]]
var events: Array[Dictionary] = []
var elapsed := 0.0
var initial: Array[int] = []
var opening_morale: Array[int] = []
var morale: Array[float] = []
var kills: Array[int]=[0,0]
var kits: Array[Dictionary]=[]
var result: Dictionary = {}
var encounter: Dictionary
var stats := {"attacks": 0, "skills": 0, "finishers": 0, "collisions": 0}

static func roster(count: int) -> Array:
	return [{"type": "halberd", "count": count}, {}, {}]

static func valid_roster(slots: Variant, count: int) -> bool:
	if not slots is Array or slots.size() != 3: return false
	var kinds: Array = []
	var total := 0
	for slot in slots:
		if not slot is Dictionary: return false
		if slot.is_empty(): continue
		if not TYPES.has(slot.get("type", "")) or not TYPES[slot.type].available or slot.type in kinds: return false
		var n: Variant = slot.get("count", -1)
		if not (n is int or n is float) or not is_finite(float(n)) or float(n) != floor(float(n)) or n < 0 or n > 10000: return false
		kinds.append(slot.type)
		total += int(n)
	return total == count and not kinds.is_empty()

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
	hero.attributes=Catalog.effective_stats(commander)
	hero.hp = float(hero.attributes.max_hp)
	hero.max_hp = hero.hp
	hero.pos = Vector2(55 if side == 0 else 1865, 720)
	hero.facing = 1 if side == 0 else -1
	hero.cooldown = 0.2
	hero.skill_clock = 3.0 + side * 0.8
	fighters.append(hero)
	sides[side].append(hero)
	var models := ceili(count / float(PEOPLE_PER_MODEL))
	var rows := 3 if models<=24 else (5 if models<=42 else 7)
	var columns := ceili(models / float(rows))
	var spacing := minf(122.0, 570.0 / maxi(1, columns - 1))
	for i in models:
		var f := Fighter.new()
		f.id = fighters.size()
		f.side = side
		f.people = mini(PEOPLE_PER_MODEL, count - i * PEOPLE_PER_MODEL)
		f.pos = Vector2(700 - (i / rows) * spacing, (i % rows) * (600.0 / (rows - 1)) + 20)
		if side == 1: f.pos.x = 1920 - f.pos.x
		f.facing = hero.facing
		f.attributes=Catalog.effective_stats(commander,"halberd")
		f.max_hp = float(f.attributes.max_hp) * f.people / PEOPLE_PER_MODEL
		f.hp = f.max_hp
		f.cooldown = (i % 7) * 0.07
		f.stride = i * 0.053
		fighters.append(f)
		sides[side].append(f)

func hero_for(side: int) -> Fighter:
	for f in fighters:
		if f.hero and f.side == side: return f
	return null

func remaining(side: int) -> int:
	var count := 0
	for f: Fighter in sides[side]:
		if not f.hero:
			count += ceili(f.people * maxf(0, f.hp) / f.max_hp)
	return count

func finisher_reason(side: int) -> String:
	if not result.is_empty(): return "战斗已结束"
	if hero_for(side).hp <= 0: return "主将已退场"
	if elapsed<INTRO: return "列阵中"
	if morale[side]+.00001<FINISHER_COST: return "士气 %d / 100 · 击杀积累" % floori(morale[side]+.00001)
	if hero_for(side).action in ["attack", "cast", "finisher"]: return "等待主将收招"
	return ""

func use_finisher(side: int) -> bool:
	if not finisher_reason(side).is_empty(): return false
	var hero := hero_for(side)
	var target := _nearest(hero)
	if target == null: return false
	morale[side] = maxf(0,morale[side]-FINISHER_COST)
	_begin(hero, target, "finisher")
	return true

func advance() -> void:
	if not result.is_empty(): return
	elapsed += STEP
	if elapsed < INTRO: return
	# Enemy obeys the same kill-earned resource gate; player release stays manual.
	use_finisher(1)
	for f in fighters:
		f.hit_age += STEP
		f.walking = false
		if f.hp <= 0:
			f.death_age += STEP
			continue
		f.cooldown -= STEP
		if f.hero: f.skill_clock -= STEP
		f.pos += f.velocity * STEP
		f.velocity = f.velocity.move_toward(Vector2.ZERO, STEP * 500)
		if f.action in ["attack", "cast", "finisher"]:
			f.age += STEP
			if not f.applied and f.age >= f.impact:
				f.applied = true
				_resolve_attack(f)
			if f.age >= f.duration: f.action = "idle"
			continue
		var target := _nearest(f)
		if target == null: continue
		var delta := target.pos - f.pos
		f.facing = 1 if delta.x >= 0 else -1
		var reach := 150.0 if f.hero else 92.0
		if f.hero and f.skill_clock <= 0 and delta.length() <= 350:
			_begin(f, target, "cast")
		elif delta.length() <= reach:
			if f.cooldown <= 0: _begin(f, target, "attack")
		else:
			# Approach the closest exposed foe; body resolution prevents passing through units.
			var direction := delta.normalized()
			f.pos += direction * (190.0 if f.hero else 160.0) * STEP
			f.walking = true
			f.stride += STEP
	_resolve_bodies()
	if remaining(0) == 0 or remaining(1) == 0 or elapsed >= INTRO + LIMIT:
		_finish()

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

func _begin(f: Fighter, target: Fighter, kind: String) -> void:
	f.action = kind
	f.age = 0
	f.applied = false
	f.target = target.id
	var ability: Dictionary=kits[f.side].ultimate if kind=="finisher" else kits[f.side].battle
	f.impact = float(ability.windup) if kind!="attack" else .32
	f.duration = f.impact + (0.55 if kind != "attack" else 0.36)
	f.cooldown = f.duration + (0.4 if f.hero else 0.7)
	if kind == "cast": f.skill_clock = float(ability.cooldown)
	if kind != "attack": events.append({"kind": "windup", "source": f.id, "pos": f.pos, "side": f.side})

func _resolve_attack(f: Fighter) -> void:
	var target: Fighter = fighters[f.target]
	if f.action == "attack":
		stats.attacks += 1
		# Damage belongs to the contact frame and still requires live reach.
		if target.hp > 0 and f.pos.distance_to(target.pos) <= (174.0 if f.hero else 112.0):
			_damage(f,target,Catalog.damage(f.attributes,target.attributes,"physical"),"hit")
		return
	var finisher := f.action == "finisher"
	stats["finishers" if finisher else "skills"] += 1
	var center := target.pos
	var ability: Dictionary=kits[f.side].ultimate if finisher else kits[f.side].battle
	events.append({"kind": "finisher" if finisher else "skill", "source": f.id, "pos": center, "side": f.side})
	for enemy: Fighter in sides[1-f.side]:
		if enemy.hp > 0 and enemy.pos.distance_to(center) <= float(ability.radius):
			_damage(f,enemy,Catalog.damage(f.attributes,enemy.attributes,ability.damage_type,float(ability.multiplier)),"finisher_hit" if finisher else "skill_hit")

func _damage(source: Fighter, target: Fighter, amount: float, kind: String) -> void:
	if target.hp<=0 or source.side==target.side: return
	var before:=ceili(target.people*target.hp/target.max_hp) if not target.hero else 0
	var actual := minf(target.hp, amount)
	target.hp = maxf(0, target.hp - amount)
	var defeated:=before-ceili(target.people*target.hp/target.max_hp) if not target.hero else 0
	kills[source.side]+=defeated
	morale[source.side]=minf(100,morale[source.side]+defeated*float(Catalog.DATA.morale.per_kill))
	target.hit_age = 0
	target.velocity = (target.pos - source.pos).normalized() * (110.0 if kind != "hit" else 24.0)
	if target.hp <= 0:
		target.action = "fall"
		target.age = 0
	events.append({"kind": kind, "pos": target.pos, "side": source.side, "amount": roundi(actual), "target": target.id})

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
			var bounded:=positions[id].clamp(Vector2(55,-25),Vector2(1865,740))
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
	result = {"player_won": won, "player_remaining": left, "enemy_remaining": right,
		"morale": floori(morale[0]+.00001),"enemy_morale": floori(morale[1]+.00001),"kills":kills.duplicate(),
		"reason": "敌阵溃散" if right == 0 else ("我军溃退" if left == 0 else "时限到达 · 按剩余兵力比例判定"),
		"elapsed": elapsed, "stats": stats.duplicate()}
