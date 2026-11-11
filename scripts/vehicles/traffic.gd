extends Node
## Circulation automatique : des véhicules roulent à droite sur les vraies rues de Dakar,
## choisissent leur chemin aux carrefours, ralentissent dans les virages et freinent devant
## un obstacle (piéton, joueur, autre véhicule). Ils apparaissent autour du joueur et
## disparaissent quand ils sont trop loin, pour garder le jeu fluide.

const Car = preload("res://scripts/vehicles/car.gd")
const Vehicles = preload("res://scripts/world/vehicles.gd")

const MAX_CARS := 26
const SPAWN_MIN := 90.0
const SPAWN_MAX := 330.0
const DESPAWN := 450.0
const LANE := 1.7
const MIX := [["taxi_sn", 34], ["car_rapide_3d", 14], ["p405", 14], ["clando", 10], ["ndiaga", 8], ["sedan_3d", 7], ["wagon_3d", 6], ["jakarta", 7]]

var city = null
var player: Node3D = null
var nodes: Array[Vector3] = []   # carrefours et points des rues
var links: Array = []            # voisins de chaque point
var cars: Array = []
var rng := RandomNumberGenerator.new()
var _timer := 0.0


func setup(p_city, p_player: Node3D) -> void:
	city = p_city
	player = p_player
	rng.seed = 99
	nodes = city.drive_nodes
	links = city.drive_links


func _process(delta: float) -> void:
	if nodes.is_empty() or player == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.7
	var p := player.global_position
	for c in cars.duplicate():
		if not is_instance_valid(c):
			cars.erase(c)
		elif c.global_position.distance_to(p) > DESPAWN and c.ai == self:
			cars.erase(c)
			c.queue_free()
	var budget := 3
	while cars.size() < MAX_CARS and budget > 0:
		budget -= 1
		_spawn_near(p)


func _pick_kind() -> String:
	var total := 0
	for e in MIX:
		total += e[1]
	var r := rng.randi() % total
	for e in MIX:
		r -= e[1]
		if r < 0:
			return e[0]
	return "taxi_sn"


func _spawn_near(p: Vector3) -> void:
	for attempt in 30:
		var i := rng.randi() % nodes.size()
		var d := nodes[i].distance_to(p)
		if d < SPAWN_MIN or d > SPAWN_MAX or links[i].is_empty():
			continue
		var j: int = links[i].pick_random()
		var dir := (nodes[j] - nodes[i])
		dir.y = 0.0
		if dir.length() < 2.0:
			continue
		dir = dir.normalized()
		var right := Vector3(-dir.z, 0.0, dir.x)
		var pos := nodes[i] + right * LANE + Vector3(0, 0.3, 0)
		# pas d'apparition sur un autre véhicule
		var free := true
		for c in get_tree().get_nodes_in_group("vehicle"):
			if c.global_position.distance_to(pos) < 7.0:
				free = false
				break
		if not free:
			continue
		var kind := _pick_kind()
		var model := Vehicles.make(kind, rng)
		var car := Car.new()
		car.setup(kind, model, Vehicles.size_of(kind))
		city.add_child(car)
		car.global_position = pos
		car.rotation.y = atan2(-dir.z, dir.x)
		car.set_meta("from", i)
		car.set_meta("to", j)
		car.set_meta("cruise", rng.randf_range(8.0, 12.5) if kind != "jakarta" else rng.randf_range(9.0, 13.0))
		car.ai = self
		car.speed = 5.0
		car.wake()
		cars.append(car)
		return


## Appelé par chaque véhicule automatique à chaque image physique.
func drive(car, delta: float) -> void:
	var from: int = car.get_meta("from")
	var to: int = car.get_meta("to")
	var a := nodes[from]
	var b := nodes[to]
	var seg := b - a
	seg.y = 0.0
	var dir: Vector3 = seg.normalized() if seg.length() > 0.01 else car.forward()
	var right := Vector3(-dir.z, 0.0, dir.x)
	var target := b + right * LANE
	var pos: Vector3 = car.global_position
	var to_t := target - pos
	to_t.y = 0.0
	# point atteint : on choisit la rue suivante (pas de demi-tour sauf impasse)
	if to_t.length() < 5.0 or (pos - a).dot(dir) > seg.length() - 2.0:
		var options: Array = links[to].filter(func(k): return k != from)
		var nxt: int = options.pick_random() if not options.is_empty() else from
		car.set_meta("from", to)
		car.set_meta("to", nxt)
		return
	var f: Vector3 = car.forward()
	var cross := f.x * to_t.z - f.z * to_t.x
	var angle := atan2(cross, f.x * to_t.x + f.z * to_t.z)
	car.steer_in = clampf(angle * 2.2, -1.0, 1.0)
	# vitesse : plus lent dans les virages, arrêt devant un obstacle
	var cruise: float = car.get_meta("cruise")
	var want := cruise * (1.0 - clampf(absf(angle) / 1.0, 0.0, 0.75))
	var block := _obstacle_ahead(car, f)
	if block < 4.5:
		want = 0.0
	elif block < 12.0:
		want = minf(want, (block - 4.5) * 1.2)
	var diff: float = want - car.speed
	car.throttle_in = clampf(diff * 0.6, -1.0, 1.0)
	car.handbrake = want == 0.0 and car.speed < 1.0
	# bloqué longtemps (encombrement) : on repart dans une autre direction
	if car.speed < 0.3 and want == 0.0:
		var stuck: float = car.get_meta("stuck", 0.0) + delta
		car.set_meta("stuck", stuck)
		if stuck > 8.0:
			car.set_meta("stuck", 0.0)
			car.set_meta("to", from)
			car.set_meta("from", to)
	else:
		car.set_meta("stuck", 0.0)


## Distance du plus proche obstacle devant le véhicule (dans sa voie).
func _obstacle_ahead(car, f: Vector3) -> float:
	var best := 999.0
	var pos: Vector3 = car.global_position
	var half: float = car.size.x * 0.5
	var candidates: Array = []
	candidates.append_array(get_tree().get_nodes_in_group("vehicle"))
	candidates.append_array(get_tree().get_nodes_in_group("pedestrian"))
	if player and player.visible:
		candidates.append(player)
	for o in candidates:
		if o == car:
			continue
		var d: Vector3 = o.global_position - pos
		if absf(d.x) > 25.0 or absf(d.z) > 25.0:
			continue
		var ahead := d.x * f.x + d.z * f.z
		if ahead <= 0.0:
			continue
		var side := absf(d.x * f.z - d.z * f.x)
		if side < 1.7:
			best = minf(best, ahead - half)
	return best


func release(car) -> void:
	cars.erase(car)
