extends RefCounted
## Pose the whole painted costume from the rib cage, clavicles and pelvis.
const Fold = preload("res://shaders/nezha_skirt_fold.gdshader")
const Tunic = preload("res://shaders/nezha_tunic_skin.gdshader")
const RATE := 60
const ROWS := 10
const COLS := 4

var skirts: Array[MeshInstance2D] = []
var tunics: Array[MeshInstance2D] = []
var hip_binds: Array[Transform2D] = []
var near_sockets := PackedVector2Array()
var far_sockets := PackedVector2Array()
var hip_path := PackedVector3Array()

func bind(rig: Node2D) -> void:
	var vertices := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in ROWS + 1:
		for col in COLS + 1:
			vertices.append(Vector2(float(col)/COLS, float(row)/ROWS))
			if row < ROWS and col < COLS:
				var i := row*(COLS+1) + col
				indices.append_array(PackedInt32Array([i,i+1,i+COLS+1, i+1,i+COLS+2,i+COLS+1]))
	var data := []
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX] = vertices
	data[Mesh.ARRAY_TEX_UV] = vertices
	data[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data)
	for sprite: Sprite2D in rig.belt.get_children() + rig.costume.get_children():
		var panel := MeshInstance2D.new()
		var material := ShaderMaterial.new()
		var is_skirt: bool = sprite.get_parent() == rig.belt
		material.shader = Fold if is_skirt else Tunic
		panel.mesh = mesh
		panel.texture = sprite.texture
		panel.material = material
		panel.position = sprite.get_rect().position
		panel.scale = sprite.get_rect().size
		sprite.add_child(panel)
		sprite.self_modulate.a = 0.0
		if is_skirt:
			skirts.append(panel)
		else:
			tunics.append(panel)
			hip_binds.append(rig.pelvis.global_transform.affine_inverse() * panel.global_transform)
			var near_at := panel.to_local(rig.arms[0][0].global_position)
			var far_at := panel.to_local(rig.arms[1][0].global_position)
			near_sockets.append(near_at)
			far_sockets.append(far_at)
			material.set_shader_parameter("near_socket",near_at)
			material.set_shader_parameter("far_socket",far_at)

func record_hip(position: Vector2, yaw: float) -> void:
	hip_path.append(Vector3(position.x,position.y,yaw))

func _hip_at(t: float) -> Vector3:
	var frame := t * RATE
	var tick := floori(frame)
	var first := posmod(tick,hip_path.size())
	return hip_path[first].lerp(hip_path[(first+1) % hip_path.size()],frame-tick)

func pose_at(t: float, rig: Node2D) -> void:
	for i in tunics.size():
		var tunic := tunics[i]
		if not tunic.is_visible_in_tree(): continue
		var hip: Transform2D = tunic.global_transform.affine_inverse() * rig.pelvis.global_transform * hip_binds[i]
		var material := tunic.material as ShaderMaterial
		material.set_shader_parameter("hip_origin",hip.origin)
		material.set_shader_parameter("hip_x",hip.x)
		material.set_shader_parameter("hip_y",hip.y)
		material.set_shader_parameter("near_pull",(tunic.to_local(rig.arms[0][0].global_position)-near_sockets[i]).limit_length(.085))
		material.set_shader_parameter("far_pull",(tunic.to_local(rig.arms[1][0].global_position)-far_sockets[i]).limit_length(.085))
	var now := _hip_at(t)
	var recent := _hip_at(t-.11)
	var earlier := _hip_at(t-.20)
	var inertia := .48 * (recent - now) + .23 * (earlier - recent)
	# Tangential travel of the cloth at the back of the waist as the hip turns.
	var twist := 14.0 * (sin(recent.z+.55) - sin(now.z+.55))
	var sway := Vector2(clampf(inertia.x+twist,-18,18), clampf(inertia.y,-5,5))
	for panel in skirts:
		if not panel.is_visible_in_tree(): continue
		# Map actor-space movement into the mirrored, normalized mesh for this view.
		var to_panel := panel.global_transform.affine_inverse() * rig.global_transform
		var shift := to_panel.basis_xform(sway)
		var outward := to_panel.basis_xform(Vector2(twist,0)).x
		var material := panel.material as ShaderMaterial
		material.set_shader_parameter("hem_offset",shift)
		material.set_shader_parameter("edge_lift",Vector2(maxf(0,-outward),maxf(0,outward))*.37)
