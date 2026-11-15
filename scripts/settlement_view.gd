extends "res://scripts/hud.gd"

var poi_id: String=""
var selected_plot: int=4
var blueprint: String="farm"
var selected_landmark: String=""
var owned_page: int=0
var confirm_action: String=""
var backgrounds: Dictionary={}
var sprites: Dictionary={}
var landmark_sprites: Dictionary={}
var painted_icons: Dictionary={}
var layouts: Dictionary={}
var plot_views: Dictionary={}
var frame: Texture2D
var lord: Texture2D
var panel_style: StyleBoxTexture
var small_style: StyleBoxTexture
var primary_skin: Texture2D
var name_skin: Texture2D
var synergy_skin: Texture2D
var build_mode: bool=false
var planning_view: bool=false
var show_links: bool=false
var settlement_menu: bool=false
var view_zoom: float=1.0
var view_pan:=Vector2.ZERO
var scene_drag: bool=false
const LANDMARK_ART={"lingtai":0,"fengshentai":1,"lutai":2,"zhaixing":3,"jinguang":4}
const INK=Color("f6e4b5")
const SOFT=Color("d0bd98")
const GREEN=Color("c5ee99")

func _ready() -> void:
	super._ready()
	layouts=JSON.parse_string(FileAccess.get_file_as_string("res://data/interior_layouts.json"))
	for kind in ["city","village","pass","ferry"]: backgrounds[kind]=load("res://assets/interiors/"+kind+"_painted.png")
	for d in game.world.economy.catalog: sprites[d.id]=load("res://assets/buildings/painted/"+d.id+".png")
	for id in LANDMARK_ART: landmark_sprites[id]=load("res://assets/buildings/painted/landmark_"+str(LANDMARK_ART[id])+".png")
	for id in ["grain","wood","iron","jade","gold","reserve","build","upgrade","demolish","map","flag","turn"]:
		painted_icons[id]=load("res://assets/ui/painted_icons/"+id+".png")
	frame=load("res://assets/ui/painted/panel.png")
	primary_skin=load("res://assets/ui/painted/primary_button.png")
	name_skin=load("res://assets/ui/painted/nameplate.png")
	synergy_skin=load("res://assets/ui/painted/synergy.png")
	lord=load("res://assets/ui/painted/jifa_portrait.png")
	panel_style=StyleBoxTexture.new()
	panel_style.texture=frame
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: panel_style.set_texture_margin(side,38)
	small_style=panel_style.duplicate()
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: small_style.set_texture_margin(side,36)

func open(pid: String) -> void:
	poi_id=pid
	selected_plot=4 if game.world.by_poi[pid].type=="city" else 0
	selected_landmark=""
	confirm_action=""
	build_mode=false
	planning_view=false
	show_links=false
	settlement_menu=false
	view_zoom=1.0
	view_pan=Vector2.ZERO
	show()
	queue_redraw()

func panel(rect: Rect2,title: String="") -> void:
	draw_style_box(panel_style,rect)
	hits.append({"id":"panel","rect":rect,"enabled":false})
	if not title.is_empty():
		text(title,rect.position+Vector2(22,38),24,INK)
		rule(rect.position.x+18,rect.position.y+51,rect.size.x-36)

func button(id: String,rect: Rect2,label: String,enabled: bool=true) -> void:
	var style: StyleBoxTexture=small_style.duplicate()
	style.modulate_color=Color("d8b86f") if enabled and hovered==id else (Color.WHITE if enabled else Color(.66,.64,.58,1))
	var primary: bool=enabled and (id in ["build","restore","end_turn"] or (id=="construction" and build_mode))
	if primary: draw_texture_rect(primary_skin,rect,false)
	else: draw_style_box(style,rect)
	center_text(label,rect.get_center()+Vector2(0,7),19,Color("4b3018") if primary else (INK if enabled else MUTED))
	hits.append({"id":id,"rect":rect,"enabled":enabled})

func icon(kind: String,c: Vector2,col: Color=GOLD,s: float=1.0) -> void:
	if painted_icons.has(kind): draw_texture_rect(painted_icons[kind],Rect2(c-Vector2.ONE*19*s,Vector2.ONE*38*s),false,col)

func action_button(id: String,rect: Rect2,label: String,kind: String,enabled: bool=true) -> void:
	button(id,rect,"",enabled)
	var primary: bool=enabled and (id in ["build","restore","end_turn"] or (id=="construction" and build_mode))
	icon(kind,rect.position+Vector2(27,rect.size.y*.5),Color("6c4829") if primary else (Color.WHITE if enabled else Color(.65,.65,.65)),.82)
	center_text(label,rect.get_center()+Vector2(15,7),20,Color("4b3018") if primary else (INK if enabled else MUTED))

func paragraph(value: String,pos: Vector2,width: float=258,font_size: int=18,color: Color=SOFT) -> float:
	var line: String=""
	var y: float=pos.y
	var pieces: Array[String]=[]
	var word: String=""
	for ch in value:
		if ch.unicode_at(0)<128 and not ch in [" ","\n"]: word+=ch
		else:
			if not word.is_empty():
				pieces.append(word)
				word=""
			pieces.append(ch)
	if not word.is_empty(): pieces.append(word)
	for token in pieces:
		if token=="\n" or (not line.is_empty() and sans.get_string_size(line+token,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width):
			text(line,Vector2(pos.x,y),font_size,color,sans)
			y+=font_size+8
			line="" if token=="\n" else token
		else: line+=token
	if not line.is_empty():
		text(line,Vector2(pos.x,y),font_size,color,sans)
		y+=font_size+8
	return y

func cost_label(cost: Dictionary) -> String:
	var parts: PackedStringArray=[]
	for key in game.world.economy.KEYS:
		if cost.has(key): parts.append(game.world.economy.NAMES[key]+" "+str(int(cost[key])))
	return "  ".join(parts)

func amount(value: int) -> String:
	if value>=100000000: return "%.1f亿" % (float(value)/100000000.0)
	if value>=1000000: return "%.0f万" % (float(value)/10000.0)
	return "%.1f万" % (float(value)/10000.0) if value>=10000 else str(value)

func picture_rect() -> Rect2:
	var size: Vector2=Vector2(1600,1067)*view_zoom
	return Rect2(Vector2(950,521)+view_pan-size/2,size)

func scene_point(uv: Vector2) -> Vector2:
	var rect: Rect2=picture_rect()
	return rect.position+uv*rect.size

# Each terrace contains a few construction sites. Normal view gives occupied
# buildings breathing room; planning reveals every site in that same terrace.
# Only presentation changes: stable plot indices, economy and saved adjacency stay intact.
func update_plot_views(state: Dictionary, kind: String) -> void:
	plot_views.clear()
	for group in layouts[kind].groups:
		var indices: Array=[]
		for raw in group[3]:
			var i: int=int(raw)
			if planning_view or build_mode or not str(state.plots[i].building).is_empty() or not game.world.economy.job_at(poi_id,i).is_empty() or i==selected_plot:
				indices.append(i)
		if indices.is_empty(): indices.append(int(group[3][0]))
		var available: float=float(group[2])*picture_rect().size.x/1536.0
		var step: float=available/indices.size()
		for j in indices.size():
			var i: int=indices[j]
			var pos: Vector2=scene_point(Vector2(group[0],group[1]))+Vector2((j-(indices.size()-1)*.5)*step,0)
			plot_views[i]={"position":pos,"width":minf(246*view_zoom,step*.92),"group":group}

func plot_position(plot: Dictionary) -> Vector2:
	var plots: Array=game.world.economy.settlements[poi_id].plots
	for i in plots.size():
		if plots[i]==plot and plot_views.has(i): return plot_views[i].position
	return Vector2.ZERO

func draw_topbar() -> void:
	var w=game.world
	var p: Dictionary=w.by_poi[poi_id]
	panel(Rect2(14,8,390,66))
	text("周",Vector2(35,50),28,INK)
	text(p.name+" · "+layouts[p.type].title,Vector2(80,50),27,INK)
	hits.append({"id":"settlements","rect":Rect2(14,8,390,66),"enabled":true})
	action_button("back",Rect2(415,13,118,55),"舆图","map")
	button("zoom_out",Rect2(542,13,56,55),"－",view_zoom>.85)
	button("zoom_in",Rect2(602,13,56,55),"＋",view_zoom<1.35)
	button("reset_view",Rect2(662,13,66,55),"复位")
	panel(Rect2(738,8,1168,66))
	var keys: Array=["grain","wood","iron","jade","gold"]
	for i in keys.size():
		var key: String=keys[i]
		var x: float=761+i*181
		icon(key,Vector2(x+14,34),Color.WHITE,1.1)
		text(w.economy.NAMES[key],Vector2(x+38,29),16,SOFT)
		text(amount(int(w.economy.treasury[key])),Vector2(x+38,52),21,INK,sans)
		text("+"+amount(int(game.economy_income.get(key,0))),Vector2(x+106,51),14,GREEN,sans)
	text("第 %d 回合" % w.turn,Vector2(1694,34),21,INK)
	text("势力府库 · 全域共享",Vector2(1694,56),15,SOFT)

func draw_left(poi: Dictionary,state: Dictionary) -> void:
	var econ=game.world.economy
	panel(Rect2(16,94,250,600))
	draw_texture_rect_region(lord,Rect2(28,106,226,178),Rect2(80,20,1090,860))
	draw_style_box(small_style,Rect2(28,280,226,39))
	center_text("西岐 · 姬发",Vector2(141,307),23,INK)
	text("领属",Vector2(36,347),17,SOFT)
	text({"player":"西岐","shang":"商军","neutral":"未归附"}[poi.owner],Vector2(175,347),19,INK)
	var built: int=0
	for plot in state.plots:
		if not plot.building.is_empty(): built+=1
	text("营建",Vector2(36,379),17,SOFT)
	text("%d / %d" % [built,state.plots.size()],Vector2(174,379),19,INK,sans)
	draw_rect(Rect2(36,392,210,5),Color("61503b"))
	draw_rect(Rect2(36,392,210*float(built)/state.plots.size(),5),Color("c0cf8a"))
	text("本地产出 / 回合",Vector2(36,427),18,INK)
	var local: Dictionary=econ.local_income(poi_id)
	for i in econ.KEYS.size():
		var key: String=econ.KEYS[i]
		var y: float=458+i*31
		icon(key,Vector2(46,y-7),Color.WHITE,.73)
		text(econ.NAMES[key],Vector2(68,y),17,SOFT)
		text("+%d" % int(local[key]),Vector2(186,y),18,GREEN if poi.owner=="player" else MUTED,sans)
	rule(35,626,210)
	text("兵员储备",Vector2(36,657),18,SOFT)
	text(amount(int(econ.treasury.reserve)),Vector2(181,657),20,INK,sans)
	panel(Rect2(16,707,250,164))
	text("工匠  %d / %d" % [state.jobs.size(),econ.queue_limit(poi)],Vector2(37,745),21,INK)
	if state.jobs.is_empty():
		paragraph("工匠待命，可择地兴建。" if poi.owner=="player" else "此地产出暂不入我方府库。",Vector2(37,785),206,17)
	for i in state.jobs.size():
		var job: Dictionary=state.jobs[i]
		var name: String=econ.definitions[job.building].name if job.landmark.is_empty() else econ.landmarks[job.landmark].name
		var y: float=777+i*43
		text(name+" · %d 回合" % int(job.remaining),Vector2(37,y),16,SOFT)
		button("cancel:"+str(i),Rect2(188,y-24,59,32),"确认" if confirm_action=="cancel:"+str(i) else "撤工",poi.owner=="player")
	if not confirm_action.is_empty() and confirm_action.begins_with("cancel:"):
		text("撤工返还一半资源",Vector2(37,856),14,SOFT)

func draw_empty_site(pos: Vector2,width: float,selected: bool) -> void:
	var rx: float=width*.42
	var ry: float=minf(37*view_zoom,width*.25)
	var pts=PackedVector2Array([pos+Vector2(-rx,-ry),pos+Vector2(rx,-ry),pos+Vector2(rx+16*view_zoom,ry),pos+Vector2(-rx+16*view_zoom,ry),pos+Vector2(-rx,-ry)])
	draw_colored_polygon(pts,Color(.40,.30,.11,.16))
	for j in 4: draw_dashed_line(pts[j],pts[j+1],INK if selected else Color(.95,.88,.63,.74),2,8,true)
	icon("build",pos+Vector2(8,-11),Color(1,1,.85,.9),.85)
	var label: String="可建造"
	var label_width: float=serif.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
	draw_string_outline(serif,pos+Vector2(8-label_width/2,28),label,HORIZONTAL_ALIGNMENT_LEFT,-1,19,4,Color("57462b"))
	center_text(label,pos+Vector2(8,28),19,INK)

func draw_world(state: Dictionary,poi: Dictionary) -> void:
	var econ=game.world.economy
	var order: Array=plot_views.keys()
	order.sort_custom(func(a,b): return plot_views[a].position.y<plot_views[b].position.y)
	if show_links and selected_landmark.is_empty() and plot_views.has(selected_plot):
		var from: Vector2=plot_views[selected_plot].position
		for i in order:
			if econ.adjacent(state.plots[selected_plot],state.plots[i]):
				var to: Vector2=plot_views[i].position
				draw_dashed_line(from,to,Color(.76,.94,.54,.8),2,9,true)
	var labels: Array=[]
	var badges: Array=[]
	for i in order:
		var plot: Dictionary=state.plots[i]
		var pos: Vector2=plot_views[i].position
		var width: float=plot_views[i].width
		var selected: bool=selected_plot==i and selected_landmark.is_empty()
		var job: Dictionary=econ.job_at(poi_id,i)
		var occupied: bool=not plot.building.is_empty()
		var id: String=plot.building if occupied else blueprint
		var height: float=width*.89
		var box: Rect2=Rect2(pos-Vector2(width*.5,height*.87),Vector2(width,height))
		if selected:
			paint_ellipse(pos,Vector2(width*.48,height*.18),Color(1,.79,.29,.22))
		if occupied:
			draw_texture_rect(sprites[id],box,false)
			var label: String=econ.definitions[id].name+"  %d级" % int(plot.level)
			labels.append({"id":i,"text":label,"position":box.position+Vector2(width*.5,9),"selected":selected,"width":width})
			var detail: Dictionary=econ.yield_detail(poi_id,i)
			if detail.bonus>0 and (width>180 or selected):
				var badge: Rect2=Rect2(pos+Vector2(-103,24),Vector2(206,29))
				var benefit: String=detail.sources[0] if detail.sources.size()==1 else "综合增益 +%d%%" % roundi(detail.bonus*100)
				badges.append({"rect":badge,"text":benefit})
		else:
			draw_empty_site(pos-Vector2(0,20*view_zoom),width,selected)
			if selected and build_mode and poi.owner=="player": draw_texture_rect(sprites[id],box,false,Color(1,1,1,.48))
		if not job.is_empty():
			var job_rect=Rect2(pos+Vector2(-92,24),Vector2(184,29))
			draw_style_box(game.make_style(Color(.14,.29,.27,.96),Color("bdd8b0"),1,10),job_rect)
			center_text("施工中 · %d 回合" % int(job.remaining),job_rect.get_center()+Vector2(0,6),16,INK)
		var hit_rect: Rect2=box if occupied else Rect2(pos-Vector2(width*.43,40),Vector2(width*.86,80))
		hits.append({"id":"plot:"+str(i),"rect":hit_rect,"enabled":true})
	for label in labels:
		var width: float=minf(190,maxf(126,float(label.width)))
		var pos: Vector2=label.position
		var rect=Rect2(pos-Vector2(width*.5,23),Vector2(width,37))
		draw_texture_rect(name_skin,rect,false)
		center_text(label.text,pos+Vector2(0,2),18,Color("fff0ba") if label.selected else INK)
		hits.append({"id":"plot:"+str(label.id),"rect":rect,"enabled":true})
	for badge in badges:
		draw_texture_rect(synergy_skin,badge.rect,false,Color(1,1,1,.94))
		center_text(badge.text,badge.rect.get_center()+Vector2(0,6),16,Color("f7ffd9"))
	var mark_index: int=0
	for id in state.landmarks:
		var uv: Array=layouts[poi.type].landmarks[mini(mark_index,layouts[poi.type].landmarks.size()-1)]
		var pos: Vector2=scene_point(Vector2(uv[0],uv[1]))
		var sz: float=155*view_zoom
		draw_texture_rect(landmark_sprites[id],Rect2(pos-Vector2(sz*.5,sz*.8),Vector2(sz,sz)),false,Color.WHITE if state.landmarks[id] else Color(.8,.84,.83,.87))
		button("landmark:"+id,Rect2(pos+Vector2(-88,24),Vector2(176,37)),econ.landmarks[id].name+(" · 已修复" if state.landmarks[id] else " · 待修复"))
		mark_index+=1

func draw_thumbnail(texture: Texture2D,poi: Dictionary,uv: Vector2=Vector2(.5,.55)) -> void:
	var rect=Rect2(1625,152,262,150)
	var source=Rect2(uv*Vector2(1536,1024)-Vector2(180,150),Vector2(360,206)).intersection(Rect2(0,0,1536,1024))
	draw_texture_rect_region(backgrounds[poi.type],rect,source,Color(.88,.91,.87))
	draw_texture_rect(texture,Rect2(1681,146,157,157),false)
	draw_rect(rect,Color("c9ac66"),false,1)

func draw_right(poi: Dictionary,state: Dictionary) -> void:
	var w=game.world
	var econ=w.economy
	panel(Rect2(1606,94,300,797))
	if not selected_landmark.is_empty():
		var d: Dictionary=econ.landmarks[selected_landmark]
		text(d.name,Vector2(1630,134),26,INK)
		draw_thumbnail(landmark_sprites[selected_landmark],poi)
		text("封神地标 · 独一",Vector2(1628,336),19,INK)
		paragraph(d.description,Vector2(1628,373),255,19,SOFT)
		rule(1628,492,252)
		text("修复所需",Vector2(1628,527),20,INK)
		paragraph(cost_label(d.cost),Vector2(1628,565),255,18,SOFT)
		text("工期  %d 回合" % int(d.turns),Vector2(1628,653),19,SOFT)
		var why: String=econ.landmark_reason(poi,selected_landmark)
		paragraph(why if not why.is_empty() else "修复后效果惠及全势力。",Vector2(1628,710),255,18)
		action_button("restore",Rect2(1625,822,262,51),"修复地标","upgrade",why.is_empty())
		return
	var plot: Dictionary=state.plots[selected_plot]
	var id: String=blueprint if plot.building.is_empty() else plot.building
	var d: Dictionary=econ.definitions[id]
	var level: int=int(plot.level)
	var next: int=mini(3,level+1)
	icon("build",Vector2(1642,126),Color.WHITE,.78)
	text(d.name+(" %d级" % level if level>0 else " · 营建"),Vector2(1670,134),23,INK)
	var uv: Vector2=Vector2(.5,.55)
	if plot_views.has(selected_plot):
		var gr: Array=plot_views[selected_plot].group
		uv=Vector2(gr[0],gr[1])
	draw_thumbnail(sprites[id],poi,uv)
	paragraph(d.description,Vector2(1628,331),255,17,SOFT)
	rule(1628,409,252)
	text("当前产出",Vector2(1628,440),20,INK)
	var current: Dictionary=econ.yield_detail(poi_id,selected_plot)
	var future: Dictionary=econ.yield_detail(poi_id,selected_plot,id,next)
	var resource: String=econ.NAMES[d.resource]
	text("%s  +%d / 回合" % [resource,int(current.amount)],Vector2(1630,472),19,SOFT,sans)
	text("地势 · "+econ.TERRAIN[int(plot.terrain)],Vector2(1630,504),17,SOFT)
	rule(1628,522,252)
	text("升级预览" if level>0 else "建成预览",Vector2(1628,554),20,INK)
	text("%d级  ›  %d级" % [level,next],Vector2(1773,553),18,GOLD)
	text("%s  +%d  ›  +%d" % [resource,int(current.amount),int(future.amount)],Vector2(1630,588),18,GREEN,sans)
	text("工期  %d 回合" % next,Vector2(1630,618),17,SOFT)
	text("协作加成",Vector2(1630,653),20,INK)
	var sources: String="、".join(future.sources)
	paragraph(sources if not sources.is_empty() else "暂无加成，可在布局中查看连接。",Vector2(1630,682),252,16,GREEN if not sources.is_empty() else SOFT)
	if poi.owner=="player":
		paragraph(cost_label(econ.cost_for(id,next)),Vector2(1630,745),252,16,INK)
		var why: String=econ.build_reason(poi,selected_plot,id,w.by_poi)
		action_button("build",Rect2(1625,822,262,51),"升级" if level>0 else "兴建", "upgrade" if level>0 else "build",why.is_empty())
		if not why.is_empty(): center_text(why,Vector2(1756,808),15,SOFT)
	else:
		text("尚未归附 · 占领后可营建",Vector2(1630,746),17,SOFT)
		action_button("capture_here",Rect2(1625,766,262,48),"占领 · 1 点行动力","flag",w.can_capture(w.units[game.selected_unit],poi))
		action_button("approach_here",Rect2(1625,824,262,48),"行军至附近","map")

func draw_toolbar(poi: Dictionary,state: Dictionary) -> void:
	panel(Rect2(14,994,780,72))
	var buttons: Array=[["construction","营建","build"],["upgrade_focus","升级","upgrade"],["demolish","拆除","demolish"],["layout","布局","map"],["settlements","据点","flag"]]
	for i in buttons.size():
		var d: Array=buttons[i]
		var enabled: bool=true
		if d[0] in ["construction","upgrade_focus","demolish"]: enabled=poi.owner=="player"
		if d[0]=="demolish": enabled=enabled and not state.plots[selected_plot].building.is_empty() and game.world.economy.job_at(poi_id,selected_plot).is_empty() and selected_landmark.is_empty()
		action_button(d[0],Rect2(27+i*151,1006,145,48),"确认拆除" if d[0]=="demolish" and confirm_action=="demolish" else d[1],d[2],enabled)
	panel(Rect2(1092,994,814,72))
	var more: Array=[["links","协作","jade"],["recruit","补兵","reserve"],["save","存档","map"],["load","读档","map"],["end_turn","结束回合","turn"]]
	for i in more.size():
		var d: Array=more[i]
		var enabled: bool=true
		if d[0]=="recruit": enabled=game.world.recruit_reason(game.world.units[game.selected_unit],poi).is_empty()
		action_button(d[0],Rect2(1105+i*157,1006,151,48),d[1],d[2],enabled)
	if hovered=="recruit":
		var why: String=game.world.recruit_reason(game.world.units[game.selected_unit],poi)
		draw_style_box(small_style,Rect2(1152,942,510,40))
		center_text("每人 2 粮草 · 至多 500 人 · 1 点行动力" if why.is_empty() else why,Vector2(1407,968),18,INK)

func draw_catalog(poi: Dictionary) -> void:
	panel(Rect2(285,803,1307,178))
	text("择地营建",Vector2(308,834),21,INK)
	text("费用从势力府库支取",Vector2(449,834),16,SOFT)
	button("close_catalog",Rect2(1487,817,85,31),"收起")
	for i in game.world.economy.catalog.size():
		var d: Dictionary=game.world.economy.catalog[i]
		var rect=Rect2(301+i*106,850,100,114)
		var enabled: bool=poi.type in d.types and game.world.economy.unlocked(d.unlock,game.world.by_poi)
		if blueprint==d.id: draw_style_box(small_style,rect)
		draw_texture_rect(sprites[d.id],Rect2(rect.position+Vector2(5,-2),Vector2(90,83)),false,Color.WHITE if enabled else Color(.57,.57,.57,.8))
		center_text(d.name,rect.position+Vector2(50,98),17,INK if enabled else MUTED)
		hits.append({"id":"blueprint:"+d.id,"rect":rect,"enabled":poi.owner=="player"})

func draw_settlement_menu() -> void:
	panel(Rect2(15,78,380,465),"我 方 据 点")
	var owned: Array=[]
	for p in game.world.pois:
		if p.owner=="player": owned.append(p)
	owned_page=clampi(owned_page,0,maxi(0,(owned.size()-1)/6))
	for i in range(owned_page*6,mini(owned.size(),owned_page*6+6)):
		var n: int=i-owned_page*6
		button("settlement:"+owned[i].id,Rect2(34,146+n*52,342,43),owned[i].name+" · "+layouts[owned[i].type].title)
	button("page_prev",Rect2(34,475,110,42),"上一页",owned_page>0)
	button("page_next",Rect2(266,475,110,42),"下一页",(owned_page+1)*6<owned.size())

func _draw() -> void:
	if game==null or poi_id.is_empty(): return
	hits.clear()
	var poi: Dictionary=game.world.by_poi[poi_id]
	var state: Dictionary=game.world.economy.settlements[poi_id]
	var art: Texture2D=backgrounds[poi.type]
	var rect: Rect2=picture_rect()
	# Extend only the peripheral landscape under the UI; central art keeps its proportions.
	draw_texture_rect(art,Rect2(0,-100,1920,1280),false)
	draw_texture_rect(art,rect,false)
	if rect.position.x>0: draw_texture_rect_region(art,Rect2(0,rect.position.y,rect.position.x,rect.size.y),Rect2(0,0,110,1024))
	if rect.end.x<1920: draw_texture_rect_region(art,Rect2(rect.end.x,rect.position.y,1920-rect.end.x,rect.size.y),Rect2(1426,0,110,1024))
	update_plot_views(state,poi.type)
	draw_world(state,poi)
	draw_left(poi,state)
	draw_right(poi,state)
	draw_toolbar(poi,state)
	if build_mode: draw_catalog(poi)
	draw_topbar()
	if settlement_menu: draw_settlement_menu()
	if not game.toast.is_empty():
		var tw: float=serif.get_string_size(game.toast,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
		var toast_y: float=756 if build_mode else 937
		draw_style_box(small_style,Rect2(947-tw/2-22,toast_y,tw+44,42))
		center_text(game.toast,Vector2(947,toast_y+28),18,INK)

func hit_test(p: Vector2) -> Dictionary:
	for i in range(hits.size()-1,-1,-1):
		if hits[i].rect.has_point(p): return hits[i]
	for rect in [Rect2(0,0,1920,80),Rect2(16,94,250,600),Rect2(16,707,250,164),Rect2(1606,94,300,797),Rect2(0,994,1920,86)]:
		if rect.has_point(p): return {"id":"panel","enabled":false}
	return {}

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered=str(hit_test(event.position).get("id",""))
		if scene_drag:
			view_pan+=event.relative
			view_pan=view_pan.clamp(Vector2(-300,-180),Vector2(300,180))
	elif event is InputEventMouseButton:
		var hit: Dictionary=hit_test(event.position)
		if event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			if not event.pressed: scene_drag=false
			elif hit.is_empty() or str(hit.get("id","")).begins_with("plot:"): scene_drag=true
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and (hit.is_empty() or str(hit.get("id","")).begins_with("plot:")):
			view_zoom=clampf(view_zoom+(0.08 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -.08),.85,1.35)
		elif event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			if hit.get("enabled",false): command(hit.id)
			elif hit.is_empty(): settlement_menu=false
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				if settlement_menu: settlement_menu=false
				elif build_mode: build_mode=false
				else: game.close_settlement()
			KEY_E: command("end_turn")
			KEY_F5: command("save")
			KEY_F9: command("load")
	queue_redraw()
func command(id: String) -> void:
	var w=game.world
	var econ=w.economy
	var poi: Dictionary=w.by_poi[poi_id]
	if id.begins_with("plot:"):
		selected_plot=int(id.trim_prefix("plot:"))
		build_mode=econ.settlements[poi_id].plots[selected_plot].building.is_empty() and poi.owner=="player"
		selected_landmark=""
		confirm_action=""
	elif id.begins_with("blueprint:"):
		blueprint=id.trim_prefix("blueprint:" )
		selected_landmark=""
		confirm_action=""
		if not econ.settlements[poi_id].plots[selected_plot].building.is_empty(): game.say("请先选择一块空地，再安排新建筑")
	elif id.begins_with("landmark:"):
		selected_landmark=id.trim_prefix("landmark:")
		build_mode=false
		confirm_action=""
	elif id.begins_with("settlement:"):
		game.selected_poi=id.trim_prefix("settlement:")
		open(game.selected_poi)
	elif id.begins_with("cancel:"):
		if confirm_action==id:
			econ.cancel(poi,int(id.trim_prefix("cancel:")))
			confirm_action=""
			game.say("工程已撤销，返还一半已付资源")
		else: confirm_action=id
	else:
		match id:
			"settlements": settlement_menu=not settlement_menu
			"construction": build_mode=not build_mode
			"close_catalog": build_mode=false
			"layout": planning_view=not planning_view
			"links": show_links=not show_links
			"zoom_in": view_zoom=minf(1.35,view_zoom+.1)
			"zoom_out": view_zoom=maxf(.85,view_zoom-.1)
			"reset_view":
				view_zoom=1.0
				view_pan=Vector2.ZERO
			"upgrade_focus":
				build_mode=false
				selected_landmark=""
				game.say("选中建筑，在右侧确认升级")
			"back": game.close_settlement()
			"page_prev": owned_page-=1
			"page_next": owned_page+=1
			"build":
				var plot: Dictionary=econ.settlements[poi_id].plots[selected_plot]
				var building: String=blueprint if plot.building.is_empty() else plot.building
				var why: String=econ.build(poi,selected_plot,building,w.by_poi)
				game.say("工匠已开工 · 结束回合推进建设" if why.is_empty() else why)
				if why.is_empty(): build_mode=false
			"restore":
				var why: String=econ.restore_landmark(poi,selected_landmark)
				game.say("地标修复已开工" if why.is_empty() else why)
			"demolish":
				if confirm_action==id:
					econ.demolish(poi,selected_plot)
					confirm_action=""
					game.say("建筑已拆除，空地可重新规划")
				else: confirm_action=id
			"recruit":
				var count: int=w.recruit(w.units[game.selected_unit],poi)
				game.say("补充 %d 兵员，消耗 %d 粮草和 1 点行动力" % [count,count*2] if count>0 else w.recruit_reason(w.units[game.selected_unit],poi))
			"capture_here": game.action("capture")
			"approach_here":
				game.close_settlement()
				game.action("approach")
				# Preserve the route just computed by the world controller.
				return
			_:
				confirm_action=""
				if id=="load":
					build_mode=false
					planning_view=false
				game.action(id)
	game.refresh()
