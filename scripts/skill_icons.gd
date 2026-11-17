extends RefCounted
## Opaque square anime paintings, sampled without stretching or letterboxing.
const Textures=preload("res://scripts/runtime_textures.gd")
static var SQUARE_ATLAS: Texture2D=Textures.get_texture("res://assets/ui/skills/hero_icons.png")
const SQUARE_IDS=["qiankun","samadhi","fire_field","three_heads_six_arms","thunder_whip","nine_thunders","thunder_seal","thunder_master"]
const NezhaArt=preload("res://scripts/nezha_art.gd")
const FLAG=preload("res://assets/ui/painted_icons/flag.png")
const JADE=preload("res://assets/ui/painted_icons/jade.png")
const RESERVE=preload("res://assets/ui/painted_icons/reserve.png")
const MAP=preload("res://assets/ui/painted_icons/map.png")
const FX={
	"qiankun":["ring_fx",0],
	"samadhi":["samadhi_fx",3],
	"fire_field":["fire_field_fx",3],
	"three_heads_six_arms":["three_heads_fx",4],
	"heart_nail":["spear_fx",1],
	"dragon_fire":["burn_fx",2]
}
static var effect_icons: Dictionary={}

static func square(canvas: CanvasItem,index: int,rect: Rect2) -> void:
	var tile:=SQUARE_ATLAS.get_size()/3.0
	# Inset the sampled cell slightly to avoid bleeding adjacent artwork.
	var source:=Rect2(Vector2(index%3,index/3)*tile,tile).grow(-6)
	canvas.draw_texture_rect_region(SQUARE_ATLAS,rect,source)

static func empty_artifact(canvas: CanvasItem,rect: Rect2) -> void:
	square(canvas,8,rect)

static func draw(hud: Control,ability: Dictionary,rect: Rect2) -> void:
	var id: String=ability.id
	if id in SQUARE_IDS:
		square(hud,SQUARE_IDS.find(id),rect)
		return
	if FX.has(id):
		if not effect_icons.has(id):
			# A static HUD icon does not need to load every character animation sheet.
			var recipe: Array=FX[id]
			var clip: Dictionary=NezhaArt.DATA.clips[recipe[0]]
			var sheet: Dictionary=NezhaArt.DATA.sheets[clip.sheet]
			var frame: Dictionary=sheet.frames[int(clip.frames[int(recipe[1])])]
			effect_icons[id]={"texture":Textures.get_texture("res://"+str(sheet.path)),"source":Rect2(frame.source[0]+frame.visible[0],frame.source[1]+frame.visible[1],frame.visible[2],frame.visible[3])}
		var entry: Dictionary=effect_icons[id]
		var source: Rect2=entry.source
		var size: Vector2=source.size*minf(rect.size.x/source.size.x,rect.size.y/source.size.y)
		hud.draw_texture_rect_region(entry.texture,Rect2(rect.get_center()-size*.5,size),source)
		return
	var texture: Texture2D
	match id:
		"army_rally": texture=FLAG
		"jade_heal": texture=JADE
		"iron_charge","royal_charge": texture=RESERVE
		"royal_march": texture=MAP
	if texture!=null:
		var size:=texture.get_size()*minf(rect.size.x/texture.get_width(),rect.size.y/texture.get_height())
		hud.draw_texture_rect(texture,Rect2(rect.get_center()-size*.5,size),false)
	else:
		hud.icon("sun" if id in ["thunder_whip","nine_thunders","thunder_seal"] else "sword",rect.get_center(),hud.GOLD,rect.size.y/34.0)
