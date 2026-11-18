extends Control
## Presentation consumes fixed simulation time: pause/speed also affect sprites and effects.
signal returned(result: Dictionary)
const BattleHud = preload("res://scripts/battle_hud.gd")
const Rules = preload("res://scripts/battle_rules.gd")
const NezhaArt = preload("res://scripts/nezha_art.gd")
const WenzhongArt = preload("res://scripts/wenzhong_art.gd")
const FONT = preload("res://assets/fonts/ShanheSerif.otf")
const SANS = preload("res://assets/fonts/ShanheSans.otf")
const BG = preload("res://assets/battle/fortress_amber.webp")
const ZHOU = preload("res://assets/battle/motion/zhou_upright_v3.png")
const SHANG = preload("res://assets/battle/motion/shang_upright_v3.png")
const GENERAL = preload("res://assets/battle/motion/general_upright_v3.png")
const TEXTURES = {"zhou":ZHOU,"shang":SHANG,"general":GENERAL}
const CREAM = Color("fff0d2")
const GOLD = Color("e6b46e")
const MUTED = Color("c9b49a")
const INK = Color("271c22")
const TEAM = [Color("e99b64"), Color("baa0da")]
# 1920x1080 design-space contract. Backdrop ground starts at y≈425 after framing.
const BACKDROP := Rect2(-48,-240,2016,1134)
const FEET_AREA := Rect2(160,500,1600,300)
const ACTOR_SAFE_AREA := Rect2(20,170,1880,650)
const SOLDIER_HEIGHT := 108.0
const HERO_HEIGHT := 180.0
const WENZHONG_HEIGHT := 194.0
class SpriteFrame:
	var source: Rect2
	var rect: Rect2
var draw_frames: Dictionary={}
var frame_catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/battle_frames.json"))
var sim: Rules
var battle_hud: BattleHud
var paused := false
var speed := 1
var accumulator := 0.0
var effects: Array[Dictionary] = []
var hits: Array[Dictionary] = []
var hovered := ""
var debug_bodies := false
var returning := false
var audio: Array[AudioStreamPlayer] = []
var sound_cooldown := 0.0
var total_frames := 0
var wall_time := 0.0
var result_age := 0.0
var profile_enabled:=false
var profile_sim_ms:=0.0
var profile_draw_ms:=0.0
var profile_steps:=0
var damage_labels: Dictionary={}

func _init() -> void:
	# Compile JSON regions once; the hot draw path does not rebuild dictionaries
	# or compute off-screen QA bounds for every sprite every frame.
	frame_catalog.erase("nezha")
	frame_catalog.erase("wenzhong")
	NezhaArt.prepare()
	WenzhongArt.prepare()
	for key in frame_catalog:
		var entry: Dictionary=frame_catalog[key]
		var height: float=SOLDIER_HEIGHT if key in ["zhou","shang"] else (WENZHONG_HEIGHT if key=="wenzhong" else HERO_HEIGHT)
		var ratio: float=height/float(entry.body_height)
		var frames: Array[SpriteFrame]=[]
		for frame in entry.frames:
			var compiled:=SpriteFrame.new()
			var src: Array=frame.source
			compiled.source=Rect2(src[0],src[1],src[2],src[3])
			compiled.rect=Rect2(-Vector2(frame.pivot[0],frame.pivot[1])*ratio,compiled.source.size*ratio)
			frames.append(compiled)
		draw_frames[key]=frames

func setup(encounter: Dictionary) -> void:
	sim = Rules.new(encounter)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_window().mouse_exited.connect(_clear_hover)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	battle_hud=BattleHud.new()
	battle_hud.battle=self
	add_child(battle_hud)
	battle_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if DisplayServer.get_name() != "headless":
		for name in ["drum", "clash", "fire", "thunder"]:
			var player := AudioStreamPlayer.new()
			player.stream = load("res://assets/battle/" + name + ".wav")
			player.volume_db = -17
			player.max_polyphony = 2
			add_child(player)
			audio.append(player)
		_audio(0)

func _process(delta: float) -> void:
	if sim == null: return
	var profile_start:=Time.get_ticks_usec() if profile_enabled else 0
	profile_steps=0
	total_frames += 1
	wall_time += delta
	if not paused:
		accumulator += minf(delta, 0.1) * speed
		while accumulator >= Rules.STEP:
			accumulator -= Rules.STEP
			sim.advance()
			advance_effects(Rules.STEP)
			profile_steps+=1
	if profile_enabled: profile_sim_ms=(Time.get_ticks_usec()-profile_start)/1000.0
	queue_redraw()

func advance_effects(dt: float) -> void:
	if not sim.result.is_empty():
		result_age += dt
		for f in sim.fighters:
			f.hit_age += dt
			f.magic_hit_age += dt
			if f.hp<=0: f.death_age+=dt
			else:
				if f.action in ["attack","cast","finisher"]:
					f.age += dt
					if f.age >= f.duration: f.action = "idle"
				f.walking=false
	sound_cooldown -= dt
	for effect in effects: effect.age += dt
	effects = effects.filter(func(e: Dictionary) -> bool: return e.age < e.life)
	for event in sim.events:
		if event.kind=="interrupt":
			# Preserve already resolved damage labels, remove cancelled cast visuals.
			effects=effects.filter(func(fx: Dictionary)->bool: return not (fx.get("source",-1)==event.source and fx.kind in ["ring","windup"]))
			continue
		var e := event.duplicate()
		e.age = 0.0
		e.life = e.get("life",1.4 if e.kind in ["skill", "finisher"] else 0.7)
		if e.kind in ["hit","skill_hit","finisher_hit","burn_hit","splash_hit"]:
			var font_size:=20 if e.kind in ["burn_hit","splash_hit"] else (26 if e.kind=="hit" else 34)
			var key:=Vector2i(int(e.amount),font_size)
			if not damage_labels.has(key):
				if damage_labels.size()>=256: damage_labels.clear()
				var line:=TextLine.new()
				line.add_string(str(e.amount),SANS,font_size)
				damage_labels[key]=line
			e.label=damage_labels[key]
		effects.append(e)
		if e.kind in ["skill", "finisher"]:
			var source: Rules.Fighter=sim.fighters[int(e.source)]
			_audio(3 if source.hero_id=="wenzhong" else (2 if source.hero_id=="nezha" else 2+int(e.side)))
		elif e.kind == "hit" and sound_cooldown <= 0:
			_audio(1)
			sound_cooldown = 0.15
	sim.events.clear()

func _audio(index: int) -> void:
	if not audio.is_empty(): audio[index].play()

func _clear_hover() -> void:
	hovered = ""

func hit_at(point: Vector2) -> Dictionary:
	for hit in hits:
		if hit.rect.has_point(point): return hit
	return battle_hud.hit_at(point)

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered = hit_at(event.position).get("id","")
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := hit_at(event.position)
		if hit.get("enabled",false): activate(hit.id)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: activate("pause")
			KEY_X: activate("speed")
			KEY_R: activate("finisher")
			KEY_ENTER, KEY_KP_ENTER: activate("return")
			KEY_F3: debug_bodies = not debug_bodies

func activate(id: String) -> void:
	match id:
		"pause":
			if sim.result.is_empty():
				paused = not paused
				for player in audio: player.stream_paused = paused
		"speed":
			if sim.result.is_empty(): speed = 2 if speed == 1 else 1
		"finisher":
			if not paused: sim.use_finisher(0)
		"return":
			if not sim.result.is_empty() and result_age>=1.35 and not returning:
				returning = true
				returned.emit(sim.result)

func text(value: String, at: Vector2, font_size := 22, color := CREAM, centered := false) -> void:
	var w := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if centered else 0.0
	var point := at - Vector2(w * 0.5 if centered else 0, 0)
	draw_string(FONT, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func panel(rect: Rect2, fill := INK, border := GOLD) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	draw_style_box(style, rect)

func button(id: String, rect: Rect2, label: String, enabled := true) -> void:
	panel(rect, Color("6f4333") if hovered == id and enabled else Color("34242a"), GOLD if enabled else Color("6d5b56"))
	text(label, rect.get_center() + Vector2(0, 8), 22, CREAM if enabled else Color("99877a"), true)
	hits.append({"id": id, "rect": rect, "enabled": enabled})

func bar(rect: Rect2, value: float, color: Color) -> void:
	draw_rect(rect, Color("4a3533"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(value, 0, 1), rect.size.y)), color)
	draw_rect(rect, Color(1, 0.83, 0.6, 0.35), false, 1)

func ground(p: Vector2) -> Vector2:
	return FEET_AREA.position+Vector2(p.x/1920.0,(p.y+25.0)/765.0)*FEET_AREA.size

func sprite_key(f: Rules.Fighter) -> String:
	if not f.hero: return "shang" if army_faction(f.side)=="shang" else "zhou"
	var id := f.hero_id
	if id.is_empty(): id = Rules.Catalog.hero_id(sim.encounter.player if f.side==0 else sim.encounter.enemy)
	return id if id in ["nezha","wenzhong"] else "general"

func army_faction(side: int) -> String:
	var unit: Dictionary=sim.encounter.player if side==0 else sim.encounter.enemy
	return str(unit.get("faction","player" if side==0 else "shang"))

func army_name(side: int) -> String:
	return "商军" if army_faction(side)=="shang" else "西岐"

func nezha_pose(f: Rules.Fighter) -> Dictionary:
	if f.hp <= 0: return {"clip":"defeat","time":f.death_age}
	if f.action in ["attack","cast","finisher"]:
		return {"clip":{"attack":"attack","cast":"qiankun","finisher":"samadhi"}[f.action],"time":f.age}
	if f.hit_age < NezhaArt.duration("hit"): return {"clip":"hit","time":f.hit_age}
	return {"clip":"run" if f.walking else "idle","time":f.stride if f.walking else sim.elapsed}

func wenzhong_pose(f: Rules.Fighter) -> Dictionary:
	if f.hp <= 0: return {"clip":"defeat","time":f.death_age}
	if f.action in ["attack","cast","finisher"]:
		return {"clip":{"attack":"attack","cast":"thunder_whip","finisher":"nine_thunders"}[f.action],"time":f.age}
	if f.hit_age < WenzhongArt.duration("hit"): return {"clip":"hit","time":f.hit_age}
	return {"clip":"run" if f.walking else "idle","time":f.stride if f.walking else sim.elapsed}

func sprite_geometry(f: Rules.Fighter, pose: Vector2i) -> Dictionary:
	var key := sprite_key(f)
	if key == "nezha":
		var depth := lerpf(.88,1.03,clampf((f.pos.y+25.0)/765.0,0,1))
		var current := nezha_pose(f)
		return NezhaArt.geometry(NezhaArt.frame(current.clip,current.time),ground(f.pos),HERO_HEIGHT*depth,f.facing)
	if key == "wenzhong":
		var depth := lerpf(.88,1.03,clampf((f.pos.y+25.0)/765.0,0,1))
		var current := wenzhong_pose(f)
		return WenzhongArt.geometry(WenzhongArt.frame(current.clip,current.time),ground(f.pos),WENZHONG_HEIGHT*depth,f.facing)
	var entry: Dictionary=frame_catalog[key]
	var frame: Dictionary=entry.frames[pose.y*4+pose.x]
	var raw: Array=frame.source
	var source:=Rect2(raw[0],raw[1],raw[2],raw[3])
	var perspective:=lerpf(0.88,1.03,clampf((f.pos.y+25.0)/765.0,0,1))
	var body_height: float=(WENZHONG_HEIGHT if key=="wenzhong" else HERO_HEIGHT) if f.hero else SOLDIER_HEIGHT
	var ratio: float=body_height*perspective/float(entry.body_height)
	var pivot:=Vector2(frame.pivot[0],frame.pivot[1])*ratio
	var destination:=Rect2(-pivot,source.size*ratio)
	var flip: bool=f.facing!=(-1 if key in ["shang","wenzhong"] else 1)
	var bounds:=Rect2(ground(f.pos)+Vector2(-destination.end.x if flip else destination.position.x,destination.position.y),destination.size)
	var pixels: Array=frame.opaque
	var visible:=Rect2(Vector2(pixels[0],pixels[1])*ratio-pivot,Vector2(pixels[2],pixels[3])*ratio)
	var visible_bounds:=Rect2(ground(f.pos)+Vector2(-visible.end.x if flip else visible.position.x,visible.position.y),visible.size)
	return {"source":source,"rect":destination,"bounds":bounds,"visible_bounds":visible_bounds,"flip":flip,"height":body_height*perspective,"key":key}

func _draw() -> void:
	if sim == null: return
	var profile_start:=Time.get_ticks_usec() if profile_enabled else 0
	hits.clear()
	draw_rect(Rect2(0,0,1920,1080),INK)
	draw_texture_rect(BG, BACKDROP, false)
	# Continue the foreground underneath the floating cards, preserving the actors' ground plane.
	var skirt_y := FEET_AREA.position.y - 24
	var texture_y := (skirt_y-BACKDROP.position.y)/BACKDROP.size.y*BG.get_height()
	draw_texture_rect_region(BG,Rect2(BACKDROP.position.x,skirt_y,BACKDROP.size.x,1080-skirt_y),
		Rect2(0,texture_y,BG.get_width(),BG.get_height()-texture_y))
	draw_polygon(PackedVector2Array([Vector2(0,695),Vector2(1920,695),Vector2(1920,910),Vector2(0,910)]),
		PackedColorArray([Color("321b2400"),Color("321b2400"),Color("391e269a"),Color("391e269a")]))
	draw_polygon(PackedVector2Array([Vector2(0,910),Vector2(1920,910),Vector2(1920,1080),Vector2(0,1080)]),
		PackedColorArray([Color("391e269a"),Color("391e269a"),Color("311924f0"),Color("311924f0")]))
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.3, 0.12, 0.08, 0.05))
	# Warm motes stay subtle and never hide action silhouettes.
	for i in 22:
		var p := Vector2(fmod(i * 157.0 + sim.elapsed * (13 + i % 5), 1920), 230 + fmod(i * 89.0 + sin(sim.elapsed + i) * 15, 520))
		draw_circle(p, 1.4, Color(1, 0.87, 0.58, 0.45))
	_draw_nezha_windups()
	_draw_wenzhong_windups()
	var ordered: Array[Vector2]=[]
	for f in sim.fighters:
		if f.hp>0 or f.death_age<=1.4: ordered.append(Vector2(f.pos.y,f.id))
	ordered.sort()
	for entry in ordered: _fighter(sim.fighters[int(entry.y)])
	for effect in effects: _effect(effect)
	if sim.elapsed < Rules.INTRO: _divider()
	_draw_header()
	if sim.elapsed >= Rules.INTRO and sim.elapsed < Rules.INTRO + 1.2:
		text("冲 阵", Vector2(960, 245), 55, INK, true)
	if paused:
		notice("战斗暂停",Rect2(770,371,380,66),32)
	if not sim.result.is_empty() and result_age>=1.35: _draw_result()
	if profile_enabled: profile_draw_ms=(Time.get_ticks_usec()-profile_start)/1000.0

func animation(f: Rules.Fighter) -> Vector2i:
	if f.hp <= 0: return Vector2i(mini(3, int(f.death_age / 0.18)), 4)
	if f.action in ["attack", "cast", "finisher"]:
		var frame := mini(1, int(f.age / f.impact * 2)) if f.age < f.impact else 2 + mini(1, int((f.age - f.impact) / (f.duration - f.impact) * 2))
		return Vector2i(frame, 2 if f.action == "attack" else 5)
	if f.hit_age < 0.32: return Vector2i(mini(3, int(f.hit_age / 0.08)), 3)
	return Vector2i(int((f.stride if f.walking else sim.elapsed + f.id * 0.13) * (10 if f.walking else 4)) % 4, 1 if f.walking else 0)

func _fighter(f: Rules.Fighter) -> void:
	if f.hp <= 0 and f.death_age > 1.4: return
	var at := ground(f.pos)
	var alpha := 1.0 if f.hp > 0 else 1.0 - smoothstep(0.6, 1.4, f.death_age)
	draw_set_transform(at, 0, Vector2(FEET_AREA.size.x/1920.0,FEET_AREA.size.y/765.0))
	draw_circle(Vector2.ZERO, f.radius, Color(0.16, 0.09, 0.07, 0.30 * alpha))
	if debug_bodies:
		draw_arc(Vector2.ZERO, f.radius, 0, TAU, 32, TEAM[f.side], 2)
	draw_set_transform(Vector2.ZERO)
	var key:=sprite_key(f)
	var perspective:=lerpf(.88,1.03,clampf((f.pos.y+25.0)/765.0,0,1))
	var color := Color(1, 0.94, 0.86, alpha) if f.hit_age < 0.09 else Color(1, 1, 1, alpha)
	if key == "nezha":
		var pose := nezha_pose(f)
		var height := HERO_HEIGHT*perspective
		if f.hp>0 and f.action=="attack" and sim.kits[f.side].passive.id=="three_heads_six_arms":
			NezhaArt.draw(self,"three_heads_fx",f.age,at-Vector2(0,height*.47),height*1.22,f.facing,Color(1,1,1,.82))
		NezhaArt.draw(self,pose.clip,float(pose.time),at,height,f.facing,color)
		if f.hp > 0 and f.action == "attack":
			for event in NezhaArt.DATA.clips.attack.events:
				var age := (f.age-float(event.at_ms)/1000.0)*1.75
				if age < 0 or age >= NezhaArt.duration("spear_fx"): continue
				var offset := Vector2(event.socket[0]*f.facing,event.socket[1])*height
				NezhaArt.draw(self,"spear_fx",age,at+offset,height*.4,f.facing,Color.WHITE,float(event.rotation)*f.facing)
	elif key == "wenzhong":
		var pose := wenzhong_pose(f)
		var height := WENZHONG_HEIGHT*perspective
		WenzhongArt.draw(self,pose.clip,float(pose.time),at,height,f.facing,color)
		if f.hp > 0 and f.action == "attack":
			var time := f.age-WenzhongArt.event_time("attack","arc_start")
			if time >= 0 and time < WenzhongArt.duration("attack_fx"):
				WenzhongArt.draw(self,"attack_fx",time,at+Vector2(.47*f.facing,-.58)*height,height*.72,f.facing)
	else:
		var pose:=animation(f)
		var frame: SpriteFrame=draw_frames[key][pose.y*4+pose.x]
		var flip: bool=f.facing!=(-1 if key in ["shang","wenzhong"] else 1)
		draw_set_transform(at,0,Vector2(-perspective if flip else perspective,perspective))
		draw_texture_rect_region(TEXTURES[key],frame.rect,frame.source,color)
		draw_set_transform(Vector2.ZERO)
	var stacks := sim.burn_stacks(f)
	if f.hp > 0 and stacks > 0 and sim.result.is_empty():
		NezhaArt.draw(self,"burn_fx",sim.elapsed+f.id*.07,at+Vector2(0,3),48+stacks*6,1,Color(1,1,1,.9))
		for i in mini(3,stacks): draw_circle(at+Vector2((i-(stacks-1)*.5)*6,13),2,Color("ffbb58"))
	if f.hero and f.hp > 0:
		var name: String = sim.encounter.player.name if f.side == 0 else sim.encounter.enemy.name
		var label_at := at + Vector2(0,-(WENZHONG_HEIGHT if key=="wenzhong" else HERO_HEIGHT)*perspective-9)
		if key == "nezha":
			var pose := nezha_pose(f)
			var frame := NezhaArt.frame(pose.clip,pose.time)
			label_at.y=minf(label_at.y,at.y+(frame.visible.position.y-frame.pivot.y)*HERO_HEIGHT*perspective/frame.body_height-14)
		elif key == "wenzhong":
			var pose := wenzhong_pose(f)
			var frame := WenzhongArt.frame(pose.clip,pose.time)
			label_at.y=minf(label_at.y,at.y+(frame.visible.position.y-frame.pivot.y)*WENZHONG_HEIGHT*perspective/frame.body_height-14)
		draw_string_outline(FONT, label_at - Vector2(FONT.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x / 2,0), name, HORIZONTAL_ALIGNMENT_LEFT,-1,20,5,INK)
		text(name, label_at, 20, CREAM, true)
		if f.action in ["cast", "finisher"]:
			bar(Rect2(at.x - 64, label_at.y + 9, 128, 7), f.age / f.impact, GOLD)
	elif f.hp < f.max_hp and f.hp > 0:
		bar(Rect2(at + Vector2(-19, 8), Vector2(38, 3)), f.hp / f.max_hp, TEAM[f.side])

func _divider() -> void:
	var alpha := 1.0 - smoothstep(2.3, Rules.INTRO, sim.elapsed)
	# Two separately framed halves become a single continuous arena on charge.
	draw_rect(Rect2(951, 76, 18, 765), Color(0.12, 0.07, 0.09, alpha))
	for x in [950, 956, 964, 970]: draw_line(Vector2(x, 76), Vector2(x, 841), Color(0.9, 0.7, 0.4, alpha), 2)
	var points := PackedVector2Array([Vector2(960, 297), Vector2(1028, 365), Vector2(960, 433), Vector2(892, 365)])
	draw_colored_polygon(points, Color(0.18, 0.1, 0.12, alpha))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color(0.95, 0.77, 0.46, alpha), 3, true)
	text("战", Vector2(960, 387), 48, Color(1, 0.9, 0.7, alpha), true)
	text(army_name(0)+" · 列阵", Vector2(460, 238), 32, INK, true)
	text(army_name(1)+" · 列阵", Vector2(1460, 238), 32, INK, true)

func notice(value: String, rect: Rect2, font_size: int) -> void:
	battle_hud.paint(self,BattleHud.BANNER,rect)
	text(value,rect.get_center()+Vector2(0,font_size*.34),font_size,CREAM,true)

func _draw_header() -> void:
	draw_rect(Rect2(0, 0, 1920, 82), Color(0.14, 0.09, 0.10, 0.96))
	draw_line(Vector2(0, 81), Vector2(1920, 81), GOLD, 2)
	text("封 神  /  阵 前 演 武" if sim.encounter.get("exhibition", false) else "封 神  /  两 军 接 战", Vector2(34, 50), 25, GOLD)
	text(sim.encounter.title, Vector2(960, 49), 30, CREAM, true)
	var phase := "列阵  %d" % maxi(1, ceili(Rules.INTRO - sim.elapsed)) if sim.elapsed < Rules.INTRO else "交战  %04.1f 秒" % (sim.elapsed - Rules.INTRO)
	text(phase, Vector2(1886, 49) - Vector2(FONT.get_string_size(phase,HORIZONTAL_ALIGNMENT_LEFT,-1,22).x,0), 22, MUTED)

func skill_name(side: int) -> String:
	return str(sim.kits[side].battle.name)

func finisher_name(side: int) -> String:
	return str(sim.kits[side].ultimate.name)

func _effect(e: Dictionary) -> void:
	var at := ground(e.pos)
	var t: float = e.age / e.life
	var color: Color = TEAM[int(e.side)]
	color.a = 1.0 - t
	if e.kind == "ring":
		var source: Rules.Fighter=sim.fighters[int(e.source)]
		var height:=HERO_HEIGHT*lerpf(.88,1.03,clampf((source.pos.y+25.0)/765.0,0,1))
		var start := ground(e.from)+Vector2(float(e.facing)*.29,-.66)*height
		var catch_at := ground(e.from)+Vector2(float(e.facing)*.13,-.53)*height
		var end := ground(e.pos)-Vector2(0,70)
		var arc:=sin(t*PI)
		var position := (start.lerp(end,arc) if t<.5 else catch_at.lerp(end,arc))-Vector2(0,arc*18)
		NezhaArt.draw(self,"ring_fx",e.age,position,78,int(e.facing))
		return
	if e.kind in ["skill","finisher"] and e.get("ability","") in ["qiankun","samadhi"]:
		var burst:=NezhaArt.event_time("samadhi_fx","lotus_burst")
		if e.ability == "samadhi" and float(e.age)+burst < NezhaArt.duration("samadhi_fx"):
			NezhaArt.draw(self,"samadhi_fx",float(e.age)+burst,at+Vector2(0,4),520)
		if e.age < .6:
			notice(finisher_name(e.side) if e.kind=="finisher" else skill_name(e.side),Rect2(725,117,470,72),32)
		return
	if e.kind == "detonate":
		if e.age < .3: NezhaArt.draw(self,"spear_fx",float(e.age)+.14,at-Vector2(0,55),90)
		return
	if e.kind in ["skill","finisher"] and e.get("ability","") in ["thunder_whip","nine_thunders"]:
		var clip: String=str(e.ability)+"_fx"
		var time := float(e.age)+WenzhongArt.event_time(clip,"impact")
		if time < WenzhongArt.duration(clip):
			WenzhongArt.draw(self,clip,time,at+Vector2(0,4),460 if e.ability=="nine_thunders" else 285)
		if e.age < .6:
			notice(finisher_name(e.side) if e.kind=="finisher" else skill_name(e.side),Rect2(725,117,470,72),32)
		return
	if e.kind in ["hit", "skill_hit", "finisher_hit", "burn_hit", "splash_hit"]:
		if e.kind == "burn_hit": color = Color(1,.55,.2,1.0-t)
		if e.kind == "splash_hit": color = Color(1,.83,.35,1.0-t)
		if e.kind == "skill_hit" and sim.fighters[int(e.source)].hero_id == "nezha" and e.age < .21:
			NezhaArt.draw(self,"spear_fx",float(e.age)+.14,at-Vector2(0,55),65)
		at += Vector2(0, -95 - 60 * t)
		# Reuse the shaped line for the entire floating-number lifetime. TextLine
		# draws from its top-left; subtract ascent to preserve our baseline anchor.
		var label: TextLine=e.label
		var top_left:=at-Vector2(0,label.get_line_ascent())
		label.draw_outline(get_canvas_item(),top_left,5,INK)
		label.draw(get_canvas_item(),top_left,color)
		# Impact sparks are a short contact flash; only the damage number floats
		# for the full lifetime. Dense melee need not redraw hundreds of old rays.
		if e.age<.16 and e.kind != "burn_hit":
			for i in 4:
				var v := Vector2.from_angle(i * TAU / 4 + 0.3)
				draw_line(at + v * 6, at + v * (12 + t * 35), color, 2, true)
	elif e.kind in ["skill", "finisher"]:
		var strong: bool = e.kind == "finisher"
		var extent := (410.0 if strong else 230.0) * sin(minf(1, t * 2) * PI * 0.5)
		draw_set_transform(at - Vector2(0, 60), 0, Vector2(1, 0.66))
		for i in 4:
			var r := extent * (0.65 + i * 0.12)
			draw_arc(Vector2.ZERO, r, -PI * 0.83 + t, PI * 0.7 + t, 70, color, (9.0 if strong else 4.0) - i, true)
		draw_set_transform(Vector2.ZERO)
		if int(e.side) == 1:
			for i in 5:
				var p := at + Vector2((i - 2) * extent * 0.35, -260)
				draw_polyline(PackedVector2Array([p, p + Vector2(-20, 90), p + Vector2(26, 70), p + Vector2(0, 230)]), color, 4, true)
		if t < 0.65:
			notice(finisher_name(e.side) if strong else skill_name(e.side),Rect2(725,117,470,72),32)

func _draw_nezha_windups() -> void:
	for side in 2:
		var hero := sim.hero_for(side)
		if hero.hero_id != "nezha" or hero.hp <= 0 or hero.action != "finisher" or hero.age >= hero.impact: continue
		var at := ground(hero.cast_target)
		var radius := float(sim.kits[side].ultimate.radius)
		draw_set_transform(at,0,Vector2(FEET_AREA.size.x/1920.0,FEET_AREA.size.y/765.0))
		draw_circle(Vector2.ZERO,radius,Color(1,.42,.1,.07))
		draw_arc(Vector2.ZERO,radius,0,TAU,64,Color(1,.68,.3,.45),2)
		draw_set_transform(Vector2.ZERO)
		var time := hero.age-(hero.impact-NezhaArt.event_time("samadhi_fx","lotus_burst"))
		if time >= 0: NezhaArt.draw(self,"samadhi_fx",time,at+Vector2(0,4),520)

func _draw_wenzhong_windups() -> void:
	for side in 2:
		var hero := sim.hero_for(side)
		if hero.hero_id != "wenzhong" or hero.hp <= 0 or hero.action not in ["cast","finisher"] or hero.age >= hero.impact: continue
		var clip := "nine_thunders_fx" if hero.action=="finisher" else "thunder_whip_fx"
		var time := hero.age-(hero.impact-WenzhongArt.event_time(clip,"impact"))
		if time < 0: continue
		# Wen Zhong's existing skill resolves at the live target position.
		var at := ground(sim.fighters[hero.target].pos)
		WenzhongArt.draw(self,clip,time,at+Vector2(0,4),460 if hero.action=="finisher" else 285)

func _draw_result() -> void:
	draw_rect(Rect2(0, 82, 1920, 754), Color(0.10, 0.06, 0.09, 0.5))
	panel(Rect2(630, 283, 660, 385), Color(0.16, 0.09, 0.11, 0.98))
	var result: Dictionary = sim.result
	text(army_name(0)+"告捷" if result.player_won else "整 军 再 战", Vector2(960, 354), 43, GOLD, true)
	text(result.reason, Vector2(960, 399), 22, MUTED, true)
	text("我军存活 %d 人   ·   损失 %d 人" % [result.player_remaining, sim.initial[0] - int(result.player_remaining)], Vector2(960, 447), 24, CREAM, true)
	text("敌军存活 %d 人 · 本战击杀 %d" % [result.enemy_remaining,sim.kills[0]],Vector2(960,489),22,MUTED,true)
	var outcome := "演武不影响兵力与士气" if sim.encounter.get("exhibition", false) else ("胜利后据点归西岐，兵损与士气将带回舆图" if result.player_won else "保留原位置，敌方残余守军保留")
	if sim.encounter.get("kind","")=="field": outcome="双方战损带回地图 · 结束回合可恢复测试兵力" if sim.encounter.get("test_scenario",false) else "双方战损带回地图 · 保留部队位置"
	text(outcome, Vector2(960, 538), 18, MUTED, true)
	button("return", Rect2(755, 581, 410, 58), "返回大地图  ↵")
