// Планета под столом (09, 11.7; часть 08, ловушка 21): суша, океан и облака
// шумом по направлению от центра; освещается обычным светом сцены (день и ночь —
// от солнца), край — дымкой атмосферы. Своих картинок нет: ничего не грузится.
shader_type spatial;
render_mode cull_back;

uniform vec3 ocean : source_color = vec3(0.05, 0.13, 0.26);
uniform vec3 shore : source_color = vec3(0.10, 0.24, 0.34);
uniform vec3 land_a : source_color = vec3(0.24, 0.30, 0.16);
uniform vec3 land_b : source_color = vec3(0.42, 0.36, 0.24);
uniform vec3 ice : source_color = vec3(0.86, 0.90, 0.94);
uniform vec3 haze : source_color = vec3(0.35, 0.58, 1.0);
uniform float haze_k = 0.9;

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
	ALBEDO = col;
	ROUGHNESS = mix(0.35, 0.9, max(land, cloud));
	METALLIC = 0.0;
	// дымка у края диска — со стороны камеры, светится сама (не зависит от солнца)
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = haze * pow(rim, 3.0) * haze_k;
}
