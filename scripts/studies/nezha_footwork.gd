extends RefCounted
## Root motion in 1280 × 720 stage pixels. The skeleton animates in its own local space.
const LOOP_SECONDS := 4.80
const GROUND_SLOPE := -.0615
const IMPACT_X := 184.0
static var shadow_mask: Texture2D

static func displacement_at(t: float) -> Vector2:
	var time := fposmod(t, LOOP_SECONDS)
	if time < 1.15 or time >= 2.94: return Vector2.ZERO
	if time < 1.62: return _ground_shift(0, -8, inverse_lerp(1.15, 1.62, time))
	if time < 1.84: return _hop(-8, IMPACT_X, inverse_lerp(1.62, 1.84, time), 3.8)
	if time <= 1.91: return Vector2(IMPACT_X, IMPACT_X * GROUND_SLOPE)
	if time < 2.20: return _ground_shift(IMPACT_X, 189, inverse_lerp(1.91, 2.20, time))
	# Load the front foot, catch the first retreat on the rear foot, then land at home.
	if time < 2.27: return Vector2(189, 189 * GROUND_SLOPE)
	if time < 2.53: return _hop(189, 70, inverse_lerp(2.27, 2.53, time), 27)
	if time < 2.61: return Vector2(70, 70 * GROUND_SLOPE)
	if time < 2.84: return _hop(70, 0, inverse_lerp(2.61, 2.84, time), 19)
	return Vector2.ZERO

static func _ground_shift(start: float, finish: float, phase: float) -> Vector2:
	var distance := lerpf(start, finish, smoothstep(0, 1, phase))
	return Vector2(distance, distance * GROUND_SLOPE)

static func _hop(start: float, finish: float, phase: float, height: float) -> Vector2:
	# The soles clear the floor before significant horizontal travel and touch down at rest.
	var weight := phase ** 3 * (10.0 - 15.0 * phase + 6.0 * phase ** 2)
	var distance := lerpf(start, finish, weight)
	return Vector2(distance, distance * GROUND_SLOPE - 4.0 * height * phase * (1.0 - phase))

## feet contains the rear and front sole markers in unscaled actor space, relative to its root.
static func draw_shadow(canvas: CanvasItem, neutral_ground: Vector2, t: float, actor_scale: float = 1.0,
		feet: PackedVector2Array = PackedVector2Array()) -> void:
	if actor_scale <= 0: return
	var motion := displacement_at(t)
	var floor_at := neutral_ground + Vector2(motion.x, motion.x * GROUND_SLOPE)
	var lift := floor_at.y - (neutral_ground.y + motion.y)
	if feet.size() != 2:
		var time := fposmod(t, LOOP_SECONDS)
		var spread := smoothstep(1.62, 1.84, time) * (1.0 - smoothstep(2.20, 2.94, time))
		feet = PackedVector2Array([Vector2(-26 - 35 * spread, 0), Vector2(25 + 43 * spread, 0)])
	var span := absf(feet[1].x - feet[0].x)
	var centre := floor_at + Vector2((feet[0].x + feet[1].x) * .5 + 12, 3) * actor_scale
	var airborne := smoothstep(0, 28, lift)
	_stamp(canvas, centre, Vector2(span + 72 + 12 * airborne, 15 + 5 * airborne) * actor_scale, .24 - .055 * airborne)
	for foot in feet:
		var local_height := foot.y * actor_scale
		var floor_height := maxf(local_height, -2.0 * actor_scale)
		var gap := maxf(0, floor_height - local_height + lift)
		var pressure := 1.0 - smoothstep(0, 21 * actor_scale, gap)
		var shoe_at := floor_at + Vector2(foot.x * actor_scale, floor_height)
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
