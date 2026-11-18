extends RefCounted
## Presentation runs on the same paused / accelerated clock as the actors.
const Rules = preload("res://scripts/battle_rules.gd")
const Nezha = preload("res://scripts/nezha_art.gd")
const Wenzhong = preload("res://scripts/wenzhong_art.gd")
const Paint = preload("res://scripts/divine_spell_art.gd")
const CAMERA_LIMIT := .075
const IMPACT_SHADE_OFFSET := Vector2(0,73)

var focus := Vector2(960,580)
var weight := 0.0
var exposure_pulse := 0.0
var thunder_mix := 0.0
var impact_positions := PackedVector2Array([Vector2.ZERO,Vector2.ZERO])
var impact_pulses := PackedFloat32Array([0,0])
var impact_colors := PackedColorArray([Color("4b2631"),Color("4b2631")])
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
		if hero.action != "finisher" or hero.hp <= 0:
			impact_pulses[side] = move_toward(impact_pulses[side],0,dt*8.5)
			continue
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
		impact_positions[side] = Vector2(view.ground(target)) - IMPACT_SHADE_OFFSET
		impact_pulses[side] = move_toward(impact_pulses[side],pulse,dt*8.5)
		impact_colors[side] = Color("292641") if hero.hero_id == "wenzhong" else Color("4b2631")
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
	canvas.draw_rect(Rect2(-64,-64,2048,1208),Color(.10,.10,.19,.10*weight))
	if exposure_pulse>.001:
		var indigo := Color("292439").lerp(Color("152b52"),thunder_mix)
		canvas.draw_rect(Rect2(-64,-64,2048,1208),Color(indigo,.13*exposure_pulse))
	# Shade the backdrop at each landing point. Both wings stay visible through simultaneous finishers.
	for side in 2:
		if impact_pulses[side] > .001:
			glow(canvas,impact_positions[side],Vector2(980,620),Color(impact_colors[side],.55*impact_pulses[side]))
	for side in [-1,1]:
		glow(canvas,focus+Vector2(850*side,-160),Vector2(1650,1120),Color(.08,.06,.15,.13*weight))

# Positions are sampled once at impact. Branches and petals stay on ranks actually hit.
static func capture(view: Control, spell: Dictionary) -> void:
	var hero: Rules.Fighter = view.sim.fighters[int(spell.source)]
	spell.caster_ground = view.ground(hero.pos)
	spell.facing = hero.facing
	var height: float = (view.WENZHONG_HEIGHT if hero.hero_id=="wenzhong" else view.HERO_HEIGHT) * lerpf(.88,1.03,clampf((hero.pos.y+25.0)/765.0,0,1))
	var socket := Vector2(.817,-.692)
	if hero.hero_id=="wenzhong":
		socket=Vector2(.766,-.081) if spell.ability=="nine_thunders" else Vector2(.675,-.271)
	spell.weapon = Vector2(spell.caster_ground)+socket*Vector2(hero.facing,1)*height
	var center: Vector2 = view.ground(spell.pos)
	var hit_kind := "finisher_hit" if spell.kind=="finisher" else "skill_hit"
	var farthest: Vector2 = center
	var second: Vector2 = center
	var hits: Array[Vector2] = []
	var fork_radius := 156.0 if spell.ability=="nine_thunders" else 106.0
	for event in view.sim.events:
		if event.kind != hit_kind or event.source != hero.id: continue
		var point: Vector2=view.ground(event.pos)
		# The wider spell still damages its full area; display forks among nearby contacts.
		if hero.hero_id=="wenzhong" and point.distance_squared_to(center)>fork_radius*fork_radius: continue
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
	if spell.ability=="samadhi":
		# Anchor the flame to the far side of the actually struck ranks. The flare at
		# center remains on the fixed skill target even if the victims subsequently recoil.
		var back_y := center.y
		var depth := 0.0
		for point in hits:
			back_y = minf(back_y,point.y)
			depth = maxf(depth,(point.x-center.x)*hero.facing)
		spell.lotus_back = center+Vector2(hero.facing*minf(70,depth*.38),maxf(-76,(back_y-center.y)*.47)-10)
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
		var fade := 1.0-smoothstep(.16,.60,age)
		glow(view,at,Vector2(272,69),Color(1,.36,.07,.72*fade))
		Paint.lotus_bloom(view,at,e.lotus_back,age,facing)
		var ember_age := Nezha.event_time("samadhi_fx","lotus_burst")+age
		if ember_age<Nezha.duration("samadhi_fx"):
			Nezha.draw(view,"samadhi_fx",ember_age,at+Vector2(0,3),148,1,Color(1,.88,.68,.65))
		for i: int in e.branches.size():
			var t:=age-(.055+i*.07)
			if t<0 or t>.37: continue
			var point: Vector2=e.branches[i]
			var energy:=sin(PI*t/.37)
			glow(view,point,Vector2(93,25),Color(1,.40,.08,.52*energy))
	elif e.ability in ["nine_thunders","thunder_whip"]:
		var strong: bool = e.ability=="nine_thunders"
		var power:=1.0-smoothstep(.07,.48 if strong else .31,age)
		glow(view,at,Vector2(212,58) if strong else Vector2(119,34),Color(.45,.60,1,.82*power))
		Paint.thunder_seal(view,at,strong,1,power*.79)
		Paint.thunder_bloom(view,at,age,strong,facing)
		var clip := str(e.ability) + "_fx"
		var time := age + Wenzhong.event_time(clip,"impact")
		if time < Wenzhong.duration(clip):
			Wenzhong.draw(view,clip,time,at+Vector2(0,4),181 if strong else 108,1,Color(.88,.91,1,.44))

static func draw_fire_strike(view: CanvasItem, e: Dictionary, target: Vector2) -> void:
	var age := float(e.age)
	var facing := int(e.facing)
	Paint.falling_lotus_petals(view,target,age,facing)
	if age>=.17: return
	var release := smoothstep(0,.17,age)
	_fire_path(view,e.weapon,target,facing,release,1.0,1.0-release)
	glow(view,target,Vector2(86,26)*(1.0+.45*release),Color(1,.68,.24,(1.0-release)*.85))

static func _fire_path(view: CanvasItem, tip: Vector2, ground_hit: Vector2, facing: int, tail: float, head: float, energy: float) -> void:
	var chord := ground_hit-tip
	var span := chord.length()
	if span<3.0 or head-tail<.005: return
	# The flame first follows the spear axis, then turns down towards the same landing
	# point used for damage and the rear bloom. Windup and contact share this curve.
	var control_a := tip+chord*.24+Vector2(facing*minf(45,span*.16),-minf(35,span*.14))
	var control_b := ground_hit-chord*.26+Vector2(-facing*minf(16,span*.06),-minf(41,span*.18))
	Paint.silk(view,tip,control_a,control_b,ground_hit,tail,head,6.3,
		Color(.86,.14,.045,.91*energy),Color(1,.79,.29,energy))
	var fillet := Vector2(0,minf(10,span*.045))
	Paint.silk(view,tip,control_a+fillet,control_b-fillet,ground_hit,tail,head,2.1,
		Color(1,.61,.10,.84*energy),Color(1,.92,.64,.96*energy))
	if head<1.0:
		var lead := tip.bezier_interpolate(control_a,control_b,ground_hit,head)
		glow(view,lead,Vector2(18,13),Color(1,.72,.32,energy*.83))

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

static func draw_whip_charge(view: CanvasItem, tip: Vector2, target: Vector2, progress: float, strong: bool) -> void:
	var charge := smoothstep(.4,.60,progress)*(1.0-smoothstep(.84,1,progress)*.4)
	var radius := (22.0 if strong else 15.0)*charge
	if radius < 1.0: return
	var direction := tip.direction_to(target)
	if direction.is_zero_approx(): direction=Vector2.UP
	glow(view,tip,Vector2.ONE*radius*2.5,Color(.57,.61,1,charge*.92))
	# Brass tip, white core, then a small leader toward the marked model.
	var axis := direction*radius*.34
	var glint := axis.orthogonal()*.32
	view.draw_colored_polygon(PackedVector2Array([tip-axis,tip+glint,tip+axis,tip-glint]),Color(1,.94,.80,charge))
	var prong := direction.orthogonal()*radius*.2
	var line := PackedVector2Array([tip,tip+direction*radius*.4+prong,tip+direction*radius*.56-prong,tip+direction*radius])
	draw_stroke(view,line,charge*.80,1.9)

static func draw_lightning(view: CanvasItem, e: Dictionary, target: Vector2) -> void:
	var strong: bool=e.ability=="nine_thunders"
	var age:=float(e.age)
	Paint.thunder_bloom(view,target,age,strong,int(e.facing),true)
	if age>(.44 if strong else .29): return
	var start: Vector2=e.weapon
	var end:=target-Vector2(0,6)
	var facing := int(e.facing)
	var seed_value:=float(e.source)+roundf(end.x*.013+end.y*.024)
	# Discharge and return stroke share a channel anchored to the photographed whip tip.
	var main:=1.0-smoothstep(.045,.23 if strong else .18,age)
	var knot := end+Vector2(26*facing,-98) if strong else end
	draw_stroke(view,bolt_points(start,knot,seed_value,.50),main*(.77 if strong else 1.0),2.6 if strong else 3.4)
	if strong:
		var echo := .32*smoothstep(.16,.20,age)*(1.0-smoothstep(.20,.36,age))
		var crown := end+Vector2(56*facing,-254)
		draw_stroke(view,bolt_points(crown,knot,seed_value+4,1.18),main+echo,5.0)
		draw_stroke(view,bolt_points(knot,end,seed_value+12,.86),main+echo,5.8)
	glow(view,start,Vector2(31,31),Color(.75,.75,1,main*.92))
	glow(view,end,Vector2(59,35) if strong else Vector2(42,27),Color(.84,.91,1,main))
	for i: int in e.branches.size():
		var elapsed: float = age-(.073 if strong else .050)-i*.028
		if elapsed < 0.0: continue
		var energy := smoothstep(0,.026,elapsed)*(1.0-smoothstep(.057,.24 if strong else .15,elapsed))
		if energy < .01: continue
		var tip: Vector2=e.branches[i]-Vector2(0,6)
		var fork := end+Vector2(4*facing,-18) if strong else end
		draw_stroke(view,bolt_points(fork,tip,seed_value+19+i,.60),energy*.79,2.2 if strong else 1.65)
		glow(view,tip,Vector2(45,20),Color(.65,.78,1,energy*.84))

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
	var beat := Nezha.frame_index("samadhi",hero.age)
	if beat<6 or beat>11: return
	# Physical tip of the raised spear through the six casting poses, in body heights.
	const TIPS := [Vector2(.546,-1.027),Vector2(.533,-1.031),Vector2(.542,-1.033),
		Vector2(.554,-.998),Vector2(.604,-.762),Vector2(.708,-.685)]
	var tip: Vector2 = foot+TIPS[beat-6]*Vector2(hero.facing,1)*height
	var kindle := smoothstep(.42,.56,hero.age)
	glow(view,tip,Vector2(29,23),Color(1,.57,.18,.84*kindle))
	var head := smoothstep(.55,hero.impact,hero.age)
	_fire_path(view,tip,target,hero.facing,0,head,kindle)
