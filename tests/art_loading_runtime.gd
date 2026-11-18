extends SceneTree
## Run after hiding only the new art's .ctex files to reproduce an old cache after pull.
## No art scripts are preloaded here: exercise the real main-scene loading order.
var failures: Array[String] = []
var checks := 0
var output := "user://art-loading"
var expect_fallback := false
var expect_troop_fallback := false
var expect_spell_fallback := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview-dir="): output = arg.trim_prefix("--preview-dir=")
		if arg == "--expect-source-fallback": expect_fallback = true
		if arg == "--expect-troop-fallback": expect_troop_fallback = true
		if arg == "--expect-spell-fallback": expect_spell_fallback = true
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
	var wen = load("res://scripts/wenzhong_art.gd")
	wen.prepare()
	for clip in ["attack","thunder_whip","nine_thunders","thunder_seal"]:
		for i in 16:
			var frame = wen.frame_number(clip,i)
			check(frame.texture != null and frame.texture.get_width() >= frame.source.end.x,"Wen Zhong %s frame %d loads without import cache" % [clip,i])
	var textures = load("res://scripts/runtime_textures.gd")
	var spells = load("res://scripts/divine_spell_art.gd")
	var spell_sheets := {"res://assets/battle/hero_fx/lotus.png": spells.lotus,
		"res://assets/battle/hero_fx/thunder.png": spells.thunder}
	for path: String in spell_sheets:
		var sheet: Texture2D = spell_sheets[path]
		check(sheet != null, "painted spell sheet loads: " + path)
		if sheet == null: continue
		var image := sheet.get_image()
		var width := image.get_height()
		check(image.get_width() == width * 4, "four square spell cels in " + path)
		var signatures := {}
		for i in 4:
			var cel := image.get_region(Rect2i(i * width, 0, width, width))
			var visible := cel.get_used_rect()
			check(visible.has_area() and Rect2i(1,1,width-2,width-2).encloses(visible), "spell cel has art and a transparent gutter")
			signatures[hash(cel.get_data())] = true
		check(signatures.size() == 4, "four distinct painted spell stages")
	var fallbacks: Array = textures.source_fallbacks.duplicate()
	for path: String in spell_sheets:
		check(fallbacks.has(path) == expect_spell_fallback, "spell uses the available source or import")
		fallbacks.erase(path)
	var army_art=load("res://scripts/army_art.gd")
	for faction in ["zhou","shang"]:
		for kind in ["archer","cavalry"]:
			var texture: Texture2D = army_art.TEXTURES[faction+"_"+kind]
			check(texture!=null and texture.get_width()>0,"both factions load their " + kind + " sheet")
			var folder: String="archers" if kind=="archer" else "cavalry"
			var path: String="res://assets/battle/%s/%s.png"%[folder,faction]
			check(fallbacks.has(path)==expect_troop_fallback,"troop textures use the available source or import")
			fallbacks.erase(path)
	if expect_fallback:
		check(fallbacks.has("res://assets/characters/nezha/v3/portrait.png"), "portrait uses source fallback when its import is absent")
		check(fallbacks.has("res://assets/ui/skills/hero_icons.png"), "icons use source fallback when their import is absent")
		check(fallbacks.has("res://assets/characters/wenzhong/v1/portrait.png"),"Wen Zhong illustration uses source fallback")
		check(fallbacks.size() == art.DATA.sheets.size() + wen.DATA.sheets.size() + 3, "both heroes' runtime sheets, portraits and icon atlas load from source")
	else:
		check(fallbacks.is_empty(), "normal imported textures retain the standard resource path")
	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures, "source_fallbacks": textures.source_fallbacks}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("ART_LOADING_RUNTIME ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
