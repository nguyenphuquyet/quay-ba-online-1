shader_type spatial;
// Tia laser sân khấu: hình nón trong suốt, cộng sáng (additive), mờ dần ở đầu xa.
// Không ghi depth để nhiều tia chồng lên nhau vẫn sáng đẹp.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(0.2, 0.85, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 1.0;
// Độ trong suốt của tia: nhỏ để nhìn xuyên qua, không chặn tầm nhìn.
uniform float opacity : hint_range(0.0, 1.0) = 0.3;
// Độ mềm của mép tia: càng lớn lõi càng mảnh, tia càng trong.
uniform float edge_softness : hint_range(0.2, 6.0) = 1.5;
uniform float core_boost : hint_range(0.0, 4.0) = 0.35;

void fragment() {
	// UV.y = 0 ở đầu nguồn, 1 ở đầu xa của CylinderMesh.
	// Giữ tia sáng gần như đều tới sàn, chỉ dịu nhẹ ở cuối.
	float length_fade = mix(1.0, 0.65, smoothstep(0.55, 1.0, UV.y));
	// NORMAL và VIEW đều ở view space: tâm tia hướng về camera sáng hơn mép.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = pow(facing, edge_softness);
	float core = pow(facing, 12.0) * core_boost;
	// Gộp độ trong suốt vào ALBEDO và để ALPHA = 1.0: additive blend cho kết
	// quả giống nhau giữa Forward+ và Compatibility, không bị đục ở một renderer.
	ALBEDO = beam_color.rgb * (1.0 + core) * intensity * (body + core) * length_fade * beam_color.a * opacity;
	ALPHA = 1.0;
}
