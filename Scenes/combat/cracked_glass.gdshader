shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 refraction_offset = vec2(25.0, 25.0);
uniform float crack_dark_threshold = 0.22;
uniform float crack_rim_threshold = 0.36;
uniform float crack_alpha_threshold = 0.05;
uniform float crack_core_darkness = 0.65;
uniform float crack_rim_brightness = 0.35;

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	float luma = dot(mask.rgb, vec3(0.2126, 0.7152, 0.0722));
	float core = 1.0 - smoothstep(0.0, crack_dark_threshold, luma);
	float band = 1.0 - smoothstep(crack_dark_threshold, crack_rim_threshold, luma);
	float rim = max(0.0, band - core);
	bool active = mask.a > crack_alpha_threshold && (core > 0.001 || rim > 0.001);

	if (!active) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		vec4 refracted = texture(screen_texture, SCREEN_UV + SCREEN_PIXEL_SIZE * refraction_offset);
		vec3 crack_core_color = mix(refracted.rgb, vec3(0.02, 0.02, 0.03), crack_core_darkness * core);
		vec3 rim_color = vec3(0.84, 0.9, 1.0) * (crack_rim_brightness * rim);
		vec3 fractured = clamp(crack_core_color + rim_color, 0.0, 1.0);
		COLOR.rgb = fractured;
		COLOR.a = clamp(max(mask.a, core * 0.95 + rim * 0.65), 0.0, 1.0);
	}
}