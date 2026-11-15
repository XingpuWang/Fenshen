extends SceneTree
const World=preload("res://scripts/world_model.gd")
var checks: int=0
var errors: Array[String]=[]
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition: errors.append(message)
func _initialize() -> void:
	var w=World.new()
	var counts={"city":0,"pass":0,"village":0,"ferry":0}
	for p in w.pois: counts[p.type]+=1
	check(counts=={"city":40,"pass":27,"village":33,"ferry":25},"nine-region POI counts")
	for i in w.cells.size():
		var c: Dictionary=w.cells[i]
		if int(c.t)!=0: check(not w.walkable(i),"terrain blocked %d" %i)
		else:
			for n in c.n: check(int(w.cells[int(n)].t)==0,"ordinary edge cannot enter water or mountain")
		check(w.cell_at(w.center(i))==i,"hex round-trip %d" %i)
	for p in w.pois:
		check(not p.cells.is_empty(),"POI footprint exists "+p.id)
		var original: String=p.owner
		p.owner="neutral"
		for ci in p.cells: check(not w.walkable(int(ci)),"neutral blocks "+p.id)
		p.owner="shang"
		for ci in p.cells: check(not w.walkable(int(ci)),"enemy blocks "+p.id)
		p.owner="player"
		for ci in p.cells: check(w.walkable(int(ci)),"player owns footprint "+p.id)
		if p.type=="ferry":
			var a=int(p.banks[0])
			var b=int(p.banks[1])
			check(a!=b,"distinct ferry banks "+p.id)
			check(w.edge_cost(a,b)==2,"owned ferry costs two "+p.id)
			p.owner="neutral"
			check(w.edge_cost(a,b)==-1,"closed ferry blocks "+p.id)
			p.owner="player"
			check(w.edge_cost(a,b)==2,"reopened ferry works "+p.id)
			p.owner="shang"
			check(w.edge_cost(a,b)==-1,"ownership loss closes ferry "+p.id)
		p.owner=original
	var u: Dictionary=w.units[0]
	var start=int(u.cell)
	var result=w.search(start,6,u.id)
	check(result.dist.size()>20,"initial army has meaningful movement area")
	for ci in result.dist:
		check(int(result.dist[ci])<=6,"reachability respects action budget")
		var route=w.route(result,ci)
		var cost=0
		for j in range(1,route.size()):
			var edge=w.edge_cost(route[j-1],route[j],u.id)
			check(edge>0,"route never enters foreign POI or blocked terrain")
			cost+=edge
		check(cost==int(result.dist[ci]),"route cost matches search")
	var ferry: Dictionary=w.by_poi.wanluo_ferry_0
	check(not w.can_capture(u,ferry),"remote capture blocked")
	var adjacent=-1
	for n in w.cells[int(ferry.banks[1])].n:
		if w.walkable(int(n)):
			adjacent=int(n)
			break
	check(adjacent>=0,"ferry bank reachable from land")
	u.cell=adjacent
	u.ap=0
	check(not w.capture(u,ferry),"zero-action capture blocked")
	u.ap=6
	check(w.capture(u,ferry),"adjacent capture succeeds")
	check(int(u.ap)==5 and ferry.owner=="player","capture consumes action and changes owner")
	check(not w.capture(u,ferry),"already-owned cannot be captured again")
	var crossing=w.search(adjacent,6,u.id,int(ferry.banks[0]))
	check(crossing.dist.has(int(ferry.banks[0])),"captured ferry connects opposite bank")
	var old_ap=int(u.ap)
	w.next_turn()
	check(int(u.ap)==int(u.max_ap) and w.turn==2,"next turn refreshes all movement")
	check(w.save_game("user://navigation-test.json")==OK,"save succeeds")
	ferry.owner="neutral"
	u.cell=start
	check(w.load_game("user://navigation-test.json"),"load succeeds")
	check(ferry.owner=="player" and int(u.cell)==adjacent,"save preserves position and ownership")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://navigation-test.json"))
	var report={"engine":Engine.get_version_info().string,"checks":checks,"failures":errors,"counts":counts,"initial_reachable_cells":result.dist.size()}
	var f=FileAccess.open("res://previews/navigation-tests.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
