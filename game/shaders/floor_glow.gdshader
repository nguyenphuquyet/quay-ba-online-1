shader_type spatial;
// Vệt sáng trên sàn nơi tia laser chạm đất: đĩa mờ dần ra mép, cộng sáng.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.8, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 1.0;
// Độ dốc của vệt sáng: lớn thì đốm gọn, nhỏ thì vũng sáng trải rộng.
uniform float falloff_power : hint_range(0.5, 4.0) = 1.7;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float falloff = smoothstep(1.0, 0.0, radius);
	falloff = pow(falloff, falloff_power);
	// Gộp alpha vào ALBEDO để additive blend ổn định trên mọi renderer.
	ALBEDO = glow_color.rgb * intensity * falloff * glow_color.a;
	ALPHA = 1.0;
}
