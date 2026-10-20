// Дым и обломки из пула MultiMesh (пакет GЭ; 08, 1.3: «взрывы оранжевые, с тёмным дымом, а не
// белые кляксы»). Обычное смешивание, а не сложение: дым ЗАСЛОНЯЕТ свет за собой — сложением он
// только подсвечивал бы, и тёмного дыма не бывает вовсе. Данные экземпляра — как у частиц
// огня (particle.gdshader): origin, basis.x — скорость, basis.y — (размер в начале, в конце,
// вид: 0 — клуб дыма, 1 — обломок), basis.z — цвет, INSTANCE_CUSTOM — (рождение, срок,
// сопротивление, непрозрачность). Обломок первые 20% срока раскалён, потом тёмный.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform float now = 0.0;
uniform float min_px = 1.4;

varying vec2 v_uv;
varying vec3 v_col;
varying float v_a;
varying float v_mode;
varying float v_k;
varying float v_seed;

void vertex() {
	float age = now - INSTANCE_CUSTOM.x;
	float life = max(INSTANCE_CUSTOM.y, 0.001);
	float k = clamp(age / life, 0.0, 1.0);
	float drag = INSTANCE_CUSTOM.z;
	float t = max(age, 0.0);
	float s = drag > 0.001 ? (1.0 - exp(-drag * t)) / drag : t;
	vec3 p = MODEL_MATRIX[3].xyz + MODEL_MATRIX[0].xyz * s;
	vec3 c = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	float px = 2.0 * max(-c.z, 1.0) / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float mode = MODEL_MATRIX[1].z;
	float size = max(mix(MODEL_MATRIX[1].x, MODEL_MATRIX[1].y, mode < 0.5 ? sqrt(k) : k), min_px * px);
	// поворот клуба — от места рождения: клубы одной тучи не повторяют друг друга
	v_seed = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float ang = v_seed * 6.2831 + (mode < 0.5 ? k * 0.8 : age * 5.0);
	vec2 q = vec2(cos(ang) * VERTEX.x - sin(ang) * VERTEX.y, sin(ang) * VERTEX.x + cos(ang) * VERTEX.y);
	bool alive = age >= 0.0 && age <= life;
	v_k = k;
	v_mode = mode;
	v_uv = q * 2.0;
	v_col = MODEL_MATRIX[2].xyz;
	float fade = mode < 0.5 ? min(1.0, k * 8.0) * pow(1.0 - k, 1.3) : 1.0 - k * k;
	v_a = alive ? fade * INSTANCE_CUSTOM.w : 0.0;
	VERTEX = alive ? c + vec3(VERTEX.xy * size, 0.0) : vec3(0.0, 0.0, 10.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r = length(v_uv);
	float a;
	vec3 col = v_col;
	if (v_mode < 0.5) {
		// клуб: мягкий, с неровным краем (три лепестка от своего зерна)
		float th = atan(v_uv.y, v_uv.x);
		float edge = 0.82 + 0.12 * sin(th * 3.0 + v_seed * 20.0) + 0.06 * sin(th * 5.0 - v_seed * 11.0);
		a = smoothstep(edge, edge * 0.35, r);
	} else {
		// обломок: угловатый кусок, раскалён в начале
		vec2 m = abs(v_uv);
		a = step(m.x + m.y * 0.7, 0.9);
		col = mix(vec3(1.0, 0.55, 0.2), v_col, smoothstep(0.0, 0.2, v_k));
	}
	ALBEDO = col;
	ALPHA = clamp(a * v_a, 0.0, 1.0);
}
