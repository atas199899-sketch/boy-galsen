shader_type spatial;
// Habille un corps de base. Les couleurs de sommets contiennent la position de repos
// (R = hauteur relative, G = écart latéral x2) : les zones de vêtements sont calculées
// ici pixel par pixel. On garde le relief (normal map) pour un tissu crédible.

uniform sampler2D skin_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_tex : hint_roughness_g, filter_linear_mipmap;
uniform vec3 top_color : source_color = vec3(0.94, 0.72, 0.23);
uniform vec3 bottom_color : source_color = vec3(0.17, 0.23, 0.33);
uniform vec3 shoe_color : source_color = vec3(0.1);
uniform vec3 skin_tint : source_color = vec3(1.0);
uniform float pattern = 0.0;               // 1 = motif type wax sur le haut
uniform vec3 pattern_color : source_color = vec3(0.95, 0.77, 0.06);
uniform float top_low = 0.5;      // bas du haut (0.5 = t-shirt, 0.18 = boubou long)
uniform float has_bottom = 1.0;   // 0 = pas de pantalon visible (boubou)
uniform float sleeve = 0.4;       // longueur des manches (écart latéral x2)
uniform float neck_hole = 0.81;
uniform float neck_width = 0.13;
uniform float waist = 0.535;
uniform float collar = 0.86;
uniform float sandals = 0.0;      // 1 = sandales (samara) : semelle + lanières, pied visible

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 skin = texture(skin_tex, UV).rgb * skin_tint;
	float t = COLOR.r;
	float ax = COLOR.g;
	float e = 0.002;
	float shoes = 1.0 - smoothstep(0.052, 0.052 + e, t);
	if (sandals > 0.5) {
		// semelle + deux lanières sur le dessus du pied
		float sole = 1.0 - smoothstep(0.012, 0.012 + e, t);
		float strap = step(0.026, t) * step(t, 0.032) + step(0.04, t) * step(t, 0.046);
		shoes *= clamp(sole + strap, 0.0, 1.0);
	}
	float bottom = has_bottom * smoothstep(0.052, 0.052 + e, t) * (1.0 - smoothstep(waist, waist + e, t));
	float top = smoothstep(top_low, top_low + e, t) * (1.0 - smoothstep(collar, collar + e, t))
		* (1.0 - smoothstep(sleeve, sleeve + e * 2.0, ax));
	float rr = clamp(ax / neck_width, 0.0, 1.0);
	float hole = neck_hole - 0.028 * (1.0 - rr * rr);   // encolure ronde (plus basse au centre)
	float neck = smoothstep(hole, hole + e, t) * (1.0 - smoothstep(neck_width, neck_width + e * 2.0, ax));
	top *= 1.0 - neck;
	bottom *= 1.0 - top;   // le haut passe par-dessus le pantalon
	float cloth = clamp(top + bottom + shoes, 0.0, 1.0);

	// trame de tissu fine
	float weave = 0.93 + 0.07 * sin(UV.x * 1400.0) * sin(UV.y * 1400.0);
	vec3 tc = top_color;
	if (pattern > 0.5) {
		vec2 g = UV * 60.0;
		vec2 c = fract(g) - 0.5;
		float d = length(c);
		float ring = smoothstep(0.32, 0.28, d) - smoothstep(0.2, 0.16, d);
		float dot_ = smoothstep(0.1, 0.06, d);
		tc = mix(tc, pattern_color, clamp(ring + dot_, 0.0, 1.0));
	}
	vec3 col = skin;
	col = mix(col, tc * weave, top);
	col = mix(col, bottom_color * weave, bottom);
	col = mix(col, shoe_color, shoes);
	ALBEDO = col;

	float r = texture(rough_tex, UV).g;
	ROUGHNESS = mix(r, mix(0.88, 0.45, shoes), cloth);
	SPECULAR = mix(0.5, 0.25, cloth);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.35, cloth);
	// léger éclairage diffus sous la peau
	BACKLIGHT = mix(vec3(0.12, 0.05, 0.03), vec3(0.0), cloth);
}
