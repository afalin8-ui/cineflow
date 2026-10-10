// Небо: звёзды и туманность шейдером (архитектура, 5.6; 09, 11.7).
// Рисуется без глубины и от дальней плоскости не зависит — ореола у планеты
// по устройству нет (часть 08, ловушка 2: в three.js небо было сферой вокруг
// центра поля, и дальняя плоскость резала её, оставляя чёрное пятно).
// Звезда — точка в 1–2 пикселя, а не пятно: размер задан в ПИКСЕЛЯХ экрана
// (px_angle — угол одного пикселя, его ставит view/space_env.gd по окну);
// при обзоре 30° сетка «по направлению» без этого давала кляксы в 5–6 точек.
// В проходе карты окружения (AT_CUBEMAP_PASS) звёзд нет, туманность ярче —
// это отражения и окружающий свет для металла кораблей (часть 08, ловушка 11).
// ЛОВУШКИ: в шейдере неба нельзя писать return — он не собирается.
// test_magenta — проверочная сборка (тест ореола): всё небо одного цвета.
shader_type sky;

uniform vec3 deep : source_color = vec3(0.006, 0.008, 0.016);
uniform vec3 neb_a : source_color = vec3(0.16, 0.08, 0.26);
uniform vec3 neb_b : source_color = vec3(0.05, 0.12, 0.22);
uniform vec3 band_col : source_color = vec3(0.20, 0.17, 0.24);
uniform float px_angle = 0.000485;     // радиан на пиксель: обзор / высота окна
uniform float star_cells = 900.0;
uniform float star_share = 0.0022;     // доля ячеек со звездой
uniform float env_gain = 3.0;          // туманность в карте окружения ярче
uniform bool test_magenta = false;

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
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	// туманность: два облака и полоса, мягко и тускло — фон, а не картинка
	float n1 = fbm(d * 2.2 + vec3(3.0, 1.0, 7.0));
	float n2 = fbm(d * 3.7 + vec3(11.0, 5.0, 2.0));
	float band = exp(-pow(dot(d, normalize(vec3(0.3, 0.55, -0.78))) * 2.6, 2.0));
	vec3 neb = neb_a * smoothstep(0.45, 0.85, n1) * 0.8 + neb_b * smoothstep(0.5, 0.9, n2) * 0.7 + band_col * band * (0.35 + 0.65 * n2);
	vec3 col = deep;
	if (AT_CUBEMAP_PASS) {
		col += neb * env_gain + vec3(0.04, 0.045, 0.07);
	} else {
		col += neb;
		// звёзды: одна на ячейку, центр со сдвигом внутри ячейки, размер — в пикселях
		vec3 cell = floor(d * star_cells);
		float h = hash13(cell);
		if (h < star_share) {
			vec3 jit = vec3(hash13(cell + 3.1), hash13(cell + 5.7), hash13(cell + 8.3)) - 0.5;
			vec3 c = normalize((cell + 0.5 + jit * 0.5) / star_cells);
			float r = length(d - c) / px_angle;               // в пикселях
			float mag = pow(hash13(cell + 1.3), 5.0);          // яркие — редкие
			float core = exp(-r * r * 1.6);
			vec3 tint = mix(vec3(1.0, 0.86, 0.72), vec3(0.78, 0.86, 1.0), hash13(cell + 7.0));
			col += tint * core * (0.35 + 3.2 * mag);
		}
	}
	if (test_magenta) {
		col = vec3(1.0, 0.0, 1.0);
	}
	COLOR = col;
}
