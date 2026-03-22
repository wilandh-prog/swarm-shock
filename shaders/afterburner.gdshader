shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float flame_speed : hint_range(0.5, 5.0) = 3.0;
uniform float flame_length : hint_range(0.5, 3.0) = 1.5;

// Gradient noise
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

float fbm2(vec3 p) {
	return _n(p) * 0.65 + _n(p * 2.0) * 0.35;
}

varying float v_height;

void vertex() {
	// CylinderMesh: bottom_radius=8 at Y=-15, top_radius=1 at Y=+15
	// After 90° X rotation: wide end at nozzle, narrow tip extends backward (+Z)
	// v_height: 0 = wide (nozzle), 1 = narrow (flame tip)
	v_height = clamp(VERTEX.y / 15.0 * 0.5 + 0.5, 0.0, 1.0);

	float t = TIME * flame_speed;
	float wobble = fbm2(VERTEX * 0.2 + vec3(t * 0.4, t, t * 0.3));
	VERTEX.xz += VERTEX.xz * wobble * 0.3 * v_height * intensity;
	VERTEX.y *= 0.3 + intensity * flame_length;
}

void fragment() {
	float t = TIME * flame_speed;
	float n = fbm2(vec3(UV * 4.0, t * 0.8)) * 0.5 + 0.5;
	float n2 = fbm2(vec3(UV.yx * 3.0 + 1.5, t * 1.2)) * 0.5 + 0.5;
	float combined = n * 0.6 + n2 * 0.4;

	// Color: white-blue core -> yellow -> orange -> red
	vec3 col = mix(vec3(1.0, 0.15, 0.02), vec3(1.0, 0.5, 0.05), smoothstep(0.2, 0.4, combined));
	col = mix(col, vec3(1.0, 0.85, 0.3), smoothstep(0.4, 0.6, combined));
	col = mix(col, vec3(0.7, 0.85, 1.0), smoothstep(0.6, 0.8, combined));
	col = mix(col, vec3(0.9, 0.95, 1.0), smoothstep(0.8, 0.95, combined));

	// Alpha: fade at tip, noise holes, edge softening
	float length_fade = 1.0 - v_height;
	float noise_alpha = smoothstep(0.15, 0.55, combined);
	float NdotV = abs(dot(normalize(NORMAL), VIEW));
	float edge = smoothstep(0.0, 0.35, NdotV);
	float alpha = length_fade * noise_alpha * edge * intensity;

	ALBEDO = col;
	EMISSION = col * 6.0 * intensity;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
