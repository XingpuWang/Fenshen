extends RefCounted
## Ground overlays only. Neither this renderer nor the grid changes the map art.
const GOLD:=Color("ffd65a")
const CYAN:=Color("8fe5ed")
const RANGE_FILL:=Color("17479c")
const RANGE_EDGE:=Color("164586")

static func hexagon(world: ShanheWorld,center: Vector2,radius: float) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for i in 6:
		result.append(center+Vector2.from_angle(deg_to_rad(i*60-30))*Vector2(radius,radius*world.grid_y_scale))
	return result

static func outline(canvas: CanvasItem,points: PackedVector2Array,color: Color,width: float) -> void:
	var loop:=points.duplicate()
	loop.append(loop[0])
	canvas.draw_polyline(loop,color,width,true)

static func glass_range(canvas: CanvasItem,game: Node2D,ids: Variant,skill: bool=false) -> void:
	var world: ShanheWorld=game.world
	var zoom: float=game.camera.zoom.x
	var members: Dictionary={}
	for id in ids: members[int(id)]=true
	var active:=int(world.units[game.selected_unit].cell)
	members[active]=true
	var tint:=RANGE_FILL if not skill else Color("f3d797")
	var edge_tint:=RANGE_EDGE if not skill else GOLD
	for ci in members:
		if int(ci)==active: continue
		var center: Vector2=world.center(int(ci))
		var points:=hexagon(world,center,world.radius-.45/zoom)
		# Deep blue stays legible over yellow fields while retaining terrain detail.
		var colors:=PackedColorArray()
		for point in points:
			var height: float=(point.y-center.y)/(world.radius*world.grid_y_scale)
			colors.append(Color(tint,(.55 if not skill else .20)-height*.055))
		canvas.draw_polygon(points,colors)
		for edge in 6:
			var cell: Dictionary=world.cells[int(ci)]
			var direction: Vector2i=world.DIRECTIONS[(6-edge)%6]
			var neighbor: int=world.by_hex.get(Vector2i(int(cell.q),int(cell.r))+direction,-1)
			var boundary:=not members.has(neighbor)
			if not boundary and int(ci)>neighbor: continue
			var a:=points[edge]
			var b:=points[(edge+1)%6]
			if boundary:
				canvas.draw_line(a,b,Color(edge_tint,.06),9.0/zoom,true)
				canvas.draw_line(a,b,Color(edge_tint,.18),4.0/zoom,true)
				canvas.draw_line(a,b,Color(edge_tint,.96),1.65/zoom,true)
			else:
				canvas.draw_line(a,b,Color(edge_tint,.82),1.15/zoom,true)

static func glow_hex(canvas: CanvasItem,world: ShanheWorld,center: Vector2,zoom: float,tint: Color,pulse: float=1.0) -> void:
	for margin in [18.0,11.0,5.0]:
		canvas.draw_colored_polygon(hexagon(world,center,world.radius+margin/zoom),Color(1,.63,.04,.04*pulse))
	var points:=hexagon(world,center,world.radius-1.0/zoom)
	canvas.draw_colored_polygon(points,Color(tint,.23*pulse))
	outline(canvas,points,Color(tint,.08),10.0/zoom)
	outline(canvas,points,Color(tint,.22),4.0/zoom)
	outline(canvas,points,Color("ffd44e"),1.65/zoom)
	# Short highlights on each bevel suggest a lit, raised tactical tile.
	for i in 6:
		var corner:=points[i]
		var a:=corner.lerp(points[(i+5)%6],.20)
		var b:=corner.lerp(points[(i+1)%6],.20)
		canvas.draw_polyline(PackedVector2Array([a,corner,b]),Color("ffe88b"),1.7/zoom,true)

static func ellipse(canvas: CanvasItem,world: ShanheWorld,center: Vector2,radius: float,tint: Color,width: float) -> void:
	var points:=PackedVector2Array()
	for i in 49: points.append(center+Vector2.from_angle(i*TAU/48)*Vector2(radius,radius*world.grid_y_scale))
	canvas.draw_polyline(points,tint,width,true)

static func draw_ground(canvas: CanvasItem,game: Node2D,age: float) -> void:
	var world: ShanheWorld=game.world
	var zoom: float=game.camera.zoom.x
	if zoom<=.16: return
	glass_range(canvas,game,game.skill_range_cells if game.map_skill_targeting else game.reachable.get("dist",{}),game.map_skill_targeting)
	if game.hover_cell>=0:
		var valid: bool=game.skill_preview.get("reason","").is_empty() if game.map_skill_targeting else game.reachable.get("dist",{}).has(game.hover_cell)
		var center:=world.center(game.hover_cell)
		if valid:
			glow_hex(canvas,world,center,zoom,GOLD,.65)
		else:
			var points:=hexagon(world,center,world.radius-1.0/zoom)
			canvas.draw_colored_polygon(points,Color(.72,.20,.16,.14))
			outline(canvas,points,Color("e99a80"),1.4/zoom)
		if game.map_skill_targeting:
			for ci in game.skill_preview.get("cells",[]):
				canvas.draw_colored_polygon(hexagon(world,world.center(int(ci)),world.radius-2),Color(1,.65,.22,.12) if valid else Color(.8,.2,.2,.10))
	if game.is_map_casting():
		for ci in game.map_cast.cells:
			var points:=hexagon(world,world.center(int(ci)),world.radius-2)
			canvas.draw_colored_polygon(points,Color(1,.4,.1,.10))
			outline(canvas,points,Color(1,.72,.3,.45),1.0/zoom)
	if not game.selected_poi.is_empty():
		var poi: Dictionary=world.by_poi[game.selected_poi]
		if poi.type=="ferry":
			var a:=world.center(int(poi.banks[0]))
			var b:=world.center(int(poi.banks[1]))
			var tint:=CYAN if poi.owner=="player" else Color("d7a58b")
			for i in range(0,20,2): canvas.draw_line(a.lerp(b,i/20.0),a.lerp(b,(i+1)/20.0),Color(tint,.8),1.6/zoom,true)
			for ci in poi.banks: ellipse(canvas,world,world.center(int(ci)),world.radius*.65,tint,1.4/zoom)
	var at: Vector2=game.unit_nodes[game.selected_unit].position
	glow_hex(canvas,world,at,zoom,GOLD,.8)
	ellipse(canvas,world,at,world.radius*.73,Color("ffeaa1"),1.1/zoom)
	if game.path.size()>1:
		var end:=world.center(int(game.path[-1]))
		glow_hex(canvas,world,end,zoom,GOLD,.92+.08*sin(age*3.0))
		draw_route(canvas,game,age)
		# Four-point ground beacon under the destination pin.
		var star:=PackedVector2Array()
		for i in 8:
			var radius: float=(15.0 if i%2==0 else 3.5)/zoom
			star.append(end+Vector2.from_angle(i*TAU/8)*Vector2(radius,radius*world.grid_y_scale))
		canvas.draw_colored_polygon(star,Color("fff5bd"))

static func draw_route(canvas: CanvasItem,game: Node2D,age: float) -> void:
	var zoom: float=game.camera.zoom.x
	var points:=PackedVector2Array()
	for ci in game.path: points.append(game.world.center(int(ci)))
	points[0]=game.unit_nodes[game.selected_unit].position
	canvas.draw_polyline(points,Color(.24,.12,.025,.17),12.0/zoom,true)
	canvas.draw_polyline(points,Color(1,.63,.08,.08),8.0/zoom,true)
	canvas.draw_polyline(points,Color(1,.82,.36,.24),1.2/zoom,true)
	var total:=0.0
	var lengths: Array[float]=[]
	for i in range(1,points.size()):
		var length:=points[i-1].distance_to(points[i])*zoom
		lengths.append(length)
		total+=length
	var distance:=18.0+fposmod(age*23.0,30.0)
	while distance<total-14.0:
		var along:=distance
		var segment:=0
		while segment<lengths.size()-1 and along>lengths[segment]:
			along-=lengths[segment]
			segment+=1
		var fraction:=clampf(along/maxf(.001,lengths[segment]),0,1)
		var center:=points[segment].lerp(points[segment+1],fraction)
		var direction:=points[segment].direction_to(points[segment+1])
		var normal:=Vector2(-direction.y,direction.x)
		var form: Array[Vector2]=[Vector2(-11,-8),Vector2(-2,-8),Vector2(10,0),Vector2(-2,8),Vector2(-11,8),Vector2(1.5,0)]
		var shade:=PackedVector2Array()
		for vertex in form: shade.append(center+(direction*vertex.x+normal*vertex.y+Vector2(0,1.5))/zoom)
		canvas.draw_colored_polygon(shade,Color(.55,.25,.025,.35))
		for scale_factor in [1.75,1.32,1.0]:
			var arrow:=PackedVector2Array()
			for vertex in form: arrow.append(center+(direction*vertex.x+normal*vertex.y)*scale_factor/zoom)
			canvas.draw_colored_polygon(arrow,Color(1,.64,.06,.07) if scale_factor>1.5 else Color(1,.78,.14,.18) if scale_factor>1.0 else Color("ffd545"))
		var bevel:=PackedVector2Array()
		for i in 3: bevel.append(center+(direction*form[i].x+normal*form[i].y)/zoom)
		canvas.draw_polyline(bevel,Color("fff0a0"),.85/zoom,true)
		distance+=30.0

static func draw_destination_pin(canvas: CanvasItem,game: Node2D) -> void:
	if game.path.size()<2 or game.camera.zoom.x<=.16: return
	var at: Vector2=game.world.center(int(game.path[-1]))
	var zoom: float=game.camera.zoom.x
	canvas.draw_set_transform(at,0,Vector2.ONE/zoom)
	canvas.draw_line(Vector2(0,-12),Vector2(0,-28),Color("ffdf7d"),1.5,true)
	var shield:=PackedVector2Array([Vector2(0,-60),Vector2(17,-52),Vector2(15,-34),Vector2(0,-24),Vector2(-15,-34),Vector2(-17,-52)])
	outline(canvas,shield,Color(1,.67,.09,.10),9)
	canvas.draw_colored_polygon(shield,Color("65442a"))
	outline(canvas,shield,Color("ffe599"),1.4)
	var attack:=false
	if not game.selected_poi.is_empty():
		var poi: Dictionary=game.world.by_poi[game.selected_poi]
		var probe: Dictionary=game.world.units[game.selected_unit].duplicate()
		probe.cell=int(game.path[-1])
		attack=poi.owner=="shang" and game.world.can_capture(probe,poi)
	if attack:
		for facing in [-1,1]:
			canvas.draw_line(Vector2(-9*facing,-52),Vector2(8*facing,-34),Color("fff0bd"),2.6,true)
			canvas.draw_line(Vector2(1*facing,-34),Vector2(9*facing,-42),Color("ffe39c"),2,true)
	else:
		canvas.draw_line(Vector2(-5,-34),Vector2(-5,-52),Color("fff0bd"),2.2,true)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(-3,-52),Vector2(10,-49),Vector2(5,-44),Vector2(-3,-45)]),Color("ffe599"))
	canvas.draw_set_transform(Vector2.ZERO)
