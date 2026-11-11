extends CharacterBody3D
## Véhicule qu'on peut conduire (joueur) ou qui roule seul (circulation automatique).
## Physique « arcade » simple et stable : vitesse le long de l'axe avant (+X du modèle),
## braquage selon l'empattement, collisions qui freinent, capsule en bas pour franchir
## les bordures de trottoir.

const Vehicles = preload("res://scripts/world/vehicles.gd")
const Step = preload("res://scripts/core/step.gd")

## Caractéristiques par type : vitesse max (m/s), accélération, freinage, nom affiché.
const STATS := {
	"jakarta": [17.0, 6.0, 10.0, "la mobylette"],
	"car_rapide_3d": [17.0, 2.6, 6.0, "le car rapide"],
	"car_rapide": [17.0, 2.6, 6.0, "le car rapide"],
	"ndiaga": [18.0, 2.4, 6.0, "le Ndiaga Ndiaye"],
	"crafter": [24.0, 3.2, 7.0, "le minibus"],
	"taxi_sn": [30.0, 4.2, 8.0, "le taxi"],
	"taxi": [30.0, 4.2, 8.0, "le taxi"],
	"clando": [24.0, 3.2, 7.0, "le clando"],
	"jetta": [38.0, 6.0, 9.0, "la Jetta"],
}

signal crashed(impact)

var kind := "car"
var size := Vector3(4.4, 1.5, 1.8)
var driver: Node3D = null
var ai = null              # contrôleur de circulation automatique (traffic.gd) ou null
var speed := 0.0
var steer := 0.0
var max_speed := 28.0
var accel := 4.0
var brake := 8.0
var display_name := "la voiture"
var throttle_in := 0.0
var steer_in := 0.0
var handbrake := false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var headlight: SpotLight3D
var _idle := 0.0


func setup(p_kind: String, model: Node3D, p_size: Vector3) -> void:
	kind = p_kind
	size = p_size
	name = "Vehicule_" + kind
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	safe_margin = 0.02
	add_child(model)
	var st: Array = STATS.get(kind, [28.0, 4.0, 8.0, "la voiture"])
	max_speed = st[0]
	accel = st[1]
	brake = st[2]
	display_name = st[3]
	# capsule couchée en bas (franchit les bordures) + boîte pour la carrosserie
	var r := clampf(size.y * 0.3, 0.3, 0.6)
	if size.x < 2.5:
		r = 0.3
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = maxf(size.x * 0.92, r * 2.0 + 0.01)
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.rotation.z = PI / 2.0
	cs.position.y = r
	add_child(cs)
	var body_h := size.y - r * 1.2
	if body_h > 0.2:
		var bx := BoxShape3D.new()
		bx.size = Vector3(size.x * 0.95, body_h, size.z * 0.9)
		var cs2 := CollisionShape3D.new()
		cs2.shape = bx
		cs2.position.y = r * 1.2 + body_h * 0.5
		add_child(cs2)
	add_to_group("vehicle")
	add_to_group("interactable")
	set_physics_process(false)


func forward() -> Vector3:
	return global_transform.basis.x.normalized()


var _taking := false

const DRIVER_SHOUTS := ["Eh ! Ma voiture !!", "Sàcc ! Au voleur !", "Wouy ! Qu'est-ce que tu fais ?!", "Yow ! Lâche ça !", "Ma voiture, waay !"]


func get_prompt() -> String:
	if driver != null or _taking:
		return ""
	if ai:
		return "[E] Prendre " + display_name
	return "[E] Conduire " + display_name


func interact(player) -> void:
	if driver != null or _taking or not player.has_method("enter_vehicle"):
		return
	if ai:
		_carjack(player)
	else:
		player.enter_vehicle(self)


## Vol de voiture : le véhicule s'arrête, on ouvre la portière, le conducteur est sorti
## de force et s'enfuit en criant, puis le joueur prend le volant.
func _carjack(player) -> void:
	_taking = true
	var traffic = ai
	ai.release(self)
	ai = null
	speed = 0.0
	throttle_in = 0.0
	handbrake = true
	set_physics_process(true)
	player.controls_locked = true
	# portière ouverte : un panneau qui pivote côté conducteur
	var left := -global_transform.basis.z.normalized()
	var door := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(minf(1.1, size.x * 0.28), size.y * 0.55, 0.06)
	door.mesh = bm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.15, 0.17, 0.2)
	dm.metallic = 0.5
	door.material_override = dm
	add_child(door)
	var hinge := Vector3(size.x * 0.18, size.y * 0.45, -size.z * 0.5)
	door.position = hinge + Vector3(-bm.size.x * 0.5, 0, 0)
	var tw := create_tween()
	tw.tween_method(func(a: float):
		door.transform = Transform3D(Basis(Vector3.UP, a), Vector3.ZERO).translated(Vector3(-bm.size.x * 0.5, 0, 0))
		door.position += hinge, 0.0, -1.1, 0.35)
	await get_tree().create_timer(0.4).timeout
	# le conducteur est éjecté et s'enfuit
	if traffic and traffic.city:
		var Pedestrian = load("res://scripts/characters/pedestrian.gd")
		var ped = Pedestrian.new()
		traffic.city.add_child(ped)
		var city = traffic.city
		var node: int = city.random_sidewalk_node_near(global_position, 40.0) if city.has_method("random_sidewalk_node_near") else city.random_sidewalk_node()
		ped.setup(city, node, {"female": randf() < 0.2, "top": [Color("ecf0f1"), Color("2c3e50"), Color("1f5fae"), Color("c0392b")].pick_random()})
		ped.global_position = global_position + left * (size.z * 0.5 + 0.9) + Vector3(0, 0.3, 0)
		ped.flee_from(player.global_position, 7.0)
		ped.say(DRIVER_SHOUTS.pick_random(), 3.0)
	await get_tree().create_timer(0.5).timeout
	door.queue_free()
	player.controls_locked = false
	_taking = false
	player.enter_vehicle(self)


func take_control(p: Node3D) -> void:
	if ai:
		ai.release(self)
		ai = null
	driver = p
	set_physics_process(true)
	if headlight == null:
		headlight = SpotLight3D.new()
		headlight.spot_range = 45.0
		headlight.spot_angle = 32.0
		headlight.light_energy = 0.0
		headlight.light_color = Color(1.0, 0.95, 0.85)
		headlight.position = Vector3(size.x * 0.5, 0.8, 0.0)
		headlight.rotation.y = -PI / 2.0   # la lampe éclaire vers -Z : on la tourne vers +X
		headlight.rotation.x = -0.08
		add_child(headlight)


func release_control() -> void:
	driver = null
	throttle_in = 0.0
	steer_in = 0.0
	handbrake = true
	if headlight:
		headlight.light_energy = 0.0


func wake() -> void:
	set_physics_process(true)
	_idle = 0.0


func _physics_process(delta: float) -> void:
	if driver:
		throttle_in = Input.get_axis("move_back", "move_forward")
		steer_in = Input.get_axis("move_left", "move_right")
		handbrake = Input.is_action_pressed("jump")
		if headlight:
			headlight.light_energy = 6.0 if Vehicles.night_level() > 0.35 else 0.0
	elif ai:
		ai.drive(self, delta)
	else:
		throttle_in = 0.0
		steer_in = 0.0
	_simulate(delta)
	# véhicule à l'arrêt sans conducteur : on arrête la physique (économie)
	if driver == null and ai == null:
		if absf(speed) < 0.05 and is_on_floor():
			_idle += delta
			if _idle > 1.0:
				set_physics_process(false)
		else:
			_idle = 0.0


func _simulate(delta: float) -> void:
	# accélération / freinage / marche arrière
	if throttle_in > 0.05:
		if speed < -0.3:
			speed = move_toward(speed, 0.0, brake * delta)
		else:
			speed += accel * throttle_in * delta * (1.0 - clampf(speed / max_speed, 0.0, 1.0) * 0.6)
	elif throttle_in < -0.05:
		if speed > 0.3:
			speed = move_toward(speed, 0.0, brake * -throttle_in * delta)
		else:
			speed -= accel * 0.6 * -throttle_in * delta
	else:
		speed = move_toward(speed, 0.0, (0.8 + absf(speed) * 0.05) * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, brake * 1.4 * delta)
	speed = clampf(speed, -max_speed * 0.3, max_speed)
	# braquage (plus doux à grande vitesse)
	var max_steer := lerpf(0.6, 0.18, clampf(absf(speed) / max_speed, 0.0, 1.0))
	steer = move_toward(steer, steer_in * max_steer, 2.5 * delta)
	var wheelbase := maxf(size.x * 0.6, 1.0)
	var yaw_rate := -speed * tan(steer) / wheelbase
	rotate_y(yaw_rate * delta)
	var f := forward()
	velocity.x = f.x * speed
	velocity.z = f.z * speed
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta
	Step.try_step(self, Vector3(velocity.x, 0.0, velocity.z), delta)   # bordures de trottoir
	move_and_slide()
	# chocs : les murs et les autres véhicules freinent brutalement
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.25:
			continue   # sol, pente ou marche : pas un choc
		var impact := -f.dot(n) * speed
		if impact > 3.0:
			crashed.emit(impact)
			speed *= 0.25
			var other = col.get_collider()
			if other is CharacterBody3D and other.has_method("wake"):
				other.wake()
				other.speed += speed * 0.3
	# sortie de l'eau / chute hors de la carte : on remet le véhicule sur la route
	if global_position.y < -5.0:
		global_position.y = 2.0
		speed = 0.0


## Vitesse en km/h pour l'interface.
func kmh() -> int:
	return int(absf(speed) * 3.6)
