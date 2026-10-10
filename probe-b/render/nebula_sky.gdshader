shader_type sky;
uniform bool check_magenta = false;
float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float s = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { s += a * n3(p); p *= 2.03; a *= 0.5; } return s; }
void sky() {
	vec3 d = EYEDIR;
	float m1 = fbm(d * 2.5);
	float m2 = fbm(d * 4.0 + 7.0);
	vec3 col = vec3(4.0, 6.0, 12.0) / 255.0;
	col += vec3(58.0, 96.0, 190.0) / 255.0 * pow(m1, 3.0) * 0.55;
	col += vec3(196.0, 92.0, 150.0) / 255.0 * pow(m2, 4.0) * 0.35;
	float s = h3(floor(d * 420.0));
	col += vec3(step(0.9975, s)) * 0.8;
	COLOR = check_magenta ? vec3(1.0, 0.0, 1.0) : col;
}
