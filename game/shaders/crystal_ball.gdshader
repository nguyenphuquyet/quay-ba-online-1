shader_type spatial;
// Quả cầu pha lê của đèn magic ball: bề mặt khảm nhiều ô gương nhỏ,
// phát sáng màu để trông giống đèn disco ball ngoài đời.

uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.75, 1.0);
uniform float facet_scale : hint_range(4.0, 32.0) = 16.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(vec2(UV.x * facet_scale, UV.y * facet_scale * 0.55));
	float h = hash21(cell);
	vec3 mirror = mix(vec3(0.82, 0.86, 1.0), vec3(1.0), step(0.6, h));
	vec3 glow = mix(tint.rgb, vec3(1.0), step(0.8, h));
	ALBEDO = mirror * 0.5;
	METALLIC = 0.85;
	ROUGHNESS = 0.12 + h * 0.12;
	EMISSION = glow * (0.35 + 0.55 * step(0.6, h));
}
