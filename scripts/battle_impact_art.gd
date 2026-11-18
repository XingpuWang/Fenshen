extends RefCounted
## Small ground effects share the arena's upper-left light and the battle clock.
static var shadow: Texture2D
static var dust: Texture2D

static func draw_shadow(canvas: CanvasItem, at: Vector2, scale: Vector2, alpha: float) -> void:
	if shadow == null:
		var stamp := Image.create(128, 48, true, Image.FORMAT_RGBA8)
		for y in 48:
			for x in 128:
				var dx := x - 45.0
				var dy := y - 18.0
				# A short, dense contact at the feet meets a soft cast shadow to the right.
				var soles := exp(-((absf(dx)-8.0)**2/72.0 + dy*dy/9.0))
				var cast_shadow := exp(-((dx-16.0)**2/920.0 + (dy-.16*dx-1.5)**2/44.0))
				stamp.set_pixel(x,y,Color(.16,.12,.13,.40*soles + .26*cast_shadow))
		stamp.generate_mipmaps()
		shadow=ImageTexture.create_from_image(stamp)
	canvas.draw_texture_rect(shadow,Rect2(at-Vector2(45,18)*scale,Vector2(128,48)*scale),false,Color(1,1,1,alpha))

static func dust_puff(canvas: CanvasItem, at: Vector2, size: Vector2, opacity: float) -> void:
	if dust == null:
		var stamp := Image.create(64, 40, true, Image.FORMAT_RGBA8)
		for y in 40:
			for x in 64:
				var p := Vector2((x-31.5)/32.0,(y-19.5)/20.0)
				var wave := .075*sin(13*p.x+4*p.y) + .06*sin(9*p.y-8*p.x)
				var coverage := 1.0 - smoothstep(.28,.96,p.length()+wave)
				var tint := Color("aa795a").lerp(Color("f4dcaf"),clampf(.55-.72*p.y,0,1))
				tint.a=coverage
				stamp.set_pixel(x,y,tint)
		stamp.generate_mipmaps()
		dust=ImageTexture.create_from_image(stamp)
	canvas.draw_texture_rect(dust,Rect2(at-size*.5,size),false,Color(1,1,1,opacity))

static func draw_hoof_dust(canvas: CanvasItem, feet: Vector2, facing: int, age: float, size: float) -> void:
	var t := clampf(age/.39,0,1)
	for i in 4:
		var trail := float(i)/3.0
		var shift := Vector2(-facing*(19.0 + trail*25.0 + (15.0+trail*38.0)*t), -2.0-(5.0+10.0*trail)*sin(t*2.2))
		var puff := Vector2(23+18*trail,8+8*trail)*(1.0+t*.75)
		dust_puff(canvas,feet+shift*size,puff*size,(1.0-t)*(.66-.33*trail))
	if t<.72:
		for i in 3:
			var phase:=t/.72
			var offset:=Vector2(-facing*(21+i*6+(18+i*6)*phase),-3-(9+i*3)*sin(PI*phase))
			var grain:=Color("916a48") if i%2==0 else Color("f6ddb7")
			grain.a=.74*(1-phase)
			canvas.draw_line(feet+offset*size,feet+(offset+Vector2(-facing*2.2,1.3))*size,grain,1.4,true)

static func draw_spark(canvas: CanvasItem, contact: Vector2, age: float, facing: int, charge: bool) -> void:
	var t:=clampf(age/(.155 if charge else .105),0,1)
	var reach:=(17.0 if charge else 8.0)*(1.0+0.6*t)
	var core:=Color(1,.97,.79,1-t)
	var gold:=Color(1,.72,.36,1-t)
	for angle: float in [-2.68,-1.32,-.50,.65]:
		var ray:=Vector2.from_angle(angle)*Vector2(facing,1)
		var across:=ray.orthogonal()*(1.35 if charge else .85)*(1-t)
		var root:=contact+ray*reach*t*.7
		canvas.draw_colored_polygon(PackedVector2Array([root+across,contact+ray*reach,root-across]),gold)
	canvas.draw_circle(contact,2.6*(1-t)+.2,core)

## The rider's loose shoulder cloth continues forward for a beat after contact.
## Build only the recovery drawings. The horse's hooves and lance keep their authored positions.
static func recovery_mesh(rect: Rect2, source: Rect2, sheet: Vector2, facing: int, pose: int) -> ArrayMesh:
	var impulse: float=[.35,1.0,.65,-.3,-.12][pose-43]
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var columns := 32
	var rows := 18
	for y in rows+1:
		for x in columns+1:
			var uv:=Vector2(float(x)/columns,float(y)/rows)
			var point:=rect.position+rect.size*uv
			var height:=-point.y/137.0
			var weight:=smoothstep(.045,.34,-point.x*facing/137.0)*smoothstep(.48,.61,height)*(1-smoothstep(.84,.95,height))
			vertices.append(point+Vector2(6.2*facing,-3.6)*weight*impulse)
			uvs.append((source.position+source.size*uv)/sheet)
			if x<columns and y<rows:
				var i:=y*(columns+1)+x
				indices.append_array(PackedInt32Array([i,i+1,i+columns+1,i+1,i+columns+2,i+columns+1]))
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh
