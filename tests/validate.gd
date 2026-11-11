extends SceneTree
## Vérifie la cohérence des données : chaque mission référence des PNJ et des lieux existants.
## Lancer : godot --headless --script res://tests/validate.gd

const City = preload("res://scripts/world/city_generator.gd")
const OsmCity = preload("res://scripts/world/osm_city.gd")


func _init() -> void:
	var errors: Array[String] = []
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))
	var city = OsmCity.new() if OsmCity.available() else City.new()
	root.add_child(city)
	city.build()
	var npc_ids := {}
	for n in data.npcs:
		npc_ids[n.id] = true
	var ids := {}
	for m in data.missions:
		if ids.has(m.id):
			errors.append("mission en double : " + m.id)
		ids[m.id] = true
		if not npc_ids.has(m.giver):
			errors.append(m.id + " : PNJ donneur inconnu " + m.giver)
		for s in m.steps:
			if s.type == "goto" and not city.places.has(s.target):
				errors.append(m.id + " : lieu inconnu " + s.target)
			elif s.type == "talk" and not npc_ids.has(s.target):
				errors.append(m.id + " : PNJ inconnu " + s.target)
			elif s.type != "goto" and s.type != "talk":
				errors.append(m.id + " : type d'étape inconnu " + s.type)
	for m in data.missions:
		for r in m.get("requires", []):
			if not ids.has(r):
				errors.append(m.id + " : prérequis inconnu " + r)
	if city.sidewalk_nodes.size() < 10:
		errors.append("graphe des trottoirs trop petit")
	for k in city.sidewalk_links.size():
		if city.sidewalk_links[k].is_empty():
			errors.append("noeud de trottoir isolé %d" % k)
	print("Lieux : ", city.places.keys())
	print("Missions : %d, PNJ : %d, noeuds de trottoir : %d" % [data.missions.size(), data.npcs.size(), city.sidewalk_nodes.size()])
	if errors.is_empty():
		print("OK : données valides")
		quit(0)
	else:
		for e in errors:
			printerr("ERREUR : " + e)
		quit(1)
