# Авиация и хвосты G2 под xvfb (ярус картинки; план G3, п. 5 и «Игровые проверки») — в
# ОБОИХ отрисовщиках. Каждая проверка — замером снимка и с откатом:
# - машины на рабочем виде (2400) — точками цвета стороны, со следом (04, 2.21): точка
#   есть у каждой машины, след виден вдоль пути; откаты — «точек нет» (модель на 2400 —
#   пара тусклых точек) и «следа нет»;
# - ракеты и трассы ПВО на рабочем виде видны (хвост G2): пятно ракеты и полоска ПВО
#   не меньше заданного числа точек; откат — один общий предел толщины, как в G2;
# - главный калибр и лёгкое на СТАРТОВОМ виде (3990) различимы по толщине (хвост G2):
#   у обоих мировая толщина меньше точки, и общий предел «не меньше 1,6» делал их
#   одинаковыми; откат — один общий предел;
# - снаряд, кончившийся раньше первого кадра, вспыхивает там, где кончился, а не в
#   центре поля (хвост G2); откат — конец в (0, 0, 0), как было.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Craft := preload("res://sim/craft.gd")
const Squad := preload("res://sim/squad.gd")
const Weapons := preload("res://sim/weapons.gd")
const BattleView := preload("res://view/battle_view.gd")
const BattleFx := preload("res://view/battle_fx.gd")
const AirView := preload("res://view/air_view.gd")
const MainScene := preload("res://main.tscn")

const BIG := 1.0e9
const WORK := 2400.0
const START := 3990.0

var _defs: Defs


func _get_defs() -> Defs:
	if _defs == null:
		_defs = Defs.load_default({}) as Defs
	return _defs


static func renderer() -> String:
	return RenderingServer.get_current_rendering_method()


static func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _shots_dir() -> String:
	var d := OS.get_environment("CAPELLA_SHOTS")
	if d == "":
		d = tmp("shots")
	DirAccess.make_dir_recursive_absolute(d)
	return d


## Бой-проба на чёрном поле: своё расставляет setup.call(battle). Часы вида стоят,
## рисует проверка сама (как в test_render_skirmish: покачивание от настоящих часов
## двигало бы картинку от прогона к прогону).
func _lab_view(setup: Callable) -> BattleView:
	await hooks.set_window_size(Vector2i(1600, 900))
	var b := Battle.create(_get_defs(), {"attacker": &"troyden", "defender": &"plektor", "size": &"small", "seed": 3, "reserve": false}) as Battle
	b.ships.clear()
	setup.call(b)
	var v := BattleView.new()
	v.name = "LabView"
	tree.root.add_child(v)
	v.setup(_get_defs(), b, false)
	v.paused = true
	v.set_process(false)
	v.clock = 0.0
	v.rig.edge_enabled = false
	v.rig.input_enabled = false
	await hooks.frames(2)
	return v


func _drop(v: BattleView) -> void:
	var b := v.battle
	v.queue_free()
	await hooks.frames(2)
	b.dispose()


func _put(b: Battle, side: int, id: StringName, pos: Vector2, look: Vector2) -> Ship:
	var s := b.spawn(side, b.defs.ship(b.sides[side].clan, id), pos)
	s.set_yaw(Ship.yaw_of(look - pos))
	s.switch_off(&"engines", BIG)
	s.stance = &"hold"
	s.hp = BIG
	s.max_hp = BIG
	return s


func _quiet(s: Ship) -> Ship:
	s.main_cd = PackedFloat64Array()
	s.sec_cd = PackedFloat64Array()
	s.light_cd = PackedFloat64Array()
	s.mis_cd = PackedFloat64Array()
	s.pd_cd = PackedFloat64Array()
	return s


## Шаг модели и кадр вида — как в игре, но часами проверки: frac — доля шага, на которой
## рисуем (на паузе вид рисует начало шага, где только что рождённый отрезок ещё не виден).
func _step_draw(v: BattleView, frac: float = 0.5) -> void:
	v.paused = false
	v.advance(Battle.STEP)
	v.acc = frac * Battle.STEP
	v.paused = true
	v.draw_state()


func _snap(name: String) -> Image:
	await hooks.frames(3)
	var img := tree.root.get_texture().get_image()
	img.save_png(_shots_dir().path_join("%s_%s.png" % [name, renderer()]))
	return img


static func _max_lum(img: Image, p: Vector2, r: int) -> float:
	var best := 0.0
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var x := roundi(p.x) + dx
			var y := roundi(p.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				best = maxf(best, lum(img.get_pixel(x, y)))
	return best


## Доля точек СЕРЕДИНЫ отрезка (30…70 %), у которых рядом (3 × 3) свет ярче порога.
static func _lit_share(img: Image, a: Vector2, b: Vector2, thr: float, n: int = 40) -> float:
	var lit := 0
	for k in n:
		var p := a.lerp(b, 0.3 + 0.4 * float(k) / float(n - 1))
		if _max_lum(img, p, 1) > thr:
			lit += 1
	return float(lit) / float(n)


## Толщина светлой полосы поперёк отрезка a→b в его середине: сколько точек поперечной
## линии ярче порога (медиана по пяти поперечникам — концы и шум не в счёт).
static func _band_width(img: Image, a: Vector2, b: Vector2, thr: float) -> float:
	var along := (b - a).normalized()
	var across := Vector2(-along.y, along.x)
	var widths: Array[float] = []
	for k in 5:
		var c := a.lerp(b, 0.4 + 0.05 * float(k))
		var n := 0
		for i in range(-12, 13):
			var p := c + across * float(i)
			var x := roundi(p.x)
			var y := roundi(p.y)
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and lum(img.get_pixel(x, y)) > thr:
				n += 1
		widths.append(float(n))
	widths.sort()
	return widths[2]


# ───────────────────────── машины: точки и след на 2400 ─────────────────────────

## Точка машины — середина её пятна белая: не меньше двух точек ярче 0,95 в 5 × 5 вокруг
## машины. Модель на 2400 — пара тусклых точек, а след и очереди рядом ярки, но не белы:
## в воздушном бою «ярче 0,7» нашлось у 35 машин из 37 и БЕЗ точек, «ярче 0,95» — у 0.
const DOT_AREA := 2


static func _has_dot(img: Image, p: Vector2) -> bool:
	return _bright_area(img, p, 2, 0.95) >= DOT_AREA


static func _bright_area(img: Image, p: Vector2, r: int, thr: float) -> int:
	var n := 0
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var x := roundi(p.x) + dx
			var y := roundi(p.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and lum(img.get_pixel(x, y)) > thr:
				n += 1
	return n


func _crafts(mode: StringName) -> Dictionary:
	AirView.rollback_no_dots = mode == &"no_dots"
	AirView.rollback_no_trails = mode == &"no_trails"
	var v := await _lab_view(func(b: Battle) -> void:
		var c := _put(b, Ship.ATTACKER, &"carrier", Vector2(0, 300), Vector2(0, -300))
		_quiet(c)
		_quiet(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -2600), Vector2(0, 0))))
	var b := v.battle
	b.queue({"op": &"launch", "ids": [b.ships[0].uid], "role": &"fighter"})
	var hist: Dictionary[int, Array] = {}
	var steps := roundi(4.0 / Battle.STEP)
	var cam := v.rig.camera
	for i in steps:
		_step_draw(v)
		var game_t := b.time - Battle.STEP * 0.5
		for c in b.crafts:
			if not c.dead:
				var h: Array = hist.get(c.uid, [])
				h.append([game_t, v.craft_point(c)])
				hist[c.uid] = h
	var q: Squad = b.squads[0] if not b.squads.is_empty() else null
	var out := {"n": 0}
	if q == null:
		await _drop(v)
		AirView.rollback_no_dots = false
		AirView.rollback_no_trails = false
		return out
	v.rig.set_view(Vector3(q.pos.x, 0.0, q.pos.y), 0.0, WORK, true)
	v.draw_state()
	var img := await _snap("air_dots_%s" % mode)
	var now := b.time - Battle.STEP * 0.5
	var dots := 0
	var areas: Array[int] = []
	var trail_sum := 0.0
	var n := 0
	for c in q.craft:
		if c.dead:
			continue
		n += 1
		var sp := cam.unproject_position(v.craft_point(c))
		areas.append(_bright_area(img, sp, 2, 0.95))
		if _has_dot(img, sp):
			dots += 1
		# хорда пути от 0,48 до 0,24 с назад: след там уже лёг и ещё не погас
		var h: Array = hist.get(c.uid, [])
		var pa := Vector3.INF
		var pb := Vector3.INF
		for e: Array in h:
			var et: float = e[0]
			var ep: Vector3 = e[1]
			if pa == Vector3.INF and et >= now - 0.48:
				pa = ep
			if pb == Vector3.INF and et >= now - 0.24:
				pb = ep
		if pa != Vector3.INF and pb != Vector3.INF:
			trail_sum += _lit_share(img, cam.unproject_position(pa), cam.unproject_position(pb), 0.05)
	out = {"n": n, "dots": dots, "trail": trail_sum / maxf(float(n), 1.0), "written": v.air.trails_written}
	note("%s · машины %s: %d из %d с точкой (ярких точек у машин: %s), след виден на %.0f%% хорды, отрезков следа %d" % [renderer(), mode, dots, n, str(areas), num(out["trail"]) * 100.0, whole(out["written"])])
	await _drop(v)
	AirView.rollback_no_dots = false
	AirView.rollback_no_trails = false
	return out


func test_crafts_dots_and_trails_at_2400() -> void:
	var r := await _crafts(&"ok")
	ok(whole(r["n"]) >= 4, "%s: звено в воздухе (%d машин)" % [renderer(), whole(r["n"])])
	eq(whole(r.get("dots", -1)), whole(r["n"]), "%s: на 2400 у каждой машины яркая точка" % renderer())
	ok(num(r.get("trail", 0.0)) >= 0.8, "%s: след виден вдоль пути: %.0f%%" % [renderer(), num(r.get("trail", 0.0)) * 100.0])
	var nd := await _crafts(&"no_dots")
	ok(whole(nd.get("dots", 0)) * 2 < whole(nd["n"]), "%s: откат «точек нет»: ярких точек %d из %d — проверка краснеет" % [renderer(), whole(nd.get("dots", 0)), whole(nd["n"])])
	var nt := await _crafts(&"no_trails")
	ok(num(nt.get("trail", 1.0)) < 0.3, "%s: откат «следа нет»: %.0f%% — проверка краснеет" % [renderer(), num(nt.get("trail", 1.0)) * 100.0])


# ───────────────────────── ракеты и ПВО на 2400 ─────────────────────────

## Оранжевых светлых точек вокруг p (ракета и её след; голубая трасса ПВО — не в счёт).
static func _orange_area(img: Image, p: Vector2, r: int) -> int:
	var n := 0
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var x := roundi(p.x) + dx
			var y := roundi(p.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				var c := img.get_pixel(x, y)
				if lum(c) > 0.3 and c.r > c.b + 0.1:
					n += 1
	return n


## mode: &"ok" — как в игре; &"one_px" — откат «один общий предел, как в G2»;
## &"pd_no_min" — откат «у трассы ПВО нет нижнего предела» (0,55 в мире — треть точки).
## Шаги идут, пока не наберётся по восемь замеров ракеты и ПВО.
func _missiles_pd(mode: StringName) -> Dictionary:
	BattleFx.rollback_one_px = mode != &"ok"
	var v := await _lab_view(func(b: Battle) -> void:
		var f := _put(b, Ship.ATTACKER, &"frigate", Vector2(0, 0), Vector2(0, -600))
		f.light_cd = PackedFloat64Array()
		var s := _put(b, Ship.DEFENDER, &"sinho", Vector2(0, -600), Vector2(0, 0))
		s.main_cd = PackedFloat64Array()
		s.sec_cd = PackedFloat64Array()
		s.light_cd = PackedFloat64Array()
		s.pd_cd = PackedFloat64Array())
	if mode == &"pd_no_min":
		v.bfx.gfx.tracer_mat.set_shader_parameter("min_px", 0.0)
	var b := v.battle
	var cam := v.rig.camera
	v.rig.set_view(Vector3(0, 0, -300), 0.0, WORK, true)
	var spr: MultiMeshInstance3D = v.bfx.get("_sprites")
	var tr := v.bfx.gfx.tracers.multimesh
	var miss_area: Array[float] = []
	var pd_lit: Array[float] = []
	var saved := false
	for i in roundi(8.0 / Battle.STEP):
		_step_draw(v)
		var mm := spr.multimesh
		var game_t := b.time - Battle.STEP * 0.5
		var segs: Array[Array] = []
		for k in tr.instance_count:
			var t := tr.get_instance_transform(k)
			var cd := tr.get_instance_custom_data(k)
			var col := Color(t.basis.z.x, t.basis.z.y, t.basis.z.z)
			if not col.is_equal_approx(BattleFx.PD_OWN):
				continue
			# голова и хвост — тем же счётом, что в tracer.gdshader
			var t01 := (game_t - cd.r) / maxf(cd.g, 0.001)
			var seg := t.basis.y.x
			var head := clampf(t01 * (1.0 + seg), 0.0, 1.0)
			var tail := clampf(t01 * (1.0 + seg) - seg, 0.0, 1.0)
			if t01 >= 0.0 and tail < 1.0 and head - tail > 0.5 * seg:
				var a2 := cam.unproject_position(t.origin + t.basis.x * tail)
				var b2 := cam.unproject_position(t.origin + t.basis.x * head)
				if a2.distance_to(b2) >= 12.0:
					segs.append([a2, b2])
		if mm.visible_instance_count == 0 and segs.is_empty():
			continue
		await hooks.frames(3)
		var img := tree.root.get_texture().get_image()
		for k in mm.visible_instance_count:
			miss_area.append(float(_orange_area(img, cam.unproject_position(mm.get_instance_transform(k).origin), 6)))
		for sg: Array in segs:
			var a2: Vector2 = sg[0]
			var b2: Vector2 = sg[1]
			pd_lit.append(_lit_share(img, a2, b2, 0.12))
		if not saved and not segs.is_empty() and mm.visible_instance_count > 0:
			img.save_png(_shots_dir().path_join("missiles_pd_%s_%s.png" % [mode, renderer()]))
			saved = true
		if miss_area.size() >= 8 and pd_lit.size() >= 8:
			break
	var f: Dictionary = v.bfx.fired
	miss_area.sort()
	pd_lit.sort()
	var out := {"m": miss_area[miss_area.size() / 2] if not miss_area.is_empty() else 0.0, "pd": pd_lit[pd_lit.size() / 2] if not pd_lit.is_empty() else 0.0,
		"nm": miss_area.size(), "npd": pd_lit.size(), "fired": f}
	note("%s · ракеты и ПВО %s: пятно ракеты %.0f точек (медиана из %d), трасса ПВО видна на %.0f%% середины (медиана из %d)" % [renderer(), mode, num(out["m"]), miss_area.size(), num(out["pd"]) * 100.0, pd_lit.size()])
	await _drop(v)
	BattleFx.rollback_one_px = false
	return out


## Пятно ракеты — оранжевые точки ярче 0,3 в 13 × 13 вокруг неё (с её следом): с G3 —
## не меньше MISS_AREA (замер: Forward+ 48, Compatibility 28; в откате 15 и 9). Трасса
## ПВО — доля середины, где она светится.
const MISS_AREA := 20.0


func test_missiles_and_pd_visible_at_2400() -> void:
	var r := await _missiles_pd(&"ok")
	ok(whole(r["nm"]) > 0 and whole(r["npd"]) > 0, "%s: ракеты летят, ПВО по ним бьёт (%s)" % [renderer(), str(r["fired"])])
	ok(num(r["m"]) >= MISS_AREA, "%s: ракета на 2400 — пятно со следом не меньше %.0f точек: %.0f" % [renderer(), MISS_AREA, num(r["m"])])
	ok(num(r["pd"]) >= 0.9, "%s: трасса ПВО на 2400 видна вдоль середины: %.0f%%" % [renderer(), num(r["pd"]) * 100.0])
	var o := await _missiles_pd(&"one_px")
	ok(num(o["m"]) < MISS_AREA, "%s: откат «один общий предел, как в G2»: пятно ракеты %.0f — пылинка, проверка краснеет" % [renderer(), num(o["m"])])
	var n := await _missiles_pd(&"pd_no_min")
	ok(num(n["pd"]) < 0.9, "%s: откат «у трассы ПВО нет нижнего предела»: %.0f%% — рвётся, проверка краснеет" % [renderer(), num(n["pd"]) * 100.0])


# ───────────────────────── главный калибр и лёгкое на старте (3990) ─────────────────────────

func _main_vs_light(one_px: bool) -> Dictionary:
	BattleFx.rollback_one_px = one_px
	var v := await _lab_view(func(b: Battle) -> void:
		var c := _put(b, Ship.ATTACKER, &"cruiser", Vector2(-300, 0), Vector2(-300, -700))
		_quiet(c)
		c.main_cd = PackedFloat64Array([0.0])
		var f := _put(b, Ship.ATTACKER, &"frigate", Vector2(300, 0), Vector2(300, -250))
		_quiet(f)
		f.light_cd = PackedFloat64Array([0.0])
		_quiet(_put(b, Ship.DEFENDER, &"cruiser", Vector2(-300, -700), Vector2(-300, 0)))
		_quiet(_put(b, Ship.DEFENDER, &"corvette", Vector2(300, -250), Vector2(300, 0))))
	var b := v.battle
	var cam := v.rig.camera
	v.rig.set_view(Vector3(0, 0, -350), 0.0, START, true)
	var got_main := false
	var got_light := false
	for i in 60:
		_step_draw(v, 0.3)
		for e in b.events:
			if e[0] == &"fire":
				got_main = got_main or e[3] == &"main"
				got_light = got_light or e[3] == &"light"
		if got_main and got_light:
			break
	var img := await _snap("main_light_3990_%s" % ("one_px" if one_px else "ok"))
	var cm := b.ships[0]
	var fr := b.ships[1]
	var mw := _band_width(img, cam.unproject_position(v.ship_point(cm)), cam.unproject_position(v.ship_point(b.ships[2])), 0.15)
	var lw := _band_width(img, cam.unproject_position(v.ship_point(fr)), cam.unproject_position(v.ship_point(b.ships[3])), 0.15)
	note("%s · на 3990%s: главный калибр %.0f точек, лёгкое %.0f" % [renderer(), " (откат)" if one_px else "", mw, lw])
	await _drop(v)
	BattleFx.rollback_one_px = false
	return {"main": mw, "light": lw, "both": got_main and got_light}


func test_main_and_light_beams_differ_at_3990() -> void:
	var r := await _main_vs_light(false)
	ok(flag(r["both"]), "%s: оба выстрела на одном кадре" % renderer())
	ok(num(r["light"]) >= 1.0 and num(r["main"]) >= 2.0 * num(r["light"]), "%s: главный калибр на старте вдвое толще лёгкого: %.0f против %.0f" % [renderer(), num(r["main"]), num(r["light"])])
	var o := await _main_vs_light(true)
	ok(num(o["main"]) < 2.0 * num(o["light"]), "%s: откат «один предел»: %.0f против %.0f — не отличить, проверка краснеет" % [renderer(), num(o["main"]), num(o["light"])])


# ───────────────────────── вспышка конца снаряда — не в центре поля ─────────────────────────

func _end_flash(center: bool) -> Dictionary:
	BattleFx.rollback_end_center = center
	var at := Vector2(700, -500)
	var v := await _lab_view(func(b: Battle) -> void:
		_quiet(_put(b, Ship.ATTACKER, &"frigate", Vector2(-400, 300), Vector2(0, 0)))
		_quiet(_put(b, Ship.DEFENDER, &"frigate", at, Vector2(0, 0))))
	var b := v.battle
	var cam := v.rig.camera
	v.rig.set_view(Vector3(150, 0, -100), 0.0, WORK, true)
	# ракета, которая кончается на ПЕРВОМ шаге — раньше первого кадра (как сбитая ПВО на
	# том же шаге при 4×): вид её ни разу не рисовал
	var p := Weapons.spawn_proj(b, b.ships[1], b.ships[0], 10.0, &"missile", 20.0, BIG, Vector2(0, 1))
	p.life = Battle.STEP * 0.5
	var fl := v.bfx.gfx.flashes.multimesh
	var w0 := v.bfx.gfx.flashes_written
	_step_draw(v, 0.1)
	var ended := false
	for e in b.events:
		ended = ended or (e[0] == &"proj_end" and whole(e[1]) == p.uid)
	var img := await _snap("end_flash_%s" % ("center" if center else "ok"))
	var origin3 := Vector3.INF
	if v.bfx.gfx.flashes_written > w0:
		var idx := (v.bfx.gfx.flashes_written - 1) % fl.instance_count
		origin3 = fl.get_instance_transform(idx).origin
	var c0 := cam.unproject_position(Vector3.ZERO)
	var c1 := cam.unproject_position(Vector3(at.x, 0.0, at.y))
	var out := {"ended": ended, "origin": origin3, "lum0": _max_lum(img, c0, 3), "lum1": _max_lum(img, c1, 6)}
	note("%s · конец снаряда%s: вспышка в %s, свет в центре поля %.2f, у места конца %.2f" % [renderer(), " (откат)" if center else "", str(origin3), num(out["lum0"]), num(out["lum1"])])
	await _drop(v)
	BattleFx.rollback_end_center = false
	return out


func test_projectile_end_flash_not_at_center() -> void:
	var r := await _end_flash(false)
	ok(flag(r["ended"]), "%s: снаряд кончился на первом шаге" % renderer())
	var o3: Vector3 = r["origin"]
	ok(o3 != Vector3.INF and Vector2(o3.x, o3.z).distance_to(Vector2(700, -500)) < 1.0, "%s: вспышка — там, где снаряд кончился: %s" % [renderer(), str(o3)])
	ok(num(r["lum0"]) < 0.1, "%s: в центре поля на снимке темно: %.2f" % [renderer(), num(r["lum0"])])
	var o := await _end_flash(true)
	var c3: Vector3 = o["origin"]
	ok(c3 != Vector3.INF and c3.length() < 1.0 and num(o["lum0"]) > 0.3, "%s: откат «конец в (0, 0, 0)»: вспышка в центре поля (%.2f) — проверка краснеет" % [renderer(), num(o["lum0"])])


# ───────────────────────── «Полигон»: воздушный бой на снимке ─────────────────────────

## Главная сцена: свои три звена подняты на первой секунде, бой идёт 30 с (вид шагает
## постоянным шагом и рисует КАЖДЫЙ шаг — так кладутся следы), потом рабочий вид 2400
## над серединой машин. На снимке: доля машин в кадре, у которых есть точка (откат «точек
## нет» — доля падает), и снимки на 1920 и 1366 — для текста выпуска.
func _air_battle(size: Vector2i, no_dots: bool) -> Dictionary:
	AirView.rollback_no_dots = no_dots
	var got := await hooks.set_window_size(size)
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	await hooks.frames(4)
	var poly: Node = main.get("polygon")
	var view: BattleView = poly.get("view")
	var b := view.battle
	view.paused = true
	var carrier: Ship = null
	for s in b.ships:
		if s.side == Ship.ATTACKER and s.hangar != null and not s.station:
			carrier = s
			break
	for role: StringName in [&"interceptor", &"fighter", &"bomber"]:
		b.queue({"op": &"launch", "ids": [carrier.uid], "role": role})
	while b.time < 30.0 and not b.over:
		view.paused = false
		view.advance(Battle.STEP)
		view.acc = 0.5 * Battle.STEP
		view.paused = true
		view.draw_state()
	var mid := Vector2.ZERO
	var n := 0
	for c in b.crafts:
		if not c.dead:
			mid += c.pos
			n += 1
	mid /= maxf(float(n), 1.0)
	view.rig.set_view(Vector3(mid.x, 0.0, mid.y), view.rig.yaw, WORK, true)
	view.draw_state()
	await hooks.frames(3)
	view.draw_state()
	await hooks.frames(2)
	var img := tree.root.get_texture().get_image()
	var tag := "%d×%d" % [got.x, got.y]
	img.save_png(_shots_dir().path_join("air_battle_%s_%s%s.png" % [renderer(), tag, "_no_dots" if no_dots else ""]))
	var cam := view.rig.camera
	var vr := Rect2(Vector2.ZERO, Vector2(got)).grow(-10.0)
	var seen := 0
	var dotted := 0
	var own_sq := 0
	var foe_sq := 0
	for q in b.squads:
		if not q.dead:
			if q.side == Ship.ATTACKER:
				own_sq += 1
			else:
				foe_sq += 1
	for c in b.crafts:
		if c.dead:
			continue
		var w := view.craft_point(c)
		if cam.is_position_behind(w):
			continue
		var sp := cam.unproject_position(w)
		if not vr.has_point(sp):
			continue
		seen += 1
		if _has_dot(img, sp):
			dotted += 1
	var out := {"seen": seen, "dotted": dotted, "own": own_sq, "foe": foe_sq, "up": b.sides[Ship.ATTACKER].sq_up, "lost": b.sides[Ship.ATTACKER].sq_lost, "t": b.time, "trails": view.air.trails_written}
	note("%s %s · воздушный бой на 30 с%s: машин в кадре %d, с точкой %d; своих звеньев поднято %d, потеряно %d, в воздухе %d; чужих в воздухе %d; отрезков следа %d" % [renderer(), tag, " (откат «точек нет»)" if no_dots else "", seen, dotted, whole(out["up"]), whole(out["lost"]), own_sq, foe_sq, whole(out["trails"])])
	main.queue_free()
	await hooks.frames(3)
	b.dispose()
	AirView.rollback_no_dots = false
	return out


func test_air_battle_snapshots() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		var r := await _air_battle(size, false)
		ok(whole(r["up"]) == 3 and whole(r["foe"]) >= 1, "%s: свои три звена поднялись (%d), чужие в воздухе (%d)" % [renderer(), whole(r["up"]), whole(r["foe"])])
		ok(whole(r["seen"]) >= 8, "%s: на рабочем виде над серединой машин — %d машин" % [renderer(), whole(r["seen"])])
		ok(float(whole(r["dotted"])) >= 0.8 * float(whole(r["seen"])), "%s: у машин в кадре точки: %d из %d (у остальных — корпус корабля ближе к камере)" % [renderer(), whole(r["dotted"]), whole(r["seen"])])
	var o := await _air_battle(Vector2i(1920, 1080), true)
	ok(float(whole(o["dotted"])) < 0.2 * float(whole(o["seen"])), "%s: откат «точек нет»: %d из %d — проверка краснеет" % [renderer(), whole(o["dotted"]), whole(o["seen"])])
