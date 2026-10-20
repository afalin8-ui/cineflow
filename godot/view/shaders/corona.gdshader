// Венец планеты: оболочка чуть больше планеты, видна изнутри (cull_front),
// светится сложением — у края диска голубое кольцо, к наружному краю гаснет.
// Сложение не бывает чёрным: проверка ореола (тест картинки) ищет как раз
// чёрное кольцо вокруг диска — им выглядел срез неба дальней плоскостью.
// Венец знает, где звезда (план GЭ, п. 6; `sun_dir` ставит view/space_env.gd): на дневной
// стороне ярче, на ночной — тусклая полоска (не ноль), и против звезды светится тёплым —
// свет проходит сквозь атмосферу на краю.
shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 glow : source_color = vec3(0.30, 0.55, 1.0);
uniform vec3 warm : source_color = vec3(1.0, 0.62, 0.36);
uniform float power = 2.4;
uniform float strength = 1.6;
uniform vec3 sun_dir = vec3(-0.645, 0.616, -0.452);
// 1 — откат проверки: венец о звезде не знает, как до GЭ (view/space_env.gd → rollback_flat_haze)
uniform float flat_k = 0.0;

varying vec3 v_out;

void vertex() {
	v_out = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
}

void fragment() {
	// у оболочки, видимой изнутри, нормаль смотрит от камеры
	float f = clamp(dot(-NORMAL, VIEW), 0.0, 1.0);
	// у края оболочки f → 0 (гаснет), к линии планеты растёт
	float a = pow(f, power);
	vec3 sd = normalize(sun_dir);
	float day = smoothstep(-0.35, 0.55, dot(normalize(v_out), sd));
	vec3 view_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	// против звезды: камера смотрит на край, а звезда — за планетой
	float back = pow(clamp(dot(-view_w, sd), 0.0, 1.0), 6.0);
	ALBEDO = (glow * mix(0.3 + 0.9 * day, 1.0, flat_k) + warm * back * 0.8 * (1.0 - flat_k)) * a * strength;
}
