shader_type spatial;
// Façades des bâtiments réels (OpenStreetMap). Les fenêtres et les rideaux de boutique
// sont dessinés ici, au pixel près, pour ne pas multiplier la géométrie.
//   UV  = (mètres le long du mur, hauteur en mètres)
//   UV2 = (longueur du mur, hauteur du bâtiment)
//   COLOR.rgb = teinte de l'enduit, COLOR.a = graine aléatoire du bâtiment

uniform sampler2D wall_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D wall_nrm : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D wall_rough : hint_roughness_g, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D shutter_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float night = 0.0;
uniform float floor_h = 3.2;
uniform float bay_w = 3.0;

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

void fragment() {
	vec2 m = UV;
	float wall_len = UV2.x;
	float height = UV2.y;
	float seed = COLOR.a * 97.0;
	// fenêtres centrées sur la longueur du mur
	float bays = max(floor(wall_len / bay_w), 1.0);
	float x0 = (wall_len - bays * bay_w) * 0.5;
	float bx = (m.x - x0) / bay_w;
	float col_i = floor(bx);
	float fy = m.y / floor_h;
	float floor_i = floor(fy);
	vec2 c = vec2(fract(bx), fract(fy));
	bool in_bays = bx >= 0.0 && bx < bays && wall_len > 2.2;
	bool below_roof = m.y < height - 0.9;

	vec3 tint = COLOR.rgb;
	// la texture sert seulement de variation (grain de l'enduit) : la couleur vient de la teinte
	vec3 wt = texture(wall_tex, m * 0.32).rgb;
	float grain = dot(wt, vec3(0.333));
	vec3 wall = tint * (0.72 + 0.6 * grain);
	// salissures en bas des murs et coulures sous les fenêtres
	wall *= mix(0.78, 1.0, smoothstep(0.0, 1.2, m.y));
	vec3 col = wall;
	float rough = texture(wall_rough, m * 0.32).g;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	vec3 nrm = texture(wall_nrm, m * 0.32).rgb;

	float h_seed = hash(vec3(col_i, floor_i, seed));
	if (in_bays && below_roof) {
		if (floor_i < 1.0) {
			// rez-de-chaussée : rideaux métalliques / vitrines / portes
			float shop = step(0.35, hash(vec3(col_i, 7.0, seed)));
			if (c.x > 0.07 && c.x < 0.93 && c.y < 0.8) {
				if (shop > 0.5) {
					vec3 sh = texture(shutter_tex, vec2(c.x * 2.0, m.y * 0.6)).rgb;
					vec3 paint = mix(vec3(0.35, 0.38, 0.40), vec3(0.20, 0.33, 0.55), step(0.6, h_seed));
					col = sh * paint * 1.8;
					rough = 0.55; metal = 0.6;
					// le soir, certaines boutiques sont ouvertes et éclairées
					float open_shop = step(0.55, hash(vec3(col_i, 3.0, seed)));
					emit = vec3(1.0, 0.78, 0.5) * 1.4 * night * open_shop * step(c.y, 0.75);
				} else {
					col = vec3(0.16, 0.11, 0.08);   // porte en bois / fer
					rough = 0.7;
				}
			}
			// bandeau peint au-dessus des boutiques
			if (c.y > 0.84 && c.y < 0.97) {
				col = mix(tint * 0.7, vec3(0.85, 0.75, 0.3), step(0.7, hash(vec3(col_i, 9.0, seed))));
			}
		} else {
			// étages : fenêtre avec encadrement, appui et persiennes parfois
			vec2 w0 = vec2(0.28, 0.26);
			vec2 w1 = vec2(0.72, 0.80);
			bool frame = c.x > w0.x - 0.05 && c.x < w1.x + 0.05 && c.y > w0.y - 0.06 && c.y < w1.y + 0.04;
			bool glass = c.x > w0.x && c.x < w1.x && c.y > w0.y && c.y < w1.y;
			if (frame) { col = mix(wall, vec3(0.92, 0.9, 0.85), 0.75); rough = 0.6; }
			if (glass) {
				float shutters = step(0.62, h_seed);
				if (shutters > 0.5) {
					float slat = step(0.5, fract(c.y * 22.0));
					col = mix(vec3(0.18, 0.42, 0.36), vec3(0.14, 0.33, 0.28), slat);
					rough = 0.7;
				} else {
					col = mix(vec3(0.05, 0.08, 0.11), vec3(0.22, 0.30, 0.38), c.y);
					rough = 0.08; metal = 0.5;
					float lit = step(h_seed, 0.42) * night;
					vec3 warm = mix(vec3(1.0, 0.76, 0.45), vec3(0.75, 0.85, 1.0), step(0.85, hash(vec3(col_i, floor_i, seed + 1.0))));
					emit = warm * lit * 1.6;
					if (lit > 0.0) { col = warm * 0.35; }
				}
				nrm = vec3(0.5, 0.5, 1.0);
			}
			// climatiseur sous certaines fenêtres
			if (step(0.86, hash(vec3(col_i, floor_i, seed + 5.0))) > 0.5 && c.x > 0.36 && c.x < 0.64 && c.y > 0.06 && c.y < 0.2) {
				col = vec3(0.85, 0.85, 0.82); rough = 0.4;
			}
		}
	}
	// corniche au sommet
	if (m.y > height - 0.45) { col = mix(wall, vec3(0.95, 0.93, 0.88), 0.5); }
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 0.8;
	EMISSION = emit;
}
