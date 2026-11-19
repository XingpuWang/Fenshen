extends RefCounted
## The fire spear's lotus socket flowers into three edges, then closes on the thrust.
const CONTACT := 3.30
# The weapon painting places its bronze lotus at x=1632, with the hand at 670
# and the working tip at 2108.5. Project the fitting along the same two live sockets.
const LOTUS_SOCKET := (1632.0-670.0)/(2108.5-670.0)

static func paint(fx, t: float, grip: Vector2, tip: Vector2, contact: Vector2) -> void:
	if t <= 2.32 or t >= 3.38: return
	var point := tip if t < CONTACT else contact
	var shaft := grip.direction_to(point)
	if shaft == Vector2.ZERO: return
	var socket := grip.lerp(point, LOTUS_SOCKET)
	var blade_length := socket.distance_to(point)
	var close := smoothstep(3.03, CONTACT, t)

	# The short lower petal follows the longer upper one. Both issue from the metal
	# before the point of the real spear brightens. All three share the final tip.
	for petal in [-1, 1, 0]:
		var upper: bool = petal == 1
		var main: bool = petal == 0
		var start := 2.32 if main else (2.36 if upper else 2.54)
		var finish := 2.79 if main else (2.85 if upper else 3.00)
		var written := smoothstep(start,finish,t)
		if written < 0.015: continue
		var side := float(petal)
		var opening := written*(1.0-close)
		var forward := (13.0 if main else (39.0 if upper else 22.0)) * opening
		var spread := (58.0 if upper else 34.0) * side * opening
		var normal := shaft.orthogonal()
		var full_tip := point + shaft*forward + normal*spread
		var reach := blade_length+forward
		var growing := socket + shaft*reach*written + normal*spread*smoothstep(0.05,0.91,written)
		var nib := growing.lerp(full_tip,smoothstep(.82,1.0,written))
		var tangent := (shaft+normal*side*opening*(.72 if upper else .55)).normalized()
		var intensity := smoothstep(0.015,0.49,written) * (1.0-smoothstep(3.26,3.38,t))
		if not main: intensity *= (0.98 if upper else 0.81) * (1.0-0.72*close)
		var length := blade_length*(0.76 if upper else 0.65) + (25.0 if upper else 15.0)*opening
		length = minf(length*lerpf(.38,1.0,written),socket.distance_to(nib)*.63)
		var throat := nib - tangent*length*.85
		var vein_length := socket.distance_to(throat)
		var root_control := socket + shaft*vein_length*.39
		var tip_control := throat - tangent*vein_length*.37
		var first_surge := (t-start-.045)/.37
		var second_surge := (t-start-.48)/.30
		_strand(fx,socket,root_control,tip_control,throat,written,
			(7.8 if main else (13.0 if upper else 9.8))*lerpf(.46,1.0,written),
			intensity,first_surge,second_surge)
		var nib_power := intensity * smoothstep(0.28,0.81,written)
		if nib_power <= 0.012: continue
		# Only the incandescent head is carried on these curved veins. The painted
		# tassel and long hilt belong to the single physical spear in the character rig.
		var full_width := length/0.35
		fx._paint(fx.SPEAR,nib,Vector2(full_width,full_width*(.25 if upper else .22)),
			tangent.angle(),nib_power,fx.FRONT if main else fx.REAR,
			1.16,0.59,fx.FORWARD,fx.SPEAR_TIP)
		var glint := _surge_at(1.0,first_surge,second_surge)
		if glint > .04:
			fx._paint(fx.THRUST,nib,Vector2(length*1.36,length*.25),tangent.angle(),
				nib_power*glint*.85,fx.FRONT if main else fx.REAR,1.16,.16,fx.FORWARD,fx.LANCE_TIP)

static func _surge_at(s: float, first: float, second: float) -> float:
	var a := smoothstep(-.23,0.0,s-first)*(1.0-smoothstep(0.0,.15,s-first))
	var b := smoothstep(-.21,0.0,s-second)*(1.0-smoothstep(0.0,.16,s-second))
	return maxf(a,b)

static func _strand(fx, root: Vector2, a: Vector2, b: Vector2, end: Vector2,
		written: float, breadth: float, power: float, first_surge: float, second_surge: float) -> void:
	var rect: Rect2 = fx.REGIONS[fx.THRUST]
	var atlas_size: Vector2 = fx._textures[0].get_size()
	var previous := PackedVector2Array()
	var previous_uv := PackedVector2Array()
	var previous_ink := PackedColorArray()
	var previous_ridge := PackedVector2Array()
	var previous_glow_uv := PackedVector2Array()
	var previous_glow := PackedColorArray()
	var segments := maxi(3, ceili(12.0*written))
	for i in segments+1:
		var s := float(i)/segments
		var at := root.bezier_interpolate(a,b,end,s)
		var normal := root.bezier_derivative(a,b,end,s).normalized().orthogonal()
		# A narrow heel at the ferrule opens into a brush-painted flame towards the blade.
		var width := breadth*(0.30+0.70*sin(PI*s*.79))*lerpf(0.61,1.0,smoothstep(0.0,0.26,s))
		var row := PackedVector2Array([at-normal*width*0.53,at+normal*width*0.47])
		var u := lerpf(0.22,0.82,s)
		var uv := PackedVector2Array([(rect.position+rect.size*Vector2(u,.14))/atlas_size,
			(rect.position+rect.size*Vector2(u,.87))/atlas_size])
		var alpha := power*lerpf(.69,1.0,smoothstep(.04,.48,s))
		var ink := PackedColorArray([Color(alpha,0,0),Color(alpha,0,0)])
		# Two finite strokes run from the metal along the bright lip: one during
		# opening, the other in the last breath before the three points reunite.
		var surge := _surge_at(s,first_surge,second_surge)
		var ridge := PackedVector2Array([at-normal*width*.32,at-normal*width*.045])
		var glow_uv := PackedVector2Array([(rect.position+rect.size*Vector2(lerpf(.59,.87,s),.415))/atlas_size,
			(rect.position+rect.size*Vector2(lerpf(.59,.87,s),.555))/atlas_size])
		var glow := PackedColorArray([Color(alpha*surge*.83,0,0),Color(alpha*surge,0,0)])
		if i > 0:
			fx._append_quad(previous,row,previous_uv,uv,previous_ink,ink,fx._textures[0])
			fx._append_quad(previous_ridge,ridge,previous_glow_uv,glow_uv,previous_glow,glow,fx._textures[0])
		previous=row
		previous_uv=uv
		previous_ink=ink
		previous_ridge=ridge
		previous_glow_uv=glow_uv
		previous_glow=glow
