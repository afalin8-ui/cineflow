# Экран боя на снимке (план GИ; ярус hud — с окном под xvfb, отдельно от render, чтобы тот
# держался под пределом 900 с). Раскладка, попадание мышью и раскладка знаков проверены без окна
# (tests/test_ui_hud.gd); здесь — то, что видно только на картинке: ЦВЕТ и ФОРМА рамок знаков
# по точкам экрана, в быстром бою, в «ИИ против ИИ» и в зеркале. Плюс снимки на 1920 и 1366
# в $CAPELLA_SHOTS — их смотрят глазами.
extends "res://tests/case.gd"

const MainScene := preload("res://main.tscn")
const MainScript := preload("res://main.gd")
const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Polygon := preload("res://tools/polygon.gd")
const QuickMenu := preload("res://ui/quick_menu.gd")
const Markers := preload("res://view/markers.gd")
const Settings := preload("res://view/settings.gd")
const Weapons := preload("res://sim/weapons.gd")

var _main: Node
## Расстановка старта: −1 — как в игре; OLD_START — прежняя ±650 (пакет GТ). Цвет и форму знаков
## сверяем в кадре, где на экране ОБЕ стороны и тесно, — им до GТ был старт. С GТ старт другой:
## противник за верхним краем, на экране только свой строй (снимки нового старта и 30-й секунды —
## test_tempo_screens).
const OLD_START := 650.0


func _open(size: Vector2i, watch: bool = false, mirror: bool = false, start_z: float = OLD_START) -> Polygon:
	await hooks.set_window_size(size)
	Settings.path = tmp("hud_screens_settings.cfg")
	if FileAccess.file_exists(Settings.path):
		DirAccess.remove_absolute(Settings.path)
	MainScript.out_override = tmp("hud_screens")
	MainScript.seed_override = 4242
	_main = MainScene.instantiate()
	tree.root.add_child(_main)
	await hooks.frames(3)
	var defs: Defs = _main.get("defs")
	if start_z >= 0.0:
		defs.doctrine.deploy_heavy_z = start_z       # у каждой главной сцены свои числа
	var cfg := QuickMenu.default_cfg(defs, watch)
	if mirror:
		cfg["defender"] = cfg["attacker"]
	_main.call("open_battle", cfg)
	await hooks.frames(4)
	var p: Polygon = _main.get("polygon")
	p.view.paused = true
	p.view.rig.edge_enabled = false
	await hooks.frames(4)
	return p


func _close() -> void:
	MainScript.out_override = ""
	MainScript.seed_override = -1
	Settings.path = Settings.DEFAULT_PATH
	if _main != null:
		var p: Polygon = _main.get("polygon")
		var b: Battle = p.battle if p != null else null
		_main.queue_free()
		_main = null
		await hooks.frames(2)
		if b != null:
			b.dispose()


func _shot(name: String) -> Image:
	await hooks.frames(3)
	var img := tree.root.get_viewport().get_texture().get_image()
	var d := OS.get_environment("CAPELLA_SHOTS")
	if d == "":
		d = tmp("shots")
	DirAccess.make_dir_recursive_absolute(d)
	var path := d.path_join("%s_%s.png" % [name, RenderingServer.get_current_rendering_method()])
	img.save_png(path)
	note("снимок %s" % path.get_file())
	return img


## Цвет рамки знака на снимке: самая яркая точка верхней кромки (середина рамки ± треть ширины,
## три строки вокруг кромки) — рамка тонкая и сглаженная, а вокруг тёмное небо и тёмная заливка.
static func _edge_color(img: Image, fr: Rect2) -> Color:
	var best := Color(0, 0, 0)
	var y0 := roundi(fr.position.y)
	for y in range(y0 - 1, y0 + 2):
		for x in range(roundi(fr.position.x + fr.size.x * 0.33), roundi(fr.end.x - fr.size.x * 0.33) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b > best.r + best.g + best.b:
				best = c
	return best


## Угол рамки: у прямоугольника (своя сторона) там кромка, у шестиугольника (чужая) — срез,
## то есть пустота. Яркость самой яркой точки 2 × 2 у угла `at`.
static func _corner_at(img: Image, at: Vector2) -> float:
	var best := 0.0
	for y in range(roundi(at.y) - 1, roundi(at.y) + 1):
		for x in range(roundi(at.x) - 1, roundi(at.x) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			best = maxf(best, maxf(c.r, maxf(c.g, c.b)))
	return best


## Оба верхних угла, берётся ТЕМНЕЙШИЙ: у прямоугольника светлы оба, у шестиугольника пусты оба,
## а тонкая линия-выноска соседнего знака, бывает, проходит через один срез (на пределе 5000
## на 1366 так и было) — и одного угла хватило бы, чтобы принять шестиугольник за прямоугольник.
static func _corner(img: Image, fr: Rect2) -> float:
	return minf(_corner_at(img, fr.position + Vector2(1, 1)), _corner_at(img, Vector2(fr.end.x, fr.position.y + 1)))


## Тот же кадр без трёхмерного мира (`disable_3d`, фон чёрный): только знаки и экран боя. На нём
## проверяется ФОРМА — на обычном снимке срезанный угол шестиугольника ложится то на купол РЭБ,
## то на соседний корпус, то на планету, и «угол есть» выходит от них, а не от рамки.
func _flat_shot(name: String) -> Image:
	var old: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color(0.3, 0.3, 0.3))
	tree.root.disable_3d = true
	RenderingServer.set_default_clear_color(Color.BLACK)
	var img := await _shot(name + "_flat")
	tree.root.disable_3d = false
	RenderingServer.set_default_clear_color(old)
	await hooks.frames(2)
	return img


## Сверка знаков: своя сторона — мятная кромка (g заметно больше r), чужая — красная (r больше g)
## — по обычному снимку; угол рамки (есть у прямоугольника, срезан у шестиугольника) — по снимку
## без трёхмерного мира. → сколько знаков и сколько не сошлось по цвету и форме.
func _check_marks(p: Polygon, img: Image, flat: Image) -> Dictionary:
	var n := 0
	var bad_col := 0
	var bad_shape := 0
	var ex := PackedStringArray()
	for m in p.view.markers.drawn:
		if m.squad:
			continue
		n += 1
		var own := m.side == p.view.my_side
		var c := _edge_color(img, m.frame)
		var col_ok := (c.g > c.r + 0.15) if own else (c.r > c.g + 0.15)
		var cor := _corner(flat, m.frame)
		var shape_ok := (cor > 0.35) if own else (cor < 0.3)
		if not col_ok:
			bad_col += 1
			if ex.size() < 3:
				ex.append("%s %s: %s" % ["свой" if own else "чужой", m.label, c])
		if not shape_ok:
			bad_shape += 1
			if ex.size() < 3:
				ex.append("%s %s: угол %.2f в %s" % ["свой" if own else "чужой", m.label, cor, m.frame.position])
	return {"n": n, "col": bad_col, "shape": bad_shape, "ex": "; ".join(ex)}


func _say(r: Dictionary) -> String:
	return "знаков %d, не тот цвет %d, не та форма %d%s" % [whole(r["n"]), whole(r["col"]), whole(r["shape"]), (" (" + str(r["ex"]) + ")") if str(r["ex"]) != "" else ""]


func test_quick_battle_screens() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		var p := await _open(size)
		var img := await _shot("hud_quick_start_%d" % size.x)
		var r := _check_marks(p, img, await _flat_shot("hud_quick_start_%d" % size.x))
		note("%d×%d, старт: %s" % [size.x, size.y, _say(r)])
		ok(whole(r["n"]) > 10 and whole(r["col"]) == 0 and whole(r["shape"]) == 0, "%d×%d, быстрый бой: свои — мятный прямоугольник, чужие — красный шестиугольник" % [size.x, size.y])
		await hooks.key(KEY_F2)
		await _shot("hud_quick_all_%d" % size.x)
		p.view.rig.set_view(p.view.rig.look, p.view.rig.yaw, 5000.0, true)
		await hooks.frames(4)
		var far := await _shot("hud_quick_far_%d" % size.x)
		var rf := _check_marks(p, far, await _flat_shot("hud_quick_far_%d" % size.x))
		note("%d×%d, весь флот на пределе 5000: %s" % [size.x, size.y, _say(rf)])
		ok(whole(rf["n"]) > 10 and whole(rf["col"]) == 0 and whole(rf["shape"]) == 0, "%d×%d, предел 5000: знаки те же по цвету и форме" % [size.x, size.y])
		await _close()


func test_watch_screens() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		var p := await _open(size, true)
		var img := await _shot("hud_watch_%d" % size.x)
		var r := _check_marks(p, img, await _flat_shot("hud_watch_%d" % size.x))
		note("%d×%d, «ИИ против ИИ»: %s" % [size.x, size.y, _say(r)])
		ok(whole(r["n"]) > 10 and whole(r["col"]) == 0 and whole(r["shape"]) == 0, "%d×%d, «ИИ против ИИ»: атакующий — мятный прямоугольник, защитник — красный шестиугольник" % [size.x, size.y])
		await _close()


## Зеркало Тройден × Тройден: стороны различаются по стороне, а не по клану. Откаты: «цвет по
## клану» — обе стороны мятные; «одна форма» — у чужих появляется угол.
func _mirror(clan_rb: bool, shape_rb: bool) -> Dictionary:
	Markers.rollback_clan_color = clan_rb
	Markers.rollback_one_shape = shape_rb
	var p := await _open(Vector2i(1366, 768), false, true)
	var nm := "hud_mirror_1366" + ("_clan" if clan_rb else "") + ("_shape" if shape_rb else "")
	var img := await _shot(nm)
	var r := _check_marks(p, img, await _flat_shot(nm))
	Markers.rollback_clan_color = false
	Markers.rollback_one_shape = false
	await _close()
	return r


func test_mirror_by_side() -> void:
	var r := await _mirror(false, false)
	note("зеркало Тройден × Тройден: %s" % _say(r))
	ok(whole(r["n"]) > 10 and whole(r["col"]) == 0 and whole(r["shape"]) == 0, "зеркало: свои и чужие различаются цветом и формой рамки")
	var o := await _mirror(true, false)
	ok(whole(o["col"]) > 0, "откат «цвет по клану» краснеет на снимке: %s" % _say(o))
	var o2 := await _mirror(false, true)
	ok(whole(o2["shape"]) > 0 and whole(o2["col"]) == 0, "откат «одна форма» краснеет на снимке формой, цвет при этом верный: %s" % _say(o2))


## Доля залитой полоски прочности знака на снимке: средняя строка полоски, точки ярче 0,3 — залиты
## (фон полоски тёмный, заливка — цвет стороны).
static func _bar_fill(img: Image, bar: Rect2) -> float:
	var y := roundi(bar.position.y + bar.size.y * 0.5 - 0.5)
	var x0 := roundi(bar.position.x)
	var x1 := roundi(bar.end.x) - 1
	var lit := 0
	for x in range(x0, x1 + 1):
		var c := img.get_pixel(clampi(x, 0, img.get_width() - 1), clampi(y, 0, img.get_height() - 1))
		if maxf(c.r, c.g) > 0.3:
			lit += 1
	return float(lit) / float(x1 - x0 + 1)


## Толщина светлой полосы левой кромки рамки (прямоугольник своей стороны) по середине высоты:
## у выбранного кромка толще и вокруг неё ореол.
static func _edge_band(img: Image, fr: Rect2) -> int:
	var y := roundi(fr.position.y + fr.size.y * 0.5)
	var n := 0
	for x in range(roundi(fr.position.x) - 8, roundi(fr.position.x) + 4):
		var c := img.get_pixel(clampi(x, 0, img.get_width() - 1), y)
		if maxf(c.r, maxf(c.g, c.b)) > 0.15:
			n += 1
	return n


## Полоска прочности под знаком — на долю hp_frac, а у выбранного рамка толще и с ореолом (план
## GИ, п. 6; замечание к GИ: ни то, ни другое не охраняла ни одна проверка — порча «полоска всегда
## полная» оставляла ярусы ui и hud зелёными). Кадр без трёхмерного мира: свой фрегат ранен, другой
## свой корабль сначала не выбран, потом выбран. Откаты: Markers.rollback_hp_full,
## Markers.rollback_sel_plain.
func _bar_and_sel(hp_rb: bool, sel_rb: bool) -> Dictionary:
	Markers.rollback_hp_full = hp_rb
	Markers.rollback_sel_plain = sel_rb
	var p := await _open(Vector2i(1366, 768))
	await hooks.move(Vector2(4.0, 400.0))
	var own: Array[int] = []
	for m in p.view.markers.drawn:
		if not m.squad and m.side == p.view.my_side and not m.moved:
			own.append(m.uid)
	var out := {"n": own.size()}
	if own.size() >= 2:
		var hurt := p.battle.ship_by_uid(own[0])
		Weapons.damage(p.battle, hurt, hurt.hp * 0.55, &"main", null, Vector2.ZERO)
		await hooks.frames(2)
		var img := await _flat_shot("hud_bar_sel_1366" + ("_hp" if hp_rb else "") + ("_sel" if sel_rb else ""))
		var mh := p.view.markers.mark_of(hurt.uid)
		out["hp"] = hurt.hp_frac()
		out["fill"] = _bar_fill(img, mh.bar) if mh != null else -1.0
		var mb := p.view.markers.mark_of(own[1])
		out["plain"] = _edge_band(img, mb.frame) if mb != null else -1
		p.view.selection = [own[1]]
		await hooks.frames(2)
		var img2 := await _flat_shot("hud_bar_sel_1366_picked" + ("_hp" if hp_rb else "") + ("_sel" if sel_rb else ""))
		var mb2 := p.view.markers.mark_of(own[1])
		out["picked"] = _edge_band(img2, mb2.frame) if mb2 != null else -1
	Markers.rollback_hp_full = false
	Markers.rollback_sel_plain = false
	await _close()
	return out


func test_marker_bar_and_selected_on_screen() -> void:
	var r := await _bar_and_sel(false, false)
	note("полоска раненого: прочность %.2f, залито %.2f; кромка невыбранного %d точек, выбранного %d" % [num(r.get("hp", -1.0)), num(r.get("fill", -1.0)), whole(r.get("plain", -1)), whole(r.get("picked", -1))])
	ok(whole(r["n"]) >= 2 and num(r["hp"]) < 0.8 and absf(num(r["fill"]) - num(r["hp"])) < 0.12, "полоска под знаком раненого залита на долю прочности (%.2f из %.2f)" % [num(r["fill"]), num(r["hp"])])
	ok(whole(r["picked"]) >= whole(r["plain"]) + 2, "у выбранного кромка рамки толще и с ореолом: %d точек против %d" % [whole(r["picked"]), whole(r["plain"])])
	var o := await _bar_and_sel(true, false)
	ok(num(o["fill"]) > 0.95, "откат «полоска всегда полная» краснеет на снимке: залито %.2f при прочности %.2f" % [num(o["fill"]), num(o["hp"])])
	var o2 := await _bar_and_sel(false, true)
	ok(whole(o2["picked"]) < whole(o2["plain"]) + 2, "откат «выбранный как невыбранный» краснеет: %d точек против %d" % [whole(o2["picked"]), whole(o2["plain"])])


## Быстрый бой как его видит игрок (пакет GТ): старт и 30-я секунда на 1920 и 1366 — снимки
## `hud_tempo_*` в $CAPELLA_SHOTS, их смотрят глазами. На старте на экране только СВОЙ строй, и он
## весь — мятные прямоугольники; противник за верхним краем. К 30-й секунде на экране и чужие —
## красные шестиугольники: сближение видно, бой ещё не начался.
func test_tempo_screens() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		var p := await _open(size, false, false, -1.0)
		var img := await _shot("hud_tempo_start_%d" % size.x)
		var r := _check_marks(p, img, await _flat_shot("hud_tempo_start_%d" % size.x))
		var own := 0
		var foe := 0
		for m in p.view.markers.drawn:
			if not m.squad:
				if m.side == p.view.my_side:
					own += 1
				else:
					foe += 1
		note("%d×%d, старт: %s; своих %d, чужих %d" % [size.x, size.y, _say(r), own, foe])
		ok(own >= 8 and whole(r["col"]) == 0 and whole(r["shape"]) == 0, "%d×%d, старт: свой строй на экране знаками своей стороны (%d), чужих %d" % [size.x, size.y, own, foe])
		p.view.paused = false
		for i in roundi(30.0 / Battle.STEP):
			p.view.advance(Battle.STEP)
		p.view.paused = true
		var img30 := await _shot("hud_tempo_30s_%d" % size.x)
		var r30 := _check_marks(p, img30, await _flat_shot("hud_tempo_30s_%d" % size.x))
		var foe30 := 0
		for m in p.view.markers.drawn:
			if not m.squad and m.side != p.view.my_side:
				foe30 += 1
		note("%d×%d, 30-я секунда: %s; чужих знаков %d, выстрел главного калибра был: %s" % [size.x, size.y, _say(r30), foe30, str(p.battle.metrics.first_gun > 0.0)])
		ok(foe30 > 0 and whole(r30["col"]) == 0 and whole(r30["shape"]) == 0, "%d×%d, 30-я секунда: противник подошёл и виден (%d знаков), цвет и форма по стороне" % [size.x, size.y, foe30])
		await _close()
