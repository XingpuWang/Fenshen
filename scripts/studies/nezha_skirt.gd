extends RefCounted
## Keep the painted belt attached to the hips while the heavier skirt panels
## catch up with each weight transfer. All views use the same stage-space motion.
const Fold = preload("res://shaders/nezha_skirt_fold.gdshader")
const RATE := 60
const ROWS := 10
const COLS := 4

var panels: Array[MeshInstance2D] = []
var hip_path := PackedVector3Array()

func bind(belt: Node2D) -> void:
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
	for sprite: Sprite2D in belt.get_children():
		var panel := MeshInstance2D.new()
		var material := ShaderMaterial.new()
		material.shader = Fold
		panel.mesh = mesh
		panel.texture = sprite.texture
		panel.material = material
		panel.position = sprite.get_rect().position
		panel.scale = sprite.get_rect().size
		sprite.add_child(panel)
		sprite.self_modulate.a = 0.0
		panels.append(panel)

func record_hip(position: Vector2, yaw: float) -> void:
	hip_path.append(Vector3(position.x,position.y,yaw))

func _hip_at(t: float) -> Vector3:
	var frame := t * RATE
	var tick := floori(frame)
	var first := posmod(tick,hip_path.size())
	return hip_path[first].lerp(hip_path[(first+1) % hip_path.size()],frame-tick)

func pose_at(t: float, rig: Node2D) -> void:
	var now := _hip_at(t)
	var recent := _hip_at(t-.11)
	var earlier := _hip_at(t-.20)
	var inertia := .48 * (recent - now) + .23 * (earlier - recent)
	# Tangential travel of the cloth at the back of the waist as the hip turns.
	var twist := 14.0 * (sin(recent.z+.55) - sin(now.z+.55))
	var sway := Vector2(clampf(inertia.x+twist,-18,18), clampf(inertia.y,-5,5))
	for panel in panels:
		if not panel.is_visible_in_tree(): continue
		# Map actor-space movement into the mirrored, normalized mesh for this view.
		var to_panel := panel.global_transform.affine_inverse() * rig.global_transform
		var shift := to_panel.basis_xform(sway)
		var outward := to_panel.basis_xform(Vector2(twist,0)).x
		var material := panel.material as ShaderMaterial
		material.set_shader_parameter("hem_offset",shift)
		material.set_shader_parameter("edge_lift",Vector2(maxf(0,-outward),maxf(0,outward))*.37)
