// Гиперворонка (08, 2.11; пакет GЭ — упрощённо): раструб от устья (широкий конец, у корабля) к
// горловине в 3,4 радиуса, бегущие кольца и переливы сине-фиолетового, к горловине — светлее.
// Сложение, видна с обеих сторон. Время — ИГРОВОЕ (`now`): на паузе стоит.
// `open` 0…1 — насколько раскрыта; при 0 сетка схлопывается в точку и не рисует ничего, но
// конвейер её уже собран: узел воронки всегда «виден» (прогрев, 07-29, 08-15), а прячет его шейдер.
// Сетка — CylinderMesh (верх 0,18, низ 1, высота 3,4): y от −1,7 (устье) до 1,7 (горловина).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float now = 0.0;
uniform float open = 0.0;

varying float v_v;
varying float v_u;

void vertex() {
	v_v = clamp((VERTEX.y + 1.7) / 3.4, 0.0, 1.0);
	v_u = atan(VERTEX.z, VERTEX.x) / 6.2831853 + 0.5;
	float sc = open > 0.001 ? 0.6 + 0.4 * open : 0.0;
	VERTEX *= sc;
}

void fragment() {
	float t = now;
	float u = v_u + t * 0.175;
	float rings = fract(v_v * 4.0 - t * 1.6);
	float band = smoothstep(0.0, 0.35, rings) * smoothstep(1.0, 0.62, rings);
	float hue = u * 3.0 + t * 0.7 + v_v * 1.4;
	vec3 tint = mix(vec3(0.24, 0.55, 1.0), vec3(0.62, 0.42, 1.0), 0.5 + 0.5 * sin(hue * 3.14159));
	tint = mix(tint, vec3(0.80, 0.95, 1.0), v_v * v_v * v_v);
	float a = (0.20 + band * 0.85) * pow(v_v, 1.6) * open * smoothstep(0.0, 0.12, v_v);
	ALBEDO = tint * (1.0 + band * 1.2) * a;
}
