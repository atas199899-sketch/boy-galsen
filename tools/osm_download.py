"""Télécharge une zone d'OpenStreetMap par tuiles (API officielle, usage modéré).

Usage : python3 tools/osm_download.py SUD OUEST NORD EST DOSSIER
Les données OSM sont sous licence ODbL : © les contributeurs OpenStreetMap.
"""
import os, sys, time, urllib.request

s, w, n, e = map(float, sys.argv[1:5])
out = sys.argv[5]
os.makedirs(out, exist_ok=True)
step = 0.005
lat = s
while lat < n - 1e-9:
    lon = w
    while lon < e - 1e-9:
        f = os.path.join(out, f"{lat:.3f}_{lon:.3f}.osm")
        if not os.path.exists(f) or os.path.getsize(f) < 100:
            url = f"https://api.openstreetmap.org/api/0.6/map?bbox={lon:.4f},{lat:.4f},{min(lon+step,e):.4f},{min(lat+step,n):.4f}"
            req = urllib.request.Request(url, headers={"User-Agent": "BoyGalsen-map-import/1.0"})
            for attempt in range(3):
                try:
                    data = urllib.request.urlopen(req, timeout=120).read()
                    open(f, "wb").write(data)
                    print(f, len(data), flush=True)
                    break
                except Exception as ex:
                    print("erreur", f, ex, flush=True)
                    time.sleep(5)
            time.sleep(1.0)
        lon += step
    lat += step
print("terminé")
