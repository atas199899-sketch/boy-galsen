"""Convertit des tuiles OpenStreetMap (.osm) en carte de jeu compacte (JSON).

Usage : python3 tools/osm_to_game.py DOSSIER_TUILES data/map/dakar_centre.json [SUD OUEST NORD EST]

Coordonnées de sortie en mètres, origine sur la Place de l'Indépendance :
x vers l'est, z vers le sud (convention Godot : le nord est vers -Z).
Données : © les contributeurs OpenStreetMap, licence ODbL.
"""
import glob, json, math, sys
import xml.etree.ElementTree as ET

LAT0, LON0 = 14.6680, -17.4313          # Place de l'Indépendance
KX = 111320.0 * math.cos(math.radians(LAT0))
KZ = 110574.0

ROAD_WIDTH = {
    "motorway": 14, "trunk": 13, "primary": 12, "secondary": 10, "tertiary": 9, "unclassified": 7,
    "residential": 7, "living_street": 6, "service": 5, "pedestrian": 6, "primary_link": 8,
    "secondary_link": 7, "tertiary_link": 7, "trunk_link": 8, "footway": 2.5, "path": 2, "steps": 2.5,
}
POI_AMENITY = {"pharmacy", "marketplace", "place_of_worship", "bank", "restaurant", "cafe", "fast_food", "fuel",
               "hospital", "clinic", "school", "university", "post_office", "police", "bus_station", "taxi",
               "townhall", "courthouse", "theatre", "cinema", "library", "bureau_de_change", "embassy", "ferry_terminal"}


def proj(lat, lon):
    return round((lon - LON0) * KX, 1), round(-(lat - LAT0) * KZ, 1)


def clip(data, x0, z0, x1, z1):
    """Garde ce qui est dans la zone téléchargée (l'API renvoie les rues entières)."""
    inside = lambda x, z: x0 <= x <= x1 and z0 <= z <= z1
    data["buildings"] = [b for b in data["buildings"] if inside(b["p"][0], b["p"][1])]
    data["areas"] = [a for a in data["areas"] if inside(a["p"][0], a["p"][1])]
    data["pois"] = [p for p in data["pois"] if inside(p["x"], p["z"])]
    roads = []
    for r in data["roads"]:
        cur, cur_ids = [], []
        pts = list(zip(r["p"][0::2], r["p"][1::2]))
        ids = r["id"] if len(r["id"]) == len(pts) else [0] * len(pts)
        for (x, z), i in zip(pts, ids):
            if inside(x, z):
                cur += [x, z]; cur_ids.append(i)
            else:
                if len(cur) >= 4:
                    roads.append(dict(r, p=cur, id=cur_ids))
                cur, cur_ids = [], []
        if len(cur) >= 4:
            roads.append(dict(r, p=cur, id=cur_ids))
    data["roads"] = roads
    data["bounds"] = [x0, z0, x1, z1]


def land_mask(data, cell=10.0, radius=55.0):
    """Terre ferme = tout ce qui est à moins de `radius` m d'un bâtiment ou d'une rue.
    Le reste devient l'océan (le centre de Dakar est une presqu'île). Codé par lignes (début, longueur)."""
    x0, z0, x1, z1 = data["bounds"]
    w, h = int((x1 - x0) / cell) + 1, int((z1 - z0) / cell) + 1
    grid = [bytearray(w) for _ in range(h)]
    r = int(radius / cell)
    disk = [(dx, dz) for dx in range(-r, r + 1) for dz in range(-r, r + 1) if dx * dx + dz * dz <= r * r]
    def mark(x, z):
        cx, cz = int((x - x0) / cell), int((z - z0) / cell)
        for dx, dz in disk:
            i, j = cx + dx, cz + dz
            if 0 <= i < w and 0 <= j < h:
                grid[j][i] = 1
    seen = set()
    def mark_once(x, z):
        k = (int((x - x0) / (cell * 2)), int((z - z0) / (cell * 2)))
        if k not in seen:
            seen.add(k)
            mark(x, z)
    for b in data["buildings"]:
        for x, z in zip(b["p"][0::2], b["p"][1::2]):
            mark_once(x, z)
    for rd in data["roads"]:
        pts = list(zip(rd["p"][0::2], rd["p"][1::2]))
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            n = max(1, int(math.hypot(bx - ax, bz - az) / cell))
            for k in range(n + 1):
                mark_once(ax + (bx - ax) * k / n, az + (bz - az) * k / n)
    rows = []
    for row in grid:
        runs, i = [], 0
        while i < w:
            if row[i]:
                j = i
                while j < w and row[j]:
                    j += 1
                runs += [i, j - i]
                i = j
            else:
                i += 1
        rows.append(runs)
    return {"cell": cell, "x0": x0, "z0": z0, "w": w, "h": h, "rows": rows}


def main(folder, out):
    nodes, ways, rels = {}, {}, {}
    for f in sorted(glob.glob(folder + "/*.osm")):
        try:
            root = ET.parse(f).getroot()
        except ET.ParseError:
            continue
        for n in root.iter("node"):
            tags = {t.get("k"): t.get("v") for t in n.findall("tag")}
            nodes[n.get("id")] = (float(n.get("lat")), float(n.get("lon")), tags)
        for w in root.iter("way"):
            ways[w.get("id")] = ([nd.get("ref") for nd in w.findall("nd")], {t.get("k"): t.get("v") for t in w.findall("tag")})
        for r in root.iter("relation"):
            rels[r.get("id")] = ([(m.get("type"), m.get("ref"), m.get("role")) for m in r.findall("member")],
                                 {t.get("k"): t.get("v") for t in r.findall("tag")})

    def pts(ids):
        p = [proj(nodes[i][0], nodes[i][1]) for i in ids if i in nodes]
        return p

    def area(p):
        return abs(sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))) / 2

    def centroid(p):
        return round(sum(a for a, _ in p) / len(p), 1), round(sum(b for _, b in p) / len(p), 1)

    buildings, roads, pois, areas = [], [], [], []
    used_as_building = set()
    # bâtiments décrits par une relation (contour extérieur seulement)
    for rid, (members, tags) in rels.items():
        if "building" in tags and tags.get("type") == "multipolygon":
            for typ, ref, role in members:
                if typ == "way" and role == "outer" and ref in ways:
                    ids, wt = ways[ref]
                    merged = dict(tags)
                    merged.update(wt)
                    ways[ref] = (ids, merged)
    for wid, (ids, tags) in ways.items():
        if len(ids) < 4 or ids[0] != ids[-1]:
            closed = False
        else:
            closed = True
        if "building" in tags and closed:
            p = pts(ids[:-1])
            if len(p) < 3 or area(p) < 8:
                continue
            lv = None
            for k in ("building:levels", "levels"):
                try:
                    lv = int(float(tags[k]))
                    break
                except (KeyError, ValueError):
                    pass
            if lv is None and "height" in tags:
                try:
                    lv = max(1, round(float(tags["height"].split()[0]) / 3.2))
                except ValueError:
                    pass
            b = {"p": [c for xy in p for c in xy]}
            if lv:
                b["l"] = lv
            kind = tags.get("amenity") or tags.get("shop") or ("worship" if tags.get("building") in ("mosque", "church", "cathedral") else None)
            if tags.get("religion"):
                kind = "mosque" if tags["religion"] == "muslim" else "church"
            if kind:
                b["k"] = kind
            if tags.get("name"):
                b["n"] = tags["name"]
            buildings.append(b)
            used_as_building.add(wid)
        elif "highway" in tags and tags["highway"] in ROAD_WIDTH and tags.get("area") != "yes":
            p = pts(ids)
            if len(p) < 2:
                continue
            r = {"p": [c for xy in p for c in xy], "t": tags["highway"], "w": ROAD_WIDTH[tags["highway"]],
                 "id": [int(i) for i in ids if i in nodes]}
            if tags.get("name"):
                r["n"] = tags["name"]
            roads.append(r)
        elif closed and (tags.get("leisure") in ("park", "garden", "pitch", "stadium") or tags.get("landuse") in ("grass", "recreation_ground", "cemetery")
                         or tags.get("place") == "square" or (tags.get("highway") == "pedestrian" and tags.get("area") == "yes")
                         or tags.get("natural") in ("sand", "beach", "scrub", "wood")):
            p = pts(ids[:-1])
            if len(p) < 3:
                continue
            kind = tags.get("leisure") or tags.get("landuse") or tags.get("natural") or ("square" if tags.get("place") == "square" or tags.get("highway") == "pedestrian" else "park")
            a = {"p": [c for xy in p for c in xy], "k": kind}
            if tags.get("name"):
                a["n"] = tags["name"]
            areas.append(a)
        if closed and wid not in used_as_building and tags.get("name") and (tags.get("amenity") in POI_AMENITY or tags.get("shop") or tags.get("tourism")):
            p = pts(ids[:-1])
            if p:
                x, z = centroid(p)
                pois.append({"x": x, "z": z, "k": tags.get("amenity") or "shop:" + tags.get("shop", "") if tags.get("shop") else tags.get("amenity") or tags.get("tourism"), "n": tags["name"]})
    for nid, (lat, lon, tags) in nodes.items():
        kind = None
        if tags.get("amenity") in POI_AMENITY:
            kind = tags["amenity"]
        elif tags.get("shop"):
            kind = "shop:" + tags["shop"]
        elif tags.get("tourism") in ("attraction", "museum", "hotel", "artwork", "viewpoint"):
            kind = tags["tourism"]
        elif tags.get("historic") in ("monument", "memorial"):
            kind = tags["historic"]
        elif tags.get("place") == "square":
            kind = "square"
        if kind:
            x, z = proj(lat, lon)
            pois.append({"x": x, "z": z, "k": kind, "n": tags.get("name", "")})

    xs = [buildings[i]["p"][0] for i in range(len(buildings))] + [r["p"][0] for r in roads]
    zs = [buildings[i]["p"][1] for i in range(len(buildings))] + [r["p"][1] for r in roads]
    data = {
        "source": "© les contributeurs OpenStreetMap (ODbL)",
        "origin": {"lat": LAT0, "lon": LON0, "name": "Place de l'Indépendance"},
        "bounds": [min(xs), min(zs), max(xs), max(zs)],
        "buildings": buildings, "roads": roads, "pois": pois, "areas": areas,
    }
    if len(sys.argv) > 3:
        s, w, n, e = map(float, sys.argv[3:7])
        a = proj(n, w); b = proj(s, e)
        clip(data, a[0], a[1], b[0], b[1])
    data["land"] = land_mask(data)
    json.dump(data, open(out, "w"), ensure_ascii=False, separators=(",", ":"))
    named = sum(1 for b in buildings if "n" in b)
    lv = sum(1 for b in buildings if "l" in b)
    buildings, roads, pois, areas = data["buildings"], data["roads"], data["pois"], data["areas"]
    named = sum(1 for b in buildings if "n" in b)
    lv = sum(1 for b in buildings if "l" in b)
    print(f"bâtiments {len(buildings)} (avec étages {lv}, nommés {named}), rues {len(roads)}, lieux {len(pois)}, zones {len(areas)}")
    print("limites", data["bounds"])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
