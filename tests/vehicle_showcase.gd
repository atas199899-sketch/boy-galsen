extends SceneTree
## Capture de présentation des véhicules : godot --path . --script res://tests/vehicle_showcase.gd -- --out=chemin.png
const Vehicles = preload("res://scripts/world/vehicles.gd")
var frames := 0
var out := "user://vehicules.png"

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	var root3d := Node3D.new()
	root.add_child(root3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("bcd3e6")
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = true
	root3d.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("8a7a60")
	ground.material_override = gm
	root3d.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var z := -7.5
	for k in ["ndiaga", "car_rapide", "taxi", "car"]:
		var v := Vehicles.make(k, rng)
		v.position = Vector3(0, 0, z)
		root3d.add_child(v)
		z += 4.6
	var cam := Camera3D.new()
	cam.transform = Transform3D(Basis(), Vector3(11.0, 3.0, 9.0)).looking_at(Vector3(0.0, 1.0, -1.5))
	root3d.add_child(cam)
	cam.fov = 55

func _process(_d: float) -> bool:
	frames += 1
	if frames == 20:
		root.get_texture().get_image().save_png(out)
		return true
	return false
