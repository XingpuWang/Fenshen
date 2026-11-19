extends Node2D
## Replayable presentation for the solo spear study. All points are in stage space.
const Textures = preload("res://scripts/runtime_textures.gd")
const ATLAS_PATH := "res://assets/characters/nezha/effects/combat.png"
# These regions are from Nezha's painted combat sheet. The hot point of each
# drawing was measured separately; it does not coincide with its tile centre.
const NIB := Rect2(326,118,294,108)
const NIB_TIP := Vector2(289,54)
const WAKE := Rect2(65,151,172,61)
const HIT := Rect2(653,83,265,176)
const HIT_CORE := Vector2(215,96)
const FLECKS := [Rect2(1167,139,23,29), Rect2(1149,175,28,20), Rect2(1111,118,17,15)]
const MAX_TRAIL := 145.0
const RESIDUE_TIME := .15

var _atlas: Texture2D
var _tip := Vector2.ZERO
var _shaft := Vector2.RIGHT
var _contact := Vector2.ZERO
var _hit_direction := Vector2.RIGHT
var _contact_age := -1.0
var _strength := 0.0
var _beat := 1
var _path := PackedVector2Array()

func _ready() -> void:
	_atlas = Textures.get_texture(ATLAS_PATH)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## history is oldest to newest. After impact its last sample stays at the
## contact tick; a later retraction can never pull the spent wake backwards.
func set_sample(hand: Vector2, tip: Vector2, history: PackedVector2Array, energy: float, contact: Vector2, contact_age: float, beat: int = 1) -> void:
	_tip = tip
	_shaft = hand.direction_to(tip)
	_contact = contact
	_contact_age = contact_age
	_strength = clampf(energy,0.0,1.0)
	_beat = beat
	var endpoint := contact if contact_age>=0.0 else tip
	_path = _recent_path(history,endpoint)
	_hit_direction = Vector2.RIGHT
	if _path.size()>=2:
		_hit_direction = _path[_path.size()-2].direction_to(endpoint)
	queue_redraw()

static func _recent_path(history: PackedVector2Array, endpoint: Vector2) -> PackedVector2Array:
	var path := PackedVector2Array([endpoint])
	var last := endpoint
	var remaining := MAX_TRAIL
	for i in range(history.size()-1,-1,-1):
		var point := history[i]
		var distance := last.distance_to(point)
		if distance<.65: continue
		if distance>MAX_TRAIL*2.5: break
		if distance>=remaining:
			path.append(last.move_toward(point,remaining))
			break
		path.append(point)
		remaining -= distance
		last = point
	path.reverse()
	return path

func _draw() -> void:
	if _atlas==null: return
	if _contact_age<0.0:
		if _strength<=.005: return
		_draw_wake(_strength)
		_draw_nib(_tip,_shaft,_strength)
	elif _contact_age<RESIDUE_TIME:
		var wake_alpha := (1.0-smoothstep(0,.115,_contact_age))*.77
		_draw_wake(wake_alpha)
		_draw_contact()

func _draw_nib(at: Vector2, direction: Vector2, energy: float) -> void:
	if direction.length_squared()<.5: return
	# Draped over the final few centimetres of the metal, with a short hot point
	# projecting beyond it. The rear brushwork reveals the shaft below.
	var length := lerpf(52,111,energy)
	# Let the written point extend into the air, then compress it into the actual
	# impact instead of letting it pass the mark a beat before the metal arrives.
	var ahead := maxf(4.0,(_contact-at).dot(direction)+4.0)
	var projection := minf(6.0+39.0*energy,ahead)
	var scale_xy := Vector2(length/NIB.size.x,length/NIB.size.x*(.58+.16*energy))
	draw_set_transform(at+direction*projection,direction.angle(),scale_xy)
	draw_texture_rect_region(_atlas,Rect2(-NIB_TIP,NIB.size),NIB,Color(1,.98,.90,.91*energy))
	draw_set_transform(Vector2.ZERO)

func _draw_wake(power: float) -> void:
	var count := _path.size()
	if power<=.01 or count<2: return
	var lengths := PackedFloat32Array([0])
	for i in range(1,count):
		lengths.append(lengths[i-1]+_path[i-1].distance_to(_path[i]))
	var distance := lengths[count-1]
	if distance<3.0: return
	var opacity := smoothstep(3,38,distance)*power
	var widths := lerpf(5.0,13.0,clampf(distance/MAX_TRAIL,0,1))
	var top := PackedVector2Array()
	var base := PackedVector2Array()
	var uv := _atlas.get_size()
	var segment := 1
	# Subdivide by distance, so the texture stretches smoothly across uneven
	# fixed-step samples and the oldest end always tapers to a point.
	for i in 13:
		var t := i/12.0
		var along := t*distance
		while segment<count-1 and lengths[segment]<along: segment+=1
		var tangent := _path[segment-1].direction_to(_path[segment])
		var center := _path[segment-1]+tangent*(along-lengths[segment-1])
		var width := widths*(.08+.92*sin(PI*t))*(.70+.30*t)
		var normal := tangent.orthogonal()
		top.append(center+normal*width)
		base.append(center-normal*width)
		if i==0: continue
		var a := (i-1)/12.0
		var left := (WAKE.position.x+a*WAKE.size.x)/uv.x
		var right := (WAKE.position.x+t*WAKE.size.x)/uv.x
		var upper := WAKE.position.y/uv.y
		var lower := WAKE.end.y/uv.y
		var old := Color(1,.88,.63,opacity*smoothstep(0,.36,a)*(.40+.58*a))
		var fresh := Color(1,.88,.63,opacity*smoothstep(0,.36,t)*(.40+.58*t))
		draw_primitive(PackedVector2Array([top[i-1],top[i],base[i],base[i-1]]),
			PackedColorArray([old,fresh,fresh,old]),PackedVector2Array([Vector2(left,upper),Vector2(right,upper),Vector2(right,lower),Vector2(left,lower)]),_atlas)

func _draw_contact() -> void:
	var age := _contact_age
	var t := age/RESIDUE_TIME
	var weight := 1.10 if _beat==2 else 1.0
	var burst := 1.0-smoothstep(.023,.103,age)
	if burst>.005:
		var extent := weight*lerpf(.32,.48,smoothstep(0,.057,age))
		draw_set_transform(_contact,_hit_direction.angle(),Vector2(extent,extent*.91))
		draw_texture_rect_region(_atlas,Rect2(-HIT_CORE,HIT.size),HIT,Color(1,1,.95,burst))
		draw_set_transform(Vector2.ZERO)
	var alpha := smoothstep(.012,.034,age)*(1.0-smoothstep(.074,RESIDUE_TIME,age))
	if alpha<=.005: return
	const ANGLES := [-.66,.34,-1.18]
	for i in FLECKS.size():
		var angle: float = ANGLES[i]*signf(_hit_direction.x if absf(_hit_direction.x)>.2 else 1.0)
		var ray := _hit_direction.rotated(angle)
		var reach := (11.0+float(i)*1.6+t*(42.0-i*6.0))*weight
		var pos := _contact+ray*reach+Vector2(0,t*t*(11.0+i*3.0))
		var source: Rect2=FLECKS[i]
		var size := source.size*(.48-.18*t)*weight
		draw_set_transform(pos,ray.angle()-.4+t*.55)
		draw_texture_rect_region(_atlas,Rect2(-size*.5,size),source,Color(1,1,.96,alpha))
	draw_set_transform(Vector2.ZERO)
