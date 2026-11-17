extends RefCounted
## Runtime crops of existing character art, clipped to the circular badge.
const NezhaArt=preload("res://scripts/nezha_art.gd")
const WenzhongArt=preload("res://scripts/wenzhong_art.gd")
const COMMANDER=preload("res://assets/units/red_army.png")
const GENERAL=preload("res://assets/battle/motion/general_upright_v3.png")

static func portrait(id: String) -> Dictionary:
	match id:
		"nezha":
			var crop: Array=NezhaArt.DATA.portrait_regions.map
			return {"texture":NezhaArt.PORTRAIT,"source":Rect2(crop[0],crop[1],crop[2],crop[3])}
		"nangongshi": return {"texture":COMMANDER,"source":Rect2(321,424,112,112)}
		"wenzhong":
			var crop: Array=WenzhongArt.DATA.portrait_regions.map
			return {"texture":WenzhongArt.PORTRAIT,"source":Rect2(crop[0],crop[1],crop[2],crop[3])}
		_: return {"texture":GENERAL,"source":Rect2(101,37,58,58)}

static func draw_circle_portrait(canvas: CanvasItem,id: String,at: Vector2,radius: float) -> void:
	var entry:=portrait(id)
	var source: Rect2=entry.source
	var texture: Texture2D=entry.texture
	var points:=PackedVector2Array()
	var uvs:=PackedVector2Array()
	for i in 64:
		var direction:=Vector2.from_angle(i*TAU/64)
		points.append(at+direction*radius)
		uvs.append((source.position+(direction+Vector2.ONE)*.5*source.size)/texture.get_size())
	canvas.draw_circle(at,radius,Color("22343c"))
	canvas.draw_colored_polygon(points,Color.WHITE,uvs,texture)
