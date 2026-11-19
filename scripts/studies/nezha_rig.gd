@tool
extends Node2D
## A two-handed cutout rig. The AnimationPlayer authors the weight shift, hands,
## weapon and foot goals. Two-bone chains close the grips and plant the boots.
const LOOP_SECONDS := 4.8
const STROKE := &"spear_study"
@onready var player: AnimationPlayer = $ActionPlayer
@onready var pelvis: Bone2D = $Skeleton/Pelvis
@onready var chest: Bone2D = $Skeleton/Pelvis/Chest
@onready var head: Bone2D = $Skeleton/Pelvis/Chest/Head
@onready var pole: Bone2D = $Skeleton/Spear

func _ready() -> void:
	player.play(STROKE)
	player.pause()
	pose_at(0.0)
	set_process(Engine.is_editor_hint())

func _process(_delta: float) -> void:
	# Keep the hand and foot constraints live when scrubbing in the editor.
	if Engine.is_editor_hint() and is_node_ready():
		_close_chains()

func pose_at(seconds: float) -> void:
	if not is_node_ready(): return
	player.seek(fposmod(seconds, LOOP_SECONDS), true)
	_close_chains()

func _close_chains() -> void:
	for limb in arms:
		var grip: Marker2D = limb[3]
		_solve(limb, to_local(grip.global_position), pole.rotation, 1.0)
	for limb in legs:
		var goal: Marker2D = limb[3]
		var sole: Marker2D = limb[4]
		_solve(limb, goal.position - sole.position.rotated(goal.rotation), goal.rotation, -1.0)

@onready var arms := [
	[$Skeleton/Pelvis/Chest/NearArm, $Skeleton/Pelvis/Chest/NearArm/Forearm,
	$Skeleton/Pelvis/Chest/NearArm/Forearm/Hand, $Skeleton/Spear/RearGrip],
	[$Skeleton/Pelvis/Chest/FarArm, $Skeleton/Pelvis/Chest/FarArm/Forearm,
	$Skeleton/Pelvis/Chest/FarArm/Forearm/Hand, $Skeleton/Spear/FrontGrip],
]
@onready var legs := [
	[$Skeleton/Pelvis/RearLeg, $Skeleton/Pelvis/RearLeg/Shin, $Skeleton/Pelvis/RearLeg/Shin/Boot,
	$FootGoals/Rear, $Skeleton/Pelvis/RearLeg/Shin/Boot/Sole],
	[$Skeleton/Pelvis/FrontLeg, $Skeleton/Pelvis/FrontLeg/Shin, $Skeleton/Pelvis/FrontLeg/Shin/Boot,
	$FootGoals/Front, $Skeleton/Pelvis/FrontLeg/Shin/Boot/Sole],
]

func _solve(chain: Array, target: Vector2, hand_angle: float, bend: float) -> void:
	var upper: Bone2D = chain[0]
	var lower: Bone2D = chain[1]
	var end: Bone2D = chain[2]
	var start := to_local(upper.global_position)
	var ray := target - start
	var a := lower.position.y
	var b := end.position.y
	var distance := clampf(ray.length(), absf(a - b) + .001, a + b - .001)
	var axis := ray.normalized()
	var along := (a*a + distance*distance - b*b)/(2.0*distance)
	var elbow := start + axis * along + Vector2(-axis.y, axis.x) * bend * sqrt(maxf(0.0, a*a - along*along))
	var parent_bone := upper.get_parent() as Node2D
	var base_angle := (global_transform.affine_inverse() * parent_bone.global_transform).get_rotation()
	var upper_angle := (elbow - start).angle() - PI/2
	var lower_angle := (start + axis * distance - elbow).angle() - PI/2
	upper.rotation = wrapf(upper_angle - base_angle, -PI, PI)
	lower.rotation = wrapf(lower_angle - upper_angle, -PI, PI)
	end.rotation = wrapf(hand_angle - lower_angle, -PI, PI)

func weapon_tip() -> Vector2:
	return to_local($Skeleton/Spear/Tip.global_position)

func weapon_grip() -> Vector2:
	return to_local($Skeleton/Spear/RearGrip.global_position)

func cloth_anchor() -> Vector2:
	return to_local($Skeleton/Pelvis/Chest/SilkRoot.global_position)

func hair_anchor() -> Vector2:
	return to_local($Skeleton/Pelvis/Chest/Head/NearBun/HairTie.global_position)

func hem_anchor() -> Vector2:
	return to_local($Skeleton/Pelvis/HemRoot.global_position)

func rear_sole() -> Vector2:
	return to_local($Skeleton/Pelvis/RearLeg/Shin/Boot/Sole.global_position)

func front_sole() -> Vector2:
	return to_local($Skeleton/Pelvis/FrontLeg/Shin/Boot/Sole.global_position)
