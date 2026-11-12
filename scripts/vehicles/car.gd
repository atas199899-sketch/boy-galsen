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
var driver_model: Node3D = null   # conducteur visible au volant (circulation automatique)
var driver_look := {}


## Place un conducteur assis au volant (côté gauche, on roule à droite au Sénégal).
func add_driver(look: Dictionary) -> void:
	var Humanoid = load("res://scripts/characters/humanoid.gd")
	var h = Humanoid.new()
	add_child(h)
	h.build(look)
	h.position = seat_position()
	h.rotation.y = -PI / 2.0   # le personnage regarde vers -Z : on le tourne vers l'avant (+X)
	h.set_driving(true)
	for gi in h.find_children("*", "GeometryInstance3D", true, false):
		gi.visibility_range_end = 90.0
	driver_model = h
	driver_look = look
	_fit_driver.call_deferred()


## Après application de la pose de conduite, abaisse le conducteur si sa tête dépasse du toit.
func _fit_driver() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if driver_model == null or driver_model.real == null:
		return
	var sk: Skeleton3D = driver_model.real.skeleton
	var head := sk.find_bone("Head")
	if head < 0:
		return
	var head_top := (global_transform.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(head))).origin.y + 0.16
	var roof := size.y - 0.14
	if head_top > roof:
		driver_model.position.y -= minf(head_top - roof, 0.45)


## Place du conducteur, en fraction de la longueur (x), hauteur du siège (y), fraction de la largeur (z).
## Côté gauche (-Z) : on roule à droite au Sénégal.
const SEATS := {
	"jakarta": [-0.1, 0.35, 0.0],
	"clando": [0.13, 0.06, -0.22],         # cabine à l'avant, caisse derrière
	"car_rapide_3d": [0.33, 0.45, -0.24],
	"car_rapide": [0.33, 0.45, -0.24],
	"ndiaga": [0.36, 0.5, -0.24],
	"crafter": [0.3, 0.42, -0.24],
}


func seat_position() -> Vector3:
	var st: Array = SEATS.get(kind, [0.0, 0.14, -0.22])
	return Vector3(size.x * st[0], st[1], size.z * st[2])


func setup(p_kind: String, model: Node3D, p_size: Vector3) -> void:
	kind = p_kind
	size = p_size
	name = "Vehicule_" + kind
	collision_layer = 4
	collision_mask = 1 | 4   # pas les personnages : une voiture ne doit jamais « monter » sur quelqu'un
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


## Vol de voiture : le véhicule s'arrête, le joueur va à la portière, l'ouvre, tire le
## conducteur hors de la voiture (il tombe, se relève et s'enfuit), puis prend le volant.
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
	var left := -global_transform.basis.z.normalized()
	var fwd := forward()
	var seat_world := global_transform * seat_position()
	# le joueur se place devant la portière, face à la voiture
	var door_spot := seat_world + left * (size.z * 0.28 + 0.75)
	door_spot.y = global_position.y + 0.2
	player.global_position = door_spot
	var to_car := seat_world - door_spot
	player.model.rotation.y = atan2(-to_car.x, -to_car.z)
	# caméra derrière le joueur, tournée vers la portière : la scène est bien visible
	player.yaw = player.model.rotation.y + 0.35
	player.pitch = -0.16
	player.spring.spring_length = 3.4
	player._cam_free = 3.0
	player.model.play_action("Interact", 1.4)
	# portière qui s'ouvre : tôle de la couleur de la carrosserie + vitre
	var door := Node3D.new()
	add_child(door)
	var door_w := minf(1.1, size.x * 0.28)
	var door_h := size.y * 0.55
	var bm := BoxMesh.new()
	bm.size = Vector3(door_w, door_h * 0.55, 0.06)
	var panel := MeshInstance3D.new()
	panel.mesh = bm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Vehicles.paint_of(kind)
	dm.metallic = 0.4
	dm.roughness = 0.35
	panel.material_override = dm
	panel.position = Vector3(-door_w * 0.5, -door_h * 0.2, 0)
	door.add_child(panel)
	var gm := BoxMesh.new()
	gm.size = Vector3(door_w * 0.9, door_h * 0.42, 0.03)
	var glass := MeshInstance3D.new()
	glass.mesh = gm
	glass.material_override = Vehicles.glass_material()
	glass.position = Vector3(-door_w * 0.5, door_h * 0.3, 0)
	door.add_child(glass)
	var hinge := Vector3(seat_position().x + door_w * 0.5, size.y * 0.5, -size.z * 0.5)
	var open_door := func(a: float):
		door.transform = Transform3D(Basis(Vector3.UP, a), hinge)
	open_door.call(0.0)
	var tw := create_tween()
	tw.tween_method(open_door, 0.0, -1.15, 0.35)
	await get_tree().create_timer(0.45).timeout
	# on regarde le conducteur, mains sur le volant : la caméra se cadre sur lui
	player.spring.spring_length = 3.2
	var to_seat: Vector3 = seat_world - player.global_position
	player.yaw = atan2(-to_seat.x, -to_seat.z) + 0.75   # de côté : on voit la portière et le conducteur
	player.pitch = -0.2
	player._cam_free = 3.0
	if driver_model and driver_model.real:
		driver_model.real.anim.speed_scale = 0.0   # figé, les mains sur le volant
	await get_tree().create_timer(0.9).timeout
	# on le tire hors de la voiture : il est entraîné vers le joueur
	var out_local := seat_position() + Vector3(0, -seat_position().y + 0.05, -(size.z * 0.5 + 1.1))
	if driver_model:
		player.model.play_action("Push", 1.0)
		driver_model.set_driving(false)
		driver_model.play_action("Hit_Chest", 0.9)
		var tw2 := create_tween()
		tw2.tween_property(driver_model, "position", out_local + Vector3(0, 0.35, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw2.parallel().tween_property(driver_model, "rotation:y", PI / 2.0, 0.35)
		tw2.tween_property(driver_model, "position", out_local, 0.25).set_trans(Tween.TRANS_BOUNCE)
		await tw2.finished
		# il se relève…
		await get_tree().create_timer(0.45).timeout
	# il se relève et s'enfuit (il devient un passant)
	if traffic and traffic.city:
		var Pedestrian = load("res://scripts/characters/pedestrian.gd")
		var ped = Pedestrian.new()
		var city = traffic.city
		city.add_child(ped)
		var node: int = city.random_sidewalk_node_near(global_position, 40.0) if city.has_method("random_sidewalk_node_near") else city.random_sidewalk_node()
		var look: Dictionary = driver_look if not driver_look.is_empty() else {"top": Color("2c3e50")}
		ped.setup(city, node, look)
		ped.global_position = global_transform * out_local + Vector3(0, 0.2, 0)
		ped.flee_from(player.global_position, 7.0)
		ped.say(DRIVER_SHOUTS.pick_random(), 3.0)
	if driver_model:
		driver_model.queue_free()
		driver_model = null
	var tw3 := create_tween()
	tw3.tween_method(open_door, -1.15, 0.0, 0.3)
	await tw3.finished
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
