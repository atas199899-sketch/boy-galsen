extends StaticBody3D
## Personnage fixe avec qui on peut parler (donneur de missions, commerçant…).

const Humanoid = preload("res://scripts/characters/humanoid.gd")

signal talked(npc)

var npc_id := ""
var npc_name := ""
var idle_lines: Array = []
var model
var _marker: Label3D
var _time := 0.0


func setup(data: Dictionary) -> void:
	npc_id = data.get("id", "")
	npc_name = data.get("name", "")
	idle_lines = data.get("idle", ["Salam aleykoum !"])
	add_to_group("interactable")
	add_to_group("npc")
	collision_layer = 2
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	var look: Dictionary = data.get("look", {})
	var parsed := {}
	for k in look:
		var v = look[k]
		parsed[k] = Color(v) if v is String and v.begins_with("#") else v
	model = Humanoid.new()
	add_child(model)
	model.build(parsed)

	var name_label := Label3D.new()
	name_label.text = npc_name
	name_label.font_size = 40
	name_label.pixel_size = 0.004
	name_label.outline_size = 10
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position.y = 2.05
	name_label.no_depth_test = false
	add_child(name_label)

	_marker = Label3D.new()
	_marker.text = "!"
	_marker.font_size = 110
	_marker.pixel_size = 0.005
	_marker.outline_size = 16
	_marker.modulate = Color("f0b93a")
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.position.y = 2.45
	_marker.visible = false
	add_child(_marker)


func set_has_mission(v: bool) -> void:
	_marker.visible = v


func get_prompt() -> String:
	return "[E] Parler à " + npc_name


func interact(player) -> void:
	var to: Vector3 = player.global_position - global_position
	model.rotation.y = atan2(-to.x, -to.z)
	talked.emit(self)


func _process(delta: float) -> void:
	_time += delta
	if _marker.visible:
		_marker.position.y = 2.45 + sin(_time * 3.0) * 0.08
	model.animate(0.0, delta)
