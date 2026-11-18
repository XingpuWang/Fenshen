extends RefCounted
## Presentation runs on the same paused / accelerated clock as the actors.
const Rules = preload("res://scripts/battle_rules.gd")
const Nezha = preload("res://scripts/nezha_art.gd")
const Paint = preload("res://scripts/divine_spell_art.gd")
const CAMERA_LIMIT := .075

var focus := Vector2(960,580)
var weight := 0.0
var exposure_pulse := 0.0
var thunder_mix := 0.0
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
	var peak := 0.0
	var pulses := 0.0
	var cold := 0.0
	for side in 2:
		var hero: Rules.Fighter = view.sim.hero_for(side)
		if hero.action != "finisher" or hero.hp <= 0: continue
		var rise := smoothstep(0,.25,hero.age)
		var fall := 1.0-smoothstep(hero.impact+.08,hero.duration,hero.age)
		var influence := rise*fall
		var pulse := smoothstep(hero.impact-.42,hero.impact-.055,hero.age)
		pulse *= 1.0-smoothstep(hero.impact+.065,hero.impact+.42,hero.age)
		peak = maxf(peak,pulse)
		pulses += pulse
		if hero.hero_id=="wenzhong": cold += pulse
		var target := hero.cast_target
		if hero.hero_id == "wenzhong" and not hero.applied:
			target = view.sim.fighters[hero.target].pos
		elif hero.hero_id == "wenzhong":
			# Stay on the original landing spot as the struck models recoil.
			for e in view.effects:
				if e.kind == "finisher" and e.source == hero.id: target = e.pos
		var approach := smoothstep(.10,hero.impact,hero.age)
		center += (Vector2(view.ground(hero.pos)).lerp(view.ground(target),lerpf(.38,.64,approach))-Vector2(0,83))*influence
		sum += influence
		strength = maxf(strength,influence)
	# Peak exposure is shared when both ultimates strike. The two hues crossfade.
	exposure_pulse = move_toward(exposure_pulse,peak,dt*8.5)
	if pulses>.001: thunder_mix = lerpf(thunder_mix,cold/pulses,1.0-exp(-dt*12.0))
	if sum > .001:
		center = (center/sum).clamp(Vector2(450,410),Vector2(1470,640))
		focus = center if weight < .001 else focus.lerp(center,1.0-exp(-dt*13.0))
	weight = move_toward(weight,strength,dt*4.5)
	if weight > 0: view.pivot_offset = focus
	view.scale = Vector2.ONE * (1.0+CAMERA_LIMIT*weight)

static func glow(canvas: CanvasItem, center: Vector2, size: Vector2, color: Color) -> void:
	canvas.draw_texture_rect(halo,Rect2(center-size*.5,size),false,color)

func draw_atmosphere(canvas: CanvasItem) -> void:
	if weight <= .001 and exposure_pulse<=.001: return
	canvas.draw_rect(Rect2(-64,0,2048,960),Color(.10,.10,.19,.19*weight))
	if exposure_pulse>.001:
		var indigo := Color("292439").lerp(Color("152b52"),thunder_mix)
		canvas.draw_rect(Rect2(-64,-64,2048,1208),Color(indigo,.57*exposure_pulse))
	for side in [-1,1]:
		glow(canvas,focus+Vector2(850*side,-160),Vector2(1650,1120),Color(.08,.06,.15,.37*weight))

# Positions are sampled once at impact. Branches and petals stay on ranks actually hit.
static func capture(view: Control, spell: Dictionary) -> void:
	var hero: Rules.Fighter = view.sim.fighters[int(spell.source)]
	spell.caster_ground = view.ground(hero.pos)
	spell.facing = hero.facing
	var height: float = (view.WENZHONG_HEIGHT if hero.hero_id=="wenzhong" else view.HERO_HEIGHT) * lerpf(.88,1.03,clampf((hero.pos.y+25.0)/765.0,0,1))
	var socket := Vector2(.81,-.70)
	if hero.hero_id=="wenzhong":
		socket=Vector2(.766,-.081) if spell.ability=="nine_thunders" else Vector2(.675,-.271)
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
	var axis := Vector2(spell.caster_ground).direction_to(center)
	if spell.ability=="qiankun":
		# A throw can hit a single defender anywhere on its swept line, even at the endpoint.
		hits.sort_custom(func(a: Vector2,b: Vector2)->bool: return a.dot(axis)<b.dot(axis))
		var contacts: Array[Vector2]=[]
		if not hits.is_empty():
			contacts.append(hits.front())
			if hits.front().distance_to(hits.back())>36: contacts.append(hits.back())
		spell.branches=contacts
		return
	var reach:=0.0
	for point in hits:
		var spread:=minf(point.distance_squared_to(center),point.distance_squared_to(farthest))
		if spread>reach:
			second=point
			reach=spread
	var branches: Array[Vector2]=[]
	if farthest.distance_to(center)>36: branches.append(farthest)
	if reach>36.0*36.0: branches.append(second)
	branches.sort_custom(func(a: Vector2,b: Vector2)->bool: return a.dot(axis)<b.dot(axis))
	spell.branches=branches

static func draw_ground(view: Control, e: Dictionary) -> void:
	var at: Vector2=view.ground(e.pos)
	var age:=float(e.age)
	var facing := int(e.facing)
	if e.ability=="samadhi":
		var fade := 1.0-smoothstep(.19,.81,age)
		glow(view,at,Vector2(480,116),Color(1,.37,.07,.80*fade))
		Paint.lotus_bloom(view,at,age,facing)
		for i: int in e.branches.size():
			var t:=age-(.045+i*.065)
			if t<0 or t>.57: continue
			var point: Vector2=e.branches[i]
			var energy:=sin(PI*t/.57)
			glow(view,point,Vector2(128,32),Color(1,.36,.07,.46*energy))
			Paint.stamp(view,Paint.lotus,.2+smoothstep(0,.26,t)*2.8,point,Vector2(134,127),.73*energy,facing)
	elif e.ability in ["nine_thunders","thunder_whip"]:
		var strong: bool = e.ability=="nine_thunders"
		var power:=1.0-smoothstep(.08,.78 if strong else .43,age)
		glow(view,at,Vector2(347,84) if strong else Vector2(192,45),Color(.39,.50,1,.81*power))
		for point in e.branches: glow(view,point,Vector2(109,29),Color(.45,.66,1,.59*power))
		Paint.thunder_bloom(view,at,age,strong,facing)

static func draw_fire_strike(view: CanvasItem, e: Dictionary, target: Vector2) -> void:
	var age := float(e.age)
	Paint.lotus_bloom(view,target,age,int(e.facing),true)
	if age>.22: return
	var source: Vector2 = e.weapon
	var end := target-Vector2(0,24)
	var chord := end-source
	var lift := Vector2(0,clampf(absf(chord.x)*.27,30,103))
	var slide := smoothstep(.015,.22,age)
	Paint.silk(view,source,source+chord*.34-lift,end-chord*.24-lift*.45,end,slide,1,7.0*(1.0-slide),
		Color(.89,.16,.04,.64*(1.0-slide)),Color(1,.78,.37,.92*(1.0-slide)))

static func draw_caster(view: CanvasItem, hero: Rules.Fighter, foot: Vector2, height: float) -> void:
	if hero.hp<=0 or hero.action not in ["cast","finisher"]: return
	var strong := hero.action=="finisher"
	var charge := smoothstep(.06,hero.impact-.06,hero.age)
	var release := 1.0-smoothstep(hero.impact,hero.impact+.29,hero.age)
	var energy := charge*release*(1.0 if strong else .56)
	var warm := hero.hero_id=="nezha"
	var tint := Color(1,.41,.10) if warm else Color(.49,.55,1)
	var socket := foot+Vector2(.27*hero.facing,-.56)*height
	glow(view,socket,Vector2(1.15,1.42)*height,Color(tint,.50*energy))
	glow(view,foot,Vector2(1.22,.29)*height,Color(tint,.57*energy))

static func draw_stroke(view: CanvasItem, line: PackedVector2Array, energy: float, width: float) -> void:
	if energy<.012: return
	view.draw_polyline(line,Color(.22,.18,.67,.30*energy),width*3.5,true)
	view.draw_polyline(line,Color(.60,.54,1,.91*energy),width*1.5,true)
	view.draw_polyline(line,Color(.93,.95,1,energy),width*.57,true)

static func draw_lightning(view: CanvasItem, e: Dictionary, target: Vector2) -> void:
	var strong: bool=e.ability=="nine_thunders"
	var age:=float(e.age)
	Paint.thunder_bloom(view,target,age,strong,int(e.facing),true)
	if age>(.46 if strong else .25): return
	var flash:=1.0-smoothstep(.025,.19 if strong else .25,age)
	if strong:
		# Return stroke down the already ionized channel, with no new damage event.
		flash += .68*smoothstep(.16,.20,age)*(1.0-smoothstep(.20,.46,age))
	var start: Vector2=e.weapon
	var end:=target-Vector2(0,6)
	var seed_value:=float(e.source)+floorf(age*20)
	# Sky channel meets the whip at the lower fork of the painted thunderbolt.
	var knot := end+Vector2(36*int(e.facing),-114) if strong else end
	var line:=bolt_points(start,knot,seed_value,1.0)
	draw_stroke(view,line,flash,3.6 if strong else 2.7)
	if strong:
		var crown := end+Vector2(62*int(e.facing),-278)
		draw_stroke(view,bolt_points(crown,knot,seed_value+4,1.40),flash*.92,4.0)
		draw_stroke(view,bolt_points(knot,end,seed_value+12,1.2),flash,4.4)
	for i in e.branches.size():
		var tip: Vector2=e.branches[i]
		# Ordinary lash forks along its length; the ultimate fans down from the sky.
		var fork: Vector2=knot if strong else line[4+i]
		var branch:=bolt_points(fork,tip-Vector2(0,6),seed_value+19+i,.7)
		draw_stroke(view,branch,flash*.85,2.2 if strong else 1.8)
	glow(view,start,Vector2(37,37),Color(.77,.70,1,flash))

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
	var travel:=smoothstep(.45,hero.impact,hero.age)
	if travel<.03 or start.distance_to(end)<22: return
	var head := minf(1.0,travel*1.04)
	var tail := maxf(0,head-.82)
	var distance := absf(end.x-start.x)
	var bow := clampf(distance*.26,40,103)
	var control_a:=start+Vector2(axis*distance*.34,-bow)
	var control_b:=end+Vector2(-axis*distance*.24,-bow*.45)
	Paint.silk(view,start,control_a,control_b,end,tail,head,9.2,Color(.79,.09,.06,.80),Color(1,.73,.32,.96))
	Paint.silk(view,start,control_a+Vector2(0,29),control_b+Vector2(0,-32),end,tail,head,4.7,Color(1,.30,.08,.68),Color(1,.86,.53,.9))
