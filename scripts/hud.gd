extends Control
var game: Node2D
var serif: Font=preload("res://assets/fonts/ShanheSerif.otf")
var sans: Font=preload("res://assets/fonts/ShanheSans.otf")
var portrait: Texture2D=preload("res://assets/ui/nezha_portrait.png")
var overview: Texture2D=preload("res://assets/maps/overview.jpg")
var army: Texture2D=preload("res://assets/units/red_army.png")
var hits: Array=[]
var hovered: String=""
const GOLD=Color("cfb079")
const LIGHT=Color("f3dfaf")
const MUTED=Color("b5ab92")
const BG=Color(0.12,0.105,0.095,0.95)
const MINI=Rect2(26,814,252,238)

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

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
	var active: bool=hovered==id and enabled
	var color: Color=GOLD if enabled else Color("746c5a")
	draw_style_box(game.make_style(Color("55432a") if active else Color("322a23"),color,1,4),rect)
	center_text(label,rect.position+Vector2(rect.size.x/2,rect.size.y/2+7),19,color)
	hits.append({"id":id,"rect":rect,"enabled":enabled})

func circle_button(id: String,c: Vector2,label: String,kind: String,enabled: bool=true) -> void:
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
	var attributes:=w.Catalog.effective_stats(u)
	var kit: Dictionary=w.Catalog.profile(u).skills
	draw_topbar()
	# Left commander panel.
	panel(Rect2(18,108,310,620))
	if game.selected_unit==0: draw_texture_rect_region(portrait,Rect2(27,117,292,236),Rect2(0,0,640,518))
	else:
		draw_rect(Rect2(27,117,292,236),Color("3b3026"))
		draw_texture_rect(army,Rect2(74,115,198,238),false)
	draw_rect(Rect2(27,293,292,60),Color(.10,.08,.07,.83))
	text(u.name,Vector2(44,333),31,LIGHT)
	text("等级 18",Vector2(228,331),16,GOLD)
	text(u.title,Vector2(42,382),19,GOLD)
	for row in 3:
		var keys: Array=[["physical_attack","physical_defense"],["magic_attack","magic_defense"],["max_hp","movement"]][row]
		for col in 2:
			var key: String=keys[col]
			var x:=43+col*156
			text(w.Catalog.DATA.stat_labels[key],Vector2(x,421+row*35),17,MUTED)
			text(str(int(attributes[key])),Vector2(x+83,421+row*35),20,LIGHT,sans)
	rule(40,506,267)
	text("戟兵",Vector2(43,539),18,GOLD)
	text("%s / %s" %[str(int(u.soldiers)),str(int(u.max_soldiers))],Vector2(151,539),20,LIGHT,sans)
	draw_rect(Rect2(44,552,260,6),Color("574b38"))
	draw_rect(Rect2(44,552,260*clampf(float(u.soldiers)/float(u.max_soldiers),0.0,1.0),6),Color("bba16b"))
	text("剩余移动",Vector2(43,594),18,MUTED)
	text("%d / %d" %[int(u.ap),int(u.max_ap)],Vector2(236,594),23,GOLD,sans)
	for i in int(u.max_ap):
		draw_style_box(game.make_style(Color("dcc08b") if i<int(u.ap) else Color("453c30"),Color.TRANSPARENT,0,3),Rect2(45+i*260.0/u.max_ap,610,250.0/u.max_ap,8))
	text("本轮行动完成" if u.action_done else "平地 1 格消耗 1 点移动力",Vector2(43,650),16,GOLD if u.action_done else MUTED)
	text("开战士气 50 · 击杀积累至 100",Vector2(43,677),16,Color("9fbfa5"))
	var effect_label: String="戟兵 / 空位 / 空位"
	if not u.effects.is_empty():
		var effect: Dictionary=u.effects[0]
		effect_label="%s · 剩余 %d 轮" % [effect.get("name","军略效果"),int(effect.expires_turn)-w.turn]
	text(effect_label,Vector2(43,707),15,MUTED)
	icon("flag",Vector2(283,676),GOLD,.9)
	# Nine-region quick travel bar.
	panel(Rect2(562,96,796,44))
	var labels=["西凉","晋地","幽燕","关中","宛洛","齐鲁","巴蜀","荆襄","吴越"]
	var ids=["xiliang","jin","youyan","guanzhong","wanluo","qilu","bashu","jingxiang","wuyue"]
	for i in 9:
		var rect=Rect2(571+i*87,101,81,34)
		if game.current_region()==ids[i]: draw_rect(rect,Color(.7,.55,.28,.22))
		center_text(labels[i],rect.position+Vector2(40,24),19,GOLD if game.current_region()==ids[i] else MUTED)
		hits.append({"id":"region:"+ids[i],"rect":rect,"enabled":true})
	# Objectives.
	panel(Rect2(1574,109,328,216),"行 军 纪 要")
	text("一统山河",Vector2(1596,185),20,LIGHT)
	text("相邻商军据点可接战；B 试演武。",Vector2(1596,215),16,MUTED)
	var owned: int=0
	for p in w.pois:
		if p.owner=="player": owned+=1
	text("我方据点",Vector2(1596,255),17,MUTED)
	text("%d / 125" %owned,Vector2(1795,255),18,GOLD,sans)
	button("capital",Rect2(1596,272,280,36),"西岐内政 · 建设与地标",not game.moving)
	# Context-sensitive orders.
	panel(Rect2(1574,343,328,245),"地 势 与 军 令")
	if not game.selected_poi.is_empty():
		var p: Dictionary=w.by_poi[game.selected_poi]
		var type_names={"city":"城池","pass":"关隘","village":"村庄","ferry":"渡口"}
		text(p.name,Vector2(1596,425),27,LIGHT)
		text(type_names[p.type],Vector2(1815,424),18,GOLD)
		text("归属 · "+{"player":"西岐","shang":"商","neutral":"未占领"}[p.owner],Vector2(1596,462),18,MUTED)
		text("商军戟兵 %d · 胜利后占领" % int(w.garrison(p).soldiers) if p.owner=="shang" else ("占领后开放两岸航线" if p.type=="ferry" else "占领后允许我方通行"),Vector2(1596,495),17,MUTED)
		button("interior",Rect2(1596,521,134,44),"进入据点",not game.moving)
		button("approach",Rect2(1742,521,138,44),"前往附近",not game.moving and p.owner!="player")
	else:
		text("山河有界，关津为钥",Vector2(1596,425),22,LIGHT)
		text("山脉与水域不可行军",Vector2(1596,464),18,MUTED)
		text("他方据点须先相邻占领",Vector2(1596,500),18,MUTED)
		text("选择地块，预览行军路线",Vector2(1596,549),17,GOLD)
	# All four real skill slots share the same definitions as their gameplay logic.
	panel(Rect2(1574,606,328,286),"武 将 四 技")
	var kinds: Array=["battle","ultimate","map","passive"]
	var names: Array=["读条","终结","军略","被动"]
	for i in 4:
		var ability: Dictionary=kit[kinds[i]]
		var y:=674+i*44
		text(names[i]+" · "+str(ability.name),Vector2(1596,y),19,GOLD)
		var detail: String=""
		match kinds[i]:
			"battle": detail=("%s伤害 · 读条 %.1f 秒" % ["魔法" if ability.damage_type=="magic" else "物理",ability.windup])
			"ultimate": detail="战斗内手动释放 · 消耗 100 士气"
			"map": detail="射程 %d · 范围 %d · 施放后结束行动" % [ability.range,ability.radius]
			"passive": detail=ability.description
		text(detail,Vector2(1596,y+19),14,MUTED)
	button("map_skill",Rect2(1596,847,280,34),"取消施法 · Esc" if game.map_skill_targeting else str(kit.map.name)+"  Q",game.map_skill_targeting or (not game.moving and w.map_skill_ready_reason(u).is_empty()))
	if hovered=="map_skill" or game.map_skill_targeting:
		panel(Rect2(490,725,940,48))
		center_text(str(kit.map.description),Vector2(960,756),18,LIGHT)
	# Mini map and unit cards.
	panel(Rect2(18,778,310,289),"九 州 舆 图")
	draw_texture_rect(overview,MINI,false)
	draw_rect(MINI,Color("c7a467"),false,1)
	for uu in w.units:
		var pp=(w.center(int(uu.cell))-w.bounds.position)/w.bounds.size
		draw_circle(MINI.position+pp*MINI.size,3,Color("ffdd6e"))
	var view: Rect2=game.visible_world().intersection(w.bounds)
	var vr=Rect2(MINI.position+(view.position-w.bounds.position)/w.bounds.size*MINI.size,view.size/w.bounds.size*MINI.size).intersection(MINI)
	draw_rect(vr,Color("fff0b0"),false,1.5)
	hits.append({"id":"minimap","rect":MINI,"enabled":true})
	icon("grid",Vector2(303,865),GOLD,.65)
	hits.append({"id":"grid","rect":Rect2(282,843,40,45),"enabled":true})
	icon("flag",Vector2(303,922),GOLD,.65)
	hits.append({"id":"focus","rect":Rect2(282,902,40,45),"enabled":true})
	icon("sun",Vector2(303,980),GOLD,.65)
	hits.append({"id":"overview","rect":Rect2(282,960,40,45),"enabled":true})
	panel(Rect2(363,943,570,121))
	for i in w.units.size():
		var rect=Rect2(375+i*180,955,169,96)
		var sel: bool=i==game.selected_unit
		draw_style_box(game.make_style(Color("413527") if sel else Color("27231f"),GOLD if sel else Color("65553b"),2 if sel else 1,4),rect)
		if i==0: draw_texture_rect_region(portrait,Rect2(rect.position+Vector2(4,4),Vector2(70,88)),Rect2(90,0,400,520))
		else:
			draw_texture_rect(army,Rect2(rect.position+Vector2(2,0),Vector2(78,88)),false,Color(0.85,0.9,1) if i==2 else Color.WHITE)
		text(w.units[i].name,rect.position+Vector2(82,32),19,LIGHT if sel else MUTED)
		text(str(int(w.units[i].soldiers)),rect.position+Vector2(83,57),17,GOLD,sans)
		text("%d 点" % int(w.units[i].ap),rect.position+Vector2(83,81),15,MUTED)
		hits.append({"id":"unit:"+str(i),"rect":rect,"enabled":not game.moving})
	# Bottom command wheel.
	circle_button("move",Vector2(1085,983),"移动","move",game.path.size()>1 and game.path_cost<=int(u.ap) and not game.moving)
	var cap: bool=not game.selected_poi.is_empty() and w.can_capture(u,w.by_poi[game.selected_poi]) and not game.moving
	circle_button("capture",Vector2(1197,983),"接战" if not game.selected_poi.is_empty() and w.by_poi[game.selected_poi].owner=="shang" else "占领","capture",cap)
	circle_button("guard",Vector2(1309,983),"驻守","guard",not game.moving and int(u.ap)>0)
	circle_button("focus",Vector2(1421,983),"定位","flag")
	circle_button("grid",Vector2(1533,983),"六边格","grid")
	var ec=Vector2(1790,977)
	draw_circle(ec,76,Color(.75,.53,.2,.18))
	draw_circle(ec,68,Color("382c1c"))
	draw_arc(ec,69,0,TAU,96,GOLD,3,true)
	draw_arc(ec,61,0,TAU,96,Color("896c3e"),1,true)
	for i in 8:
		var p=ec+Vector2.from_angle(i*PI/4)*71
		draw_circle(p,3,LIGHT)
	center_text("结束",ec+Vector2(0,-3),28,LIGHT)
	center_text("回合",ec+Vector2(0,33),28,LIGHT)
	hits.append({"id":"end_turn","rect":Rect2(ec-Vector2(74,74),Vector2(148,148)),"enabled":not game.moving})
	# Quiet controls and a contextual message, away from the map's center.
	text("滚轮缩放 · 中键 / 右键拖图 · 左键选点 · 右键行军",Vector2(372,914),17,Color("fff2cf"),sans)
	button("battle_demo",Rect2(1130,860,310,44),"戟兵演武  B",not game.moving)
	if not game.toast.is_empty():
		var tw: float=serif.get_string_size(game.toast,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
		var rr=Rect2(960-tw/2-24,837,tw+48,48)
		draw_style_box(game.make_style(Color(.14,.115,.08,.94),Color("ac8d53"),1,4),rr)
		center_text(game.toast,Vector2(960,869),20,LIGHT)
	if game.hover_cell>=0 and hovered.is_empty() and not game.moving:
		var info: String=w.reason(game.hover_cell)
		if game.map_skill_targeting:
			info=game.skill_preview.get("reason","")
			if info.is_empty(): info="左键施放 "+str(kit.map.name)+" · 本轮行动随即结束"
		var tw: float=sans.get_string_size(info,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		var rr=Rect2(960-tw/2-18,786,tw+36,34)
		draw_style_box(game.make_style(Color(.10,.12,.11,.86),Color(.65,.58,.41,.5),1,3),rr)
		center_text(info,Vector2(960,810),16,LIGHT,sans)

func hit_test(p: Vector2) -> Dictionary:
	for i in range(hits.size()-1,-1,-1):
		if hits[i].rect.has_point(p): return hits[i]
	for rect in [Rect2(0,0,1920,78),Rect2(18,108,310,620),Rect2(1574,109,328,216),Rect2(1574,343,328,245),Rect2(1574,606,328,286),Rect2(18,778,310,289),Rect2(363,943,570,121),Rect2(562,96,796,44)]:
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
