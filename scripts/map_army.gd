extends Sprite2D
## Ground slots follow the map projection; the soldiers and flag stay upright.
const SOLDIER=preload("res://assets/battle/halberdiers/zhou.png")
const ENEMY_SOLDIER=preload("res://assets/battle/halberdiers/shang.png")
const FONT=preload("res://assets/fonts/ShanheSerif.otf")
const FORMATION_SCALE:=.45
static var atlas: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/battle_frames.json")).zhou
static var enemy_atlas: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/battle_frames.json")).shang
var game: Node2D
var unit_index:=0
var clock:=0.0
var last_frame:=-1
var last_selected:=false
var last_people:=-1
var hit_frames: Array[Dictionary]=[]
static var pixels: Image
static var enemy_pixels: Image

func enemy_army() -> bool:
	return game.world.faction(game.world.units[unit_index])=="shang"

func _init() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func formation_scale() -> float:
	return FORMATION_SCALE*game.world.radius/80.0

func resting_height() -> float:
	return -game.world.radius*.175 if get_parent().get_node("Boat").visible else game.world.radius*.5

func badge_clearance() -> float:
	var boat: bool=get_parent().get_node("Boat").visible
	return (165.0+(32.0 if boat else 72.0)*game.world.grid_y_scale)*formation_scale()*(.72 if boat else 1.0)-resting_height()+8.0

func _process(delta: float) -> void:
	if game==null or not is_visible_in_tree(): return
	clock+=delta
	var marching: bool=game.moving and game.selected_unit==unit_index
	var boat: bool=get_parent().get_node("Boat").visible
	# Keep the full formation centered over its tile in both idle and movement.
	scale=Vector2.ONE*formation_scale()*(.72 if boat else 1.0)
	position.y=resting_height()+(sin(clock*16.0)*2.8*formation_scale() if marching else 0.0)
	var tick:=int(clock*(10 if marching else 3))
	var selected: bool=game.selected_unit==unit_index
	var people:=int(game.world.units[unit_index].soldiers)
	if tick!=last_frame or selected!=last_selected or people!=last_people:
		last_frame=tick
		last_selected=selected
		last_people=people
		queue_redraw()

func contains_formation_point(point: Vector2) -> bool:
	if not Rect2(-180,-350,360,370).has_point(point): return false
	var boat: bool=get_parent().get_node("Boat").visible
	var banner: Vector2=point-Vector2(-92,(-32 if boat else -72)*game.world.grid_y_scale)
	if Rect2(0,-158,68,60).has_point(banner) or Rect2(-4,-158,8,158).has_point(banner): return true
	if pixels==null: pixels=SOLDIER.get_image()
	if enemy_army() and enemy_pixels==null: enemy_pixels=ENEMY_SOLDIER.get_image()
	var image: Image=enemy_pixels if enemy_army() else pixels
	for frame in hit_frames:
		var local: Vector2=(point-frame.slot)*Vector2(-1 if flip_h else 1,1)/float(frame.ratio)+frame.pivot
		var source: Rect2=frame.source
		if Rect2(Vector2.ZERO,source.size).has_point(local):
			var texel:=Vector2i(source.position+local)
			if image.get_pixelv(texel).a>.2: return true
	return false

func ellipse(at: Vector2, radius: Vector2, color: Color) -> void:
	var points:=PackedVector2Array()
	for i in 24: points.append(at+Vector2.from_angle(i*TAU/24)*radius)
	draw_colored_polygon(points,color)

func _draw() -> void:
	if game==null: return
	hit_frames.clear()
	var tilt: float=game.world.grid_y_scale
	var unit: Dictionary=game.world.units[unit_index]
	var source_atlas: Dictionary=enemy_atlas if enemy_army() else atlas
	var source_texture: Texture2D=ENEMY_SOLDIER if enemy_army() else SOLDIER
	var marching: bool=game.moving and game.selected_unit==unit_index
	var boat: bool=get_parent().get_node("Boat").visible
	var slots: Array[Vector2]=[]
	var columns:=4 if boat else 5
	var rows:=2 if boat else 4
	for row in rows:
		for col in columns:
			slots.append(Vector2((col-row-(columns-rows)*.5)*32,(col+row-(columns+rows-2))*24*tilt))
	slots.sort_custom(func(a: Vector2,b: Vector2)->bool: return a.y<b.y)
	var count:=clampi(ceili(slots.size()*float(unit.soldiers)/maxf(1,float(unit.max_soldiers))),0,slots.size())
	var ratio:=88.0/float(source_atlas.body_height)
	for i in count:
		var slot:=slots[roundi(i*(slots.size()-1)/float(maxi(1,count-1)))]
		ellipse(slot+Vector2(0,2),Vector2(13,6),Color(.10,.12,.08,.23))
		var index: int=(4 if marching else 0)+(int(clock*(10 if marching else 3))+i)%4
		var frame: Dictionary=source_atlas.frames[index]
		var src:=Rect2(frame.source[0],frame.source[1],frame.source[2],frame.source[3])
		var pivot:=Vector2(frame.pivot[0],frame.pivot[1])
		hit_frames.append({"slot":slot,"ratio":ratio,"source":src,"pivot":pivot})
		draw_set_transform(slot,0,Vector2(-1 if flip_h else 1,1))
		draw_texture_rect_region(source_texture,Rect2(-pivot*ratio,src.size*ratio),src)
		draw_set_transform(Vector2.ZERO)
	# One army banner, behind the commander badge; never mirrored text.
	draw_set_transform(Vector2(-92,(-72 if not boat else -32)*tilt))
	draw_line(Vector2.ZERO,Vector2(0,-158),Color("5b4229"),5,true)
	draw_line(Vector2(-1,0),Vector2(-1,-158),Color("d7c08b"),1.5,true)
	var wave:=sin(clock*2.4)*3.0
	var flag:=PackedVector2Array([Vector2(3,-153),Vector2(68,-146+wave),Vector2(61,-98+wave),Vector2(3,-104)])
	draw_colored_polygon(flag,Color("65426f") if enemy_army() else Color("245b79"))
	flag.append(flag[0])
	draw_polyline(flag,Color("dabd7d"),2,true)
	draw_string(FONT,Vector2(18,-115),"商" if enemy_army() else "周",HORIZONTAL_ALIGNMENT_LEFT,-1,34,Color("f2e8c5"))
	draw_circle(Vector2(0,-161),4,Color("e7c987"))
	draw_set_transform(Vector2.ZERO)
