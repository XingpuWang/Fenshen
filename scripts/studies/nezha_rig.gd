@tool
extends Node2D
## The artist keys the turn of the pelvis, chest, gaze and spear separately.
## Angles around the standing axis select painted views and project the two arms.
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
	_draw_turnaround()
	_place_spear_and_arms()
	var feet := Footwork.sole_goals_at(time, _stage_scale)
	var hips_angle := deg_to_rad(hip_turn)
	var pelvis_x := 12.0 * cos(hips_angle)
	for i in 2:
		var chain: Array = legs[i]
		var upper: Bone2D = chain[0]
		upper.position.x = -pelvis_x if i == 0 else pelvis_x
		var goal: Marker2D = chain[3]
		var sole: Marker2D = chain[4]
		goal.position = feet[i]
		var lift := maxf(0, -feet[i].y)
		goal.rotation = deg_to_rad(clampf(lift*.60,0,11)) * (-1.0 if i==1 else 1.0)
		# Soles stay on their appointed floor point even as the toe pivots round.
		var shoe: Sprite2D = chain[2].get_node("Shoe")
		var forward := cos(hips_angle + (.08 if i == 0 else -.08))
		var shoe_factor := (1.0 if forward >= 0 else -1.0) * lerpf(.55,1.0,absf(forward))
		var end_view := absf(forward) < .52
		shoe.visible = not end_view
		chain[2].get_node("Heel").visible = end_view and sin(hips_angle) >= 0
		chain[2].get_node("Toe").visible = end_view and sin(hips_angle) < 0
		shoe.scale.x = .137 * shoe_factor
		shoe.position.x = sole.position.x*(1.0-shoe_factor)
		var ankle := goal.position - sole.position.rotated(goal.rotation)
		_solve_leg(chain, ankle, goal.rotation, forward)

func _view(yaw: float, head_part: bool, belt_part := false) -> StringName:
	var depth := sin(deg_to_rad(yaw))
	if depth > .87: return &"Back"
	if head_part and depth > .57: return &"BackQuarter"
	if depth > .54 and not head_part: return &"Back"
	if depth > .22: return &"Side"
	if depth < -.76 and not belt_part: return &"Front"
	return &"ThreeQuarter"

func _direction_group(group: Node2D, view: StringName, sideways: float) -> void:
	for child in group.get_children():
		child.visible = child.name == view
	group.scale.x = 1.0 if view in [&"Front", &"Back"] else sideways

func _draw_turnaround() -> void:
	var yaw := deg_to_rad(chest_turn)
	var hip_yaw := deg_to_rad(hip_turn)
	var face_yaw := deg_to_rad(face_turn)
	var front_sign := 1.0 if cos(yaw)>=0 else -1.0
	_direction_group(costume,_view(chest_turn,false),front_sign)
	_direction_group(belt,_view(hip_turn,false,true),1.0 if cos(hip_yaw)>=0 else -1.0)
	var look := _view(face_turn,true)
	var face_sign := 1.0 if cos(face_yaw)>=0 else -1.0
	portrait.visible = look == &"ThreeQuarter"
	portrait.scale.x = face_sign
	_direction_group(head_views,look,face_sign)
	# The shoulder socket follows the painted armhole, including on the back view.
	var side_offset := 20.0*sin(yaw+.91)
	var depth := cos(yaw+.91)
	arms[0][0].position = Vector2(-side_offset,-43.0+1.5*depth)
	arms[1][0].position = Vector2(side_offset,-43.0-1.5*depth)
	head.position.x = 2.5*cos(face_yaw) + 1.5*sin(yaw)
	$Skeleton/Pelvis/Chest/SilkRoot.position = Vector2(-side_offset, -46)
	$Skeleton/Pelvis/HemRoot.position.x = -14.0*cos(hip_yaw)+6.0*sin(hip_yaw)
	$Skeleton/Pelvis/Chest/Head/HairTie.position.x = -14.0*cos(face_yaw)-6.0*sin(face_yaw)

func _place_spear_and_arms() -> void:
	var yaw := deg_to_rad(spear_turn)
	# The shaft describes an ellipse in depth. A spear aimed at the far rank
	# foreshortens and passes behind the body without collapsing into one pixel.
	var axis := Vector2(cos(yaw), cos(yaw)*tan(deg_to_rad(spear_pitch))-.31*sin(yaw))
	var flip := 1.0 if axis.x >= 0 else -1.0
	var hand_angle := (axis*flip).angle()
	var direction := axis.angle()
	# The grip passes across the front of his ribs. When the camera sees his
	# back, the tunic must mask the middle of the pole and both palms.
	var back_to_camera := sin(deg_to_rad(chest_turn)) > .50
	var outside := sin(yaw) < .46 and not back_to_camera
	var near_front := cos(deg_to_rad(chest_turn)+.91) >= 0
	var half_span := grip_spacing * .5
	var center := hand_line
	# Both palms share one rigid handle. If a view change brings an arm to its
	# limit, slide the whole handle into the intersection of the two reach arcs.
	for pass_index in 5:
		for i in 2:
			var chain: Array = arms[i]
			var hold: Marker2D = chain[4]
			var offset := axis * (-half_span if i == 0 else half_span)
			offset -= Vector2(hold.position.x*flip,hold.position.y).rotated(hand_angle)
			var shoulder := to_local((chain[0] as Bone2D).global_position)
			var ray := center+offset-shoulder
			var radius := ray.length()
			var resolved := clampf(radius, 29.0, 62.8)
			if absf(radius-resolved)>.0001 and radius>.001:
				center += ray*(resolved/radius-1.0)
	pole.position = center - axis*half_span
	pole.rotation = direction
	pole.scale = Vector2(axis.length(), flip)
	$Skeleton/Spear/FrontGrip.position.x = grip_spacing
	var weapon_layer := 10 if outside else -4
	$Skeleton/Spear/FireTip.z_index = weapon_layer
	for i in 2:
		var chain: Array = arms[i]
		var upper: Bone2D = chain[0]
		var joint: Bone2D = chain[1]
		var wrist: Bone2D = chain[2]
		var target := to_local((chain[3] as Marker2D).global_position)
		var grip_offset: Vector2 = (chain[4] as Marker2D).position
		var wrist_at := target - Vector2(grip_offset.x*flip,grip_offset.y).rotated(hand_angle)
		var is_front: bool = near_front if i==0 else not near_front
		# The elbow passes smoothly fore/aft as it sweeps around the ribcage.
		var arm_yaw := deg_to_rad(chest_turn)
		var bend := .78+.16*cos(arm_yaw+.32) if i==0 else .72+.14*cos(arm_yaw-.25)
		_solve_arm(chain, wrist_at, hand_angle, bend)
		var hand_art := wrist.get_node("HandArt") as Node2D
		hand_art.scale.x=flip
		upper.get_node("UpperArt").z_index = 6 if is_front else 1
		joint.get_node("LowerArt").z_index = 7 if is_front and outside else 2
		var guard := upper.get_node("Guard") as Sprite2D
		guard.z_index = 8 if is_front else 2
		# The cap hangs off the shoulder, rolling only slightly as the humerus lifts.
		guard.rotation = -upper.rotation + .18*wrapf(upper.rotation,-PI,PI)
		guard.flip_h = cos(deg_to_rad(chest_turn))<0
		hand_art.get_node("Palm").z_index = weapon_layer-1
		hand_art.get_node("Fingers").z_index = weapon_layer+1
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
	var elbow := start+axis*along+Vector2(-axis.y,axis.x)*across*bend
	var upper_length := start.distance_to(elbow)
	var lower_length := elbow.distance_to(target)
	lower.position.y = upper_length
	end.position.y = lower_length
	upper.get_node("UpperArt").scale.y = upper_length/UPPER_LENGTH
	lower.get_node("LowerArt").scale.y = lower_length/FORE_LENGTH
	_orient_chain(upper,lower,end,start,elbow,target,hand_angle)

func _solve_leg(chain: Array,target: Vector2,foot_angle: float,forward: float) -> void:
	var upper: Bone2D=chain[0]
	var lower: Bone2D=chain[1]
	var end: Bone2D=chain[2]
	var start:=to_local(upper.global_position)
	var ray:=target-start
	var a:=48.0
	var b:=45.0
	var distance:=maxf(.001, ray.length())
	var axis:=ray/distance
	var along:=(a*a+distance*distance-b*b)/(2.0*distance)
	# Project the bent knee into and out of depth as the hips pivot. Changing
	# just the elbow sign would pop the kneecap across the body in one frame.
	var elbow:=start+axis*along-Vector2(-axis.y,axis.x)*sqrt(maxf(0.0,a*a-along*along))*forward
	var upper_length:=start.distance_to(elbow)
	var lower_length:=elbow.distance_to(target)
	lower.position.y=upper_length
	end.position.y=lower_length
	upper.get_node("UpperArt").scale.y=upper_length/a
	lower.get_node("LowerArt").scale.y=lower_length/b
	_orient_chain(upper,lower,end,start,elbow,target,foot_angle)

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
