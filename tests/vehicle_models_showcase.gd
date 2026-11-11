extends SceneTree
## Aligne les modèles de véhicules importés pour vérifier taille et orientation.
var frames := 0
var out := ""
func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	var r := Node3D.new()
	root.add_child(r)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("bcd3e6")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; r.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0); sun.shadow_enabled = true; r.add_child(sun)
	var Vehicles = load("res://scripts/world/vehicles.gd")
	var rng := RandomNumberGenerator.new()
	var kinds := ["car_rapide_3d", "taxi_sn", "clando", "p405", "sedan_3d", "wagon_3d", "jakarta", "jetta", "crafter", "ndiaga"]
	var z := -11.0
	for k in kinds:
		var v: Node3D = Vehicles.make(k, rng)
		v.position = Vector3(0, 0, z)
		r.add_child(v)
		var l := Label3D.new(); l.text = k; l.position = Vector3(-3.5, 1.0, z); l.pixel_size = 0.008; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED; r.add_child(l)
		z += 2.6
	var g := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(80, 80); g.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color("8a7a60"); g.material_override = gm; r.add_child(g)
	var cam := Camera3D.new()
	cam.transform = Transform3D(Basis(), Vector3(16, 9, 10)).looking_at(Vector3(0, 0.8, 0.5))
	r.add_child(cam)
func _process(_d: float) -> bool:
	frames += 1
	if frames == 15:
		root.get_texture().get_image().save_png(out)
		return true
	return false
