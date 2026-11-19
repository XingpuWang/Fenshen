extends Node2D
## The lance follows the metal. After the blow every unfolding petal is measured from its fixed calyx.
const Textures = preload("res://scripts/runtime_textures.gd")
const Unfold = preload("res://assets/nezha_study/spear_fx/lotus_unfold.gdshader")
const ATLAS := "res://assets/nezha_study/spear_fx/lotus_burst.png"
const HIT := 3.30
const JET := Rect2(10, 130, 880, 218)
const BUD := Rect2(978, 8, 450, 429)
const CROWN := Rect2(8, 445, 930, 536)
const PETAL := Rect2(949, 531, 572, 366)
# Coordinates in the original painting: blade point, bud/crown cup, detached petal base.
const NIB := Vector2(872, 252)
const BUD_CUP := Vector2(1117, 387)
const CROWN_CUP := Vector2(365, 838)
const PETAL_BASE := Vector2(976, 866)

var _sheet: Texture2D
var _jet: Sprite2D
var _fringe: Sprite2D
var _bud: Sprite2D
var _crown: Sprite2D
var _lip: Sprite2D
var _point: Sprite2D
var _heart: Sprite2D
var _spur: Sprite2D
var _split: Sprite2D
var _petals: Array[Sprite2D] = []
var _embers: Array[Sprite2D] = []

func _ready() -> void:
	_sheet = Textures.get_texture(ATLAS)
	_fringe = _cel("Sheath", JET, NIB, -9)
	_jet = _cel("Jet", JET, NIB, -8)
	_spur = _cel("ForwardSpur", JET, Vector2(215,252), 12)
	_split = _cel("ImpactPetal", PETAL, PETAL_BASE, 14)
	_bud = _cel("Bud", BUD, BUD_CUP, 15)
	_crown = _cel("Corolla", CROWN, CROWN_CUP, 13, 1)
	_lip = _cel("NearPetals", CROWN, CROWN_CUP, 16, 2)
	_point = _light("Point", 18)
	_heart = _light("Heart", 18)
	for i in 6:
		_petals.append(_cel("FlyingPetal%d" % i, PETAL, PETAL_BASE, 14 if i % 2 else 17))
	for i in 9:
		_embers.append(_cel("Cinder%d" % i, JET, Vector2(590,252), 17))

func _cel(label: String, region: Rect2, socket: Vector2, depth: int, surface := 0) -> Sprite2D:
	var node := Sprite2D.new()
	node.name = label
	node.texture = _sheet
	node.region_enabled = true
	node.region_filter_clip_enabled = true
	node.region_rect = region
	node.centered = false
	node.offset = region.position - socket
	node.z_as_relative = false
	node.z_index = depth
	node.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if region == CROWN or region == BUD:
		var paint := ShaderMaterial.new()
		paint.shader = Unfold
		var uv := region.position / _sheet.get_size()
		var span := region.size / _sheet.get_size()
		paint.set_shader_parameter("atlas_region", Vector4(uv.x, uv.y, span.x, span.y))
		paint.set_shader_parameter("calyx", (socket - region.position) / region.size)
		paint.set_shader_parameter("surface", surface)
		node.material = paint
	add_child(node)
	return node

func _light(label: String, depth: int) -> Sprite2D:
	# Only the burning calyx and the very tip emit light. The broad fire stays painted.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, .17, .39, .68, 1.0])
	gradient.colors = PackedColorArray([Color("fff7da"),Color("ffe083e8"),Color("ffac45a4"),Color("f66c304c"),Color("ee402000")])
	var halo := GradientTexture2D.new()
	halo.width = 64
	halo.height = 64
	halo.fill = GradientTexture2D.FILL_RADIAL
	halo.fill_from = Vector2(.5, .5)
	halo.fill_to = Vector2(1, .5)
	halo.gradient = gradient
	var node := Sprite2D.new()
	node.name = label
	node.texture = halo
	node.texture_filter = TEXTURE_FILTER_LINEAR
	node.z_as_relative = false
	node.z_index = depth
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	node.material = add
	add_child(node)
	return node

func _pose(node: Sprite2D, origin: Vector2, span: Vector2, angle: float, alpha: float) -> void:
	node.visible = alpha > .003
	if not node.visible: return
	node.position = origin
	node.rotation = angle
	node.scale = span / (node.region_rect.size if node.region_enabled else node.texture.get_size())
	node.self_modulate.a = clampf(alpha, 0, 1)

func _unfold(node: Sprite2D, amount: float, burned: float, heat: float) -> void:
	var paint := node.material as ShaderMaterial
	paint.set_shader_parameter("unfolding", amount)
	paint.set_shader_parameter("consumed", burned)
	paint.set_shader_parameter("heat", heat)

func pose_at(t: float, grip: Vector2, tip: Vector2, contact: Vector2, impact_axis: Vector2) -> void:
	visible = t >= 3.005 and t < HIT + .85
	if not visible: return
	var age := t - HIT
	var before := age < 0
	var socket := tip if before else contact
	var axis := grip.direction_to(tip) if before else impact_axis.normalized()
	var angle := axis.angle()
	var hot := smoothstep(3.01, 3.22, t)
	var stretch := smoothstep(3.13, 3.29, t)
	var length := lerpf(24, 147, stretch)
	var release := 1.0 - smoothstep(.008, .15, age)
	_pose(_jet, socket, Vector2(length, 7 + 25*stretch) * lerpf(.38,1,release), angle, hot*release)
	_pose(_fringe, socket, Vector2(length*.77, -10-21*stretch), angle+.048, .62*hot*release)
	_pose(_point, socket, Vector2(8+21*stretch, 5+5*stretch), angle, hot*release*.95)
	# The flare grows out along the incoming shaft after contact. Its tail at full extent
	# is shorter than the gap from the hit to the forward hand.
	var blow := smoothstep(0,.045,age)
	_pose(_spur, contact, Vector2(35+88*blow,9+10*blow), angle-.045,
		float(not before)*(1.0-smoothstep(.062,.188,age)))
	_pose(_split, contact, Vector2(15+17*blow,6+5*blow),angle-.59,
		float(not before)*(1.0-smoothstep(.024,.107,age)))
	var flash := 1.0-smoothstep(.012,.28,age)
	_pose(_heart, contact, Vector2(34+21*blow,21+13*blow), angle, flash if not before else 0.0)

	var bud := smoothstep(0, .087, age)
	_pose(_bud, contact, Vector2(11+62*bud,10+51*bud),angle+.11-.19*bud,
		float(not before) * (1.0-smoothstep(.085,.205,age)))
	_unfold(_bud, .21+bud, smoothstep(.11,.24,age)*.9, flash)

	var opening := smoothstep(.036,.245,age)
	var fade := 1.0-smoothstep(.30,.62,age)
	var lip := smoothstep(.065,.32,age)
	var furl := smoothstep(.21,.61,age)
	# As the back petals curl upward, the near lip tips down and out towards
	# the viewer. Both rotate around the same fixed, luminous attachment.
	_pose(_crown,contact,Vector2(37+202*opening-12*furl,23+123*opening+9*furl),angle+.08-.12*opening-.09*furl,
		smoothstep(.028,.088,age)*fade)
	_pose(_lip,contact,Vector2(44+184*lip+18*furl,21+119*lip-17*furl),angle+.12-.14*lip+.115*furl,
		smoothstep(.055,.110,age)*(1.0-smoothstep(.34,.67,age)))
	_unfold(_crown, .035+.95*opening, smoothstep(.29,.61,age)*1.05, 1.0-smoothstep(.21,.48,age))
	_unfold(_lip, .025+.95*lip, smoothstep(.33,.66,age)*1.02, 1.0-smoothstep(.23,.51,age))
	_release_petals(age, contact, angle)

func _release_petals(age: float, origin: Vector2, angle: float) -> void:
	# Each petal leaves the calyx edge along the tilt of a particular lobe.
	# Faster, fine golden embers escape first; heavier red petals turn over and fall.
	const ANGLES := [-2.17,-1.62,-1.04,-.59,-.21,.22]
	const RIM := [48,62,80,99,107,71]
	const REACH := [108,135,170,190,200,140]
	for i in _petals.size():
		var delay := .177 + .025 * (i%3)
		var phase := clampf((age-delay)/(.46 + .039*(i%3)), 0, 1)
		var ray := Vector2.from_angle(angle + ANGLES[i])
		var at := origin + ray*lerpf(RIM[i],REACH[i],1.0-pow(1.0-phase,1.75))
		at += Vector2(18*phase*phase, 62*phase*phase)
		var edge := .30+.70*absf(cos(PI*(phase*1.12+.043*(i%2))))
		var size := (21.0+4.4*(i%4)) * (1.0-.27*phase)
		_pose(_petals[i],at,Vector2(size,size*(.24+.56*edge)),ray.angle()+.52+phase*(1.05 if i%2 else -1.20),
			smoothstep(delay,delay+.067,age)*(1.0-smoothstep(.62,1.0,phase)))
	for i in _embers.size():
		var delay := .008+.012*(i%4)
		var phase := clampf((age-delay)/(.25+.022*i),0,1)
		var ray := Vector2.from_angle(angle - 2.80 + .43*i)
		var at: Vector2 = origin + ray*((34+11*i)*(1.0-pow(1.0-phase,2.5))) + Vector2(0,26*phase*phase)
		var size := (6.0+1.6*(i%4))*(1.0-.70*phase)
		_pose(_embers[i],at,Vector2(size,maxf(1.3,size*.21)),ray.angle(),
			smoothstep(delay,delay+.035,age)*(1.0-smoothstep(.36,1.0,phase)))
