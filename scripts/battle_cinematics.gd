extends RefCounted
## Presentation runs on the same paused / accelerated clock as the actors.
const Rules = preload("res://scripts/battle_rules.gd")
const Nezha = preload("res://scripts/nezha_art.gd")
const CAMERA_LIMIT := .075

var focus := Vector2(960,580)
var weight := 0.0
static var halo: GradientTexture2D

func _init() -> void:
	if halo != null: return
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0,.32,.70,1])
	grad.colors = PackedColorArray([Color.WHITE,Color(1,1,1,.72),Color(1,1,1,.16),Color(1,1,1,0)])
	halo = GradientTexture2D.new()
	halo.width = 128
	halo.height = 128
	halo.gradient = grad
	halo.fill = GradientTexture2D.FILL_RADIAL
	halo.fill_from = Vector2(.5,.5)
	halo.fill_to = Vector2(1,.5)

func advance(view: Control, dt: float) -> void:
	var strength := 0.0
	var sum := 0.0
	var center := Vector2.ZERO
	for side in 2:
		var hero: Rules.Fighter = view.sim.hero_for(side)
		if hero.action != "finisher" or hero.hp <= 0: continue
		var rise := smoothstep(0,.25,hero.age)
		var fall := 1.0-smoothstep(hero.impact+.08,hero.duration,hero.age)
		var influence := rise*fall
		var target := hero.cast_target
		if hero.hero_id == "wenzhong" and not hero.applied:
			target = view.sim.fighters[hero.target].pos
		elif hero.hero_id == "wenzhong":
			# Stay on the original landing spot as the struck models recoil.
			for e in view.effects:
				if e.kind == "finisher" and e.source == hero.id: target = e.pos
		center += (Vector2(view.ground(hero.pos)).lerp(view.ground(target),.52)-Vector2(0,83))*influence
		sum += influence
		strength = maxf(strength,influence)
	if sum > .001:
		center = (center/sum).clamp(Vector2(450,410),Vector2(1470,640))
		focus = center if weight < .001 else focus.lerp(center,1.0-exp(-dt*13.0))
	weight = move_toward(weight,strength,dt*4.5)
	if weight > 0: view.pivot_offset = focus
	view.scale = Vector2.ONE * (1.0+CAMERA_LIMIT*weight)

static func glow(canvas: CanvasItem, center: Vector2, size: Vector2, color: Color) -> void:
	canvas.draw_texture_rect(halo,Rect2(center-size*.5,size),false,color)

func draw_atmosphere(canvas: CanvasItem) -> void:
	if weight <= .001: return
	canvas.draw_rect(Rect2(-64,0,2048,960),Color(.09,.13,.23,.12*weight))
	for side in [-1,1]:
		glow(canvas,focus+Vector2(850*side,-160),Vector2(1650,1120),Color(.07,.10,.19,.32*weight))

# Positions are sampled once at impact. Branches and petals stay on ranks actually hit.
static func capture(view: Control, spell: Dictionary) -> void:
	var hero: Rules.Fighter = view.sim.fighters[int(spell.source)]
	spell.caster_ground = view.ground(hero.pos)
	var height: float = (view.WENZHONG_HEIGHT if hero.hero_id=="wenzhong" else view.HERO_HEIGHT) * lerpf(.88,1.03,clampf((hero.pos.y+25.0)/765.0,0,1))
	var socket := Vector2(.81,-.70)
	if hero.hero_id=="wenzhong":
		socket=Vector2(.46,-.56) if spell.ability=="nine_thunders" else Vector2(.51,-.40)
	spell.weapon = Vector2(spell.caster_ground)+socket*Vector2(hero.facing,1)*height
	var center: Vector2 = view.ground(spell.pos)
	var hit_kind := "finisher_hit" if spell.kind=="finisher" else "skill_hit"
	var farthest: Vector2 = center
	var second: Vector2 = center
	var hits: Array[Vector2] = []
	for event in view.sim.events:
		if event.kind != hit_kind or event.source != hero.id: continue
		var point: Vector2=view.ground(event.pos)
		hits.append(point)
		if point.distance_squared_to(center)>farthest.distance_squared_to(center): farthest=point
	var reach:=0.0
	for point in hits:
		var spread:=minf(point.distance_squared_to(center),point.distance_squared_to(farthest))
		if spread>reach:
			second=point
			reach=spread
	var branches: Array[Vector2]=[]
	if farthest.distance_to(center)>36: branches.append(farthest)
	if reach>36.0*36.0: branches.append(second)
	var axis := Vector2(spell.caster_ground).direction_to(center)
	branches.sort_custom(func(a: Vector2,b: Vector2)->bool: return a.dot(axis)<b.dot(axis))
	spell.branches=branches

static func draw_ground(view: Control, e: Dictionary) -> void:
	var at: Vector2=view.ground(e.pos)
	var age:=float(e.age)
	if e.ability=="samadhi":
		for i: int in e.branches.size():
			var delay:=.045+i*.065
			var t:=age-delay
			if t<0 or t>.54: continue
			var point: Vector2=e.branches[i]
			var energy:=sin(PI*t/.54)
			glow(view,point,Vector2(118,32),Color(1,.31,.07,.46*energy))
			Nezha.draw(view,"samadhi_fx",Nezha.event_time("samadhi_fx","lotus_burst")+t,point+Vector2(0,4),105+i*19,1,Color(1,.84,.67,.76*energy))
	elif e.ability in ["nine_thunders","thunder_whip"] and age<.52:
		var power:=1.0-smoothstep(.05,.52,age)
		glow(view,at,Vector2(245,63),Color(.54,.59,1,.58*power))
		for point in e.branches: glow(view,point,Vector2(100,29),Color(.57,.55,1,.44*power))

static func draw_lightning(view: CanvasItem, e: Dictionary, target: Vector2) -> void:
	var strong: bool=e.ability=="nine_thunders"
	var age:=float(e.age)
	if age>.32: return
	var energy:=1.0-smoothstep(.04,.32,age)
	var start: Vector2=e.weapon
	var end:=target+Vector2(0,-4)
	var seed_value:=float(e.source)+floorf(age*22)
	var line:=bolt_points(start,end,seed_value,1.0)
	view.draw_polyline(line,Color(.42,.34,.94,.22*energy),12 if strong else 7,true)
	view.draw_polyline(line,Color(.67,.60,1,.86*energy),5 if strong else 3,true)
	view.draw_polyline(line,Color(.96,.96,1,energy),2.2,true)
	for i in e.branches.size():
		var tip: Vector2=e.branches[i]
		var branch:=bolt_points(line[4+i],tip,seed_value+19+i,.5)
		view.draw_polyline(branch,Color(.69,.61,1,.78*energy),2.8,true)
		view.draw_polyline(branch,Color(.95,.94,1,.90*energy),1.1,true)
	glow(view,start,Vector2(28,28),Color(.77,.65,1,energy))

static func bolt_points(start: Vector2, end: Vector2, seed_value: float, power: float) -> PackedVector2Array:
	var line:=PackedVector2Array([start])
	var span:=start.distance_to(end)
	var side:=start.direction_to(end).orthogonal()
	for i in range(1,7):
		var t:=i/7.0
		var bend:=sin(i*5.4+seed_value*1.8)*minf(19,span*.12)*sin(PI*t)
		line.append(start.lerp(end,t)+side*(bend*power)-Vector2(0,minf(25,span*.12)*sin(t*PI)))
	line.append(end)
	return line

static func draw_lotus_ribbon(view: CanvasItem, hero: Rules.Fighter, foot: Vector2, target: Vector2, height: float) -> void:
	var beat:=Nezha.frame_index("samadhi",hero.age)
	if beat<8 or beat>11: return
	# The tip drops from a high diagonal to a horizontal thrust over the last four windup frames.
	var tip: Vector2=[Vector2(.56,-1.00),Vector2(.57,-1.0),Vector2(.75,-.76),Vector2(.81,-.70)][beat-8]
	var start:=foot+tip*Vector2(hero.facing,1)*height
	var end:=target-Vector2(0,15)
	var axis:=signf(end.x-start.x)
	var control_a:=start+Vector2(axis*55,-48)
	var control_b:=end+Vector2(-axis*58,-52)
	var travel:=smoothstep(.55,hero.impact,hero.age)
	var energy:=smoothstep(0,.26,travel)
	if start.distance_to(end)<22 or travel<.04: return
	var top:=PackedVector2Array()
	var bottom:=PackedVector2Array()
	for i in 21:
		var along:=lerpf(maxf(0,travel-.60),travel,i/20.0)
		var p:=start.bezier_interpolate(control_a,control_b,end,along)
		var tangent:=start.bezier_derivative(control_a,control_b,end,along).normalized()
		var width:float=2.9*(.15+.85*sin(PI*i/20.0))
		var normal:=tangent.orthogonal()*width
		top.append(p+normal)
		bottom.append(p-normal)
	bottom.reverse()
	var strip:=top.duplicate()
	strip.append_array(bottom)
	view.draw_colored_polygon(strip,Color(.93,.24,.15,.86*energy))
	view.draw_polyline(top,Color(1,.73,.34,.88*energy),1.35,true)
