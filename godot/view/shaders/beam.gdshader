// Лучи и трассы из пула MultiMesh (архитектура, 5.3): один вызов отрисовки на все.
// Данные экземпляра:
//   origin            — начало A;
//   basis.x           — вектор A → B;
//   basis.z           — цвет (rgb) — не через цвет экземпляра: так одинаково
//                       в Forward+ и Compatibility;
//   INSTANCE_CUSTOM   — (рождение, срок, толщина в мире, яркость).
// Квад разворачивается вокруг оси луча к камере (часть 08, 5.2), а толщина
// не меньше min_px точек экрана (09, 11.8: при 2400 трасса ПВО иначе меньше точки).
// Умерший (возраст вне срока) складывается за камеру — ничего не рисует.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform float now = 0.0;
uniform float min_px = 1.6;

varying float v_fade;
varying float v_across;
varying vec3 v_col;

void vertex() {
	float age = now - INSTANCE_CUSTOM.x;
	float life = max(INSTANCE_CUSTOM.y, 0.001);
	vec3 a = MODEL_MATRIX[3].xyz;
	vec3 b = a + MODEL_MATRIX[0].xyz;
	vec3 va = (VIEW_MATRIX * vec4(a, 1.0)).xyz;
	vec3 vb = (VIEW_MATRIX * vec4(b, 1.0)).xyz;
	vec3 vp = mix(va, vb, VERTEX.x);
	vec3 side = cross(vb - va, vp);
	side = length(side) > 1e-6 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	float px = 2.0 * max(-vp.z, 1.0) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = max(INSTANCE_CUSTOM.z, min_px * px);
	v_across = VERTEX.y;
	vp += side * VERTEX.y * w;
	bool alive = age >= 0.0 && age <= life;
	v_fade = alive ? (1.0 - age / life) * INSTANCE_CUSTOM.w : 0.0;
	v_col = MODEL_MATRIX[2].xyz;
	VERTEX = alive ? vp : vec3(0.0, 0.0, 10.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float core = clamp(1.0 - abs(v_across) * 2.0, 0.0, 1.0);
	float a = pow(core, 1.4) * v_fade;
	ALBEDO = (v_col + vec3(pow(core, 8.0)) * 0.8) * a;
}
