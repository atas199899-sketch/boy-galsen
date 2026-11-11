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
			return Vector3(5.1, 2.5, 2.0)
		"ndiaga":
			return Vector3(6.3, 2.9, 2.15)
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


static func _label(root: Node3D, text: String, pos: Vector3, rot_y: float, size: int, color: Color, outline := Color(0, 0, 0, 0)) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 8 if outline.a > 0.0 else 0
	l.outline_modulate = outline
	l.position = pos
	l.rotation.y = rot_y
	l.double_sided = false
	root.add_child(l)


## Fenêtres latérales : rectangles vitrés posés sur la caisse (x0, x1 le long du véhicule).
static func _side_windows(root: Node3D, spans: Array, y0: float, y1: float, hw: float) -> void:
	for sp in spans:
		for side in [-1.0, 1.0]:
			root.add_child(box(Vector3(sp[1] - sp[0], y1 - y0, 0.03), Vector3((sp[0] + sp[1]) * 0.5, (y0 + y1) * 0.5, side * (hw + 0.01)), mat("glass")))


## Galerie de toit : cadre + barreaux.
static func _roof_rack(root: Node3D, x0: float, x1: float, y: float, hw: float, m: Material) -> void:
	for z in [-hw, hw]:
		root.add_child(box(Vector3(x1 - x0, 0.06, 0.06), Vector3((x0 + x1) * 0.5, y + 0.25, z), m))
		root.add_child(box(Vector3(x1 - x0, 0.05, 0.05), Vector3((x0 + x1) * 0.5, y + 0.08, z), m))
	var x := x0
	while x <= x1 + 0.01:
		root.add_child(box(Vector3(0.05, 0.05, hw * 2.0), Vector3(x, y + 0.25, 0), m))
		for z in [-hw, hw]:
			root.add_child(box(Vector3(0.05, 0.22, 0.05), Vector3(x, y + 0.14, z), m))
		x += 0.6


## Car rapide (Renault SG2) : petit capot arrondi, bas bleu, bandeau blanc
## « TRANSPORT EN COMMUN », haut et toit jaunes, galerie, décorations peintes.
static func _car_rapide(root: Node3D, rng: RandomNumberGenerator) -> void:
	var blue := paint(Color("1d4f9c"))
	var yellow := paint(Color("f0b52a"))
	var white := paint(Color("f3f1ea"))
	var hw := 0.98
	# caisse : bas bleu, bandeau blanc, haut jaune, toit jaune bombé
	root.add_child(loft([[-2.5, 0.45, 1.05, hw, hw], [1.95, 0.45, 1.05, hw, hw]], blue))
	root.add_child(loft([[-2.5, 1.05, 1.28, hw, hw], [1.95, 1.05, 1.28, hw, hw]], white))
	root.add_child(loft([[-2.5, 1.28, 1.95, hw, hw * 0.99], [1.95, 1.28, 1.95, hw, hw * 0.99]], yellow))
	root.add_child(loft([[-2.5, 1.94, 2.22, hw * 0.99, hw * 0.82], [1.95, 1.94, 2.22, hw * 0.99, hw * 0.82], [2.02, 1.9, 2.12, hw * 0.95, hw * 0.8]], yellow, 12))
	# capot court et arrondi (bleu en bas, jaune dessus) + calandre
	root.add_child(loft([[1.9, 0.5, 1.2, 0.86, 0.8], [2.3, 0.5, 1.12, 0.84, 0.72], [2.5, 0.55, 0.98, 0.76, 0.6], [2.56, 0.62, 0.86, 0.66, 0.5]], yellow, 12))
	root.add_child(box(Vector3(0.08, 0.32, 0.9), Vector3(2.52, 0.72, 0), white))
	for k in 5:
		root.add_child(box(Vector3(0.03, 0.03, 0.8), Vector3(2.565, 0.6 + k * 0.06, 0), mat("chrome")))
	root.add_child(box(Vector3(0.1, 0.16, 1.9), Vector3(2.55, 0.48, 0), mat("chrome")))
	# pare-brise et vitre de porte
	var ws := box(Vector3(0.04, 0.6, 1.7), Vector3(1.98, 1.58, 0), mat("glass"))
	ws.rotation.z = 0.12
	root.add_child(ws)
	_side_windows(root, [[1.15, 1.85], [-2.35, -1.6], [-1.45, -0.7], [-0.55, 0.25], [0.4, 1.0]], 1.36, 1.86, hw)
	# texte et décorations
	for side in [-1.0, 1.0]:
		_label(root, "TRANSPORT EN COMMUN", Vector3(-0.3, 1.165, side * (hw + 0.02)), 0.0 if side > 0 else PI, 72, Color("1d4f9c"))
		_label(root, ["Touba", "Alhamdoulilah", "Ndiguel", "Baye Fall"][rng.randi() % 4], Vector3(-1.2, 0.8, side * (hw + 0.02)), 0.0 if side > 0 else PI, 56, Color("f3f1ea"))
		var d := box(Vector3(0.35, 0.35, 0.02), Vector3(0.9, 0.78, side * (hw + 0.012)), paint(Color("e74c3c")))
		d.rotation.z = PI / 4.0
		root.add_child(d)
		root.add_child(box(Vector3(0.18, 0.18, 0.025), Vector3(0.9, 0.78, side * (hw + 0.015)), paint(Color("27ae60"))))
		root.add_child(box(Vector3(4.4, 0.04, 0.02), Vector3(-0.27, 1.03, side * (hw + 0.012)), paint(Color("e74c3c"))))
		root.add_child(box(Vector3(0.1, 0.14, 0.24), Vector3(2.5, 0.85, side * 0.62), mat("head")))
		root.add_child(box(Vector3(0.05, 0.2, 0.15), Vector3(-2.52, 0.9, side * 0.85), mat("tail")))
	_label(root, "ALHAMDOULILAH", Vector3(2.03, 2.0, 0), PI / 2.0, 64, Color("1d4f9c"))
	# galerie de toit avec bagages
	_roof_rack(root, -2.3, 1.7, 2.22, 0.88, paint(Color("2a3f6b")))
	for k in rng.randi_range(1, 3):
		root.add_child(box(Vector3(rng.randf_range(0.5, 0.9), rng.randf_range(0.3, 0.5), rng.randf_range(0.4, 0.8)), Vector3(rng.randf_range(-1.8, 0.8), 2.55, rng.randf_range(-0.4, 0.4)), paint([Color("5b4636"), Color("2c3e50"), Color("8e44ad"), Color("c9b28a")][rng.randi() % 4])))
	# échelle et marchepied arrière (porte ouverte de l'apprenti)
	for k in 4:
		root.add_child(box(Vector3(0.04, 0.04, 0.5), Vector3(-2.53, 1.0 + k * 0.32, 0.55), mat("chrome")))
	root.add_child(box(Vector3(0.25, 0.05, 1.4), Vector3(-2.62, 0.45, 0), mat("chrome")))
	wheels(root, [-1.55, 1.55], 0.86, 0.4)


## Ndiaga Ndiaye (Mercedes 508) : grand minibus blanc, petit nez court avec calandre,
## grand pare-brise, fenêtres espacées, longue galerie de toit.
static func _ndiaga(root: Node3D, rng: RandomNumberGenerator) -> void:
	var white := paint(Color("f2f1ec"))
	var hw := 1.05
	# caisse haute et longue + toit arrondi
	root.add_child(loft([[-3.2, 0.5, 2.2, hw, hw], [2.45, 0.5, 2.2, hw, hw]], white))
	root.add_child(loft([[-3.2, 2.18, 2.48, hw, hw * 0.86], [2.45, 2.18, 2.48, hw, hw * 0.86], [2.6, 2.1, 2.36, hw * 0.95, hw * 0.8]], white, 12))
	# nez court (moteur) + calandre noire chromée + logo
	root.add_child(loft([[2.4, 0.55, 1.3, 0.98, 0.95], [2.85, 0.55, 1.25, 0.96, 0.9], [3.1, 0.6, 1.12, 0.9, 0.8]], white, 12))
	root.add_child(box(Vector3(0.06, 0.38, 1.0), Vector3(3.1, 0.88, 0), mat("black")))
	for k in 4:
		root.add_child(box(Vector3(0.03, 0.03, 0.95), Vector3(3.135, 0.75 + k * 0.09, 0), mat("chrome")))
	var logo := MeshInstance3D.new()
	var lm := TorusMesh.new()
	lm.inner_radius = 0.07
	lm.outer_radius = 0.09
	logo.mesh = lm
	logo.material_override = mat("chrome")
	logo.position = Vector3(3.14, 0.9, 0)
	logo.rotation.z = PI / 2.0
	root.add_child(logo)
	root.add_child(box(Vector3(0.14, 0.2, 2.15), Vector3(3.13, 0.5, 0), mat("black")))
	for side in [-1.0, 1.0]:
		var hl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.1
		cm.height = 0.06
		hl.mesh = cm
		hl.material_override = mat("head")
		hl.position = Vector3(3.11, 0.92, side * 0.72)
		hl.rotation.z = PI / 2.0
		root.add_child(hl)
		root.add_child(box(Vector3(0.05, 0.1, 0.18), Vector3(3.1, 0.75, side * 0.72), paint(Color("e67e22"))))
		root.add_child(box(Vector3(0.05, 0.25, 0.16), Vector3(-3.22, 1.0, side * 0.9), mat("tail")))
		# porte de cabine (contour) et poignée
		root.add_child(box(Vector3(0.03, 1.5, 0.02), Vector3(1.55, 1.3, side * (hw + 0.01)), mat("black")))
		root.add_child(box(Vector3(0.18, 0.04, 0.03), Vector3(1.7, 1.25, side * (hw + 0.015)), mat("chrome")))
		# drapeau du Sénégal peint
		for k in 3:
			root.add_child(box(Vector3(0.12, 0.28, 0.02), Vector3(2.15 + k * 0.12, 1.15, side * (hw + 0.012)), paint([Color("00853f"), Color("fdef42"), Color("e31b23")][k])))
		_label(root, ["G.I.E Transport", "Touba Express", "Dieureudieuf", "Serigne Saliou"][rng.randi() % 4], Vector3(1.95, 1.0, side * (hw + 0.02)), 0.0 if side > 0 else PI, 44, Color("1b1b1b"))
	# grand pare-brise incliné et vitres latérales espacées (larges panneaux blancs entre)
	var ws := box(Vector3(0.04, 0.85, 1.85), Vector3(2.5, 1.75, 0), mat("glass"))
	ws.rotation.z = 0.14
	root.add_child(ws)
	_side_windows(root, [[1.65, 2.35], [-3.0, -2.15], [-1.75, -0.85], [-0.45, 0.45], [0.8, 1.4]], 1.45, 2.0, hw)
	_label(root, "ALHAMDOULILLAH", Vector3(2.62, 2.25, 0), PI / 2.0, 72, Color("1f7a4d"), Color("f2f1ec"))
	# longue galerie de toit (jusqu'au-dessus de la cabine)
	_roof_rack(root, -3.0, 2.6, 2.48, 0.98, paint(Color("d8cfbd")))
	for k in rng.randi_range(1, 4):
		root.add_child(box(Vector3(rng.randf_range(0.5, 1.0), rng.randf_range(0.3, 0.6), rng.randf_range(0.5, 0.9)), Vector3(rng.randf_range(-2.6, 1.6), 2.85, rng.randf_range(-0.45, 0.45)), paint([Color("5b4636"), Color("2c3e50"), Color("c9b28a"), Color("7f8c8d")][rng.randi() % 4])))
	# passages de roues sombres
	for x in [2.1, -1.7]:
		for side in [-1.0, 1.0]:
			root.add_child(box(Vector3(1.0, 0.5, 0.02), Vector3(x, 0.72, side * (hw + 0.005)), mat("black")))
	wheels(root, [-1.7, 2.1], 0.92, 0.42)
