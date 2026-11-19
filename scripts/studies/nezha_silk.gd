@tool
extends Node2D
## Secondary animation for Nezha's ribbons. Pose the sibling rig first, then call pose_at.
const Textures = preload("res://scripts/runtime_textures.gd")
const LOOP_SECONDS := 6.40
const STRIDE := 5 # transparent edge, upper selvage, ridge, lower selvage, transparent edge
const SHOULDER_BIND := Vector2(-12, -158)
const HAIR_BIND := Vector2(-20, -201)
const WAIST_BIND := Vector2(-12, -96)
const FABRIC_ROWS := [0, 1, 3, 2, 0]

enum Fabric { SASH, HAIR, JADE, HEM, LOCK }

@export_file("*.png") var silk_art := "res://assets/nezha_study/silk/brocade.png"
@export_file("*.png") var hair_art := "res://assets/nezha_study/actor/bun_near.png"
@export var shoulder_travel: Curve
@export var shoulder_drop: Curve
@export var body_turns: Curve
@export var sweep_tension: Curve
@export var sash_turns: Curve
@export_range(0.0, 6.4, 0.005) var editor_time := 0.0:
	set(value):
		editor_time = value
		if Engine.is_editor_hint() and is_node_ready():
			pose_at(value, null)

class Ribbon:
	var path: Path2D
	var kind: Fabric
	var width: float
	var delay: float
	var phase: float
	var count: int
	var indices := PackedInt32Array()
	var centers := PackedVector2Array()
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var depths := PackedFloat32Array()
	var front_colors := PackedColorArray()
	var has_front := false
	var uvs := PackedVector2Array()

	func _init(guide: Path2D, fabric: Fabric, breadth: float, lag: float, offset: float, segments: int) -> void:
		path = guide
		kind = fabric
		width = breadth
		delay = lag
		phase = offset
		count = segments
		centers.resize(count + 1)
		vertices.resize((count + 1) * STRIDE)
		colors.resize(vertices.size())
		uvs.resize(vertices.size())
		if kind == Fabric.SASH:
			depths.resize(count + 1)
			front_colors.resize(vertices.size())
		for i in count:
			for j in STRIDE - 1:
				var a := STRIDE*i+j
				var b := a+STRIDE
				indices.append_array(PackedInt32Array([a, b, a+1, a+1, b, b+1]))

var _layers: Array[Ribbon] = []
var _no_bones := PackedInt32Array()
var _no_weights := PackedFloat32Array()
var _atlas: Texture2D
var _hair_paint: Texture2D
@onready var _front: Node2D = $FrontFold
var _time := 0.0
var _dirty := true
var _shoulder_offset := Vector2.ZERO
var _hair_offset := Vector2.ZERO
var _waist_offset := Vector2.ZERO
var _back_grip := Vector2.INF
var _forward_grip := Vector2.INF

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_atlas = load(silk_art) as Texture2D if Engine.is_editor_hint() else Textures.get_texture(silk_art)
	_hair_paint = load(hair_art) as Texture2D if Engine.is_editor_hint() else Textures.get_texture(hair_art)
	_layers.assign([
		Ribbon.new($Sash, Fabric.SASH, 15.5, 0.39, 0.0, 54),
		Ribbon.new($WaistSilk, Fabric.JADE, 7.8, 0.24, 2.4, 20),
		Ribbon.new($CoatTail, Fabric.HEM, 17.0, 0.31, 1.5, 26),
		Ribbon.new($LooseHair, Fabric.LOCK, 4.8, 0.135, 1.7, 14),
		Ribbon.new($ShortLock, Fabric.LOCK, 2.8, 0.10, 2.9, 12),
		Ribbon.new($HairLow, Fabric.HAIR, 5.0, 0.21, 2.6, 14),
		Ribbon.new($HairHigh, Fabric.HAIR, 5.7, 0.17, 0.7, 16)
	])
	for ribbon in _layers:
		if ribbon.path.curve: ribbon.path.curve.changed.connect(_invalidate)
	for motion in [shoulder_travel, shoulder_drop, body_turns, sweep_tension, sash_turns]:
		if motion: motion.changed.connect(_invalidate)
	_front.draw.connect(_draw_near_fold)
	pose_at(editor_time if Engine.is_editor_hint() else 0.0, null)

func pose_at(seconds: float, rig: Node2D) -> void:
	_time = fposmod(seconds, LOOP_SECONDS)
	_back_grip = Vector2.INF
	_forward_grip = Vector2.INF
	if is_instance_valid(rig):
		_shoulder_offset = to_local(rig.to_global(rig.cloth_anchor())) - SHOULDER_BIND
		_hair_offset = to_local(rig.to_global(rig.hair_anchor())) - HAIR_BIND
		_waist_offset = to_local(rig.to_global(rig.hem_anchor())) - WAIST_BIND
		var spear := rig.get_node(^"Skeleton/Spear") as Bone2D
		var blade := spear.get_node(^"FireTip") as Sprite2D
		if spear.z_index + blade.z_index < _front.z_index:
			_back_grip = to_local(spear.get_node(^"RearGrip").global_position)
			_forward_grip = to_local(spear.get_node(^"FrontGrip").global_position)
	else:
		_shoulder_offset = Vector2.ZERO
		_hair_offset = Vector2.ZERO
		_waist_offset = Vector2.ZERO
	_invalidate()

func _invalidate() -> void:
	_dirty = true
	queue_redraw()
	if is_instance_valid(_front): _front.queue_redraw()

func _travel(at: float) -> Vector2:
	var u := fposmod(at, LOOP_SECONDS) / LOOP_SECONDS
	return Vector2(shoulder_travel.sample_baked(u), shoulder_drop.sample_baked(u))

# After a change of direction, a fold travels outwards, loses energy and settles.
# The compact envelope is exactly zero through the loop seam, even when scrubbing.
func _fold(at: float, start: float, length: float) -> float:
	var u := (at-start)/length
	if u <= 0.0 or u >= 1.0: return 0.0
	return sin(TAU*1.16*u) * sin(PI*u) * (1.0-u) * (1.0-u) * 2.8

func _wake(at: float) -> float:
	return (0.55*_fold(at, 1.12, 0.57) - 0.83*_fold(at, 1.72, 0.66)
		+ 1.36*_fold(at, 2.44, 0.95) - 0.78*_fold(at, 3.41, 0.90)
		+ 0.72*_fold(at, 4.65, 0.67))

func _draw() -> void:
	if not _atlas: return
	_prepare_meshes()
	for ribbon in _layers:
		var texture := _hair_paint if ribbon.kind == Fabric.LOCK else _atlas
		if texture and ribbon.path.curve and ribbon.path.curve.point_count >= 2:
			_submit(get_canvas_item(), ribbon, ribbon.colors, texture)

func _draw_near_fold() -> void:
	if not _atlas or _layers.is_empty(): return
	_prepare_meshes()
	var sash := _layers[0]
	if sash.has_front: _submit(_front.get_canvas_item(), sash, sash.front_colors, _atlas)

func _submit(item: RID, ribbon: Ribbon, colors: PackedColorArray, texture: Texture2D) -> void:
	RenderingServer.canvas_item_add_triangle_array(item, ribbon.indices, ribbon.vertices,
		colors, ribbon.uvs, _no_bones, _no_weights, texture.get_rid())

func _prepare_meshes() -> void:
	if not _dirty or not (shoulder_travel and shoulder_drop and body_turns and sweep_tension): return
	var now := _travel(_time)
	for ribbon in _layers:
		if ribbon.path.curve and ribbon.path.curve.point_count >= 2: _shape_ribbon(ribbon, now)
	_dirty = false

func _shape_ribbon(r: Ribbon, now: Vector2) -> void:
	var offset := _waist_offset
	var is_hair := r.kind == Fabric.HAIR or r.kind == Fabric.LOCK
	if r.kind == Fabric.SASH: offset = _shoulder_offset
	elif is_hair: offset = _hair_offset
	var fabric_row: int = FABRIC_ROWS[r.kind]
	var length := r.path.curve.get_baked_length()
	var idle_angle := TAU*3.0*_time/LOOP_SECONDS + r.phase
	var scale_factor := r.width / 15.5
	var previous_rest := Vector2.ZERO
	var previous_point := Vector3.ZERO
	var origin := r.path.position + offset
	r.has_front = false
	for i in r.count + 1:
		var u := float(i) / r.count
		var free := smoothstep(0.0, 0.92, u)
		var delayed := _time - r.delay*u
		var lag := (_travel(delayed)-now) * (0.58 + 0.42*free)
		if r.kind == Fabric.HEM or r.kind == Fabric.JADE: lag.x *= 0.59
		if is_hair: lag *= 0.36 if r.kind == Fabric.LOCK else 0.57
		var rest := r.path.transform.basis_xform(r.path.curve.sample_baked(u*length, true))
		var wind := Vector2(1.6*sin(idle_angle-5.0*u), 2.65*sin(idle_angle-4.4*u))
		var fold := _wake(_time-r.delay*u*0.78)
		var lift := Vector2(2.2*cos(PI*u), -9.0) * fold
		var phase := fposmod(_time-r.delay*(0.57*u+0.12*u*u), LOOP_SECONDS)/LOOP_SECONDS
		var tension := sweep_tension.sample_baked(phase)
		var yaw := TAU*body_turns.sample_baked(phase) + free*(0.38*fold+0.075*sin(idle_angle+r.phase))*tension
		var radius := length*(0.53*u+0.21*sin(PI*u*0.5))
		var height := 21.0*u + 6.5*sin(PI*u) + 19.0*maxf(0.0, sin(yaw))*u
		if is_hair:
			radius = length*0.94*u
			height = rest.y*0.42 - 3.5*sin(PI*u)
		elif r.kind != Fabric.SASH:
			height = rest.y*0.74 - 4.0*sin(PI*u)
		var orbit := Vector3(-cos(yaw)*radius, height, sin(yaw)*radius)
		var wanted := Vector3(rest.x,rest.y,0.0).lerp(orbit,tension)
		var flutter := lag*(1.0-0.43*tension) + free*(wind+lift)*(0.47+0.53*scale_factor)
		wanted += Vector3(flutter.x,flutter.y,0.0)
		if i > 0:
			# Preserve length in three dimensions. A strip turning towards the camera foreshortens.
			var segment := wanted - previous_point
			var rest_length := previous_rest.distance_to(rest)
			wanted = previous_point + segment.normalized()*clampf(segment.length(),rest_length*0.90,rest_length*1.08)
		r.centers[i] = origin + Vector2(wanted.x, wanted.y+0.21*wanted.z)
		if r.kind == Fabric.SASH: r.depths[i] = wanted.z
		previous_point = wanted
		previous_rest = rest
	for i in r.count + 1:
		var u := float(i) / r.count
		var span := r.centers[mini(i+1, r.count)]-r.centers[maxi(0, i-1)]
		var normal := Vector2(-span.y, span.x).normalized()
		var wake := _wake(_time-r.delay*u*0.78)
		var twist := smoothstep(0.0, 0.85, u)*(0.17*sin(idle_angle-5.2*u)+0.55*wake)
		var roll := cos(TAU*(0.72*u-0.095) + twist)
		if r.kind == Fabric.SASH and sash_turns:
			roll = sash_turns.sample_baked(clampf(u+twist*0.068, 0.0, 1.0))
		var full := r.width * lerpf(0.44, 1.0, smoothstep(0.0, 0.15, u))
		if r.kind == Fabric.LOCK: roll = 0.88 + 0.1*sin(u*TAU+idle_angle)
		full *= lerpf(1.0, 0.033, smoothstep(0.72 if r.kind != Fabric.HEM else 0.84, 1.0, u))
		var half_width := full * (0.075+0.425*absf(roll))
		var front := smoothstep(-0.32, 0.48, roll)
		var shade := Color("bd939d").lerp(Color.WHITE, front)
		if r.kind == Fabric.JADE: shade = Color("92a097").lerp(Color.WHITE, front)
		var row := 1 if roll < 0.0 and r.kind == Fabric.SASH else fabric_row
		var start := (row + 0.024)/4.0
		var end := (row + 0.976)/4.0
		if roll < 0.0:
			var swap := start
			start = end
			end = swap
		# The wide upper curl carries the main gilded cloud, clear of the shoulder guard.
		var tex_u := lerpf(0.006, 0.994, u*u if r.kind == Fabric.SASH else u)
		if r.kind == Fabric.LOCK:
			# Sample the actual brunette hair painting under the ornaments on the rear bun.
			tex_u = lerpf(0.29, 0.69, u)
			start = 0.24
			end = 0.44
		var pos := r.centers[i]
		var j := i*STRIDE
		# Coverage falls above and below the selvages, leaving the painted center opaque.
		var feather := minf(0.54, half_width+0.09)
		r.vertices[j] = pos-normal*(half_width+feather)
		r.vertices[j+1] = pos-normal*half_width
		r.vertices[j+2] = pos-normal*half_width*0.16
		r.vertices[j+3] = pos+normal*half_width
		r.vertices[j+4] = pos+normal*(half_width+feather)
		r.uvs[j] = Vector2(tex_u, start)
		r.uvs[j+1] = r.uvs[j]
		r.uvs[j+2] = Vector2(tex_u, lerpf(start,end,0.42))
		r.uvs[j+3] = Vector2(tex_u, end)
		r.uvs[j+4] = r.uvs[j+3]
		r.colors[j] = Color(shade, 0.0)
		r.colors[j+1] = shade.darkened(0.12)
		r.colors[j+2] = shade
		r.colors[j+3] = shade.darkened(0.23)
		r.colors[j+4] = Color(shade, 0.0)
		if r.kind == Fabric.SASH:
			# Only the portion on the camera side crossing the waist comes in front of the robe.
			var clearance := minf(r.depths[i]-16.0, pos.y-origin.y-19.0)
			clearance = minf(clearance, 63.0-absf(pos.x-(WAIST_BIND.x+_waist_offset.x)))
			if _back_grip.is_finite():
				# The shaft and hands pass behind the body during a turn; let the short fold
				# slip low at the waist when either grip crosses its screen projection.
				var hand_gap := minf(pos.distance_to(_back_grip), pos.distance_to(_forward_grip))
				clearance = minf(clearance, hand_gap-12.0)
			var opacity := smoothstep(-2.5, 2.5, clearance)
			r.has_front = r.has_front or opacity>0.0
			for k in STRIDE:
				var color := r.colors[j+k]
				color.a *= opacity
				r.front_colors[j+k] = color
