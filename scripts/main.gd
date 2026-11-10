extends Node3D
## Point d'entrée : construit le ciel et la lumière, la ville, le joueur, les passants,
## l'interface et les missions, puis fait tourner le cycle jour / nuit.

const City = preload("res://scripts/world/city_generator.gd")
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
	city = City.new()
	city.name = "Ville"
	add_child(city)
	city.build()

	hud = Hud.new()
	add_child(hud)

	player = Player.new()
	player.name = "Joueur"
	add_child(player)
	player.global_position = city.spawn_point
	player.hud = hud
	hud.player = player
	hud.camera = player.camera

	for k in PEDESTRIANS:
		var p := Pedestrian.new()
		add_child(p)
		var female := randf() < 0.5
		p.setup(city, city.random_sidewalk_node(), {
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

	missions = MissionManager.new()
	add_child(missions)
	missions.setup(city, player, hud)
	hud.toast("Boy Galsen\nBienvenue à Dakar")
	_parse_dev_args()


# ---------------------------------------------------------------- outils de développement
# godot --path . -- --time=18.5 --capture=res://capture.png --yaw=0.6
# lance le jeu à une heure donnée, enregistre une capture d'écran puis quitte.
# godot --headless --path . -- --selftest   joue la première mission automatiquement.

var _capture_path := ""
var _capture_frames := 0


func _parse_dev_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			Game.time_of_day = float(a.get_slice("=", 1))
		elif a.begins_with("--capture="):
			_capture_path = a.get_slice("=", 1)
		elif a.begins_with("--yaw="):
			player.yaw = float(a.get_slice("=", 1))
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
	if _capture_frames == 150:
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(_capture_path))
		print("Capture : ", _capture_path)
		get_tree().quit()


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
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_density = 0.0025
	env.fog_aerial_perspective = 0.4
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
	_update_daylight(Game.time_of_day)


## Soleil de Dakar : lever vers 7 h, coucher vers 19 h.
func _update_daylight(t: float) -> void:
	var elev := (t - 7.0) / 12.0 * PI          # 0 au lever, PI au coucher
	var height := sin(elev)
	var day := clampf(height * 3.0 + 0.3, 0.0, 1.0)
	var night := 1.0 - day
	var dusk := clampf(1.0 - absf(height - 0.08) / 0.3, 0.0, 1.0)
	sun.rotation = Vector3(-clampf(elev, 0.15, PI - 0.15), deg_to_rad(-35.0), 0.0)
	sun.light_energy = lerpf(0.05, 1.6, day)
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.62, 0.38), dusk).lerp(Color(0.55, 0.65, 1.0), night)
	sky_mat.sky_top_color = Color("2f6db5").lerp(Color("04070f"), night)
	sky_mat.sky_horizon_color = Color("a9cbe6").lerp(Color("f29a5c"), dusk * 0.8).lerp(Color("101828"), night)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color("5a4c3a").lerp(Color("050505"), night)
	sky_mat.sky_energy_multiplier = lerpf(0.25, 1.0, day)
	env.ambient_light_energy = lerpf(0.25, 1.0, day)
	env.ambient_light_color = Color("d8c7a8").lerp(Color("1c2436"), night)
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
