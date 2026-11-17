extends Control
var game: Node2D
var serif: Font=preload("res://assets/fonts/ShanheSerif.otf")
var sans: Font=preload("res://assets/fonts/ShanheSans.otf")
const NezhaArt=preload("res://scripts/nezha_art.gd")
const CommanderPanel=preload("res://scripts/commander_panel.gd")
var overview: Texture2D=preload("res://assets/maps/overview.jpg")
var army: Texture2D=preload("res://assets/units/red_army.png")
var hits: Array=[]
var hovered: String=""
var commander_formations: Array[Dictionary]=[]
var commander_tooltip: Dictionary={}
const GOLD=Color("cfb079")
const LIGHT=Color("f3dfaf")
const MUTED=Color("b5ab92")
const BG=Color(0.12,0.105,0.095,0.95)
const MINI_FRAME=Rect2(18,850,214,214)
const MINI=Rect2(24,856,202,202)

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	get_window().mouse_exited.connect(clear_hover)

func clear_hover() -> void:
	hovered=""
	commander_tooltip.clear()
	queue_redraw()

func text(s: String,p: Vector2,size: int=20,color: Color=LIGHT,font: Font=null) -> void:
	draw_string(serif if font==null else font,p,s,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func center_text(s: String,p: Vector2,size: int=20,color: Color=LIGHT,font: Font=null) -> void:
	var f: Font=serif if font==null else font
	var width: float=f.get_string_size(s,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	text(s,p-Vector2(width/2,0),size,color,f)

func rule(x: float,y: float,width: float) -> void:
	draw_line(Vector2(x,y),Vector2(x+width,y),Color(0.65,0.52,0.31,0.5),1,true)
	draw_circle(Vector2(x,y),2,GOLD)

func panel(rect: Rect2,title: String="") -> void:
	draw_style_box(game.make_style(Color(0.02,0.018,0.015,0.45),Color.TRANSPARENT,0,9),Rect2(rect.position+Vector2(4,7),rect.size))
	draw_style_box(game.make_style(BG,Color(0.75,0.61,0.39,0.9),1,7),rect)
	draw_rect(rect.grow(-5),Color(0.72,0.58,0.36,0.22),false,1)
	for sx in [0,1]:
		for sy in [0,1]:
			var c: Vector2=rect.position+Vector2(rect.size.x*sx,rect.size.y*sy)
			var d:=Vector2(1 if sx==0 else -1,1 if sy==0 else -1)
			draw_polyline(PackedVector2Array([c+Vector2(d.x*27,d.y*2),c+Vector2(d.x*10,d.y*2),c+Vector2(d.x*2,d.y*10),c+Vector2(d.x*2,d.y*27)]),GOLD,2,true)
	if not title.is_empty():
		text(title,rect.position+Vector2(20,34),22,GOLD)
		rule(rect.position.x+18,rect.position.y+48,rect.size.x-36)

func icon(kind: String,c: Vector2,col: Color=GOLD,s: float=1.0) -> void:
	var a: float=12*s
	match kind:
		"grain":
			draw_line(c+Vector2(-6,a),c+Vector2(7,-a),col,2,true)
			for i in 4:
				var p=c+Vector2(-3+i*3,8-i*6)*s
				paint_ellipse(p+Vector2(-4,-3)*s,Vector2(3,6)*s,col,-.7)
				paint_ellipse(p+Vector2(4,0)*s,Vector2(3,6)*s,col,.7)
		"wood":
			for i in 3:
				var p=c+Vector2(-7+i*7,4-i*3)*s
				draw_line(p+Vector2(-7,-6)*s,p+Vector2(6,5)*s,col,7*s,true)
				draw_circle(p+Vector2(6,5)*s,4*s,Color("aa7246"))
		"iron":
			draw_colored_polygon(PackedVector2Array([c+Vector2(-12,7)*s,c+Vector2(-6,-8)*s,c+Vector2(8,-11)*s,c+Vector2(14,4)*s,c+Vector2(3,10)*s]),col)
		"jade":
			draw_circle(c,11*s,col)
			draw_arc(c,6*s,.5,5,24,BG,3*s,true)
		"gold":
			draw_circle(c,12*s,col)
			draw_arc(c,8*s,0,TAU,24,Color("8e692e"),1*s,true)
			draw_rect(Rect2(c-Vector2(3,3)*s,Vector2(6,6)*s),BG)
		"sword","move":
			draw_line(c+Vector2(-10,12)*s,c+Vector2(11,-12)*s,col,4*s,true)
			draw_polyline(PackedVector2Array([c+Vector2(4,-12)*s,c+Vector2(14,-15)*s,c+Vector2(12,-4)*s]),col,2*s,true)
			draw_line(c+Vector2(-12,1)*s,c+Vector2(-1,12)*s,col,3*s,true)
		"flag","capture":
			draw_line(c+Vector2(-8,15)*s,c+Vector2(-8,-16)*s,col,2*s,true)
			draw_colored_polygon(PackedVector2Array([c+Vector2(-7,-15)*s,c+Vector2(13,-12)*s,c+Vector2(8,-2)*s,c+Vector2(-7,-5)*s]),col)
		"guard":
			draw_rect(Rect2(c+Vector2(-13,-8)*s,Vector2(26,23)*s),col,false,2*s)
			for i in 3: draw_rect(Rect2(c+Vector2(-13+i*10,-14)*s,Vector2(6,9)*s),col)
			draw_arc(c+Vector2(0,13)*s,5*s,PI,TAU,12,col,2*s,true)
		"grid":
			var pts=PackedVector2Array()
			for i in 7: pts.append(c+Vector2.from_angle(i*PI/3-PI/6)*13*s)
			draw_polyline(pts,col,2*s,true)
		"ferry":
			draw_polyline(PackedVector2Array([c+Vector2(-16,1)*s,c+Vector2(-9,10)*s,c+Vector2(10,10)*s,c+Vector2(16,1)*s,c+Vector2(-16,1)*s]),col,2*s,true)
			draw_line(c+Vector2(1,1)*s,c+Vector2(1,-15)*s,col,2*s,true)
			draw_colored_polygon(PackedVector2Array([c+Vector2(3,-15)*s,c+Vector2(12,-3)*s,c+Vector2(3,-3)*s]),col)
		"sun":
			draw_arc(c,8*s,0,TAU,24,col,2*s,true)
			for i in 8: draw_line(c+Vector2.from_angle(i*PI/4)*11*s,c+Vector2.from_angle(i*PI/4)*16*s,col,2*s,true)
		_:
			draw_arc(c,12*s,0,TAU,24,col,2*s,true)
			text("·",c+Vector2(-4,4)*s,18,col)

func paint_ellipse(c: Vector2,r: Vector2,col: Color,rot: float=0.0) -> void:
	var pts=PackedVector2Array()
	for i in 20: pts.append(c+(Vector2(cos(i*TAU/20),sin(i*TAU/20))*r).rotated(rot))
	draw_colored_polygon(pts,col)

func button(id: String,rect: Rect2,label: String,enabled: bool=true) -> void:
	enabled=enabled and not game.is_map_casting()
	var active: bool=hovered==id and enabled
	var color: Color=GOLD if enabled else Color("746c5a")
	draw_style_box(game.make_style(Color("55432a") if active else Color("322a23"),color,1,4),rect)
	center_text(label,rect.position+Vector2(rect.size.x/2,rect.size.y/2+7),19,color)
	hits.append({"id":id,"rect":rect,"enabled":enabled})

func circle_button(id: String,c: Vector2,label: String,kind: String,enabled: bool=true) -> void:
	enabled=enabled and not game.is_map_casting()
	var color: Color=LIGHT if enabled else Color("817764")
	if hovered==id and enabled: draw_circle(c,42,Color(0.92,0.69,0.25,.23))
	draw_circle(c,35,Color("28231e"))
	draw_arc(c,35,0,TAU,64,GOLD if enabled else Color("665a44"),2,true)
	draw_arc(c,30,0,TAU,64,Color("655137"),1,true)
	icon(kind,c,color,1.1)
	var label_width: float=serif.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
	draw_string_outline(serif,c+Vector2(-label_width/2,62),label,HORIZONTAL_ALIGNMENT_LEFT,-1,20,5,Color(.11,.08,.05,.95))
	center_text(label,c+Vector2(0,62),20,color)
	hits.append({"id":id,"rect":Rect2(c-Vector2(42,42),Vector2(84,108)),"enabled":enabled})

func _draw() -> void:
	if game==null: return
	hits.clear()
	var w: ShanheWorld=game.world
	var u: Dictionary=w.units[game.selected_unit]
	CommanderPanel.draw(self,w,u)
	panel(MINI_FRAME)
	draw_texture_rect(overview,MINI,false)
	draw_rect(MINI,Color("c7a467"),false,1)
	for unit in w.units:
		var point: Vector2=(w.center(int(unit.cell))-w.bounds.position)/w.bounds.size
		draw_circle(MINI.position+point*MINI.size,3,Color("dcb879") if w.faction(unit)=="player" else Color("c385d4"))
	var view: Rect2=game.visible_world().intersection(w.bounds)
	var area:=Rect2(MINI.position+(view.position-w.bounds.position)/w.bounds.size*MINI.size,view.size/w.bounds.size*MINI.size).intersection(MINI)
	draw_rect(area,Color("fff0b0"),false,1.5)
	hits.append({"id":"minimap","rect":MINI,"enabled":true})
	var ec=Vector2(1790,977)
	draw_circle(ec,76,Color(.75,.53,.2,.18))
	draw_circle(ec,68,Color("382c1c"))
	draw_arc(ec,69,0,TAU,96,GOLD,3,true)
	draw_arc(ec,61,0,TAU,96,Color("896c3e"),1,true)
	for i in 8:
		var p=ec+Vector2.from_angle(i*PI/4)*71
		draw_circle(p,3,LIGHT)
	center_text("施法" if game.is_map_casting() else "结束",ec+Vector2(0,-3),28,MUTED if game.is_map_casting() else LIGHT)
	center_text("中" if game.is_map_casting() else "回合",ec+Vector2(0,33),28,MUTED if game.is_map_casting() else LIGHT)
	hits.append({"id":"end_turn","rect":Rect2(ec-Vector2(74,74),Vector2(148,148)),"enabled":not game.moving and not game.is_map_casting()})
	commander_tooltip=CommanderPanel.draw_tooltip(self,w,u)

func hit_test(p: Vector2) -> Dictionary:
	for i in range(hits.size()-1,-1,-1):
		if hits[i].rect.has_point(p): return hits[i]
	for rect in [CommanderPanel.RECT,MINI_FRAME]:
		if rect.has_point(p): return {"id":"panel","enabled":false}
	return {}

func draw_topbar() -> void:
	var w: ShanheWorld = game.world
	# Top status strip.
	draw_rect(Rect2(0,0,1920,78),Color(0.13,.10,.08,.97))
	draw_line(Vector2(0,77),Vector2(1920,77),GOLD,2,true)
	draw_line(Vector2(0,73),Vector2(1920,73),Color("665134"),1,true)
	for i in 7: draw_arc(Vector2(37+i*11,14),15,0,TAU,24,Color(.66,.48,.22,.10),1,true)
	draw_circle(Vector2(60,48),47,Color("2d241d"))
	draw_arc(Vector2(60,48),44,0,TAU,64,GOLD,2,true)
	draw_arc(Vector2(60,48),39,0,TAU,64,Color("806946"),1,true)
	center_text("西岐",Vector2(60,60),29,LIGHT)
	text("姬发",Vector2(124,31),24)
	text("西岐王 · 奉天伐商",Vector2(196,30),16,MUTED)
	text("武王兴周    第 %02d 回合" % w.turn,Vector2(124,59),17,GOLD)
	var resources=[["grain","粮草",Color("d9ba67")],["wood","木材",Color("ba8b57")],["iron","金铁",Color("b2b8ba")],["jade","玉石",Color("8cbfa4")],["gold","钱帛",Color("e8c168")]]
	for i in resources.size():
		var x: float=425+i*235
		var r: Array=resources[i]
		icon(r[0],Vector2(x,34),r[2],.85)
		text(r[1],Vector2(x+22,29),16,MUTED)
		text(str(int(w.economy.treasury[r[0]])),Vector2(x+22,55),23,LIGHT,sans)
		text("+%d" % int(game.economy_income.get(r[0],0)),Vector2(x+118,54),15,Color("9ebd76"),sans)
	icon("sun",Vector2(1620,36),GOLD,.8)
	text("声望  %d" % w.economy.prestige,Vector2(1645,43),18)
	button("save",Rect2(1780,17,53,40),"存")
	button("load",Rect2(1839,17,53,40),"读")
