extends SceneTree
## Measures alpha only. Source art is untouched; runtime samples whole per-pose regions.
const SOURCES := {
	"zhou":{"path":"res://assets/battle/halberdiers/zhou.png","rows":8,"body_height":192.0,"ground_pivot":[200,232]},
	"shang":{"path":"res://assets/battle/halberdiers/shang.png","rows":8,"body_height":192.0,"ground_pivot":[312,232]},
	"nezha":{"path":"res://assets/battle/motion/nezha_upright_v3.png","rows":6,"body_height":195.0,"anchor_x":0.47},
	"wenzhong":{"path":"res://assets/battle/motion/wenzhong_upright_v3.png","rows":6,"body_height":217.0,"anchor_x":0.47},
	"general":{"path":"res://assets/battle/motion/general_upright_v3.png","rows":6,"body_height":192.0,"anchor_x":0.50}}

func _initialize() -> void:
	var catalog := {}
	var edge_warnings: Array = []
	var frame_count := 0
	for key in SOURCES:
		var definition: Dictionary = SOURCES[key].duplicate()
		var img := Image.load_from_file(definition.path)
		var w := img.get_width()
		var h := img.get_height()
		var row_height: float = float(h) / int(definition.rows)
		var ys: Array[int] = [0]
		for row in range(1,int(definition.rows)):
			ys.append(seam(img,roundi(row*row_height),roundi(row_height*.12),0,w,true))
		ys.append(h)
		var frames: Array = []
		for row in int(definition.rows):
			var xs: Array[int] = [0]
			for col in range(1,4): xs.append(seam(img,roundi(col*w/4.0),roundi(w/4.0*.16),ys[row],ys[row+1],false))
			xs.append(w)
			for col in 4:
				var x0 := xs[col]
				var y0 := ys[row]
				var x1 := xs[col+1]
				var y1 := ys[row+1]
				var lo := Vector2i(x1,y1)
				var hi := Vector2i(x0,y0)
				for y in range(y0,y1):
					for x in range(x0,x1):
						if img.get_pixel(x,y).a<0.15: continue
						lo=Vector2i(mini(lo.x,x),mini(lo.y,y))
						hi=Vector2i(maxi(hi.x,x),maxi(hi.y,y))
				if lo.x<=x0 or hi.x>=x1-1 or lo.y<=y0 or hi.y>=y1-1:
					edge_warnings.append("%s:%d:%d"%[key,row,col])
				# Measured idle pelvis axis, independent of weapon/cape extent. Uniform scale per actor.
				var pivot := Vector2((col+float(definition.get("anchor_x",0.5)))*w/4.0-x0,hi.y+1-y0)
				# Generated idle columns can drift horizontally. Register each pair of boots,
				# rather than their weapon-inclusive bounding box, to the same ground point.
				if definition.has("ground_pivot"):
					# The infantry sheets are registered to the ground during packing.
					# Keep the planted boot fixed through the thrust and preserve airborne strides.
					var ground: Array = definition.ground_pivot
					pivot = Vector2(col * w / 4.0 + ground[0] - x0, row * row_height + ground[1] - y0)
				elif row==0:
					var mass:=0.0
					var moment:=0.0
					for y in range(hi.y-roundi(float(definition.body_height)*.04),hi.y+1):
						for x in range(lo.x,hi.x+1):
							var alpha:=img.get_pixel(x,y).a
							if alpha<.5: continue
							mass+=alpha
							moment+=(x-x0)*alpha
					if mass>0: pivot.x=moment/mass
				frames.append({"source":[x0,y0,x1-x0,y1-y0],"pivot":[pivot.x,pivot.y],"opaque":[lo.x-x0,lo.y-y0,hi.x-lo.x+1,hi.y-lo.y+1]})
		definition.frames=frames
		frame_count += frames.size()
		catalog[key]=definition
	FileAccess.open("res://data/battle_frames.json",FileAccess.WRITE).store_string(JSON.stringify(catalog,"\t"))
	print("BATTLE_FRAME_MEASURE ",JSON.stringify({"sprites":catalog.size(),"frames":frame_count,"edge_warnings":edge_warnings}))
	quit()

func seam(img: Image, around: int, radius: int, start: int, end: int, horizontal: bool) -> int:
	var best := around
	var score := INF
	for at in range(around-radius,around+radius+1):
		var count := 0.0
		for along in range(start,end):
			var alpha := img.get_pixel(along,at).a if horizontal else img.get_pixel(at,along).a
			if alpha>0.15: count+=1
		var value := count*1000+absf(at-around)
		if value<score:
			score=value
			best=at
	return best
