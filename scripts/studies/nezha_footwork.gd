extends RefCounted
## Stage-space weight transfer and footfalls. The rig closes its legs to the two sole goals.
const LOOP_SECONDS := 6.40
const GROUND_SLOPE := -.0615
const REAR_REST := -27.0
const FRONT_REST := 33.0
const SOLE_LEVER := 8.0

# Time, horizontal displacement in stage pixels, velocity in pixels/second.
# Tangents carry the pelvis across the two sweeps. The final strike has a flat stop.
const WEIGHT: Array[Vector3] = [
	Vector3(.55, 0, 0), Vector3(.94, -10, -23), Vector3(1.13, -14, 0),
	Vector3(1.28, -9, 62), Vector3(1.52, 14, 98), Vector3(1.72, 30, 49),
	Vector3(1.85, 34, 0), Vector3(2.13, 24, -53), Vector3(2.35, 18, 0),
	Vector3(2.63, 24, 5), Vector3(2.83, 22, 0), Vector3(2.94, 24, 43),
	Vector3(3.07, 38, 160), Vector3(3.19, 64, 199), Vector3(3.30, 78, 0),
	Vector3(3.41, 78, 0), Vector3(3.63, 81, 0), Vector3(3.84, 78, -30),
	Vector3(4.05, 66, -65), Vector3(4.22, 55, -32), Vector3(4.29, 54, 0),
	Vector3(4.40, 58, 0), Vector3(4.50, 54, -86), Vector3(4.64, 30, -155),
	Vector3(4.76, 13, -113), Vector3(4.89, 1, -38), Vector3(4.95, 0, 0),
]
# Small changes in height let the supporting knee take the load under the body.
# Positive values sink toward the floor; both soles remain independently planted.
const COMPRESSION: Array[Vector3] = [
	Vector3(.55, 0, 0), Vector3(1.08, 5, 0), Vector3(1.39, -.9, -9),
	Vector3(1.53, 1.4, 12), Vector3(1.69, 2.1, -3), Vector3(2.07, -2.5, 0),
	Vector3(2.40, 1.2, 6), Vector3(2.84, 4.7, 0), Vector3(3.04, 1.7, -28),
	Vector3(3.13, -.7, 0), Vector3(3.30, 2.5, 0), Vector3(3.41, 2.5, 0),
	Vector3(3.53, 3.5, 0), Vector3(3.86, .1, -7), Vector3(4.12, 2.0, 0),
	Vector3(4.28, 0, -7), Vector3(4.49, -1.6, 0), Vector3(4.70, 2.2, 0),
	Vector3(4.95, 0, 0),
]

# Liftoff, touchdown, displacement from this boot's original footprint, maximum lift.
# Between these windows a boot stays at the same world position as the pelvis shifts.
const REAR_STEPS: Array[Vector4] = [
	Vector4(1.55, 1.97, 30.7, 8.3),
	Vector4(3.15, 3.29, 67.7, 4.6),
	Vector4(4.30, 4.67, 0.0, 9.2),
]
const FRONT_STEPS: Array[Vector4] = [
	Vector4(1.10, 1.45, 23.3, 6.0),
	Vector4(2.15, 2.52, 34.3, 3.7),
	Vector4(2.94, 3.15, 64.3, 7.2),
	Vector4(4.05, 4.30, 38.3, 4.2),
	Vector4(4.68, 4.95, 0.0, 5.3),
]
static var shadow_mask: Texture2D

static func displacement_at(t: float) -> Vector2:
	var time := fposmod(t, LOOP_SECONDS)
	var travel := _weight_at(WEIGHT, time)
	return Vector2(travel, travel * GROUND_SLOPE + _weight_at(COMPRESSION, time))

static func _weight_at(keys: Array[Vector3], time: float) -> float:
	if time <= keys[0].x or time >= keys[-1].x: return 0
	for i in range(1, keys.size()):
		var next := keys[i]
		if time > next.x: continue
		var previous := keys[i - 1]
		var duration := next.x - previous.x
		var u := (time - previous.x) / duration
		# Cubic Hermite interpolation with authored incoming and outgoing speeds.
		return lerpf(previous.y, next.y, smoothstep(0, 1, u)) + duration*u*(1.0-u)*((1.0-u)*previous.z-u*next.z)
	return 0

# Returns travel, sole clearance and boot roll in radians. The moving shoe
# rolls off one edge, skims across, then touches down on the opposite edge.
static func _step_at(steps: Array[Vector4], time: float) -> Vector3:
	var previous := 0.0
	for step in steps:
		if time <= step.x: break
		if time >= step.y:
			previous = step.z
			continue
		var u := inverse_lerp(step.x, step.y, time)
		var stride := step.z - previous
		var long_step := smoothstep(12, 66, absf(stride))
		var pass_time := lerpf(.39, .48, long_step) if stride>0 else lerpf(.53, .44, long_step)
		var fly := clampf(inverse_lerp(.08, .89, u), 0, 1)
		var travel := fly*fly*fly * (10.0 - 15.0*fly + 6.0*fly*fly)
		var clearance := step.w * smoothstep(.08, pass_time, u) * (1.0 - smoothstep(pass_time, .88, u))
		var departure := smoothstep(0, .18, u) * (1.0 - smoothstep(.18, .44, u))
		var landing := smoothstep(.38, .68, u) * (1.0 - smoothstep(.76, 1.0, u))
		var roll := deg_to_rad(signf(stride) * (lerpf(7,17,long_step)*departure-lerpf(6,12,long_step)*landing))
		return Vector3(lerpf(previous, step.z, travel), clearance, roll)
	return Vector3(previous, 0, 0)

static func sole_rotation_at(t: float, foot: int) -> float:
	return _step_at(REAR_STEPS if foot==0 else FRONT_STEPS, fposmod(t, LOOP_SECONDS)).z

static func _pivot_arc(foot: int, time: float) -> float:
	# In the first turn the near shoe opens downstage, and the rear shoe circles upstage.
	# The second sweep changes direction as the front shoe is brought back onto the thrust line.
	var phase := 0.0
	var depth := 0.0
	if foot == 0:
		phase = clampf(inverse_lerp(1.55, 1.97, time), 0, 1)
		depth = -5.0
	elif time < 1.45:
		phase = clampf(inverse_lerp(1.10, 1.45, time), 0, 1)
		depth = 3.5
	else:
		phase = clampf(inverse_lerp(2.15, 2.52, time), 0, 1)
		depth = -3.5
	return depth * sin(PI * phase) ** 2

static func sole_goals_at(t: float, actor_scale: float = .84) -> PackedVector2Array:
	if actor_scale <= 0: return PackedVector2Array()
	var time := fposmod(t, LOOP_SECONDS)
	var root := displacement_at(time)
	var goals := PackedVector2Array()
	for i in 2:
		var step := _step_at(REAR_STEPS if i == 0 else FRONT_STEPS, time)
		var rest := REAR_REST if i == 0 else FRONT_REST
		var footprint := Vector2(rest * actor_scale + step.x, step.x * GROUND_SLOPE + _pivot_arc(i,time))
		# Rotate the sole marker around the toe or heel that is on the floor.
		var to_centre := Vector2(-signf(step.z) * SOLE_LEVER, 0)
		var roll_offset := to_centre.rotated(step.z) - to_centre
		goals.append((footprint - Vector2(0, step.y) - root) / actor_scale + roll_offset)
	return goals

## feet contains the actual rear and front sole markers in unscaled actor space.
static func draw_shadow(canvas: CanvasItem, neutral_ground: Vector2, t: float, actor_scale: float = 1.0,
		feet: PackedVector2Array = PackedVector2Array()) -> void:
	if actor_scale <= 0: return
	var motion := displacement_at(t)
	var time := fposmod(t, LOOP_SECONDS)
	if feet.size() != 2: feet = sole_goals_at(t, actor_scale)
	var span := absf(feet[1].x - feet[0].x)
	var centre := neutral_ground + Vector2(motion.x, motion.x * GROUND_SLOPE) + Vector2((feet[0].x + feet[1].x) * .5 + 12, 3) * actor_scale
	_stamp(canvas, centre, Vector2(span + 72, 15) * actor_scale, .24)
	for i in 2:
		var sole := neutral_ground + motion + feet[i] * actor_scale
		var rest := REAR_REST if i == 0 else FRONT_REST
		var travel := motion.x + (feet[i].x - rest) * actor_scale
		var shoe_at := Vector2(sole.x, neutral_ground.y + travel * GROUND_SLOPE + _pivot_arc(i,time))
		var gap := maxf(0, shoe_at.y - sole.y)
		var pressure := 1.0 - smoothstep(0, 21 * actor_scale, gap)
		var penumbra := Vector2(26, 7).lerp(Vector2(34, 10), 1.0 - pressure) * actor_scale
		_stamp(canvas, shoe_at + Vector2(2, .8) * actor_scale, penumbra, .11 + .33 * pressure)
		var roll := sole_rotation_at(time,i)
		var edge_gap := maxf(0, gap - SOLE_LEVER * actor_scale * absf(sin(roll)))
		var contact := 1.0-smoothstep(.4*actor_scale,4.4*actor_scale,edge_gap)
		if contact > .02:
			var on_edge := smoothstep(.02, .18, absf(roll))
			var contact_at := shoe_at + Vector2(signf(roll) * SOLE_LEVER * on_edge * actor_scale, 0)
			_stamp(canvas, contact_at, Vector2(lerpf(17,9,on_edge), 3.8) * actor_scale, .55 * contact)

static func _stamp(canvas: CanvasItem, at: Vector2, size: Vector2, opacity: float) -> void:
	if shadow_mask == null:
		var image := Image.create(96, 48, false, Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				var uv := Vector2(x + .5, y + .5) / Vector2(48, 24) - Vector2.ONE
				var r2 := uv.length_squared()
				var coverage := exp(-3.0 * r2) * (1.0 - smoothstep(.67, 1.0, r2))
				image.set_pixel(x, y, Color(1, 1, 1, coverage))
		image.generate_mipmaps()
		shadow_mask = ImageTexture.create_from_image(image)
	canvas.draw_texture_rect(shadow_mask, Rect2(at - size * .5, size), false, Color(.16, .105, .11, opacity))
