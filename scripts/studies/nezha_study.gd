extends Node2D
## One clock drives the editable pose, grounded travel and world-space paint.
const Footwork = preload("res://scripts/studies/nezha_footwork.gd")
const BronzeReflection = preload("res://shaders/nezha_bronze_reflection.gdshader")
const Costume = preload("res://scripts/studies/nezha_costume.gd")
const DESIGN_SIZE := Vector2(1280,720)
const HOME_FOOT := Vector2(505,510)
const CYCLE := 6.40
const CONTACT := 3.30
const TRAIL_START := 1.08
const TRAIL_STEP := 1.0 / 60.0
const AUDIO_START := .52

@onready var stage: Node2D = $Stage
@onready var actor: Node2D = $Stage/Actor
@onready var rig = $Stage/Actor/Rig
@onready var ribbons = $Stage/Actor/Ribbons
@onready var spear_fx = $Stage/SpearFX
@onready var shadow: Node2D = $Stage/Shadow
@onready var arena_light: ShaderMaterial = $Stage/PaintedArena.material
@onready var fire_audio: AudioStreamPlayer = $Stage/FireAudio
@onready var controls: Control = $Stage/Controls
@onready var pause_button: Button = $Stage/Controls/Buttons/Pause
@onready var effects_button: Button = $Stage/Controls/Buttons/Effects

var playing := true
var effects_enabled := true
var seconds := 0.0
var reel := false
var tip_path := PackedVector2Array()
var soles := PackedVector2Array()
var pose_time := 0.0
var bronze := ShaderMaterial.new()
var costume := Costume.new()

func _ready() -> void:
	reel = "--nezha-study-reel" in OS.get_cmdline_user_args()
	rig.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	controls.visible = not reel
	effects_button.button_pressed = effects_enabled
	effects_button.toggled.connect(_set_effects)
	pause_button.pressed.connect(_toggle_pause)
	$Stage/Controls/Buttons/Replay.pressed.connect(_replay)
	shadow.draw.connect(_paint_shadow)
	get_viewport().size_changed.connect(_fit_stage)
	_fit_stage()
	bronze.shader = BronzeReflection
	for part in rig.find_children("Guard","Sprite2D",true,false) + rig.find_children("Vambrace","Sprite2D",true,false):
		part.material = bronze
	rig.get_node("Skeleton/Spear/FireTip").material = bronze
	costume.bind(rig)
	_bake_motion()
	seek(0)

func _fit_stage() -> void:
	var available := get_viewport_rect().size
	var zoom := minf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y)
	stage.scale = Vector2.ONE * zoom
	stage.position = (available - DESIGN_SIZE * zoom) * .5

func _process(delta: float) -> void:
	if playing:
		seek(seconds + delta, false)

func _apply_body(t: float) -> void:
	actor.position = HOME_FOOT + Footwork.displacement_at(t)
	rig.pose_at(t, absf(actor.scale.x))

func _bake_motion() -> void:
	# A single walk through the authored poses gives the cloth its inertia and
	# records the blade in stage space. Scrubbing, replays and playback share it.
	for frame in roundi(CYCLE / TRAIL_STEP):
		var t := frame * TRAIL_STEP
		_apply_body(t)
		ribbons.record_anchor_sample(frame, rig)
		var waist: Vector2 = rig.to_local(rig.pelvis.global_position) + (actor.position-HOME_FOOT)/actor.scale.x
		costume.record_hip(waist, deg_to_rad(rig.hip_turn))
		if frame <= roundi(CONTACT / TRAIL_STEP):
			tip_path.append(actor.transform * Vector2(rig.weapon_tip()))

func _tip_on_path(t: float) -> Vector2:
	var frame := clampf(t / TRAIL_STEP,0,tip_path.size()-1)
	var first := floori(frame)
	return tip_path[first].lerp(tip_path[mini(first+1,tip_path.size()-1)],frame-first)

func seek(t: float, resync_audio: bool = true) -> void:
	# A 60 Hz accumulator can arrive a few picoseconds before the loop boundary.
	var seam := snappedf(t,CYCLE)
	if absf(t-seam) < .00000001: t = seam
	seconds = fposmod(t,CYCLE*2.0 if reel else CYCLE)
	pose_time = fposmod(seconds,CYCLE)
	_apply_body(pose_time)
	costume.pose_at(pose_time,rig)
	ribbons.pose_at(pose_time,rig)
	soles = PackedVector2Array([rig.rear_sole(),rig.front_sole()])
	shadow.queue_redraw()
	spear_fx.visible = seconds < CYCLE if reel else effects_enabled
	_sound_at(pose_time, resync_audio)
	_light_stage(pose_time if spear_fx.visible else 0.0)
	if not spear_fx.visible: return
	var history := PackedVector2Array()
	if pose_time > TRAIL_START and pose_time < CONTACT + .25:
		var end := minf(pose_time,CONTACT)
		for i in range(39,-1,-1):
			history.append(_tip_on_path(end - i*TRAIL_STEP))
	var grip: Vector2 = actor.transform * Vector2(rig.weapon_grip())
	var tip: Vector2 = actor.transform * Vector2(rig.weapon_tip())
	spear_fx.set_choreography(pose_time,actor.position,grip,tip,tip_path[-1],history)

func _sound_at(t: float, resync: bool) -> void:
	var offset := t - AUDIO_START
	if not playing or not spear_fx.visible or offset < 0 or offset >= fire_audio.stream.get_length():
		if fire_audio.playing:
			fire_audio.stop()
	elif not fire_audio.playing:
		fire_audio.play(offset)
	elif resync:
		fire_audio.seek(offset)

func _light_stage(t: float) -> void:
	var dusk := (.43*smoothstep(.49,1.16,t) + .47*smoothstep(2.24,2.98,t)) * (1.0-smoothstep(3.44,4.22,t))
	var first := smoothstep(1.17,1.51,t) * (1.0-smoothstep(1.53,1.81,t))
	var second := smoothstep(1.80,2.11,t) * (1.0-smoothstep(2.13,2.49,t))
	var landing := smoothstep(3.18,CONTACT,t) * (1.0-smoothstep(3.37,3.92,t))
	bronze.set_shader_parameter("strength",maxf(.62*first,maxf(.75*second,landing)))
	bronze.set_shader_parameter("light_side",1.0-2.0*first)
	arena_light.set_shader_parameter("dusk",dusk)
	arena_light.set_shader_parameter("sweep_glow",.68*first + second)
	arena_light.set_shader_parameter("strike_glow",landing)
	arena_light.set_shader_parameter("caster_ground",actor.position)
	arena_light.set_shader_parameter("strike_ground",Vector2(tip_path[-1].x, HOME_FOOT.y + Footwork.displacement_at(CONTACT).y))

func _paint_shadow() -> void:
	Footwork.draw_shadow(shadow,HOME_FOOT,pose_time,actor.scale.x,soles)

func _set_effects(enabled: bool) -> void:
	effects_enabled = enabled
	effects_button.set_pressed_no_signal(enabled)
	effects_button.text = "特效 开" if enabled else "特效 关"
	seek(seconds)

func _toggle_pause() -> void:
	playing = not playing
	pause_button.text = "暂停" if playing else "继续"
	_sound_at(pose_time, true)

func _replay() -> void:
	playing = true
	pause_button.text = "暂停"
	seek(0)

func _unhandled_key_input(event: InputEvent) -> void:
	if reel or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_R: _replay()
		KEY_SPACE: _toggle_pause()
		KEY_F: _set_effects(not effects_enabled)
		_: return
	get_viewport().set_input_as_handled()
