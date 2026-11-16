extends SceneTree
## Real rendered 1080p workload. Disable pacing only here to measure headroom.
const Rules=preload("res://scripts/battle_rules.gd")
var reports: Array[Dictionary]=[]
var output_dir:="res://previews/battle/upright-v3"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output_dir=arg.trim_prefix("--output=")
	call_deferred("run")

func run() -> void:
	var paced: bool="--paced" in OS.get_cmdline_user_args()
	if not paced:
		Engine.max_fps=0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size=Vector2i(1920,1080)
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_exhibition()
	var battle: Control=game.battle
	battle.profile_enabled=true
	for soldiers in [2400,6000]:
		var encounter: Dictionary=battle.sim.encounter.duplicate(true)
		encounter.player.soldiers=soldiers
		encounter.enemy.soldiers=soldiers
		battle.sim=Rules.new(encounter)
		battle.effects.clear()
		battle.result_age=0
		battle.accumulator=0
		battle.speed=1
		var samples: Array[float]=[]
		var cpu: Array[float]=[]
		var sim_ms: Array[float]=[]
		var draw_ms: Array[float]=[]
		var steps: Array[float]=[]
		var previous:=Time.get_ticks_usec()
		while battle.sim.elapsed<23 and battle.sim.result.is_empty():
			await RenderingServer.frame_post_draw
			var now:=Time.get_ticks_usec()
			if battle.sim.elapsed>3.0:
				samples.append((now-previous)/1000.0)
				cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
				sim_ms.append(battle.profile_sim_ms)
				draw_ms.append(battle.profile_draw_ms)
				steps.append(battle.profile_steps)
			previous=now
			if battle.sim.finisher_reason(0).is_empty(): battle.sim.use_finisher(0)
		var elapsed_ms:=0.0
		var missed:=0
		for ms in samples:
			elapsed_ms+=ms
			if ms>1000.0/60.0: missed+=1
		samples.sort()
		cpu.sort()
		sim_ms.sort()
		draw_ms.sort()
		steps.sort()
		reports.append({"soldiers_per_side":soldiers,"starting_actors":battle.sim.fighters.size(),
			"sample_frames":samples.size(),"sample_seconds":elapsed_ms/1000.0,
			"fps_average":1000.0*samples.size()/elapsed_ms,"frame_ms_p95":percentile(samples,.95),
			"frame_ms_p99":percentile(samples,.99),"frame_ms_max":samples.back(),
			"cpu_process_ms_p95":percentile(cpu,.95),"frames_over_16_67_ms":missed,
			"simulation_ms_p95":percentile(sim_ms,.95),"draw_script_ms_p95":percentile(draw_ms,.95),"steps_per_frame_p95":percentile(steps,.95),
			"meets_60fps_p95":percentile(samples,.95)<=1000.0/60.0,
			"combat":battle.sim.stats.duplicate()})
		print("BATTLE_PERF_SAMPLE "+JSON.stringify(reports.back()))
	var report: Dictionary={"resolution":[root.size.x,root.size.y],"target_fps":60,
		"runtime_cap":ProjectSettings.get_setting("application/run/max_fps"),
		"benchmark_cap":60 if paced else 0,"vsync":"disabled during measurement", "simulation_hz":60,
		"renderer":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"samples":reports}
	DirAccess.make_dir_recursive_absolute(output_dir)
	FileAccess.open(output_dir.path_join("performance-paced.json" if paced else "performance-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BATTLE_PERFORMANCE "+JSON.stringify(report))
	quit()

func percentile(values: Array[float], quantile: float) -> float:
	return values[mini(values.size()-1,floori(values.size()*quantile))]
