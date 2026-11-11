extends Node3D
## Construit le vrai centre de Dakar (Plateau, Médina…) à partir des données OpenStreetMap
## converties par tools/osm_to_game.py : bâtiments à leur vraie forme, rues et trottoirs,
## côte et océan, parcs, arbres, lampadaires qui éclairent la nuit, véhicules garés.
## Données : © les contributeurs OpenStreetMap (ODbL).
##
## Même interface que l'ancien générateur : places, place_names, sidewalk_nodes,
## sidewalk_links, spawn_point, random_sidewalk_node(), sidewalk_point_near(), set_night().

const Vehicles = preload("res://scripts/world/vehicles.gd")
const MAP_PATH := "res://data/map/dakar_centre.json"
const BUILDING_SHADER := preload("res://scripts/world/building.gdshader")
const CHUNK := 300.0
const FLOOR_H := 3.2
const WALK_W := 2.4        # largeur des trottoirs
const WALK_H := 0.15       # hauteur des trottoirs
const JUNCTION_CUT := 8.0  # on interrompt les trottoirs aux carrefours
const MAX_VEHICLES := 260
const LAMP_LIGHTS := 18    # lampes réellement éclairantes autour du joueur

var places := {}
var place_names := {}
var sidewalk_nodes: Array[Vector3] = []
var sidewalk_links: Array = []
var spawn_point := Vector3.ZERO
var focus: Node3D = null   # le joueur (pour placer les lumières des lampadaires)
var landmarks: Array = []  # [nom, position]

var rng := RandomNumberGenerator.new()
var data: Dictionary
var _chunks := {}
var _lamps: Array[Vector3] = []
var _lamp_lights: Array[OmniLight3D] = []
var _lamp_timer := 0.0
var _night := 0.0
var _trees: Array[Transform3D] = []
var _tanks: Array[Transform3D] = []
var _pois: Array = []
var building_mat: ShaderMaterial
var lamp_material: StandardMaterial3D
var window_material: StandardMaterial3D   # compatibilité


static func available() -> bool:
	return FileAccess.file_exists(MAP_PATH)


func build() -> void:
	rng.seed = 2210
	data = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	_make_materials()
	_build_ground()
	_build_roads()
	_build_buildings()
	_build_areas()
	_flush_chunks()
	_build_props()
	_build_lamp_lights()
	_assign_places()
	_build_labels()
	print("Dakar : %d bâtiments, %d rues, %d véhicules garés, %d arbres, %d lampadaires" % [data.buildings.size(), data.roads.size(), _park_vehicles.size(), _trees.size(), _lamps.size()])


# ---------------------------------------------------------------- matériaux

func _tex(name: String) -> Texture2D:
	var p := "res://assets/textures/%s.jpg" % name
	return load(p) if ResourceLoader.exists(p) else null


func _pbr(base: String, tint: Color, scale: float, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _tex(base + "_albedo")
	m.normal_enabled = m.albedo_texture != null
	m.normal_texture = _tex(base + "_normal")
	m.roughness_texture = _tex(base + "_roughness")
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


var mat_ground: StandardMaterial3D
var mat_road: StandardMaterial3D
var mat_walk: StandardMaterial3D
var mat_roof: StandardMaterial3D
var mat_park: StandardMaterial3D
var mat_line: StandardMaterial3D
var mat_water: StandardMaterial3D


func _make_materials() -> void:
	mat_ground = _pbr("sand", Color(1.0, 0.95, 0.88), 0.12)
	mat_road = _pbr("asphalt", Color(0.9, 0.9, 0.9), 0.14)
	mat_walk = _pbr("pavers", Color(0.95, 0.92, 0.86), 0.4)
	mat_roof = _pbr("dirty_concrete", Color(0.75, 0.72, 0.68), 0.15)
	mat_park = _pbr("sand", Color(0.42, 0.62, 0.3), 0.12)
	mat_line = StandardMaterial3D.new()
	mat_line.albedo_color = Color(0.92, 0.9, 0.82)
	mat_line.roughness = 0.7
	mat_water = StandardMaterial3D.new()
	mat_water.albedo_color = Color(0.07, 0.25, 0.33)
	mat_water.metallic = 0.3
	mat_water.roughness = 0.06
	building_mat = ShaderMaterial.new()
	building_mat.shader = BUILDING_SHADER
	building_mat.set_shader_parameter("wall_tex", _tex("wall_plaster_albedo"))
	building_mat.set_shader_parameter("wall_nrm", _tex("wall_plaster_normal"))
	building_mat.set_shader_parameter("wall_rough", _tex("wall_plaster_roughness"))
	building_mat.set_shader_parameter("shutter_tex", _tex("corrugated_albedo"))
	lamp_material = StandardMaterial3D.new()
	lamp_material.albedo_color = Color(1.0, 0.95, 0.85)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.82, 0.55)
	lamp_material.emission_energy_multiplier = 0.0
	window_material = lamp_material


# ---------------------------------------------------------------- tampons de géométrie par zone

class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, u2 := Vector2.ZERO, color := Color.WHITE) -> void:
		v.append_array([a, b, c])
		n.append_array([nrm, nrm, nrm])
		uv.append_array([ua, ub, uc])
		uv2.append_array([u2, u2, u2])
		col.append_array([color, color, color])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO, u2 := Vector2.ZERO, color := Color.WHITE) -> void:
		tri(a, b, c, nrm, ua, ub, uc, u2, color)
		tri(a, c, d, nrm, ua, uc, ud, u2, color)

	func mesh(m: Material) -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_COLOR] = col
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(0, m)
		return am


func _chunk(p: Vector2) -> Dictionary:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	if not _chunks.has(key):
		_chunks[key] = {"walls": Buf.new(), "roofs": Buf.new(), "roads": Buf.new(), "walks": Buf.new(), "lines": Buf.new(), "parks": Buf.new(), "coll": PackedVector3Array()}
	return _chunks[key]


func _flush_chunks() -> void:
	for key in _chunks:
		var c: Dictionary = _chunks[key]
		var node := Node3D.new()
		node.name = "Zone_%d_%d" % [key.x, key.y]
		add_child(node)
		for part in [["walls", building_mat, true], ["roofs", mat_roof, true], ["roads", mat_road, false], ["walks", mat_walk, false], ["lines", mat_line, false], ["parks", mat_park, false]]:
			var b: Buf = c[part[0]]
			if b.v.is_empty():
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = b.mesh(part[1])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if part[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 1600.0 if part[0] == "walls" or part[0] == "roofs" else 700.0
			node.add_child(mi)
		var coll: PackedVector3Array = c.coll
		if not coll.is_empty():
			var body := StaticBody3D.new()
			body.collision_layer = 1
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(coll)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			node.add_child(body)


# ---------------------------------------------------------------- sol, côte, océan

func _build_ground() -> void:
	var land: Dictionary = data.land
	var cell: float = land.cell
	var x0: float = land.x0
	var z0: float = land.z0
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var buf := Buf.new()
	var rows: Array = land.rows
	for j in rows.size():
		var runs: Array = rows[j]
		for k in range(0, runs.size(), 2):
			var a := x0 + float(runs[k]) * cell
			var b := a + float(runs[k + 1]) * cell
			var za := z0 + j * cell
			var zb := za + cell
			buf.quad(Vector3(a, 0, za), Vector3(b, 0, za), Vector3(b, 0, zb), Vector3(a, 0, zb), Vector3.UP)
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(b - a, 2.0, cell)
			cs.shape = box
			cs.position = Vector3((a + b) * 0.5, -1.0, za + cell * 0.5)
			body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = buf.mesh(mat_ground)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# océan
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30000, 30000)
	sea.mesh = pm
	sea.material_override = mat_water
	sea.position = Vector3(0, -0.35, 0)
	add_child(sea)


# ---------------------------------------------------------------- rues et trottoirs

const ROAD_Y := {"trunk": 0.05, "primary": 0.048, "secondary": 0.046, "tertiary": 0.044, "unclassified": 0.04,
	"residential": 0.04, "living_street": 0.038, "pedestrian": 0.036, "service": 0.034, "footway": 0.03, "path": 0.03, "steps": 0.03}
const WITH_SIDEWALK := ["trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "primary_link", "secondary_link", "tertiary_link", "living_street"]


func _pts(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		var p := Vector2(flat[i], flat[i + 1])
		if out.is_empty() or out[-1].distance_to(p) > 0.3:
			out.append(p)
	return out


func _build_roads() -> void:
	var degree := {}
	for r in data.roads:
		for id in r.get("id", []):
			degree[id] = degree.get(id, 0) + 1
	var sw_graph_ends: Array = []
	for r in data.roads:
		var pts := _pts(r.p)
		if pts.size() < 2:
			continue
		var t: String = r.t
		var hw: float = float(r.w) * 0.5
		var y: float = ROAD_Y.get(t, 0.04)
		var mat_buf := "roads" if t != "footway" and t != "path" and t != "steps" and t != "pedestrian" else "walks"
		# chaussée : segments + disques aux jonctions
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var d := (b - a).normalized()
			var nrm := Vector2(-d.y, d.x) * hw
			var c := _chunk((a + b) * 0.5)
			c[mat_buf].quad(_v(a + nrm, y), _v(b + nrm, y), _v(b - nrm, y), _v(a - nrm, y), Vector3.UP)
		for p in pts:
			var c := _chunk(p)
			for k in 10:
				var a0 := TAU * k / 10.0
				var a1 := TAU * (k + 1) / 10.0
				c[mat_buf].tri(_v(p, y - 0.001), _v(p + Vector2(cos(a0), sin(a0)) * hw, y - 0.001), _v(p + Vector2(cos(a1), sin(a1)) * hw, y - 0.001), Vector3.UP)
		# marquage central pour les grandes rues
		if hw >= 4.5 and t != "pedestrian":
			_dashes(pts, y + 0.004)
		# trottoirs
		if t in WITH_SIDEWALK:
			var ids: Array = r.get("id", [])
			var cum := _cumulative(pts)
			var cuts: Array = []
			for i in pts.size():
				if i < ids.size() and degree.get(ids[i], 0) >= 2:
					cuts.append(cum[i])
			if ids.is_empty() or (ids.size() > 0 and degree.get(ids[0], 0) < 2):
				pass
			var intervals := _intervals(cum[-1], cuts, JUNCTION_CUT + hw * 0.3)
			for iv in intervals:
				var seg := _slice(pts, cum, iv.x, iv.y)
				if seg.size() < 2:
					continue
				for side in [-1.0, 1.0]:
					_sidewalk(seg, hw, side, sw_graph_ends, t)


func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


func _cumulative(pts: PackedVector2Array) -> PackedFloat32Array:
	var c := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		c.append(c[-1] + pts[i].distance_to(pts[i - 1]))
	return c


func _intervals(total: float, cuts: Array, gap: float) -> Array:
	var out: Array = []
	var s := 0.0
	cuts.sort()
	for c in cuts:
		var e: float = c - gap
		if e - s > 3.0:
			out.append(Vector2(s, e))
		s = maxf(s, c + gap)
	if total - s > 3.0:
		out.append(Vector2(s, total))
	return out


func _at(pts: PackedVector2Array, cum: PackedFloat32Array, d: float) -> Vector2:
	for i in range(1, pts.size()):
		if cum[i] >= d:
			var f := (d - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.001)
			return pts[i - 1].lerp(pts[i], f)
	return pts[-1]


func _slice(pts: PackedVector2Array, cum: PackedFloat32Array, s: float, e: float) -> PackedVector2Array:
	var out := PackedVector2Array([_at(pts, cum, s)])
	for i in pts.size():
		if cum[i] > s and cum[i] < e:
			out.append(pts[i])
	out.append(_at(pts, cum, e))
	return out


func _dashes(pts: PackedVector2Array, y: float) -> void:
	var cum := _cumulative(pts)
	var d := 4.0
	while d < cum[-1] - 4.0:
		var a := _at(pts, cum, d)
		var b := _at(pts, cum, d + 2.5)
		var dir := (b - a).normalized()
		var n := Vector2(-dir.y, dir.x) * 0.07
		_chunk(a)["lines"].quad(_v(a + n, y), _v(b + n, y), _v(b - n, y), _v(a - n, y), Vector3.UP)
		d += 6.0


func _offset_line(seg: PackedVector2Array, off: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in seg.size():
		var d0 := (seg[i] - seg[max(i - 1, 0)]).normalized() if i > 0 else (seg[1] - seg[0]).normalized()
		var d1 := (seg[min(i + 1, seg.size() - 1)] - seg[i]).normalized() if i < seg.size() - 1 else d0
		var d := (d0 + d1).normalized()
		if d == Vector2.ZERO:
			d = d0
		var n := Vector2(-d.y, d.x)
		var scale := 1.0 / maxf(0.5, n.dot(Vector2(-d0.y, d0.x)))
		out.append(seg[i] + n * off * scale)
	return out


func _sidewalk(seg: PackedVector2Array, hw: float, side: float, ends: Array, road_type: String) -> void:
	var inner := _offset_line(seg, side * hw)
	var outer := _offset_line(seg, side * (hw + WALK_W))
	var mid := _offset_line(seg, side * (hw + WALK_W * 0.5))
	var y := WALK_H
	for i in seg.size() - 1:
		var c := _chunk(seg[i])
		var a := inner[i]
		var b := inner[i + 1]
		var d := outer[i + 1]
		var e := outer[i]
		c.walks.quad(_v(a, y), _v(b, y), _v(d, y), _v(e, y), Vector3.UP)
		# bordure (face verticale côté rue) et face extérieure
		var nin := Vector3(-(b - a).normalized().y, 0, (b - a).normalized().x) * -side
		c.walks.quad(_v(a, 0.0), _v(b, 0.0), _v(b, y), _v(a, y), nin)
		c.walks.quad(_v(e, 0.0), _v(d, 0.0), _v(d, y), _v(e, y), -nin)
		var coll: PackedVector3Array = c.coll
		coll.append_array([_v(a, y), _v(b, y), _v(d, y), _v(a, y), _v(d, y), _v(e, y)])
		coll.append_array([_v(a, 0.0), _v(b, 0.0), _v(b, y), _v(a, 0.0), _v(b, y), _v(a, y)])
		c.coll = coll
	# lampadaires, arbres
	var cum := _cumulative(mid)
	var lamp_off := hw + WALK_W - 0.35
	var lamp_line := _offset_line(seg, side * lamp_off)
	var lcum := _cumulative(lamp_line)
	var d0 := 6.0 if side > 0 else 21.0
	while d0 < lcum[-1] - 3.0:
		var p := _at(lamp_line, lcum, d0)
		_lamps.append(Vector3(p.x, WALK_H, p.y))
		d0 += 30.0
	if road_type in ["primary", "secondary", "tertiary", "trunk"]:
		var tree_line := _offset_line(seg, side * (hw + WALK_W - 0.9))
		var tcum := _cumulative(tree_line)
		var dt := 12.0
		while dt < tcum[-1] - 4.0:
			if rng.randf() < 0.55:
				var p := _at(tree_line, tcum, dt)
				_add_tree(Vector3(p.x, WALK_H, p.y))
			dt += rng.randf_range(10.0, 18.0)
	# graphe des passants : points tous les ~12 m le long du trottoir
	var count := maxi(2, int(cum[-1] / 12.0) + 1)
	var first := sidewalk_nodes.size()
	for k in count:
		var p := _at(mid, cum, cum[-1] * k / (count - 1))
		sidewalk_nodes.append(Vector3(p.x, WALK_H, p.y))
		sidewalk_links.append([])
		if k > 0:
			_link(first + k - 1, first + k)
	ends.append(first)
	ends.append(first + count - 1)
	# véhicules garés le long du trottoir (côté chaussée)
	if road_type in ["residential", "tertiary", "unclassified", "secondary", "living_street"] and _vehicle_count < MAX_VEHICLES:
		var park_line := _offset_line(seg, side * (hw - 1.15))
		var pcum := _cumulative(park_line)
		var dp := rng.randf_range(4.0, 12.0)
		while dp < pcum[-1] - 6.0 and _vehicle_count < MAX_VEHICLES:
			if rng.randf() < 0.5:
				var p := _at(park_line, pcum, dp)
				var q := _at(park_line, pcum, dp + 1.0)
				var dir := q - p
				var kind := _pick_vehicle()
				_park_vehicles.append([Vector3(p.x, 0.04, p.y), atan2(-dir.y, dir.x) + (PI if side < 0 else 0.0), kind])
				_vehicle_count += 1
				dp += Vehicles.size_of(kind).x + rng.randf_range(1.0, 14.0)
			else:
				dp += rng.randf_range(6.0, 20.0)


var _vehicle_count := 0
var _park_vehicles: Array = []


## Répartition des véhicules garés : vrais modèles quand ils sont présents, sinon modèles en code.
const VEHICLE_MIX := [["taxi_sn", 24], ["p405", 14], ["car_rapide_3d", 10], ["clando", 8], ["ndiaga", 6], ["sedan_3d", 9],
	["wagon_3d", 7], ["jakarta", 7], ["jetta", 4], ["crafter", 3], ["taxi", 4], ["car", 4]]
var _vehicle_used := {}


func _pick_vehicle() -> String:
	var total := 0
	for e in VEHICLE_MIX:
		total += e[1]
	for attempt in 10:
		var r := rng.randi() % total
		for e in VEHICLE_MIX:
			r -= e[1]
			if r < 0:
				var kind: String = e[0]
				if Vehicles.MODELS.has(kind):
					if not Vehicles.has_model(kind):
						break   # modèle absent : on retire au sort
					var mx: int = Vehicles.MODELS[kind].get("max", 100000)
					if _vehicle_used.get(kind, 0) >= mx:
						break
				_vehicle_used[kind] = _vehicle_used.get(kind, 0) + 1
				return kind
	return ["taxi", "car", "car_rapide", "ndiaga"][rng.randi() % 4]


func _link(a: int, b: int) -> void:
	if a == b:
		return
	if not sidewalk_links[a].has(b):
		sidewalk_links[a].append(b)
	if not sidewalk_links[b].has(a):
		sidewalk_links[b].append(a)


# ---------------------------------------------------------------- bâtiments

const PALETTE_PLATEAU := [Color("efe9dc"), Color("e6dccb"), Color("d9cdb6"), Color("f4f1ea"), Color("cfc5b4"), Color("e9d9b8"), Color("d6c7a8"), Color("c9d3d6")]
const PALETTE_MEDINA := [Color("e3c79a"), Color("d9a86c"), Color("f0e4c8"), Color("c97b5a"), Color("9fc2b8"), Color("e3c16f"), Color("b7c7d9"), Color("d88a7a"), Color("efe3c8")]


func _levels(b: Dictionary, area: float, center: Vector2) -> int:
	if b.has("l"):
		return clampi(int(b.l), 1, 30)
	var plateau := center.y > -650.0
	if plateau:
		if area > 900.0 and rng.randf() < 0.2:
			return rng.randi_range(8, 14)
		if area > 500.0:
			return rng.randi_range(4, 8)
		if area > 150.0:
			return rng.randi_range(3, 6)
		return rng.randi_range(2, 4)
	if area > 400.0:
		return rng.randi_range(2, 4)
	return rng.randi_range(1, 3)


func _build_buildings() -> void:
	for b in data.buildings:
		var poly := _pts(b.p)
		if poly.size() >= 2 and poly[0].distance_to(poly[-1]) < 0.3:
			poly.remove_at(poly.size() - 1)
		if poly.size() < 3:
			continue
		var area := absf(_signed_area(poly))
		var perim := 0.0
		for i in poly.size():
			perim += poly[i].distance_to(poly[(i + 1) % poly.size()])
		if area < 12.0 or area / perim < 1.0:
			continue   # forme trop fine (mur, clôture) : ce n'est pas un vrai bâtiment
		var center := Vector2.ZERO
		for p in poly:
			center += p
		center /= poly.size()
		var kind: String = b.get("k", "")
		var lv := _levels(b, area, center)
		if kind == "mosque":
			lv = 2
		var h := lv * FLOOR_H + 0.6
		var plateau := center.y > -650.0
		var pal: Array = PALETTE_PLATEAU if plateau else PALETTE_MEDINA
		var tint: Color = pal[rng.randi() % pal.size()]
		if kind == "mosque":
			tint = Color("f4f1ea")
		var seed := rng.randf()
		var c := _chunk(center)
		var walls: Buf = c.walls
		var coll: PackedVector3Array = c.coll
		for i in poly.size():
			var a := poly[i]
			var bb := poly[(i + 1) % poly.size()]
			var len := a.distance_to(bb)
			if len < 0.05:
				continue
			var d := (bb - a) / len
			var n := Vector2(-d.y, d.x)
			if n.dot((a + bb) * 0.5 - center) < 0.0:
				n = -n
			var nrm := Vector3(n.x, 0, n.y)
			var col := Color(tint.r, tint.g, tint.b, seed)
			walls.quad(_v(a, 0.0), _v(bb, 0.0), _v(bb, h), _v(a, h), nrm,
				Vector2(0, 0), Vector2(len, 0), Vector2(len, h), Vector2(0, h), Vector2(len, h), col)
			coll.append_array([_v(a, 0.0), _v(bb, 0.0), _v(bb, h), _v(a, 0.0), _v(bb, h), _v(a, h)])
		c.coll = coll
		# toit (en retrait de l'acrotère)
		var tris := Geometry2D.triangulate_polygon(poly)
		var roof_y := h - 0.6
		var roofs: Buf = c.roofs
		for k in range(0, tris.size(), 3):
			roofs.tri(_v(poly[tris[k]], roof_y), _v(poly[tris[k + 1]], roof_y), _v(poly[tris[k + 2]], roof_y), Vector3.UP)
		# équipements de toit (citernes)
		if area > 40.0 and area < 900.0 and rng.randf() < 0.35 and not tris.is_empty():
			_tanks.append(Transform3D(Basis(), Vector3(center.x, roof_y + 0.6, center.y)))
		if kind == "mosque" and area > 150.0:
			_mosque_details(poly, center, h, area)
		if kind in ["marketplace"] or (b.get("n", "") as String).begins_with("Marché"):
			landmarks.append([b.n if b.has("n") else "Marché", Vector3(center.x, h + 6.0, center.y)])
		elif b.has("n") and area > 600.0:
			landmarks.append([b.n, Vector3(center.x, h + 4.0, center.y)])


func _signed_area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


func _mosque_details(poly: PackedVector2Array, center: Vector2, h: float, area: float) -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("f4f1ea")
	white.roughness = 0.6
	var green := StandardMaterial3D.new()
	green.albedo_color = Color("1f7a4d")
	green.roughness = 0.4
	green.metallic = 0.3
	# dôme
	var r := clampf(sqrt(area) * 0.25, 3.0, 12.0)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.is_hemisphere = true
	dome.mesh = sm
	dome.material_override = green
	dome.position = Vector3(center.x, h - 0.6, center.y)
	add_child(dome)
	# minaret au coin le plus éloigné du centre
	var far := poly[0]
	for p in poly:
		if p.distance_to(center) > far.distance_to(center):
			far = p
	var tip := far.lerp(center, 0.12)
	var mh := h + 18.0 + area * 0.004
	for part in [[1.6, 1.8, mh, mh * 0.5, white], [2.2, 2.2, 0.8, mh * 0.72, white], [1.2, 1.4, mh * 0.2, mh + mh * 0.1, white], [0.0, 1.3, 3.0, mh * 1.2 + 1.5, green]]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = part[0]
		cm.bottom_radius = part[1]
		cm.height = part[2]
		cm.radial_segments = 12
		mi.mesh = cm
		mi.material_override = part[4]
		mi.position = Vector3(tip.x, part[3], tip.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)


# ---------------------------------------------------------------- parcs, places

func _build_areas() -> void:
	for a in data.areas:
		var poly := _pts(a.p)
		if poly.size() >= 2 and poly[0].distance_to(poly[-1]) < 0.3:
			poly.remove_at(poly.size() - 1)
		if poly.size() < 3:
			continue
		var k: String = a.k
		var tris := Geometry2D.triangulate_polygon(poly)
		var green := k in ["park", "garden", "grass", "pitch", "recreation_ground", "stadium", "cemetery", "wood", "scrub"]
		var center := Vector2.ZERO
		for p in poly:
			center += p
		center /= poly.size()
		var buf: Buf = _chunk(center)["parks" if green else "walks"]
		var y := 0.02 if green else 0.025
		for i in range(0, tris.size(), 3):
			buf.tri(_v(poly[tris[i]], y), _v(poly[tris[i + 1]], y), _v(poly[tris[i + 2]], y), Vector3.UP)
		if green and k != "pitch":
			var area := absf(_signed_area(poly))
			var n := mini(int(area / 160.0), 120)
			var minv := poly[0]
			var maxv := poly[0]
			for p in poly:
				minv = minv.min(p)
				maxv = maxv.max(p)
			for t in n * 3:
				if n <= 0:
					break
				var p := Vector2(rng.randf_range(minv.x, maxv.x), rng.randf_range(minv.y, maxv.y))
				if Geometry2D.is_point_in_polygon(p, poly):
					_add_tree(Vector3(p.x, 0.0, p.y))
					n -= 1
		if a.has("n"):
			landmarks.append([a.n, Vector3(center.x, 8.0, center.y)])


func _add_tree(p: Vector3) -> void:
	var s := rng.randf_range(0.8, 1.3)
	_trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))


# ---------------------------------------------------------------- objets répétés (multimesh)

func _multimesh(mesh: Mesh, m: Material, xforms: Array[Transform3D], shadows := true) -> void:
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
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_props() -> void:
	# arbres (neems) : tronc + houppier
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.3
	trunk.height = 3.4
	trunk.radial_segments = 8
	var trunk_x: Array[Transform3D] = []
	var crown_x: Array[Transform3D] = []
	for t in _trees:
		trunk_x.append(t.translated(Vector3(0, 1.7, 0)))
		crown_x.append(Transform3D(t.basis.scaled(Vector3(1.0, 0.75, 1.0)), t.origin + Vector3(0, 4.3 * t.basis.get_scale().y, 0)))
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color("5b4636")
	bark.roughness = 1.0
	_multimesh(trunk, bark, trunk_x)
	var crown := SphereMesh.new()
	crown.radius = 2.6
	crown.height = 4.2
	crown.radial_segments = 12
	crown.rings = 6
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color("496f33")
	leaves.roughness = 0.9
	leaves.albedo_texture = _tex("sand_albedo")
	leaves.uv1_triplanar = true
	leaves.uv1_world_triplanar = true
	leaves.uv1_scale = Vector3.ONE * 0.5
	_multimesh(crown, leaves, crown_x)
	# lampadaires
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.1
	pole.height = 7.0
	pole.radial_segments = 6
	var arm := BoxMesh.new()
	arm.size = Vector3(1.4, 0.08, 0.08)
	var head := BoxMesh.new()
	head.size = Vector3(0.6, 0.14, 0.32)
	var pole_x: Array[Transform3D] = []
	var arm_x: Array[Transform3D] = []
	var head_x: Array[Transform3D] = []
	for p in _lamps:
		pole_x.append(Transform3D(Basis(), p + Vector3(0, 3.5, 0)))
		arm_x.append(Transform3D(Basis(), p + Vector3(0, 7.0, 0)))
		head_x.append(Transform3D(Basis(), p + Vector3(0, 6.9, 0)))
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("3a3d40")
	metal.metallic = 0.6
	metal.roughness = 0.45
	_multimesh(pole, metal, pole_x)
	_multimesh(arm, metal, arm_x, false)
	_multimesh(head, lamp_material, head_x, false)
	# citernes sur les toits
	var tank := CylinderMesh.new()
	tank.top_radius = 0.6
	tank.bottom_radius = 0.6
	tank.height = 1.3
	var tank_m := StandardMaterial3D.new()
	tank_m.albedo_color = Color("1c1c1c")
	tank_m.roughness = 0.6
	_multimesh(tank, tank_m, _tanks)
	# véhicules garés
	var vrng := RandomNumberGenerator.new()
	vrng.seed = 77
	for v in _park_vehicles:
		var node := Vehicles.make(v[2], vrng)
		node.position = v[0]
		node.rotation.y = v[1]
		if not Vehicles.MODELS.has(v[2]):
			for mi in node.find_children("*", "GeometryInstance3D", true, false):
				mi.visibility_range_end = 260.0
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var sz := Vehicles.size_of(v[2])
		box.size = sz
		cs.shape = box
		cs.position = Vector3(0, sz.y * 0.5, 0)
		body.add_child(cs)
		node.add_child(body)
		add_child(node)


# ---------------------------------------------------------------- lumière des lampadaires

func _build_lamp_lights() -> void:
	for k in LAMP_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.55)
		l.omni_range = 16.0
		l.omni_attenuation = 1.2
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		_lamp_lights.append(l)


func _process(delta: float) -> void:
	_lamp_timer -= delta
	if _lamp_timer > 0.0 or focus == null:
		return
	_lamp_timer = 0.35
	if _night < 0.3:
		for l in _lamp_lights:
			l.visible = false
		return
	var p := focus.global_position
	var near: Array = []
	for lp in _lamps:
		var d := Vector2(lp.x - p.x, lp.z - p.z).length_squared()
		if d < 90.0 * 90.0:
			near.append([d, lp])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for k in _lamp_lights.size():
		var l := _lamp_lights[k]
		if k < near.size():
			l.visible = true
			l.global_position = near[k][1] + Vector3(0, 6.6, 0)
			l.light_energy = 2.6 * clampf((_night - 0.3) * 2.0, 0.0, 1.0)
		else:
			l.visible = false


# ---------------------------------------------------------------- lieux des missions

const PLACE_KINDS := {
	"boulangerie": ["shop:bakery", "shop:pastry"],
	"pharmacie": ["pharmacy"],
	"dibiterie": ["fast_food", "restaurant"],
	"telecentre": ["shop:mobile_phone", "shop:telecommunication", "shop:computer", "shop:electronics"],
	"tailleur": ["shop:sewing", "shop:tailor", "shop:fabric", "shop:clothes"],
	"garage": ["shop:car_repair", "shop:car_parts", "fuel"],
	"boutique": ["shop:convenience", "shop:kiosk", "shop:general", "shop:supermarket"],
	"marche": ["marketplace"],
}
const DEFAULT_NAMES := {"boulangerie": "Boulangerie", "pharmacie": "Pharmacie", "dibiterie": "Dibiterie Chez Pathé",
	"telecentre": "Télécentre", "tailleur": "Couture", "garage": "Garage", "boutique": "Boutique Keur Mame", "marche": "Marché Sandaga", "place": "Place de l'Indépendance"}


func _nearest_node(p: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in sidewalk_nodes.size():
		var d := sidewalk_nodes[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _assign_places() -> void:
	_connect_sidewalk_gaps()
	var origin := Vector3.ZERO
	var start := _nearest_node(origin)
	spawn_point = sidewalk_nodes[start] + Vector3(0, 0.1, 0)
	places["place"] = spawn_point
	place_names["place"] = DEFAULT_NAMES.place
	for key in PLACE_KINDS:
		var best = null
		var bd := INF
		for poi in data.pois:
			if not (poi.k in PLACE_KINDS[key]):
				continue
			var p := Vector3(poi.x, 0.0, poi.z)
			var d := p.distance_to(spawn_point)
			if d < 90.0 or d > 1300.0:
				continue
			if d < bd:
				bd = d
				best = poi
		if key == "marche":
			for b in data.buildings:
				if (b.get("n", "") as String) == "Marché Sandaga":
					best = {"x": b.p[0], "z": b.p[1], "n": "Marché Sandaga"}
		var target: Vector3
		if best == null:
			target = sidewalk_point_near(spawn_point, 150.0, 600.0)
			place_names[key] = DEFAULT_NAMES[key]
		else:
			target = Vector3(best.x, 0.0, best.z)
			var nm: String = best.get("n", "")
			place_names[key] = nm if nm != "" else DEFAULT_NAMES[key]
		var node := _nearest_node(target)
		places[key] = sidewalk_nodes[node]
		landmarks.append([place_names[key], sidewalk_nodes[node] + Vector3(0, 3.2, 0)])


## Relie les bouts de trottoir proches (traversées aux carrefours) et supprime les nœuds isolés.
func _connect_sidewalk_gaps() -> void:
	var grid := {}
	for i in sidewalk_nodes.size():
		var p := sidewalk_nodes[i]
		var key := Vector2i(floori(p.x / 20.0), floori(p.z / 20.0))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	for i in sidewalk_nodes.size():
		if sidewalk_links[i].size() >= 2:
			continue
		var p := sidewalk_nodes[i]
		var key := Vector2i(floori(p.x / 20.0), floori(p.z / 20.0))
		var best := -1
		var bd := 24.0 * 24.0
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for j in grid.get(key + Vector2i(dx, dz), []):
					if j == i or sidewalk_links[i].has(j):
						continue
					var d := p.distance_squared_to(sidewalk_nodes[j])
					if d < bd and d > 1.0:
						bd = d
						best = j
		if best >= 0:
			_link(i, best)


func _build_labels() -> void:
	for lm in landmarks:
		var l := Label3D.new()
		l.text = lm[0]
		l.font_size = 64
		l.pixel_size = 0.007
		l.outline_size = 10
		l.modulate = Color(1, 0.95, 0.8)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = lm[1]
		l.visibility_range_end = 120.0
		l.no_depth_test = false
		add_child(l)


# ---------------------------------------------------------------- interface commune

func random_sidewalk_node() -> int:
	for t in 50:
		var i := rng.randi() % sidewalk_nodes.size()
		if not sidewalk_links[i].is_empty():
			return i
	return 0


## Nœud de trottoir au hasard près d'un point (pour faire apparaître les passants autour du joueur).
func random_sidewalk_node_near(p: Vector3, radius: float) -> int:
	for t in 200:
		var i := rng.randi() % sidewalk_nodes.size()
		if not sidewalk_links[i].is_empty() and sidewalk_nodes[i].distance_to(p) < radius:
			return i
	return random_sidewalk_node()


## Point de trottoir au hasard entre min_d et max_d de `from`, en évitant les points de `avoid`.
func sidewalk_point_near(from: Vector3, min_d: float, max_d: float, avoid: Array = [], spacing := 5.0) -> Vector3:
	var candidates: Array = []
	for i in sidewalk_nodes.size():
		if sidewalk_links[i].is_empty():
			continue
		var d := sidewalk_nodes[i].distance_to(from)
		if d >= min_d and d <= max_d:
			candidates.append(i)
	candidates.shuffle()
	for i in candidates:
		var p := sidewalk_nodes[i].lerp(sidewalk_nodes[sidewalk_links[i].pick_random()], randf_range(0.2, 0.8))
		var ok := true
		for q in avoid:
			if p.distance_to(q) < spacing:
				ok = false
				break
		if ok:
			return p
	return from + Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))


func set_night(night: float) -> void:
	_night = night
	building_mat.set_shader_parameter("night", clampf((night - 0.25) * 1.6, 0.0, 1.0))
	lamp_material.emission_energy_multiplier = 6.0 if night > 0.35 else 0.0
	Vehicles.set_night(night)
