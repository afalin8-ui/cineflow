// Летящие отрезки (трассы ПВО, очереди батареи) из пула MultiMesh (архитектура, 5.3;
// часть 08, ловушка 18: огонь — длинные росчерки, а не мгновенная нитка во всю
// дистанцию — та читается подсветкой цели). Один вызов отрисовки на все.
// Данные экземпляра:
//   origin            — начало A;  basis.x — вектор A → B;
//   basis.y.x         — длина отрезка долей пути (0…1);
//   basis.z           — цвет (rgb);
//   INSTANCE_CUSTOM   — (рождение, время пути, толщина в мире, яркость).
// Голова идёт от A к B за «время пути», хвост — на длину отрезка позади. Рождение
// в будущем (очередь батареи) — экземпляр ещё не виден. Толщина — не меньше min_px
// точек экрана (09, 11.8).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform float now = 0.0;
uniform float min_px = 1.6;

varying float v_fade;
varying float v_across;
varying float v_along;
varying vec3 v_col;

void vertex() {
	float age = now - INSTANCE_CUSTOM.x;
	float life = max(INSTANCE_CUSTOM.y, 0.001);
	float seg = clamp(MODEL_MATRIX[1].x, 0.0, 1.0);
	float t = age / life;
	float head = clamp(t * (1.0 + seg), 0.0, 1.0);
	float tail = clamp(t * (1.0 + seg) - seg, 0.0, 1.0);
	vec3 a = MODEL_MATRIX[3].xyz;
	vec3 b = a + MODEL_MATRIX[0].xyz;
	vec3 va = (VIEW_MATRIX * vec4(mix(a, b, tail), 1.0)).xyz;
	vec3 vb = (VIEW_MATRIX * vec4(mix(a, b, head), 1.0)).xyz;
	vec3 vp = mix(va, vb, VERTEX.x);
	vec3 side = cross(vb - va, vp);
	side = length(side) > 1e-6 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	// abs: [1][1] здесь ОТРИЦАТЕЛЕН в обоих отрисовщиках (4.7.2, проверено в G2) — без него
	// px < 0, и «не меньше min_px точек» не действовало вовсе (с G0b)
	float px = 2.0 * max(-vp.z, 1.0) / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float w = max(INSTANCE_CUSTOM.z, min_px * px);
	v_across = VERTEX.y;
	v_along = VERTEX.x;
	vp += side * VERTEX.y * w;
	bool alive = age >= 0.0 && tail < 1.0 && head > tail;
	v_fade = alive ? INSTANCE_CUSTOM.w : 0.0;
	v_col = MODEL_MATRIX[2].xyz;
	VERTEX = alive ? vp : vec3(0.0, 0.0, 10.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float core = clamp(1.0 - abs(v_across) * 2.0, 0.0, 1.0);
	// ярче к голове: отрезок читается летящим, а не полосой
	float a = pow(core, 1.3) * v_fade * (0.35 + 0.65 * v_along);
	ALBEDO = (v_col + vec3(pow(core, 8.0)) * 0.7) * a;
}
