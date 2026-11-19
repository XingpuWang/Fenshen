@tool
extends Node2D
## Secondary animation for Nezha's ribbons. Pose the sibling rig first, then call pose_at.
const Textures = preload("res://scripts/runtime_textures.gd")
const LOOP_SECONDS := 4.80
const STRIDE := 5 # transparent edge, upper selvage, ridge, lower selvage, transparent edge
const SHOULDER_BIND := Vector2(-12, -158)
const HAIR_BIND := Vector2(-20, -201)
const WAIST_BIND := Vector2(-12, -96)
const FABRIC_ROWS := [0, 1, 3, 2]

enum Fabric { SASH, HAIR, JADE, HEM }

@export_file("*.png") var silk_art := "res://assets/nezha_study/silk/brocade.png"
@export var shoulder_travel: Curve
@export var shoulder_drop: Curve
@export var sash_turns: Curve
@export_range(0.0, 4.8, 0.005) var editor_time := 0.0:
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
		for i in count:
			for j in STRIDE - 1:
				var a := STRIDE*i+j
				var b := a+STRIDE
				indices.append_array(PackedInt32Array([a, b, a+1, a+1, b, b+1]))

var _layers: Array[Ribbon] = []
var _no_bones := PackedInt32Array()
var _no_weights := PackedFloat32Array()
var _atlas: Texture2D
var _time := 0.0
var _shoulder_offset := Vector2.ZERO
var _hair_offset := Vector2.ZERO
var _waist_offset := Vector2.ZERO

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_atlas = load(silk_art) as Texture2D if Engine.is_editor_hint() else Textures.get_texture(silk_art)
	_layers.assign([
		Ribbon.new($Sash, Fabric.SASH, 15.5, 0.38, 0.0, 44),
		Ribbon.new($WaistSilk, Fabric.JADE, 7.8, 0.24, 2.4, 20),
		Ribbon.new($CoatTail, Fabric.HEM, 17.0, 0.31, 1.5, 26),
		Ribbon.new($HairLow, Fabric.HAIR, 5.0, 0.21, 2.6, 14),
		Ribbon.new($HairHigh, Fabric.HAIR, 5.7, 0.17, 0.7, 16)
	])
	for ribbon in _layers:
		if ribbon.path.curve: ribbon.path.curve.changed.connect(queue_redraw)
	for motion in [shoulder_travel, shoulder_drop, sash_turns]:
		if motion: motion.changed.connect(queue_redraw)
	pose_at(editor_time if Engine.is_editor_hint() else 0.0, null)

func pose_at(seconds: float, rig: Node2D) -> void:
	_time = fposmod(seconds, LOOP_SECONDS)
	if is_instance_valid(rig):
		_shoulder_offset = to_local(rig.to_global(rig.cloth_anchor())) - SHOULDER_BIND
		_hair_offset = to_local(rig.to_global(rig.hair_anchor())) - HAIR_BIND
		_waist_offset = to_local(rig.to_global(rig.hem_anchor())) - WAIST_BIND
	else:
		_shoulder_offset = Vector2.ZERO
		_hair_offset = Vector2.ZERO
		_waist_offset = Vector2.ZERO
	queue_redraw()

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
	return -0.47*_fold(at, 1.62, 0.64) + _fold(at, 1.91, 0.87) - 0.88*_fold(at, 2.83, 0.80)

func _draw() -> void:
	if not _atlas or not shoulder_travel or not shoulder_drop: return
	var now := _travel(_time)
	for ribbon in _layers:
		if not ribbon.path.curve or ribbon.path.curve.point_count < 2: continue
		_draw_ribbon(ribbon, now)

func _draw_ribbon(r: Ribbon, now: Vector2) -> void:
	var offset := _waist_offset
	if r.kind == Fabric.SASH: offset = _shoulder_offset
	elif r.kind == Fabric.HAIR: offset = _hair_offset
	var fabric_row: int = FABRIC_ROWS[r.kind]
	var length := r.path.curve.get_baked_length()
	var idle_angle := TAU * _time / (LOOP_SECONDS*0.5) + r.phase
	var scale_factor := r.width / 15.5
	var previous_rest := Vector2.ZERO
	for i in r.count + 1:
		var u := float(i) / r.count
		var free := smoothstep(0.0, 0.92, u)
		var delayed := _time - r.delay*u
		var lag := (_travel(delayed)-now) * (0.58 + 0.42*free)
		if r.kind == Fabric.HEM or r.kind == Fabric.JADE: lag.x *= 0.59
		if r.kind == Fabric.HAIR: lag *= 0.57
		var rest := r.path.transform * r.path.curve.sample_baked(u*length, true)
		var wind := Vector2(1.6*sin(idle_angle-5.0*u), 2.65*sin(idle_angle-4.4*u))
		var fold := _wake(_time-r.delay*u*0.78)
		var lift := Vector2(2.0*cos(PI*u), -8.0) * fold
		var desired := rest + offset + lag + free*(wind+lift)*(0.47+0.53*scale_factor)
		if i == 0:
			r.centers[i] = desired
		else:
			# Preserve the physical strip length when the forward step pulls its curls open.
			var segment := desired - r.centers[i-1]
			var rest_length := previous_rest.distance_to(rest)
			r.centers[i] = r.centers[i-1] + segment.normalized()*clampf(segment.length(),rest_length*0.93,rest_length*1.06)
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
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), r.indices, r.vertices,
		r.colors, r.uvs, _no_bones, _no_weights, _atlas.get_rid())
