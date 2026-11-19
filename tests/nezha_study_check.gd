extends SceneTree

const Study = preload("res://scenes/studies/nezha_study.tscn")
var failures := PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition: failures.append(label)

func press_key(key: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = down
		root.push_input(event)

func sole_at(scene: Node2D, t: float, front: bool) -> Vector2:
	scene.seek(t)
	var point: Vector2 = scene.rig.front_sole() if front else scene.rig.rear_sole()
	return scene.actor.transform * point

func check_grips(scene: Node2D) -> void:
	var chest: Node2D = scene.rig.get_node("Skeleton/Pelvis/Chest")
	var spear: Node2D = scene.rig.get_node("Skeleton/Spear")
	for pair in [["NearArm","RearGrip"],["FarArm","FrontGrip"]]:
		var shoulder: Bone2D = chest.get_node(pair[0])
		var elbow: Bone2D = shoulder.get_node("Forearm")
		var wrist: Bone2D = elbow.get_node("Hand")
		var hold: Marker2D = wrist.get_node("HandArt/Hold")
		var palm: Sprite2D = wrist.get_node("HandArt/Palm")
		var fingers: Sprite2D = wrist.get_node("HandArt/Fingers")
		var blade: Sprite2D = spear.get_node("FireTip")
		var socket: Marker2D = spear.get_node(pair[1])
		var worst_error := 0.0
		for frame in range(0,230,2):
			scene.rig.pose_at(frame / 60.0)
			worst_error = maxf(worst_error,hold.global_position.distance_to(socket.global_position))
		check(worst_error < 1.25,"%s fingers stay wrapped around the moving shaft" % pair[0])
		for t in [0.0, 2.94, 3.30]:
			scene.rig.pose_at(t)
			check(palm.z_index < blade.z_index and blade.z_index < fingers.z_index,"%s palm and fingers wrap the shaft" % pair[0])
			var upper := shoulder.global_position - elbow.global_position
			var lower := wrist.global_position - elbow.global_position
			var bend := absf(rad_to_deg(upper.angle_to(lower)))
			check(bend > 30.0 and bend < 165.0,"%s elbow retains a readable bend at %.2fs" % [pair[0],t])
	for t in [1.34, 2.94]:
		scene.rig.pose_at(t)
		var coat: Sprite2D = chest.get_node("RobeViews/Back")
		var blade: Sprite2D = spear.get_node("FireTip")
		check(coat.visible and blade.z_index < coat.z_index,"back armour occludes the shaft at %.2fs" % t)

func check_pivots(scene: Node2D) -> void:
	for leg in ["RearLeg","FrontLeg"]:
		var knee: Bone2D = scene.rig.get_node("Skeleton/Pelvis/" + leg + "/Shin")
		var largest_step := 0.0
		scene.seek(1.15)
		var previous := knee.global_position
		for frame in range(139,309):
			scene.seek(frame / 120.0)
			largest_step = maxf(largest_step,previous.distance_to(knee.global_position))
			previous = knee.global_position
		check(largest_step < 10.0,"%s follows a continuous arc during both turns" % leg)

func _run() -> void:
	var scene = Study.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.playing = false
	scene.seek(0)
	var home: Vector2 = scene.actor.position
	var backdrop: Transform2D = scene.get_node("Stage/PaintedArena").global_transform
	check(scene.rig.find_children("*","Bone2D",true,false).size() >= 4,"editable bones")
	check(not scene.rig.find_children("*","AnimationPlayer",true,false).is_empty(),"editable pose animation")
	check_grips(scene)
	check_pivots(scene)
	scene.seek(1.52)
	var first_sweep: Vector2 = Vector2(scene.rig.weapon_tip()) - Vector2(scene.rig.weapon_grip())
	scene.seek(2.12)
	var second_sweep: Vector2 = Vector2(scene.rig.weapon_tip()) - Vector2(scene.rig.weapon_grip())
	check(first_sweep.x < 0 and second_sweep.x > 0 and second_sweep.y < 0,"low sweep reverses into a rising sweep")
	scene.seek(2.94)
	var loaded_tip: Vector2 = scene.rig.weapon_tip()
	scene.seek(scene.CONTACT)
	var struck_at: Vector2 = scene.actor.transform * Vector2(scene.rig.weapon_tip())
	var contact_root: Vector2 = scene.actor.position
	check(contact_root.x-home.x > 55,"grounded lunge advances")
	check(loaded_tip.distance_to(scene.rig.weapon_tip()) > 50,"weapon moves independently of the lunge")
	check(struck_at.distance_to(scene.tip_path[-1]) < .05,"contact paint aligns with live tip")
	scene.seek(3.39)
	check(scene.actor.position.is_equal_approx(contact_root),"brief contact hold")
	for stance in [[1.10,1.45,false],[1.58,1.99,true],[2.15,2.52,false],[2.96,3.15,false],
			[3.16,3.29,true],[4.05,4.30,false],[4.32,4.66,true],[4.68,4.95,false]]:
		var planted := sole_at(scene,stance[0],stance[2])
		check(planted.distance_to(sole_at(scene,stance[1],stance[2]))<2,"supporting boot stays planted at %.2fs" % stance[0])
	scene.seek(4.64)
	check(scene.actor.position.x < contact_root.x-20,"body withdraws")
	check(struck_at.is_equal_approx(scene._tip_on_path(scene.CONTACT)),"trail stays in stage space")
	check(scene.get_node("Stage/PaintedArena").global_transform.is_equal_approx(backdrop),"fixed scenery")
	scene.seek(4.95)
	check(scene.actor.position.is_equal_approx(home),"return to starting mark")
	scene.seek(scene.CONTACT)
	var before: Vector2 = scene.rig.weapon_tip()
	scene.playing = true
	press_key(KEY_F)
	check(not scene.spear_fx.visible and before.is_equal_approx(scene.rig.weapon_tip()),"clean pass preserves pose")
	check(is_zero_approx(scene.arena_light.get_shader_parameter("dusk")) and not scene.fire_audio.playing,"clean pass uses daylight and silence")
	var button: Button = scene.effects_button
	for down in [true,false]:
		var click := InputEventMouseButton.new()
		click.position = button.get_global_rect().get_center()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		root.push_input(click,true)
	check(scene.spear_fx.visible and before.is_equal_approx(scene.rig.weapon_tip()),"toggle at the same instant")
	press_key(KEY_SPACE)
	scene._process(.1)
	check(is_equal_approx(scene.pose_time,scene.CONTACT),"pause freezes the pose clock")
	press_key(KEY_R)
	check(scene.playing and is_zero_approx(scene.pose_time),"replay starts at the first pose")
	scene.reel = true
	scene.seek(scene.CONTACT)
	check(scene.spear_fx.visible and scene.fire_audio.playing,"first reel pass includes paint and audio")
	scene.seek(scene.CYCLE-1e-12)
	check(not scene.spear_fx.visible and scene.pose_time==0.0,"second pass starts clean at the first pose at a fixed-step seam")
	scene.seek(scene.CYCLE+scene.CONTACT)
	check(before.is_equal_approx(scene.rig.weapon_tip()) and not scene.fire_audio.playing,"the clean reel repeats the exact hit in silence")
	scene.queue_free()
	# The headless audio thread needs time to retire its last stopped WAV playback.
	await create_timer(.55).timeout
	print("NEZHA_STUDY ",JSON.stringify({"failures":failures}))
	quit(0 if failures.is_empty() else 1)
