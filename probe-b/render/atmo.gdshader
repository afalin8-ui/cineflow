shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_front;
void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	vec3 c = vec3(0.35, 0.6, 1.0) * pow(rim, 3.0) * 1.4;
	ALBEDO = c;
	ALPHA = 1.0;
}
