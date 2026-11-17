extends Node2D
const NezhaArt=preload("res://scripts/nezha_art.gd")
const Portraits=preload("res://scripts/map_portraits.gd")
const Tactics=preload("res://scripts/map_tactics.gd")
var effect_age:=0.0
var effect_tick:=-1
var unit_badges: Array[Dictionary]=[]
var foreground_only:=false
var foreground: Node2D
var game: Node2D
var font: Font = preload("res://assets/fonts/ShanheSerif.otf")
var small_font: Font = preload("res://assets/fonts/ShanheSans.otf")
var debug_mask: Sprite2D
const GOLD=Color("f5d278")
const CYAN=Color("81e2ee")

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if foreground_only:
		z_as_relative=false
		z_index=8
	else:
		z_index=3
		foreground=get_script().new()
		foreground.game=game
		foreground.foreground_only=true
		foreground.unit_badges=unit_badges
		add_child(foreground)

func hexagon(c: Vector2, r: float) -> PackedVector2Array:
	return Tactics.hexagon(game.world,c,r)

func _process(delta: float) -> void:
	if foreground_only or game==null or not is_visible_in_tree(): return
	effect_age+=delta
	var tick:=int(effect_age*30)
	if tick!=effect_tick and (game.path.size()>1 or game.map_skill_targeting):
		effect_tick=tick
		queue_redraw()

func _draw() -> void:
	if game==null: return
	if foreground_only:
		_draw_foreground()
		return
	Tactics.draw_ground(self,game,effect_age)
	foreground.queue_redraw()

func _draw_foreground() -> void:
	var w: ShanheWorld=game.world
	var zoom: float=game.camera.zoom.x
	var u: Dictionary=w.units[game.selected_unit]
	if zoom>.16 and game.map_skill_targeting and game.hover_cell>=0:
		var can: bool=game.skill_preview.get("reason","").is_empty()
		label_at(w.center(game.hover_cell)+Vector2(0,-80)/game.camera.zoom,str(w.map_skill(u).name)+(" · 可释放" if can else " · 无效目标"),GOLD if can else Color("e58d7c"),zoom,18,true)
	if game.path.size()>1:
		Tactics.draw_destination_pin(self,game)
		label_at(w.center(game.path[-1])+Vector2(0,55)/game.camera.zoom,"行军  %d / %d" %[game.path_cost,int(u.ap)],GOLD,zoom,16)
	if zoom<0.16:
		for r in w.regions:
			var pos=Vector2(r.center[0],r.center[1])
			label_at(pos,r.name,Color("fff1cf"),zoom,26)
	else:
		for p in w.pois:
			if w.test_scenario and p.id!=w.test_city_id: continue
			if p.type=="village" and zoom<0.38: continue
			if p.type=="ferry" and zoom<0.27: continue
			var pos=Vector2(p.position[0],p.position[1])
			if not game.visible_world().grow(180).has_point(pos): continue
			var col=Color("f3ce7c") if p.owner=="player" else Color("d8b3d6") if p.owner=="shang" else Color("e9e0bf")
			var off: float=95 if p.type=="city" else 35
			var prefix="西  " if p.owner=="player" else "商  " if p.owner=="shang" else "◇  "
			label_at(pos+Vector2(100 if p.id==game.selected_poi and p.type=="ferry" else 0,-off)/game.camera.zoom,prefix+p.name,col,zoom,17 if p.type=="city" else 14,p.id==game.selected_poi)
	if game.is_map_casting(): _draw_map_cast(zoom)
	_draw_unit_badges(zoom)

func badge_at_screen(point: Vector2) -> int:
	for i in range(unit_badges.size()-1,-1,-1):
		if unit_badges[i].rect.has_point(point): return int(unit_badges[i].unit)
	return -1

func _draw_unit_badges(zoom: float) -> void:
	unit_badges.clear()
	if zoom<.16: return
	var order: Array[int]=[game.selected_unit]
	for i in game.world.units.size():
		if i!=game.selected_unit: order.append(i)
	var badge_scale:=clampf(sqrt(zoom/.5),.82,1.08)
	var clear_area:=Rect2(340,24,1552,1028)
	var end_turn:=Rect2(1712,899,156,156)
	for i in order:
		var at: Vector2=game.world_to_screen(game.unit_nodes[i].position)
		if not clear_area.grow(100).has_point(at): continue
		var cast: bool=game.is_map_casting() and int(game.map_cast.unit)==i
		var army=game.unit_nodes[i].get_node("Soldiers")
		var above: float=(184.0 if cast else army.badge_clearance()*zoom)+48.0*badge_scale
		var offsets: Array[Vector2]=[Vector2(-28,-above),Vector2(-164,-above),Vector2(-28,-above-58*badge_scale),Vector2(40,-above+44*badge_scale),Vector2(-164,-above-58*badge_scale)]
		# Search additional rows near the army when several adjacent units cluster.
		for row in range(1,6):
			for direction in [-1,1]:
				for column in [0,-1,1,-2,2]:
					offsets.append(Vector2(-28+column*186*badge_scale,-above+direction*row*58*badge_scale))
		var rect:=Rect2(at+offsets[0],Vector2(176,48)*badge_scale)
		for offset in offsets:
			var candidate:=Rect2(at+offset,rect.size)
			candidate.position.x=clampf(candidate.position.x,clear_area.position.x,clear_area.end.x-candidate.size.x)
			candidate.position.y=clampf(candidate.position.y,clear_area.position.y,clear_area.end.y-candidate.size.y)
			if candidate.intersects(end_turn): continue
			var overlaps:=false
			for existing in unit_badges:
				if candidate.grow(5).intersects(existing.rect): overlaps=true; break
			rect=candidate
			if not overlaps: break
		unit_badges.append({"unit":i,"rect":rect,"anchor":at,"scale":badge_scale,"soldiers":int(game.world.units[i].soldiers)})
	unit_badges.reverse()
	for badge in unit_badges: _draw_unit_badge(badge)

func _draw_unit_badge(badge: Dictionary) -> void:
	var i:=int(badge.unit)
	var unit: Dictionary=game.world.units[i]
	var selected: bool=i==game.selected_unit
	var accent:=GOLD if selected else (Color("cf96df") if game.world.faction(unit)=="shang" else Color("7dbacf"))
	var rect: Rect2=badge.rect
	var scale_factor: float=badge.scale
	draw_set_transform(game.screen_to_world(rect.position),0,Vector2.ONE/game.camera.zoom*scale_factor)
	var shape:=PackedVector2Array([Vector2(24,3),Vector2(176,3),Vector2(167,45),Vector2(24,45)])
	var colors:=PackedColorArray([Color(.06,.13,.17,.96),Color(.06,.13,.17,.65),Color(.06,.13,.17,.65),Color(.06,.13,.17,.96)])
	draw_polygon(shape,colors)
	draw_line(Vector2(43,3),Vector2(175,3),Color(accent,.85),1,true)
	draw_line(Vector2(44,25),Vector2(171,25),Color(accent,.4),1,true)
	draw_line(Vector2(43,45),Vector2(167,45),Color(accent,.7),1,true)
	draw_circle(Vector2(24,24),25,Color(.025,.05,.07,.95))
	Portraits.draw_circle_portrait(self,game.world.Catalog.hero_id(unit),Vector2(24,24),21.5)
	draw_arc(Vector2(24,24),24,0,TAU,64,accent,2.6,true)
	draw_arc(Vector2(24,24),21.5,0,TAU,64,Color("e3d5b1"),.8,true)
	draw_string_outline(font,Vector2(55,21),unit.name,HORIZONTAL_ALIGNMENT_LEFT,116,18,3,Color(.03,.05,.07,.8))
	draw_string(font,Vector2(55,21),unit.name,HORIZONTAL_ALIGNMENT_LEFT,116,18,Color("fff0cf"))
	draw_string(small_font,Vector2(55,42),str(int(unit.soldiers)),HORIZONTAL_ALIGNMENT_LEFT,116,20,Color("f8f5e7"))
	var strength:=clampf(float(unit.soldiers)/maxf(1,float(unit.max_soldiers)),0,1)
	draw_rect(Rect2(54,47,110,2),Color(.04,.08,.1,.65))
	draw_rect(Rect2(54,47,110*strength,2),accent)
	draw_set_transform(Vector2.ZERO)

func _draw_map_cast(zoom: float) -> void:
	var cast: Dictionary=game.map_cast
	var age: float=cast.age
	var facing:=1 if cast.position.x>=cast.origin.x else -1
	NezhaArt.draw(self,"fire_field" if age<NezhaArt.duration("fire_field") else "idle",age if age<NezhaArt.duration("fire_field") else 0.0,cast.origin,170.0/zoom,facing,Color.WHITE)
	var effect_time: float=age-game.MAP_CAST_RELEASE
	if effect_time>=0 and effect_time<NezhaArt.duration("fire_field_fx"):
		NezhaArt.draw(self,"fire_field_fx",effect_time,cast.position+Vector2(0,35)/game.camera.zoom,maxf(280.0/zoom,game.world.radius*5.0),1,Color.WHITE)

func label_at(pos: Vector2, text: String, color: Color, zoom: float, size: int=18, active: bool=false) -> void:
	var width: float=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	draw_set_transform(pos,0,Vector2.ONE/game.camera.zoom)
	var rect:=Rect2(-Vector2(width/2+12,23),Vector2(width+24,32))
	draw_style_box(game.make_style(Color(0.13,0.105,0.09,0.88),color if active else Color(0.65,0.52,0.31,0.7),1,3),rect)
	draw_string(font,Vector2(-width/2,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
	draw_set_transform(Vector2.ZERO)
