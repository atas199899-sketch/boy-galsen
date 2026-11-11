extends CanvasLayer
## Interface : argent, heure, objectif + distance, boussole, invite d'interaction,
## boîte de dialogue, messages.

var _money: Label
var _clock: Label
var _objective: Label
var _distance: Label
var _prompt: Label
var _speed: Label
var _toast: Label
var _toast_time := 0.0
var _dialog: PanelContainer
var _dialog_name: Label
var _dialog_text: Label
var _lines: Array = []
var _line := 0
var _on_done: Callable
var _compass: Control
var _compass_target = null
var camera: Camera3D
var player: Node3D


func _ready() -> void:
	var top := _panel(Control.PRESET_TOP_LEFT, Vector2(16, 16))
	var v := VBoxContainer.new()
	top.add_child(v)
	_money = _text(26, Color("46c37b"))
	_clock = _text(16, Color(1, 1, 1, 0.8))
	v.add_child(_money)
	v.add_child(_clock)

	var obj_box := VBoxContainer.new()
	obj_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	obj_box.position.y = 16
	obj_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(obj_box)
	_objective = _text(20, Color("f0b93a"))
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance = _text(16, Color.WHITE)
	_distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	obj_box.add_child(_objective)
	obj_box.add_child(_distance)

	_compass = Control.new()
	_compass.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_compass.position = Vector2(-30, 78)
	_compass.custom_minimum_size = Vector2(60, 60)
	_compass.size = Vector2(60, 60)
	_compass.draw.connect(_draw_compass)
	add_child(_compass)

	_prompt = _text(20, Color.WHITE)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y -= 60
	add_child(_prompt)

	_speed = _text(40, Color.WHITE)
	_speed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_speed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_speed.position += Vector2(-30, -30)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed.visible = false
	add_child(_speed)

	_toast = _text(34, Color.WHITE)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BOTH
	_toast.position.y -= 140
	_toast.modulate.a = 0.0
	add_child(_toast)

	_dialog = PanelContainer.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_dialog.offset_left = 80
	_dialog.offset_right = -80
	_dialog.offset_top = -170
	_dialog.offset_bottom = -24
	_dialog.add_theme_stylebox_override("panel", _style(Color(0.05, 0.07, 0.09, 0.88)))
	var dv := VBoxContainer.new()
	_dialog.add_child(dv)
	_dialog_name = _text(20, Color("f0b93a"))
	_dialog_text = _text(19, Color.WHITE)
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hint := _text(13, Color(1, 1, 1, 0.55))
	hint.text = "E / clic : continuer"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dv.add_child(_dialog_name)
	dv.add_child(_dialog_text)
	dv.add_child(hint)
	_dialog.visible = false
	add_child(_dialog)

	Game.money_changed.connect(func(_v): _refresh_money())
	_refresh_money()


func _panel(preset: int, pos: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(preset)
	p.position = pos
	p.add_theme_stylebox_override("panel", _style(Color(0.05, 0.07, 0.09, 0.7)))
	add_child(p)
	return p


func _style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _text(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return l


func _refresh_money() -> void:
	_money.text = Game.format_money(Game.money)


func _process(delta: float) -> void:
	_clock.text = Game.clock_text()
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time * 2.0, 0.0, 1.0)
	_compass.queue_redraw()


# ---------------------------------------------------------------- API

func set_objective(t: String) -> void:
	_objective.text = t
	if t == "":
		_distance.text = ""
		_compass_target = null


func set_distance(d: float) -> void:
	_distance.text = "" if d < 0.0 else "%d m" % int(d)


func set_compass_target(p: Vector3) -> void:
	_compass_target = p


## Compteur de vitesse (km/h) ; -1 pour le cacher.
func set_speed(kmh: int) -> void:
	_speed.visible = kmh >= 0
	if kmh >= 0:
		_speed.text = "%d km/h" % kmh


func set_prompt(t: String) -> void:
	_prompt.text = t


func toast(t: String) -> void:
	_toast.text = t
	_toast_time = 3.0


func is_dialogue_open() -> bool:
	return _dialog.visible


func show_dialogue(speaker: String, lines: Array, on_done: Callable = Callable()) -> void:
	if lines.is_empty():
		if on_done.is_valid():
			on_done.call()
		return
	_lines = lines
	_line = 0
	_on_done = on_done
	_dialog_name.text = speaker
	_dialog_name.visible = speaker != ""
	_dialog_text.text = str(_lines[0])
	_dialog.visible = true


func advance_dialogue() -> void:
	_line += 1
	if _line < _lines.size():
		_dialog_text.text = str(_lines[_line])
		return
	_dialog.visible = false
	var cb := _on_done
	_on_done = Callable()
	if cb.is_valid():
		cb.call()


func _draw_compass() -> void:
	if _compass_target == null or camera == null or player == null:
		return
	var to: Vector3 = _compass_target - player.global_position
	var fwd := -camera.global_transform.basis.z
	var ang := atan2(to.x, -to.z) - atan2(fwd.x, -fwd.z)
	var c := Vector2(30, 30)
	_compass.draw_circle(c, 26, Color(0, 0, 0, 0.45))
	var tip := c + Vector2(sin(ang), -cos(ang)) * 22
	var l := c + Vector2(sin(ang - 2.5), -cos(ang - 2.5)) * 12
	var r := c + Vector2(sin(ang + 2.5), -cos(ang + 2.5)) * 12
	_compass.draw_colored_polygon(PackedVector2Array([tip, l, c, r]), Color("f0b93a"))
