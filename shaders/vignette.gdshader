shader_type canvas_item;
// Post-processing: vignette, chromatic aberration, scanlines.

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.4;
uniform float vignette_radius : hint_range(0.0, 2.0) = 0.8;
uniform float aberration_amount : hint_range(0.0, 0.02) = 0.0;
uniform float scanline_strength : hint_range(0.0, 0.3) = 0.05;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Chromatic aberration
	vec2 aberr = (uv - 0.5) * aberration_amount;
	float r = texture(screen_texture, uv + aberr).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - aberr).b;
	vec3 color = vec3(r, g, b);

	// Scanlines
	float scanline = sin(uv.y * 800.0) * 0.5 + 0.5;
	color *= 1.0 - scanline_strength * scanline;

	// Vignette
	float dist = distance(uv, vec2(0.5));
	float vignette = smoothstep(vignette_radius, vignette_radius - 0.3, dist);
	color *= mix(1.0 - vignette_strength, 1.0, vignette);

	// Flash overlay
	color = mix(color, flash_color.rgb, flash_amount);

	COLOR = vec4(color, 1.0);
}
