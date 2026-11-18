extends RefCounted
## Native-facing uniform sheets shared by the tactical map and the battle view.
const Textures=preload("res://scripts/runtime_textures.gd")
static var TEXTURES := {
	"zhou": Textures.get_texture("res://assets/battle/halberdiers/zhou.png"),
	"shang": Textures.get_texture("res://assets/battle/halberdiers/shang.png"),
	"zhou_archer": Textures.get_texture("res://assets/battle/archers/zhou.png"),
	"shang_archer": Textures.get_texture("res://assets/battle/archers/shang.png"),
	"zhou_cavalry": Textures.get_texture("res://assets/battle/cavalry/zhou.png"),
	"shang_cavalry": Textures.get_texture("res://assets/battle/cavalry/shang.png"),
	"general": preload("res://assets/battle/motion/general_upright_v3.png"),
}

static func troop_key(faction: String, kind: String) -> String:
	var army := "shang" if faction == "shang" else "zhou"
	return army if kind == "halberd" else army + "_" + kind

static func native_facing(key: String) -> int:
	return -1 if key.begins_with("shang") else 1
