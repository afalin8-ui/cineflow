// Венец планеты: оболочка чуть больше планеты, видна изнутри (cull_front),
// светится сложением — у края диска голубое кольцо, к наружному краю гаснет.
// Сложение не бывает чёрным: проверка ореола (тест картинки) ищет как раз
// чёрное кольцо вокруг диска — им выглядел срез неба дальней плоскостью.
shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 glow : source_color = vec3(0.30, 0.55, 1.0);
uniform float power = 2.4;
uniform float strength = 1.6;

void fragment() {
	// у оболочки, видимой изнутри, нормаль смотрит от камеры
	float f = clamp(dot(-NORMAL, VIEW), 0.0, 1.0);
	// у края оболочки f → 0 (гаснет), к линии планеты растёт
	float a = pow(f, power);
	ALBEDO = glow * a * strength;
}
