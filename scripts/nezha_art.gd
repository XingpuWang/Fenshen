extends RefCounted
## Shared atlas sampler for live battle, map casting and HUD portraits.
const Textures = preload("res://scripts/runtime_textures.gd")
static var PORTRAIT: Texture2D = Textures.get_texture("res://assets/characters/nezha/v3/portrait.png")
static var DATA: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/nezha_art_v4.json"))
static var sheets: Dictionary = {}

class Frame:
	var texture: Texture2D
	var source: Rect2
	var pivot: Vector2
	var visible: Rect2
	var body_height: float
	func rect(height: float) -> Rect2:
		var ratio := height / body_height
		return Rect2(-pivot * ratio, source.size * ratio)

static func prepare() -> void:
	if not sheets.is_empty(): return
	for key in DATA.sheets:
		var entry: Dictionary = DATA.sheets[key]
		var texture: Texture2D = Textures.get_texture("res://" + str(entry.path))
		var frames: Array[Frame] = []
		for raw in entry.frames:
			var f := Frame.new()
			f.texture = texture
			f.source = Rect2(raw.source[0],raw.source[1],raw.source[2],raw.source[3])
			f.pivot = Vector2(raw.pivot[0],raw.pivot[1])
			f.visible = Rect2(raw.visible[0],raw.visible[1],raw.visible[2],raw.visible[3])
			f.body_height = float(entry.body_height)
			frames.append(f)
		sheets[key] = frames

static func duration(clip: String) -> float:
	var ms := 0.0
	for value in DATA.clips[clip].durations_ms: ms += float(value)
	return ms / 1000.0

static func event_time(clip: String, event: String) -> float:
	for marker in DATA.clips[clip].events:
		if marker.event == event: return float(marker.at_ms) / 1000.0
	push_error("Unknown art event: " + clip + "/" + event)
	return 0.0

static func frame_index(clip: String, seconds: float) -> int:
	var entry: Dictionary = DATA.clips[clip]
	var time := maxf(0,seconds) * 1000.0
	if entry.loop: time = fmod(time,duration(clip)*1000.0)
	for i in entry.frames.size():
		if time + .000001 < float(entry.durations_ms[i]): return i
		time -= float(entry.durations_ms[i])
	return entry.frames.size()-1

static func frame(clip: String, seconds: float) -> Frame:
	return frame_number(clip,frame_index(clip,seconds))

static func frame_number(clip: String, index: int) -> Frame:
	prepare()
	var entry: Dictionary = DATA.clips[clip]
	return sheets[entry.sheet][int(entry.frames[clampi(index,0,entry.frames.size()-1)])]

static func draw(canvas: CanvasItem, clip: String, seconds: float, at: Vector2, height: float, facing: int = 1, color: Color = Color.WHITE, rotation: float = 0.0, aspect: Vector2 = Vector2.ONE) -> void:
	var f := frame(clip,seconds)
	canvas.draw_set_transform(at,rotation,Vector2(facing,1)*aspect)
	canvas.draw_texture_rect_region(f.texture,f.rect(height),f.source,color)
	canvas.draw_set_transform(Vector2.ZERO)

static func geometry(f: Frame, at: Vector2, height: float, facing: int) -> Dictionary:
	var rect := f.rect(height)
	var ratio := height/f.body_height
	var visible := Rect2((f.visible.position-f.pivot)*ratio,f.visible.size*ratio)
	var bounds := Rect2(at+Vector2(-rect.end.x if facing<0 else rect.position.x,rect.position.y),rect.size)
	var visible_bounds := Rect2(at+Vector2(-visible.end.x if facing<0 else visible.position.x,visible.position.y),visible.size)
	return {"source":f.source,"rect":rect,"bounds":bounds,"visible_bounds":visible_bounds,"flip":facing<0,"height":height,"key":"nezha"}

static func draw_portrait(canvas: CanvasItem, destination: Rect2, slot: String = "battle") -> void:
	var raw: Array = DATA.portrait_regions.get(slot,DATA.portrait_regions.battle)
	var source := Rect2(raw[0],raw[1],raw[2],raw[3])
	var ratio := destination.size.x / destination.size.y
	if source.size.x/source.size.y > ratio:
		var width := source.size.y*ratio
		source.position.x += (source.size.x-width)*.5
		source.size.x = width
	else: source.size.y = source.size.x/ratio
	canvas.draw_rect(destination,Color("f5dfbc"))
	canvas.draw_texture_rect_region(PORTRAIT,destination,source)
