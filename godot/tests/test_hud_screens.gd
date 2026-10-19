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

var _main: Node


func _open(size: Vector2i, watch: bool = false, mirror: bool = false) -> Polygon:
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
