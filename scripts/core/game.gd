extends Node
## État global du jeu (autoload « Game ») : argent, progression, sauvegarde, commandes.

signal money_changed(value: int)

const SAVE_PATH := "user://sauvegarde.json"

var money: int = 2000
var completed: Array[String] = []
## Heure du jeu (0–24). Une journée complète dure DAY_LENGTH secondes réelles.
var time_of_day: float = 8.5
const DAY_LENGTH := 1440.0


func _ready() -> void:
	_setup_input()
	load_game()


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta * 24.0 / DAY_LENGTH, 24.0)


func add_money(amount: int) -> void:
	money = maxi(0, money + amount)
	money_changed.emit(money)
	save_game()


func complete_mission(id: String) -> void:
	if not completed.has(id):
		completed.append(id)
	save_game()


static func format_money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3, 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out + " FCFA"


func clock_text() -> String:
	var h := int(time_of_day)
	var m := int((time_of_day - h) * 60.0)
	return "%02d:%02d" % [h, m]


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"money": money, "completed": completed, "time": time_of_day}))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		money = int(d.get("money", money))
		completed.assign(d.get("completed", []))
		time_of_day = float(d.get("time", time_of_day))


func reset_save() -> void:
	money = 2000
	completed.clear()
	save_game()
	money_changed.emit(money)


# --- Commandes -----------------------------------------------------------
# Les touches utilisent la position physique : ZQSD sur AZERTY = WASD sur QWERTY.

func _setup_input() -> void:
	_action("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_action("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_action("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_action("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_action("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_SHOULDER], [])
	_action("jump", [KEY_SPACE], [JOY_BUTTON_A], [])
	_action("interact", [KEY_E], [JOY_BUTTON_X], [])
	_action("pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])


func _action(action: String, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.25)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = b
		InputMap.action_add_event(action, ev)
	for a in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = a[0]
		ev.axis_value = a[1]
		InputMap.action_add_event(action, ev)
