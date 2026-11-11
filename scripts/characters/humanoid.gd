extends Node3D
## Corps humain provisoire construit en code, animé procéduralement (marche, course).
##
## Il sert en attendant de vrais modèles 3D : si un fichier .glb existe dans
## res://assets/characters/ (voir docs/ASSETS.md), le personnage l'utilise à la place.
## Le personnage regarde vers -Z (convention Godot).

var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _body: Node3D
var _phase := 0.0
var _amp := 0.0
var _glb_anim: AnimationPlayer = null
var real = null   # personnage réaliste (real_character.gd) s'il est disponible

const RealCharacter = preload("res://scripts/characters/real_character.gd")

const SKIN_TONES := [Color("3b2417"), Color("4a2c1b"), Color("5c3822"), Color("6e4529"), Color("7d5134"), Color("8d5f3c")]
const CLOTH := [Color("1f5fae"), Color("c0392b"), Color("f1c40f"), Color("2e8b57"), Color("8e44ad"), Color("e67e22"),
	Color("ecf0f1"), Color("16a085"), Color("d35400"), Color("2c3e50"), Color("e84393"), Color("0f7a5a")]


## look : female, skin, top, bottom, shoes (Color), long_dress (robe / boubou), head_wrap (foulard),
## wrap_color, wax (motif), hair, beard, height (m), realistic (false = corps simple).
func build(look: Dictionary) -> void:
	var glb_path: String = look.get("model", "")
	if glb_path != "" and ResourceLoader.exists(glb_path):
		_use_glb(glb_path)
		return
	if look.get("realistic", true) and RealCharacter.assets_available():
		var l := look.duplicate()
		if not l.has("style"):
			if l.get("female", false):
				l["style"] = "dress" if l.get("long_dress", false) else "casual"
			else:
				l["style"] = "boubou" if l.get("long_dress", false) else "casual"
		real = RealCharacter.new()
		add_child(real)
		real.build(l)
		return
	var skin: Color = look.get("skin", SKIN_TONES.pick_random())
	var top: Color = look.get("top", CLOTH.pick_random())
	var bottom: Color = look.get("bottom", Color("26313d"))
	var h: float = look.get("height", 1.75)
	scale = Vector3.ONE * (h / 1.75)
	var skin_m := _mat(skin, 0.55)
	var top_m := _mat(top, 0.85)
	var bottom_m := _mat(bottom, 0.9)
	var shoe_m := _mat(Color("1a1a1a"), 0.6)

	_body = Node3D.new()
	add_child(_body)
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.1 * side, 0.92, 0)
		_body.add_child(hip)
		var leg := _capsule(0.075, 0.88, bottom_m)
		leg.position.y = -0.44
		hip.add_child(leg)
		var shoe := _box(Vector3(0.11, 0.07, 0.25), shoe_m)
		shoe.position = Vector3(0, -0.88, -0.05)
		hip.add_child(shoe)
		_legs.append(hip)

		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.24 * side, 1.46, 0)
		_body.add_child(shoulder)
		var arm := _capsule(0.055, 0.6, top_m if look.get("long_sleeves", false) else skin_m)
		arm.position.y = -0.29
		shoulder.add_child(arm)
		var hand := _sphere(0.055, skin_m)
		hand.position.y = -0.62
		shoulder.add_child(hand)
		_arms.append(shoulder)

	var torso := _capsule(0.17, 0.66, top_m)
	torso.position.y = 1.22
	torso.scale = Vector3(1.3, 1.0, 0.8)
	_body.add_child(torso)
	if look.get("long_dress", false):
		var dress := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 0.33
		cm.height = 0.85
		dress.mesh = cm
		dress.material_override = top_m
		dress.position.y = 0.6
		_body.add_child(dress)
	var neck := _capsule(0.05, 0.14, skin_m)
	neck.position.y = 1.56
	_body.add_child(neck)
	var head := _sphere(0.115, skin_m)
	head.position.y = 1.68
	head.scale = Vector3(0.92, 1.05, 1.0)
	_body.add_child(head)
	if look.get("head_wrap", false):
		var wrap := _sphere(0.13, _mat(look.get("wrap_color", CLOTH.pick_random()), 0.8))
		wrap.position = Vector3(0, 1.76, 0.02)
		wrap.scale = Vector3(1.05, 0.85, 1.1)
		_body.add_child(wrap)
	else:
		var hair := _sphere(0.118, _mat(Color("0d0d0d"), 1.0))
		hair.position = Vector3(0, 1.71, 0.01)
		hair.scale = Vector3(0.95, 0.75, 1.0)
		_body.add_child(hair)


## speed en m/s : anime la marche (bras et jambes opposés) et le léger rebond.
func animate(speed: float, delta: float, airborne := false) -> void:
	if real:
		real.play_state(speed, airborne)
		return
	if _glb_anim:
		var anim := "idle"
		if speed > 3.0:
			anim = "run"
		elif speed > 0.2:
			anim = "walk"
		if _glb_anim.has_animation(anim) and _glb_anim.current_animation != anim:
			_glb_anim.play(anim, 0.2)
		return
	var target := clampf(speed / 5.0, 0.0, 1.0) * 0.55 + (0.3 if speed > 0.15 else 0.0)
	_amp = lerpf(_amp, target, clampf(delta * 8.0, 0.0, 1.0))
	if speed > 0.15:
		_phase += delta * (3.2 + speed * 1.5)
	else:
		_phase = lerpf(_phase, roundf(_phase / PI) * PI, clampf(delta * 6.0, 0.0, 1.0))
	var s := sin(_phase) * _amp
	if _legs.size() == 2:
		_legs[0].rotation.x = s
		_legs[1].rotation.x = -s
		_arms[0].rotation.x = -s * 0.85
		_arms[1].rotation.x = s * 0.85
	if _body:
		_body.position.y = absf(sin(_phase)) * 0.04 * _amp
		_body.rotation.x = -0.12 * clampf((speed - 3.0) / 3.0, 0.0, 1.0)


func _use_glb(path: String) -> void:
	var scene: PackedScene = load(path)
	var inst := scene.instantiate()
	add_child(inst)
	_glb_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _capsule(r: float, h: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = m
	return mi


func _sphere(r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = m
	return mi


func _box(size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	return mi


## Gestes de discussion (animation « Idle_Talking » du personnage réaliste).
func set_talking(v: bool) -> void:
	if real:
		real.talking = v


## Assis au volant.
func set_driving(v: bool) -> void:
	if real:
		real.driving = v
		real.play_state(0.0)


## Animation ponctuelle (voir real_character.gd). Renvoie sa durée.
func play_action(anim_name: String, speed_scale := 1.0) -> float:
	return real.play_action(anim_name, speed_scale) if real else 0.0
