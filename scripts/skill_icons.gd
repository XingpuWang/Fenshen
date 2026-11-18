extends RefCounted
## The map and battle HUD sample the same painted ability artwork.
const Textures=preload("res://scripts/runtime_textures.gd")
static var SQUARE_ATLAS: Texture2D=Textures.get_texture("res://assets/ui/skills/hero_icons.png")
const SQUARE_IDS=["qiankun","samadhi","fire_field","three_heads_six_arms","thunder_whip","nine_thunders","thunder_seal","thunder_master"]
const NezhaArt=preload("res://scripts/nezha_art.gd")
const FLAG=preload("res://assets/ui/painted_icons/flag.png")
const JADE=preload("res://assets/ui/painted_icons/jade.png")
const RESERVE=preload("res://assets/ui/painted_icons/reserve.png")
const MAP=preload("res://assets/ui/painted_icons/map.png")
const EMBLEMS={
	"army_rally":FLAG, "jade_heal":JADE, "iron_charge":RESERVE,
	"royal_charge":RESERVE, "royal_march":MAP
}
const FX={"heart_nail":["spear_fx",1], "dragon_fire":["burn_fx",2]}
static var cached_art: Dictionary={}

static func square_source(index: int) -> Rect2:
	var tile:=SQUARE_ATLAS.get_size()/3.0
	return Rect2(Vector2(index%3,index/3)*tile,tile).grow(-6)

static func artwork(id: String) -> Dictionary:
	if cached_art.has(id): return cached_art[id]
	var art: Dictionary={}
	if id in SQUARE_IDS:
		art={"texture":SQUARE_ATLAS, "source":square_source(SQUARE_IDS.find(id))}
	elif FX.has(id):
		var recipe: Array=FX[id]
		var clip: Dictionary=NezhaArt.DATA.clips[recipe[0]]
		var sheet: Dictionary=NezhaArt.DATA.sheets[clip.sheet]
		var frame: Dictionary=sheet.frames[int(clip.frames[int(recipe[1])])]
		art={"texture":Textures.get_texture("res://"+str(sheet.path)),
			"source":Rect2(frame.source[0]+frame.visible[0],frame.source[1]+frame.visible[1],frame.visible[2],frame.visible[3])}
	elif EMBLEMS.has(id):
		var texture: Texture2D=EMBLEMS[id]
		art={"texture":texture, "source":Rect2(Vector2.ZERO,texture.get_size())}
	cached_art[id]=art
	return art

static func square(canvas: CanvasItem,index: int,rect: Rect2) -> void:
	canvas.draw_texture_rect_region(SQUARE_ATLAS,rect,square_source(index))

static func empty_artifact(canvas: CanvasItem,rect: Rect2) -> void:
	square(canvas,8,rect)

static func draw(hud: Control,ability: Dictionary,rect: Rect2) -> void:
	var id: String=ability.id
	var art:=artwork(id)
	if art.is_empty():
		hud.icon("sword",rect.get_center(),hud.GOLD,rect.size.y/34.0)
		return
	var source: Rect2=art.source
	var size:=source.size*minf(rect.size.x/source.size.x,rect.size.y/source.size.y)
	hud.draw_texture_rect_region(art.texture,Rect2(rect.get_center()-size*.5,size),source)
