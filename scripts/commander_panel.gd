extends RefCounted
## Commander card: four skills, three fixed formations, four artifact slots.
const RECT:=Rect2(18,18,310,812)
const PORTRAIT_RECT:=Rect2(40,40,146,162)
const ROW_HEIGHT:=44
const FRAME=preload("res://assets/ui/painted/panel.png")
const NezhaArt=preload("res://scripts/nezha_art.gd")
const Portraits=preload("res://scripts/map_portraits.gd")
const GENERAL=preload("res://assets/battle/motion/general_upright_v3.png")
const COMMANDER=preload("res://assets/units/red_army.png")
const JIFA=preload("res://assets/ui/painted/jifa_portrait.png")
const SkillIcons=preload("res://scripts/skill_icons.gd")
const SKILL_SLOTS=["battle","ultimate","map","passive"]
const SKILL_KINDS={"battle":"战技","ultimate":"终结技","map":"军略","passive":"被动"}
const ARTIFACT_SLOTS:=4
static var frame_style: StyleBoxTexture

static func right_text(hud: Control,value: String,at: Vector2,size: int=20,color: Color=Color("ead6b3")) -> void:
	var width: float=hud.sans.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	hud.text(value,at-Vector2(width,0),size,color,hud.sans)

static func section(hud: Control,label: String,y: float) -> void:
	hud.icon("grid",Vector2(39,y-6),hud.GOLD,.42)
	hud.text(label,Vector2(52,y),18,hud.GOLD)
	hud.rule(36,y+9,274)

static func empty_slot(hud: Control,rect: Rect2) -> void:
	hud.draw_style_box(hud.game.make_style(Color(.075,.064,.060,.42),Color("786447"),1,2),rect)
	hud.draw_rect(rect.grow(-3),Color(.69,.56,.36,.12),false,1)

static func skill_rect(index: int) -> Rect2:
	return Rect2(228,244+index*70,64,64)

static func artifact_rect(index: int) -> Rect2:
	return Rect2(42+index*68,746,56,56)

static func skill_card(hud: Control,ability: Dictionary,index: int) -> void:
	var rect:=skill_rect(index)
	var id: String="commander_skill:"+SKILL_SLOTS[index]
	var active: bool=hud.hovered==id
	SkillIcons.draw(hud,ability,rect)
	hud.draw_rect(rect,hud.LIGHT if active else hud.GOLD,false,2 if active else 1)
	# The map-skill icon replaces the removed map command button.
	hud.hits.append({"id":id,"rect":rect,"enabled":SKILL_SLOTS[index]=="map"})

static func formations(world: ShanheWorld,unit: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for i in 3:
		var slot: Dictionary=unit.troops[i] if i<unit.troops.size() else {}
		var row: Dictionary={"label":"编队%d" % (i+1),"name":"","count":""}
		if not slot.is_empty() and int(slot.get("count",0))>0:
			row.name=str(world.BattleRules.TYPES.get(slot.type,{}).get("name",slot.type))
			row.count=str(int(slot.count))
		result.append(row)
	return result

static func skill_info(world: ShanheWorld,unit: Dictionary,slot: String) -> Dictionary:
	var ability: Dictionary=world.Catalog.skill(unit,slot)
	var description: String=ability.get("description","")
	var details: Array[String]=[]
	if slot=="passive":
		details.append("被动生效 · 无需施放 · 不消耗士气")
		if ability.id=="three_heads_six_arms":
			details.append("每段普攻命中触发 · 不重复伤害主目标 · 溅射不连锁")
	elif slot=="map":
		details.append("射程 %d 格 · %s" % [int(ability.range),"影响半径 %d 格" % int(ability.radius) if int(ability.radius)>0 else "单格目标"])
		details.append("点击图标或按 Q 选点 · 施放后结束本轮行动")
	else:
		var damage_type: String="法术" if ability.damage_type=="magic" else "物理"
		if description.is_empty(): description="对目标周围的敌军造成%s伤害。" % damage_type
		details.append("%s伤害 · 系数 %.2f · 读条 %.2f 秒" % [damage_type,float(ability.multiplier),float(ability.windup)])
		if slot=="battle": details.append("战斗中自动释放 · 冷却 %.1f 秒" % float(ability.cooldown))
		else: details.append("战斗中手动释放 · 消耗 %d 士气 · 可立即打断其他动作" % int(world.Catalog.DATA.morale.cost))
	return {"hero":world.Catalog.hero_id(unit),"slot":slot,"id":ability.id,"name":ability.name,"kind":SKILL_KINDS[slot],"description":description,"details":"\n".join(details)}

static func paragraph(hud: Control,value: String,size: int,width: float) -> TextParagraph:
	var text:=TextParagraph.new()
	text.width=width
	text.break_flags=TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND|TextServer.BREAK_ADAPTIVE
	text.add_string(value,hud.serif,size)
	return text

static func draw_tooltip(hud: Control,world: ShanheWorld,unit: Dictionary) -> Dictionary:
	if hud.hovered.begins_with("commander_artifact:"):
		var index:=int(hud.hovered.trim_prefix("commander_artifact:"))
		var rect:=Rect2(342,730,240,82)
		hud.draw_style_box(hud.game.make_style(Color("28201b"),hud.GOLD,1,5),rect)
		hud.text("法宝 %d" % (index+1),rect.position+Vector2(18,30),21,hud.GOLD)
		hud.text("未装备",rect.position+Vector2(18,60),17,hud.MUTED)
		return {"id":"artifact_empty","rect":rect,"name":"未装备"}
	if not hud.hovered.begins_with("commander_skill:") or hud.game.is_map_casting(): return {}
	var slot: String=hud.hovered.trim_prefix("commander_skill:")
	if not slot in SKILL_SLOTS: return {}
	var info:=skill_info(world,unit,slot)
	var body:=paragraph(hud,info.description,18,344)
	var details:=paragraph(hud,info.details,15,344)
	var height:=76.0+body.get_size().y+details.get_size().y
	var rect:=Rect2(342,skill_rect(SKILL_SLOTS.find(slot)).position.y,380,height)
	hud.draw_style_box(hud.game.make_style(Color(0,0,0,.28),Color.TRANSPARENT,0,6),Rect2(rect.position+Vector2(4,5),rect.size))
	hud.draw_style_box(hud.game.make_style(Color("28201b"),hud.GOLD,1,5),rect)
	hud.text(info.name,rect.position+Vector2(18,30),23,hud.LIGHT)
	hud.text(info.kind,rect.position+Vector2(302,29),15,hud.GOLD)
	hud.rule(rect.position.x+18,rect.position.y+43,344)
	body.draw(hud.get_canvas_item(),rect.position+Vector2(18,53),hud.LIGHT)
	details.draw(hud.get_canvas_item(),rect.position+Vector2(18,62+body.get_size().y),hud.MUTED)
	info.rect=rect
	return info

static func portrait(hud: Control,hero: String,rect: Rect2) -> void:
	if hero=="nezha":
		NezhaArt.draw_portrait(hud,rect,"map_panel")
		return
	var source: Rect2
	var texture: Texture2D
	match hero:
		"nangongshi":
			texture=COMMANDER
			source=Rect2(322,397,136,147)
		"huangtianhua":
			texture=GENERAL
			source=Rect2(85,24,96,104)
		"jifa":
			texture=JIFA
			source=Rect2(Vector2.ZERO,texture.get_size())
		"wenzhong":
			texture=Portraits.WENZHONG
			source=Rect2(Vector2.ZERO,texture.get_size())
		_:
			var entry:=Portraits.portrait(hero)
			texture=entry.texture
			source=entry.source
	var aspect:=rect.size.x/rect.size.y
	if source.size.x/source.size.y>aspect:
		var width:=source.size.y*aspect
		source.position.x+=(source.size.x-width)*.5
		source.size.x=width
	else:
		source.size.y=source.size.x/aspect
	hud.draw_texture_rect_region(texture,rect,source)

static func draw(hud: Control,world: ShanheWorld,unit: Dictionary) -> void:
	if frame_style==null:
		frame_style=StyleBoxTexture.new()
		frame_style.texture=FRAME
		frame_style.set_texture_margin_all(24)
	hud.draw_style_box(hud.game.make_style(Color(0,0,0,.28),Color.TRANSPARENT,0,6),Rect2(RECT.position+Vector2(4,6),RECT.size))
	hud.draw_style_box(frame_style,RECT)
	var hero:=world.Catalog.hero_id(unit)
	var stats:=world.Catalog.effective_stats(unit)
	var kit: Dictionary=world.Catalog.profile(unit).skills
	portrait(hud,hero,PORTRAIT_RECT)
	hud.draw_rect(PORTRAIT_RECT.grow(1),Color("9c8054"),false,1)
	hud.text(unit.name,Vector2(198,76),28,hud.LIGHT)
	var title: String=str(unit.title)
	var title_size:=14
	while hud.serif.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,title_size).x>108 and title_size>11:
		title_size-=1
	hud.text(title,Vector2(198,110),title_size,hud.GOLD)
	hud.text("等级 18",Vector2(198,144),16,hud.MUTED)
	var maximum:=int(world.Catalog.DATA.morale.maximum)
	var morale:=clampi(int(unit.get("morale",world.Catalog.DATA.morale.opening)),0,maximum)
	hud.text("士气",Vector2(198,180),14,hud.MUTED)
	right_text(hud,"%d/%d" % [morale,maximum],Vector2(306,180),14,hud.LIGHT)
	hud.draw_rect(Rect2(198,192,108,5),Color("514232"))
	hud.draw_rect(Rect2(198,192,108*float(morale)/maxi(1,maximum),5),hud.GOLD)
	hud.rule(36,222,274)
	# Keep the same six gameplay attributes, in the reference's vertical layout.
	var keys: Array=["physical_attack","physical_defense","magic_attack","magic_defense","max_hp","movement"]
	var icons: Array=["sword","guard","sun","grid","jade","move"]
	for i in keys.size():
		var y:=276+i*ROW_HEIGHT
		hud.icon(icons[i],Vector2(44,y-6),hud.GOLD,.53)
		hud.text(world.Catalog.DATA.stat_labels[keys[i]],Vector2(64,y),18,hud.GOLD)
		right_text(hud,str(int(stats[keys[i]])),Vector2(198,y),20)
		hud.draw_line(Vector2(61,y+12),Vector2(208,y+12),Color(.7,.56,.37,.10),1)
	hud.draw_line(Vector2(215,244),Vector2(215,518),Color(.7,.56,.37,.20),1)
	for i in SKILL_SLOTS.size(): skill_card(hud,kit[SKILL_SLOTS[i]],i)
	section(hud,"部队",550)
	hud.commander_formations=formations(world,unit)
	for i in 3:
		var row: Dictionary=hud.commander_formations[i]
		var y:=592+i*ROW_HEIGHT
		hud.text(row.label,Vector2(43,y),18,hud.GOLD)
		hud.text(row.name,Vector2(145,y),18,hud.LIGHT)
		right_text(hud,row.count,Vector2(306,y),20)
		hud.draw_line(Vector2(42,y+12),Vector2(306,y+12),Color(.7,.56,.37,.12),1)
	section(hud,"法宝",724)
	for i in ARTIFACT_SLOTS:
		var rect:=artifact_rect(i)
		SkillIcons.empty_artifact(hud,rect)
		hud.draw_rect(rect,hud.GOLD,false,1)
		hud.hits.append({"id":"commander_artifact:%d" % i,"rect":rect,"enabled":false})
