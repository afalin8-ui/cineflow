// Светящиеся точки, которые живут, пока живёт их хозяин (ракеты и торпеды в полёте):
// квад к камере, положение пишет вид каждый кадр. Не меньше min_px точек экрана.
// basis.z — цвет; INSTANCE_CUSTOM.z — размер в мире, .w — яркость (0 — не рисовать).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform float min_px = 3.0;

varying vec2 v_uv;
varying vec3 v_col;
varying float v_pow;

void vertex() {
	vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	// abs: [1][1] здесь ОТРИЦАТЕЛЕН в обоих отрисовщиках (4.7.2, проверено в G2) — без него
	// px < 0, и «не меньше min_px точек» не действовало вовсе (с G0b)
	float px = 2.0 * max(-c.z, 1.0) / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float size = max(INSTANCE_CUSTOM.z, min_px * px);
	v_uv = VERTEX.xy * 2.0;
	v_col = MODEL_MATRIX[2].xyz;
	v_pow = INSTANCE_CUSTOM.w;
	VERTEX = v_pow > 0.0 ? c + vec3(VERTEX.xy * size, 0.0) : vec3(0.0, 0.0, 10.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r = length(v_uv);
	float a = clamp(1.0 - r, 0.0, 1.0);
	a = a * a * v_pow;
	ALBEDO = (v_col + vec3(pow(clamp(1.0 - r * 2.0, 0.0, 1.0), 2.0))) * a;
}
