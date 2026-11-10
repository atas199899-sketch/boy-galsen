extends Node3D
## Génère un quartier inspiré de Dakar (Médina / Plateau) :
## rues en damier, trottoirs, immeubles bas aux couleurs chaudes avec cours intérieures,
## toits-terrasses (citernes, fers à béton), boutiques avec enseignes, marché, place arborée,
## taxis jaunes et noirs garés, lampadaires.
##
## Tout est généré avec une graine fixe : la ville est identique à chaque partie.
## Plus tard, ce générateur pourra être remplacé par de vraies données de rues
## (OpenStreetMap, voir docs/ROADMAP.md).

const PITCH := 48.0          # distance entre deux axes de rue (m)
const ROAD_HALF := 3.5       # demi-largeur de chaussée
const WALK_W := 2.5          # largeur de trottoir
const GRID := 6              # nombre de pâtés de maisons par côté
const FLOOR_H := 3.2

## Lieux utilisables par les missions : clé -> position (sur le trottoir devant).
var places := {}
var place_names := {}
## Graphe des trottoirs pour les passants.
var sidewalk_nodes: Array[Vector3] = []
var sidewalk_links: Array = []
var spawn_point := Vector3.ZERO

var rng := RandomNumberGenerator.new()
var _mats := {}
var _windows: Array[Transform3D] = []
var _shutters: Array[Transform3D] = []
var _lamps: Array[Vector3] = []
var lamp_material: StandardMaterial3D
var window_material: StandardMaterial3D

const WALL_COLORS := ["e8d9b5", "d9a86c", "f2eee6", "c97b5a", "9fc2b8", "e3c16f", "b7c7d9", "d88a7a", "efe3c8", "c9b28a"]

## Boutiques obligatoires (utilisées par les missions) puis boutiques de décor.
const KEY_SHOPS := {
	"boulangerie": "Boulangerie Al Amine",
	"pharmacie": "Pharmacie de la Médina",
	"dibiterie": "Dibiterie Chez Pathé",
	"telecentre": "Télécentre Ndèye Coumba",
	"tailleur": "Couture Ndiaye & Fils",
	"garage": "Garage Mécanique Diop",
	"boutique": "Boutique Keur Mame",
}
const DECOR_SHOPS := ["Alimentation Fall", "Quincaillerie Sow", "Salon Belles Dames", "Restaurant Le Thiébou", "Cyber Café",
	"Boutique Diallo", "Tissus Wax Sall", "Pâtisserie Teranga", "Cordonnerie Gaye", "Transfert d'argent", "Bijouterie Thiam",
	"Librairie Ndar", "Vente de crédit", "Fruits & Légumes", "Café Touba"]
const AWNING_COLORS := ["c0392b", "1f7a4d", "f0b93a", "2f6fb3", "e67e22", "6b3fa0"]


func build() -> void:
	rng.seed = 221
	_make_shared_materials()
	_build_ground()
	_build_roads()
	var key_list := KEY_SHOPS.keys()
	var shop_slots: Array = []
	for j in GRID:
		for i in GRID:
			var x0 := i * PITCH + ROAD_HALF + WALK_W
			var z0 := j * PITCH + ROAD_HALF + WALK_W
			var size := PITCH - 2.0 * (ROAD_HALF + WALK_W)
			_build_sidewalk(x0, z0, size)
			if i == 2 and j == 2:
				_build_square(x0, z0, size)
			elif i == 3 and j == 3:
				_build_market(x0, z0, size)
			else:
				_build_block(x0, z0, size, shop_slots, absf(i - 2.5) + absf(j - 2.5))
	# placer les boutiques importantes à des endroits répartis dans la ville
	shop_slots.shuffle()
	for k in key_list.size():
		_make_shop(shop_slots[k], key_list[k], KEY_SHOPS[key_list[k]])
	for k in range(key_list.size(), shop_slots.size()):
		if rng.randf() < 0.55:
			_make_shop(shop_slots[k], "", DECOR_SHOPS[rng.randi() % DECOR_SHOPS.size()])
	_build_lamps()
	_build_parked_cars()
	_flush_multimeshes()
	_build_sidewalk_graph()
	spawn_point = Vector3(2 * PITCH + ROAD_HALF + WALK_W * 0.5, 0.2, 2 * PITCH + 20.0)


# ---------------------------------------------------------------- matériaux

func _make_shared_materials() -> void:
	window_material = StandardMaterial3D.new()
	window_material.albedo_color = Color("1d2a33")
	window_material.metallic = 0.6
	window_material.roughness = 0.15
	window_material.emission_enabled = true
	window_material.emission = Color("ffd59a")
	window_material.emission_energy_multiplier = 0.0
	lamp_material = StandardMaterial3D.new()
	lamp_material.albedo_color = Color("fff2d0")
	lamp_material.emission_enabled = true
	lamp_material.emission = Color("ffd9a0")
	lamp_material.emission_energy_multiplier = 0.0


func _noise_tex(freq: float, dark: Color, light: Color) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = true
	var g := Gradient.new()
	g.set_color(0, dark)
	g.set_color(1, light)
	t.color_ramp = g
	return t


## Matériau à grain (triplanaire, aligné sur le monde) pour éviter l'aspect « plastique ».
func mat(hex: String, rough := 0.9, grain := 0.12, scale := 0.25) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [hex, rough, grain]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = rough
	if grain > 0.0:
		m.albedo_texture = _noise_tex(0.02, Color(1.0 - grain, 1.0 - grain, 1.0 - grain), Color.WHITE)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
	_mats[key] = m
	return m


# ---------------------------------------------------------------- géométrie de base

func _box(size: Vector3, pos: Vector3, m: Material, collide := false, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _cyl(r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = maxf(r_top, r_bot)
		shape.height = h
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _label(text: String, pos: Vector3, normal: Vector3, size := 64, color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.008
	l.outline_size = 8
	l.modulate = color
	l.position = pos
	l.rotation.y = atan2(normal.x, normal.z)
	add_child(l)
	return l


# ---------------------------------------------------------------- sol et rues

func _build_ground() -> void:
	var total := GRID * PITCH + PITCH
	var c := GRID * PITCH * 0.5
	var g := _box(Vector3(total + 400.0, 1.0, total + 400.0), Vector3(c, -0.5, c), mat("cdb38a", 1.0, 0.25, 0.08), true)
	g.name = "Sol"


func _build_roads() -> void:
	var length := GRID * PITCH + 2.0 * ROAD_HALF
	var asphalt := mat("4a4642", 0.92, 0.3, 0.15)
	var line := mat("e9e4d4", 0.7, 0.0)
	for k in GRID + 1:
		var c := k * PITCH
		var mid := GRID * PITCH * 0.5
		_box(Vector3(length, 0.04, ROAD_HALF * 2.0), Vector3(mid, 0.02, c), asphalt)
		_box(Vector3(ROAD_HALF * 2.0, 0.041, length), Vector3(c, 0.02, mid), asphalt)
	# pointillés centraux et passages piétons (multimesh)
	var dash := BoxMesh.new()
	dash.size = Vector3(2.0, 0.01, 0.15)
	var xforms: Array[Transform3D] = []
	for k in GRID + 1:
		var c := k * PITCH
		for b in GRID:
			var s := b * PITCH + ROAD_HALF + 4.0
			var e := (b + 1) * PITCH - ROAD_HALF - 4.0
			var p := s
			while p < e:
				xforms.append(Transform3D(Basis(), Vector3(p + 1.0, 0.05, c)))
				xforms.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(c, 0.05, p + 1.0)))
				p += 4.5
	_multimesh(dash, line, xforms)
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.5, 0.01, 2.6)
	var zebra: Array[Transform3D] = []
	for i in GRID + 1:
		for j in GRID + 1:
			var cx := i * PITCH
			var cz := j * PITCH
			for side in [-1.0, 1.0]:
				var off: float = side * (ROAD_HALF + 1.6)
				for t in range(-3, 4):
					var w := t * 1.0
					if j > 0 or side > 0:
						if (side < 0 and j > 0) or (side > 0 and j < GRID):
							zebra.append(Transform3D(Basis(), Vector3(cx + w, 0.05, cz + off)))
					if (side < 0 and i > 0) or (side > 0 and i < GRID):
						zebra.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(cx + off, 0.05, cz + w)))
	_multimesh(stripe, line, zebra)


func _build_sidewalk(x0: float, z0: float, size: float) -> void:
	var full := size + 2.0 * WALK_W
	var c := Vector3(x0 + size * 0.5, 0.07, z0 + size * 0.5)
	_box(Vector3(full, 0.14, full), c, mat("a89c86", 0.95, 0.18, 0.3))
	# bordure
	_box(Vector3(full + 0.1, 0.16, 0.18), c + Vector3(0, 0.01, full * 0.5), mat("8e8577", 0.9, 0.1))
	_box(Vector3(full + 0.1, 0.16, 0.18), c + Vector3(0, 0.01, -full * 0.5), mat("8e8577", 0.9, 0.1))
	_box(Vector3(0.18, 0.16, full + 0.1), c + Vector3(full * 0.5, 0.01, 0), mat("8e8577", 0.9, 0.1))
	_box(Vector3(0.18, 0.16, full + 0.1), c + Vector3(-full * 0.5, 0.01, 0), mat("8e8577", 0.9, 0.1))
	# cour intérieure en sable
	_box(Vector3(size - 0.2, 0.15, size - 0.2), c + Vector3(0, 0.005, 0), mat("d2b98d", 1.0, 0.25, 0.1))


# ---------------------------------------------------------------- pâtés de maisons

func _build_block(x0: float, z0: float, size: float, shop_slots: Array, center_dist: float) -> void:
	var tall := clampf(1.0 - center_dist / 5.0, 0.0, 1.0)  # plus haut vers le centre (Plateau)
	var depth := rng.randf_range(9.0, 12.0)
	# côtés nord / sud sur toute la largeur, est / ouest entre les deux
	var sides := [
		{"start": Vector3(x0, 0, z0), "dir": Vector3.RIGHT, "len": size, "n": Vector3.FORWARD},
		{"start": Vector3(x0, 0, z0 + size), "dir": Vector3.RIGHT, "len": size, "n": Vector3.BACK},
		{"start": Vector3(x0, 0, z0 + depth), "dir": Vector3.BACK, "len": size - 2.0 * depth, "n": Vector3.LEFT},
		{"start": Vector3(x0 + size, 0, z0 + depth), "dir": Vector3.BACK, "len": size - 2.0 * depth, "n": Vector3.RIGHT},
	]
	for sd in sides:
		var length: float = sd.len
		var pos := 0.0
		while pos < length - 0.01:
			var w := rng.randf_range(6.0, 11.0)
			if length - pos - w < 4.5:
				w = length - pos
			var floors := 1 + rng.randi_range(0, 2) + int(round(tall * rng.randf_range(0.0, 5.0)))
			_build_house(sd, pos, w, depth, floors, shop_slots)
			pos += w


func _build_house(sd: Dictionary, pos: float, w: float, depth: float, floors: int, shop_slots: Array) -> void:
	var dir: Vector3 = sd.dir
	var n: Vector3 = sd.n
	var h := floors * FLOOR_H
	# centre du bâtiment : le long du côté, enfoncé de depth/2 vers l'intérieur
	var along: Vector3 = sd.start + dir * (pos + w * 0.5)
	var center := along - n * (depth * 0.5)
	var size := Vector3(w - 0.05, h, depth) if absf(dir.x) > 0.5 else Vector3(depth, h, w - 0.05)
	var wall := mat(WALL_COLORS[rng.randi() % WALL_COLORS.size()], 0.92, 0.14, 0.3)
	_box(size, center + Vector3(0, h * 0.5, 0), wall, true)
	# corniche / acrotère
	var trim := mat("f5f0e6" if rng.randf() < 0.5 else "8d7b63", 0.9, 0.08)
	_box(Vector3(size.x + 0.2, 0.25, size.z + 0.2), center + Vector3(0, h + 0.05, 0), trim)
	_box(Vector3(size.x + 0.1, 0.7, 0.15) if absf(dir.x) > 0.5 else Vector3(0.15, 0.7, size.z + 0.1), along + Vector3(0, h + 0.5, 0) - n * 0.07, wall)
	# toits-terrasses : citerne, fers à béton d'un étage « à finir »
	var roof := center + Vector3(0, h, 0)
	if rng.randf() < 0.35:
		_cyl(0.6, 0.6, 1.3, roof + Vector3(rng.randf_range(-1.5, 1.5), 0.9, rng.randf_range(-1.5, 1.5)), mat("1c1c1c", 0.6, 0.0))
	if rng.randf() < 0.3:
		var steel := mat("5b3a29", 0.7, 0.0)
		for k in 4:
			var off := Vector3((k % 2 - 0.5) * (size.x - 1.0), 0.9, (k / 2 - 0.5) * (size.z - 1.0))
			_cyl(0.04, 0.04, 1.8, roof + off, steel)
	if rng.randf() < 0.25:
		_box(Vector3(2.5, 2.2, 2.5), roof + Vector3(rng.randf_range(-1.0, 1.0), 1.1, rng.randf_range(-1.0, 1.0)), wall)
	# fenêtres et volets côté rue
	var tangent := dir
	var cols := maxi(1, int(w / 3.0))
	for f in range(1, floors):
		for c in cols:
			var t := (c + 0.5) / cols - 0.5
			var p := along + tangent * (t * (w - 1.5)) + Vector3(0, f * FLOOR_H + 1.5, 0) + n * 0.03
			var basis := Basis(Vector3.UP, atan2(n.x, n.z))
			_windows.append(Transform3D(basis, p))
			if rng.randf() < 0.5:
				_shutters.append(Transform3D(basis, p + tangent * 0.8 + n * 0.02))
				_shutters.append(Transform3D(basis, p - tangent * 0.8 + n * 0.02))
		if rng.randf() < 0.25 and f >= 1:
			# petit balcon
			_box(Vector3(w * 0.5, 0.15, 1.0) if absf(dir.x) > 0.5 else Vector3(1.0, 0.15, w * 0.5), along + n * 0.5 + Vector3(0, f * FLOOR_H + 0.1, 0), trim)
	# rez-de-chaussée : porte, ou emplacement de boutique
	if w >= 5.5:
		shop_slots.append({"along": along, "n": n, "dir": dir, "w": w})
	else:
		_box(Vector3(1.1, 2.2, 0.1) if absf(dir.x) > 0.5 else Vector3(0.1, 2.2, 1.1), along + Vector3(0, 1.1, 0) + n * 0.04, mat("5a3b28", 0.8, 0.1))
	if rng.randf() < 0.3:
		_lamps.append(along + n * (WALK_W - 0.4))


func _make_shop(slot: Dictionary, key: String, title: String) -> void:
	var along: Vector3 = slot.along
	var n: Vector3 = slot.n
	var dir: Vector3 = slot.dir
	var w: float = slot.w
	var horiz := absf(dir.x) > 0.5
	var awning_col: String = AWNING_COLORS[rng.randi() % AWNING_COLORS.size()]
	if key == "pharmacie":
		awning_col = "1f7a4d"
	# vitrine / rideau métallique
	_box(Vector3(w - 1.4, 2.4, 0.1) if horiz else Vector3(0.1, 2.4, w - 1.4), along + Vector3(0, 1.25, 0) + n * 0.04, mat("2a3238", 0.35, 0.05))
	# auvent
	var aw := _box(Vector3(w - 1.0, 0.12, 1.5) if horiz else Vector3(1.5, 0.12, w - 1.0), along + n * 0.75 + Vector3(0, 2.75, 0), mat(awning_col, 0.8, 0.1))
	aw.rotation = Vector3((0.12 if n.z > 0 else -0.12) if horiz else 0.0, 0, (-0.12 if n.x > 0 else 0.12) if not horiz else 0.0)
	# enseigne
	_box(Vector3(w - 1.2, 0.9, 0.12) if horiz else Vector3(0.12, 0.9, w - 1.2), along + Vector3(0, 3.5, 0) + n * 0.08, mat("f4efe3", 0.8, 0.05))
	_label(title, along + Vector3(0, 3.5, 0) + n * 0.16, n, 52 if title.length() < 22 else 40, Color("1b1b1b"))
	if key == "pharmacie":
		var cross := mat("2ecc71", 0.5, 0.0)
		cross.emission_enabled = true
		cross.emission = Color("2ecc71")
		cross.emission_energy_multiplier = 1.5
		_box(Vector3(0.9, 0.3, 0.1) if horiz else Vector3(0.1, 0.3, 0.9), along + Vector3(0, 4.4, 0) + n * 0.15, cross)
		_box(Vector3(0.3, 0.9, 0.1) if horiz else Vector3(0.1, 0.9, 0.3), along + Vector3(0, 4.4, 0) + n * 0.15, cross)
	# marchandise sur le trottoir
	if rng.randf() < 0.5:
		for k in 3:
			_box(Vector3(0.5, 0.5, 0.5), along + n * 0.6 + dir * (k * 0.6 - 0.6) + Vector3(0, 0.39, 0), mat(["c8a165", "e74c3c", "3498db", "f1c40f"][k % 4], 0.9, 0.1), true)
	var front := along + n * (WALK_W * 0.5 + 0.3)
	front.y = 0.15
	if key != "":
		places[key] = front
		place_names[key] = title


func _build_square(x0: float, z0: float, size: float) -> void:
	var c := Vector3(x0 + size * 0.5, 0.15, z0 + size * 0.5)
	_box(Vector3(size, 0.02, size), c + Vector3(0, 0.01, 0), mat("c2a878", 1.0, 0.2, 0.2))
	_box(Vector3(size * 0.6, 0.03, size * 0.6), c + Vector3(0, 0.02, 0), mat("6f8f4e", 1.0, 0.3, 0.2))
	# fontaine / monument central
	_cyl(2.6, 3.0, 0.7, c + Vector3(0, 0.35, 0), mat("d9d2c3", 0.8, 0.1), true)
	_cyl(0.5, 0.7, 5.0, c + Vector3(0, 2.5, 0), mat("e8e1d0", 0.7, 0.1), true)
	_label("Place de la Teranga", c + Vector3(0, 1.0, 3.05), Vector3.BACK, 48, Color("3b2a1a"))
	# arbres (neems) et bancs
	for k in 12:
		var a := k * TAU / 12.0
		var p := c + Vector3(cos(a), 0, sin(a)) * (size * 0.38)
		_tree(p, rng.randf() < 0.3)
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var p := c + Vector3(cos(a), 0, sin(a)) * 7.0
		var b := _box(Vector3(2.0, 0.45, 0.5), p + Vector3(0, 0.25, 0), mat("6b4a2e", 0.8, 0.1), true)
		b.rotation.y = -a + PI / 2.0
	places["place"] = c + Vector3(0, 0, 4.5)
	place_names["place"] = "Place de la Teranga"


func _build_market(x0: float, z0: float, size: float) -> void:
	var c := Vector3(x0 + size * 0.5, 0.15, z0 + size * 0.5)
	_box(Vector3(size, 0.02, size), c + Vector3(0, 0.01, 0), mat("b89f78", 1.0, 0.25, 0.2))
	var cloth := ["e74c3c", "f1c40f", "27ae60", "2980b9", "e67e22", "8e44ad", "16a085"]
	var goods := ["e67e22", "c0392b", "f39c12", "27ae60", "d35400", "7f8c8d"]
	for gx in 5:
		for gz in 5:
			if rng.randf() < 0.15:
				continue
			var p := c + Vector3((gx - 2) * 6.0 + rng.randf_range(-0.6, 0.6), 0, (gz - 2) * 6.0 + rng.randf_range(-0.6, 0.6))
			_box(Vector3(2.4, 0.9, 1.3), p + Vector3(0, 0.45, 0), mat("7a5636", 0.9, 0.15), true)
			for k in 3:
				_box(Vector3(0.6, 0.25, 0.9), p + Vector3(-0.75 + k * 0.75, 1.02, 0), mat(goods[rng.randi() % goods.size()], 0.9, 0.2))
			_cyl(0.04, 0.04, 2.4, p + Vector3(0, 1.2, 0.0), mat("444444", 0.5, 0.0))
			var u := _cyl(0.0, 1.9, 0.8, p + Vector3(0, 2.6, 0), mat(cloth[rng.randi() % cloth.size()], 0.9, 0.0))
			u.rotation.z = rng.randf_range(-0.06, 0.06)
	_label("Marché Teranga", c + Vector3(0, 4.5, -size * 0.5 - 0.1), Vector3.FORWARD, 90, Color("f0b93a"))
	places["marche"] = Vector3(c.x, 0.15, z0 - 1.0)
	place_names["marche"] = "Marché Teranga"


func _tree(p: Vector3, palm: bool) -> void:
	if palm:
		_cyl(0.18, 0.26, 7.0, p + Vector3(0, 3.5, 0), mat("7a6248", 1.0, 0.2), true)
		var leaf := mat("3f7a32", 0.9, 0.1)
		for k in 7:
			var l := _box(Vector3(0.6, 0.06, 3.2), p + Vector3(0, 7.0, 0), leaf)
			l.rotation = Vector3(0.5, k * TAU / 7.0, 0)
			l.translate_object_local(Vector3(0, 0, 1.4))
	else:
		_cyl(0.22, 0.32, 3.2, p + Vector3(0, 1.6, 0), mat("5b4636", 1.0, 0.2), true)
		var crown := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(2.2, 3.0)
		sm.height = sm.radius * 1.6
		crown.mesh = sm
		crown.material_override = mat("4c7a35", 0.95, 0.35, 0.6)
		crown.position = p + Vector3(0, 4.4, 0)
		add_child(crown)


# ---------------------------------------------------------------- mobilier urbain, voitures

func _build_lamps() -> void:
	var pole := mat("3c4045", 0.5, 0.0)
	pole.metallic = 0.6
	for p in _lamps:
		_cyl(0.06, 0.09, 5.5, p + Vector3(0, 2.85, 0), pole, true)
		var head := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.15, 0.3)
		head.mesh = bm
		head.material_override = lamp_material
		head.position = p + Vector3(0, 5.6, 0)
		add_child(head)


func _build_parked_cars() -> void:
	for k in 40:
		var i := rng.randi_range(0, GRID)
		var j := rng.randi_range(0, GRID - 1)
		var horizontal := rng.randf() < 0.5
		var t := rng.randf_range(8.0, PITCH - 8.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pos: Vector3
		var ang: float
		if horizontal:
			pos = Vector3(j * PITCH + t, 0, i * PITCH + side * (ROAD_HALF - 1.0))
			ang = 0.0 if side > 0 else PI
		else:
			pos = Vector3(i * PITCH + side * (ROAD_HALF - 1.0), 0, j * PITCH + t)
			ang = PI / 2.0 if side < 0 else -PI / 2.0
		_car(pos, ang, rng.randf() < 0.45)


## Taxi jaune et noir (typique de Dakar) ou voiture particulière.
func _car(pos: Vector3, ang: float, taxi: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = ang
	add_child(root)
	var body_col: String = "f2c230" if taxi else ["8c8c8c", "1f1f1f", "e8e8e8", "7a1d1d", "1f4e79", "4d5d3a"][rng.randi() % 6]
	var paint := mat(body_col, 0.35, 0.0)
	paint.metallic = 0.4
	paint.metallic_specular = 0.7
	var glass := mat("202a33", 0.1, 0.0)
	glass.metallic = 0.8
	_box(Vector3(4.2, 0.75, 1.75), Vector3(0, 0.62, 0), paint, true, root)
	_box(Vector3(2.2, 0.6, 1.6), Vector3(-0.3, 1.27, 0), glass, false, root)
	_box(Vector3(2.0, 0.07, 1.5), Vector3(-0.35, 1.6, 0), paint, false, root)
	if taxi:
		var black := mat("111111", 0.4, 0.0)
		_box(Vector3(4.22, 0.18, 1.77), Vector3(0, 0.7, 0), black, false, root)
		_box(Vector3(0.6, 0.22, 0.35), Vector3(-0.3, 1.75, 0), mat("f7f1dc", 0.6, 0.0), false, root)
	var tyre := mat("151515", 0.9, 0.0)
	for x in [-1.35, 1.35]:
		for z in [-0.82, 0.82]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.33
			cm.bottom_radius = 0.33
			cm.height = 0.24
			w.mesh = cm
			w.material_override = tyre
			w.position = Vector3(x, 0.33, z)
			w.rotation.x = PI / 2.0
			root.add_child(w)


# ---------------------------------------------------------------- instanciation groupée

func _multimesh(mesh: Mesh, m: Material, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	add_child(mmi)


func _flush_multimeshes() -> void:
	var wm := BoxMesh.new()
	wm.size = Vector3(1.1, 1.4, 0.08)
	_multimesh(wm, window_material, _windows)
	var sm := BoxMesh.new()
	sm.size = Vector3(0.5, 1.45, 0.06)
	_multimesh(sm, mat("2f6f5e", 0.8, 0.1), _shutters)


# ---------------------------------------------------------------- graphe des trottoirs

func _build_sidewalk_graph() -> void:
	var index := {}
	var off := ROAD_HALF + WALK_W * 0.5
	for j in GRID:
		for i in GRID:
			var cx := i * PITCH
			var cz := j * PITCH
			var corners := [Vector3(cx + off, 0.15, cz + off), Vector3(cx + PITCH - off, 0.15, cz + off),
				Vector3(cx + PITCH - off, 0.15, cz + PITCH - off), Vector3(cx + off, 0.15, cz + PITCH - off)]
			var ids := []
			for p in corners:
				var key := Vector2i(roundi(p.x), roundi(p.z))
				if not index.has(key):
					index[key] = sidewalk_nodes.size()
					sidewalk_nodes.append(p)
					sidewalk_links.append([])
				ids.append(index[key])
			for k in 4:
				_link(ids[k], ids[(k + 1) % 4])
	# passages piétons : relier les coins qui se font face de part et d'autre d'une rue
	var keys := index.keys()
	for a in keys:
		for d in [Vector2i(roundi(2.0 * off), 0), Vector2i(0, roundi(2.0 * off))]:
			var b: Vector2i = a + d
			if index.has(b):
				_link(index[a], index[b])


func _link(a: int, b: int) -> void:
	if not sidewalk_links[a].has(b):
		sidewalk_links[a].append(b)
	if not sidewalk_links[b].has(a):
		sidewalk_links[b].append(a)


func random_sidewalk_node() -> int:
	return rng.randi() % sidewalk_nodes.size()


## Point aléatoire sur un trottoir, à une distance comprise entre min_d et max_d de `from`.
func sidewalk_point_near(from: Vector3, min_d: float, max_d: float) -> Vector3:
	for attempt in 200:
		var a := sidewalk_nodes[randi() % sidewalk_nodes.size()]
		var links: Array = sidewalk_links[sidewalk_nodes.find(a)]
		var b := sidewalk_nodes[links.pick_random()]
		var p := a.lerp(b, randf_range(0.2, 0.8))
		var d := p.distance_to(from)
		if d >= min_d and d <= max_d:
			return p
	return from


## Allume fenêtres et lampadaires selon la nuit (0 = jour, 1 = nuit).
func set_night(night: float) -> void:
	window_material.emission_energy_multiplier = clampf((night - 0.3) * 2.0, 0.0, 1.0) * 0.9
	lamp_material.emission_energy_multiplier = 4.0 if night > 0.45 else 0.0
