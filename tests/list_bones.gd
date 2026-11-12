extends SceneTree
func _init() -> void:
	for p in OS.get_cmdline_user_args():
		var n: Node = load(p).instantiate()
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		var names := []
		for i in sk.get_bone_count():
			names.append(sk.get_bone_name(i))
		print("== ", p, " (", sk.get_bone_count(), ") chemin=", n.get_path_to(sk))
		print(", ".join(names))
		var aabb := AABB()
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			print("  mesh ", mi.name, " ", mi.get_aabb().size.snapped(Vector3.ONE * 0.01))
		n.free()
	quit()
