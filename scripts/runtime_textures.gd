extends RefCounted
## New source art can arrive through git before the editor imports it.
## Keep those textures from turning a missing local cache into a script error.
static var textures: Dictionary = {}
static var source_fallbacks: Array[String] = []

static func get_texture(path: String) -> Texture2D:
	if textures.has(path): return textures[path]
	var settings := ConfigFile.new()
	var has_settings := settings.load(path + ".import") == OK
	var imported_path: String = settings.get_value("remap", "path", "") if has_settings else ""
	var imported_ready := not imported_path.is_empty() and FileAccess.file_exists(imported_path)
	var source_available := FileAccess.file_exists(path)
	var texture: Texture2D
	# Exported builds use Godot's resource remaps and need no original PNG.
	if imported_ready or not source_available:
		texture = load(path) as Texture2D
	if texture == null and source_available:
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
			push_error("Cannot decode source texture: " + path)
			return null
		if settings.get_value("params", "process/fix_alpha_border", true): image.fix_alpha_edges()
		if settings.get_value("params", "process/premult_alpha", false): image.premultiply_alpha()
		if settings.get_value("params", "mipmaps/generate", false): image.generate_mipmaps()
		texture = ImageTexture.create_from_image(image)
		source_fallbacks.append(path)
	if texture != null: textures[path] = texture
	return texture
