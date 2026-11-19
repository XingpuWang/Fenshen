extends RefCounted
## Stage-space weight transfer and footfalls. The rig closes its legs to the two sole goals.
const LOOP_SECONDS := 6.40
const GROUND_SLOPE := -.0615
const REAR_REST := -27.0
const FRONT_REST := 33.0

# Time, horizontal displacement in stage pixels, velocity in pixels/second.
# Tangents carry the pelvis across the two sweeps. The final strike has a flat stop.
const WEIGHT: Array[Vector3] = [
	Vector3(.55, 0, 0), Vector3(.95, -8, -17), Vector3(1.10, -10, 0),
	Vector3(1.26, -4, 68), Vector3(1.52, 15, 57), Vector3(1.78, 22, 24),
	Vector3(2.12, 34, 32), Vector3(2.40, 38, 0), Vector3(2.86, 29, 0),
	Vector3(2.94, 30, 19), Vector3(3.07, 38, 125), Vector3(3.19, 64, 200),
	Vector3(3.30, 78, 0), Vector3(3.41, 78, 0), Vector3(3.72, 81, 0),
	Vector3(4.05, 78, -18), Vector3(4.32, 62, -85), Vector3(4.64, 27, -99),
	Vector3(4.82, 10, -87), Vector3(4.95, 0, 0),
]

# Liftoff, touchdown, displacement from this boot's original footprint, maximum lift.
# Between these windows a boot stays at the same world position as the pelvis shifts.
const REAR_STEPS: Array[Vector4] = [
	Vector4(1.58, 1.99, 30.7, 15.5),
	Vector4(3.16, 3.29, 67.7, 10.0),
	Vector4(4.32, 4.66, 0.0, 15.0),
]
const FRONT_STEPS: Array[Vector4] = [
	Vector4(1.10, 1.45, 23.3, 11.0),
	Vector4(2.15, 2.52, 34.3, 8.0),
	Vector4(2.96, 3.15, 69.3, 13.0),
	Vector4(4.05, 4.30, 42.3, 9.0),
	Vector4(4.68, 4.95, 0.0, 11.0),
]
static var shadow_mask: Texture2D

static func displacement_at(t: float) -> Vector2:
	var time := fposmod(t, LOOP_SECONDS)
	if time <= WEIGHT[0].x or time >= WEIGHT[-1].x: return Vector2.ZERO
	for i in range(1, WEIGHT.size()):
		var next := WEIGHT[i]
		if time > next.x: continue
		var previous := WEIGHT[i - 1]
		var duration := next.x - previous.x
		var u := (time - previous.x) / duration
		# Cubic Hermite interpolation with authored incoming and outgoing speeds.
		var travel := lerpf(previous.y, next.y, smoothstep(0, 1, u))
		travel += duration * u * (1.0-u) * ((1.0-u) * previous.z - u * next.z)
		return Vector2(travel, travel * GROUND_SLOPE)
	return Vector2.ZERO

static func _step_at(steps: Array[Vector4], time: float) -> Vector2:
	var previous := 0.0
	for step in steps:
		if time <= step.x: break
		if time >= step.y:
			previous = step.z
			continue
		var u := inverse_lerp(step.x, step.y, time)
		var travel := u*u*u * (10.0 - 15.0*u + 6.0*u*u)
		return Vector2(lerpf(previous, step.z, travel), step.w * sin(PI * u))
	return Vector2(previous, 0)

static func _pivot_arc(foot: int, time: float) -> float:
	# In the first turn the near shoe opens downstage, and the rear shoe circles upstage.
	# The second sweep changes direction as the front shoe is brought back onto the thrust line.
	var phase := 0.0
	var depth := 0.0
	if foot == 0:
		phase = clampf(inverse_lerp(1.58, 1.99, time), 0, 1)
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
		goals.append((footprint - Vector2(0, step.y) - root) / actor_scale)
	return goals

## feet contains the actual rear and front sole markers in unscaled actor space.
static func draw_shadow(canvas: CanvasItem, neutral_ground: Vector2, t: float, actor_scale: float = 1.0,
		feet: PackedVector2Array = PackedVector2Array()) -> void:
	if actor_scale <= 0: return
	var motion := displacement_at(t)
	var time := fposmod(t, LOOP_SECONDS)
	if feet.size() != 2: feet = sole_goals_at(t, actor_scale)
	var span := absf(feet[1].x - feet[0].x)
	var centre := neutral_ground + motion + Vector2((feet[0].x + feet[1].x) * .5 + 12, 3) * actor_scale
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
		if pressure > .02:
			_stamp(canvas, shoe_at, Vector2(17, 3.8) * actor_scale, .55 * pressure)

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
