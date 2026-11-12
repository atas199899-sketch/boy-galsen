extends Node3D
## Point d'entrée : construit le ciel et la lumière, la ville, le joueur, les passants,
## l'interface et les missions, puis fait tourner le cycle jour / nuit.

const City = preload("res://scripts/world/city_generator.gd")
const OsmCity = preload("res://scripts/world/osm_city.gd")
const Traffic = preload("res://scripts/vehicles/traffic.gd")
const Player = preload("res://scripts/characters/player.gd")
const Pedestrian = preload("res://scripts/characters/pedestrian.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const MissionManager = preload("res://scripts/missions/mission_manager.gd")
const Humanoid = preload("res://scripts/characters/humanoid.gd")

const PEDESTRIANS := 45

var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var city
var player
var hud
var missions


func _ready() -> void:
	_build_environment()
	# vraie ville (OpenStreetMap) si les données sont présentes, sinon quartier généré
	city = OsmCity.new() if OsmCity.available() else City.new()
	city.name = "Ville"
	add_child(city)
	city.build()

	hud = Hud.new()
	add_child(hud)

	player = Player.new()
	player.name = "Joueur"
	add_child(player)
	player.global_position = city.spawn_point
	if "focus" in city:
		city.focus = player
	player.hud = hud
	hud.player = player
	hud.camera = player.camera

	var count := PEDESTRIANS / 2 if OS.has_feature("web") else PEDESTRIANS   # navigateur : moins de passants
	for k in count:
		var p := Pedestrian.new()
		add_child(p)
		var female := randf() < 0.5
		var start_node: int = city.random_sidewalk_node_near(city.spawn_point, 260.0) if city.has_method("random_sidewalk_node_near") else city.random_sidewalk_node()
		p.setup(city, start_node, {
			"female": female,
			"top": Humanoid.CLOTH.pick_random(),
			"bottom": [Color("26313d"), Color("1d1d1d"), Color("3b4a5c"), Color("5b4a3a"), Color("c9b28a")].pick_random(),
			"wax": randf() < 0.3,
			"pattern_color": Humanoid.CLOTH.pick_random(),
			"wrap_color": Humanoid.CLOTH.pick_random(),
			"long_dress": female and randf() < 0.7 or (not female and randf() < 0.25),
			"head_wrap": female and randf() < 0.6,
			"long_sleeves": randf() < 0.4,
			"height": randf_range(1.58, 1.72) if female else randf_range(1.68, 1.92),
		})

	if "drive_nodes" in city and not city.drive_nodes.is_empty():
		var traffic := Traffic.new()
		traffic.name = "Circulation"
		add_child(traffic)
		traffic.setup(city, player)

	_make_street_chats()

	missions = MissionManager.new()
	add_child(missions)
	missions.setup(city, player, hud)
	hud.toast("Boy Galsen\nBienvenue à Dakar" + ("\n\nClique dans le jeu pour commencer" if OS.has_feature("web") else ""))
	_parse_dev_args()


# ---------------------------------------------------------------- outils de développement
# godot --path . -- --time=18.5 --capture=res://capture.png --yaw=0.6
# lance le jeu à une heure donnée, enregistre une capture d'écran puis quitte.
# godot --headless --path . -- --selftest   joue la première mission automatiquement.

var _capture_path := ""
var _capture_frames := 0
var _capture_at := 150


func _parse_dev_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			Game.time_of_day = float(a.get_slice("=", 1))
		elif a.begins_with("--capture="):
			_capture_path = a.get_slice("=", 1)
		elif a.begins_with("--capframe="):
			_capture_at = int(a.get_slice("=", 1))
		elif a.begins_with("--yaw="):
			player.yaw = float(a.get_slice("=", 1))
		elif a == "--debughair":
			await get_tree().create_timer(3.0).timeout
			for att in find_children("*", "BoneAttachment3D", true, false):
				var owner_body: Node3D = att.get_parent().get_parent().get_parent().get_parent().get_parent()
				var hair_y := -1.0
				for mi in att.find_children("*", "MeshInstance3D", true, false):
					hair_y = maxf(hair_y, mi.global_transform * mi.get_aabb().get_center().y if false else (mi.global_transform * mi.get_aabb().get_center()).y)
				print("ATT bone=", att.bone_name, " idx=", att.bone_idx, " corps_y=%.2f att_y=%.2f meche_y=%.2f" % [owner_body.global_position.y, att.global_position.y, hair_y], " ", owner_body.name)
			get_tree().quit()
		elif a.begins_with("--nearcar="):
			# se place près du n-ième véhicule garé (captures d'écran)
			var kind := a.get_slice("=", 1)
			for v in city._park_vehicles:
				if v[2] == kind and v[0].distance_to(city.spawn_point) < 900.0:
					player.global_position = v[0] + Vector3(cos(v[1]) * 5.0, 0.3, -sin(v[1]) * 5.0) + Vector3(sin(v[1]), 0, cos(v[1])) * 4.0
					var to: Vector3 = v[0] - player.global_position
					player.yaw = atan2(-to.x, -to.z)
					break
		elif a == "--carshow":
			# aligne des véhicules avec conducteur devant le joueur (captures d'écran)
			var Car = load("res://scripts/vehicles/car.gd")
			var V = load("res://scripts/world/vehicles.gd")
			var rng := RandomNumberGenerator.new()
			var kinds := ["clando", "taxi_sn", "car_rapide_3d", "p405"]
			var f := Vector3(sin(player.yaw), 0, cos(player.yaw)) * -1.0
			var side := Vector3(f.z, 0, -f.x)
			for i in kinds.size():
				var c = Car.new()
				c.setup(kinds[i], V.make(kinds[i], rng), V.size_of(kinds[i]))
				add_child(c)
				c.global_position = player.global_position + f * (8.0 + i * 3.2) + side * 0.0 + Vector3(0, 0.3, 0)
				c.rotation.y = atan2(-side.z, side.x)
				c.add_driver({"top": Color("2c3e50"), "hair": "Hair_Buzzed"})
		elif a == "--nossao":
			env.ssao_enabled = false
		elif a == "--noglow":
			env.glow_enabled = false
		elif a == "--nofog":
			env.fog_enabled = false
		elif a == "--crowd":
			# rassemble quelques passants devant la caméra (captures d'écran)
			var k := 0
			for n in get_children():
				if n is Pedestrian and k < 8:
					n.global_position = player.global_position + Vector3(-3.0 + (k % 4) * 2.0, 0.3, -4.0 - (k / 4) * 3.0)
					n.wait = 30.0
					k += 1
		elif a.begins_with("--zoom="):
			player.spring.spring_length = float(a.get_slice("=", 1))
		elif a.begins_with("--pitch="):
			player.pitch = float(a.get_slice("=", 1))
		elif a == "--drivetest":
			_drivetest.call_deferred()
		elif a == "--selftest":
			_selftest.call_deferred()
		elif a.begins_with("--goto="):
			var key := a.get_slice("=", 1)
			if city.places.has(key):
				player.global_position = city.places[key]


func _physics_process(_delta: float) -> void:
	if _capture_path == "":
		return
	_capture_frames += 1
	if _capture_frames == _capture_at:
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(_capture_path))
		print("Capture : ", _capture_path)
		get_tree().quit()


## Petits groupes de passants qui discutent sur les trottoirs autour du point de départ.
func _make_street_chats() -> void:
	var peds: Array = get_tree().get_nodes_in_group("pedestrian")
	peds.shuffle()
	var k := 0
	var taken: Array = []
	for g in 7:
		var size := 2 if randf() < 0.6 else 3
		if k + size > peds.size():
			break
		var center: Vector3 = city.sidewalk_point_near(city.spawn_point, 12.0, 160.0, taken, 12.0) if city.has_method("random_sidewalk_node_near") else city.sidewalk_point_near(city.spawn_point, 12.0, 160.0)
		taken.append(center)
		for m in size:
			var p = peds[k]
			k += 1
			var a := TAU * m / size + randf() * 0.3
			p.global_position = center + Vector3(cos(a), 0.0, sin(a)) * 0.75 + Vector3(0, 0.2, 0)
			p.start_chat(center, randf_range(60.0, 240.0))


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_color = Color("d8c7a8")
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 0.9
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.0   # >0 fait apparaître des silhouettes fantômes dans le ciel (Forward+)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.light_angular_distance = 0.5
	add_child(sun)


func _process(_delta: float) -> void:
	if player and player.global_position.y < -4.0:
		player.global_position = city.spawn_point
		player.velocity = Vector3.ZERO
		hud.toast("Plouf ! Retour à la place")
	_update_daylight(Game.time_of_day)


## Soleil de Dakar : lever vers 7 h, coucher vers 19 h.
func _update_daylight(t: float) -> void:
	var elev := (t - 7.0) / 12.0 * PI          # 0 au lever, PI au coucher
	var height := sin(elev)
	var day := clampf(height * 3.0 + 0.3, 0.0, 1.0)
	var night := 1.0 - day
	var dusk := clampf(1.0 - absf(height - 0.08) / 0.3, 0.0, 1.0)
	sun.rotation = Vector3(-clampf(elev, 0.15, PI - 0.15), deg_to_rad(-35.0), 0.0)
	sun.light_energy = lerpf(0.22, 1.6, day)   # la nuit : clair de lune
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.62, 0.38), dusk).lerp(Color(0.55, 0.65, 1.0), night)
	sky_mat.sky_top_color = Color("2f6db5").lerp(Color("0b1630"), night)
	sky_mat.sky_horizon_color = Color("a9cbe6").lerp(Color("f29a5c"), dusk * 0.8).lerp(Color("1c2a44"), night)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color("5a4c3a").lerp(Color("050505"), night)
	sky_mat.sky_energy_multiplier = lerpf(0.45, 1.0, day)
	env.ambient_light_energy = lerpf(0.55, 1.0, day)
	env.ambient_light_color = Color("d8c7a8").lerp(Color("3a4a6e"), night)
	env.fog_light_color = sky_mat.sky_horizon_color
	city.set_night(night)


func _selftest() -> void:
	var saved_money := Game.money
	var saved_done := Game.completed.duplicate()
	Game.completed.clear()
	var start_money := Game.money
	await get_tree().physics_frame
	var adja = missions.npcs["adja_fatou"]
	adja.interact(player)
	while hud.is_dialogue_open():
		hud.advance_dialogue()
	var started: bool = missions.active != null
	player.global_position = city.places["boulangerie"]
	for i in 10:
		await get_tree().physics_frame
	var reached: bool = missions.step == 1
	while hud.is_dialogue_open():
		hud.advance_dialogue()
	player.global_position = adja.global_position + Vector3(1, 0, 0)
	adja.interact(player)
	while hud.is_dialogue_open():
		hud.advance_dialogue()
	var ok: bool = started and reached and Game.completed.has("pain_du_matin") and Game.money == start_money + 500
	print("SELFTEST démarrée=%s boulangerie=%s terminée=%s argent=%d → %s" % [started, reached, Game.completed.has("pain_du_matin"), Game.money - start_money, "OK" if ok else "ÉCHEC"])
	Game.money = saved_money
	Game.completed.assign(saved_done)
	Game.save_game()
	get_tree().quit(0 if ok else 1)


## Test de conduite : monte dans le véhicule le plus proche, accélère, vérifie la circulation.
func _drivetest() -> void:
	await get_tree().create_timer(2.0).timeout
	var best = null
	var bd := 1e9
	var all_v := get_tree().get_nodes_in_group("vehicle")
	for v in all_v:
		if v.ai != null or v.kind == "jakarta":
			continue
		var d: float = v.global_position.distance_to(player.global_position)
		if d >= bd:
			continue
		# il faut de la place devant (pas de véhicule garé juste devant)
		var f: Vector3 = v.forward()
		var clear := true
		for o in all_v:
			if o == v:
				continue
			var rel: Vector3 = o.global_position - v.global_position
			var ahead := rel.x * f.x + rel.z * f.z
			if ahead > 0.0 and ahead < 25.0 and absf(rel.x * f.z - rel.z * f.x) < 2.5:
				clear = false
				break
		if clear:
			bd = d
			best = v
	var traffic = get_node_or_null("Circulation")
	var ai_start := {}
	if traffic:
		for c in traffic.cars:
			ai_start[c] = c.global_position
	player.global_position = best.global_position + Vector3(0, 1, 0)
	player.enter_vehicle(best)
	var start: Vector3 = best.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(4.0).timeout
	var top_speed: float = best.speed
	Input.action_release("move_forward")
	Input.action_press("move_left")
	Input.action_press("move_forward")
	await get_tree().create_timer(1.5).timeout
	Input.action_release("move_left")
	Input.action_release("move_forward")
	var moved: float = best.global_position.distance_to(start)
	player.exit_vehicle()
	var ai_moving := 0
	if traffic:
		for c in traffic.cars:
			if is_instance_valid(c) and ai_start.has(c) and c.global_position.distance_to(ai_start[c]) > 8.0:
				ai_moving += 1
	var n_ai: int = traffic.cars.size() if traffic else 0
	# vol d'une voiture de la circulation
	var jacked := false
	var fled := false
	if traffic and not traffic.cars.is_empty():
		var target = traffic.cars[0]
		player.global_position = target.global_position - target.global_transform.basis.z * (target.size.z * 0.5 + 1.0) + Vector3(0, 0.5, 0)
		target.interact(player)
		await get_tree().create_timer(7.0).timeout
		jacked = player.vehicle == target and target.ai == null
		for p in get_tree().get_nodes_in_group("pedestrian"):
			if p.flee_time > 0.0:
				fled = true
		player.exit_vehicle()
	var ok: bool = top_speed > 5.0 and moved > 10.0 and ai_moving >= 3 and jacked and fled
	print("DRIVETEST véhicule=%s vitesse_max=%.1f m/s distance=%.1f m circulation=%d dont en mouvement=%d vol=%s conducteur_enfui=%s → %s" % [best.kind, top_speed, moved, n_ai, ai_moving, jacked, fled, "OK" if ok else "ÉCHEC"])
	get_tree().quit(0 if ok else 1)
