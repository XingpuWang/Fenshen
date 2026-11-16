extends SceneTree

const Gallery=preload("res://tests/settlement_runtime.gd")
const PROFILES=["guanzhong_city_0","guanzhong_city_1","guanzhong_village_0","guanzhong_pass_1","guanzhong_ferry_1"]
var output_dir: String="res://previews/settlement-performance"
var sample_frames: int=360
var only_scenario: String=""
var results: Array=[]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf-output="): output_dir=arg.trim_prefix("--perf-output=")
		if arg.begins_with("--perf-frames="): sample_frames=int(arg.trim_prefix("--perf-frames="))
		if arg.begins_with("--perf-only="): only_scenario=arg.trim_prefix("--perf-only=")
	call_deferred("run")

func wait_frames(count: int) -> void:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw

func percentile(sorted: Array[float],fraction: float) -> float:
	return sorted[clampi(int(ceil(sorted.size()*fraction))-1,0,sorted.size()-1)]

func measure(game: Node,label: String,count: int,motion: bool=false,switching: bool=false) -> void:
	if not only_scenario.is_empty() and only_scenario!=label: return
	await wait_frames(60)
	var intervals: Array[float]=[]
	var previous: int=Time.get_ticks_usec()
	for i in count:
		if switching: game.open_settlement(PROFILES[i%PROFILES.size()])
		if motion:
			var phase: float=float(i)/90.0
			game.interior.view_zoom=1.1+.22*sin(phase)
			game.interior.view_pan=Vector2(sin(phase*.8)*170,cos(phase*.6)*90)
			game.interior.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var now: int=Time.get_ticks_usec()
		intervals.append(float(now-previous)/1000.0)
		previous=now
	var sorted: Array[float]=intervals.duplicate()
	sorted.sort()
	var total: float=0.0
	var over_25: int=0
	var over_33: int=0
	for ms in intervals:
		total+=ms
		if ms>25.0: over_25+=1
		if ms>33.333: over_33+=1
	var row: Dictionary={"scenario":label,"frames":count,"elapsed_seconds":total/1000.0,"average_fps":count*1000.0/total,"p95_frame_ms":percentile(sorted,.95),"p99_frame_ms":percentile(sorted,.99),"max_frame_ms":sorted[-1],"over_25ms_frames":over_25,"over_33ms_frames":over_33,"engine_fps_last":Engine.get_frames_per_second(),"last_draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	print("PERF_SAMPLE "+JSON.stringify(row))
	row["frame_intervals_ms"]=intervals
	results.append(row)

func fill(game: Node) -> void:
	var w=game.world
	var econ=w.economy
	for pid in PROFILES:
		var poi: Dictionary=w.by_poi[pid]
		poi.owner="player"
		for key in econ.KEYS: econ.treasury[key]=1000000
		for i in econ.settlements[pid].plots.size():
			if not econ.settlements[pid].plots[i].building.is_empty(): continue
			var kind: String=Gallery.LARGE_CITY_GALLERY[i] if pid==PROFILES[0] else ["farm","lumber","mine","market","jade"][int(econ.settlements[pid].plots[i].terrain)]
			var why: String=econ.build(poi,i,kind,w.by_poi)
			assert(why.is_empty(),why)
			w.next_turn()
	game.refresh()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size=Vector2i(1920,1080)
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await wait_frames(90)
	var rendered: Vector2i=Vector2i(root.get_texture().get_size())
	var environment: Dictionary={"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"requested_size":[1920,1080],"window_size":[root.size.x,root.size.y],"rendered_size":[rendered.x,rendered.y],"vsync_mode":DisplayServer.window_get_vsync_mode(),"refresh_hz":DisplayServer.screen_get_refresh_rate(),"max_fps":Engine.max_fps,"target_fps":60,"sampling":"Wall-clock intervals between completed draws. Warmup and screenshots are excluded. Native window; no simulated frame delta."}
	environment["accessibility_active"]=call("is_accessibility_enabled") if has_method("is_accessibility_enabled") else "unknown"
	environment["deadline_cap_fps"]=game.frame_pacer.target_fps
	print("PERF_ENV "+JSON.stringify(environment))
	if rendered!=Vector2i(1920,1080):
		push_error("Benchmark requires actual 1920x1080 rendering")
		quit(2)
		return
	game.open_settlement(PROFILES[0]); game.toast=""
	await measure(game,"large_city_initial",sample_frames)
	fill(game)
	for pid in PROFILES:
		game.open_settlement(pid); game.toast=""
		var scenario: String=game.interior.kind_for(game.world.by_poi[pid])+"_developed"
		await measure(game,scenario,sample_frames)
		if only_scenario==scenario:
			root.get_texture().get_image().save_png(output_dir.path_join(scenario+"-1920x1080.png"))
	game.open_settlement(PROFILES[0]); game.toast=""
	await measure(game,"large_city_pan_zoom",sample_frames*2,true)
	game.interior.view_zoom=1.0; game.interior.view_pan=Vector2.ZERO
	game.interior.queue_redraw()
	await wait_frames(3)
	if only_scenario.is_empty(): root.get_texture().get_image().save_png(output_dir.path_join("large-city-1920x1080.png"))
	await measure(game,"switching_interior_every_frame",60,false,true)
	game.close_settlement(); game.toast=""
	await measure(game,"overworld_return",sample_frames)
	var report: Dictionary={"environment":environment,"scenarios":results}
	FileAccess.open(output_dir.path_join("performance.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PERF_COMPLETE "+output_dir)
	quit()
