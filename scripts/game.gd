extends Node2D

const World=preload("res://scripts/world_model.gd")
const MapLayer=preload("res://scripts/map_layer.gd")
const HUD=preload("res://scripts/hud.gd")
const Interior=preload("res://scripts/settlement_view.gd")
const BattleView=preload("res://scripts/battle_view.gd")
const MapArmy=preload("res://scripts/map_army.gd")
@export var start_in_test_scenario:=true
var battle: Control
var battle_canvas: CanvasLayer
var interior: Control
var economy_income: Dictionary = {}
var world: ShanheWorld
var camera: Camera2D
var layer: Node2D
var hud: Control
var grid: Polygon2D
var grid_material: ShaderMaterial
var unit_nodes: Array[Node2D]=[]
var selected_unit: int=0
var selected_poi: String=""
var hover_cell: int=-1
var reachable: Dictionary={}
var path: Array[int]=[]
var path_cost: int=0
var moving: bool=false
var toast: String=""
var toast_time: float=0.0
var dragging: bool=false
var drag_button: int=0
var drag_origin:=Vector2.ZERO
var drag_distance: float=0.0
var last_mouse:=Vector2.ZERO
var grid_visible: bool=false
var terrain_overlay: Sprite2D
var capture_mode: bool=false
var travel_speed: float=1.0
var covered_world_visibility: Dictionary={}
var world_view_dirty: bool=true
var last_camera_position:=Vector2(INF,INF)
var last_camera_zoom:=Vector2.ZERO
var frame_pacer: Node
var map_skill_targeting:=false
var skill_range_cells: Array=[]
var skill_preview: Dictionary={}
var map_cast: Dictionary={}
const MAP_CAST_RELEASE:=0.62
const MAP_CAST_IMPACT:=1.12
const MAP_CAST_END:=1.85

func _ready() -> void:
	frame_pacer=load("res://scripts/frame_pacer.gd").new()
	add_child(frame_pacer)
	world=World.new(not "--legacy-fixture" in OS.get_cmdline_user_args())
	if start_in_test_scenario and not "--campaign" in OS.get_cmdline_user_args() and not "--legacy-fixture" in OS.get_cmdline_user_args(): world.setup_chaoge_test()
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	load_map()
	camera=Camera2D.new()
	camera.position=world.center(int(world.units[0].cell))+Vector2(-50,100)
	set_map_zoom(.50)
	if world.test_scenario:
		var city: Dictionary=world.by_poi[world.test_city_id]
		camera.position=Vector2(city.position[0],city.position[1])+Vector2(0,180)
		set_map_zoom(.72)
	camera.position_smoothing_enabled=false
	add_child(camera)
	grid=Polygon2D.new()
	var b:=world.bounds
	grid.polygon=PackedVector2Array([b.position,b.position+Vector2(b.size.x,0),b.end,b.position+Vector2(0,b.size.y)])
	grid_material=ShaderMaterial.new()
	grid_material.shader=load("res://shaders/hex_grid.gdshader")
	grid_material.set_shader_parameter("hex_radius",world.radius)
	grid_material.set_shader_parameter("grid_y_scale",world.grid_y_scale)
	grid_material.set_shader_parameter("grid_opacity",0.09)
	grid_material.set_shader_parameter("ink_color",Color(.17,.24,.16,1))
	grid_material.set_shader_parameter("has_selection",false)
	grid.material=grid_material
	grid.z_index=1
	grid.visible=grid_visible
	add_child(grid)
	terrain_overlay=Sprite2D.new()
	terrain_overlay.texture=load("res://data/terrain_mask.png")
	terrain_overlay.centered=false
	terrain_overlay.position=world.bounds.position
	terrain_overlay.scale=Vector2.ONE*8
	terrain_overlay.z_index=2
	terrain_overlay.visible=false
	add_child(terrain_overlay)
	for u in world.units:
		var node=Node2D.new()
		node.position=world.center(int(u.cell))
		node.z_index=5
		add_child(node)
		var shadow=Polygon2D.new()
		var pts=PackedVector2Array()
		for i in 32: pts.append(Vector2(cos(i*TAU/32)*world.radius*.64,world.radius*.17+sin(i*TAU/32)*world.radius*.22*world.grid_y_scale))
		shadow.polygon=pts
		shadow.color=Color(.08,.08,.04,.24)
		node.add_child(shadow)
		var sprite=MapArmy.new()
		sprite.name="Soldiers"
		sprite.game=self
		sprite.unit_index=unit_nodes.size()
		node.add_child(sprite)
		var boat=Sprite2D.new()
		boat.name="Boat"
		boat.texture=load("res://assets/units/ferry_boat.svg")
		boat.scale=Vector2.ONE*.64*world.radius/80.0
		boat.position=Vector2(0,-5)
		boat.z_index=-1
		boat.visible=false
		node.add_child(boat)
		unit_nodes.append(node)
	layer=MapLayer.new()
	layer.game=self
	add_child(layer)
	layer.z_index=3
	var canvas=CanvasLayer.new()
	canvas.layer=20
	add_child(canvas)
	battle_canvas=canvas
	hud=HUD.new()
	hud.game=self
	canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interior=Interior.new()
	interior.game=self
	interior.visible=false
	canvas.add_child(interior)
	interior.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh()
	say("西岐开局 · 点击城池经营，选择青色地块行军")
	for arg in OS.get_cmdline_user_args():
		if arg=="--battle-demo": call_deferred("start_exhibition")
		if arg.begins_with("--skills-capture="):
			var runner=load("res://tests/skills_runtime.gd").new()
			add_child(runner)
			runner.call_deferred("run",self,arg.trim_prefix("--skills-capture="))
		if arg.begins_with("--battle-capture="):
			var runner=load("res://tests/battle_runtime.gd").new()
			add_child(runner)
			runner.call_deferred("run",self,arg.trim_prefix("--battle-capture="))
		if arg.begins_with("--settlement-capture="):
			var test_runner=load("res://tests/settlement_runtime.gd").new()
			add_child(test_runner)
			test_runner.call_deferred("run",self,arg.trim_prefix("--settlement-capture="))
		if arg.begins_with("--capture="):
			capture_mode=true
			var runner=load("res://tests/runtime_check.gd").new()
			add_child(runner)
			runner.call_deferred("run",self,arg.trim_prefix("--capture="))

func load_map() -> void:
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/map_data.json"))
	for chunk in source.chunks:
		var sprite=Sprite2D.new()
		sprite.texture=load("res://assets/maps/"+chunk.background_path)
		sprite.centered=false
		sprite.position=Vector2(float(chunk.global_position.x),float(chunk.global_position.y))
		add_child(sprite)

func make_style(fill: Color,border: Color,width: float=1.0,roundness: float=4.0) -> StyleBoxFlat:
	var style=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=border
	style.set_border_width_all(int(ceil(width)))
	style.set_corner_radius_all(int(roundness))
	style.anti_aliasing=true
	return style

func refresh() -> void:
	economy_income=world.economy.income(world.by_poi)
	world_view_dirty=true
	if interior!=null:
		interior.invalidate_economy_cache()
		interior.queue_redraw()
	var u: Dictionary=world.units[selected_unit]
	reachable=world.search(int(u.cell),int(u.ap),u.id)
	path.clear()
	path_cost=0
	if layer!=null: layer.queue_redraw()
	if hud!=null: hud.queue_redraw()

func say(message: String) -> void:
	toast=message
	toast_time=5.0
	world_view_dirty=true
	if hud!=null: hud.queue_redraw()
	if interior!=null and interior.visible: interior.queue_redraw()

func _process(delta: float) -> void:
	if is_instance_valid(battle): return
	if toast_time>0:
		toast_time-=delta
		if toast_time<=0:
			toast=""
			world_view_dirty=true
			if interior.visible: interior.queue_redraw()
	# Interior changes invalidate their own canvas through input / refresh.
	# The covered world has no visible animation or hover state to redraw.
	if interior.visible: return
	if is_map_casting(): _advance_map_cast(delta)
	if not moving and not interior.visible:
		var pan=Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): pan.y-=1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): pan.y+=1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): pan.x-=1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): pan.x+=1
		if pan!=Vector2.ZERO: camera.position+=pan.normalized()*delta*780/camera.zoom
	clamp_camera()
	if moving:
		world_view_dirty=true
	if camera.position!=last_camera_position or camera.zoom!=last_camera_zoom:
		world_view_dirty=true
		last_camera_position=camera.position
		last_camera_zoom=camera.zoom
	if world_view_dirty:
		for i in unit_nodes.size(): unit_nodes[i].z_index=5 if i!=selected_unit else 6
		layer.queue_redraw()
		hud.queue_redraw()
		world_view_dirty=false

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(battle):
		battle.handle_input(event)
		get_viewport().set_input_as_handled()
		return
	if interior.visible:
		interior.handle_input(event)
		return
	if is_map_casting(): return
	world_view_dirty=true
	if event is InputEventMouseMotion:
		last_mouse=event.position
		var hit: Dictionary=hud.hit_test(event.position)
		hud.hovered=str(hit.get("id",""))
		if dragging:
			drag_distance=maxf(drag_distance,event.position.distance_to(drag_origin))
			if drag_distance>5:
				camera.position-=event.relative/camera.zoom
				clamp_camera()
			hover_cell=-1
		else: hover_cell=map_cell_at_screen(event.position) if hit.is_empty() else -1
		if map_skill_targeting: update_skill_preview()
	elif event is InputEventMouseButton:
		last_mouse=event.position
		var hit: Dictionary=hud.hit_test(event.position)
		if map_skill_targeting and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_map_skill()
			return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			if hit.is_empty(): zoom_at(event.position,1.13 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.13)
			return
		if event.button_index in [MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
			if event.pressed and hit.is_empty():
				dragging=true
				drag_origin=event.position
				drag_distance=0
				drag_button=event.button_index
			elif not event.pressed and dragging:
				dragging=false
				if drag_distance<5 and drag_button==MOUSE_BUTTON_RIGHT and not moving:
					var enemy:=unit_at_screen(event.position)
					if enemy>=0 and world.faction(world.units[enemy])!=world.faction(world.units[selected_unit]):
						start_field_battle(enemy)
						return
					choose_cell(world.cell_at(screen_to_world(event.position)))
					if path.size()>1: execute_move()
			return
		if event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			if not hit.is_empty():
				if bool(hit.get("enabled",false)): action(str(hit.id),event.position)
				return
			if moving: return
			var wp=screen_to_world(event.position)
			if map_skill_targeting:
				cast_selected_map_skill(map_cell_at_screen(event.position))
				return
			var badge: int=layer.badge_at_screen(event.position)
			if badge>=0:
				select_unit(badge,false)
				return
			for i in unit_nodes.size():
				var army: Sprite2D=unit_nodes[i].get_node("Soldiers")
				if world.cell_at(wp)==int(world.units[i].cell) or army.contains_formation_point(army.to_local(wp)):
					select_unit(i,false)
					return
			var poi=poi_at(wp)
			if not poi.is_empty():
				selected_poi=poi
				path.clear()
				var p: Dictionary=world.by_poi[poi]
				say(p.name+" · "+("已属我方，可以通行" if p.owner=="player" else "先行军至相邻地块，再占领"))
				open_settlement(poi)
			else:
				selected_poi=""
				choose_cell(world.cell_at(wp))
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_G: action("grid")
			KEY_F: action("overview")
			KEY_SPACE: action("focus")
			KEY_ENTER: action("move")
			KEY_E: action("end_turn")
			KEY_C: action("capture")
			KEY_B: action("battle_demo")
			KEY_Q: action("map_skill")
			KEY_ESCAPE:
				if not moving:
					cancel_map_skill()
					path.clear()
					selected_poi=""
			KEY_F3: terrain_overlay.visible=not terrain_overlay.visible
			KEY_F5: action("save")
			KEY_F9: action("load")
			KEY_1: select_unit(0)
			KEY_2: select_unit(1)
			KEY_3: select_unit(2)

func poi_at(wp: Vector2) -> String:
	var closest=""
	var best=INF
	for p in world.pois:
		var pos=Vector2(p.position[0],p.position[1])
		var half=Vector2(p.half_size[0],p.half_size[1])
		var rect=Rect2(pos-half,half*2).grow(15)
		var label_pos=pos+Vector2(0,-(95 if p.type=="city" else 35))/camera.zoom
		if rect.has_point(wp) or Rect2(label_pos-Vector2(65,26)/camera.zoom,Vector2(130,36)/camera.zoom).has_point(wp):
			var dist=wp.distance_to(pos)
			if dist<best:
				best=dist
				closest=p.id
	return closest

func choose_cell(ci: int) -> void:
	world_view_dirty=true
	if ci<0: return
	var u: Dictionary=world.units[selected_unit]
	if not world.walkable(ci,world.faction(u)):
		path.clear()
		say(world.reason(ci))
		if not str(world.cells[ci].p).is_empty(): selected_poi=world.cells[ci].p
		return
	if world.occupied(ci,u.id):
		say("此处已有我方部队驻扎")
		return
	if reachable.dist.has(ci):
		path=world.route(reachable,ci)
		path_cost=int(reachable.dist[ci])
		if path.size()>1: say("路线已标出 · 点击移动或按 Enter 下达军令")
	else:
		path.clear()
		var distant=world.search(int(u.cell),99999,u.id,ci)
		if distant.dist.has(ci): say("目标超出本回合行动力 · 当前可行军 %d 点" % int(u.ap))
		else: say("无法到达 · 途中有山水阻隔或尚未占领的据点")

func action(id: String,mouse: Vector2=Vector2.ZERO) -> void:
	if is_instance_valid(battle): return
	if is_map_casting(): return
	if id=="commander_skill:map": id="map_skill"
	if world.test_scenario and id in ["save","load","capture"]: return
	if map_skill_targeting and not id in ["map_skill","focus","overview","grid","minimap","panel"]:
		cancel_map_skill()
	world_view_dirty=true
	if id.begins_with("region:"):
		for r in world.regions:
			if r.id==id.trim_prefix("region:"):
				camera.position=Vector2(r.center[0],r.center[1])
				set_map_zoom(.28)
		return
	if id.begins_with("unit:"):
		select_unit(int(id.trim_prefix("unit:")))
		return
	match id:
		"map_skill": toggle_map_skill()
		"battle_demo": start_exhibition()
		"capital": open_settlement(world.theme.capital)
		"interior": open_settlement(selected_poi)
		"minimap":
			camera.position=world.bounds.position+(mouse-hud.MINI.position)/hud.MINI.size*world.bounds.size
			if camera.zoom.x<.2: set_map_zoom(.5)
		"grid":
			grid_visible=not grid_visible
			grid.visible=grid_visible
		"overview":
			camera.position=world.bounds.get_center()
			set_map_zoom(.085)
		"focus":
			camera.position=unit_nodes[selected_unit].position+Vector2(70,100)
			set_map_zoom(.50)
		"move":
			if not moving: execute_move()
		"capture":
			if moving or selected_poi.is_empty(): return
			var p: Dictionary=world.by_poi[selected_poi]
			if p.owner=="shang":
				var encounter: Dictionary=world.begin_battle(world.units[selected_unit],p)
				if encounter.is_empty(): say("须有兵力、相邻陆地和 1 点行动力才能接战")
				else: open_battle(encounter)
				return
			if world.capture(world.units[selected_unit],p):
				refresh()
				say(p.name+"已归西岐 · "+("两岸航线已开放" if p.type=="ferry" else "我方通行已开放"))
			else: say("需要先到达据点相邻的陆地，并保留 1 点行动力")
		"approach": approach_selected()
		"guard":
			if moving: return
			world.units[selected_unit].guarding=true
			world.units[selected_unit].ap=0
			refresh()
			say("部队就地驻守 · 下回合恢复行动力")
		"end_turn":
			if moving: return
			world.next_turn()
			refresh()
			say("第 %d 回合 · 资源已入库，%d 项工程竣工" % [world.turn,world.economy.last_report.completed.size()])
		"save":
			if moving: say("行军结束后即可存档")
			else: say("战局已保存" if world.save_game()==OK else "存档失败，请检查用户目录")
		"load":
			if moving: return
			if world.load_game():
				for i in unit_nodes.size(): unit_nodes[i].position=world.center(int(world.units[i].cell))
				refresh()
				action("focus")
				say("已恢复战局")
			else: say("尚无可读取的战局存档")

func approach_selected() -> void:
	if moving or is_map_casting() or selected_poi.is_empty(): return
	var u: Dictionary=world.units[selected_unit]
	var p: Dictionary=world.by_poi[selected_poi]
	if world.can_capture(u,p):
		say("已到达相邻位置 · 可直接占领")
		return
	var result=world.search(int(u.cell),99999,u.id)
	var best: int=-1
	var best_cost: int=999999
	for b in p.cells:
		for a in world.cells[int(b)].n:
			var ai=int(a)
			if not result.dist.has(ai): continue
			var probe: Dictionary=u.duplicate()
			probe.cell=ai
			probe.ap=1
			if world.can_capture(probe,p) and int(result.dist[ai])<best_cost:
				best=ai
				best_cost=int(result.dist[ai])
	if best<0:
		say("附近道路尚未打通 · 请先占领沿途关津")
		return
	var full: Array[int]=world.route(result,best)
	path.clear()
	path_cost=0
	path.append(int(u.cell))
	for i in range(1,full.size()):
		var cost=world.edge_cost(full[i-1],full[i],u.id)
		if path_cost+cost>int(u.ap): break
		path.append(full[i])
		path_cost+=cost
	say("已规划到据点附近的路线" if best_cost<=int(u.ap) else "目标较远 · 已标出本回合可行军路段")

func execute_move() -> void:
	if is_instance_valid(battle) or moving or is_map_casting() or path.size()<2: return
	var u: Dictionary=world.units[selected_unit]
	var planned: Array[int]=path.duplicate()
	var total: int=0
	if planned[0]!=int(u.cell):
		refresh()
		return
	for i in range(1,planned.size()):
		var cost=world.edge_cost(planned[i-1],planned[i],u.id)
		if cost<0:
			refresh()
			say("道路通行状态已变化 · 请重新规划")
			return
		total+=cost
	if total>int(u.ap):
		say("行动力不足")
		return
	moving=true
	u.guarding=false
	reachable={"dist":{}}
	var node: Node2D=unit_nodes[selected_unit]
	for i in range(1,planned.size()):
		var next: int=planned[i]
		# Ownership and occupancy are checked again before every step.
		var cost=world.edge_cost(int(u.cell),next,u.id)
		if cost<0 or cost>int(u.ap):
			say("前路已封锁 · 行军中止")
			break
		var ferry=world.ferry_between(int(u.cell),next)
		var sprite: Sprite2D=node.get_node("Soldiers")
		sprite.flip_h=(world.center(next).x<node.position.x)!=(world.faction(u)=="shang")
		if not ferry.is_empty():
			say("经由 "+world.by_poi[ferry].name+" 乘舟过河")
			sprite.modulate=Color(.8,.94,1,1)
			node.get_node("Boat").visible=true
		var tween=create_tween()
		tween.tween_property(node,"position",world.center(next),(1.15 if not ferry.is_empty() else .27)*travel_speed).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tween.finished
		u.cell=next
		u.ap=int(u.ap)-cost
		if not ferry.is_empty(): world.crossed+=1
		sprite.modulate=Color.WHITE
		node.get_node("Boat").visible=false
		path.pop_front()
	moving=false
	refresh()
	say("部队已抵达 · 剩余 %d 点行动力" % int(u.ap))

func select_unit(index: int,focus: bool=true) -> void:
	if is_instance_valid(battle) or moving or is_map_casting() or index<0 or index>=world.units.size(): return
	cancel_map_skill()
	selected_unit=index
	selected_poi=""
	refresh()
	if focus: action("focus")

func screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse()*p

func map_cell_at_screen(p: Vector2) -> int:
	var badge: int=layer.badge_at_screen(p)
	if badge>=0:
		return int(world.units[badge].cell) if map_skill_targeting else -1
	return world.cell_at(screen_to_world(p))

func set_map_zoom(amount: float) -> void:
	# The artwork, buildings and actors retain their original proportions.
	# Only the grid geometry is projected, in World.center / World.hex_at.
	camera.zoom=Vector2.ONE*amount

func world_to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform()*p

func visible_world() -> Rect2:
	return Rect2(camera.position-Vector2(1920,1080)/camera.zoom/2,Vector2(1920,1080)/camera.zoom)

func clamp_camera() -> void:
	camera.position.x=clampf(camera.position.x,world.bounds.position.x,world.bounds.end.x)
	camera.position.y=clampf(camera.position.y,world.bounds.position.y,world.bounds.end.y)

func zoom_at(point: Vector2,factor: float) -> void:
	var before=screen_to_world(point)
	set_map_zoom(clampf(camera.zoom.x*factor,.075,1.4))
	camera.force_update_scroll()
	var after=screen_to_world(point)
	camera.position+=before-after
	clamp_camera()

func current_region() -> String:
	var best="wanluo"
	var dist=INF
	for r in world.regions:
		var d=camera.position.distance_to(Vector2(r.center[0],r.center[1]))
		if d<dist:
			dist=d
			best=r.id
	return best

func cover_world(covered: bool) -> void:
	if covered:
		if not covered_world_visibility.is_empty(): return
		for child in get_children():
			if child is CanvasItem and child!=camera:
				covered_world_visibility[child]=child.visible
				child.hide()
	else:
		for item in covered_world_visibility:
			if is_instance_valid(item): item.visible=covered_world_visibility[item]
		covered_world_visibility.clear()

func open_settlement(pid: String) -> void:
	if is_instance_valid(battle) or moving or is_map_casting() or not world.by_poi.has(pid): return
	cancel_map_skill()
	selected_poi=pid
	dragging=false
	hover_cell=-1
	path.clear()
	cover_world(true)
	hud.hide()
	interior.open(pid)

func close_settlement() -> void:
	interior.hide()
	cover_world(false)
	hud.show()
	refresh()

func start_exhibition() -> void:
	if moving or is_map_casting() or is_instance_valid(battle): return
	if world.test_scenario:
		start_field_battle(1-selected_unit)
		return
	var player: Dictionary=world.units[selected_unit].duplicate(true)
	player.soldiers=2400
	player.troops=world.BattleRules.mixed_roster(2400)
	player.morale=50
	open_battle({"exhibition":true,"title":"岐山 · 三军演武","player":player,"enemy":{"id":"wenzhong","name":"闻仲","soldiers":2200,"troops":world.BattleRules.mixed_roster(2200),"morale":50}})

func unit_at_screen(point: Vector2) -> int:
	var badge:=int(layer.badge_at_screen(point))
	if badge>=0: return badge
	var wp:=screen_to_world(point)
	for i in unit_nodes.size():
		var army: Sprite2D=unit_nodes[i].get_node("Soldiers")
		if world.cell_at(wp)==int(world.units[i].cell) or army.contains_formation_point(army.to_local(wp)): return i
	return -1

func start_field_battle(index: int) -> void:
	if moving or is_map_casting() or is_instance_valid(battle) or index<0 or index>=world.units.size(): return
	var unit: Dictionary=world.units[selected_unit]
	var enemy: Dictionary=world.units[index]
	var encounter:=world.begin_field_battle(unit,enemy)
	if encounter.is_empty():
		say(world.field_battle_reason(unit,enemy))
		return
	open_battle(encounter)

func open_battle(encounter: Dictionary) -> void:
	if is_map_casting(): return
	cancel_map_skill()
	dragging=false
	path.clear()
	hover_cell=-1
	cover_world(true)
	interior.hide()
	hud.hide()
	battle=BattleView.new()
	battle.setup(encounter)
	battle.returned.connect(close_battle)
	battle_canvas.add_child(battle)
	battle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func close_battle(result: Dictionary) -> void:
	if not is_instance_valid(battle): return
	var exhibition: bool=battle.sim.encounter.get("exhibition",false)
	var field: bool=battle.sim.encounter.get("kind","")=="field"
	if not exhibition and not world.finish_battle(result):
		push_error("Battle result could not be applied")
		return
	battle.queue_free()
	battle=null
	cover_world(false)
	hud.show()
	refresh()
	say("双方战损已结算 · 结束回合可继续测试" if field and world.test_scenario else ("演武结束 · 实际兵力与士气保持不变" if exhibition else ("攻城告捷 · 兵损与士气已结算" if result.player_won else "败退原阵 · 补兵整军后可再次进攻")))

func toggle_map_skill() -> void:
	if moving or is_map_casting() or is_instance_valid(battle) or interior.visible: return
	if map_skill_targeting:
		cancel_map_skill()
		return
	var unit: Dictionary=world.units[selected_unit]
	var reason_text:=world.map_skill_ready_reason(unit)
	if not reason_text.is_empty():
		say(reason_text)
		return
	var ability:=world.map_skill(unit)
	map_skill_targeting=true
	path.clear()
	skill_range_cells=world.search(int(unit.cell),int(ability.march_range),unit.id).dist.keys() if ability.effect=="march" else world.hex_disk(int(unit.cell),int(ability.range))
	update_skill_preview()
	say(ability.name+" · 左键选择目标，右键 / Esc 取消")

func cancel_map_skill() -> void:
	map_skill_targeting=false
	skill_range_cells.clear()
	skill_preview.clear()
	world_view_dirty=true
	if layer!=null: layer.queue_redraw()
	if hud!=null: hud.queue_redraw()

func update_skill_preview() -> void:
	var unit: Dictionary=world.units[selected_unit]
	skill_preview=world.map_skill_targets(unit,hover_cell)
	skill_preview.reason=world.map_skill_reason(unit,hover_cell)
	world_view_dirty=true

func cast_selected_map_skill(target: int) -> void:
	if moving or is_map_casting() or not map_skill_targeting: return
	var unit: Dictionary=world.units[selected_unit]
	var reason_text:=world.map_skill_reason(unit,target)
	if not reason_text.is_empty():
		say(reason_text)
		return
	if world.Catalog.hero_id(unit) in ["nezha","wenzhong"]:
		map_cast={"unit":selected_unit,"target":target,"origin":unit_nodes[selected_unit].position,"position":world.center(target),"age":0.0,"resolved":false,"cells":world.map_skill_targets(unit,target).cells}
		unit_nodes[selected_unit].get_node("Soldiers").hide()
		dragging=false
		hover_cell=-1
		cancel_map_skill()
		path.clear()
		say(str(world.map_skill(unit).name)+" · 施法中")
		return
	_complete_map_skill(world.cast_map_skill(unit,target))

func is_map_casting() -> bool:
	return not map_cast.is_empty()

func _advance_map_cast(delta: float) -> void:
	map_cast.age+=delta
	world_view_dirty=true
	if not map_cast.resolved and map_cast.age>=MAP_CAST_IMPACT:
		map_cast.resolved=true
		_complete_map_skill(world.cast_map_skill(world.units[int(map_cast.unit)],int(map_cast.target)))
	if map_cast.age>=MAP_CAST_END:
		unit_nodes[int(map_cast.unit)].get_node("Soldiers").show()
		map_cast.clear()
		refresh()

func _complete_map_skill(result: Dictionary) -> void:
	if not result.ok:
		say(result.reason)
		return
	for i in unit_nodes.size(): unit_nodes[i].position=world.center(int(world.units[i].cell))
	cancel_map_skill()
	refresh()
	var suffix: String=" · 恢复 %d 人" % result.amount if result.effect=="heal" else (" · 杀伤 %d 人" % result.amount if result.effect=="aoe" else "")
	say(result.skill+suffix+" · 本轮行动结束")
