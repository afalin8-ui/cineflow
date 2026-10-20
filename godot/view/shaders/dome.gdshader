// Стенка купола РЭБ в полном виде (08, 2.10; пакет GЭ): обод с сеткой и бегущей рябью,
// светится по краю (обод виден ребром ярче, чем в лоб). Сложение, двусторонний. Время —
// ИГРОВОЕ (`now`): на паузе рябь стоит, как и весь бой. В покое стенки нет — только кольцо
// ровно по границе поля (view/battle_fx.gd, 04-17, 08-14).
// Сетка — открытый цилиндр радиуса 1 и высоты 90 (нарисованная толщина купола, 04, 2.18).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.56, 1.0, 0.78);
uniform float power = 0.5;
uniform float now = 0.0;

varying vec2 v_uv;

void vertex() {
	v_uv = vec2(atan(VERTEX.z, VERTEX.x) / 6.2831853 + 0.5, VERTEX.y / 90.0 + 0.5);
}

void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 4.0);
	float grid = max(smoothstep(0.985, 1.0, abs(sin(v_uv.x * 62.831))), smoothstep(0.99, 1.0, abs(sin(v_uv.y * 37.699))));
	float wave = smoothstep(0.14, 0.0, abs(fract(v_uv.y * 2.0 - now * 0.35) - 0.5));
	float a = (rim * 0.5 + grid * 0.35 + wave * 0.12 + 0.05) * power;
	ALBEDO = color * (0.7 + wave * 0.4) * a;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// В Compatibility бледное сложение пропадает целиком (замер снимком: стенка 0 против
	// 27–38 из 255 в Forward+) — тот же свет поднимаем к экранным цветам, как это делает
	// перевод из линейного пространства в Forward+ (godot/CLAUDE.md, 11).
	ALBEDO = pow(ALBEDO, vec3(0.4545));
#endif
}
