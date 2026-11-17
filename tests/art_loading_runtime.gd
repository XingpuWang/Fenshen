extends SceneTree
## Run after hiding only the new art's .ctex files to reproduce an old cache after pull.
## No art scripts are preloaded here: exercise the real main-scene loading order.
var failures: Array[String] = []
var checks := 0
var output := "user://art-loading"
var expect_fallback := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview-dir="): output = arg.trim_prefix("--preview-dir=")
		if arg == "--expect-source-fallback": expect_fallback = true
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func settle() -> void:
	for i in 8:
		await process_frame
		await RenderingServer.frame_post_draw

func bright_fraction(image: Image, area: Rect2i) -> float:
	var bright := 0
	var samples := 0
	for y in range(area.position.y, area.end.y, 3):
		for x in range(area.position.x, area.end.x, 3):
			var pixel := image.get_pixel(x, y)
			if pixel.get_luminance() > .38: bright += 1
			samples += 1
	return float(bright) / maxi(1, samples)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1080)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	var screenshot := root.get_texture().get_image()
	screenshot.save_png(output.path_join("01-map.png"))
	check(bright_fraction(screenshot, Rect2i(50, 50, 126, 142)) > .30, "Nezha portrait has visible artwork")
	for i in 4:
		check(bright_fraction(screenshot, Rect2i(234, 250 + 70 * i, 52, 52)) > .15, "skill %d has visible artwork" % i)
	for badge in game.layer.unit_badges:
		var center: Vector2 = badge.rect.position + Vector2(24, 24) * float(badge.scale)
		check(bright_fraction(screenshot, Rect2i(Vector2i(center) - Vector2i(12, 12), Vector2i(24, 24))) > .10, "map portrait is filled")
		var label: Vector2 = badge.rect.position + Vector2(54, 28) * float(badge.scale)
		check(bright_fraction(screenshot, Rect2i(Vector2i(label), Vector2i(55, 17))) > .03, "army strength remains drawn after the portrait")
	game.selected_unit = 1
	game.hud.queue_redraw()
	await settle()
	screenshot = root.get_texture().get_image()
	screenshot.save_png(output.path_join("02-wenzhong.png"))
	check(bright_fraction(screenshot, Rect2i(50, 50, 126, 142)) > .15, "Wen Zhong portrait remains visible")
	for i in 4:
		check(bright_fraction(screenshot, Rect2i(234, 250 + 70 * i, 52, 52)) > .15, "Wen Zhong skill %d has visible artwork" % i)
	var art = load("res://scripts/nezha_art.gd")
	art.prepare()
	for i in 16:
		var frame = art.frame_number("attack", i)
		check(frame.texture != null and frame.texture.get_width() > frame.source.position.x, "attack frame %d loads without import cache" % i)
	var textures = load("res://scripts/runtime_textures.gd")
	var fallbacks: Array = textures.source_fallbacks.duplicate()
	if expect_fallback:
		check(fallbacks.has("res://assets/characters/nezha/v3/portrait.png"), "portrait uses source fallback when its import is absent")
		check(fallbacks.has("res://assets/ui/skills/hero_icons.png"), "icons use source fallback when their import is absent")
		check(fallbacks.size() == 8, "all eight runtime art sheets load from source")
	else:
		check(fallbacks.is_empty(), "normal imported textures retain the standard resource path")
	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures, "source_fallbacks": fallbacks}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("ART_LOADING_RUNTIME ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
