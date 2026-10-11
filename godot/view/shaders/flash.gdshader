// Вспышки из пула MultiMesh (архитектура, 5.3): квад к камере, растёт и гаснет
// в вершинном шейдере от `now`. Данные экземпляра:
//   origin          — место;
//   basis.z         — цвет (rgb);
//   INSTANCE_CUSTOM — (рождение, срок, размер в мире, яркость).
// Не меньше min_px точек экрана, иначе на дальнем виде вспышка — пылинка.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform float now = 0.0;
uniform float min_px = 3.0;

varying float v_fade;
varying vec2 v_uv;
varying vec3 v_col;

void vertex() {
	float age = now - INSTANCE_CUSTOM.x;
	float life = max(INSTANCE_CUSTOM.y, 0.001);
	float k = clamp(age / life, 0.0, 1.0);
	vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	// abs: [1][1] здесь ОТРИЦАТЕЛЕН в обоих отрисовщиках (4.7.2, проверено в G2) — без него
	// px < 0, и «не меньше min_px точек» не действовало вовсе (с G0b)
	float px = 2.0 * max(-c.z, 1.0) / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float size = max(INSTANCE_CUSTOM.z * (0.35 + 0.65 * sqrt(k)), min_px * px);
	bool alive = age >= 0.0 && age <= life;
	v_fade = alive ? (1.0 - k) * (1.0 - k) * INSTANCE_CUSTOM.w : 0.0;
	v_uv = VERTEX.xy * 2.0;
	v_col = MODEL_MATRIX[2].xyz;
	VERTEX = alive ? c + vec3(VERTEX.xy * size, 0.0) : vec3(0.0, 0.0, 10.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r = length(v_uv);
	float a = clamp(1.0 - r, 0.0, 1.0);
	a = a * a * v_fade;
	ALBEDO = (v_col + vec3(pow(clamp(1.0 - r * 1.8, 0.0, 1.0), 3.0))) * a;
}
