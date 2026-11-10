extends Node3D
## Gère les personnages à qui parler et les missions décrites dans data/missions.json.
##
## Types d'étapes :
##   goto : aller à un lieu de la ville (boulangerie, pharmacie, marché…)
##   talk : parler à un personnage (identifiant d'un PNJ)
## Une mission peut exiger d'autres missions terminées avant ("requires").

const Npc = preload("res://scripts/characters/npc.gd")
const DATA_PATH := "res://data/missions.json"
const ARRIVE_DIST := 3.2

var city = null
var player = null
var hud = null
var npcs := {}           # id -> noeud PNJ
var npc_data := {}
var missions: Array = []
var active = null        # mission en cours (Dictionary)
var step := 0
var beacon: MeshInstance3D


func setup(p_city, p_player, p_hud) -> void:
	city = p_city
	player = p_player
	hud = p_hud
	var data = load_data()
	missions = data.missions
	for d in data.npcs:
		npc_data[d.id] = d
		_spawn_npc(d)
	_make_beacon()
	_refresh_markers()


static func load_data() -> Dictionary:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	assert(d is Dictionary, "missions.json invalide")
	return d


func _spawn_npc(d: Dictionary) -> void:
	var npc := Npc.new()
	add_child(npc)
	npc.setup(d)
	var near: String = d.get("near", "start")
	var pos: Vector3
	if near == "start":
		pos = city.sidewalk_point_near(city.spawn_point, 6.0, 30.0)
	elif near == "far":
		pos = city.sidewalk_point_near(city.spawn_point, 90.0, 160.0)
	elif city.places.has(near):
		pos = city.places[near] + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
	else:
		pos = city.sidewalk_point_near(city.spawn_point, 10.0, 80.0)
	npc.global_position = pos
	npc.rotation.y = randf() * TAU
	npc.talked.connect(_on_talk)
	npcs[d.id] = npc


func _make_beacon() -> void:
	beacon = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.2
	cm.bottom_radius = 1.2
	cm.height = 60.0
	cm.cap_top = false
	cm.cap_bottom = false
	beacon.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.95, 0.75, 0.2, 0.22)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	beacon.material_override = m
	beacon.visible = false
	add_child(beacon)


# ---------------------------------------------------------------- logique

func available_for(npc_id: String):
	for m in missions:
		if m.giver != npc_id or Game.completed.has(m.id):
			continue
		var ok := true
		for r in m.get("requires", []):
			if not Game.completed.has(r):
				ok = false
		if ok:
			return m
	return null


func _on_talk(npc) -> void:
	var id: String = npc.npc_id
	if active:
		var s: Dictionary = active.steps[step]
		if s.type == "talk" and s.target == id:
			_advance()
			return
		hud.show_dialogue(npc.npc_name, ["Tu as déjà une course en cours : " + s.text.to_lower() + "."])
		return
	var m = available_for(id)
	if m:
		hud.show_dialogue(npc.npc_name, m.intro, func(): _start(m))
	else:
		hud.show_dialogue(npc.npc_name, [npc.idle_lines.pick_random()])


func _start(m: Dictionary) -> void:
	active = m
	step = 0
	hud.toast("Nouvelle mission\n" + m.title)
	_refresh_markers()
	_update_objective()


func _advance() -> void:
	var s: Dictionary = active.steps[step]
	var say: Array = s.get("say", [])
	step += 1
	if step >= active.steps.size():
		var m: Dictionary = active
		var giver_name: String = npc_data[m.giver].name
		var lines: Array = say.duplicate()
		lines.append_array(m.get("outro", []))
		active = null
		Game.add_money(int(m.reward))
		Game.complete_mission(m.id)
		hud.show_dialogue(giver_name, lines, func(): hud.toast("Mission réussie !\n+" + Game.format_money(int(m.reward))))
		_refresh_markers()
		_update_objective()
		return
	if not say.is_empty():
		hud.show_dialogue("", say)
	_update_objective()


func _target_pos():
	if active == null:
		return null
	var s: Dictionary = active.steps[step]
	if s.type == "goto":
		return city.places.get(s.target)
	if npcs.has(s.target):
		return npcs[s.target].global_position
	return null


func _update_objective() -> void:
	if active == null:
		hud.set_objective("")
		beacon.visible = false
		return
	hud.set_objective(active.title + " — " + active.steps[step].text)


func _refresh_markers() -> void:
	for id in npcs:
		npcs[id].set_has_mission(active == null and available_for(id) != null)


func _process(_delta: float) -> void:
	var t = _target_pos()
	beacon.visible = t != null
	if t == null:
		hud.set_distance(-1.0)
		return
	beacon.global_position = t + Vector3(0, 30.0, 0)
	var d: float = player.global_position.distance_to(t)
	hud.set_distance(d)
	hud.set_compass_target(t)
	var s: Dictionary = active.steps[step]
	if s.type == "goto" and d < ARRIVE_DIST and not hud.is_dialogue_open():
		_advance()
