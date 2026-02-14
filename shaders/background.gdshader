shader_type spatial;
render_mode unshaded;
// Ocean with tropical islands, beaches, forests, flowers.

uniform vec4 deep_color : source_color = vec4(0.02, 0.12, 0.28, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.08, 0.3, 0.5, 1.0);
uniform vec4 sand_color : source_color = vec4(0.82, 0.75, 0.55, 1.0);
uniform vec4 grass_light : source_color = vec4(0.22, 0.52, 0.15, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.08, 0.28, 0.06, 1.0);
uniform vec4 forest_color : source_color = vec4(0.04, 0.2, 0.08, 1.0);
uniform vec4 rock_color : source_color = vec4(0.4, 0.38, 0.32, 1.0);
uniform vec4 foam_color : source_color = vec4(0.7, 0.9, 0.95, 1.0);
uniform float wave_height : hint_range(1.0, 20.0) = 8.0;
uniform float terrain_height : hint_range(5.0, 60.0) = 30.0;
uniform float water_level : hint_range(0.1, 1.0) = 1.0;
uniform vec2 offset = vec2(0.0, 0.0);
uniform float time_val : hint_range(0.0, 100000.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm3(vec2 p) {
	float val = 0.0;
	val += 0.5 * noise(p);
	val += 0.25 * noise(p * 2.0);
	val += 0.125 * noise(p * 4.0);
	return val;
}

float fbm2(vec2 p) {
	return 0.5 * noise(p) + 0.25 * noise(p * 2.0);
}

// Terrain heightmap with domain warping for fractal coastlines
float terrain_at(vec2 wp) {
	// Domain warp - 2 octaves only
	vec2 ws = wp * 0.0008;
	float wx = fbm2(ws + vec2(0.0, 100.0));
	float wy = fbm2(ws + vec2(100.0, 0.0));
	vec2 warped = wp + vec2(wx, wy) * 800.0;

	// Base terrain with warped coords
	float h = fbm3(warped * 0.0004) * 0.6;
	h += fbm3(warped * 0.0012 + vec2(50.0, 80.0)) * 0.25;

	// Medium detail (unwarped for local variation)
	h += fbm2(wp * 0.004 + vec2(120.0, 200.0)) * 0.08;

	// Fine fractal detail along coastline
	float coast_dist = abs(h - water_level);
	float coast_mask = 1.0 - smoothstep(0.0, 0.06, coast_dist);
	h += fbm2(wp * 0.012 + vec2(300.0, 400.0)) * 0.025 * coast_mask;

	return h;
}

float wave_at(vec2 wp, float t) {
	vec2 uv = wp * 0.004;
	float w = 0.0;
	w += sin(uv.x * 3.0 + t * 1.2) * 0.25;
	w += sin(uv.y * 2.5 + t * 0.9) * 0.2;
	w += sin((uv.x + uv.y) * 2.0 + t * 1.5) * 0.15;
	w += fbm2(uv * 3.0 + vec2(t * 0.4, t * 0.3)) * 0.35;
	return w;
}

float caustic(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float md = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 nb = vec2(float(x), float(y));
			vec2 pt = vec2(hash(i + nb), hash(i + nb + vec2(37.0, 91.0)));
			pt = 0.5 + 0.5 * sin(t * 0.6 + 6.2831 * pt);
			md = min(md, length(nb + pt - f));
		}
	}
	return md;
}

varying float v_terrain;

void vertex() {
	vec2 wp = UV * 6000.0 + offset;
	float t = time_val * 0.4;
	float terrain = terrain_at(wp);
	v_terrain = terrain;

	float land_factor = smoothstep(-0.04, 0.04, terrain - water_level);
	float land_h = max(terrain - water_level, 0.0) * terrain_height;
	float w = wave_at(wp, t) * wave_height;
	VERTEX.y += mix(w, land_h, land_factor);
}

void fragment() {
	vec2 world_uv = UV * 6000.0 + offset;
	float t = time_val * 0.4;
	float terrain = v_terrain;

	float above = terrain - water_level;
	float land_factor = smoothstep(-0.04, 0.04, above);

	// --- LAND COLOR ---
	float above_clamped = max(above, 0.0);

	// Cheap noise to break up zone contour lines (reuse single noise calls)
	float zone_noise = noise(world_uv * 0.005 + vec2(77.0, 33.0)) * 0.05 - 0.025;
	float ah = above_clamped + zone_noise;

	// Zones by perturbed height
	float beach_t = smoothstep(0.0, 0.04, ah);
	float grass_t = smoothstep(0.015, 0.09, ah);
	float forest_t = smoothstep(0.08, 0.22, ah);
	float rock_t = smoothstep(0.22, 0.42, ah);

	// Beach sand
	vec3 land_color = sand_color.rgb;
	float wet = 1.0 - smoothstep(0.0, 0.02, above_clamped);
	land_color = mix(land_color, sand_color.rgb * 0.65, wet);

	// Grass
	float grass_noise = fbm2(world_uv * 0.006);
	vec3 grass = mix(grass_light.rgb, grass_dark.rgb, grass_noise);
	land_color = mix(land_color, grass, grass_t);

	// Forest patches
	float forest_noise = fbm2(world_uv * 0.003 + vec2(77.0, 55.0));
	float forest_mask = forest_t * smoothstep(0.35, 0.6, forest_noise);
	land_color = mix(land_color, forest_color.rgb, forest_mask);
	float canopy = noise(world_uv * 0.025);
	land_color = mix(land_color, forest_color.rgb * (0.7 + canopy * 0.6), forest_mask * 0.5);

	// Rocky peaks
	float rock_noise = noise(world_uv * 0.01 + vec2(200.0, 150.0));
	land_color = mix(land_color, rock_color.rgb * (0.8 + rock_noise * 0.4), rock_t);

	// Cheap terrain shading from noise gradient instead of extra terrain_at calls
	float shade_n = noise(world_uv * 0.002 + vec2(50.0, 80.0));
	float shade = 0.65 + shade_n * 0.3 + above_clamped * 0.5;
	shade = clamp(shade, 0.5, 1.0);
	land_color *= shade;

	// Shore foam on land side
	float shore_foam = smoothstep(0.015, 0.0, above_clamped);
	float foam_wave = sin(world_uv.x * 0.08 + t * 2.0) * 0.5 + 0.5;
	foam_wave *= sin(world_uv.y * 0.06 + t * 1.5) * 0.5 + 0.5;
	land_color = mix(land_color, foam_color.rgb, shore_foam * foam_wave * 0.7);

	// --- WATER COLOR ---
	float below = max(water_level - terrain, 0.0);
	float depth = clamp(below / 0.25, 0.0, 1.0);

	// Color variation using terrain noise for natural patches
	vec3 ocean_mid = vec3(0.06, 0.25, 0.45);
	vec3 turquoise = vec3(0.1, 0.38, 0.45);
	float color_var = fbm2(world_uv * 0.0006 + vec2(200.0, 300.0));
	vec3 water_col = mix(shallow_color.rgb, ocean_mid, color_var * 0.6);
	water_col = mix(water_col, turquoise, (1.0 - depth) * 0.3);
	water_col = mix(water_col, deep_color.rgb, depth * depth * 0.6);

	// Wave color variation
	float w = wave_at(world_uv, t);
	float wave_bright = smoothstep(-0.2, 0.5, w);
	water_col = mix(water_col, shallow_color.rgb * 1.3, wave_bright * 0.2);

	// Wave troughs slightly darker
	float wave_dark = smoothstep(0.1, -0.4, w);
	water_col = mix(water_col, deep_color.rgb, wave_dark * 0.15);

	// Caustics — brighter and more visible
	float c = caustic(world_uv * 0.012 + vec2(t * 0.3, t * 0.2), t);
	float caust = smoothstep(0.15, 0.0, c) * 0.5;
	water_col += vec3(0.15, 0.35, 0.45) * caust;

	// Second layer of caustics at different scale for richness
	float c2 = caustic(world_uv * 0.005 + vec2(-t * 0.15, t * 0.1), t * 0.7);
	float caust2 = smoothstep(0.2, 0.0, c2) * 0.25;
	water_col += vec3(0.1, 0.25, 0.35) * caust2;

	// Whitecap foam scattered across ocean
	float foam_n1 = fbm2(world_uv * 0.008 + vec2(t * 0.3, -t * 0.2));
	float foam_n2 = noise(world_uv * 0.025 + vec2(t * 0.6, t * 0.4));
	float whitecap = smoothstep(0.55, 0.7, foam_n1) * smoothstep(0.5, 0.65, foam_n2);
	float foam_flicker = sin(world_uv.x * 0.03 + t * 3.0) * 0.3 + 0.7;
	water_col = mix(water_col, foam_color.rgb, whitecap * foam_flicker * 0.6);

	// --- BLEND ---
	vec3 color = mix(water_col, land_color, land_factor);

	ALBEDO = color;
	EMISSION = color;
}
