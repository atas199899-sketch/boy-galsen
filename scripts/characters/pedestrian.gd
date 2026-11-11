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


func setup(p_city, start_node: int, look: Dictionary) -> void:
	city = p_city
	node_id = start_node
	collision_layer = 2
	collision_mask = 1 | 2
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


func _physics_process(delta: float) -> void:
	if city == null:
		return
	var to := target - global_position
	to.y = 0.0
	var hv := Vector3.ZERO
	if wait > 0.0:
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
