extends Node2D
## Two planes of original brush paintings, animated from the same time and world
## sockets as the rig. No emitters or tweens retain state across a seek.
const Textures = preload("res://scripts/runtime_textures.gd")
const REVEAL = preload("res://assets/nezha_study/spear_fx/paint_reveal.gdshader")
const BRUSHES := "res://assets/nezha_study/spear_fx/fire_brushes.png"
const ARMORY := "res://assets/nezha_study/spear_fx/lotus_armory.png"
enum { FEATHER, LOW_ARC, RISING_ARC, THRUST, CORONA, SPEAR, BLOOM, PETAL }
enum { FORWARD, AROUND, UP, DIAGONAL }
enum { WHOLE, FAR_LIP, NEAR_LIP, POINT }
const REGIONS := [
	Rect2(141,12,365,600), Rect2(605,145,643,369),
	Rect2(14,632,560,600), Rect2(609,790,643,277),
	Rect2(60,0,652,440), Rect2(774,167,748,202),
	Rect2(38,500,730,506), Rect2(916,524,549,448)]
const SPEAR_TIP := Vector2(.99,.383)
const LANCE_TIP := Vector2(.99,.503)
const BLOOM_FOOT := Vector2(.350,.959)
const ARC_TIP := Vector2(.972,.032)
const REAR := -50
const FRONT := 20
const MAX_WAKE := 170.0
const CONTACT_TIME := 3.30
const CROWN_SPACING := [-.408,-.264,0.0,.264,.408]
const CROWN_HEIGHT := [.062,-.126,-.397,-.126,.062]
const CROWN_TILT := [-.64,-.39,0.0,.39,.64]

var _textures: Array[Texture2D] = []
var _marks: Array[Sprite2D] = []
var _used := 0
var _trail := PackedVector2Array()
var _trail_power := 0.0
var _turn_quads: Array[PackedVector2Array] = []
var _turn_uvs: Array[PackedVector2Array] = []
var _turn_inks: Array[PackedColorArray] = []
var _turn_layers: Array[Node2D] = []

func _ready() -> void:
	_textures.assign([Textures.get_texture(BRUSHES), Textures.get_texture(ARMORY)])
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for depth: int in [REAR,FRONT]:
		var layer := Node2D.new()
		layer.z_as_relative = false
		layer.z_index = depth
		add_child(layer)
		layer.draw.connect(_draw_turns.bind(layer,depth==FRONT))
		_turn_layers.append(layer)

func set_choreography(t: float, foot: Vector2, grip: Vector2, tip: Vector2,
		contact: Vector2, trail: PackedVector2Array = PackedVector2Array()) -> void:
	_used = 0
	_trail = trail
	_trail_power = 0.0
	_turn_quads.clear()
	_turn_uvs.clear()
	_turn_inks.clear()
	if t >= .55 and t < 4.05:
		_gather(t,foot)
		_record_turn(t,foot,grip,tip,false)
		_record_turn(t,foot,grip,tip,true)
		_arsenal(t,contact)
		_finisher(t,grip,tip,contact)
		_local_edge(t,grip,tip)
	for i in range(_used,_marks.size()):
		_marks[i].hide()
	for layer in _turn_layers: layer.queue_redraw()
	queue_redraw()

# Pool in draw order; every visual parameter is replaced on each use. Absolute
# depth lets the same circular brush pass behind the shoulder and across the shins.
func _paint(index: int, at: Vector2, size_xy: Vector2, angle: float,
		opacity: float, depth: int, head: float = 1.16, tail: float = -.16,
		flow: int = FORWARD, pivot: Vector2 = Vector2(.5,.5), slice: int = WHOLE) -> void:
	if opacity < .008 or head <= -.02 or tail >= 1.04 or absf(size_xy.x) < 1: return
	if _used == _marks.size():
		var mark := Sprite2D.new()
		mark.centered = false
		mark.region_enabled = true
		mark.region_filter_clip_enabled = true
		mark.z_as_relative = false
		var reveal := ShaderMaterial.new()
		reveal.shader = REVEAL
		mark.material = reveal
		add_child(mark)
		_marks.append(mark)
	var sprite := _marks[_used]
	_used += 1
	var region: Rect2 = REGIONS[index]
	var sheet := _textures[0 if index < CORONA else 1]
	sprite.texture = sheet
	sprite.region_rect = region
	sprite.offset = -region.size * pivot
	sprite.scale = size_xy / region.size
	sprite.rotation = angle
	sprite.position = at
	sprite.z_index = depth
	sprite.self_modulate = Color(1,1,1,clampf(opacity,0,1))
	var atlas := sheet.get_size()
	var uv := region.position / atlas
	var uv_size := region.size / atlas
	var reveal := sprite.material as ShaderMaterial
	reveal.set_shader_parameter("atlas_region",Vector4(uv.x,uv.y,uv_size.x,uv_size.y))
	reveal.set_shader_parameter("head",head)
	reveal.set_shader_parameter("tail",tail)
	reveal.set_shader_parameter("stroke_flow",flow)
	reveal.set_shader_parameter("depth_slice",slice)
	sprite.show()

static func _beat(t: float, start: float, full: float, release: float, spent: float) -> float:
	return smoothstep(start,full,t) * (1.0-smoothstep(release,spent,t))

func _gather(t: float, foot: Vector2) -> void:
	if t >= 1.49: return
	# A root of flame opens behind his back. Three increasingly tall afterimages
	# rise along its grain. The large white points are reserved for later beats.
	var lift := smoothstep(.56,1.15,t)
	var settle := smoothstep(1.08,1.44,t)
	var opacity := _beat(t,.55,.88,1.08,1.45)
	var origin := foot + Vector2(-58.0 - 8.0*lift,-30)
	_paint(FEATHER,origin,Vector2(121+34*lift,171+87*lift),-.74-.14*settle,
		.68*opacity,REAR,1.14*lift+.03,settle*.92-.14,UP,Vector2(.22,.98))
	_paint(FEATHER,origin+Vector2(25,-3),Vector2(118,202+73*lift),-.36+.13*lift,
		.80*opacity,REAR,1.29*lift-.10,settle-.14,UP,Vector2(.22,.98))
	for i in 3:
		var step := i*.097
		var rise := smoothstep(.61+step,.98+step,t)
		var ray := Vector2.UP.rotated(-.90+.37*i)
		var base := foot+Vector2(-68,-74)
		var length := 98.0+34.0*i+46.0*rise
		var spear_tip := base+ray*(86+length*.70+rise*13.0)
		_paint(SPEAR,spear_tip,Vector2(length,length*.205),ray.angle(),
			opacity*(.58+.09*i),REAR,1.23*rise-.09,settle-.15,FORWARD,SPEAR_TIP)

# The inner and outer edges of the two curved brush paintings, measured along
# 13 radial cuts. Sampling across each cut preserves the hand-painted variations
# in width, the dark brush edge and the white core as the weapon bends the paint.
const LOW_EDGES := [Vector2(.334,.428),Vector2(.251,.393),Vector2(.236,.426),
	Vector2(.212,.500),Vector2(.212,.528),Vector2(.222,.543),Vector2(.232,.548),
	Vector2(.297,.533),Vector2(.247,.526),Vector2(.193,.493),Vector2(.208,.441),
	Vector2(.256,.411),Vector2(.350,.443)]
const HIGH_EDGES := [Vector2(.319,.387),Vector2(.323,.442),Vector2(.381,.525),
	Vector2(.293,.669),Vector2(.398,.842),Vector2(.422,.828),Vector2(.438,.764),
	Vector2(.398,.697),Vector2(.363,.637),Vector2(.343,.614),Vector2(.336,.568),
	Vector2(.349,.602),Vector2(.427,.590)]

func _tip_at(t: float, sample_time: float, tip: Vector2) -> Vector2:
	if sample_time >= t-.00001: return tip
	var tick := clampf(_trail.size()-1-(t-sample_time)*60.0,0.0,_trail.size()-1)
	var i := floori(tick)
	return _trail[i].cubic_interpolate(_trail[mini(i+1,_trail.size()-1)],
		_trail[maxi(i-1,0)],_trail[mini(i+2,_trail.size()-1)],tick-i)

func _record_turn(t: float, foot: Vector2, grip: Vector2, tip: Vector2, high: bool) -> void:
	var start := 1.78 if high else 1.16
	var peak := 2.12 if high else 1.52
	var spent := 2.58 if high else 1.84
	if t <= start or t >= spent or _trail.size()<2: return
	var from := maxf(start,t-(_trail.size()-1)/60.0)
	var until := minf(t,peak)
	if until-from < .004: return
	var count := ceili((until-from)*90.0)
	var strength := _beat(t,start,start+.11,peak+.055,spent)
	var rect: Rect2 = REGIONS[RISING_ARC if high else LOW_ARC]
	var source_centre := Vector2(.83,.61) if high else Vector2(.47,.51)
	var edges: Array = HIGH_EDGES if high else LOW_EDGES
	var previous := PackedVector2Array()
	var previous_fork := PackedVector2Array()
	var last_uv := PackedVector2Array()
	var last_ink := PackedColorArray()
	var last_fork_ink := PackedColorArray()
	var sheet_size := _textures[0].get_size()
	var last_tip := _tip_at(t,from,tip)
	var travel := (from-start)*240.0
	for i in range(count+1):
		var s := lerpf(from,until,float(i)/count)
		var age := t-s
		var sample := _tip_at(t,s,tip)
		travel += last_tip.distance_to(sample)
		last_tip = sample
		# Feed the brush by distance, not time. A shaft pivoting briefly toward
		# camera leaves a fine trace until the point travels across the stage.
		var p := clampf(travel/(337.0 if high else 324.0),0.0,1.0)
		var tex_p := lerpf(.015,.986 if high else .82,p)
		var section := tex_p*(edges.size()-1)
		var k := floori(section)
		var radii: Vector2 = edges[k].lerp(edges[mini(k+1,edges.size()-1)],section-k)
		var angle := lerpf(103,279,tex_p) if high else lerpf(-155,120,tex_p)
		var ray := Vector2.from_angle(deg_to_rad(angle))
		var uv0 := (rect.position+(source_centre+ray*radii.x).clamp(Vector2.ZERO,Vector2.ONE)*rect.size)/sheet_size
		var uv1 := (rect.position+(source_centre+ray*radii.y).clamp(Vector2.ZERO,Vector2.ONE)*rect.size)/sheet_size
		var before := _tip_at(t,maxf(from,s-.026),tip)
		var after := _tip_at(t,minf(until,s+.026),tip)
		var cast := smoothstep(.008,.26,age)
		# The blade can reverse its projected tangent in just two ticks when it
		# turns through camera. The radial width stays continuous through that turn.
		var center := sample.lerp((before+2.0*sample+after)*.25,cast)
		var radial := center-(foot+Vector2(0,-85))
		var normal := radial.normalized()
		var air := normal*(75.0 if high else 72.0)+Vector2(0,-26.0 if high else -7.0)
		center += air*cast
		var tip_taper := lerpf(.045,1.0,smoothstep(0,.052,until-s))
		var velocity := before.distance_to(after)/maxf(.001,minf(until,s+.026)-maxf(from,s-.026))
		var pressure := lerpf(.30,1.0,smoothstep(70,800,velocity))*smoothstep(0,.10,until-start)
		var width := (radii.y-radii.x)*(212.0 if high else 177.0)*tip_taper*pressure
		var row := PackedVector2Array([center-normal*width*.56,center+normal*width*.68])
		var uv := PackedVector2Array([uv0,uv1])
		var dry := lerpf(.16,1.0,smoothstep(85,660,velocity))
		var opacity := strength*dry*smoothstep(0,.067,s-start)*(1.0-smoothstep(.35,.70,age))
		var ink := PackedColorArray()
		for point in row:
			# Only the low lip may pass in front. Face and grip retain their shape.
			var front := smoothstep(foot.y-83,foot.y-43,point.y)*smoothstep(23,65,absf(point.x-grip.x))
			ink.append(Color(opacity,front,0,1))
		# One narrow, later branch peels from the hot spine toward the actual
		# travelled path. Its ends rejoin the stroke. Keep it behind the actor.
		var fork_phase := smoothstep(.024,.090,age)*smoothstep(.13,.39,p)
		var fork_curve := sin(p*PI)*fork_phase
		var fork_center := center-air*fork_curve*(.84 if high else .66)
		var fork_width := width*(.26+.11*fork_curve)*fork_phase
		var fork := PackedVector2Array([fork_center-normal*fork_width*.56,fork_center+normal*fork_width*.68])
		var fork_alpha := opacity*fork_phase*(.80 if high else .67)
		var fork_ink := PackedColorArray([Color(fork_alpha,0,0),Color(fork_alpha,0,0)])
		if i>0:
			_append_quad(previous_fork,fork,last_uv,uv,last_fork_ink,fork_ink)
			_append_quad(previous,row,last_uv,uv,last_ink,ink)
		previous=row
		previous_fork=fork
		last_uv=uv
		last_ink=ink
		last_fork_ink=fork_ink

func _append_quad(a: PackedVector2Array, b: PackedVector2Array,
		uv_a: PackedVector2Array, uv_b: PackedVector2Array,
		ink_a: PackedColorArray, ink_b: PackedColorArray) -> void:
	_turn_quads.append(PackedVector2Array([a[0],b[0],b[1],a[1]]))
	_turn_uvs.append(PackedVector2Array([uv_a[0],uv_b[0],uv_b[1],uv_a[1]]))
	_turn_inks.append(PackedColorArray([ink_a[0],ink_b[0],ink_b[1],ink_a[1]]))

func _draw_turns(layer: Node2D, in_front: bool) -> void:
	for i in _turn_quads.size():
		var colors := PackedColorArray()
		var visible_ink := 0.0
		for ink in _turn_inks[i]:
			var alpha := ink.r*(ink.g if in_front else 1.0-ink.g)
			visible_ink = maxf(visible_ink,alpha)
			colors.append(Color(1,1,1,alpha))
		if visible_ink>.006:
			layer.draw_primitive(_turn_quads[i],colors,_turn_uvs[i],_textures[0])

func _arsenal(t: float, contact: Vector2) -> void:
	if t < 2.32 or t >= 3.47: return
	var open := smoothstep(2.39,2.78,t)
	var close := smoothstep(2.92,3.16,t)
	# The holder can move under this fan. Fix it in world space as soon as it forms.
	var center := Vector2(clampf(contact.x-366.0,420.0,587.0),clampf(contact.y-164.0,154.0,267.0))
	center.y += 19.0*(1.0-open)
	var span := Vector2(lerpf(304,482,open),lerpf(139,242,open))
	var opacity := _beat(t,2.32,2.73,2.96,3.16)
	_paint(CORONA,center,span,-.026,opacity*.95,REAR,open*1.21-.03,close*.99-.15,UP)
	for i in 5:
		# Each weapon takes the place of its own flame in the crown. Outer blades
		# leave first; the last bright central point lands in the same burst.
		var rank := 2-absi(i-2)
		var launch := 2.894+.063*rank+(i%2)*.014
		var landing := 3.294+.033*rank+(i%2)*.009
		var p := clampf((t-launch)/(landing-launch),0,1)
		var appear := smoothstep(launch-.10,launch+.012,t)
		var vanish := 1.0-smoothstep(landing-.024,landing+.045,t)
		var origin := center+Vector2(CROWN_SPACING[i]*span.x,CROWN_HEIGHT[i]*span.y)
		var axis := origin.direction_to(contact)
		var side := Vector2(-axis.y,axis.x)
		var released := pow(p,1.83)
		var flight := origin.lerp(contact,released) + side*sin(PI*p)*(float(i)-2.0)*10.0
		var turn := smoothstep(0,.42,p)
		var angle := lerp_angle(-PI*.5+float(CROWN_TILT[i]),axis.angle(),turn)
		var width := (138.0+float(rank)*17.0)*lerpf(.78,1.42,released)
		_paint(SPEAR,flight,Vector2(width,width*(.24-.09*released)),angle,
			appear*vanish*(.74+.11*rank),REAR,1.16,-.16,FORWARD,SPEAR_TIP)

func _finisher(t: float, grip: Vector2, tip: Vector2, contact: Vector2) -> void:
	if t < 2.97: return
	var shaft := grip.direction_to(tip)
	# In the foreshortened turn, keep a hand-sized stroke on the actual metal.
	var nib := _beat(t,2.98,3.09,3.18,3.24)
	_paint(THRUST,tip,Vector2(44+26*nib,14+6*nib),shaft.angle(),nib,
		FRONT,1.16,-.16,FORWARD,LANCE_TIP)
	# Unfurl the tail away from the attached point only as the arm completes its
	# rightward extension. Keep the paint on the live tip until actual impact.
	var writing := smoothstep(3.145,3.297,t)*smoothstep(.82,.987,shaft.x)
	var draw_to := tip if t < CONTACT_TIME else contact
	var power := _beat(t,3.145,3.245,3.38,3.62)
	var tail := maxf(.51*(1.0-writing)-.14,1.20*smoothstep(3.34,3.61,t)-.14)
	var span := Vector2(lerpf(48,567,writing),lerpf(17,106,writing))
	var curve := Vector2(lerpf(58,461,writing),lerpf(19,147,writing))
	var direction := shaft.angle()
	_paint(RISING_ARC,draw_to,curve,direction+.09,power*.64*writing,REAR,
		1.16,tail+.13,DIAGONAL,ARC_TIP)
	_paint(THRUST,draw_to,span,direction,power,REAR,1.16,tail,FORWARD,LANCE_TIP)
	_paint(THRUST,draw_to,span,direction,power*.94,FRONT,
		1.16,tail,FORWARD,LANCE_TIP,POINT)
	if t >= CONTACT_TIME:
		var age := t-CONTACT_TIME
		var opened := smoothstep(0,.14,age)
		var fall := smoothstep(.12,.57,age)
		var petal_power := (1.0-smoothstep(.13,.57,age))
		_paint(BLOOM,contact,Vector2(132+119*opened,72+79*opened),-.035,
			petal_power,REAR,.36+.84*smoothstep(0,.075,age),fall-.15,UP,BLOOM_FOOT)
		_scattered_petals(age,contact)

func _scattered_petals(age: float, contact: Vector2) -> void:
	const ANGLES := [-2.36,-1.90,-1.34,-.88,-.54,-.29,.10]
	const DISTANCES := [112.0,82.0,150.0,163.0,199.0,125.0,157.0]
	for i in ANGLES.size():
		var delay := .041 + (i%3)*.018
		var time := clampf((age-delay)/.65,0,1)
		var power := _beat(age,delay,delay+.07,.32+(i%3)*.055,.66+(i%2)*.05)
		var axis := Vector2.from_angle(ANGLES[i])
		var at: Vector2 = contact + axis*(10.0 + DISTANCES[i]*(1.0-pow(1.0-time,2.45))) + Vector2(0,85*time*time)
		var length := (15.0+(i%3)*9.0)*(1.0-.34*time)
		_paint(PETAL,at,Vector2(length,length*(.42+.31*absf(cos(time*PI*2.0+i)))),
			axis.angle()+.43+sin(time*3.2+i)*.64,power*.90,FRONT)

func _local_edge(t: float, grip: Vector2, tip: Vector2) -> void:
	var low := _beat(t,1.22,1.46,1.53,1.76)
	var high := _beat(t,1.84,2.05,2.14,2.38)
	var last := _beat(t,3.01,3.23,3.31,3.43)
	_trail_power = maxf(low,maxf(high,last))
	var axis := grip.direction_to(tip)
	if axis == Vector2.ZERO or t >= CONTACT_TIME: return
	var shine := maxf(low,high)
	var length := 50.0+55*shine
	_paint(THRUST,tip+axis*3.0,Vector2(length,length*.24),axis.angle(),
		shine*.96,FRONT,1.16,-.16,FORWARD,LANCE_TIP)

func _draw() -> void:
	if _trail.size()<2 or _trail_power < .01 or _textures.is_empty(): return
	# UV spans accumulate actual distance from the physical tip backwards. Before
	# contact this follows the metal; afterwards the supplied history stays pinned.
	var sheet := _textures[0]
	var rect: Rect2 = REGIONS[THRUST]
	var uv := sheet.get_size()
	var travelled := 0.0
	var newer := _trail[-1]
	var join := newer
	# The painted sweeps use a longer history. The little metal wake still
	# spans at most six physics steps and 170 stage pixels.
	for i in range(_trail.size()-2,maxi(-1,_trail.size()-8),-1):
		var older := _trail[i]
		var delta := older-newer
		var length := delta.length()
		if length < .38: continue
		if length > MAX_WAKE*2.0: break
		var reach := minf(MAX_WAKE-travelled,length)
		older = newer+delta*(reach/length)
		var a := travelled/MAX_WAKE
		var b := (travelled+reach)/MAX_WAKE
		var normal := delta.orthogonal().normalized()
		var width := 8.5+4.0*_trail_power
		var near_width := width*sin((.16+a*.84)*PI)
		var far_width := width*sin((.16+b*.84)*PI)
		var near_top := newer + normal*near_width if travelled==0.0 else join
		var far_top := older + normal*far_width
		join = far_top
		var left := (rect.position.x + (1.0-b)*rect.size.x)/uv.x
		var right := (rect.position.x + (1.0-a)*rect.size.x)/uv.x
		var top := rect.position.y/uv.y
		var bottom := rect.end.y/uv.y
		var fresh := Color(1,1,1,_trail_power*(1.0-a))
		var spent := Color(1,1,1,_trail_power*(1.0-b))
		draw_primitive(PackedVector2Array([far_top,near_top,newer*2.0-near_top,older*2.0-far_top]),
			PackedColorArray([spent,fresh,fresh,spent]),PackedVector2Array([Vector2(left,top),Vector2(right,top),Vector2(right,bottom),Vector2(left,bottom)]),sheet)
		travelled += reach
		newer = older
		if travelled >= MAX_WAKE: break
