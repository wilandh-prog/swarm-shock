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
uniform float wave_height : hint_range(0.0, 20.0) = 0.0;
uniform float terrain_height : hint_range(5.0, 60.0) = 30.0;
uniform float water_level : hint_range(0.1, 1.0) = 1.0;
uniform vec2 offset = vec2(0.0, 0.0);
uniform float time_val : hint_range(0.0, 100000.0) = 0.0;

// Water quality
uniform vec3 sun_direction = vec3(0.4, 0.8, -0.3);
uniform float specular_power : hint_range(32.0, 512.0) = 200.0;
uniform float specular_intensity : hint_range(0.0, 3.0) = 1.2;
uniform vec4 sky_reflect_color : source_color = vec4(0.45, 0.65, 0.85, 1.0);
uniform vec4 sss_color : source_color = vec4(0.05, 0.4, 0.3, 1.0);
uniform float detail_normal_strength : hint_range(0.0, 10.0) = 5.0;
uniform vec4 horizon_color : source_color = vec4(0.55, 0.65, 0.78, 1.0);
uniform float fog_intensity : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// Quintic interpolation (C2 continuous) — eliminates grid artifacts in derivatives
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Value noise with analytical derivatives (Inigo Quilez technique)
// Returns vec3(value, dNoise/dx, dNoise/dy) — no finite differences needed
vec3 noised(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// Quintic interpolation
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	// Analytical derivative of quintic
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	float k1 = b - a;
	float k2 = c - a;
	float k4 = a - b - c + d;

	return vec3(
		a + k1 * u.x + k2 * u.y + k4 * u.x * u.y,
		du.x * (k1 + k4 * u.y),
		du.y * (k2 + k4 * u.x)
	);
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

	// Base terrain with warped coords (2 octaves for perf)
	float h = fbm2(warped * 0.0004) * 0.6;
	h += fbm2(warped * 0.0012 + vec2(50.0, 80.0)) * 0.25;

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
	w += sin(uv.x * 1.5 - uv.y * 1.8 + t * 0.7) * 0.1; // cross wave
	// Gerstner-like: sharpen crests, flatten troughs
	w = w + 0.18 * w * w * sign(w);
	w += fbm2(uv * 3.0 + vec2(t * 0.4, t * 0.3)) * 0.3;
	return w;
}

// Per-pixel wave detail with analytical derivatives (no finite differences!)
// Returns vec3(height, dh/dx, dh/dz) — smooth C2, no grid artifacts
vec3 detail_waves(vec2 p, float t) {
	float s1 = 0.025; float a1 = 0.5;
	float s2 = 0.06;  float a2 = 0.25;
	float s3 = 0.14;  float a3 = 0.125;

	vec3 n1 = noised(p * s1 + vec2(t * 0.5, t * 0.35));
	vec3 n2 = noised(p * s2 + vec2(-t * 0.35, t * 0.55));
	vec3 n3 = noised(p * s3 + vec2(t * 0.7, -t * 0.25));

	return vec3(
		n1.x * a1 + n2.x * a2 + n3.x * a3,
		n1.y * s1 * a1 + n2.y * s2 * a2 + n3.y * s3 * a3,  // chain rule: dh/dp * dp/dx
		n1.z * s1 * a1 + n2.z * s2 * a2 + n3.z * s3 * a3
	);
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
	vec2 wp = UV * 3000.0 + offset;
	float t = time_val * 0.4;
	float terrain = terrain_at(wp);
	v_terrain = terrain;

	float land_factor = smoothstep(-0.04, 0.04, terrain - water_level);
	float land_h = max(terrain - water_level, 0.0) * terrain_height;
	float w = wave_at(wp, t) * wave_height;

	// Fade vertex displacement near edges — per-pixel normals handle distant waves
	float edge_dist = max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0;
	float wave_fade = 1.0 - smoothstep(0.5, 0.9, edge_dist);
	VERTEX.y += mix(w * wave_fade, land_h, land_factor);
}

void fragment() {
	vec2 world_uv = UV * 3000.0 + offset;
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
	// Distance for LOD and fog (computed early for performance)
	float dist_uv = max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0;
	float dist_fade = smoothstep(0.3, 0.6, dist_uv);
	float fog = dist_fade * fog_intensity;

	vec3 water_col = horizon_color.rgb; // default for fully fogged pixels

	if (dist_fade < 0.99) {
		float below = max(water_level - terrain, 0.0);
		float depth_raw = below / 0.25;
		float beer = exp(-depth_raw * 2.0);

		// Base depth color
		water_col = mix(deep_color.rgb, shallow_color.rgb, beer);

		// Tropical color patches
		float color_var = fbm2(world_uv * 0.0006 + vec2(200.0, 300.0));
		water_col = mix(water_col, vec3(0.1, 0.4, 0.48), beer * color_var * 0.4);

		// View direction in world space
		vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);

		// Macro wave normal (analytical sine derivatives, per-pixel)
		vec2 uv_wave = world_uv * 0.004;
		float macro_dx = cos(uv_wave.x * 3.0 + t * 1.2) * 3.0 * 0.004 * 0.25
		               + cos((uv_wave.x + uv_wave.y) * 2.0 + t * 1.5) * 2.0 * 0.004 * 0.15
		               + cos(uv_wave.x * 1.5 - uv_wave.y * 1.8 + t * 0.7) * 1.5 * 0.004 * 0.1;
		float macro_dz = cos(uv_wave.y * 2.5 + t * 0.9) * 2.5 * 0.004 * 0.2
		               + cos((uv_wave.x + uv_wave.y) * 2.0 + t * 1.5) * 2.0 * 0.004 * 0.15
		               + cos(uv_wave.x * 1.5 - uv_wave.y * 1.8 + t * 0.7) * (-1.8) * 0.004 * 0.1;

		// Detail normal (analytical C2 noise derivatives) — skip at distance
		float detail_fade = 1.0 - smoothstep(0.15, 0.35, dist_uv);
		float nx = -macro_dx * 3.0;
		float nz = -macro_dz * 3.0;
		if (detail_fade > 0.01) {
			vec3 detail = detail_waves(world_uv, t);
			nx -= detail.y * detail_normal_strength * detail_fade;
			nz -= detail.z * detail_normal_strength * detail_fade;
		}
		vec3 normal_w = normalize(vec3(nx, 1.0, nz));

		// Per-pixel wave value for color effects
		float w_val = wave_at(world_uv, t);

		// Schlick fresnel (F0 = 0.02 for water IOR 1.33)
		float cos_theta = max(dot(normal_w, view_dir), 0.0);
		float fresnel = 0.02 + 0.98 * pow(1.0 - cos_theta, 5.0);
		water_col = mix(water_col, sky_reflect_color.rgb, fresnel);

		// Subsurface scattering
		float sss = smoothstep(-0.1, 0.4, w_val) * beer;
		water_col += sss_color.rgb * sss * 0.4;

		// Sun specular highlights with sparkle
		vec3 sun_d = normalize(sun_direction);
		vec3 half_vec = normalize(sun_d + view_dir);
		float spec = pow(max(dot(normal_w, half_vec), 0.0), specular_power);
		float sparkle = noise(world_uv * 0.05 + vec2(t * 2.0, -t * 1.5));
		spec *= 0.7 + sparkle * 0.6;
		water_col += vec3(1.0, 0.95, 0.85) * spec * specular_intensity;

		// Wave brightness/darkness
		water_col = mix(water_col, shallow_color.rgb * 1.3, smoothstep(-0.2, 0.5, w_val) * 0.15);
		water_col = mix(water_col, deep_color.rgb, smoothstep(0.1, -0.4, w_val) * 0.15);

		// Caustics — only very near camera (expensive 3x3 loops), single layer only
		if (dist_uv < 0.2) {
			float c = caustic(world_uv * 0.012 + vec2(t * 0.3, t * 0.2), t);
			float caust = smoothstep(0.15, 0.0, c) * 0.5 * beer;
			water_col += vec3(0.15, 0.35, 0.45) * caust;
		}

		// Whitecap foam
		float foam_n1 = fbm2(world_uv * 0.008 + vec2(t * 0.3, -t * 0.2));
		float foam_n2 = noise(world_uv * 0.025 + vec2(t * 0.6, t * 0.4));
		float whitecap = smoothstep(0.55, 0.7, foam_n1) * smoothstep(0.5, 0.65, foam_n2);
		whitecap *= smoothstep(-0.1, 0.3, w_val);
		float foam_flicker = sin(world_uv.x * 0.03 + t * 3.0) * 0.3 + 0.7;
		water_col = mix(water_col, foam_color.rgb, whitecap * foam_flicker * 0.7);
	}

	// --- BLEND ---
	vec3 color = mix(water_col, land_color, land_factor);

	// Atmospheric haze
	color = mix(color, horizon_color.rgb, fog);

	ALBEDO = color;
	EMISSION = color;
}
