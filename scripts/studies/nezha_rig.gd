@tool
extends Node2D
## A continuous right-facing guard. Separate body, clavicle and spear keys
## shape the two-handed low cut, rising cut and direct thrust.
const Footwork = preload("res://scripts/studies/nezha_footwork.gd")
const LOOP_SECONDS := 6.4
const STROKE := &"fire_sweep"
const UPPER_LENGTH := 34.0
const FORE_LENGTH := 32.0
const DEFAULT_STAGE_SCALE := 0.84

@export_group("Turn around the standing axis (degrees)")
@export var hip_turn := 0.0
@export var chest_turn := 0.0
@export var face_turn := 0.0
@export var spear_turn := 0.0
@export var spear_pitch := -27.0
## Protraction and lift of the leading clavicle, in model units.
@export var shoulder_drive := Vector2(-1, -.5)
@export_group("Hands")
@export var hand_line := Vector2(15, -102)
@export var grip_spacing := 51.0

@onready var player: AnimationPlayer = $ActionPlayer
@onready var pelvis: Bone2D = $Skeleton/Pelvis
@onready var chest: Bone2D = $Skeleton/Pelvis/Chest
@onready var head: Bone2D = $Skeleton/Pelvis/Chest/Head
@onready var pole: Bone2D = $Skeleton/Spear
@onready var costume: Node2D = $Skeleton/Pelvis/Chest/RobeViews
@onready var belt: Node2D = $Skeleton/Pelvis/BeltViews
@onready var portrait: Node2D = $Skeleton/Pelvis/Chest/Head/Portrait
@onready var head_views: Node2D = $Skeleton/Pelvis/Chest/Head/TurnViews
@onready var rear_hand: Bone2D = $Skeleton/Pelvis/Chest/NearArm/Forearm/Hand
@onready var lead_hand: Bone2D = $Skeleton/Pelvis/Chest/FarArm/Forearm/Hand
@onready var arms: Array = [
	[$Skeleton/Pelvis/Chest/NearArm, $Skeleton/Pelvis/Chest/NearArm/Forearm,
	rear_hand, $Skeleton/Spear/RearGrip, rear_hand.get_node("HandArt/Hold")],
	[$Skeleton/Pelvis/Chest/FarArm, $Skeleton/Pelvis/Chest/FarArm/Forearm,
	lead_hand, $Skeleton/Spear/FrontGrip, lead_hand.get_node("HandArt/Hold")],
]
@onready var legs: Array = [
	[$Skeleton/Pelvis/RearLeg, $Skeleton/Pelvis/RearLeg/Shin, $Skeleton/Pelvis/RearLeg/Shin/Boot,
	$FootGoals/Rear, $Skeleton/Pelvis/RearLeg/Shin/Boot/Sole],
	[$Skeleton/Pelvis/FrontLeg, $Skeleton/Pelvis/FrontLeg/Shin, $Skeleton/Pelvis/FrontLeg/Shin/Boot,
	$FootGoals/Front, $Skeleton/Pelvis/FrontLeg/Shin/Boot/Sole],
]
var _stage_scale := DEFAULT_STAGE_SCALE

func _ready() -> void:
	player.play(STROKE)
	player.pause()
	pose_at(0)
	set_process(Engine.is_editor_hint())

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and is_node_ready():
		_apply_pose(player.current_animation_position)

func pose_at(seconds: float, stage_scale := DEFAULT_STAGE_SCALE) -> void:
	if not is_node_ready(): return
	_stage_scale = maxf(.001, absf(stage_scale))
	var time := fposmod(seconds, LOOP_SECONDS)
	player.seek(time, true)
	_apply_pose(time)

func _apply_pose(time: float) -> void:
	var feet := Footwork.sole_goals_at(time, _stage_scale)
	var ankles := PackedVector2Array()
	var minimum_hip_y := -INF
	var hip_sine := sin(deg_to_rad(hip_turn))
	for i in 2:
		var chain: Array = legs[i]
		var upper: Bone2D = chain[0]
		var goal: Marker2D = chain[3]
		var sole: Marker2D = chain[4]
		# Both sockets stay under the same three-quarter waistband. Turning the
		# ribs does not reverse the direction a planted knee or toe can travel.
		upper.position = Vector2(-10.5 + hip_sine * 2, -2.5) if i == 0 else Vector2(10.5 + hip_sine * 2, 1.5)
		goal.position = feet[i]
		goal.rotation = Footwork.sole_rotation_at(time, i)
		var ankle := goal.position - sole.position.rotated(goal.rotation)
		ankles.append(ankle)
		var lateral := ankle.x - (pelvis.position.x + upper.position.x)
		var shin: Bone2D = chain[1]
		var reach := upper.get_length() + shin.get_length() - .9
		var drop := sqrt(maxf(0, reach * reach - lateral * lateral))
		minimum_hip_y = maxf(minimum_hip_y, ankle.y - upper.position.y - drop)
	pelvis.position.y = maxf(pelvis.position.y, minimum_hip_y)
	_pose_upper_body()
	_place_spear_and_arms()
	for i in 2:
		var chain: Array = legs[i]
		var goal: Marker2D = chain[3]
		_solve_leg(chain, ankles[i], goal.rotation)
		chain[0].get_node("UpperArt").refresh_pose()

func _pose_upper_body() -> void:
	var chest_yaw := deg_to_rad(chest_turn)
	var hip_yaw := deg_to_rad(hip_turn)
	var gaze := deg_to_rad(face_turn)
	# Both armholes belong to the same right-facing painting. The far shoulder
	# moves out from the ribs to lead each cut, while the rear arm sends the haft.
	var shoulder_span := 16.0 + 6.0*sin(chest_yaw)
	var clavicle_lift := 1.8*cos(chest_yaw)
	arms[0][0].position = Vector2(-shoulder_span,-43.0+clavicle_lift) - shoulder_drive*.57
	arms[1][0].position = Vector2(shoulder_span,-43.0-clavicle_lift) + shoulder_drive*.82
	head.position.x = 2.8 + 3.5*sin(gaze) + 1.3*sin(chest_yaw)
	$Skeleton/Pelvis/Chest/SilkRoot.position = Vector2(-shoulder_span,-45) - shoulder_drive*.43
	$Skeleton/Pelvis/HemRoot.position.x = -14.0*cos(hip_yaw) + 6.0*sin(hip_yaw)
	$Skeleton/Pelvis/Chest/Head/HairTie.position.x = -14.0*cos(gaze) - 6.0*sin(gaze)

func _place_spear_and_arms() -> void:
	var yaw := deg_to_rad(spear_turn)
	# Project elevation and depth separately so a low cut can cross the
	# downstage lane and an uppercut can rise on the target side.
	var pitch := deg_to_rad(spear_pitch)
	var axis := Vector2(cos(yaw)*cos(pitch), sin(pitch)-.31*sin(yaw)*cos(pitch))
	var direction := axis.angle()
	# A power grip at the butt and an underhand guiding grip roll independently.
	# Each palm still closes around its own exact point on the single handle.
	var hand_angles := Vector2(
		direction + .08 + .17*sin(pitch) + .13*sin(deg_to_rad(chest_turn)),
		direction - .09 - .22*sin(pitch)
	)
	var half_span := grip_spacing * .5
	var center := hand_line
	# Keep both palms on the same haft as their distance along it changes.
	for pass_index in 5:
		for i in 2:
			var chain: Array = arms[i]
			var hold: Marker2D = chain[4]
			var offset := axis * (-half_span if i == 0 else half_span)
			offset -= hold.position.rotated(hand_angles[i])
			var shoulder := to_local((chain[0] as Bone2D).global_position)
			var ray := center+offset-shoulder
			var radius := ray.length()
			var resolved := clampf(radius, 18.5, 62.8)
			if absf(radius-resolved)>.0001 and radius>.001:
				center += ray*(resolved/radius-1.0)
	pole.position = center - axis*half_span
	pole.rotation = direction
	pole.scale = Vector2(axis.length(), 1.0)
	$Skeleton/Spear/FrontGrip.position.x = grip_spacing
	for i in 2:
		var chain: Array = arms[i]
		var upper: Bone2D = chain[0]
		var joint: Bone2D = chain[1]
		var wrist: Bone2D = chain[2]
		var target := to_local((chain[3] as Marker2D).global_position)
		var grip_offset: Vector2 = (chain[4] as Marker2D).position
		var hand_angle := hand_angles[i]
		var wrist_at := target - grip_offset.rotated(hand_angle)
		var is_front := i == 0
		# The driving elbow drops under the shaft. The leading elbow stays
		# on the other side of the handle, open towards the outside shoulder.
		var arm_yaw := deg_to_rad(chest_turn)
		var bend := .78+.16*cos(arm_yaw+.32) if i==0 else -.62-.18*sin(arm_yaw)
		_solve_arm(chain, wrist_at, hand_angle, bend)
		var hand_art := wrist.get_node("HandArt") as Node2D
		upper.get_node("UpperArt").z_index = 6 if is_front else 1
		joint.get_node("LowerArt").z_index = 7 if is_front else 4
		var guard := upper.get_node("Guard") as Sprite2D
		guard.z_index = 8 if is_front else 2
		# The cap hangs off the shoulder, rolling only slightly as the humerus lifts.
		guard.rotation = -upper.rotation + .24*sin(upper.rotation) + shoulder_drive.y*.012
		hand_art.get_node("Palm").z_index = 9
		hand_art.get_node("Fingers").z_index = 11
		hand_art.modulate = Color.WHITE if is_front else Color(.96,.93,.92,1)

func _solve_arm(chain: Array, target: Vector2, hand_angle: float, bend: float) -> void:
	var upper: Bone2D=chain[0]
	var lower: Bone2D=chain[1]
	var end: Bone2D=chain[2]
	var start := to_local(upper.global_position)
	var ray := target-start
	var distance := maxf(.001,ray.length())
	var axis := ray/distance
	var along := (UPPER_LENGTH*UPPER_LENGTH + distance*distance - FORE_LENGTH*FORE_LENGTH)/(2*distance)
	var across := sqrt(maxf(0.0, UPPER_LENGTH*UPPER_LENGTH-along*along))
	var radial := Vector2(-axis.y,axis.x) * bend
	var elbow := start + axis*along + radial*across
	var upper_length := start.distance_to(elbow)
	var lower_length := elbow.distance_to(target)
	lower.position.y = upper_length
	end.position.y = lower_length
	upper.get_node("UpperArt").scale.y = upper_length/UPPER_LENGTH
	lower.get_node("LowerArt").scale.y = lower_length/FORE_LENGTH
	_orient_chain(upper,lower,end,start,elbow,target,hand_angle)

func _solve_leg(chain: Array, target: Vector2, foot_angle: float) -> void:
	var upper: Bone2D = chain[0]
	var shin: Bone2D = chain[1]
	var boot: Bone2D = chain[2]
	var hip := to_local(upper.global_position)
	var ray := target - hip
	var distance := maxf(.001, ray.length())
	var axis := ray / distance
	var along := (upper.get_length() * upper.get_length() + distance * distance - shin.get_length() * shin.get_length()) / (2.0 * distance)
	var across := sqrt(maxf(0, upper.get_length() * upper.get_length() - along * along))
	var knee := hip + axis * along + Vector2(axis.y, -axis.x) * across
	_orient_chain(upper, shin, boot, hip, knee, target, foot_angle)

func _orient_chain(upper: Bone2D,lower: Bone2D,end: Bone2D,start: Vector2,elbow: Vector2,target: Vector2,end_angle: float) -> void:
	var parent_bone := upper.get_parent() as Node2D
	var base_angle := (global_transform.affine_inverse()*parent_bone.global_transform).get_rotation()
	var upper_angle:= (elbow-start).angle()-PI/2
	var lower_angle:= (target-elbow).angle()-PI/2
	upper.rotation=wrapf(upper_angle-base_angle,-PI,PI)
	lower.rotation=wrapf(lower_angle-upper_angle,-PI,PI)
	end.rotation=wrapf(end_angle-lower_angle,-PI,PI)

func weapon_tip() -> Vector2:
	return to_local($Skeleton/Spear/Tip.global_position)

func weapon_grip() -> Vector2:
	return to_local($Skeleton/Spear/RearGrip.global_position)

func cloth_anchor() -> Vector2:
	return to_local($Skeleton/Pelvis/Chest/SilkRoot.global_position)

func hair_anchor() -> Vector2:
	return to_local($Skeleton/Pelvis/Chest/Head/HairTie.global_position)

func hem_anchor() -> Vector2:
	return to_local($Skeleton/Pelvis/HemRoot.global_position)

func rear_sole() -> Vector2:
	return to_local($Skeleton/Pelvis/RearLeg/Shin/Boot/Sole.global_position)

func front_sole() -> Vector2:
	return to_local($Skeleton/Pelvis/FrontLeg/Shin/Boot/Sole.global_position)
