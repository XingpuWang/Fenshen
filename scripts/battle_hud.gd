extends Control
## Battle controls and commander cards, in the same design coordinates as the arena.
const Rules = preload("res://scripts/battle_rules.gd")
const Textures = preload("res://scripts/runtime_textures.gd")
const Icons = preload("res://scripts/skill_icons.gd")
const Commander = preload("res://scripts/commander_panel.gd")
const Nezha = preload("res://scripts/nezha_art.gd")
const Wenzhong = preload("res://scripts/wenzhong_art.gd")
const FONT = preload("res://assets/fonts/ShanheSerif.otf")
const PALE := Color("fff0d8")
const GOLD := Color("f0cd98")
const RULE := Color("ac815b9e")
const SHADOW := Color("342026")

# Source regions in the painted atlas. Portrait and skill frames have open centers.
const PURPLE_CARD := Rect2(10,68,699,216)
const RED_CARD := Rect2(737,70,700,215)
const PURPLE_PORTRAIT := Rect2(15,328,245,317)
const RED_PORTRAIT := Rect2(268,327,248,318)
const GOLD_SQUARE := Rect2(538,402,186,187)
const RING := Rect2(1146,356,278,283)
const JADE_STRIP := Rect2(45,701,684,81)
const HEALTH_TRACK := Rect2(806,715,591,44)
const HEALTH_FILL := Rect2(70,800,626,47)
const BANNER := Rect2(709,945,497,75)
const KEYCAP := Rect2(576,927,113,110)
const PLAQUE := Rect2(25,932,265,100)

const CARDS := [Rect2(25,817,652,247), Rect2(1218,817,677,247)]
const AUTO := Rect2(765,830,130,130)
const ULTIMATE := Rect2(963,786,166,169)
const RING_CENTER := Vector2(1046,869.6)
const RING_RADIUS := 72.5
const R_BADGE := Rect2(1098,806,42,40)
const STRIP := Rect2(687,997,527,66)

var battle: Control
var hits: Array[Dictionary] = []
var atlas: Texture2D = Textures.get_texture("res://assets/ui/battle/hud_kit.png")
var disc := PackedVector2Array()
var circle_uv := PackedVector2Array()
var circle_art_id := ""
var resting_uv := PackedVector2Array()
static var resting_icons: Dictionary = {}

func _init() -> void:
	for i in 72:
		var direction := Vector2.from_angle(i * TAU / 72)
		disc.append(RING_CENTER + direction * 67)
		resting_uv.append((direction+Vector2.ONE)*.5)

func paint(canvas: CanvasItem, source: Rect2, dest: Rect2, tint := Color.WHITE) -> void:
	canvas.draw_texture_rect_region(atlas,dest,source,tint)

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _process(_delta: float) -> void:
	queue_redraw()

func label(value: String, at: Vector2, font_size: int, color: Color, centered := false) -> void:
	if centered: at.x -= FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x*.5
	draw_string(FONT,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw() -> void:
	if battle == null or battle.sim == null: return
	hits.clear()
	_draw_card(0)
	_draw_card(1)
	for x in [716,1184]:
		var points := PackedVector2Array([Vector2(x,861),Vector2(x+1,904),Vector2(x,948),Vector2(x-1,904)])
		draw_colored_polygon(points,Color("ebbd8399"))
		points=PackedVector2Array([Vector2(x,898),Vector2(x+4,904),Vector2(x,910),Vector2(x-4,904),Vector2(x,898)])
		draw_polyline(points,GOLD,1.2,true)
	_draw_abilities()
	_draw_playback()
	if battle.sim.result.is_empty(): _draw_hint()

func hit_at(point: Vector2) -> Dictionary:
	for hit in hits:
		if not hit.rect.has_point(point): continue
		if hit.has("radius") and point.distance_squared_to(hit.center) > hit.radius * hit.radius: continue
		return hit
	return {}

static func purple_theme(hero: String, faction: String) -> bool:
	return hero == "wenzhong" or (hero != "nezha" and faction == "shang")

func _draw_card(side: int) -> void:
	var sim: Rules = battle.sim
	var unit: Dictionary = sim.encounter.player if side == 0 else sim.encounter.enemy
	var hero := sim.hero_for(side)
	var purple := purple_theme(hero.hero_id,battle.army_faction(side))
	var card: Rect2 = CARDS[side]
	var plate := PURPLE_CARD if purple else RED_CARD
	# Compress the lower cloud / lotus border so the stats sit on clear lacquer.
	paint(self,Rect2(plate.position,Vector2(plate.size.x,56)),Rect2(card.position,Vector2(card.size.x,53)))
	paint(self,Rect2(plate.position+Vector2(0,56),Vector2(plate.size.x,plate.size.y-120)),Rect2(card.position+Vector2(0,53),Vector2(card.size.x,card.size.y-97)))
	paint(self,Rect2(plate.position.x,plate.end.y-64,plate.size.x,64),Rect2(card.position.x,card.end.y-44,card.size.x,44))
	var frame := Rect2(card.position+Vector2(23,20),Vector2(164,208))
	# Slight overlap under the painted inner lip prevents a seam at fractional scales.
	var inner := Rect2(frame.position+Vector2(19,19),Vector2(133,175))
	match hero.hero_id:
		"nezha": Nezha.draw_portrait(self,inner,"battle")
		"wenzhong": Wenzhong.draw_portrait(self,inner,"battle")
		_: Commander.portrait(self,hero.hero_id,inner)
	paint(self,PURPLE_PORTRAIT if purple else RED_PORTRAIT,frame)

	var x := card.position.x + 195
	var right := card.end.x - 28
	var name: String = unit.name
	var name_width := FONT.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,34).x
	label(name,Vector2(x,868),34,PALE)
	var split := x + name_width + 17
	draw_line(Vector2(split,846),Vector2(split,865),RULE,1.5)
	draw_string(FONT,Vector2(split+16,866),str(unit.get("title",battle.army_name(side)+"主将")),
		HORIZONTAL_ALIGNMENT_LEFT,right-split-26,21,GOLD)
	label("生命",Vector2(x,904),22,GOLD)
	var ratio := clampf(hero.hp / hero.max_hp,0,1)
	var track := Rect2(x+61,883,right-x-145,22)
	paint(self,HEALTH_TRACK,track)
	if ratio > 0:
		var fill := track.grow(-3)
		fill.size.x *= ratio
		paint(self,HEALTH_FILL,fill)
	draw_string(FONT,Vector2(right-77,904),"%d%%" % ceili(ratio*100),HORIZONTAL_ALIGNMENT_RIGHT,65,22,PALE)
	var alive := sim.remaining(side)
	label("兵力",Vector2(x,935),22,GOLD)
	label("%d / %d" % [alive,sim.initial[side]],Vector2(x+67,935),23,PALE)
	_draw_formation(sim.remaining_roster(side), Rect2(x-3,946,right-x-5,59))
	label("士气",Vector2(x,1029),21,GOLD)
	label("%d / %d" % [floori(sim.morale[side]+.00001),Rules.FINISHER_COST],Vector2(x+61,1029),22,PALE)
	draw_line(Vector2(x+180,1012),Vector2(x+180,1031),RULE,1.5)
	label("击杀",Vector2(x+199,1029),21,GOLD)
	label(str(sim.kills[side]),Vector2(x+260,1029),22,PALE)
	hits.append({"id":"commander_%d" % side,"rect":card,"enabled":false})

func _draw_formation(roster: Array, rect: Rect2) -> void:
	var cell := rect.size.x / 3
	var edge := PackedVector2Array([rect.position+Vector2(6,0),Vector2(rect.end.x-6,rect.position.y),
		Vector2(rect.end.x,rect.position.y+6),rect.end-Vector2(0,6),rect.end-Vector2(6,0),
		Vector2(rect.position.x+6,rect.end.y),Vector2(rect.position.x,rect.end.y-6),rect.position+Vector2(0,6)])
	draw_colored_polygon(edge,Color("2b202660"))
	edge.append(edge[0])
	draw_polyline(edge,RULE,1.3,true)
	for i in 3:
		var pos := rect.position + Vector2(cell*i,0)
		if i > 0: draw_line(pos+Vector2(0,6),pos+Vector2(0,rect.size.y-6),RULE,1.2)
		if i >= roster.size() or roster[i].is_empty(): continue
		var kind: String = roster[i].type
		var at := pos + Vector2(25,31)
		match kind:
			"halberd": _halberd(self, at, 1.0)
			"archer":
				draw_set_transform(at, -.30)
				draw_polyline(PackedVector2Array([Vector2(-7,-17),Vector2(2,-13),Vector2(7,-5),Vector2(7,4),Vector2(2,13),Vector2(-7,17)]), GOLD, 2.8, true)
				draw_line(Vector2(-7,-17), Vector2(-7,17), PALE, 1.0, true)
				draw_line(Vector2(-13,0), Vector2(14,0), PALE, 2, true)
				draw_colored_polygon(PackedVector2Array([Vector2(16,0),Vector2(9,-3),Vector2(9,3)]), PALE)
				draw_set_transform(Vector2.ZERO)
			"cavalry":
				draw_set_transform(at)
				var horse := PackedVector2Array([Vector2(-10,15),Vector2(-8,4),Vector2(-11,-4),Vector2(-5,-13),Vector2(1,-17),Vector2(1,-10),Vector2(5,-14),Vector2(8,-5),Vector2(15,3),Vector2(11,7),Vector2(3,4),Vector2(0,8),Vector2(1,15)])
				draw_colored_polygon(horse,GOLD)
				draw_line(Vector2(-6,-5), Vector2(-9,4), PALE, 1.6, true)
				draw_circle(Vector2(4,-5),1.4,SHADOW)
				draw_set_transform(Vector2.ZERO)
		label(Rules.TYPES[kind].name,pos+Vector2(48,25),20,GOLD)
		label(str(roster[i].count),pos+Vector2(48,50),22,PALE)

func _halberd(canvas: CanvasItem, at: Vector2, scale: float) -> void:
	canvas.draw_set_transform(at,-.81,Vector2.ONE*scale)
	canvas.draw_line(Vector2(0,22),Vector2(0,-13),Color("91633c"),4,true)
	canvas.draw_line(Vector2(-1,21),Vector2(-1,-12),GOLD,1.6,true)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(0,-24),Vector2(4,-9),Vector2(0,-3),Vector2(-3,-9)]),PALE)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(1,-5),Vector2(8,-11),Vector2(9,-18),Vector2(11,-10),Vector2(8,-4),Vector2(1,0)]),GOLD)
	canvas.draw_line(Vector2(-4,-3),Vector2(4,-3),Color("e8ab5c"),2,true)
	canvas.draw_set_transform(Vector2.ZERO)

func _draw_abilities() -> void:
	var sim: Rules = battle.sim
	var kit := sim.kits[0]
	var hero := sim.hero_for(0)
	var purple := purple_theme(hero.hero_id,battle.army_faction(0))
	var accent := Color("c29aee") if purple else Color("ff9971")
	var ready: bool = sim.finisher_reason(0).is_empty() and not battle.paused
	var ability: Dictionary = kit.battle
	var automatic := Icons.artwork(ability.id)
	var square := AUTO.grow(-8)
	draw_rect(square,SHADOW)
	if automatic.is_empty():
		_halberd(self,square.get_center(),1.8)
	else:
		var source: Rect2 = automatic.source
		var fit := source.size * minf(square.size.x/source.size.x,square.size.y/source.size.y)
		draw_texture_rect_region(automatic.texture,Rect2(square.get_center()-fit*.5,fit),source)
	paint(self,GOLD_SQUARE,AUTO,Color("fff1cc") if battle.hovered=="auto" else Color.WHITE)
	paint(self,PLAQUE,Rect2(849,818,74,39))
	label("自动",Vector2(886,845),20,PALE,true)
	_caption(ability.name,Vector2(AUTO.get_center().x,985),25)
	hits.append({"id":"auto","rect":AUTO.merge(Rect2(849,818,74,39)),"enabled":false})

	var ultimate: Dictionary = kit.ultimate
	var art := Icons.artwork(ultimate.id)
	draw_circle(RING_CENTER,66,SHADOW,true,-1,true)
	if not art.is_empty():
		if ultimate.id != circle_art_id:
			var source: Rect2 = art.source
			var texture: Texture2D = art.texture
			var square_size := minf(source.size.x,source.size.y)
			circle_uv.clear()
			for p in disc:
				var direction := (p-RING_CENTER)/67
				circle_uv.append((source.get_center()+direction*square_size*.5)/texture.get_size())
			circle_art_id=ultimate.id
		if ready:
			draw_colored_polygon(disc,Color.WHITE,circle_uv,art.texture)
		else:
			draw_colored_polygon(disc,Color("b7b0c0"),resting_uv,_resting_icon(ultimate.id,art))
	paint(self,RING,ULTIMATE)
	var fraction := clampf(sim.morale[0]/Rules.FINISHER_COST,0,1)
	if fraction > 0:
		var end := -PI*.5 + TAU*fraction
		draw_arc(RING_CENTER,RING_RADIUS,-PI*.5,end,maxi(2,ceili(fraction*96)),accent.darkened(.30),8,true)
		draw_arc(RING_CENTER,RING_RADIUS-1,-PI*.5,end,maxi(2,ceili(fraction*96)),accent,4,true)
		draw_circle(RING_CENTER+Vector2.from_angle(end)*RING_RADIUS,2.4,PALE,true,-1,true)
	if ready or battle.hovered == "finisher":
		draw_arc(RING_CENTER,RING_RADIUS+9,0,TAU,90,Color(GOLD,.82 if ready else .4),2,true)
	paint(self,KEYCAP,R_BADGE)
	label("R",Vector2(R_BADGE.get_center().x,R_BADGE.position.y+29),23,PALE,true)
	_caption(ultimate.name,Vector2(RING_CENTER.x,968),26)
	_caption("%d / %d" % [floori(sim.morale[0]+.00001),Rules.FINISHER_COST],Vector2(RING_CENTER.x,991),20,GOLD)
	hits.append({"id":"finisher","rect":ULTIMATE,"center":RING_CENTER,"radius":RING_RADIUS+9,"enabled":true})
	hits.append({"id":"finisher","rect":R_BADGE,"enabled":true})

# Cache the inactive state at icon size, including alpha from effect-based skill paintings.
func _resting_icon(id: String, art: Dictionary) -> Texture2D:
	if not resting_icons.has(id):
		var texture: Texture2D = art.texture
		var source: Rect2 = art.source
		var side := floori(minf(source.size.x,source.size.y))
		var image := texture.get_image()
		if image.is_compressed(): image.decompress()
		var tile := image.get_region(Rect2i(Vector2i(source.get_center())-Vector2i(side,side)/2,Vector2i(side,side)))
		tile.clear_mipmaps()
		tile.resize(224,224,Image.INTERPOLATE_LANCZOS)
		tile.convert(Image.FORMAT_LA8)
		tile.generate_mipmaps()
		resting_icons[id]=ImageTexture.create_from_image(tile)
	return resting_icons[id]

func _caption(value: String, center: Vector2, size: int, tint := PALE) -> void:
	var width := FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	var at := center - Vector2(width*.5,0)
	draw_string_outline(FONT,at+Vector2(0,1),value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,5,Color("392123df"))
	draw_string(FONT,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,tint)

func _draw_playback() -> void:
	paint(self,JADE_STRIP,STRIP)
	var x := STRIP.get_center().x
	var y := STRIP.get_center().y
	draw_line(Vector2(x,y-13),Vector2(x,y+13),RULE,1.5)
	var enabled: bool = battle.sim.result.is_empty()
	for i in 2:
		var id := "pause" if i == 0 else "speed"
		var rect := Rect2(STRIP.position+Vector2(38+i*(STRIP.size.x-76)*.5,6),Vector2((STRIP.size.x-76)*.5,STRIP.size.y-12))
		var tint := Color("fff3c9") if enabled and battle.hovered == id else PALE
		if enabled and battle.hovered == id: draw_rect(rect.grow(-4),Color("ffc57b16"))
		var icon_x := rect.position.x + 33
		if i == 0 and not battle.paused:
			for n in 2: draw_rect(Rect2(icon_x+n*10,y-8,5,17),tint)
		else:
			for n in (2 if i == 1 else 1):
				var p := Vector2(icon_x+n*11,y)
				draw_colored_polygon(PackedVector2Array([p+Vector2(-2,-9),p+Vector2(10,0),p+Vector2(-2,9)]),tint)
		var action_label: String = ("继续" if battle.paused else "暂停") if i == 0 else "×%d" % battle.speed
		label(action_label,Vector2(icon_x+40,y+8),24,tint)
		label("Space" if i == 0 else "X",Vector2(rect.end.x-47,y+8),22,GOLD,true)
		hits.append({"id":id,"rect":rect,"enabled":enabled})

func _auto_state(hero: Rules.Fighter) -> String:
	if hero.hp <= 0: return "主将已退场"
	if hero.action == "cast": return "施放中" if hero.age < hero.impact else "收招中"
	return "冷却 %.1f 秒" % hero.skill_clock if hero.skill_clock > 0 else "就绪 · 接敌后自动施放"

func _draw_hint() -> void:
	var sim: Rules = battle.sim
	var title := ""
	var detail := ""
	var center := 0.0
	match battle.hovered:
		"commander_0","commander_1":
			var side := 0 if battle.hovered=="commander_0" else 1
			var passive: Dictionary=sim.kits[side].passive
			title="被动 · "+str(passive.name)
			var hero:=sim.hero_for(side)
			detail=str(passive.description)+"\n"+str(sim.kits[side].battle.name)+" · "+_auto_state(hero)
			center=CARDS[side].get_center().x
		"auto","finisher":
			var auto: bool=battle.hovered=="auto"
			var skill: Dictionary=sim.kits[0].battle if auto else sim.kits[0].ultimate
			title=("自动战技 · " if auto else "终结技 · ")+str(skill.name)
			if auto:
				detail=_auto_state(sim.hero_for(0))
			else:
				detail=sim.finisher_reason(0)
				if detail.is_empty(): detail="恢复战斗后可释放" if battle.paused else "点击或按 R · 立即释放"
			center=AUTO.get_center().x if auto else RING_CENTER.x
		_: return
	# A single fixed-width wrapped line group keeps long passive descriptions on screen.
	var width:=clampf(FONT.get_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x+42,276,520)
	var wrapped:=FONT.get_multiline_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,width-34,20)
	var box:=Rect2(center-width*.5,788-53-wrapped.y,width,53+wrapped.y)
	draw_rect(box,Color("302029f5"))
	draw_rect(box,Color("ba925e"),false,1.5)
	label(title,box.position+Vector2(17,29),22,GOLD)
	draw_multiline_string(FONT,box.position+Vector2(17,56),detail,HORIZONTAL_ALIGNMENT_LEFT,width-34,20,-1,PALE)
