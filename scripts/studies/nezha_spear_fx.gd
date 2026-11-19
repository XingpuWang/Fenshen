extends Node2D
## Two planes of original brush paintings, animated from the same time and world
## sockets as the rig. No emitters or tweens retain state across a seek.
const LotusImpact = preload("res://scripts/studies/nezha_lotus_impact.gd")
const Textures = preload("res://scripts/runtime_textures.gd")
const REVEAL = preload("res://assets/nezha_study/spear_fx/paint_reveal.gdshader")
const WAVE_LIGHT = preload("res://shaders/nezha_wave_light.gdshader")
const SpearEchoes = preload("res://scripts/studies/nezha_spear_echoes.gd")
const BRUSHES := "res://assets/nezha_study/spear_fx/fire_brushes.png"
const ARMORY := "res://assets/nezha_study/spear_fx/lotus_armory.png"
const WAVES := "res://assets/nezha_study/spear_fx/spear_waves.png"
const IGNITION_REGION := Rect2(45,42,1270,249)
const IGNITION_POINT := Vector2(1258.5,138.5) # last half-opaque pixel of the painted nib
const FALL_WAVE := Rect2(14,335,1496,324)
const RISE_WAVE := Rect2(32,713,1331,265)
# Vertical positions of the hot seam across each hand-painted stroke.
const FALL_SPINE := [.71,.71,.72,.73,.75,.77,.77,.74,.69,.63,.58]
const RISE_SPINE := [.79,.52,.56,.52,.68,.77,.83,.83,.78,.78,.77]
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
const REAR := -50
const FRONT := 20
const MAX_WAKE := 170.0

var _lotus := LotusImpact.new()
var _textures: Array[Texture2D] = []
var _marks: Array[Sprite2D] = []
var _used := 0
var _trail := PackedVector2Array()
var _trail_power := 0.0
var _wave_sheet: Texture2D
var _ignition := Sprite2D.new()
var _turn_quads: Array[PackedVector2Array] = []
var _turn_uvs: Array[PackedVector2Array] = []
var _turn_sheets: Array[Texture2D] = []
var _turn_inks: Array[PackedColorArray] = []
var _turn_layers: Array[Node2D] = []

func _ready() -> void:
	_lotus.name = "LotusImpact"
	add_child(_lotus)
	_textures.assign([Textures.get_texture(BRUSHES), Textures.get_texture(ARMORY)])
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_wave_sheet = Textures.get_texture(WAVES)
	_ignition.name = "BladeIgnition"
	_ignition.z_as_relative = false
	_ignition.z_index = FRONT
	_ignition.texture = _wave_sheet
	_ignition.centered = false
	_ignition.region_enabled = true
	_ignition.region_rect = IGNITION_REGION
	_ignition.offset = -IGNITION_POINT
	var burn := ShaderMaterial.new()
	burn.shader = REVEAL
	var size_xy := _wave_sheet.get_size()
	burn.set_shader_parameter("atlas_region",Vector4(IGNITION_REGION.position.x/size_xy.x,
		IGNITION_REGION.position.y/size_xy.y,IGNITION_REGION.size.x/size_xy.x,IGNITION_REGION.size.y/size_xy.y))
	_ignition.material = burn
	_ignition.hide()
	add_child(_ignition)
	var wave_light := ShaderMaterial.new()
	wave_light.shader = WAVE_LIGHT
	for depth: int in [REAR,FRONT]:
		var layer := Node2D.new()
		layer.material = wave_light
		layer.z_as_relative = false
		layer.z_index = depth
		add_child(layer)
		layer.draw.connect(_draw_turns.bind(layer,depth==FRONT))
		_turn_layers.append(layer)

func set_choreography(t: float, foot: Vector2, grip: Vector2, tip: Vector2,
		contact: Vector2, trail: PackedVector2Array = PackedVector2Array(), contact_axis: Vector2 = Vector2.RIGHT) -> void:
	_used = 0
	_trail = trail
	_trail_power = 0.0
	_turn_quads.clear()
	_turn_uvs.clear()
	_turn_sheets.clear()
	_turn_inks.clear()
	_ignition.hide()
	if t >= .55 and t < 4.05:
		_gather(t,grip,tip)
		_record_turn(t,foot,grip,tip,false)
		_record_turn(t,foot,grip,tip,true)
		_sweep_embers(t,tip)
		_arsenal(t,grip,tip,contact)
		_local_edge(t)
	_lotus.pose_at(t,grip,tip,contact,contact_axis)
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

func _gather(t: float, grip: Vector2, tip: Vector2) -> void:
	var charge := _beat(t,.56,.96,1.16,1.39)
	var low := _beat(t,1.26,1.44,1.54,1.65)
	var high := _beat(t,1.87,2.04,2.14,2.24)
	var light := maxf(charge,maxf(low,high))
	_ignition.visible = light>.01
	if not _ignition.visible: return
	var distance := grip.distance_to(tip)
	var hot_length := minf(distance*.62,29.0 + charge*61.0 + maxf(low,high)*30)
	_ignition.position = tip
	_ignition.rotation = grip.direction_to(tip).angle()
	_ignition.scale = Vector2(hot_length/IGNITION_REGION.size.x,(10.0+19.0*light)/IGNITION_REGION.size.y)
	_ignition.self_modulate = Color(1,1,1,light)
	# The gilded point catches first, then two red tongues open along the metal.
	_ignition.material.set_shader_parameter("tail",lerpf(.72,-.15,smoothstep(.56,.99,t)))
	# A short spark runs up the blade into the two lit edges at ignition.
	var gather_spark := _beat(t,.64,.72,.84,.96)
	if gather_spark>.01:
		var run := smoothstep(.64,.90,t)
		var spark := grip.lerp(tip,lerpf(.68,1.0,run))
		_paint(THRUST,spark,Vector2(19+15*run,6.0+3.0*run),_ignition.rotation,
			gather_spark,FRONT,1.16,-.16,FORWARD,LANCE_TIP)

func _tip_at(t: float, sample_time: float, tip: Vector2) -> Vector2:
	if sample_time >= t-.00001: return tip
	var tick := clampf(_trail.size()-1-(t-sample_time)*60.0,0.0,_trail.size()-1)
	var i := floori(tick)
	return _trail[i].cubic_interpolate(_trail[mini(i+1,_trail.size()-1)],
		_trail[maxi(i-1,0)],_trail[mini(i+2,_trail.size()-1)],tick-i)

func _record_turn(t: float, foot: Vector2, grip: Vector2, tip: Vector2, high: bool) -> void:
	var start := 1.78 if high else 1.16
	var peak := 2.12 if high else 1.52
	var spent := peak+(.20 if high else .23)
	if t<=start or t>=spent or _trail.size()<2: return
	var from := maxf(start,t-(_trail.size()-1)/60.0)
	var until := minf(t,peak)
	if until-from<.004: return
	# Enter the wave at the end of the backswing. Projecting onto the cut
	# leaves the reverse preparation on the live blade instead of folding it
	# into the same patch of fire twice.
	var cut := Vector2(-.12,-1).normalized() if high else Vector2(.75,.66).normalized()
	var bottom_time := from
	var lowest := _tip_at(t,from,tip).dot(cut)
	for step in range(1,ceili((until-from)*100.0)+1):
		var probe := minf(until,from+step*.01)
		var along := _tip_at(t,probe,tip).dot(cut)
		if along < lowest:
			lowest = along
			bottom_time = probe
	from = minf(bottom_time,until-.0001)
	var count := maxi(1,ceili((until-from)*150.0))
	var points := PackedVector2Array()
	var lengths := PackedFloat32Array([0])
	for i in range(count+1):
		points.append(_tip_at(t,lerpf(from,until,float(i)/count),tip))
		if i>0: lengths.append(lengths[i-1]+points[i].distance_to(points[i-1]))
	var travel := lengths[count]
	var rect := RISE_WAVE if high else FALL_WAVE
	var atlas_size := _wave_sheet.get_size()
	var spine := RISE_SPINE if high else FALL_SPINE
	var previous := PackedVector2Array()
	var previous_uv := PackedVector2Array()
	var previous_ink := PackedColorArray()
	var previous_edge := PackedVector2Array()
	var previous_edge_uv := PackedVector2Array()
	var previous_edge_ink := PackedColorArray()
	for i in range(count+1):
		var f := float(i)/count
		var s := lerpf(from,until,f)
		var age := t-s
		var arc := lengths[i]/maxf(travel,1.0)
		# The leading point of the painting arrives with the metal at every sample.
		# Its rear unfurls by distance as the spear carves out the sheet of flame.
		var u := clampf(1.0-(travel-lengths[i])/(169.0 if high else 195.0),0.0,1.0)
		var x := lerpf(rect.position.x,rect.end.x,u)/atlas_size.x
		var section := u*(spine.size()-1)
		var lo := floori(section)
		var hot := lerpf(spine[lo],spine[mini(lo+1,spine.size()-1)],section-lo)
		var window := .024
		var a := maxf(from,s-window)
		var b := minf(until,s+window)
		var velocity := (_tip_at(t,b,tip)-_tip_at(t,a,tip))/maxf(.001,b-a)
		var forward := maxf(-velocity.y,0.0) if high else maxf(velocity.dot(Vector2(.78,.62)),0.0)
		var pressure := smoothstep(55,650,forward)
		# Keep the width perpendicular to one stable cutting plane. With both
		# endpoints of a section at the same along-cut coordinate, short turns
		# cannot twist successive sections inside out.
		var normal := -cut.orthogonal()
		var waft := smoothstep(.015,.15,age)
		var settled := points[i]
		if not high:
			settled.y = lerpf(settled.y,points[count].y,.64*waft)
		var air := normal*(16.0 if high else 9.0)
		var release := smoothstep(peak,spent,t)
		var coast := (Vector2(9,-13) if high else Vector2(20,4))*release
		var center := settled + air*waft + coast
		var opening := smoothstep(0,.010,until-s)*smoothstep(4,72,travel)
		var height := (89.0 if high else 95.0)*(.27+.73*pressure)*opening
		height = minf(height, maxf(6.0,velocity.length()*.115))
		if not high:
			height = minf(height, maxf(9.0,(foot.y+5.0-center.y)/(normal.y*hot)))
		var row := PackedVector2Array([center+normal*height*hot,center-normal*height*(1.0-hot)])
		var top := rect.position.y/atlas_size.y
		var bottom := rect.end.y/atlas_size.y
		var uv := PackedVector2Array([Vector2(x,top),Vector2(x,bottom)])
		var retiring := smoothstep(peak+.015+.065*arc,spent-.04+.04*arc,t)
		var alpha := (1.0-retiring)*(1.0-smoothstep(.20,.37,age))*(.22+.78*pressure)
		alpha *= smoothstep(0,.038,s-start)*smoothstep(.01,.08,u)
		var ink := PackedColorArray()
		for p in row:
			var front := smoothstep(foot.y-85,foot.y-44,p.y)*smoothstep(25,68,absf(p.x-grip.x))
			ink.append(Color(alpha,front,0))
		# A fine lick stays in the cut for a few ticks after the crest lifts away.
		# Isolate only the painted gold seam so the interior of the wave stays open.
		var edge_center := points[i].lerp(settled,.22)+air*waft*.15+coast
		var delay := smoothstep(.010,.058,age)*(1.0-smoothstep(.10,.20,age))
		var edge_height := height*.12*delay
		var edge := PackedVector2Array([edge_center+normal*edge_height,edge_center-normal*edge_height*.55])
		var edge_uv := PackedVector2Array([Vector2(x,lerpf(top,bottom,maxf(0,hot-.135))),
			Vector2(x,lerpf(top,bottom,minf(1,hot+.07)))])
		var edge_alpha := alpha*delay*.76
		var edge_ink := PackedColorArray([Color(edge_alpha,0,1),Color(edge_alpha,0,1)])
		if i>0:
			_append_quad(previous_edge,edge,previous_edge_uv,edge_uv,previous_edge_ink,edge_ink)
			_append_quad(previous,row,previous_uv,uv,previous_ink,ink)
		previous=row
		previous_uv=uv
		previous_ink=ink
		previous_edge=edge
		previous_edge_uv=edge_uv
		previous_edge_ink=edge_ink

func _append_quad(a: PackedVector2Array, b: PackedVector2Array,
		uv_a: PackedVector2Array, uv_b: PackedVector2Array,
		ink_a: PackedColorArray, ink_b: PackedColorArray, tex: Texture2D = null) -> void:
	_turn_sheets.append(tex if tex!=null else _wave_sheet)
	_turn_quads.append(PackedVector2Array([a[0],b[0],b[1],a[1]]))
	_turn_uvs.append(PackedVector2Array([uv_a[0],uv_b[0],uv_b[1],uv_a[1]]))
	_turn_inks.append(PackedColorArray([ink_a[0],ink_b[0],ink_b[1],ink_a[1]]))

func _draw_turns(layer: Node2D, in_front: bool) -> void:
	var ids := PackedInt32Array()
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	var ink := PackedColorArray()
	var sheet: Texture2D
	for i in _turn_quads.size():
		var colors := PackedColorArray()
		var visible_ink := 0.0
		for shade in _turn_inks[i]:
			var alpha := shade.r*(shade.g if in_front else 1.0-shade.g)
			visible_ink = maxf(visible_ink,alpha)
			colors.append(Color(1,1,1,alpha))
		if visible_ink<=.006: continue
		if sheet!=_turn_sheets[i] and not ids.is_empty():
			_submit_ink(layer,sheet,ids,points,ink,uv)
			ids.clear()
			points.clear()
			ink.clear()
			uv.clear()
		sheet = _turn_sheets[i]
		var q := _turn_quads[i]
		var src := _turn_uvs[i]
		# Approximate the bilinear texture mapping across the wave, rather
		# than stretching one triangle diagonally across the whole gold edge.
		var bands := 7 if sheet==_wave_sheet else 1
		for j in range(bands+1):
			var v := float(j)/bands
			var k := points.size()
			points.append(q[0].lerp(q[3],v))
			points.append(q[1].lerp(q[2],v))
			uv.append(src[0].lerp(src[3],v))
			uv.append(src[1].lerp(src[2],v))
			var fade := 1.0
			if _turn_inks[i][0].b>.5:
				fade = minf(1.0,sin(PI*v)*2.3)
			var a := colors[0].lerp(colors[3],v)
			var b := colors[1].lerp(colors[2],v)
			a.a *= fade
			b.a *= fade
			ink.append(a)
			ink.append(b)
			if j>0: ids.append_array(PackedInt32Array([k-2,k-1,k+1,k-2,k+1,k]))
	if not ids.is_empty(): _submit_ink(layer,sheet,ids,points,ink,uv)

func _submit_ink(layer: Node2D, sheet: Texture2D, ids: PackedInt32Array,
		points: PackedVector2Array, ink: PackedColorArray, uv: PackedVector2Array) -> void:
	RenderingServer.canvas_item_add_triangle_array(layer.get_canvas_item(),ids,points,ink,
		uv,PackedInt32Array(),PackedFloat32Array(),sheet.get_rid())

func _sweep_embers(t: float, tip: Vector2) -> void:
	# Each chip leaves a particular point along the stroke. A downswing sheds
	# short, falling scales; the rising stroke lifts longer sparks into the air.
	if _trail.size()<2: return
	var rising := t >= 1.92
	var start := 1.976 if rising else 1.338
	if t < start or t > start+.53: return
	const BEATS := [0.0,.019,.047,.078,.091,.122,.147]
	const OPENING := [-.51,.26,-.13,-.71,.39,-.28,.12]
	const REACH := [58.0,48.0,71.0,59.0,84.0,67.0,95.0]
	for i in BEATS.size():
		var birth: float = start + BEATS[i]
		var age := t-birth
		var life := .24+.043*(i%4)
		if age <= 0 or age >= life: continue
		var anchor := _tip_at(t,birth,tip)
		var tangent := _tip_at(t,birth-.018,tip).direction_to(anchor)
		var ray := tangent.rotated(float(OPENING[i]))
		var phase := age/life
		var travel := float(REACH[i])*(1.0-pow(1.0-phase,1.8))
		var at := anchor + ray*travel + Vector2.DOWN*(23.0 if rising else 12.0)*phase*phase
		var tilt := ray.angle()+lerpf(.16,.55,phase) * (-1.0 if i%2 else 1.0)
		var length := (12.0+float(i%3)*3.5)*(1.0-.59*phase)
		var thickness := length*(.29+.18*absf(cos(phase*PI+i)))
		var power := smoothstep(0,.032,age)*(1.0-smoothstep(.28,1.0,phase))
		_paint(PETAL,at,Vector2(length,thickness),tilt+.29,power*.92,REAR)
		# The small gilt edge flashes first; the surviving chip turns vermilion.
		var glint := power * (1.0-smoothstep(.08,.52,phase))
		_paint(THRUST,at+ray*length*.22,Vector2(length*.87,thickness*.58),
			tilt,glint,REAR,1.16,-.16,FORWARD,Vector2(.64,.51))

func _arsenal(t: float, grip: Vector2, tip: Vector2, contact: Vector2) -> void:
	SpearEchoes.paint(self,t,grip,tip,contact)

func _local_edge(t: float) -> void:
	var low := _beat(t,1.26,1.44,1.52,1.64)
	var high := _beat(t,1.89,2.04,2.12,2.23)
	var last := _beat(t,3.01,3.23,3.31,3.43)
	_trail_power = maxf(last,.24*maxf(low,high))

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
