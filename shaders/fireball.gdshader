shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform float emission_strength : hint_range(0.0, 20.0) = 8.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;

// Gradient noise hash
vec3 _h(vec3 p) {
	p = vec3(dot(p,vec3(127.1,311.7,74.7)), dot(p,vec3(269.5,183.3,246.1)), dot(p,vec3(113.5,271.9,124.6)));
	return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}

float _n(vec3 p) {
	vec3 i = floor(p), f = fract(p), u = f*f*(3.0-2.0*f);
	return mix(mix(mix(dot(_h(i),f), dot(_h(i+vec3(1,0,0)),f-vec3(1,0,0)),u.x),
		mix(dot(_h(i+vec3(0,1,0)),f-vec3(0,1,0)), dot(_h(i+vec3(1,1,0)),f-vec3(1,1,0)),u.x),u.y),
		mix(mix(dot(_h(i+vec3(0,0,1)),f-vec3(0,0,1)), dot(_h(i+vec3(1,0,1)),f-vec3(1,0,1)),u.x),
		mix(dot(_h(i+vec3(0,1,1)),f-vec3(0,1,1)), dot(_h(i+vec3(1,1,1)),f-vec3(1,1,1)),u.x),u.y),u.z);
}

// 2-octave FBM — fast
float fbm2(vec3 p) {
	return _n(p) * 0.65 + _n(p * 2.0) * 0.35;
}

varying vec3 v_unit;

void vertex() {
	vec3 unit = normalize(VERTEX);
	float r = length(VERTEX);
	v_unit = unit;

	// Scroll noise upward in object space — fire rises
	float t = TIME * 1.5;
	float n = fbm2(unit * 3.0 + vec3(t * 0.3, t, t * 0.2));
	VERTEX = unit * (r + n * 0.4 * r);
}

void fragment() {
	float t = TIME * 1.5;

	// Sample at slightly different offset than vertex for variation
	float n = fbm2(v_unit * 3.5 + vec3(t * 0.2, t * 0.8, t * 0.15));
	n = n * 0.5 + 0.5; // remap 0..1

	// Fire color ramp: white-hot core → yellow → orange → dark red → black
	vec3 col;
	col = mix(vec3(0.15, 0.01, 0.0), vec3(0.8, 0.15, 0.01), smoothstep(0.15, 0.35, n));
	col = mix(col, vec3(1.0, 0.55, 0.05), smoothstep(0.35, 0.55, n));
	col = mix(col, vec3(1.0, 0.9, 0.4), smoothstep(0.55, 0.72, n));
	col = mix(col, vec3(1.0, 1.0, 0.9), smoothstep(0.72, 0.88, n));

	// View angle — edges more transparent (shows sphere depth)
	float NdotV = abs(dot(normalize(NORMAL), VIEW));
	float edge = smoothstep(0.0, 0.4, NdotV);

	// Noise-driven alpha: dark areas become transparent holes
	float alpha = smoothstep(0.18, 0.5, n) * edge;

	// Dissolve: noise-driven disintegration
	float dn = fbm2(v_unit * 4.0 + vec3(0.0, TIME * 0.5, 0.0)) * 0.5 + 0.5;
	float dt = dissolve * 1.4;
	if (dn < dt) discard;
	// Glowing edge at dissolve boundary
	col += vec3(1.0, 0.7, 0.2) * (1.0 - smoothstep(dt, dt + 0.1, dn)) * step(0.01, dissolve) * 3.0;
	alpha *= 1.0 - dissolve * 0.3;

	ALBEDO = col;
	EMISSION = col * emission_strength;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
