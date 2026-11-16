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
var layouts: Dictionary={}
var plot_views: Dictionary={}
var panel_style: StyleBoxFlat
var small_style: StyleBoxFlat
var build_mode: bool=false
var planning_view: bool=false
var show_links: bool=false
var settlement_menu: bool=false
var view_zoom: float=1.0
var view_pan:=Vector2.ZERO
var scene_drag: bool=false
var economy_display_cache: Dictionary={}
const LANDMARK_ART={"lingtai":0,"fengshentai":1,"lutai":2,"zhaixing":3,"jinguang":4}
const INK=Color("f0e4c9")
const SOFT=Color("c6b99d")
const GREEN=Color("bbca95")

func _ready() -> void:
	super._ready()
	layouts=JSON.parse_string(FileAccess.get_file_as_string("res://data/interior_layouts.json"))
	for kind in ["city_large","city_small","village","pass","ferry"]:
		var background: String=layouts[kind].get("background","assets/interiors/grounded/"+kind+".png")
		backgrounds[kind]=load("res://"+background)
	for d in game.world.economy.catalog: sprites[d.id]=load("res://assets/buildings/grounded/"+d.id+".png")
	for id in LANDMARK_ART: landmark_sprites[id]=load("res://assets/buildings/grounded/landmark_"+str(LANDMARK_ART[id])+".png")
	panel_style=game.make_style(Color(.18,.145,.105,.94),Color("8c795b"),1,2)
	small_style=game.make_style(Color(.25,.205,.14,.95),Color("8d7957"),1,2)

func kind_for(poi: Dictionary) -> String:
	return game.world.economy.layout_kind(poi)

func open(pid: String) -> void:
	poi_id=pid
	invalidate_economy_cache()
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

func invalidate_economy_cache() -> void:
	economy_display_cache.clear()

func panel(rect: Rect2,title: String="") -> void:
	draw_style_box(panel_style,rect)
	hits.append({"id":"panel","rect":rect,"enabled":false})
	if not title.is_empty():
		text(title,rect.position+Vector2(22,38),24,INK)
		rule(rect.position.x+18,rect.position.y+51,rect.size.x-36)

func button(id: String,rect: Rect2,label: String,enabled: bool=true) -> void:
	var style: StyleBoxFlat=small_style.duplicate()
	var primary: bool=enabled and (id in ["build","restore","end_turn"] or (id=="construction" and build_mode))
	style.bg_color=Color("6e6142") if primary else Color(.25,.205,.14,.95)
	if enabled and hovered==id: style.bg_color=Color("85734d")
	if not enabled: style.bg_color=Color("393126")
	draw_style_box(style,rect)
	center_text(label,rect.get_center()+Vector2(0,7),19,INK if enabled else Color("968b75"))
	hits.append({"id":id,"rect":rect,"enabled":enabled})

func icon(kind: String,c: Vector2,col: Color=GOLD,s: float=1.0) -> void:
	# Existing restrained line icons match the earth-and-stone interface.
	super.icon(kind,c,Color("d4bd8e")*col,s)

func action_button(id: String,rect: Rect2,label: String,kind: String,enabled: bool=true) -> void:
	button(id,rect,"",enabled)
	icon(kind,rect.position+Vector2(27,rect.size.y*.5),Color.WHITE if enabled else Color(.55,.55,.55),.75)
	center_text(label,rect.get_center()+Vector2(15,7),19,INK if enabled else Color("968b75"))

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
	var size: Vector2=Vector2(1320,880)*view_zoom
	return Rect2(Vector2(936,532)+view_pan-size/2,size)

func scene_point(uv: Vector2) -> Vector2:
	var rect: Rect2=picture_rect()
	return rect.position+uv*rect.size

# A plot is a fixed place in the landscape. Adding buildings, selecting a site,
# opening the catalogue and toggling labels never move its neighbours.
func update_plot_views(state: Dictionary, kind: String) -> void:
	plot_views.clear()
	var sites: Array=layouts[kind].sites
	for i in state.plots.size():
		var site: Array=sites[i]
		var uv:=Vector2(site[0],site[1])
		plot_views[i]={"position":scene_point(uv),"width":float(site[2])*picture_rect().size.x/1536.0,"uv":uv}

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
	text(p.name+" · "+layouts[kind_for(p)].title,Vector2(80,50),27,INK)
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
	panel(Rect2(16,94,250,466))
	text(poi.name,Vector2(36,135),27,INK)
	text(layouts[kind_for(poi)].title+" · "+str(state.plots.size())+" 处用地",Vector2(36,167),18,SOFT)
	rule(36,185,210)
	text("领属",Vector2(36,216),17,SOFT)
	text({"player":"西岐","shang":"商军","neutral":"未归附"}[poi.owner],Vector2(175,216),19,INK)
	var built: int=0
	for plot in state.plots:
		if not plot.building.is_empty(): built+=1
	text("已建成",Vector2(36,248),17,SOFT)
	text("%d / %d" % [built,state.plots.size()],Vector2(174,248),19,INK,sans)
	text("本地产出 / 回合",Vector2(36,291),18,INK)
	if not economy_display_cache.has("income"): economy_display_cache.income=econ.local_income(poi_id)
	var local: Dictionary=economy_display_cache.income
	for i in econ.KEYS.size():
		var key: String=econ.KEYS[i]
		var y: float=324+i*30
		icon(key,Vector2(46,y-7),Color.WHITE,.65)
		text(econ.NAMES[key],Vector2(68,y),17,SOFT)
		text("+%d" % int(local[key]),Vector2(186,y),18,GREEN if poi.owner=="player" else MUTED,sans)
	rule(35,496,210)
	text("兵员储备",Vector2(36,531),18,SOFT)
	text(amount(int(econ.treasury.reserve)),Vector2(181,531),20,INK,sans)
	panel(Rect2(16,576,250,180))
	text("工匠  %d / %d" % [state.jobs.size(),econ.queue_limit(poi)],Vector2(37,613),21,INK)
	if state.jobs.is_empty():
		paragraph("工匠待命，可择地兴建。" if poi.owner=="player" else "此地产出暂不入我方府库。",Vector2(37,653),206,17)
	for i in state.jobs.size():
		var job: Dictionary=state.jobs[i]
		var name: String=econ.definitions[job.building].name if job.landmark.is_empty() else econ.landmarks[job.landmark].name
		var y: float=650+i*40
		text(name+" · %d 回合" % int(job.remaining),Vector2(37,y),16,SOFT)
		button("cancel:"+str(i),Rect2(188,y-24,59,32),"确认" if confirm_action=="cancel:"+str(i) else "撤工",poi.owner=="player")
	if not confirm_action.is_empty() and confirm_action.begins_with("cancel:"):
		text("撤工返还一半资源",Vector2(37,737),14,SOFT)

func draw_empty_site(pos: Vector2,width: float,selected: bool,show_label: bool) -> void:
	# A small timber survey stake, not a ground tile or enclosing boundary.
	var col:=Color("ddd7bc") if selected else Color("b2aa8d")
	draw_line(pos+Vector2(0,4),pos+Vector2(0,-12),Color("504a38"),3,true)
	draw_line(pos+Vector2(-5,-9),pos+Vector2(6,-9),col,3,true)
	if show_label:
		var label: String="空地"
		draw_string_outline(serif,pos+Vector2(-16,25),label,HORIZONTAL_ALIGNMENT_LEFT,-1,16,4,Color("34372c"))
		center_text(label,pos+Vector2(0,25),16,col)

func draw_world(state: Dictionary,poi: Dictionary) -> void:
	var econ=game.world.economy
	var order: Array=plot_views.keys()
	order.sort_custom(func(a,b): return plot_views[a].position.y<plot_views[b].position.y)
	if show_links and selected_landmark.is_empty() and plot_views.has(selected_plot):
		var from: Vector2=plot_views[selected_plot].position
		for i in order:
			if econ.adjacent(state.plots[selected_plot],state.plots[i]):
				draw_dashed_line(from,plot_views[i].position,Color(.74,.79,.63,.7),1,6,true)
	var labels: Array=[]
	for i in order:
		var plot: Dictionary=state.plots[i]
		var pos: Vector2=plot_views[i].position
		var width: float=plot_views[i].width
		var selected: bool=selected_plot==i and selected_landmark.is_empty()
		var job: Dictionary=econ.job_at(poi_id,i)
		var occupied: bool=not plot.building.is_empty()
		var id: String=plot.building if occupied else (str(job.building) if not job.is_empty() else blueprint)
		var texture: Texture2D=sprites[id]
		var height: float=width*texture.get_height()/texture.get_width()
		var box:=Rect2(pos-Vector2(width*.5,height),Vector2(width,height))
		if occupied or not job.is_empty():
			draw_texture_rect(texture,box,false,Color.WHITE if occupied else Color(.83,.80,.72,.65))
			var label: String=econ.definitions[id].name+" · "+str(int(plot.level)) if occupied else econ.definitions[id].name
			if not job.is_empty(): label+="  %d回合" % int(job.remaining)
			labels.append({"id":i,"text":label,"position":pos+Vector2(0,7),"selected":selected})
		else:
			draw_empty_site(pos,width,selected,planning_view or build_mode or selected or hovered=="plot:"+str(i))
			if selected and build_mode and poi.owner=="player": draw_texture_rect(texture,box,false,Color(1,1,1,.44))
		if selected: draw_line(pos+Vector2(-18,9),pos+Vector2(18,9),Color("e0d4a8"),2,true)
		var hit_rect: Rect2=box.grow(4) if occupied or not job.is_empty() else Rect2(pos-Vector2(width*.42,29),Vector2(width*.84,62))
		hits.append({"id":"plot:"+str(i),"rect":hit_rect,"enabled":true})
	for label in labels:
		var width: float=serif.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x+18
		var rect:=Rect2(label.position-Vector2(width*.5,0),Vector2(width,25))
		draw_style_box(game.make_style(Color(.23,.18,.115,.88),Color("a29d83") if label.selected else Color(.4,.42,.35,.65),1,1),rect)
		center_text(label.text,rect.get_center()+Vector2(0,5),15,INK)
		hits.append({"id":"plot:"+str(label.id),"rect":rect,"enabled":true})
	var mark_index: int=0
	var kind: String=kind_for(poi)
	for id in state.landmarks:
		var uv: Array=layouts[kind].landmarks[mini(mark_index,layouts[kind].landmarks.size()-1)]
		var pos: Vector2=scene_point(Vector2(uv[0],uv[1]))
		# The civic hall is part of the landscape. A compact plaque selects its
		# landmark; the individual monument artwork is shown in the inspector.
		button("landmark:"+id,Rect2(pos+Vector2(-76,8),Vector2(152,29)),econ.landmarks[id].name+("" if state.landmarks[id] else " · 待修复"))
		mark_index+=1

func draw_thumbnail(texture: Texture2D,poi: Dictionary,uv: Vector2=Vector2(.5,.55)) -> void:
	var rect=Rect2(1625,152,262,150)
	var source=Rect2(uv*Vector2(1536,1024)-Vector2(180,150),Vector2(360,206)).intersection(Rect2(0,0,1536,1024))
	draw_texture_rect_region(backgrounds[kind_for(poi)],rect,source,Color(.88,.91,.87))
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
		uv=plot_views[selected_plot].uv
	draw_thumbnail(sprites[id],poi,uv)
	paragraph(d.description,Vector2(1628,331),255,17,SOFT)
	rule(1628,409,252)
	text("当前产出",Vector2(1628,440),20,INK)
	if not economy_display_cache.has("current"):
		economy_display_cache.current=econ.yield_detail(poi_id,selected_plot)
		economy_display_cache.future=econ.yield_detail(poi_id,selected_plot,id,next)
	var current: Dictionary=economy_display_cache.current
	var future: Dictionary=economy_display_cache.future
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
		action_button("capture_here",Rect2(1625,766,262,48),"接战 · 1 点行动力" if poi.owner=="shang" else "占领 · 1 点行动力","flag",w.can_capture(w.units[game.selected_unit],poi))
		action_button("approach_here",Rect2(1625,824,262,48),"行军至附近","map")

func draw_toolbar(poi: Dictionary,state: Dictionary) -> void:
	panel(Rect2(14,994,780,72))
	var buttons: Array=[["construction","营建","build"],["upgrade_focus","升级","upgrade"],["demolish","拆除","demolish"],["layout","用地","map"],["settlements","据点","flag"]]
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
		button("settlement:"+owned[i].id,Rect2(34,146+n*52,342,43),owned[i].name+" · "+layouts[kind_for(owned[i])].title)
	button("page_prev",Rect2(34,475,110,42),"上一页",owned_page>0)
	button("page_next",Rect2(266,475,110,42),"下一页",(owned_page+1)*6<owned.size())

func _draw() -> void:
	if game==null or poi_id.is_empty(): return
	hits.clear()
	var poi: Dictionary=game.world.by_poi[poi_id]
	var state: Dictionary=game.world.economy.settlements[poi_id]
	var art: Texture2D=backgrounds[kind_for(poi)]
	var rect: Rect2=picture_rect()
	# Fit the entire city between the sidebars so all wall layers stay visible.
	# Zoom may crop the landscape, but never duplicate or stretch edge pixels.
	draw_rect(Rect2(0,0,1920,1080),Color("3b3225"))
	draw_texture_rect(art,rect,false)
	update_plot_views(state,kind_for(poi))
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
	for rect in [Rect2(0,0,1920,80),Rect2(16,94,250,466),Rect2(16,576,250,180),Rect2(1606,94,300,797),Rect2(0,994,1920,86)]:
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
