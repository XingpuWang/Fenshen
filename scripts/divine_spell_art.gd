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
	var rise := smoothstep(.03,.90,progress)
	stamp(canvas,lotus,smoothstep(.42,1,progress)*.95,at,Vector2(236,264).lerp(Vector2(329,275),rise),rise*.80,facing)

static func lotus_bloom(canvas: CanvasItem, at: Vector2, age: float, facing: int, front: bool = false) -> void:
	if age>=.90: return
	var opening := ease(clampf(age/.115,0,1),.42)
	var decay := smoothstep(.24,.73,age)
	var phase := .95+opening*1.05+decay
	var size := Vector2(329,275).lerp(Vector2(479,458),opening).lerp(Vector2(513,478),decay)
	stamp(canvas,lotus,phase,at-Vector2(0,12*decay),size,(.93 if front else 1.0)*(1.0-smoothstep(.35,.90,age)),facing,front)
	if not front: return
	# Red-gold leaves peel away from the corona as the last painted cel dissolves.
	var lift := smoothstep(.12,.86,age)
	var visibility := smoothstep(.08,.2,age)*(1.0-smoothstep(.4,.78,age))
	for i in 8:
		var a := -PI+(i+.5)*PI/8.0
		var shaft := Vector2(cos(a)*facing,sin(a))
		var distance := 40.0+lift*(117+(i%3)*22)
		var pos := at+shaft*distance-Vector2(0,25+lift*41)
		var tip := shaft.rotated(.3*sin(i*.8+lift*3))*(7.0+i%3)
		var rim := tip.orthogonal()*.28
		canvas.draw_colored_polygon(PackedVector2Array([pos-tip,pos+rim,pos+tip,pos-rim]),Color(1,.52+.05*(i%3),.14,visibility))

static func thunder_windup(canvas: CanvasItem, at: Vector2, progress: float, strong: bool, facing: int) -> void:
	var rise := smoothstep(.05,.92,progress)
	var size := Vector2(229,300) if strong else Vector2(111,130)
	stamp(canvas,thunder,.6*smoothstep(.58,1.0,progress),at,size*(.78+.22*rise),rise*(.84 if strong else .62),facing)

static func thunder_bloom(canvas: CanvasItem, at: Vector2, age: float, strong: bool, facing: int, front: bool = false) -> void:
	var duration := .88 if strong else .50
	if age>=duration: return
	var extent := clampf(age/duration,0,1)
	var opening := ease(clampf(extent/.18,0,1),.42)
	var phase := .60+opening*1.40+smoothstep(.28,.77,extent)
	var size := Vector2(330,431) if strong else Vector2(171,201)
	stamp(canvas,thunder,phase,at,size*(.76+.24*opening),(.88 if front else 1.0)*(1.0-smoothstep(.38,1.0,extent)),facing,front)
