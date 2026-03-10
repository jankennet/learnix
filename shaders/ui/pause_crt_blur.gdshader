shader_type canvas_item;
render_mode unshaded;

uniform float curvature : hint_range(0.0, 0.1) = 0.024;
uniform vec3 bezel_color : source_color = vec3(0.08, 0.08, 0.08);
uniform float blur_size : hint_range(0.0, 4.0) = 1.35;
uniform float darken : hint_range(0.0, 1.0) = 0.34;
uniform float static_strength : hint_range(0.0, 0.5) = 0.18;
uniform float scanline_strength : hint_range(0.0, 0.3) = 0.11;
uniform float chromatic_aberration : hint_range(0.0, 0.01) = 0.0018;
uniform float custom_time = 0.0;

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 curve_uv(vec2 uv) {
	vec2 centered = uv * 2.0 - 1.0;
	vec2 offset = centered.yx * centered.yx * (curvature * 2.4);
	centered += centered * offset;
	return centered * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = curve_uv(UV);
	uv.x += (rand(vec2(floor(UV.y * 140.0), floor(custom_time * 45.0))) - 0.5) * 0.008;
	uv.y += sin(UV.x * 1050.0 + custom_time * 14.0) * 0.0014;
	bool out_of_bounds = uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
	if (out_of_bounds) {
		COLOR = vec4(bezel_color, 1.0);
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE * blur_size;

		vec3 c = vec3(0.0);
		c += texture(TEXTURE, uv + vec2(-px.x, -px.y)).rgb;
		c += texture(TEXTURE, uv + vec2(0.0, -px.y)).rgb;
		c += texture(TEXTURE, uv + vec2(px.x, -px.y)).rgb;
		c += texture(TEXTURE, uv + vec2(-px.x, 0.0)).rgb;
		c += texture(TEXTURE, uv).rgb;
		c += texture(TEXTURE, uv + vec2(px.x, 0.0)).rgb;
		c += texture(TEXTURE, uv + vec2(-px.x, px.y)).rgb;
		c += texture(TEXTURE, uv + vec2(0.0, px.y)).rgb;
		c += texture(TEXTURE, uv + vec2(px.x, px.y)).rgb;
		c /= 9.0;

		float r = texture(TEXTURE, uv + vec2(chromatic_aberration, 0.0)).r;
		float g = c.g;
		float b = texture(TEXTURE, uv - vec2(chromatic_aberration, 0.0)).b;
		c = vec3(r, g, b);

		float grain = rand(floor(uv * vec2(960.0, 540.0)) + custom_time * 170.0) - 0.5;
		float scan = sin((uv.y + custom_time * 0.3) * 900.0) * 0.5 + 0.5;
		float line_seed = rand(vec2(floor(uv.y * 320.0), floor(custom_time * 60.0)));
		float line_static = step(0.972, line_seed);
		float vignette = smoothstep(1.0, 0.15, length((UV - 0.5) * 1.45));

		c *= (1.0 - darken) * vignette;
		c += vec3(grain * static_strength + scan * scanline_strength * 0.35 + line_static * 0.3);
		c = clamp(c, 0.0, 1.0);
		COLOR = vec4(c, 1.0);
	}
}
