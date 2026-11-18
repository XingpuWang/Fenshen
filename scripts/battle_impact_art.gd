extends RefCounted
## Local reactions, contact sparks and ground shadows share the battle clock.
static var shadow: Texture2D
static var dust: Texture2D
const RECOIL_TIME := .19

static func recoil_strength(event: Dictionary) -> float:
	if event.kind=="splash_hit": return 8.5
	if event.has("spear_beat"): return 18.0 if event.spear_beat==2 else 14.0
	match event.kind:
		"charge_hit","finisher_hit": return 14.0
		"skill_hit": return 9.0
		"arrow_hit": return 5.0
		_: return 6.0

## The sole stays at its simulation ground point. Only the upper silhouette leans away.
static func recoil_transform(feet: Vector2, depth: float, flip: bool, height: float, event: Dictionary) -> Transform2D:
	var age:=float(event.age)
	var impulse:=(.48+.52*smoothstep(0,.031,age))*(1.0-smoothstep(.038,.137,age))
	impulse-=.14*sin(PI*clampf((age-.101)/(RECOIL_TIME-.101),0,1))
	var push: Vector2=event.incoming*float(event.recoil)*impulse
	var compression: float=float(event.recoil)*.24*maxf(0,impulse)
	return Transform2D(Vector2(-depth if flip else depth,0),
		Vector2(-push.x/height,1.0-(push.y+compression)/height)*depth,feet)

static func draw_spear_contact(canvas: CanvasItem, at: Vector2, direction: Vector2, age: float, beat: int, splash: bool) -> void:
	var duration:=.14 if splash else (.18 if beat==2 else .15)
	if age>=duration: return
	var t:=age/duration
	var fade:=1.0-smoothstep(.16,1.0,t)
	var length:=(11.0 if splash else (30.0 if beat==2 else 23.0))
	var normal:=direction.orthogonal()
	var tip:=at+direction*length*(.38+.75*t)
	var tail:=at-direction*length*(.44-.25*t)
	var edge:=normal*(1.0 if splash else 2.8)*(1.0-.8*t)
	var gold:=Color(1,.69,.25,fade)
	var hot:=Color(1,.97,.79,fade)
	canvas.draw_colored_polygon(PackedVector2Array([tail,at-edge,tip,at+edge]),gold)
	canvas.draw_line(tail,tip,hot,1.25 if splash else 2.0,true)
	for i in (2 if splash else 3):
		var angle: float=[-.91,.54,-.30][i]
		var ray:=direction.rotated(angle)
		var start:=at+ray*length*(.10+.69*t)
		var end:=start+ray*length*(.64-.46*t)
		var wing:=ray.orthogonal()*(.9 if splash else 1.65)*(1.0-.71*t)
		canvas.draw_colored_polygon(PackedVector2Array([start-wing,end,start+wing]),gold if i==1 else hot)

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
