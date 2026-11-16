extends SceneTree

# Crop transparent atlas padding mechanically; keep original sprite pixels and
# alpha. A few nearly invisible generated pixels must not enlarge the bounds.
func visible_bounds(img: Image) -> Rect2i:
	var low:=img.get_size()
	var high:=Vector2i.ZERO
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x,y).a<.10: continue
			low=low.min(Vector2i(x,y))
			high=high.max(Vector2i(x+1,y+1))
	return Rect2i(low,high-low).grow(3).intersection(Rect2i(Vector2i.ZERO,img.get_size()))

func _initialize() -> void:
	var items: Array=["farm","lumber","mine","market","jade","granary","homes","forge","barracks","drill","alchemy","altar"]
	for atlas in [["atlas",4,3,items],["landmarks_atlas",3,2,["landmark_0","landmark_1","landmark_2","landmark_3","landmark_4"]]]:
		var path: String="res://assets/buildings/grounded/"
		var img:=Image.load_from_file(path+atlas[0]+".png")
		for i in atlas[3].size():
			var col: int=i%int(atlas[1])
			var row: int=i/int(atlas[1])
			var x: int=col*img.get_width()/int(atlas[1])
			var y: int=row*img.get_height()/int(atlas[2])
			var x2: int=(col+1)*img.get_width()/int(atlas[1])
			var y2: int=(row+1)*img.get_height()/int(atlas[2])
			var cell:=img.get_region(Rect2i(x,y,x2-x,y2-y))
			var crop:=visible_bounds(cell)
			var sprite:=cell.get_region(crop)
			sprite.save_png(path+str(atlas[3][i])+".png")
			print(atlas[3][i]," ",sprite.get_size())
	quit()
