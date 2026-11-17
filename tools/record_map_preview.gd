extends SceneTree
## Capture the actual map UI and normal input at 30 fps with Godot Movie Maker.
## godot --path . --script res://tools/record_map_preview.gd \
##   --write-movie /tmp/map-preview.avi --fixed-fps 30 --disable-vsync
const FPS:=30
var game: Node2D
var markers: Array[Dictionary]=[]
var preview_dir:="res://previews/map-tactical"
var snapshot_only:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview-dir="): preview_dir=arg.trim_prefix("--preview-dir=")
		if arg=="--snapshot-only": snapshot_only=true
	call_deferred("record")

func hold(seconds: float) -> void:
	for i in roundi(seconds*FPS): await process_frame

func mark(name: String) -> void:
	markers.append({"name":name,"frame":Engine.get_frames_drawn(),"seconds":Engine.get_frames_drawn()/float(FPS)})

func click(point: Vector2,button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	var motion:=InputEventMouseMotion.new()
	motion.position=point
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point
		event.button_index=button
		event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new()
		event.physical_keycode=code
		event.pressed=pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func badge(index: int) -> Rect2:
	for entry in game.layer.unit_badges:
		if int(entry.unit)==index: return entry.rect
	return Rect2()

func record() -> void:
	Engine.max_fps=0
	DirAccess.make_dir_recursive_absolute(preview_dir)
	root.size=Vector2i(1920,1080)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await hold(.25)
	game.toast=""
	game.refresh()
	mark("原比例底图、半透明战术格与部队")
	await hold(2.0)
	await click(badge(1).get_center())
	assert(game.selected_unit==1,"Nameplate must select the correct army")
	mark("点击南宫适头像选中部队")
	await hold(1.4)
	await click(badge(0).get_center())
	await hold(.5)
	var target:=-1
	var best_score:=-INF
	for ci in game.reachable.dist:
		if int(game.reachable.dist[ci]) not in [4,5,6]: continue
		var screen: Vector2=game.world_to_screen(game.world.center(int(ci)))
		var start: Vector2=game.world_to_screen(game.unit_nodes[0].position)
		if screen.x<start.x+130 or absf(screen.y-start.y)>95: continue
		if not Rect2(500,250,1040,560).has_point(screen): continue
		if not game.hud.hit_test(screen).is_empty() or game.layer.badge_at_screen(screen)>=0: continue
		if not game.poi_at(game.world.center(int(ci))).is_empty(): continue
		var score:=screen.x-start.x-absf(screen.y-start.y)*2.0
		if score>best_score:
			best_score=score
			target=int(ci)
	assert(target>=0,"No visible legal demonstration route")
	await click(game.world_to_screen(game.world.center(target)))
	assert(game.path.size()>1 and game.path.back()==target,"Ground click must produce the displayed route")
	mark("独立斜俯视网格、金色箭簇与终点光标")
	await hold(1.5)
	root.get_texture().get_image().save_png(preview_dir.path_join("tactical-route.png"))
	if snapshot_only:
		print("MAP_SNAPSHOT "+preview_dir.path_join("tactical-route.png"))
		quit()
		return
	key(KEY_ENTER)
	mark("真实行军与移动动作")
	while game.moving: await process_frame
	assert(int(game.world.units[0].cell)==target,"Army must reach its clicked destination")
	await hold(1.0)
	key(KEY_SPACE)
	await hold(.25)
	for i in 3:
		await click(Vector2(950,560),MOUSE_BUTTON_WHEEL_UP)
		await hold(.2)
	mark("放大查看方阵与圆形头像")
	await hold(2.0)
	key(KEY_G)
	mark("查看淡色全图网格")
	await hold(1.4)
	key(KEY_G)
	await hold(1.2)
	var report:={"source":"actual Godot viewport / Movie Maker","fps":FPS,"resolution":[1920,1080],"grid_y_scale":game.world.grid_y_scale,"map_aspect_unchanged":game.camera.zoom.x==game.camera.zoom.y,
		"markers":markers,"seconds":Engine.get_frames_drawn()/float(FPS),"start":"unchanged new campaign","saved_campaign":false,
		"destination":target,"remaining_ap":int(game.world.units[0].ap),"balance_overrides":false}
	FileAccess.open(preview_dir.path_join("recording.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MAP_RECORDING "+JSON.stringify(report))
	quit()
