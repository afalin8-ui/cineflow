// Огонь, искры и ударная волна из пула MultiMesh (пакет GЭ; архитектура, 5.3): частица летит
// и гаснет в вершинном шейдере от `now` — процессор пишет одну запись на рождение и ничего
// каждый кадр. В Compatibility нет emit_particle (архитектура, 5.1) — поэтому пул, а не
// GPUParticles3D. Сложение: огонь светится сам.
// Данные экземпляра:
//   origin            — место рождения;
//   basis.x           — скорость в мире (ед/с), гаснет с сопротивлением drag;
//   basis.y           — (размер в начале, размер в конце, вид): 0 — огненный клуб (цвет идёт
//                       от жёлтого через цвет взрыва к тёмно-красному), 1 — искра (росчерк вдоль
//                       хода), 2 — кольцо ударной волны, 3 — мягкое свечение без смены цвета;
//   basis.z           — цвет (rgb);
//   INSTANCE_CUSTOM   — (рождение, срок, сопротивление, яркость). Рождение в будущем —
//                       отложенный (вторичный взрыв): до него не виден.
// Не меньше min_px точек экрана, иначе на дальнем виде искра — пылинка (09, 11.8).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform float now = 0.0;
uniform float min_px = 1.6;

varying vec2 v_uv;
varying vec3 v_col;
varying float v_fade;
varying float v_mode;
varying float v_k;

void vertex() {
	float age = now - INSTANCE_CUSTOM.x;
	float life = max(INSTANCE_CUSTOM.y, 0.001);
	float k = clamp(age / life, 0.0, 1.0);
	float drag = INSTANCE_CUSTOM.z;
	float t = max(age, 0.0);
	float s = drag > 0.001 ? (1.0 - exp(-drag * t)) / drag : t;
	vec3 vel = MODEL_MATRIX[0].xyz;
	vec3 p = MODEL_MATRIX[3].xyz + vel * s;
	vec3 c = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	float px = 2.0 * max(-c.z, 1.0) / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float mode = MODEL_MATRIX[1].z;
	float grow = mode > 1.5 && mode < 2.5 ? sqrt(k) : (mode < 0.5 ? pow(k, 0.6) : k);
	float size = max(mix(MODEL_MATRIX[1].x, MODEL_MATRIX[1].y, grow), min_px * px);
	vec2 off = VERTEX.xy * size;
	if (mode > 0.5 && mode < 1.5) {
		// искра — росчерк вдоль хода на экране: длина от скорости на этом миге
		vec3 vv = (VIEW_MATRIX * vec4(vel * exp(-drag * t), 0.0)).xyz;
		vec2 d = length(vv.xy) > 1e-4 ? normalize(vv.xy) : vec2(1.0, 0.0);
		float len = max(size, length(vv.xy) * 0.07);
		off = d * VERTEX.x * len + vec2(-d.y, d.x) * VERTEX.y * size;
	}
	bool alive = age >= 0.0 && age <= life;
	v_k = k;
	v_mode = mode;
	v_uv = VERTEX.xy * 2.0;
	v_col = MODEL_MATRIX[2].xyz;
	float fade = mode < 0.5 ? pow(1.0 - k, 1.4) * min(1.0, k * 12.0 + 0.25) : (mode < 2.5 ? (1.0 - k) * (1.0 - k) : 1.0 - k);
	v_fade = alive ? fade * INSTANCE_CUSTOM.w : 0.0;
	VERTEX = alive ? c + vec3(off, 0.0) : vec3(0.0, 0.0, 10.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r = length(v_uv);
	float a;
	vec3 col = v_col;
	if (v_mode < 0.5) {
		// огненный клуб: мягкий край, цвет остывает — жёлтый → цвет взрыва → тёмно-красный
		a = smoothstep(1.0, 0.15, r);
		vec3 hot = vec3(1.0, 0.5, 0.15);
		vec3 cold = vec3(0.45, 0.08, 0.03);
		col = v_k < 0.3 ? mix(hot, v_col, v_k / 0.3) : mix(v_col, cold, (v_k - 0.3) / 0.7);
	} else if (v_mode < 1.5) {
		a = smoothstep(1.0, 0.0, abs(v_uv.y)) * smoothstep(1.0, 0.6, abs(v_uv.x));
	} else if (v_mode < 2.5) {
		// кольцо: тонкий обод у края квадрата
		a = smoothstep(0.84, 0.94, r) * smoothstep(1.0, 0.96, r);
	} else {
		a = smoothstep(1.0, 0.0, r);
		a *= a;
	}
	ALBEDO = col * a * v_fade;
}
