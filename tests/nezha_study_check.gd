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
	# Check the painted cels too. A rightward weapon alone doesn't tell us
	# whether the animation shows the back of the head or a flipped face.
	var faces_target := true
	var body_forward := true
	for frame in range(769):
		scene.rig.pose_at(frame/120.0)
		faces_target = faces_target and scene.rig.portrait.visible and scene.rig.portrait.global_transform.x.x > 0
		body_forward = body_forward and not scene.rig.costume.get_node("Back").visible and not scene.rig.belt.get_node("Back").visible
	check(faces_target,"Nezha keeps his gaze on the right throughout the entire action")
	check(body_forward,"the hips and chest never turn their back to the target")
	# A cross-fade between two translucent views let sand show through the hair and sash.
	for t in [1.24,1.34,1.66,2.72,3.11]:
		scene.rig.pose_at(t)
		for group in [scene.rig.belt, scene.rig.costume]:
			var coverage := 0.0
			for art: Sprite2D in group.get_children():
				if art.visible: coverage = maxf(coverage,art.modulate.a)
			check(coverage >= .99,"opaque costume at %.2fs" % t)
		var face_opacity: float = scene.rig.portrait.modulate.a if scene.rig.portrait.visible else 0.0
		for view: Sprite2D in scene.rig.head_views.get_children():
			if view.visible: face_opacity = maxf(face_opacity,view.modulate.a)
		check(face_opacity >= .99,"opaque head at %.2fs" % t)

func check_weight_transfer(scene: Node2D) -> void:
	# Both attacks play into the same forward sector. The hips can wind up
	# inside that stance while the two-handed spear travels a wider arc.
	scene.rig.pose_at(.8)
	var hip: float = scene.rig.hip_turn
	var spear: float = scene.rig.spear_turn
	var hip_travel := 0.0
	var spear_travel := 0.0
	for frame in range(49,140):
		scene.rig.pose_at(frame/60.0)
		hip_travel += absf(wrapf(scene.rig.hip_turn - hip,-180,180))
		spear_travel += absf(wrapf(scene.rig.spear_turn - spear,-180,180))
		hip = scene.rig.hip_turn
		spear = scene.rig.spear_turn
	check(hip_travel < 300 and spear_travel > hip_travel * 1.45,"the hips transfer weight under both sweeps")
	scene.rig.pose_at(2.52)
	var sight: float = scene.rig.face_turn
	var shoulders: float = scene.rig.chest_turn
	scene.rig.pose_at(2.94)
	check(absf(scene.rig.face_turn-sight) + 12 < absf(scene.rig.chest_turn-shoulders),"gaze steadies while the shoulder winds up")

func check_leg_motion(scene: Node2D) -> void:
	for leg in ["RearLeg","FrontLeg"]:
		var hip: Bone2D = scene.rig.get_node("Skeleton/Pelvis/" + leg)
		var knee: Bone2D = hip.get_node("Shin")
		var ankle: Bone2D = knee.get_node("Boot")
		var largest_step := 0.0
		var lowest_angle := 180.0
		var highest_angle := 0.0
		var span_error := 0.0
		var right_bend := true
		scene.rig.pose_at(0)
		var thigh_span := hip.global_position.distance_to(knee.global_position)
		var shin_span := knee.global_position.distance_to(ankle.global_position)
		var previous: Vector2 = scene.rig.to_local(knee.global_position)
		for frame in range(1,769):
			scene.rig.pose_at(frame/120.0)
			var thigh := knee.global_position - hip.global_position
			var shin := ankle.global_position - knee.global_position
			span_error = maxf(span_error,maxf(absf(thigh.length()-thigh_span),absf(shin.length()-shin_span)))
			right_bend = right_bend and thigh.cross(shin) > 0.0
			var angle := absf(rad_to_deg((-thigh).angle_to(shin)))
			lowest_angle = minf(lowest_angle,angle)
			highest_angle = maxf(highest_angle,angle)
			var current: Vector2 = scene.rig.to_local(knee.global_position)
			largest_step = maxf(largest_step,previous.distance_to(current))
			previous = current
		check(span_error < .05,"%s thigh and shin retain their bone lengths" % leg)
		check(right_bend and lowest_angle > 90 and highest_angle < 177,"%s knee bends towards its toe without collapsing or locking" % leg)
		check(largest_step < 10.0,"%s knee follows a continuous arc" % leg)
	scene.seek(scene.CONTACT)
	var heel: Bone2D = scene.rig.legs[0][2]
	var plant: Bone2D = scene.rig.legs[1][2]
	check(heel.global_rotation > deg_to_rad(8) and absf(plant.global_rotation) < deg_to_rad(3),"rear heel drives up while the front foot bears the finishing stroke")
	var rear_bend: float = absf(scene.rig.legs[0][1].rotation)
	check(rear_bend + deg_to_rad(18) < absf(scene.rig.legs[1][1].rotation),"the front knee receives the lunge while the rear leg extends")
	scene.seek(3.62)
	check(rear_bend + deg_to_rad(12) < absf(scene.rig.legs[0][1].rotation),"the driving knee releases after the hit")

# Read the character art itself: the last half-opaque column is the metal
# point. Its pixel centre is independent of the rig marker and the effect.
func painted_tip_pixel(blade: Sprite2D) -> Vector2:
	var source := blade.texture.get_image()
	if source == null:
		check(false, "physical spear source image is available")
		return Vector2.ZERO
	for x in range(source.get_width()-1, -1, -1):
		var total_y := 0.0
		var count := 0
		for y in source.get_height():
			if source.get_pixel(x,y).a >= .5:
				total_y += y + .5
				count += 1
		if count > 0:
			return Vector2(x+.5, total_y/count)
	check(false, "physical spear contains a painted point")
	return Vector2.ZERO

func check_weapon_effects() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	root.add_child(viewport)
	var scene = Study.instantiate()
	# Keep FX and weapon in independent local frames. The real scene normally
	# places FX at zero, which by itself cannot catch a stage/FX coordinate mixup.
	var fx: Node2D = scene.get_node("Stage/SpearFX")
	fx.position = Vector2(26,-13)
	var actor: Node2D = scene.get_node("Stage/Actor")
	actor.scale *= 1.18
	var rig: Node2D = actor.get_node("Rig")
	rig.position += Vector2(7,-2)
	viewport.add_child(scene)
	scene.set_process(false)
	scene.playing = false
	var blade: Sprite2D = scene.rig.get_node("Skeleton/Spear/FireTip")
	var pixel := blade.get_rect().position + painted_tip_pixel(blade)
	var ignition := fx.get_node_or_null("BladeIgnition") as Sprite2D
	var point := fx.get_node_or_null("LotusImpact/Point") as Sprite2D
	var heart := fx.get_node_or_null("LotusImpact/Heart") as Sprite2D
	var corolla := fx.get_node_or_null("LotusImpact/Corolla") as Sprite2D
	if ignition == null or point == null or heart == null or corolla == null:
		check(false, "the drawn spear ignition and lotus impact sprites are available")
		viewport.queue_free()
		return
	# Jump across phase boundaries, revisit a frame, and cover both a letterbox
	# and a large viewport. All comparisons are in the viewport's canvas space.
	for size: Vector2i in [Vector2i(640,360),Vector2i(1024,768),Vector2i(1920,1080)]:
		viewport.size = size
		scene._fit_stage()
		scene.seek(scene.CONTACT)
		var struck_at := blade.to_global(pixel)
		for millis: int in [3810, 1420, 3180, 2070, 3470, 1380, 3130, 3300, 3350, 1420]:
			var t := millis*.001
			var label := "at %dms in %s" % [millis,size]
			scene.seek(t)
			var gold := blade.to_global(pixel)
			var marker: Vector2 = scene.rig.to_global(scene.rig.weapon_tip())
			check(marker.distance_to(gold)<.01, "marker follows the actual painting " + label)
			if millis < 3000:
				check(ignition.is_visible_in_tree() and ignition.global_position.distance_to(gold)<.04,
						"ignition follows the painted spear " + label)
				var quads: Array = fx.get("_turn_quads")
				if quads.is_empty():
					check(false, "the active sweep draws its hot edge " + label)
				else:
					var edge: PackedVector2Array = quads[-1]
					check(fx.to_global(edge[1]).distance_to(gold)<.04 and fx.to_global(edge[2]).distance_to(gold)<.04,
							"both painted edges meet the current metal point " + label)
			elif millis < 3300:
				check(point.is_visible_in_tree() and point.global_position.distance_to(gold)<.04,
						"finisher light follows the moving point before contact " + label)
			else:
				if millis <= 3470:
					check(heart.is_visible_in_tree() and heart.global_position.distance_to(struck_at)<.04,
							"impact light stays where the metal made contact " + label)
				if millis == 3810:
					check(gold.distance_to(struck_at)>4.0, "the spear has pulled away from the flowering hit " + label)
				if millis > 3300:
					check(corolla.is_visible_in_tree() and corolla.global_position.distance_to(struck_at)<.04,
							"the opening lotus stays on the original hit " + label)
	viewport.queue_free()

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
	check_weight_transfer(scene)
	check_leg_motion(scene)
	check_weapon_effects()
	scene.seek(1.52)
	var first_sweep: Vector2 = Vector2(scene.rig.weapon_tip()) - Vector2(scene.rig.weapon_grip())
	scene.seek(2.12)
	var second_sweep: Vector2 = Vector2(scene.rig.weapon_tip()) - Vector2(scene.rig.weapon_grip())
	check(first_sweep.x > 0 and first_sweep.y > 0 and second_sweep.x > 0 and second_sweep.y < 0,"low sweep and rising sweep both strike to the right")
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
	# The delayed hem samples straddle zero on a 60 Hz clock accumulated in floats.
	var hip: Vector3 = scene.costume._hip_at(0)
	check(hip.is_equal_approx(scene.costume._hip_at(-1e-15)), "delayed hem samples wrap across the start of the reel")
	scene.queue_free()
	# The headless audio thread needs time to retire its last stopped WAV playback.
	await create_timer(.55).timeout
	print("NEZHA_STUDY ",JSON.stringify({"failures":failures}))
	quit(0 if failures.is_empty() else 1)
