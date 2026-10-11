// Пояс тяжёлого и круг дальности (архитектура, 5.5; доктрина 09, 6.7): квад на плоскости
// боя, рисует шейдер. Внешний круг — дальность, внутренний ПУНКТИРОМ — мёртвая зона
// (у своего тусклее дальности, у чужого ярче: ближе пунктира его главный калибр не
// бьёт — там работают батарея и наши лёгкие), бледная заливка между ними. Круг
// дальности лёгкого — тот же шейдер без мёртвой зоны (inner = 0). Толщина линий —
// в точках экрана (fwidth): на любом приближении кольцо тонкое, но не пропадает.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.62, 0.85, 1.0, 1.0);
uniform float inner = 0.4;          // мёртвая зона долей дальности; 0 — нет
uniform float outer_alpha = 0.55;
uniform float inner_alpha = 0.35;
uniform float fill_alpha = 0.06;
uniform float line_px = 1.6;
uniform float dashes = 48.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float fw = max(fwidth(r), 1e-5);
	float outer = 1.0 - smoothstep(line_px * 0.5 * fw, (line_px * 0.5 + 1.0) * fw, abs(r - 0.985));
	float a = outer * outer_alpha;
	if (inner > 0.0) {
		float ring = 1.0 - smoothstep(line_px * 0.5 * fw, (line_px * 0.5 + 1.0) * fw, abs(r - inner));
		float ang = atan(p.y, p.x) / 6.2831853 + 0.5;
		float dash = step(0.45, fract(ang * dashes));
		a = max(a, ring * dash * inner_alpha);
		if (r > inner && r < 0.985) {
			a = max(a, fill_alpha);
		}
	}
	if (a <= 0.002) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = a * color.a;
}
