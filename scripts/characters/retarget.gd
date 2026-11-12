extends RefCounted
## Reciblage d'animations : convertit les animations de l'« Universal Animation Library »
## (squelette type Unreal) vers un autre squelette humanoïde (Mixamo, MakeHuman…).
##
## Méthode : pour chaque image, on calcule la rotation globale de chaque os source par rapport
## à sa pose de repos, puis on l'applique à l'os cible correspondant, après avoir aligné
## les poses de repos (T-pose / A-pose) et l'orientation des deux personnages.
## Les animations converties sont mises en cache par squelette.

const ANIMS_PATH := "res://assets/animations/UAL1_Standard.glb"
const FPS := 30.0

## Os de la bibliothèque source → noms possibles dans les squelettes cibles (sans suffixe numérique).
const MAP := {
	"pelvis": ["mixamorig_Hips", "Hips", "root"],
	"spine_01": ["mixamorig_Spine", "Spine", "spine04"],
	"spine_02": ["mixamorig_Spine1", "Spine1", "spine03"],
	"spine_03": ["mixamorig_Spine2", "Spine2", "spine01"],
	"neck_01": ["mixamorig_Neck", "Neck", "neck01"],
	"Head": ["mixamorig_Head", "Head", "head"],
	"clavicle_l": ["mixamorig_LeftShoulder", "LeftShoulder", "clavicle.L"],
	"upperarm_l": ["mixamorig_LeftArm", "LeftArm", "upperarm01.L"],
	"lowerarm_l": ["mixamorig_LeftForeArm", "LeftForeArm", "lowerarm01.L"],
	"hand_l": ["mixamorig_LeftHand", "LeftHand", "wrist.L"],
	"clavicle_r": ["mixamorig_RightShoulder", "RightShoulder", "clavicle.R"],
	"upperarm_r": ["mixamorig_RightArm", "RightArm", "upperarm01.R"],
	"lowerarm_r": ["mixamorig_RightForeArm", "RightForeArm", "lowerarm01.R"],
	"hand_r": ["mixamorig_RightHand", "RightHand", "wrist.R"],
	"thigh_l": ["mixamorig_LeftUpLeg", "LeftUpLeg", "upperleg01.L"],
	"calf_l": ["mixamorig_LeftLeg", "LeftLeg", "lowerleg01.L"],
	"foot_l": ["mixamorig_LeftFoot", "LeftFoot", "foot.L"],
	"ball_l": ["mixamorig_LeftToeBase", "LeftToeBase", "toe1-1.L"],
	"thigh_r": ["mixamorig_RightUpLeg", "RightUpLeg", "upperleg01.R"],
	"calf_r": ["mixamorig_RightLeg", "RightLeg", "lowerleg01.R"],
	"foot_r": ["mixamorig_RightFoot", "RightFoot", "foot.R"],
	"ball_r": ["mixamorig_RightToeBase", "RightToeBase", "toe1-1.R"],
}
## Os enfant utilisé pour connaître la direction de chaque os au repos.
const CHILD := {
	"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "Head",
	"clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l",
	"clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r",
	"thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l",
	"thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r",
}

static var _cache := {}


## Nom d'os sans le suffixe numérique ajouté par Sketchfab (« mixamorig_Hips_01 » → « mixamorig_Hips »).
static func clean(name: String) -> String:
	var i := name.rfind("_")
	if i > 0 and name.substr(i + 1).is_valid_int():
		return name.substr(0, i)
	return name


## Transformation du squelette vers la racine du modèle (échelle et rotations d'import comprises).
static func to_root(top: Node, sk: Skeleton3D) -> Transform3D:
	var t := Transform3D()
	var n: Node = sk
	while n != top and n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _global_rests(sk: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		out[i] = (out[p] if p >= 0 else Transform3D()) * sk.get_bone_rest(i)
	return out


## Construit (ou récupère) la bibliothèque d'animations convertie pour ce squelette.
## `key` identifie le modèle (son chemin), `anim_names` les animations à convertir.
static func library_for(key: String, top: Node3D, sk: Skeleton3D, anim_names: Array) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var src: Node3D = load(ANIMS_PATH).instantiate()
	var ssk: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var sap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
	var s_root := to_root(src, ssk)
	var t_root := to_root(top, sk)
	var s_rest := _global_rests(ssk)
	var t_rest := _global_rests(sk)
	# correspondance des os
	var t_index := {}
	for i in sk.get_bone_count():
		t_index[clean(sk.get_bone_name(i))] = i
	var pairs := {}   # os source → os cible
	for sname in MAP:
		var si := ssk.find_bone(sname)
		if si < 0:
			continue
		for cand in MAP[sname]:
			if t_index.has(cand):
				pairs[si] = t_index[cand]
				break
	# espace commun : on aligne l'orientation du personnage cible sur la source
	var s_rb := s_root.basis.orthonormalized()
	var t_rb := t_root.basis.orthonormalized()
	var sl := ssk.find_bone("upperarm_l")
	var sr := ssk.find_bone("upperarm_r")
	var s_left := s_rb * (s_rest[sl].origin - s_rest[sr].origin)
	var tl: int = pairs.get(sl, -1)
	var tr: int = pairs.get(sr, -1)
	var align := Basis()
	if tl >= 0 and tr >= 0:
		var t_left := t_rb * (t_rest[tl].origin - t_rest[tr].origin)
		var a := Vector2(s_left.x, s_left.z).angle()
		var b := Vector2(t_left.x, t_left.z).angle()
		align = Basis(Vector3.UP, b - a)   # rotation autour de Y : gauche cible → gauche source
	var t_space := align * t_rb
	# rotations de repos dans l'espace commun
	var s_rest_q := {}
	for i in ssk.get_bone_count():
		s_rest_q[i] = Quaternion((s_rb * s_rest[i].basis).orthonormalized())
	var t_rest_q := {}
	for i in sk.get_bone_count():
		t_rest_q[i] = Quaternion((t_space * t_rest[i].basis).orthonormalized())
	# alignement des poses de repos (T-pose / A-pose) os par os
	var fix := {}
	for si in pairs:
		var ti: int = pairs[si]
		fix[si] = Quaternion.IDENTITY
		var child: String = CHILD.get(ssk.get_bone_name(si), "")
		var sc := ssk.find_bone(child)
		if sc >= 0 and pairs.has(sc):
			var ds := (s_rb * (s_rest[sc].origin - s_rest[si].origin)).normalized()
			var dt := (t_space * (t_rest[pairs[sc]].origin - t_rest[ti].origin)).normalized()
			if ds.length() > 0.5 and dt.length() > 0.5 and ds.dot(dt) < 0.9999:
				fix[si] = Quaternion(dt, ds)
	# hauteur des hanches pour adapter le déplacement du bassin
	var sp := ssk.find_bone("pelvis")
	var tp: int = pairs.get(sp, -1)
	var s_hip_h := (s_root * s_rest[sp].origin).y if sp >= 0 else 1.0
	var t_hip_h := (t_root * t_rest[tp].origin).y if tp >= 0 else 1.0
	var t_root_inv := t_root.affine_inverse()

	var lib := AnimationLibrary.new()
	var skel_path := String(top.get_path_to(sk))
	for anim_name in anim_names:
		if not sap.has_animation(anim_name):
			continue
		var sa: Animation = sap.get_animation(anim_name)
		var out := Animation.new()
		out.length = sa.length
		out.loop_mode = sa.loop_mode
		var rot_tracks := {}
		for si in pairs:
			var ti: int = pairs[si]
			var tr2 := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(tr2, NodePath(skel_path + ":" + sk.get_bone_name(ti)))
			rot_tracks[ti] = tr2
		var pos_track := -1
		if tp >= 0:
			pos_track = out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(pos_track, NodePath(skel_path + ":" + sk.get_bone_name(tp)))
		# pistes source par os
		var s_tracks := {}
		var s_pos_track := -1
		for k in sa.get_track_count():
			var bone := String(sa.track_get_path(k)).get_slice(":", 1)
			var bi := ssk.find_bone(bone)
			if bi < 0:
				continue
			if sa.track_get_type(k) == Animation.TYPE_ROTATION_3D:
				s_tracks[bi] = k
			elif sa.track_get_type(k) == Animation.TYPE_POSITION_3D and bi == sp:
				s_pos_track = k
		var frames := maxi(2, int(ceil(sa.length * FPS)) + 1)
		for f in frames:
			var t := minf(f / FPS, sa.length)
			# pose globale source (rotations) dans l'espace commun
			var s_glob := {}
			for i in ssk.get_bone_count():
				var local_q: Quaternion = sa.rotation_track_interpolate(s_tracks[i], t) if s_tracks.has(i) else ssk.get_bone_rest(i).basis.get_rotation_quaternion()
				var p := ssk.get_bone_parent(i)
				s_glob[i] = (s_glob[p] if p >= 0 else Quaternion(s_rb)) * local_q
			# pose globale cible, en parcourant la hiérarchie
			var t_glob := {}
			for i in sk.get_bone_count():
				var p := sk.get_bone_parent(i)
				var parent_q: Quaternion = t_glob[p] if p >= 0 else Quaternion(t_space)
				var mapped := -1
				for si in pairs:
					if pairs[si] == i:
						mapped = si
						break
				if mapped >= 0:
					var delta: Quaternion = s_glob[mapped] * (s_rest_q[mapped] as Quaternion).inverse()
					var want: Quaternion = delta * (fix[mapped] as Quaternion) * (t_rest_q[i] as Quaternion)
					t_glob[i] = want
					out.rotation_track_insert_key(rot_tracks[i], t, (parent_q.inverse() * want).normalized())
				else:
					t_glob[i] = parent_q * sk.get_bone_rest(i).basis.get_rotation_quaternion()
			# déplacement du bassin (montée / descente pendant la marche, saut…)
			if pos_track >= 0:
				var s_pos: Vector3 = sa.position_track_interpolate(s_pos_track, t) if s_pos_track >= 0 else ssk.get_bone_rest(sp).origin
				var sp_parent := ssk.get_bone_parent(sp)
				var s_parent_g: Transform3D = s_rest[sp_parent] if sp_parent >= 0 else Transform3D()
				var s_delta: Vector3 = s_root * (s_parent_g * s_pos) - s_root * s_rest[sp].origin
				s_delta *= t_hip_h / maxf(s_hip_h, 0.01)
				s_delta = align.inverse() * s_delta
				var tp_parent := sk.get_bone_parent(tp)
				var t_parent_g: Transform3D = t_rest[tp_parent] if tp_parent >= 0 else Transform3D()
				var world := t_root * t_rest[tp].origin + s_delta
				var local := t_parent_g.affine_inverse() * (t_root_inv * world)
				out.position_track_insert_key(pos_track, t, local)
		lib.add_animation(anim_name, out)
	src.free()
	var result := {"library": lib, "align": align, "space": t_space}
	_cache[key] = result
	return result
