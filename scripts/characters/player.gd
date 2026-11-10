extends CharacterBody3D
## Le joueur : marche / course / saut à la troisième personne, caméra à l'épaule,
## interaction avec les personnages proches (touche E).

const Humanoid = preload("res://scripts/characters/humanoid.gd")
const PLAYER_MODEL := "res://assets/characters/player.glb"

const WALK_SPEED := 1.8
const RUN_SPEED := 5.0
const JUMP_VELOCITY := 4.0
const ACCEL := 9.0
const INTERACT_RANGE := 2.4

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var model
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var yaw := 0.0
var pitch := -0.2
var mouse_sensitivity := 0.0025
var stick_sensitivity := 2.6
var controls_locked := false
var hud = null
var focus: Node = null  # personnage avec qui on peut interagir


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 2
	floor_snap_length = 0.3
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	col.shape = cap
	col.position.y = 0.875
	add_child(col)

	model = Humanoid.new()
	add_child(model)
	model.build({"model": PLAYER_MODEL, "top": Color("f0b93a"), "bottom": Color("2b3a55"), "shoes": Color("e8e8e8"), "hair": "Hair_Buzzed", "beard": false, "height": 1.78})

	cam_pivot = Node3D.new()
	cam_pivot.position.y = 1.6
	add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 3.0
	spring.margin = 0.2
	spring.collision_mask = 1
	var ss := SphereShape3D.new()
	ss.radius = 0.25
	spring.shape = ss
	spring.position.x = 0.45
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.08
	camera.far = 900.0
	spring.add_child(camera)
	camera.make_current()
	_capture_mouse(true)


func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, -1.2, 0.55)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse(true)
		if hud and hud.is_dialogue_open():
			hud.advance_dialogue()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and hud and hud.is_dialogue_open():
		hud.advance_dialogue()
	elif event.is_action_pressed("pause"):
		_capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("interact"):
		if hud and hud.is_dialogue_open():
			hud.advance_dialogue()
		elif focus and focus.has_method("interact"):
			focus.interact(self)


func _physics_process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	yaw -= look.x * stick_sensitivity * delta
	pitch = clampf(pitch - look.y * stick_sensitivity * delta, -1.2, 0.55)
	cam_pivot.rotation = Vector3(pitch, yaw, 0.0)

	var locked: bool = controls_locked or (hud != null and hud.is_dialogue_open())
	var input := Vector2.ZERO if locked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	var running := Input.is_action_pressed("sprint")
	var target_speed := (RUN_SPEED if running else WALK_SPEED) * minf(1.0, input.length())
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	hv = hv.lerp(dir.normalized() * target_speed if dir.length() > 0.05 else Vector3.ZERO, clampf(ACCEL * delta, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif not locked and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
	move_and_slide()

	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.2:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-velocity.x, -velocity.z), clampf(10.0 * delta, 0.0, 1.0))
	model.animate(speed, delta, not is_on_floor() and absf(velocity.y) > 1.5)
	_update_focus()


func _update_focus() -> void:
	var best: Node = null
	var best_d := INTERACT_RANGE
	for n in get_tree().get_nodes_in_group("interactable"):
		var d: float = global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	if best != focus:
		focus = best
	if hud:
		hud.set_prompt(focus.get_prompt() if focus and not hud.is_dialogue_open() else "")
