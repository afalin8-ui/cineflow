// Небо-заглушка: звёзды шейдером (архитектура, 5.6). Рисуется без глубины,
// от дальней плоскости не зависит — ореола у планеты по устройству нет.
// ЛОВУШКА: в шейдере неба нельзя писать return — он не собирается.
shader_type sky;

uniform vec3 deep : source_color = vec3(0.010, 0.012, 0.024);
uniform vec3 haze : source_color = vec3(0.10, 0.07, 0.16);
uniform float star_cells = 420.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = deep;
	// мягкая полоса туманности
	float band = exp(-pow(dot(d, normalize(vec3(0.3, 0.55, -0.78))) * 3.2, 2.0));
	col += haze * band * 0.55;
	// звёзды: одна на ячейку, яркость — по хэшу; точка, а не пятно
	vec3 cell = floor(d * star_cells);
	float h = hash13(cell);
	if (h > 0.985) {
		vec3 c = normalize((cell + vec3(0.5)) / star_cells);
		float r = length(d - c) * star_cells;
		float b = smoothstep(0.55, 0.0, r) * (h - 0.985) / 0.015;
		col += mix(vec3(1.0, 0.86, 0.7), vec3(0.75, 0.85, 1.0), hash13(cell + 7.0)) * b * 2.2;
	}
	COLOR = col;
}
