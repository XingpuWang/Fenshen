extends "res://scripts/hud.gd"

var poi_id: String = ""
var selected_plot: int = 0
var blueprint: String = "farm"
var selected_landmark: String = ""
var owned_page: int = 0
var confirm_action: String = ""
var backgrounds: Dictionary = {}
var sprites: Dictionary = {}
var landmark_sprites: Dictionary = {}
const LANDMARK_ART = {"lingtai":0,"fengshentai":1,"lutai":2,"zhaixing":3,"jinguang":4}

func _ready() -> void:
	super._ready()
	for kind in ["city","village","pass","ferry"]: backgrounds[kind]=load("res://assets/interiors/"+kind+".png")
	for d in game.world.economy.catalog: sprites[d.id]=load("res://assets/buildings/"+d.id+".png")
	for id in LANDMARK_ART: landmark_sprites[id]=load("res://assets/buildings/landmark_"+str(LANDMARK_ART[id])+".png")

func open(pid: String) -> void:
	poi_id=pid
	selected_plot=0
	selected_landmark=""
	confirm_action=""
	show()
	queue_redraw()

func plot_position(plot: Dictionary) -> Vector2:
	return Vector2(935,552)+Vector2((float(plot.q)+float(plot.r)*.5)*154,float(plot.r)*110)

func diamond(c: Vector2, fill: Color, border: Color, width: float=1.0) -> void:
	var pts=PackedVector2Array()
	for i in 7:
		var angle: float=TAU*i/6.0
		pts.append(c+Vector2(cos(angle)*87,sin(angle)*59))
	draw_colored_polygon(pts,fill)
	draw_polyline(pts,border,width,true)

func paragraph(value: String, pos: Vector2, width: float=282, font_size: int=18, color: Color=MUTED) -> float:
	var line: String=""
	var y: float=pos.y
	for ch in value:
		if ch=="\n" or sans.get_string_size(line+ch,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:
			text(line,Vector2(pos.x,y),font_size,color,sans)
			y+=font_size+10
			line="" if ch=="\n" else ch
		else: line+=ch
	if not line.is_empty():
		text(line,Vector2(pos.x,y),font_size,color,sans)
		y+=font_size+10
	return y

func cost_label(cost: Dictionary) -> String:
	var parts: PackedStringArray=[]
	for key in game.world.economy.KEYS:
		if cost.has(key): parts.append(game.world.economy.NAMES[key]+" "+str(int(cost[key])))
	return "  ·  ".join(parts)

func _draw() -> void:
	if game==null or poi_id.is_empty(): return
	hits.clear()
	var w=game.world
	var econ=w.economy
	var poi: Dictionary=w.by_poi[poi_id]
	var state: Dictionary=econ.settlements[poi_id]
	# The illustration has an empty central courtyard; all buildings are stateful sprites.
	draw_texture_rect(backgrounds[poi.type],Rect2(0,-70,1920,1280),false)
	draw_rect(Rect2(0,78,1920,1002),Color(.13,.11,.08,.04))
	draw_topbar()
	panel(Rect2(18,100,280,770))
	button("back",Rect2(34,116,248,43),"‹  返回九州舆图")
	text(poi.name,Vector2(40,210),37,LIGHT)
	text({"city":"城池","village":"村庄","pass":"关隘","ferry":"渡口"}[poi.type]+"  ·  "+{"player":"西岐领地","shang":"商军据点","neutral":"尚未归附"}[poi.owner],Vector2(41,247),18,GOLD)
	text("独立建设 · 势力共享资源",Vector2(41,278),16,MUTED)
	rule(40,296,236)
	text("本地每回合产出",Vector2(40,330),20,LIGHT)
	var local: Dictionary=econ.local_income(poi_id)
	for i in econ.KEYS.size():
		var key: String=econ.KEYS[i]
		var y: float=366+i*30
		icon(key,Vector2(51,y-6),GOLD,.6)
		text(econ.NAMES[key],Vector2(72,y),17,MUTED)
		text("+%d" % int(local[key]),Vector2(218,y),18,LIGHT,sans)
	text("地标加成已计入顶部势力收益" if poi.owner=="player" else "未归附：产出不进入我方府库",Vector2(40,553),14,MUTED)
	rule(40,570,236)
	text("工匠  %d / %d" % [state.jobs.size(),econ.queue_limit(poi)],Vector2(40,604),20,GOLD)
	for i in state.jobs.size():
		var job: Dictionary=state.jobs[i]
		var y: float=642+i*74
		var name: String=econ.definitions[job.building].name if job.landmark.is_empty() else econ.landmarks[job.landmark].name
		text(name+" · 余 %d 回合" % int(job.remaining),Vector2(40,y),17,LIGHT)
		button("cancel:"+str(i),Rect2(40,y+9,236,29),"确认撤工 · 返还一半" if confirm_action=="cancel:"+str(i) else "撤工 · 返还一半资源",poi.owner=="player")
	if state.jobs.is_empty(): paragraph("工匠待命\n选择空地，安排兴建。",Vector2(40,650),225,18)
	text("兵员储备  %d" % int(econ.treasury.reserve),Vector2(40,825),20,GOLD)
	# Settlement switcher supports any number of owned settlements, six per page.
	panel(Rect2(18,888,280,174),"我 方 据 点")
	var owned: Array=[]
	for p in w.pois:
		if p.owner=="player": owned.append(p)
	owned_page=clampi(owned_page,0,maxi(0,(owned.size()-1)/4))
	for i in range(owned_page*4,mini(owned.size(),owned_page*4+4)):
		var n: int=i-owned_page*4
		button("settlement:"+owned[i].id,Rect2(32+(n%2)*128,947+(n/2)*43,122,36),owned[i].name)
	button("page_prev",Rect2(214,901,26,27),"‹",owned_page>0)
	button("page_next",Rect2(248,901,26,27),"›",(owned_page+1)*4<owned.size())
	# Upper central ribbon and fixed landmark sites.
	panel(Rect2(570,100,726,62))
	center_text("经营内景  /  "+poi.name,Vector2(933,140),26,LIGHT)
	var mark_index: int=0
	for id in state.landmarks:
		var x: float=435+mark_index*890
		var active: bool=state.landmarks[id]
		if landmark_sprites.has(id): draw_texture_rect(landmark_sprites[id],Rect2(x-92,204,184,184),false,Color.WHITE if active else Color(.73,.76,.73,.9))
		button("landmark:"+id,Rect2(x-98,380,196,40),econ.landmarks[id].name+(" · 已启用" if active else " · 待修复"))
		mark_index+=1
	# Projected hex plots. Sort by depth so silhouettes overlap naturally.
	var order: Array=[]
	var captions: Array=[]
	for i in state.plots.size(): order.append(i)
	order.sort_custom(func(a,b): return plot_position(state.plots[a]).y<plot_position(state.plots[b]).y)
	for i in order:
		var plot: Dictionary=state.plots[i]
		var pos: Vector2=plot_position(plot)
		var selected: bool=selected_plot==i and selected_landmark.is_empty()
		var job: Dictionary=econ.job_at(poi_id,i)
		var outline: Color=Color(.96,.81,.38,.95) if selected else Color(.39,.36,.23,.36)
		var tint: Color=Color(.94,.76,.34,.17) if selected else Color(.5,.49,.31,.05)
		if not selected_landmark.is_empty(): tint=Color(.5,.49,.31,.02)
		diamond(pos,tint,outline,2.5 if selected else 1.0)
		if not plot.building.is_empty():
			var sz: float=134+float(plot.level)*7
			draw_texture_rect(sprites[plot.building],Rect2(pos-Vector2(sz/2,sz-32),Vector2(sz,sz)),false)
			var caption: String=econ.definitions[plot.building].name+"  "+["","Ⅰ","Ⅱ","Ⅲ"][int(plot.level)]
			captions.append({"text":caption,"position":pos})
		elif selected and sprites.has(blueprint) and poi.owner=="player":
			draw_texture_rect(sprites[blueprint],Rect2(pos-Vector2(70,106),Vector2(140,140)),false,Color(1,1,1,.43))
			center_text("待建 · "+econ.definitions[blueprint].name,pos+Vector2(0,43),16,Color("fff1b5"))
		else:
			center_text("＋",pos+Vector2(0,0),25,Color(.35,.31,.21,.75))
			center_text(econ.TERRAIN[int(plot.terrain)],pos+Vector2(0,25),15,Color("504c35"))
		if not job.is_empty():
			draw_rect(Rect2(pos+Vector2(-60,-36),Vector2(120,27)),Color(.15,.28,.29,.95))
			center_text("施工 · %d 回合" % int(job.remaining),pos+Vector2(0,-16),15,Color("c3eee2"))
		hits.append({"id":"plot:"+str(i),"rect":Rect2(pos-Vector2(66,38),Vector2(132,80)),"enabled":true})
	for caption in captions:
		var pos: Vector2=caption.position
		draw_style_box(game.make_style(Color(.13,.12,.08,.88),Color(.6,.5,.3,.4),1,4),Rect2(pos+Vector2(-72,25),Vector2(144,27)))
		center_text(caption.text,pos+Vector2(0,45),15,LIGHT)
	# Right inspector.
	panel(Rect2(1560,100,342,770),"营 建 司")
	if poi.owner!="player":
		text("此地尚未归附",Vector2(1584,195),26,LIGHT)
		paragraph("可查阅建筑与地标。占领前不能建设，产出也不会计入我方府库。",Vector2(1584,240),290)
		button("capture_here",Rect2(1584,366,294,48),"占领此地 · 1 点行动力",w.can_capture(w.units[game.selected_unit],poi))
		button("approach_here",Rect2(1584,428,294,48),"返回舆图 · 行军至附近")
		if not selected_landmark.is_empty(): paragraph(econ.landmarks[selected_landmark].description,Vector2(1584,530),290)
	elif not selected_landmark.is_empty():
		var d: Dictionary=econ.landmarks[selected_landmark]
		text(d.name,Vector2(1584,199),30,LIGHT)
		text("独一地标 · 固定位置",Vector2(1584,235),17,GOLD)
		var y: float=paragraph(d.description,Vector2(1584,280),290,19,LIGHT)
		y=paragraph(d.source+"；效果为游戏设计。",Vector2(1584,y+20),290,15)
		paragraph(cost_label(d.cost),Vector2(1584,y+30),290,17,GOLD)
		var why: String=econ.landmark_reason(poi,selected_landmark)
		button("restore",Rect2(1584,624,294,50),"修复地标 · %d 回合" % int(d.turns),why.is_empty())
		paragraph(why if not why.is_empty() else "竣工后生效；新产出从下一次结算起入库。",Vector2(1584,710),290,17)
	else:
		draw_plot_inspector(poi,state)
	# Building palette: always visible, costs and lock reasons live in inspector.
	panel(Rect2(318,888,1224,174))
	text("营建目录",Vector2(338,916),17,GOLD)
	text("先选地块，再选建筑；选中已有建筑可升级。",Vector2(460,916),16,MUTED)
	for i in econ.catalog.size():
		var d: Dictionary=econ.catalog[i]
		var rect=Rect2(331+i*100,929,94,119)
		var available: bool=poi.type in d.types and econ.unlocked(d.unlock,w.by_poi)
		var chosen: bool=blueprint==d.id
		draw_style_box(game.make_style(Color("51442e") if chosen else Color("2d2923"),GOLD if chosen else Color("65573e"),2 if chosen else 1,4),rect)
		draw_texture_rect(sprites[d.id],Rect2(rect.position+Vector2(5,0),Vector2(84,80)),false,Color.WHITE if available else Color(.5,.5,.5,.6))
		center_text(d.name,rect.position+Vector2(47,97),16,LIGHT if available else MUTED)
		center_text("可营建" if available else ("仙道未启" if not d.unlock.is_empty() else "据点限制"),rect.position+Vector2(47,113),11,MUTED)
		hits.append({"id":"blueprint:"+d.id,"rect":rect,"enabled":poi.owner=="player"})
	button("end_turn",Rect2(1560,888,342,82),"结束回合 · 结算府库")
	var recruit_status: String=w.recruit_reason(w.units[game.selected_unit],poi)
	button("recruit",Rect2(1560,984,342,50),"为"+w.units[game.selected_unit].name+"补兵",recruit_status.is_empty())
	draw_rect(Rect2(1560,1037,342,29),BG)
	center_text("每人 2 粮草 · 至多 500 人 · 1 点行动力" if recruit_status.is_empty() else recruit_status,Vector2(1731,1057),14,MUTED)
	if not game.toast.is_empty():
		var tw: float=serif.get_string_size(game.toast,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
		draw_style_box(game.make_style(Color(.13,.15,.12,.95),GOLD,1,5),Rect2(930-tw/2-20,827,tw+40,43))
		center_text(game.toast,Vector2(930,856),18,LIGHT)

func draw_plot_inspector(poi: Dictionary, state: Dictionary) -> void:
	var econ=game.world.economy
	var plot: Dictionary=state.plots[selected_plot]
	var id: String=blueprint if plot.building.is_empty() else plot.building
	var d: Dictionary=econ.definitions[id]
	var target: int=int(plot.level)+1
	text(d.name,Vector2(1584,198),30,LIGHT)
	text("地块 %02d  ·  %s" % [selected_plot+1,econ.TERRAIN[int(plot.terrain)]],Vector2(1584,235),17,GOLD)
	paragraph(d.description,Vector2(1584,278),286,18,LIGHT)
	var detail: Dictionary=econ.yield_detail(poi_id,selected_plot,id,mini(3,target))
	text(("建成" if plot.building.is_empty() else "升至 %d 级" % mini(3,target))+"产出  +%d %s / 回合" % [detail.amount,econ.NAMES[detail.resource]],Vector2(1584,391),18,GOLD)
	paragraph("、".join(detail.sources) if not detail.sources.is_empty() else "邻接加成：无",Vector2(1584,425),286,16)
	text("地形与邻接总加成上限 60%",Vector2(1584,487),15,MUTED)
	paragraph(cost_label(econ.cost_for(id,mini(3,target))),Vector2(1584,529),286,17,GOLD)
	var why: String=econ.build_reason(poi,selected_plot,id,game.world.by_poi)
	button("build",Rect2(1584,624,294,50),("兴建" if plot.building.is_empty() else "升级至 %d 级" % mini(3,target))+" · %d 回合" % mini(3,target),why.is_empty())
	paragraph(why if not why.is_empty() else "费用立即扣除；升级施工期间保留原等级产出。",Vector2(1584,710),286,17)
	if not plot.building.is_empty():
		button("demolish",Rect2(1584,794,294,40),"再次点击确认拆除 · 不返资源" if confirm_action=="demolish" else "拆除建筑 · 不返资源",econ.job_at(poi_id,selected_plot).is_empty())

func hit_test(p: Vector2) -> Dictionary:
	for i in range(hits.size()-1,-1,-1):
		if hits[i].rect.has_point(p): return hits[i]
	return {"id":"panel","enabled":false}

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered=str(hit_test(event.position).get("id",""))
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var hit: Dictionary=hit_test(event.position)
		if hit.get("enabled",false): command(hit.id)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: game.close_settlement()
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
		selected_landmark=""
		confirm_action=""
	elif id.begins_with("blueprint:"):
		blueprint=id.trim_prefix("blueprint:" )
		selected_landmark=""
		confirm_action=""
		if not econ.settlements[poi_id].plots[selected_plot].building.is_empty(): game.say("请先选择一块空地，再安排新建筑")
	elif id.begins_with("landmark:"):
		selected_landmark=id.trim_prefix("landmark:")
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
			"back": game.close_settlement()
			"page_prev": owned_page-=1
			"page_next": owned_page+=1
			"build":
				var plot: Dictionary=econ.settlements[poi_id].plots[selected_plot]
				var building: String=blueprint if plot.building.is_empty() else plot.building
				var why: String=econ.build(poi,selected_plot,building,w.by_poi)
				game.say("工匠已开工 · 结束回合推进建设" if why.is_empty() else why)
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
				game.action(id)
	game.refresh()
