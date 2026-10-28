shader_type canvas_item;
// mask.r: 1 = dirt, 0 = cleared. sweep (0..1) dissolves any remaining dirt for the reveal.
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec4 rock_tint : source_color = vec4(0.65, 0.49, 0.32, 1.0);
uniform float sweep : hint_range(0.0, 1.0) = 0.0;
uniform float noise_scale = 18.0;
uniform float corner = 0.042;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float m = texture(mask, UV).r;
	float n = vnoise(UV * noise_scale) * 0.6 + vnoise(UV * noise_scale * 2.7) * 0.4;
	float a = smoothstep(0.42, 0.58, m + (n - 0.5) * 0.35 - sweep * 1.2);
	vec3 col = rock_tint.rgb * (0.78 + 0.34 * n);
	col *= mix(0.8, 1.0, smoothstep(0.5, 1.0, m)); // darker rim where dirt thins
	vec2 q = abs(UV - 0.5) - (0.5 - corner);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
	a *= 1.0 - smoothstep(-0.002, 0.002, d);
	COLOR = vec4(col, a);
}
