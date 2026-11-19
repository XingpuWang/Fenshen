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

func _run() -> void:
	var scene = Study.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.seek(0)
	var home: Vector2 = scene.actor.position
	var backdrop: Transform2D = scene.get_node("Stage/PaintedArena").global_transform
	check(scene.rig.find_children("*","Bone2D",true,false).size() >= 4,"editable bones")
	check(not scene.rig.find_children("*","AnimationPlayer",true,false).is_empty(),"editable pose animation")
	scene.seek(1.62)
	var loaded_tip: Vector2 = scene.rig.weapon_tip()
	scene.seek(scene.CONTACT)
	var struck_at: Vector2 = scene.actor.transform * Vector2(scene.rig.weapon_tip())
	var contact_root: Vector2 = scene.actor.position
	check(contact_root.x-home.x > 130,"grounded lunge advances")
	check(Vector2(scene.rig.weapon_tip()).x-loaded_tip.x > 32,"weapon extends independently of the lunge")
	check(struck_at.distance_to(scene.tip_path[-1]) < .05,"contact paint aligns with live tip")
	scene.seek(1.89)
	check(scene.actor.position.is_equal_approx(contact_root),"brief contact hold")
	check(absf(sole_at(scene,1.81,true).x - sole_at(scene,1.84,true).x)<2,"front boot plants on arrival")
	for stance in [[2.20,2.27,true],[2.53,2.61,false],[2.84,2.94,true]]:
		var planted := sole_at(scene,stance[0],stance[2])
		check(planted.distance_to(sole_at(scene,stance[1],stance[2]))<2,"supporting boot stays planted between backward hops")
	scene.seek(2.51)
	check(scene.actor.position.x < contact_root.x-20,"body withdraws")
	check(struck_at.is_equal_approx(scene._tip_on_path(scene.CONTACT)),"trail stays in stage space")
	check(scene.get_node("Stage/PaintedArena").global_transform.is_equal_approx(backdrop),"fixed scenery")
	scene.seek(2.94)
	check(scene.actor.position.is_equal_approx(home),"return to starting mark")
	scene.seek(scene.CONTACT)
	var before: Vector2 = scene.rig.weapon_tip()
	press_key(KEY_F)
	check(not scene.spear_fx.visible and before.is_equal_approx(scene.rig.weapon_tip()),"clean pass preserves pose")
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
	scene.seek(scene.CYCLE-1e-12)
	check(scene.spear_fx.visible and scene.pose_time==0.0,"second pass starts at the first pose at a fixed-step seam")
	scene.free()
	print("NEZHA_STUDY ",JSON.stringify({"failures":failures}))
	quit(0 if failures.is_empty() else 1)
