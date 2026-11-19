extends Node2D
## One clock drives the editable pose, grounded travel and world-space paint.
const Footwork = preload("res://scripts/studies/nezha_footwork.gd")
const DESIGN_SIZE := Vector2(1280,720)
const HOME_FOOT := Vector2(505,510)
const CYCLE := 4.80
const CONTACT := 1.84
const TRAIL_START := 1.50
const TRAIL_STEP := 1.0 / 60.0

@onready var stage: Node2D = $Stage
@onready var actor: Node2D = $Stage/Actor
@onready var rig = $Stage/Actor/Rig
@onready var ribbons = $Stage/Actor/Ribbons
@onready var spear_fx = $Stage/SpearFX
@onready var shadow: Node2D = $Stage/Shadow
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

func _ready() -> void:
	reel = "--nezha-study-reel" in OS.get_cmdline_user_args()
	controls.visible = not reel
	effects_button.button_pressed = effects_enabled
	effects_button.toggled.connect(_set_effects)
	pause_button.pressed.connect(_toggle_pause)
	$Stage/Controls/Buttons/Replay.pressed.connect(_replay)
	shadow.draw.connect(_paint_shadow)
	get_viewport().size_changed.connect(_fit_stage)
	_fit_stage()
	_bake_thrust_path()
	seek(0)

func _fit_stage() -> void:
	var available := get_viewport_rect().size
	var zoom := minf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y)
	stage.scale = Vector2.ONE * zoom
	stage.position = (available - DESIGN_SIZE * zoom) * .5

func _process(delta: float) -> void:
	if playing:
		seek(seconds + delta)

func _apply_body(t: float) -> void:
	actor.position = HOME_FOOT + Footwork.displacement_at(t)
	rig.pose_at(t)

func _bake_thrust_path() -> void:
	# Sample the actual articulated weapon in stage space, including the root's lunge.
	for step in range(ceili((CONTACT - TRAIL_START) / TRAIL_STEP) + 1):
		_apply_body(minf(TRAIL_START + step * TRAIL_STEP, CONTACT))
		tip_path.append(actor.transform * Vector2(rig.weapon_tip()))

func _tip_on_path(t: float) -> Vector2:
	var elapsed := clampf(t, TRAIL_START, CONTACT) - TRAIL_START
	var index := mini(floori(elapsed / TRAIL_STEP), tip_path.size() - 2)
	# The contact drawing falls between fixed ticks. Interpolate the last, shorter interval.
	var start := index * TRAIL_STEP
	var stop := minf(start + TRAIL_STEP, CONTACT - TRAIL_START)
	return tip_path[index].lerp(tip_path[index + 1], clampf((elapsed-start)/(stop-start),0,1))

func seek(t: float) -> void:
	# A 60 Hz accumulator can arrive a few picoseconds before the loop boundary.
	var seam := snappedf(t,CYCLE)
	if absf(t-seam) < .00000001: t = seam
	seconds = fposmod(t,CYCLE*2.0 if reel else CYCLE)
	pose_time = fposmod(seconds,CYCLE)
	_apply_body(pose_time)
	ribbons.pose_at(pose_time,rig)
	soles = PackedVector2Array([rig.rear_sole(),rig.front_sole()])
	shadow.queue_redraw()
	spear_fx.visible = seconds >= CYCLE if reel else effects_enabled
	if not spear_fx.visible: return
	var intensity := smoothstep(1.46,1.80,pose_time) * (1.0-smoothstep(1.90,2.09,pose_time))
	var history := PackedVector2Array()
	if intensity > 0:
		var end := minf(pose_time,CONTACT)
		for i in range(4,-1,-1):
			history.append(_tip_on_path(end - i*TRAIL_STEP))
	var grip: Vector2 = actor.transform * Vector2(rig.weapon_grip())
	var tip: Vector2 = actor.transform * Vector2(rig.weapon_tip())
	spear_fx.set_sample(grip,tip,history,intensity,tip_path[-1],pose_time-CONTACT)

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
