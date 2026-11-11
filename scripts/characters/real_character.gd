extends Node3D
## Personnage réaliste : modèles « Universal Base Characters » (Quaternius, CC0)
## animés avec l'« Universal Animation Library » (Quaternius, CC0).
##
## Les modèles de base n'ont pas de vêtements : on les habille ici par zones du corps
## (haut, bas, chaussures), calculées à partir de la pose de repos et stockées dans les
## couleurs de sommets, puis colorées par un shader qui garde le relief de la peau.
## Le personnage regarde vers -Z (convention Godot).

const MALE := "res://assets/characters/quaternius/Superhero_Male_FullBody.gltf"
const FEMALE := "res://assets/characters/quaternius/Superhero_Female_FullBody.gltf"
const ANIMS := "res://assets/animations/UAL1_Standard.glb"
const HAIR_DIR := "res://assets/characters/quaternius/hair/"
const SHADER := preload("res://scripts/characters/clothing.gdshader")

## Animations utilisées selon l'état.
const ANIM_IDLE := "Idle"
const ANIM_WALK := "Walk"
const ANIM_RUN := "Jog_Fwd"
const ANIM_SPRINT := "Sprint"
const ANIM_TALK := "Idle_Talking"
const ANIM_JUMP := "Jump"
## La texture de peau d'origine est claire : on la teinte pour obtenir des peaux noires
## (du brun chaud au noir ébène).
const SKIN_TONES := [Color(0.36, 0.27, 0.23), Color(0.42, 0.32, 0.27), Color(0.30, 0.22, 0.19),
	Color(0.48, 0.37, 0.31), Color(0.26, 0.19, 0.17), Color(0.55, 0.43, 0.35)]
const HAIR_TINT := Color(0.06, 0.05, 0.045)
const WALK_REF_SPEED := 1.45   # vitesse (m/s) à laquelle l'animation de marche est naturelle
const RUN_REF_SPEED := 3.6

static var _libraries := {}       # une bibliothèque d'animations par morphologie
static var _anim_pelvis_height := 0.0
static var _dressed_cache := {}   # clé -> ArrayMesh habillé (partagé entre personnages)

var anim: AnimationPlayer
var skeleton: Skeleton3D
var talking := false
var _current := ""


static func assets_available() -> bool:
	return ResourceLoader.exists(MALE) and ResourceLoader.exists(ANIMS)


func build(look: Dictionary) -> void:
	var female: bool = look.get("female", false)
	var inst: Node3D = load(FEMALE if female else MALE).instantiate()
	inst.rotation.y = PI   # le modèle regarde vers +Z
	var h: float = look.get("height", 1.65 if female else 1.78)
	inst.scale = Vector3.ONE * (h / 1.82)
	add_child(inst)
	skeleton = inst.find_children("*", "Skeleton3D", true, false)[0]

	anim = AnimationPlayer.new()
	inst.add_child(anim)
	anim.root_node = NodePath("..")
	anim.add_animation_library("", _get_library(skeleton))
	anim.playback_default_blend_time = 0.25

	for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		if mi.get_aabb().size.y > 1.0:   # le corps (pas les yeux ni les sourcils)
			_dress(mi, look, female)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_add_hair(look, female)
	_add_drape(look)
	play_state(0.0)
	anim.seek(randf() * 1.0, true)


## Les animations ont été faites pour un mannequin aux jambes un peu plus courtes :
## on adapte la hauteur du bassin à chaque morphologie pour que les pieds touchent le sol.
func _get_library(sk: Skeleton3D) -> AnimationLibrary:
	var pelvis := sk.find_bone("pelvis")
	var target_h := sk.get_bone_global_rest(pelvis).origin.y if pelvis >= 0 else 0.0
	var key := snappedf(target_h, 0.001)
	if _libraries.has(key):
		return _libraries[key]
	var src: Node = load(ANIMS).instantiate()
	var ap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
	var src_sk: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var src_pelvis := src_sk.find_bone("pelvis")
	var ratio := 1.0
	if src_pelvis >= 0 and target_h > 0.0:
		ratio = target_h / src_sk.get_bone_global_rest(src_pelvis).origin.y
	var lib: AnimationLibrary = ap.get_animation_library("").duplicate(true)
	src.free()
	for n in lib.get_animation_list():
		var a := lib.get_animation(n)
		if n in [ANIM_IDLE, ANIM_WALK, ANIM_RUN, ANIM_SPRINT, ANIM_TALK, "Sitting_Idle", "Crouch_Idle", "Jump"]:
			a.loop_mode = Animation.LOOP_LINEAR
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D and str(a.track_get_path(t)).ends_with(":pelvis"):
				for k in a.track_get_key_count(t):
					a.track_set_key_value(t, k, a.track_get_key_value(t, k) * ratio)
	_libraries[key] = lib
	return lib


## speed : vitesse horizontale en m/s.
func play_state(speed: float, airborne := false) -> void:
	var target := ANIM_IDLE
	var scale := 1.0
	if airborne:
		target = ANIM_JUMP
	elif speed > 4.2:
		target = ANIM_SPRINT
		scale = clampf(speed / 5.5, 0.8, 1.3)
	elif speed > 2.4:
		target = ANIM_RUN
		scale = clampf(speed / RUN_REF_SPEED, 0.7, 1.4)
	elif speed > 0.15:
		target = ANIM_WALK
		scale = clampf(speed / WALK_REF_SPEED, 0.5, 1.5)
	elif talking:
		target = ANIM_TALK
	if target != _current and anim.has_animation(target):
		anim.play(target)
		_current = target
	anim.speed_scale = scale


# ---------------------------------------------------------------- vêtements

func _dress(mi: MeshInstance3D, look: Dictionary, female: bool) -> void:
	var style: String = look.get("style", "casual")
	var key := "%s_%s" % [mi.mesh.resource_path, mi.name]
	var mesh: ArrayMesh = _dressed_cache.get(key)
	if mesh == null:
		mesh = _build_dressed_mesh(mi.mesh)
		_dressed_cache[key] = mesh
	var src_mat: BaseMaterial3D = mi.mesh.surface_get_material(0)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	if src_mat:
		m.set_shader_parameter("skin_tex", src_mat.albedo_texture)
		m.set_shader_parameter("normal_tex", src_mat.normal_texture)
		m.set_shader_parameter("rough_tex", src_mat.roughness_texture)
	var top: Color = look.get("top", Color("f0b93a"))
	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("bottom_color", _drape_color(look) if style == "dress" else look.get("bottom", Color("2b3a55")))
	m.set_shader_parameter("shoe_color", look.get("shoes", Color("1a1a1a")))
	m.set_shader_parameter("skin_tint", look.get("skin_tint", SKIN_TONES.pick_random()))
	m.set_shader_parameter("pattern", 1.0 if look.get("wax", false) else 0.0)
	m.set_shader_parameter("pattern_color", look.get("pattern_color", Color("f1c40f")))
	# coupe du vêtement
	m.set_shader_parameter("top_low", 0.525)   # bas du t-shirt au niveau des hanches
	m.set_shader_parameter("has_bottom", 1.0)
	m.set_shader_parameter("sleeve", 0.84 if style in ["boubou", "dress"] else 0.4)
	m.set_shader_parameter("neck_hole", 0.80 if female else 0.81)
	m.set_shader_parameter("neck_width", 0.15 if female else 0.13)
	mi.mesh = mesh
	mi.set_surface_override_material(0, m)


## Recopie le maillage en stockant dans les couleurs de sommets la position de repos
## (R = hauteur relative 0 → 1, G = écart latéral). Le shader en déduit les zones de
## vêtements pixel par pixel, ce qui donne des ourlets et des cols nets.
static func _build_dressed_mesh(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	var aabb := src.get_aabb()
	var y0 := aabb.position.y
	var hgt := aabb.size.y
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		for i in verts.size():
			var v := verts[i]
			cols[i] = Color((v.y - y0) / hgt, clampf(absf(v.x) / hgt * 2.0, 0.0, 1.0), 0.0, 1.0)
		arrays[Mesh.ARRAY_COLOR] = cols
		for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[c] = null   # données inutilisées, dont le format n'est pas recopié
		var flags: int = src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays, [], {}, flags)
	return out


# ---------------------------------------------------------------- robes et boubous

static func _drape_color(look: Dictionary) -> Color:
	return look.get("skirt", look.get("top", Color("8e44ad")))


## Ajoute un pagne / une robe longue (femmes) ou le bas d'un grand boubou (hommes) :
## un tissu évasé accroché au bassin, qui suit les mouvements du corps.
func _add_drape(look: Dictionary) -> void:
	var style: String = look.get("style", "casual")
	if style != "dress" and style != "boubou":
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _drape_color(look)
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if look.get("wax", false):
		mat.albedo_texture = _wax_texture(_drape_color(look), look.get("pattern_color", Color("f1c40f")))
		mat.albedo_color = Color.WHITE
		mat.uv1_scale = Vector3(6, 3, 1)
	if style == "dress":
		# pagne / robe longue : du bassin aux chevilles
		var waist := 0.535 * 1.82
		_drape_cone("pelvis", 0.19, 0.3, 0.12, waist, 1.0, mat)
	else:
		# grand boubou : tombe des épaules jusqu'aux mollets, ample, couvre les bras
		var shoulders := 0.8 * 1.82
		_drape_cone("spine_03", 0.3, 0.62, 0.32, shoulders, 0.72, mat)
		# encolure brodée
		var collar := StandardMaterial3D.new()
		collar.albedo_color = mat.albedo_color.darkened(0.25) if not look.get("wax", false) else Color("f1c40f")
		_drape_cone("spine_03", 0.13, 0.31, shoulders - 0.04, shoulders + 0.03, 0.72, collar)
		# bonnet (kufi)
		var head := skeleton.find_bone("Head")
		if head >= 0:
			var att := BoneAttachment3D.new()
			att.bone_idx = head
			skeleton.add_child(att)
			var kufi := MeshInstance3D.new()
			var km := CylinderMesh.new()
			km.top_radius = 0.085
			km.bottom_radius = 0.098
			km.height = 0.1
			kufi.mesh = km
			var kmat := StandardMaterial3D.new()
			kmat.albedo_color = look.get("kufi", mat.albedo_color if not look.get("wax", false) else Color("ecf0f1"))
			kmat.roughness = 0.8
			kufi.material_override = kmat
			kufi.transform = skeleton.get_bone_global_rest(head).affine_inverse() * Transform3D(Basis(), Vector3(0, 1.73, -0.005))
			att.add_child(kufi)


## Tissu évasé (tronc de cône sans fond) accroché à un os, de y_bas à y_haut (mètres, pose de repos).
func _drape_cone(bone_name: String, r_top: float, r_bottom: float, y_bottom: float, y_top: float, depth_scale: float, mat: Material) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = bone
	skeleton.add_child(att)
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = y_top - y_bottom
	cm.radial_segments = 24
	cm.rings = 4
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	var t := Transform3D(Basis().scaled(Vector3(1.0, 1.0, depth_scale)), Vector3(0, y_bottom + cm.height * 0.5, 0.01))
	mi.transform = skeleton.get_bone_global_rest(bone).affine_inverse() * t
	att.add_child(mi)


static var _wax_cache := {}
## Petit motif de tissu wax (cercles et points) généré une fois par couleur.
static func _wax_texture(base: Color, accent: Color) -> ImageTexture:
	var key := base.to_html() + accent.to_html()
	if _wax_cache.has(key):
		return _wax_cache[key]
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 32, y - 32).length()
			var c := base
			if (d > 18 and d < 25) or d < 7:
				c = accent
			elif d >= 28 and int(x / 4 + y / 4) % 2 == 0:
				c = base.lerp(accent, 0.35)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_wax_cache[key] = tex
	return tex


# ---------------------------------------------------------------- cheveux

func _add_hair(look: Dictionary, female: bool) -> void:
	var options := ["Hair_Buns", "Hair_BuzzedFemale", "Hair_Long"] if female else ["Hair_Buzzed", "Hair_Buzzed", "Hair_SimpleParted"]
	var hair: String = look.get("hair", options.pick_random())
	var parts := [hair, "Eyebrows_Female" if female else "Eyebrows_Regular"]
	if not female and look.get("beard", randf() < 0.35):
		parts.append("Hair_Beard")
	var head := skeleton.find_bone("Head")
	if head < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = head
	skeleton.add_child(att)
	var offset := skeleton.get_bone_global_rest(head).affine_inverse()
	for p in parts:
		var path: String = HAIR_DIR + p + ".gltf"
		if not ResourceLoader.exists(path):
			continue
		var h: Node3D = load(path).instantiate()
		h.transform = offset
		att.add_child(h)
		for mi: MeshInstance3D in h.find_children("*", "MeshInstance3D", true, false):
			var base: BaseMaterial3D = mi.mesh.surface_get_material(0)
			if base:
				var dark: BaseMaterial3D = base.duplicate()
				dark.albedo_color = look.get("hair_color", HAIR_TINT)
				dark.roughness = 0.75
				mi.material_override = dark
		if look.get("head_wrap", false) and p == hair:
			# foulard : on colore la coiffure avec le tissu choisi
			var wrap := StandardMaterial3D.new()
			wrap.albedo_color = look.get("wrap_color", Color("c0392b"))
			wrap.roughness = 0.85
			for mi: MeshInstance3D in h.find_children("*", "MeshInstance3D", true, false):
				mi.material_override = wrap
				mi.scale *= 1.08   # multiplier : le modèle a déjà sa propre échelle
