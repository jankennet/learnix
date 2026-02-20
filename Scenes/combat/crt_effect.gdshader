shader_type canvas_item;

// CRT Terminal Effect Shader
// Simulates old-school phosphor terminal display

uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.08;
uniform float scanline_frequency : hint_range(1.0, 10.0) = 3.0;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.2;
uniform float curvature : hint_range(0.0, 0.1) = 0.015;
uniform float flicker_intensity : hint_range(0.0, 0.1) = 0.01;
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.12;
uniform float chromatic_aberration : hint_range(0.0, 0.01) = 0.0008;
uniform vec3 phosphor_color : source_color = vec3(0.3, 0.95, 0.4);
uniform vec3 bezel_color : source_color = vec3(0.65, 0.68, 0.62);
uniform float bezel_glow : hint_range(0.0, 1.0) = 0.2;

// Use screen texture to read what's behind the overlay
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Screen curvature distortion
vec2 curve_uv(vec2 uv) {
	vec2 centered = uv * 2.0 - 1.0;
	vec2 offset = centered.yx * centered.yx * curvature;
	centered += centered * offset;
	return centered * 0.5 + 0.5;
}

void fragment() {
	// Apply curvature to screen UV
	vec2 curved_uv = curve_uv(SCREEN_UV);
	
	// Check if we're outside the curved screen bounds
	bool out_of_bounds = curved_uv.x < 0.0 || curved_uv.x > 1.0 || curved_uv.y < 0.0 || curved_uv.y > 1.0;
	
	if (out_of_bounds) {
		// Create a subtle bezel/frame effect instead of pure black
		// Calculate distance from edge for glow effect
		vec2 edge_dist = min(SCREEN_UV, 1.0 - SCREEN_UV);
		float edge_factor = min(edge_dist.x, edge_dist.y) * 10.0;
		edge_factor = clamp(edge_factor, 0.0, 1.0);
		
		// Bezel with subtle phosphor glow bleeding from screen
		vec3 bezel = bezel_color * (0.8 + 0.2 * edge_factor);
		bezel += phosphor_color * bezel_glow * (1.0 - edge_factor) * 0.15;
		
		COLOR = vec4(bezel, 1.0);
	} else {
		// Read from screen texture with chromatic aberration
		float r = texture(screen_texture, curved_uv + vec2(chromatic_aberration, 0.0)).r;
		float g = texture(screen_texture, curved_uv).g;
		float b = texture(screen_texture, curved_uv - vec2(chromatic_aberration, 0.0)).b;
		float a = texture(screen_texture, curved_uv).a;
		
		vec3 col = vec3(r, g, b);
		
		// Phosphor glow - boost greens for that classic terminal look
		float luminance = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, phosphor_color * luminance * 1.5, glow_intensity);
		
		// Scanlines
		float scanline = sin(curved_uv.y * SCREEN_PIXEL_SIZE.y * scanline_frequency * 1000.0) * 0.5 + 0.5;
		col *= 1.0 - scanline_intensity * (1.0 - scanline);
		
		// Flicker
		float flicker = 1.0 - flicker_intensity * sin(TIME * 8.0) * sin(TIME * 21.0);
		col *= flicker;
		
		// Vignette
		vec2 vignette_uv = curved_uv * (1.0 - curved_uv);
		float vignette = vignette_uv.x * vignette_uv.y * 15.0;
		vignette = pow(vignette, vignette_intensity);
		col *= vignette;
		
		COLOR = vec4(col, a);
	}
}
