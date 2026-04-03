shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float feather : hint_range(0.0, 0.08) = 0.02;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * tint;
	float cutoff = 1.0 - clamp(progress, 0.0, 1.0);
	float alpha_mask = smoothstep(cutoff - feather, cutoff + feather, UV.y);
	COLOR = vec4(tex.rgb, tex.a * alpha_mask);
}