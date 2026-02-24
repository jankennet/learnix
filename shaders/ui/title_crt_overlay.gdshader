shader_type canvas_item;
render_mode unshaded;

uniform float curvature : hint_range(0.0, 0.1) = 0.012;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.08;
uniform float scanline_frequency : hint_range(1.0, 10.0) = 2.8;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.16;
uniform float flicker_intensity : hint_range(0.0, 0.1) = 0.01;
uniform vec3 bezel_color : source_color = vec3(0.08, 0.08, 0.08);

vec2 curve_uv(vec2 uv) {
	vec2 centered = uv * 2.0 - 1.0;
	vec2 offset = centered.yx * centered.yx * curvature;
	centered += centered * offset;
	return centered * 0.5 + 0.5;
}

void fragment() {
	vec2 curved_uv = curve_uv(UV);
	bool out_of_bounds = curved_uv.x < 0.0 || curved_uv.x > 1.0 || curved_uv.y < 0.0 || curved_uv.y > 1.0;

	if (out_of_bounds) {
		COLOR = vec4(bezel_color, 0.35);
	} else {
		float scanline = sin(curved_uv.y * SCREEN_PIXEL_SIZE.y * scanline_frequency * 1000.0) * 0.5 + 0.5;
		float scan_dark = scanline_intensity * (1.0 - scanline);

		float flicker = 1.0 - flicker_intensity * sin(TIME * 8.0) * sin(TIME * 21.0);
		float flicker_dark = 1.0 - flicker;

		vec2 vignette_uv = curved_uv * (1.0 - curved_uv);
		float vignette = vignette_uv.x * vignette_uv.y * 15.0;
		vignette = pow(vignette, vignette_intensity);
		float vignette_dark = 1.0 - clamp(vignette, 0.0, 1.0);

		float alpha = clamp(scan_dark + flicker_dark + vignette_dark * 0.6, 0.0, 0.35);

		COLOR = vec4(vec3(0.0), alpha);
	}
}
