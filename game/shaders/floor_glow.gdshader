shader_type spatial;
// Vệt sáng trên sàn nơi tia laser chạm đất: đĩa mờ dần ra mép, cộng sáng.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.8, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float falloff = smoothstep(1.0, 0.0, radius);
	falloff = pow(falloff, 1.7);
	ALBEDO = glow_color.rgb * intensity;
	ALPHA = clamp(falloff * glow_color.a, 0.0, 1.0);
}
