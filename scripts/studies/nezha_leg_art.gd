@tool
extends Node2D
## Painted trouser and greave share the hip–knee–ankle contour. The IK owns the joints.
const Fold = preload("res://shaders/nezha_leg_fold.gdshader")
const COLUMNS := 8
const ROWS := 30

enum Layer { TROUSER, GREAVE, INNER_CUFF }

var _materials: Array[ShaderMaterial] = []
var _lower: Bone2D
var _boot: Bone2D

func _ready() -> void:
	var upper := get_parent() as Bone2D
	_lower = upper.get_node("Shin") as Bone2D
	_boot = _lower.get_node("Boot") as Bone2D
	var trouser := get_node("Trousers") as Sprite2D
	var greave := _lower.get_node("LowerArt/Greave") as Sprite2D
	var near_leg := upper.name == &"FrontLeg"
	var grid := _paint_grid()
	_add_paint(grid, trouser, Layer.TROUSER, trouser.z_index, near_leg)
	_add_paint(grid, greave, Layer.GREAVE, greave.z_index, near_leg)
	# A few inside folds of the trouser fall over the back of the boot in deep flexion.
	_add_paint(grid, trouser, Layer.INNER_CUFF, greave.z_index, near_leg)
	trouser.hide()
	greave.hide()
	refresh_pose()

func _add_paint(grid: ArrayMesh, source: Sprite2D, layer: Layer, depth: int, near_leg: bool) -> void:
	var material_instance := ShaderMaterial.new()
	material_instance.shader = Fold
	material_instance.set_shader_parameter("layer", int(layer))
	material_instance.set_shader_parameter("paint_width", source.texture.get_width() * absf(source.scale.x))
	material_instance.set_shader_parameter("near_leg", near_leg)
	var surface := MeshInstance2D.new()
	surface.name = ["SilkTrousers", "WrappedGreave", "InnerCuff"][layer]
	surface.mesh = grid
	surface.texture = source.texture
	surface.material = material_instance
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	surface.z_index = depth
	add_child(surface)
	_materials.append(material_instance)

func _paint_grid() -> ArrayMesh:
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var triangles := PackedInt32Array()
	for row in ROWS + 1:
		for column in COLUMNS + 1:
			var uv := Vector2(float(column)/COLUMNS, float(row)/ROWS)
			uvs.append(uv)
			# Initial bounds include the skirt, forward knee and ankle during canvas culling.
			points.append(Vector2(200.0*uv.x-100.0, 170.0*uv.y-36.0))
			if row == ROWS or column == COLUMNS: continue
			var a := row * (COLUMNS+1) + column
			var b := a + COLUMNS + 1
			triangles.append_array(PackedInt32Array([a, b, a+1, a+1, b, b+1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = triangles
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

func refresh_pose() -> void:
	if _materials.is_empty(): return
	var hip := to_local((get_parent() as Node2D).global_position)
	var knee := to_local(_lower.global_position)
	var ankle := to_local(_boot.global_position)
	var boot_axis := (to_local(_boot.to_global(Vector2.DOWN)) - ankle).normalized()
	for paint in _materials:
		paint.set_shader_parameter("hip", hip)
		paint.set_shader_parameter("knee", knee)
		paint.set_shader_parameter("ankle", ankle)
		paint.set_shader_parameter("boot_axis", boot_axis)
