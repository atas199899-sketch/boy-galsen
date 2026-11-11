extends RefCounted
## Véhicules de Dakar construits en code, avec une vraie silhouette (carrosserie profilée,
## vitres, roues à jantes, phares) et une peinture vernie :
##   taxi        : berline jaune et noire
##   car         : voiture particulière
##   car_rapide  : minibus bleu et jaune peint à la main, galerie sur le toit
##   ndiaga      : grand minibus blanc (Ndiaga Ndiaye)
## Les véhicules regardent vers +X ; longueur en mètres.

static var _mats := {}


static func make(kind: String, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	match kind:
		"taxi":
			_sedan(root, Color("f2c230"), true, rng)
		"car_rapide":
			_car_rapide(root, rng)
		"ndiaga":
			_ndiaga(root, rng)
		_:
			var cols := [Color("d8d8d8"), Color("1b1b1b"), Color("8a8d91"), Color("6e1b1b"), Color("1f3f6b"), Color("f2f2ee"), Color("3d4a3a"), Color("5b4636")]
			_sedan(root, cols[rng.randi() % cols.size()], false, rng)
	return root


## Taille de la boîte de collision (longueur, hauteur, largeur).
static func size_of(kind: String) -> Vector3:
	match kind:
		"car_rapide":
			return Vector3(5.3, 2.5, 2.0)
		"ndiaga":
			return Vector3(7.0, 2.8, 2.2)
	return Vector3(4.4, 1.5, 1.8)


# ---------------------------------------------------------------- matériaux

static func paint(c: Color) -> StandardMaterial3D:
	var key := "p" + c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = 0.35
		m.roughness = 0.32
		m.clearcoat_enabled = true
		m.clearcoat = 0.8
		m.clearcoat_roughness = 0.1
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return _mats[key]


static func mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match key:
		"glass":
			m.albedo_color = Color(0.08, 0.11, 0.14)
			m.metallic = 0.8
			m.roughness = 0.05
		"tyre":
			m.albedo_color = Color(0.06, 0.06, 0.06)
			m.roughness = 0.9
		"rim":
			m.albedo_color = Color(0.75, 0.76, 0.78)
			m.metallic = 0.9
			m.roughness = 0.25
		"black":
			m.albedo_color = Color(0.05, 0.05, 0.05)
			m.roughness = 0.5
		"chrome":
			m.albedo_color = Color(0.8, 0.8, 0.8)
			m.metallic = 1.0
			m.roughness = 0.15
		"head":
			m.albedo_color = Color(0.95, 0.95, 0.9)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.95, 0.8)
			m.emission_energy_multiplier = 0.3
		"tail":
			m.albedo_color = Color(0.6, 0.05, 0.05)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.1, 0.1)
			m.emission_energy_multiplier = 0.4
		"rust":
			m.albedo_color = Color(0.45, 0.28, 0.18)
			m.roughness = 0.9
	_mats[key] = m
	return m


## Allume les phares la nuit (0 = jour, 1 = nuit).
static func set_night(night: float) -> void:
	mat("head").emission_energy_multiplier = lerpf(0.3, 3.0, night)
	mat("tail").emission_energy_multiplier = lerpf(0.4, 2.0, night)


# ---------------------------------------------------------------- formes

## Construit un « loft » : une suite de sections le long de X. Chaque station :
## [x, y_bas, y_haut, demi_largeur_bas, demi_largeur_haut]. Sections en rectangle arrondi.
static func loft(stations: Array, m: Material, ring := 12) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var rings: Array = []
	for s in stations:
		var x: float = s[0]
		var yb: float = s[1]
		var yt: float = s[2]
		var wb: float = s[3]
		var wt: float = s[4]
		var pts: Array = []
		var r := minf(0.12, (yt - yb) * 0.3)
		# contour : bas gauche → haut gauche → haut droit → bas droit ; toit légèrement bombé
		var corners := [[-wb, yb], [-wt, yt], [wt, yt], [wb, yb]]
		for k in ring:
			var t := float(k) / ring * 4.0
			var seg := int(t)
			var f := t - seg
			var a: Array = corners[seg]
			var b: Array = corners[(seg + 1) % 4]
			var y := lerpf(a[1], b[1], f)
			if seg == 1:
				y += sin(f * PI) * r
			pts.append(Vector3(x, y, lerpf(a[0], b[0], f)))
		rings.append(pts)
	for i in rings.size():
		for p in rings[i]:
			verts.append(p)
			norms.append(Vector3(0, p.y - (stations[i][1] + stations[i][2]) * 0.5, p.z).normalized())
	for i in rings.size() - 1:
		for k in ring:
			var a := i * ring + k
			var b := i * ring + (k + 1) % ring
			var c := (i + 1) * ring + k
			var d := (i + 1) * ring + (k + 1) % ring
			idx.append_array([a, c, b, b, c, d])
	# bouchons avant / arrière
	for end in [0, rings.size() - 1]:
		var center := Vector3.ZERO
		for p in rings[end]:
			center += p
		center /= ring
		var ci := verts.size()
		verts.append(center)
		norms.append(Vector3(1 if end > 0 else -1, 0, 0))
		for k in ring:
			idx.append_array([ci, end * ring + k, end * ring + (k + 1) % ring])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = m
	return mi


static func box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	return mi


static func wheels(root: Node3D, xs: Array, half_track: float, r: float) -> void:
	var tyre := CylinderMesh.new()
	tyre.top_radius = r
	tyre.bottom_radius = r
	tyre.height = 0.22
	tyre.radial_segments = 18
	var rim := CylinderMesh.new()
	rim.top_radius = r * 0.62
	rim.bottom_radius = r * 0.62
	rim.height = 0.24
	rim.radial_segments = 12
	for x in xs:
		for side in [-1.0, 1.0]:
			var t := MeshInstance3D.new()
			t.mesh = tyre
			t.material_override = mat("tyre")
			t.position = Vector3(x, r, side * half_track)
			t.rotation.x = PI / 2.0
			root.add_child(t)
			var w := MeshInstance3D.new()
			w.mesh = rim
			w.material_override = mat("rim")
			w.position = Vector3(x, r, side * (half_track + 0.01))
			w.rotation.x = PI / 2.0
			root.add_child(w)


static func _sedan(root: Node3D, color: Color, taxi: bool, rng: RandomNumberGenerator) -> void:
	var body := paint(color)
	# carrosserie basse : pare-chocs arrière → capot → pare-chocs avant
	root.add_child(loft([
		[-2.22, 0.34, 0.78, 0.80, 0.78], [-2.12, 0.26, 0.98, 0.86, 0.84], [-1.6, 0.24, 1.0, 0.88, 0.86],
		[1.2, 0.24, 0.95, 0.88, 0.86], [1.85, 0.26, 0.86, 0.87, 0.84], [2.18, 0.32, 0.72, 0.82, 0.76], [2.25, 0.4, 0.62, 0.74, 0.7]], body))
	# habitacle vitré
	root.add_child(loft([
		[-1.62, 0.96, 0.98, 0.84, 0.82], [-1.05, 0.98, 1.45, 0.84, 0.70], [0.42, 0.98, 1.47, 0.84, 0.70],
		[1.2, 0.95, 0.99, 0.85, 0.83]], mat("glass"), 10))
	# toit peint + montants
	var roof_col := Color(0.06, 0.06, 0.06) if taxi else color
	root.add_child(loft([[-1.0, 1.42, 1.49, 0.71, 0.66], [0.4, 1.44, 1.51, 0.71, 0.66]], paint(roof_col), 8))
	for x in [-0.35, 0.95]:
		for side in [-1.0, 1.0]:
			var p := box(Vector3(0.09, 0.48, 0.05), Vector3(x if x < 0 else 0.84, 1.2, side * 0.8), body)
			p.rotation.z = 0.0 if x < 0 else -0.6
			root.add_child(p)
	if taxi:
		root.add_child(box(Vector3(4.46, 0.12, 1.79), Vector3(0, 0.7, 0), paint(Color(0.05, 0.05, 0.05))))
		root.add_child(box(Vector3(0.55, 0.2, 0.32), Vector3(-0.3, 1.6, 0), mat("head")))
	# phares, feux, calandre, rétroviseurs
	for side in [-1.0, 1.0]:
		root.add_child(box(Vector3(0.06, 0.12, 0.34), Vector3(2.2, 0.74, side * 0.55), mat("head")))
		root.add_child(box(Vector3(0.05, 0.14, 0.3), Vector3(-2.2, 0.82, side * 0.6), mat("tail")))
		root.add_child(box(Vector3(0.12, 0.1, 0.18), Vector3(0.95, 1.02, side * 0.96), body))
	root.add_child(box(Vector3(0.05, 0.16, 0.7), Vector3(2.24, 0.6, 0), mat("black")))
	root.add_child(box(Vector3(0.04, 0.16, 0.5), Vector3(-2.24, 0.55, 0), mat("chrome")))
	wheels(root, [-1.35, 1.35], 0.8, 0.32)


static func _car_rapide(root: Node3D, rng: RandomNumberGenerator) -> void:
	var blue := paint(Color("1f5fae"))
	var yellow := paint(Color("f2c230"))
	var white := paint(Color("f1efe8"))
	# caisse : bas jaune, bande bleue, vitres, toit blanc bombé
	root.add_child(loft([[-2.65, 0.45, 1.15, 0.98, 0.98], [2.2, 0.45, 1.15, 0.98, 0.98], [2.62, 0.5, 1.05, 0.9, 0.92]], yellow))
	root.add_child(loft([[-2.65, 1.15, 1.35, 0.98, 0.98], [2.4, 1.15, 1.35, 0.98, 0.97], [2.6, 1.05, 1.3, 0.92, 0.9]], blue))
	root.add_child(loft([[-2.6, 1.35, 1.9, 0.98, 0.95], [1.9, 1.35, 1.9, 0.98, 0.95], [2.45, 1.3, 1.75, 0.96, 0.92]], mat("glass"), 10))
	root.add_child(loft([[-2.65, 1.88, 2.25, 0.97, 0.8], [1.95, 1.88, 2.25, 0.97, 0.8], [2.4, 1.75, 2.0, 0.93, 0.8]], white, 10))
	# montants bleus entre les fenêtres
	for x in [-2.0, -1.0, 0.0, 1.0, 1.85]:
		for side in [-1.0, 1.0]:
			root.add_child(box(Vector3(0.12, 0.56, 0.04), Vector3(x, 1.62, side * 0.97), blue))
	# décorations peintes (bandes et losanges)
	for k in 6:
		var c: Color = [Color("c0392b"), Color("27ae60"), Color("f1efe8")][k % 3]
		root.add_child(box(Vector3(0.5, 0.18, 0.02), Vector3(-2.2 + k * 0.8, 0.8, 0.99), paint(c)))
		root.add_child(box(Vector3(0.5, 0.18, 0.02), Vector3(-2.2 + k * 0.8, 0.8, -0.99), paint(c)))
	# galerie sur le toit avec bagages
	var rack := mat("rust")
	for z in [-0.75, 0.75]:
		root.add_child(box(Vector3(3.8, 0.05, 0.05), Vector3(-0.3, 2.45, z), rack))
	for x in [-2.0, -1.0, 0.0, 1.0]:
		root.add_child(box(Vector3(0.05, 0.05, 1.5), Vector3(x, 2.45, 0), rack))
	for k in rng.randi_range(1, 4):
		var c: Color = [Color("5b4636"), Color("2c3e50"), Color("8e44ad"), Color("c9b28a")][rng.randi() % 4]
		root.add_child(box(Vector3(rng.randf_range(0.5, 0.9), rng.randf_range(0.3, 0.5), rng.randf_range(0.4, 0.8)), Vector3(rng.randf_range(-1.8, 0.8), 2.62, rng.randf_range(-0.4, 0.4)), paint(c)))
	# porte arrière ouverte avec l'apprenti qui s'y accroche (marchepied)
	root.add_child(box(Vector3(0.1, 0.06, 1.2), Vector3(-2.75, 0.5, 0), mat("chrome")))
	for side in [-1.0, 1.0]:
		root.add_child(box(Vector3(0.06, 0.16, 0.3), Vector3(2.62, 0.75, side * 0.6), mat("head")))
		root.add_child(box(Vector3(0.05, 0.2, 0.15), Vector3(-2.66, 0.9, side * 0.85), mat("tail")))
	root.add_child(box(Vector3(0.06, 0.25, 1.4), Vector3(2.64, 0.55, 0), mat("chrome")))
	wheels(root, [-1.7, 1.75], 0.88, 0.38)


static func _ndiaga(root: Node3D, rng: RandomNumberGenerator) -> void:
	var white := paint(Color("f4f3ee"))
	var stripe := paint([Color("1f7a4d"), Color("1f5fae"), Color("c0392b")][rng.randi() % 3])
	root.add_child(loft([[-3.45, 0.5, 1.3, 1.08, 1.08], [2.9, 0.5, 1.3, 1.08, 1.08], [3.45, 0.55, 1.15, 1.0, 1.0]], white))
	root.add_child(loft([[-3.45, 1.3, 2.0, 1.08, 1.05], [2.7, 1.3, 2.0, 1.08, 1.05], [3.35, 1.2, 1.85, 1.02, 0.98]], mat("glass"), 10))
	root.add_child(loft([[-3.45, 1.98, 2.7, 1.06, 0.95], [2.75, 1.98, 2.7, 1.06, 0.95], [3.2, 1.85, 2.3, 1.0, 0.9]], white, 10))
	for side in [-1.0, 1.0]:
		root.add_child(box(Vector3(6.6, 0.16, 0.02), Vector3(-0.1, 1.15, side * 1.09), stripe))
		for k in 7:
			root.add_child(box(Vector3(0.1, 0.7, 0.04), Vector3(-3.0 + k * 0.95, 1.65, side * 1.07), white))
		root.add_child(box(Vector3(0.06, 0.16, 0.35), Vector3(3.45, 0.8, side * 0.65), mat("head")))
		root.add_child(box(Vector3(0.05, 0.2, 0.18), Vector3(-3.47, 0.95, side * 0.9), mat("tail")))
		var l := Label3D.new()
		l.text = ["Alhamdoulilah", "Touba", "Dieureudieuf Serigne", "Ndiaga Ndiaye"][rng.randi() % 4]
		l.font_size = 64
		l.pixel_size = 0.006
		l.modulate = stripe.albedo_color
		l.outline_size = 0
		l.position = Vector3(-0.5, 0.85, side * 1.1)
		l.rotation.y = 0.0 if side > 0 else PI
		root.add_child(l)
	root.add_child(box(Vector3(0.06, 0.3, 1.6), Vector3(3.47, 0.6, 0), mat("chrome")))
	var rack := mat("rust")
	for z in [-0.8, 0.8]:
		root.add_child(box(Vector3(5.0, 0.05, 0.05), Vector3(-0.4, 2.85, z), rack))
	for k in rng.randi_range(2, 5):
		root.add_child(box(Vector3(rng.randf_range(0.5, 1.0), rng.randf_range(0.3, 0.6), rng.randf_range(0.5, 0.9)), Vector3(rng.randf_range(-2.6, 1.6), 3.05, rng.randf_range(-0.45, 0.45)), paint([Color("5b4636"), Color("2c3e50"), Color("c9b28a"), Color("7f8c8d")][rng.randi() % 4])))
	wheels(root, [-2.3, 2.35], 0.95, 0.42)
