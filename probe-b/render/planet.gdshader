shader_type spatial;
float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
varying vec3 objp;
void vertex() { objp = VERTEX; }
void fragment() {
	vec3 p = normalize(objp) * 4.0;
	float n = n3(p) * 0.6 + n3(p * 2.1) * 0.3 + n3(p * 4.3) * 0.1;
	vec3 sea = vec3(0.05, 0.12, 0.25);
	vec3 land = vec3(0.22, 0.28, 0.16);
	ALBEDO = mix(sea, land, smoothstep(0.48, 0.55, n));
	ROUGHNESS = 0.8;
}
