@tool
extends Node2D
## Secondary animation for Nezha's ribbons. Pose the sibling rig first, then call pose_at.
const Textures = preload("res://scripts/runtime_textures.gd")
const LOOP_SECONDS := 6.40
const SAMPLE_RATE := 60.0
const SAMPLES := 384
const STATIONS := 6 # Six damped points between the attachment and the free tip.
const STRIDE := 5 # transparent edge, upper selvage, ridge, lower selvage, transparent edge
const SHOULDER_BIND := Vector2(-12, -158)
const HAIR_BIND := Vector2(-20, -201)
const WAIST_BIND := Vector2(-12, -96)
const FABRIC_ROWS := [0, 1, 3, 2, 0]

enum Fabric { SASH, HAIR, JADE, HEM, LOCK }
enum Attachment { SHOULDER, HAIR_TIE, HIP }
const DAMPING := [0.57, 0.74, 0.77, 0.68, 0.84]

@export_file("*.png") var silk_art := "res://assets/nezha_study/silk/brocade.png"
@export_file("*.png") var hair_art := "res://assets/nezha_study/actor/bun_near.png"
@export var shoulder_travel: Curve
@export var shoulder_drop: Curve
@export var body_turns: Curve
@export var sweep_tension: Curve
@export var sash_turns: Curve
@export var breeze_pressure: Curve
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
	var exposure: float
	var attachment: Attachment
	var response: Array[PackedVector3Array] = []
	var stations := PackedVector3Array()
	var count: int
	var indices := PackedInt32Array()
	var centers := PackedVector2Array()
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var depths := PackedFloat32Array()
	var twists := PackedFloat32Array()
	var front_colors := PackedColorArray()
	var has_front := false
	var uvs := PackedVector2Array()

	func _init(guide: Path2D, fabric: Fabric, breadth: float, lag: float, breeze: float, segments: int) -> void:
		path = guide
		kind = fabric
		width = breadth
		delay = lag
		exposure = breeze
		match fabric:
			Fabric.SASH: attachment = Attachment.SHOULDER
			Fabric.HAIR, Fabric.LOCK: attachment = Attachment.HAIR_TIE
			_: attachment = Attachment.HIP
		count = segments
		stations.resize(STATIONS+1)
		centers.resize(count + 1)
		twists.resize(count + 1)
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
# x and y are the world-travelling attachment in unscaled character units, z is yaw.
var _anchors: Array[PackedVector3Array] = []
var _winding := PackedFloat32Array([0.0, 0.0, 0.0])
var _recorded_body := false
var _response_dirty := true

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_atlas = load(silk_art) as Texture2D if Engine.is_editor_hint() else Textures.get_texture(silk_art)
	_hair_paint = load(hair_art) as Texture2D if Engine.is_editor_hint() else Textures.get_texture(hair_art)
	_layers.assign([
		Ribbon.new($Sash, Fabric.SASH, 15.5, 0.40, 1.0, 54),
		Ribbon.new($WaistSilk, Fabric.JADE, 7.8, 0.22, 0.47, 20),
		Ribbon.new($CoatTail, Fabric.HEM, 17.0, 0.31, 0.36, 26),
		Ribbon.new($LooseHair, Fabric.LOCK, 4.8, 0.13, 0.52, 14),
		Ribbon.new($ShortLock, Fabric.LOCK, 2.8, 0.09, 0.33, 12),
		Ribbon.new($HairLow, Fabric.HAIR, 5.0, 0.21, 0.85, 14),
		Ribbon.new($HairHigh, Fabric.HAIR, 5.7, 0.17, 0.96, 16)
	])
	for k in Attachment.size():
		var track := PackedVector3Array()
		track.resize(SAMPLES)
		_anchors.append(track)
	for ribbon in _layers:
		if ribbon.path.curve: ribbon.path.curve.changed.connect(_invalidate)
	for guide in [shoulder_travel, shoulder_drop, body_turns]:
		if guide: guide.changed.connect(_motion_changed)
	for motion in [sweep_tension, sash_turns, breeze_pressure]:
		if motion: motion.changed.connect(_invalidate)
	_front.draw.connect(_draw_near_fold)
	pose_at(editor_time if Engine.is_editor_hint() else 0.0, null)

# Called during the stage's existing weapon-path bake, with the rig already posed.
func record_anchor_sample(tick: int, rig: Node2D) -> void:
	if tick < 0 or tick >= SAMPLES: return
	var actor := get_parent() as Node2D
	var root_travel := (actor.transform * transform).affine_inverse().basis_xform(actor.position)
	var shoulder := to_local(rig.to_global(rig.cloth_anchor())) + root_travel
	var hair := to_local(rig.to_global(rig.hair_anchor())) + root_travel
	var waist := to_local(rig.to_global(rig.hem_anchor())) + root_travel
	_anchors[Attachment.SHOULDER][tick] = Vector3(shoulder.x, shoulder.y, deg_to_rad(rig.chest_turn))
	_anchors[Attachment.HAIR_TIE][tick] = Vector3(hair.x, hair.y, deg_to_rad(rig.face_turn))
	_anchors[Attachment.HIP][tick] = Vector3(waist.x, waist.y, deg_to_rad(rig.hip_turn))
	if tick == SAMPLES-1:
		_recorded_body = true
		_motion_changed()

func _motion_changed() -> void:
	_response_dirty = true
	_invalidate()

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

func _sample(track: PackedVector3Array, frame: float, winding: float) -> Vector3:
	var tick := floori(frame)
	var index := posmod(tick, SAMPLES)
	var next := track[(index + 1) % SAMPLES]
	if index == SAMPLES-1: next.z += winding
	var value := track[index].lerp(next, frame - tick)
	value.z += floorf(frame / SAMPLES) * winding
	return value

func _bake_responses() -> void:
	if not _recorded_body:
		# The component's editor timeline can be played without a sibling skeleton.
		for frame in SAMPLES:
			var u := float(frame) / SAMPLES
			var guide := Vector3(shoulder_travel.sample_baked(u), shoulder_drop.sample_baked(u),
				TAU * body_turns.sample_baked(u))
			for track in _anchors: track[frame] = guide
	for index in _anchors.size():
		var track := _anchors[index]
		_winding[index] = roundf((track[-1].z-track[0].z) / TAU) * TAU
	for ribbon in _layers:
		var track := _anchors[ribbon.attachment]
		ribbon.response.assign([track])
		for station in range(1, STATIONS+1):
			var span := float(station) / STATIONS
			ribbon.response.append(_spring_track(track, ribbon.delay * span ** 1.25,
				DAMPING[ribbon.kind], _winding[ribbon.attachment]))
	_response_dirty = false

func _spring_track(input: PackedVector3Array, response_time: float, damping: float, winding: float) -> PackedVector3Array:
	# Analytic solution of a damped mass following the previous attachment pose.
	# The same fixed-rate motion is available to real-time playback and a backwards seek.
	var flight := 0.47 * response_time * SAMPLE_RATE
	var frequency := 2.0 * damping / (0.53 * response_time)
	var damped := frequency * sqrt(1.0 - damping*damping)
	var decay := exp(-damping * frequency / SAMPLE_RATE)
	var cosine := cos(damped / SAMPLE_RATE)
	var sine := sin(damped / SAMPLE_RATE) / damped
	var position_gain := decay * (cosine + damping*frequency*sine)
	var velocity_gain := decay * (cosine - damping*frequency*sine)
	var velocity_to_position := decay*sine
	var position_to_velocity := -velocity_to_position*frequency*frequency
	var position := _sample(input, -SAMPLES-flight, winding)
	var velocity := Vector3.ZERO
	var output := PackedVector3Array()
	output.resize(SAMPLES)
	# The previous revolution primes the spring so the loop join has the same history.
	for tick in range(-SAMPLES, SAMPLES):
		var target := _sample(input, tick-flight, winding)
		var error := position-target
		position = target + position_gain*error + velocity_to_position*velocity
		velocity = position_to_velocity*error + velocity_gain*velocity
		if tick >= 0: output[tick] = position
	return output

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
	if _response_dirty: _bake_responses()
	for ribbon in _layers:
		if ribbon.path.curve and ribbon.path.curve.point_count >= 2: _shape_ribbon(ribbon)
	_dirty = false

func _shape_ribbon(r: Ribbon) -> void:
	var offset := _waist_offset
	var is_hair := r.attachment == Attachment.HAIR_TIE
	if r.kind == Fabric.SASH: offset = _shoulder_offset
	elif is_hair: offset = _hair_offset
	var fabric_row: int = FABRIC_ROWS[r.kind]
	var length := r.path.curve.get_baked_length()
	var clock := _time*SAMPLE_RATE
	var winding := _winding[r.attachment]
	for station in r.response.size():
		r.stations[station] = _sample(r.response[station], clock, winding)
	var source := r.stations[0]
	var intensity := sweep_tension.sample_baked(_time/LOOP_SECONDS)
	var breeze := breeze_pressure.sample_baked(_time/LOOP_SECONDS) if breeze_pressure else 0.0
	var draft := r.exposure * breeze * Vector2(-4.2, -2.4)
	var previous_rest := Vector2.ZERO
	var previous_point := Vector3.ZERO
	var origin := r.path.position + offset
	r.has_front = false
	for i in r.count + 1:
		var u := float(i) / r.count
		var free := smoothstep(0.0, 1.0, u)
		var station := mini(floori(u*STATIONS), STATIONS-1)
		var response := r.stations[station].lerp(r.stations[station+1], u*STATIONS-station)
		var lag := Vector2(response.x-source.x, response.y-source.y)
		var turn_lag := clampf(source.z-response.z, -2.6, 2.6)
		var angular_load := smoothstep(0.07, 1.25, absf(turn_lag))
		var travel_load := smoothstep(3.0, 48.0, lag.length())
		var tension := clampf(0.14*intensity + 0.78*angular_load + 0.30*travel_load, 0.0, 1.0)
		var rest := r.path.transform.basis_xform(r.path.curve.sample_baked(u*length, true))
		var yaw := response.z
		var radius := length*(0.53*u+0.21*sin(PI*u*0.5))
		var height := 19.0*u + 7.5*sin(PI*u) + 19.0*maxf(0.0, sin(yaw))*u
		if is_hair:
			radius = length*0.94*u
			height = rest.y*0.42 - 3.5*sin(PI*u)
		elif r.kind != Fabric.SASH:
			height = rest.y*0.74 - 4.0*sin(PI*u)
		# The attached part follows its own bone. The outward sections retain their
		# former heading and momentum until the turn reaches them.
		radius = lerpf(-rest.x, radius, tension)
		var wanted := Vector3(-cos(yaw)*radius, lerpf(rest.y,height,tension), sin(yaw)*radius)
		var drift := lag * (0.40 if is_hair else 0.65)
		if r.attachment == Attachment.HIP: drift.x *= 0.67
		drift += draft * free * (1.0-0.70*tension)
		wanted += Vector3(drift.x, drift.y, 0.0)
		r.twists[i] = free * clampf(0.43*turn_lag + 0.011*lag.y + 0.12*breeze, -1.1, 1.1)
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
		var twist := r.twists[i]
		var roll := cos(TAU*(0.72*u-0.095) + twist)
		if r.kind == Fabric.SASH and sash_turns:
			roll = sash_turns.sample_baked(clampf(u+twist*0.068, 0.0, 1.0))
		var full := r.width * lerpf(0.44, 1.0, smoothstep(0.0, 0.15, u))
		if r.kind == Fabric.LOCK: roll = 0.91 + 0.06*twist
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
