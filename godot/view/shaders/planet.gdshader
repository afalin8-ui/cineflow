// Планета под столом (09, 11.7; часть 08, ловушка 21): суша, океан и облака
// шумом по направлению от центра, край — дымкой атмосферы. Своих картинок нет:
// ничего не грузится.
// День и ночь — от ЗВЕЗДЫ (план GЭ, п. 6): свет считается здесь по `sun_dir` (его ставит
// view/space_env.gd — то же направление, что у тёплого ключа и диска на небе), а не
// светом сцены: с GЭ у сцены есть холодная заливка и «фара» из камеры, и они залили бы ночную
// сторону (до GЭ её яркость была 13% дневной, замер копией; теперь 3%). Ночная сторона — тёмная,
// но не чёрная; блик океана — по звезде; дымка у края — ярче на дневной стороне (до GЭ она
// светилась ровно и на снимке была заметнее с тёмной стороны).
shader_type spatial;
render_mode cull_back, unshaded;

uniform vec3 ocean : source_color = vec3(0.05, 0.13, 0.26);
uniform vec3 shore : source_color = vec3(0.10, 0.24, 0.34);
uniform vec3 land_a : source_color = vec3(0.24, 0.30, 0.16);
uniform vec3 land_b : source_color = vec3(0.42, 0.36, 0.24);
uniform vec3 ice : source_color = vec3(0.86, 0.90, 0.94);
uniform vec3 haze : source_color = vec3(0.35, 0.58, 1.0);
uniform float haze_k = 0.9;
uniform vec3 sun_dir = vec3(-0.645, 0.616, -0.452);
uniform vec3 sun_col : source_color = vec3(1.0, 0.9, 0.78);
uniform float sun_k = 1.15;
uniform vec3 night : source_color = vec3(0.014, 0.02, 0.04);
// 1 — откат проверки: дымка у края о звезде не знает, светится ровно по кругу, как до GЭ
// (view/space_env.gd → rollback_flat_haze)
uniform float flat_k = 0.0;

varying vec3 v_dir;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash13(i), b = hash13(i + vec3(1, 0, 0)), c = hash13(i + vec3(0, 1, 0)), d = hash13(i + vec3(1, 1, 0));
	float e = hash13(i + vec3(0, 0, 1)), g = hash13(i + vec3(1, 0, 1)), h = hash13(i + vec3(0, 1, 1)), k = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0, a = 0.5;
	for (int i = 0; i < 6; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec3(4.1, 1.3, 7.7);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(v_dir);
	float h = fbm(d * 2.6);
	float lat = abs(d.y);
	vec3 col = mix(ocean, shore, smoothstep(0.44, 0.5, h));
	float land = smoothstep(0.5, 0.53, h);
	col = mix(col, mix(land_a, land_b, smoothstep(0.55, 0.7, fbm(d * 7.0 + 3.0))), land);
	col = mix(col, ice, smoothstep(0.78, 0.86, lat + (h - 0.5) * 0.3));
	float cloud = smoothstep(0.52, 0.72, fbm(d * 4.5 + vec3(9.0, 2.0, 5.0)));
	col = mix(col, vec3(0.92), cloud * 0.75);
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 sd = normalize(sun_dir);
	float ndl = dot(n, sd);
	// мягкий терминатор: сумерки на полосе шириной в десятую часть радиуса
	float lit = smoothstep(-0.08, 0.3, ndl) * max(ndl * 0.75 + 0.25, 0.0);
	vec3 v_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float spec = pow(clamp(dot(reflect(-sd, n), v_w), 0.0, 1.0), 40.0) * (1.0 - max(land, cloud)) * 0.6;
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float day = smoothstep(-0.25, 0.4, ndl);
	vec3 glow = haze * pow(rim, 3.0) * haze_k * mix(0.18 + 0.82 * day, 1.0, flat_k);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// В Compatibility бледное сложение пропадает (godot/CLAUDE.md, 24 — тот же урок, что у стенки
	// купола): дымка ночной стороны там выходила чёрной, и край диска сливался с небом — проверка
	// ореола (tests/test_render_table.gd → test_halo_nine_shots) нашла «чёрное кольцо венца» в 7
	// точках. Ту же дымку поднимаем к экранным цветам, как это делает Forward+.
	glow = pow(glow, vec3(0.4545));
#endif
	ALBEDO = col * (sun_col * lit * sun_k + night) + sun_col * spec * smoothstep(0.0, 0.2, ndl) + glow;
}
