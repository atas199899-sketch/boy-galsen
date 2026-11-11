extends CharacterBody3D
## Passant : marche sur les trottoirs d'un coin de rue à l'autre, traverse aux passages,
## s'arrête parfois (pour discuter, regarder une boutique…).

const Humanoid = preload("res://scripts/characters/humanoid.gd")
const Step = preload("res://scripts/core/step.gd")

var city = null
var node_id := -1
var target := Vector3.ZERO
var speed := 1.3
var wait := 0.0
var model
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _lateral := 0.0
var chat_time := 0.0           # temps restant de discussion
var flee_time := 0.0
var flee_dir := Vector3.ZERO
var chat_center := Vector3.ZERO
var _say_timer := 0.0
var _greet_cooldown := 0.0
var bubble: Label3D

const CHAT_LINES := ["Nanga def ?", "Mangi fi rek !", "Jamm rek.", "Ça va bien ?", "Waaw, waaw !", "Dégg nga ?",
	"Alhamdoulilah.", "Yalla na Yalla sàmm !", "Tu as vu le match ?", "Les prix ont encore monté…", "Ndank ndank…",
	"Ah bon ?!", "Wallaay !", "Ba beneen yoon !", "Le car rapide était plein.", "Jërëjëf !", "Inchallah.", "C'est vrai, hein !",
	"Sa yaay nangi ci jamm ?", "Dama sonn…", "On se voit à la descente !"]
const GREET_LINES := ["Salam aleykoum !", "Nanga def ?", "Bonsoir !", "Na nga fanaane ?", "Ça va, jeune ?"]


func setup(p_city, start_node: int, look: Dictionary) -> void:
	city = p_city
	node_id = start_node
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	model = Humanoid.new()
	add_child(model)
	model.build(look)
	speed = randf_range(1.0, 1.6)
	add_to_group("pedestrian")
	bubble = Label3D.new()
	bubble.font_size = 44
	bubble.pixel_size = 0.0045
	bubble.outline_size = 10
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.position.y = 2.1
	bubble.visible = false
	bubble.visibility_range_end = 20.0
	add_child(bubble)
	_lateral = randf_range(-0.7, 0.7)
	position = city.sidewalk_nodes[node_id] + Vector3(_lateral, 0.0, _lateral)
	_pick_next()


func _pick_next() -> void:
	var links: Array = city.sidewalk_links[node_id]
	node_id = links.pick_random()
	_lateral = randf_range(-0.7, 0.7)
	target = city.sidewalk_nodes[node_id] + Vector3(_lateral, 0.0, -_lateral)
	if randf() < 0.15:
		wait = randf_range(2.0, 7.0)
	elif randf() < 0.25:
		_try_join_chat()


func _physics_process(delta: float) -> void:
	if city == null:
		return
	var to := target - global_position
	to.y = 0.0
	var hv := Vector3.ZERO
	if flee_time > 0.0:
		flee_time -= delta
		hv = flee_dir * 4.6
	elif wait > 0.0:
		wait -= delta
	elif to.length() < 0.6:
		_pick_next()
	else:
		hv = to.normalized() * speed
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	Step.try_step(self, hv, delta)
	move_and_slide()
	var sp := Vector2(velocity.x, velocity.z).length()
	if sp > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-velocity.x, -velocity.z), clampf(6.0 * delta, 0.0, 1.0))
	model.animate(sp, delta)



# ---------------------------------------------------------------- vie de rue

## Commence une discussion autour d'un point (les participants se font face).
func start_chat(center: Vector3, duration: float) -> void:
	chat_center = center
	chat_time = duration
	wait = duration
	_say_timer = randf_range(0.5, 3.0)
	model.set_talking(true)


## Cherche un passant proche pour discuter avec lui.
func _try_join_chat() -> void:
	for o in get_tree().get_nodes_in_group("pedestrian"):
		if o == self or o.chat_time > 0.0:
			continue
		if o.global_position.distance_to(global_position) < 6.0:
			var center: Vector3 = (o.global_position + global_position) * 0.5
			var t := randf_range(8.0, 25.0)
			start_chat(center, t)
			o.start_chat(center, t)
			return


func say(text: String, duration := 2.6) -> void:
	bubble.text = text
	bubble.visible = true
	bubble.set_meta("t", duration)


func _process(delta: float) -> void:
	if bubble.visible:
		var t: float = bubble.get_meta("t", 0.0) - delta
		bubble.set_meta("t", t)
		if t <= 0.0:
			bubble.visible = false
	if chat_time > 0.0:
		chat_time -= delta
		var to := chat_center - global_position
		if to.length() > 0.2:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(-to.x, -to.z), clampf(4.0 * delta, 0.0, 1.0))
		_say_timer -= delta
		if _say_timer <= 0.0:
			_say_timer = randf_range(3.0, 7.0)
			if randf() < 0.6:
				say(CHAT_LINES.pick_random())
		if chat_time <= 0.0:
			model.set_talking(false)
			wait = 0.0
	# salue le joueur qui passe tout près
	_greet_cooldown -= delta
	if _greet_cooldown <= 0.0 and chat_time <= 0.0:
		_greet_cooldown = 1.0
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty() and players[0].visible and players[0].global_position.distance_to(global_position) < 3.0 and randf() < 0.35:
			say(GREET_LINES.pick_random())
			_greet_cooldown = 40.0



## S'enfuit loin d'un point en courant (après s'être fait voler sa voiture, par exemple).
func flee_from(p: Vector3, duration: float) -> void:
	var d := global_position - p
	d.y = 0.0
	flee_dir = d.normalized() if d.length() > 0.1 else Vector3.RIGHT
	flee_time = duration
	chat_time = 0.0
	wait = 0.0
	model.set_talking(false)
