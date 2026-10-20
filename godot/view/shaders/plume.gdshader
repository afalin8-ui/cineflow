// Факел двигателя (08, 2.9; пакет GЭ): две скрещённые плоскости от сопла, как в three.js
// (`enginePlume`): белое раскалённое горло и цветной язык, сходящий на нет. Длину тянет тяга
// (масштаб узла задаёт вид, view/battle_view.gd), а мелкая дрожь — здесь, по ИГРОВОМУ времени
// `now`: на паузе факел замирает, на 4× дрожит вчетверо чаще. Фаза дрожи — от места сопла:
// факелы соседей не дрожат в лад.
// Сетка: ось факела — y модели от −0,5 (сопло) до 0,5 (кончик), UV.y от 0 у сопла до 1;
// поперёк — UV.x от 0 до 1. Не выбирается мышью: в выборе мышью эффекты не кандидаты
// (input/picking.gd — капсула корпуса), и «малый за факелом» проверяется (C29).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.55, 0.8, 1.0);
uniform float now = 0.0;
uniform float power = 1.0;

varying float v_flick;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = fract(sin(dot(o, vec3(12.9898, 78.233, 37.719))) * 43758.5453) * 6.2831;
	v_flick = 1.0 + 0.07 * sin(now * 26.0 + ph) + 0.04 * sin(now * 41.0 + ph * 1.7);
	// кончик дрожит длиной: сдвиг вершин у кончика вдоль оси
	VERTEX.y = -0.5 + (VERTEX.y + 0.5) * v_flick;
}

void fragment() {
	float t = clamp(UV.y, 0.0, 1.0);
	float a = pow(1.0 - t, 1.7);
	float half_w = 0.5 - 0.40 * pow(t, 0.6);
	float across = abs(UV.x - 0.5) / max(half_w, 0.02);
	float body = smoothstep(1.0, 0.0, across);
	// горло — белое и узкое у самого сопла, дальше — цвет факела
	float throat = smoothstep(0.35, 0.0, t) * smoothstep(0.55, 0.0, across);
	vec3 col = color * body * (0.5 + 0.7 * (1.0 - t)) + vec3(1.0, 0.95, 0.85) * throat * 0.55;
	ALBEDO = col * a * power;
}
