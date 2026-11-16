extends Node2D
var game: Node2D
var font: Font = preload("res://assets/fonts/ShanheSerif.otf")
var small_font: Font = preload("res://assets/fonts/ShanheSans.otf")
var debug_mask: Sprite2D
const GOLD=Color("f5d278")
const CYAN=Color("81e2ee")

func _ready() -> void:
	z_index=3

func hexagon(c: Vector2, r: float) -> PackedVector2Array:
	var pts=PackedVector2Array()
	for i in 6:
		pts.append(c+Vector2.from_angle(deg_to_rad(60*i-30))*r)
	return pts

func _draw() -> void:
	if game==null: return
	var w: ShanheWorld=game.world
	var zoom: float=game.camera.zoom.x
	var u: Dictionary=w.units[game.selected_unit]
	if zoom>0.16:
		for ci in (game.skill_range_cells if game.map_skill_targeting else game.reachable.get("dist",{})):
			if int(ci)==int(u.cell): continue
			var shape=hexagon(w.center(ci),w.radius-2)
			draw_colored_polygon(shape,Color(.90,.68,.25,.20) if game.map_skill_targeting else Color(0.25,0.82,0.92,0.16))
			shape.append(shape[0])
			draw_polyline(shape,Color(0.47,0.93,1.0,0.52),1.2/zoom,true)
		if game.hover_cell>=0:
			var can: bool=game.skill_preview.get("reason","").is_empty() if game.map_skill_targeting else game.reachable.get("dist",{}).has(game.hover_cell)
			var shape=hexagon(w.center(game.hover_cell),w.radius-1)
			draw_colored_polygon(shape,Color(0.96,0.79,0.3,0.16) if can else Color(0.85,0.21,0.15,0.2))
			shape.append(shape[0])
			draw_polyline(shape,GOLD if can else Color(0.9,0.35,0.3,0.8),1.5/zoom,true)
			if game.map_skill_targeting:
				for ci in game.skill_preview.get("cells",[]):
					var area:=hexagon(w.center(int(ci)),w.radius-3)
					draw_colored_polygon(area,Color(.97,.53,.25,.27) if can else Color(.8,.2,.2,.16))
				label_at(w.center(game.hover_cell)+Vector2(0,-80/zoom),str(w.map_skill(u).name)+(" · 可释放" if can else " · 无效目标"),GOLD if can else Color("e58d7c"),zoom,18,true)
	if game.path.size()>1:
		for i in range(1,game.path.size()):
			var a=w.center(game.path[i-1])
			var b=w.center(game.path[i])
			var ferry=not w.ferry_between(game.path[i-1],game.path[i]).is_empty()
			draw_line(a,b,Color(0.17,0.11,0.04,0.4),9/zoom,true)
			draw_line(a,b,CYAN if ferry else GOLD,3/zoom,true)
			var v=(b-a).normalized()
			var mid=a.lerp(b,0.6)
			var side=Vector2(-v.y,v.x)
			draw_polyline(PackedVector2Array([mid-v*10/zoom+side*7/zoom,mid,mid-v*10/zoom-side*7/zoom]),CYAN if ferry else GOLD,3/zoom,true)
		var end=w.center(game.path[-1])
		var pts=hexagon(end,w.radius-1)
		draw_colored_polygon(pts,Color(1,0.77,0.19,0.27))
		pts.append(pts[0])
		draw_polyline(pts,GOLD,3/zoom,true)
		label_at(end+Vector2(100/zoom,20/zoom),"行军  %d / %d" %[game.path_cost,int(u.ap)],GOLD,zoom)
	# Ferry links are visible when selected; the ground grid never makes water walkable.
	if not game.selected_poi.is_empty():
		var p: Dictionary=w.by_poi[game.selected_poi]
		if p.type=="ferry":
			var a=w.center(int(p.banks[0]))
			var b=w.center(int(p.banks[1]))
			var tint=CYAN if p.owner=="player" else Color("d7a58b")
			for i in range(0,20,2): draw_line(a.lerp(b,i/20.0),a.lerp(b,(i+1)/20.0),tint,2/zoom,true)
			for ci in p.banks: draw_arc(w.center(int(ci)),w.radius*.65,0,TAU,24,tint,2/zoom,true)
	var c: Vector2=game.unit_nodes[game.selected_unit].position
	var selected=hexagon(c,w.radius)
	draw_colored_polygon(selected,Color(1,0.76,0.17,0.18))
	selected.append(selected[0])
	draw_polyline(selected,GOLD,2.4/zoom,true)
	draw_arc(c,w.radius*.72,0,TAU,48,Color(1,0.86,0.48,0.75),1/zoom,true)
	if zoom<0.16:
		for r in w.regions:
			var pos=Vector2(r.center[0],r.center[1])
			label_at(pos,r.name,Color("fff1cf"),zoom,26)
	else:
		for p in w.pois:
			if p.type=="village" and zoom<0.38: continue
			if p.type=="ferry" and zoom<0.27: continue
			var pos=Vector2(p.position[0],p.position[1])
			if not game.visible_world().grow(180).has_point(pos): continue
			var col=Color("f3ce7c") if p.owner=="player" else Color("d8b3d6") if p.owner=="shang" else Color("e9e0bf")
			var off: float=95 if p.type=="city" else 35
			var prefix="西  " if p.owner=="player" else "商  " if p.owner=="shang" else "◇  "
			label_at(pos+Vector2(100/zoom if p.id==game.selected_poi and p.type=="ferry" else 0,-off/zoom),prefix+p.name,col,zoom,17 if p.type=="city" else 14,p.id==game.selected_poi)
	if zoom<0.16: return
	for i in w.units.size():
		var uu: Dictionary=w.units[i]
		var pos: Vector2=game.unit_nodes[i].position
		label_at(pos+Vector2(0,-287),uu.name,GOLD if i==game.selected_unit else Color("e9e0bf"),zoom,17,i==game.selected_unit)

func label_at(pos: Vector2, text: String, color: Color, zoom: float, size: int=18, active: bool=false) -> void:
	var fs: int=int(size/zoom)
	var width: float=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	var rect=Rect2(pos-Vector2(width/2+12/zoom,23/zoom),Vector2(width+24/zoom,32/zoom))
	draw_style_box(game.make_style(Color(0.13,0.105,0.09,0.88),color if active else Color(0.65,0.52,0.31,0.7),1/zoom,3/zoom),rect)
	draw_string(font,pos+Vector2(-width/2,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color)
