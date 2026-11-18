extends RefCounted
## All four painted cels share a ground contact point. The existing 16-frame actor
## and elemental clips supply the motion between these larger silhouette changes.
const Textures = preload("res://scripts/runtime_textures.gd")
static var lotus: Texture2D = Textures.get_texture("res://assets/battle/hero_fx/lotus.png")
static var thunder: Texture2D = Textures.get_texture("res://assets/battle/hero_fx/thunder.png")
const HEEL := Vector2(.5,222.0/256.0)

static func stamp(canvas: CanvasItem, texture: Texture2D, phase: float, at: Vector2, size: Vector2, opacity: float, facing: int = 1, front: bool = false) -> void:
	if opacity <= .005 or texture == null: return
	var cell := Vector2(texture.get_width()*.25,texture.get_height())
	var p := clampf(phase,0,3)
	var first := floori(p)
	var blend := smoothstep(.12,.88,p-first)
	canvas.draw_set_transform(at,0,Vector2(facing,1))
	for i in range(first,mini(3,first+1)+1):
		var alpha := opacity * (1.0-blend if i==first else blend)
		if alpha <= .005: continue
		if front:
			_draw_crown(canvas,texture,i,size,alpha)
		else:
			canvas.draw_texture_rect_region(texture,Rect2(-HEEL*size,size),Rect2(Vector2(i*cell.x,0),cell),Color(1,1,1,alpha))
	canvas.draw_set_transform(Vector2.ZERO)

# The upper petals and lightning are luminous through a rank of soldiers.
# Fade the front pass near their boots to keep the contact point in the ground plane.
static func _draw_crown(canvas: CanvasItem, sheet: Texture2D, column: int, size: Vector2, opacity: float) -> void:
	var breaks := PackedFloat32Array([0,.48,.72,.90])
	var weights := PackedFloat32Array([1,1,.81,0])
	for i in 3:
		var from := breaks[i]
		var to := breaks[i+1]
		var a := (Vector2(0,from)-HEEL)*size
		var b := (Vector2(1,to)-HEEL)*size
		var top := Color(1,1,1,weights[i]*opacity)
		var bottom := Color(1,1,1,weights[i+1]*opacity)
		var u := column*.25
		canvas.draw_polygon(PackedVector2Array([a,Vector2(b.x,a.y),b,Vector2(a.x,b.y)]),
			PackedColorArray([top,top,bottom,bottom]),
			PackedVector2Array([Vector2(u,from),Vector2(u+.25,from),Vector2(u+.25,to),Vector2(u,to)]),sheet)

# Tapered silk and ring wakes use an unbroken leading edge. Drawing small quads
# also supports very close targets, where the returning curve folds over itself.
static func silk(canvas: CanvasItem, start: Vector2, control_a: Vector2, control_b: Vector2, end: Vector2, begin: float, finish: float, width: float, color: Color, edge: Color) -> void:
	if finish-begin<.003 or start.distance_to(end)<4: return
	var top := PackedVector2Array()
	var low := PackedVector2Array()
	var shades := PackedColorArray()
	for i in 21:
		var t := i/20.0
		var along := lerpf(begin,finish,t)
		var pos := start.bezier_interpolate(control_a,control_b,end,along)
		var normal := start.bezier_derivative(control_a,control_b,end,along).normalized().orthogonal()
		var wave := (.035+.965*sin(PI*t))*(.67+.33*sin(t*PI*2.3+.40))
		top.append(pos+normal*width*wave)
		low.append(pos-normal*width*wave)
		shades.append(Color(edge,edge.a*(.08+.92*sin(PI*t))))
	for i in 20:
		if top[i].distance_squared_to(low[i])<.0001: continue
		canvas.draw_primitive(PackedVector2Array([top[i],low[i],low[i+1],top[i+1]]),PackedColorArray([color]),PackedVector2Array())
	canvas.draw_polyline_colors(top,shades,1.6,true)

static func ring_point(start: Vector2, end: Vector2, back: Vector2, t: float, facing: int) -> Vector2:
	var travel := sin(clampf(t,0,1)*PI)
	var at := (start if t<.5 else back).lerp(end,travel)
	# Different outward and returning arcs make the throw and catch legible in a crowd.
	at += Vector2(5.0*facing*sin(t*TAU),-36*sin(t*TAU)-17*travel)
	return at

static func ring_wake(canvas: CanvasItem, start: Vector2, end: Vector2, back: Vector2, t: float, facing: int) -> Vector2:
	var lines := [PackedVector2Array(),PackedVector2Array()]
	var edges := PackedColorArray()
	for i in 14:
		var k := i/13.0
		var phase := maxf(0,t-.22*(1.0-k))
		var p := ring_point(start,end,back,phase,facing)
		var d := ring_point(start,end,back,minf(1,phase+.003),facing)-p
		var wing := d.normalized().orthogonal()*Vector2(1,.65)*sin(k*PI)*6.5
		lines[0].append(p+wing)
		lines[1].append(p-wing)
		edges.append(Color(1,.76,.36,k*.88))
	canvas.draw_polyline(lines[0],Color(.63,.14,.03,.62),5,true)
	canvas.draw_polyline_colors(lines[0],edges,2.4,true)
	canvas.draw_polyline_colors(lines[1],edges,1.3,true)
	return ring_point(start,end,back,t,facing)

static func lotus_windup(canvas: CanvasItem, at: Vector2, progress: float, facing: int) -> void:
	# Only the seed is visible before the spear finishes the cast.
	var charge := smoothstep(.80,1.0,progress)
	stamp(canvas,lotus,0,at,Vector2(92,107),charge*.78,facing)

static func lotus_bloom(canvas: CanvasItem, impact: Vector2, behind_rank: Vector2, age: float, facing: int) -> void:
	if age>=.82: return
	# The base grows away from the point of contact, and the corolla opens behind the ranks.
	var opening := smoothstep(0,.17,age)
	var retreat := smoothstep(.24,.68,age)
	var size := Vector2(92,107).lerp(Vector2(463,439),opening).lerp(Vector2(482,454),retreat)
	var root := impact.lerp(behind_rank,opening)-Vector2(0,7*retreat)
	stamp(canvas,lotus,2.0*opening+retreat,root,size,1.0-smoothstep(.35,.82,age),facing)

# Three isolated brushstrokes from the last painted cel pass in front of the targets.
# They peel off on the far side of the strike and descend as the spear retracts.
static func falling_lotus_petals(canvas: CanvasItem, target: Vector2, age: float, facing: int) -> void:
	if age<.18 or age>.73 or lotus==null: return
	const FRAGMENTS := [Rect2(933,117,46,80),Rect2(986,182,21,20),Rect2(852,130,18,16)]
	const SIZES := [Vector2(15,31),Vector2(23,20),Vector2(16,13)]
	for i in FRAGMENTS.size():
		var t := (age-.18-i*.055)/.43
		if t<=0.0 or t>=1.0: continue
		var drift := sin(t*PI)*8.0 + t*(21.0+i*6.0)
		var x := (34.0+i*29.0+drift)*facing
		var y := -86.0-i*13.0-11.0*sin(PI*t)+t*t*(73.0+i*7.0)
		var alpha := smoothstep(0,.14,t)*(1.0-smoothstep(.58,1.0,t))
		var size: Vector2 = SIZES[i]*Vector2(.7+.3*absf(cos(2.2*t+i)),1.0)
		canvas.draw_set_transform(target+Vector2(x,y),facing*(.35*sin(t*4.0+i)-.45*t),Vector2(facing,1))
		canvas.draw_texture_rect_region(lotus,Rect2(-size*.5,size),FRAGMENTS[i],Color(1,1,1,.90*alpha))
	canvas.draw_set_transform(Vector2.ZERO)

static func thunder_seal(canvas: CanvasItem, at: Vector2, strong: bool, charge: float, opacity: float, front: bool = false) -> void:
	if opacity < .01: return
	var radius := (88.0 if strong else 55.0)*lerpf(1.13,1.0,charge)
	canvas.draw_set_transform(at,0,Vector2(1,.35))
	# Leave the middle open so the struck model's feet and shadow stay visible.
	for i in 3:
		var start := TAU*i/3.0+.12
		var end := start+lerpf(.26,1.86,charge)
		# Only the near edge is visible in front of the formation's boots.
		if front:
			end=minf(end,PI-.10)
			if end<=start: continue
		canvas.draw_arc(Vector2.ZERO,radius,start,end,26,Color(.20,.14,.46,opacity*.92),6.3,true)
		canvas.draw_arc(Vector2.ZERO,radius,start,end,26,Color(.65,.72,1,opacity),2.9,true)
		# An angular thunder meander is legible as a seal even when the centre is occupied.
		var point := Vector2.from_angle(start)*radius
		var tangent := Vector2.from_angle(start).orthogonal()
		var inward := -point.normalized()
		var mark := PackedVector2Array([point+tangent*6,point+tangent*4+inward*10,
			point+tangent*14+inward*10,point+tangent*10+inward*20])
		canvas.draw_polyline(mark,Color(.96,.84,.53,opacity*.95),3.3,true)
	canvas.draw_set_transform(Vector2.ZERO)

static func thunder_windup(canvas: CanvasItem, at: Vector2, progress: float, strong: bool, front: bool) -> void:
	var charge := smoothstep(.53,.92,progress)
	thunder_seal(canvas,at,strong,charge,charge*(.90 if front else .68),front)

static func thunder_bloom(canvas: CanvasItem, at: Vector2, age: float, strong: bool, facing: int, front: bool = false) -> void:
	var duration := .88 if strong else .50
	if age>=duration: return
	var extent := clampf(age/duration,0,1)
	var opening := ease(clampf(extent/.18,0,1),.42)
	var phase := .60+opening*1.40+smoothstep(.28,.77,extent)
	var size := Vector2(298,358) if strong else Vector2(116,140)
	# Let the returning stroke light the foreground briefly. Its painted afterglow stays behind the fighters.
	var opacity := (.56 if front else .76)*(1.0-smoothstep(.21,.91,extent))
	if front: opacity *= 1.0 - smoothstep(.035,.145,age)
	stamp(canvas,thunder,phase,at,size*(.76+.24*opening),opacity,facing,front)
