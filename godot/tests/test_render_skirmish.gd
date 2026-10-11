# «Перестрелка» под xvfb (ярус картинки; план G2, «Игровые проверки») — в ОБОИХ
# отрисовщиках. Каждая проверка — с откатом:
# - лучи на рабочем виде (2400) не тоньше точки (09, 11.8): тонкий луч лёгкого орудия
#   (0,9 в мире — 0,6 точки на 2400) виден вдоль всей середины; откаты — без нижнего
#   предела толщины (min_px = 0) и шейдер «как было с G0b» (без abs у отрицательного
#   PROJECTION_MATRIX[1][1] предел не действовал вовсе — найдено этой проверкой):
#   луч рвётся посередине — фрагмент считается в середине точки, а она вне тонкой
#   полоски;
# - купол РЭБ в покое — ОДНО кольцо, ровно по границе поля (04, ловушка 17; 08,
#   ловушка 14); откат — кольцо на 0,6625 радиуса, как в JS;
# - пояс выделенного тяжёлого читается: внешний круг — дальность, внутренний —
#   пунктиром (09, 6.7); откат — поясов нет;
# - четыре источника урона рисуются разным: главный калибр — лучом, батарея —
#   очередью из трёх росчерков, лёгкое — тонким лучом, ПВО — летящим отрезком;
# - снимки «Перестрелки» на 1920 и 1366 — в $CAPELLA_SHOTS; заголовок справа сверху
#   не наезжает на подсказку клавиш (откат — прежний длинный заголовок, на 1366).
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Weapons := preload("res://sim/weapons.gd")
const BattleView := preload("res://view/battle_view.gd")
const BattleFx := preload("res://view/battle_fx.gd")
const MainScene := preload("res://main.tscn")
const Polygon := preload("res://tools/polygon.gd")
const PolygonHud := preload("res://ui/polygon_hud.gd")

const BIG := 1.0e9

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


## Бой-проба на чёрном поле (без неба): своё расставляет setup.call(battle).
func _lab_view(setup: Callable) -> BattleView:
	await hooks.set_window_size(Vector2i(1600, 900))
	var b := Battle.create(_get_defs(), {"attacker": &"troyden", "defender": &"plektor", "size": &"small", "seed": 3, "reserve": false}) as Battle
	b.ships.clear()
	setup.call(b)
	var v := BattleView.new()
	v.name = "LabView"
	tree.root.add_child(v)
	v.setup(_get_defs(), b, false)
	v.paused = true                          # шагает сама проверка, а не часы кадров
	# часы вида стоят: покачивание (view.bob) считается от НАСТОЯЩИХ часов, и концы
	# луча от прогона к прогону сдвигались на доли точки — откат «тонкий луч» гулял
	# 67…87% при пороге 80% (замечание к G2). Рисует проверка сама — draw_state()
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


## Шагать вид по шагу, пока не придёт событие kind/role; → было ли.
func _until_fire(v: BattleView, role: StringName, max_steps: int = 120) -> bool:
	v.paused = false
	for i in max_steps:
		v.advance(Battle.STEP)
		for e in v.battle.events:
			if e[0] == &"fire" and e[3] == role:
				v.paused = true
				return true
	v.paused = true
	return false


## Доля точек СЕРЕДИНЫ отрезка (30…70 %: без корпусов и вспышек на концах), у которых\n## рядом (3 × 3) есть свет ярче порога.
static func _lit_share(img: Image, a: Vector2, b: Vector2, thr: float, n: int = 60) -> float:
	var lit := 0
	for k in n:
		var p := a.lerp(b, 0.3 + 0.4 * float(k) / float(n - 1))
		var best := 0.0
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var x := clampi(roundi(p.x) + dx, 0, img.get_width() - 1)
				var y := clampi(roundi(p.y) + dy, 0, img.get_height() - 1)
				best = maxf(best, lum(img.get_pixel(x, y)))
		if best > thr:
			lit += 1
	return float(lit) / float(n)


# ───────────────────────── луч не тоньше точки на 2400 ─────────────────────────

## mode: &"ok" — как в игре; &"no_min" — откат «без нижнего предела толщины»
## (min_px = 0); &"no_abs" — откат «как было с G0b»: шейдер без abs у
## PROJECTION_MATRIX[1][1] (он отрицательный — предел не действует).
## Луч стоит на экране ВЕРТИКАЛЬНО (камера смотрит вдоль него), и кадр снимается при
## восьми сдвигах камеры вбок на восьмую точки: тонкий луч (0,6 точки) пропадает
## там, где середина точки выпала из полоски, — а на вертикали это видно сразу всей
## длиной хотя бы при одном из восьми сдвигов (полоска 0,6, промежуток 0,4 > 0,125).
## → доли «виден» по сдвигам. Раньше луч шёл наискось при одном положении, и доля
## у отката зависела от того, куда пришлась полоска: 67…87% (замечание к G2).
const BEAM_SHIFTS := 8


func _beam_shares(mode: StringName) -> PackedFloat64Array:
	var v := await _lab_view(func(b: Battle) -> void:
		var f := _put(b, Ship.ATTACKER, &"frigate", Vector2(0, 0), Vector2(0, -250))
		f.light_cd = PackedFloat64Array([0.0])
		f.pd_cd = PackedFloat64Array()
		_quiet(_put(b, Ship.DEFENDER, &"corvette", Vector2(0, -250), Vector2(0, 0))))
	var mid := Vector3(0, 0, -125)
	v.rig.set_view(mid, 0.0, 2400.0, true)
	var mat := v.bfx.gfx.beam_mat
	if mode == &"no_min":
		mat.set_shader_parameter("min_px", 0.0)
	elif mode == &"no_abs":
		var sh := Shader.new()
		sh.code = FileAccess.get_file_as_string("res://view/shaders/beam.gdshader").replace("abs(PROJECTION_MATRIX[1][1])", "PROJECTION_MATRIX[1][1]")
		ok(sh.code != mat.shader.code, "откат «без abs» правит шейдер")
		mat.shader = sh
	await hooks.frames(2)
	var fired := _until_fire(v, &"light")
	ok(fired, "лёгкое орудие выстрелило")
	var me := v.battle.ships[0]
	var tg := v.battle.ships[1]
	var cam := v.rig.camera
	# точек экрана на единицу мира поперёк луча — на его середине
	var px_per := cam.unproject_position(mid + Vector3(1, 0, 0)).distance_to(cam.unproject_position(mid))
	var out := PackedFloat64Array()
	for k in BEAM_SHIFTS:
		v.rig.set_view(mid + Vector3(float(k) / float(BEAM_SHIFTS) / px_per, 0, 0), 0.0, 2400.0, true)
		v.draw_state()
		await hooks.frames(3)
		var img := tree.root.get_texture().get_image()
		var a := cam.unproject_position(v.visual_of(me).part_point(&"muzzle_0"))
		var bb := cam.unproject_position(v.ship_point(tg))
		out.append(_lit_share(img, a, bb, 0.06))
		if k == 0:
			img.save_png(_shots_dir().path_join("beam_2400_%s_%s.png" % [mode, renderer()]))
	var txt := PackedStringArray()
	for x in out:
		txt.append("%.0f%%" % (x * 100.0))
	note("%s · луч %s: виден на %s середины (сдвиги по %.2f точки, луч вертикален: %.1f → %.1f)" % [renderer(), mode, ", ".join(txt), 1.0 / BEAM_SHIFTS, cam.unproject_position(v.ship_point(me)).x, cam.unproject_position(v.ship_point(tg)).x])
	await _drop(v)
	return out


static func _min_of(a: PackedFloat64Array) -> float:
	var m := INF
	for x in a:
		m = minf(m, x)
	return m


func test_beam_not_thinner_than_pixel_at_2400() -> void:
	var s := await _beam_shares(&"ok")
	ok(s.size() == BEAM_SHIFTS and _min_of(s) >= 0.95, "%s: луч лёгкого орудия на 2400 (0,9 в мире — меньше точки) виден вдоль всей середины при любом сдвиге: худший %.0f%%" % [renderer(), _min_of(s) * 100.0])
	for m: StringName in [&"no_min", &"no_abs"]:
		var o := await _beam_shares(m)
		ok(_min_of(o) < 0.5, "%s: откат «%s»: луч рвётся — при худшем сдвиге виден на %.0f%% середины, проверка краснеет" % [renderer(), m, _min_of(o) * 100.0])


# ───────────────────────── купол в покое — одно кольцо по полю ─────────────────────────

func _dome(js: bool) -> Dictionary:
	BattleFx.rollback_dome_js = js
	var v := await _lab_view(func(b: Battle) -> void:
		_quiet(_put(b, Ship.ATTACKER, &"ecm", Vector2(0, 0), Vector2(0, -100)))
		_quiet(_put(b, Ship.DEFENDER, &"corvette", Vector2(2200, -2200), Vector2(0, 0))))
	v.rig.set_view(Vector3(0, 0, 0), 0.0, 2000.0, true)
	v.paused = false
	for i in 90:
		v.advance(Battle.STEP)               # купол набрал мощность
	v.paused = true
	v.draw_state()
	await hooks.frames(3)
	var img := tree.root.get_texture().get_image()
	var s := v.battle.ships[0]
	var drawn: Array = v.bfx.drawn_domes.get(s.uid, [])
	var y := v.ship_point(s).y
	var cam := v.rig.camera
	var r := _get_defs().factions[&"troyden"].ecm.radius
	var at_r := 0
	var at_js := 0
	var n := 72
	for k in n:
		var ang := TAU * k / n
		for which in 2:
			var rr := r if which == 0 else r * BattleFx.JS_DOME_K
			var p := cam.unproject_position(Vector3(cos(ang) * rr, y, sin(ang) * rr))
			if p.x < 2 or p.y < 2 or p.x > img.get_width() - 3 or p.y > img.get_height() - 3:
				continue
			var best := 0.0
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					best = maxf(best, lum(img.get_pixel(roundi(p.x) + dx, roundi(p.y) + dy)))
			if best > 0.05:
				if which == 0:
					at_r += 1
				else:
					at_js += 1
	if not js:
		img.save_png(_shots_dir().path_join("dome_rest_%s.png" % renderer()))
	var wall_on := false
	for c in v.bfx.get_children():
		var mi := c as MeshInstance3D
		if mi != null and mi.name == "dome_wall" and mi.visible:
			wall_on = true
	note("%s · купол%s: на радиусе поля %d из %d точек, на 0,66 — %d" % [renderer(), " (откат JS)" if js else "", at_r, n, at_js])
	var out := {"drawn": drawn, "at_r": float(at_r) / n, "at_js": float(at_js) / n, "wall": wall_on, "r": r}
	BattleFx.rollback_dome_js = false
	await _drop(v)
	return out


func test_dome_rest_one_ring_at_field() -> void:
	var d := await _dome(false)
	var drawn: Array = d["drawn"]
	ok(drawn.size() == 3 and absf(num(drawn[0]) - num(d["r"])) < 1e-6 and not flag(drawn[1]), "%s: в покое кольцо радиусом ровно поле (%s при поле %.0f), не полный купол" % [renderer(), str(drawn), num(d["r"])])
	ok(not flag(d["wall"]), "%s: стенки купола в покое нет — одно кольцо" % renderer())
	ok(num(d["at_r"]) >= 0.85 and num(d["at_js"]) <= 0.15, "%s: кольцо видно на радиусе поля (%.0f%% точек), а на 0,66 радиуса — нет (%.0f%%)" % [renderer(), num(d["at_r"]) * 100.0, num(d["at_js"]) * 100.0])
	var o := await _dome(true)
	ok(num(o["at_r"]) <= 0.15, "%s: откат «кольцо на 0,66 радиуса, как в JS»: на границе поля его нет (%.0f%%) — проверка краснеет" % [renderer(), num(o["at_r"]) * 100.0])


# ───────────────────────── пояс выделенного тяжёлого ─────────────────────────

func _belt(none: bool) -> Dictionary:
	BattleFx.rollback_no_belts = none
	var v := await _lab_view(func(b: Battle) -> void:
		_quiet(_put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -100)))
		_quiet(_put(b, Ship.DEFENDER, &"corvette", Vector2(2300, -2300), Vector2(0, 0))))
	var s := v.battle.ships[0]
	v.selection = [s.uid]
	v.rig.set_view(Vector3(0, 0, 0), 0.0, 3000.0, true)
	v.draw_state()
	await hooks.frames(3)
	var img := tree.root.get_texture().get_image()
	var cam := v.rig.camera
	var y := v.ship_point(s).y
	var out_lit := 0
	var in_lit := 0
	var flips := 0
	var prev := false
	var n := 144
	for k in n:
		var ang := TAU * k / n
		var po := cam.unproject_position(Vector3(cos(ang) * 780.0, y, sin(ang) * 780.0))
		var pi := cam.unproject_position(Vector3(cos(ang) * 312.0, y, sin(ang) * 312.0))
		var lo := 0.0
		var li := lum(img.get_pixel(clampi(roundi(pi.x), 0, img.get_width() - 1), clampi(roundi(pi.y), 0, img.get_height() - 1)))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				lo = maxf(lo, lum(img.get_pixel(clampi(roundi(po.x) + dx, 0, img.get_width() - 1), clampi(roundi(po.y) + dy, 0, img.get_height() - 1))))
		if lo > 0.04:
			out_lit += 1
		var on := li > 0.03
		if on:
			in_lit += 1
		if k > 0 and on != prev:
			flips += 1
		prev = on
	note("%s · пояс%s: внешний %d/%d, внутренний светлых %d, переходов %d" % [renderer(), " (откат)" if none else "", out_lit, n, in_lit, flips])
	if not none:
		img.save_png(_shots_dir().path_join("belt_%s.png" % renderer()))
	BattleFx.rollback_no_belts = false
	await _drop(v)
	return {"out": float(out_lit) / n, "in": float(in_lit) / n, "flips": flips}


func test_belt_reads() -> void:
	var r := await _belt(false)
	ok(num(r["out"]) >= 0.85, "%s: внешний круг пояса (дальность 780) виден на %.0f%% точек" % [renderer(), num(r["out"]) * 100.0])
	ok(num(r["in"]) > 0.2 and num(r["in"]) < 0.85 and whole(r["flips"]) >= 16, "%s: внутренний (мёртвая зона 312) — пунктиром: светлых %.0f%%, переходов %d" % [renderer(), num(r["in"]) * 100.0, whole(r["flips"])])
	var o := await _belt(true)
	ok(num(o["out"]) < 0.15, "%s: откат «поясов нет»: круга нет (%.0f%%) — проверка краснеет" % [renderer(), num(o["out"]) * 100.0])


# ───────────────────────── четыре источника — разное на экране ─────────────────────────

func test_four_sources_drawn_differently() -> void:
	var v := await _lab_view(func(b: Battle) -> void:
		var c := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -600))
		c.main_cd = PackedFloat64Array([0.0])
		c.sec_cd = PackedFloat64Array([0.0, 0.0])
		var f := _put(b, Ship.ATTACKER, &"frigate", Vector2(400, 0), Vector2(400, -200))
		f.light_cd = PackedFloat64Array([0.0])
		_quiet(_put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -600), Vector2(0, 0)))
		_quiet(_put(b, Ship.DEFENDER, &"corvette", Vector2(-150, -230), Vector2(0, 0)))   # в мёртвой зоне — батарея
		_quiet(_put(b, Ship.DEFENDER, &"frigate", Vector2(400, -200), Vector2(400, 0))))
	var b := v.battle
	v.rig.set_view(Vector3(150, 0, -300), 0.0, 1300.0, true)
	var foe := b.ships[2]
	var p := Weapons.spawn_proj(b, foe, b.ships[1], 10.0, &"missile", 20.0, BIG, Vector2(0, 1))
	p.pos = Vector2(400, -60)                     # ракета у фрегата — ПВО
	var fx := v.bfx.gfx
	var beams0 := fx.beams_written
	var tracers0 := fx.tracers_written
	v.paused = false
	for i in 6:
		v.advance(Battle.STEP)
	v.paused = true
	var f: Dictionary = v.bfx.fired
	for k: StringName in [&"main", &"sec", &"light", &"pd"]:
		ok(whole(f.get(k, 0)) > 0, "%s: выстрел «%s» нарисован" % [renderer(), k])
	eq(fx.tracers_written - tracers0, 3 * whole(f.get(&"sec", 0)) + whole(f.get(&"pd", 0)), "%s: батарея — очередью из трёх росчерков, ПВО — одним летящим отрезком" % renderer())
	eq(fx.beams_written - beams0, 2 * whole(f.get(&"main", 0)) + whole(f.get(&"light", 0)), "%s: главный калибр — двойной луч, лёгкое — одиночный" % renderer())
	ok(BattleFx.SEC_OWN.h != BattleFx.MAIN_OWN.h and BattleFx.SEC_FOE.h != BattleFx.MAIN_FOE.h, "%s: у батареи своя пара оттенков" % renderer())
	v.draw_state()
	await hooks.frames(2)
	tree.root.get_texture().get_image().save_png(_shots_dir().path_join("sources_%s.png" % renderer()))
	await _drop(v)


# ───────────────────────── снимки «Перестрелки» ─────────────────────────

func test_skirmish_snapshots() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		var got := await hooks.set_window_size(size)
		var main := MainScene.instantiate()
		tree.root.add_child(main)
		await hooks.frames(6)
		var poly: Polygon = main.get("polygon")
		var view := poly.view
		view.speed = 4
		var b := view.battle
		var sel: Array[int] = []
		for s in b.ships:
			if s.side == Ship.ATTACKER and s.def.id == &"cruiser":
				sel.append(s.uid)
		view.selection = sel
		var t0 := Time.get_ticks_msec()
		while b.time < 32.0 and Time.get_ticks_msec() - t0 < 120000:
			await hooks.frames(1)
		view.paused = true
		await hooks.frames(3)
		var tag := "%d×%d" % [got.x, got.y]
		ok(b.time >= 32.0, "%s %s: «Перестрелка» дошла до 32 с" % [renderer(), tag])
		var f: Dictionary = view.bfx.fired
		ok(whole(f.get(&"main", 0)) > 0 and whole(f.get(&"sec", 0)) > 0 and whole(f.get(&"light", 0)) > 0, "%s %s: к 32 с бьют главный калибр, батареи и лёгкие: %s" % [renderer(), tag, str(f)])
		tree.root.get_texture().get_image().save_png(_shots_dir().path_join("skirmish_%s_%s.png" % [renderer(), tag]))
		# заголовок справа сверху не наезжает на подсказку клавиш слева; откат — прежний
		# длинный заголовок G2 («Полигон · «Перестрелка» («Сражение»): …») на 1366 наезжал
		var fps: Node = main.get("fps")
		var hint: Label = fps.get("hint")
		var hud: Node = poly.get("hud")
		var status: Label = hud.get("status")
		ok(not hint.get_global_rect().intersects(status.get_global_rect()), "%s %s: заголовок (%s) не наезжает на подсказку (%s)" % [renderer(), tag, str(status.get_global_rect()), str(hint.get_global_rect())])
		if got.x < 1500:
			var was: String = hud.get("title")
			hud.set("title", "Полигон · «Перестрелка» («Сражение»): Тройден × Плэктор")
			await hooks.frames(2)
			ok(hint.get_global_rect().intersects(status.get_global_rect()), "%s %s: откат «длинный заголовок» наезжает — проверка краснеет" % [renderer(), tag])
			hud.set("title", was)
		main.queue_free()
		await hooks.frames(3)
		b.dispose()


## Полоска фокуса ВСЕГО флота не наезжает на строку статуса справа (замечание к G2: на
## 1366 полоса в 799 точек по середине экрана доходила до 1082, а статус начинается
## с 1023 — на снимке «…идут на цельПланета (Ядерная ракета): 23 с»). Полоски стоят на
## той же высоте, что статус, и обязаны умещаться между левым краем и им. Откат — по
## середине экрана, как было (на 1366 краснеет, на 1920 места хватает и так).
func test_toast_not_on_status() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		var got := await hooks.set_window_size(size)
		var main := MainScene.instantiate()
		tree.root.add_child(main)
		await hooks.frames(6)
		var poly: Polygon = main.get("polygon")
		var view := poly.view
		var b := view.battle
		view.paused = true
		var all_own: Array[int] = []
		var foe: Ship = null
		for s in b.ships:
			if s.side == Ship.ATTACKER:
				all_own.append(s.uid)
			elif s.def.id == &"cruiser" and foe == null:
				foe = s
		view.selection = all_own
		b.queue({"op": &"focus", "ids": all_own, "target": foe.uid})
		view.paused = false
		view.advance(Battle.STEP)
		view.paused = true
		await hooks.frames(3)
		var tag := "%d×%d" % [got.x, got.y]
		var fps: Node = main.get("fps")
		var hint: Label = fps.get("hint")
		var hud: Node = poly.get("hud")
		var status: Label = hud.get("status")
		var toasts: Label = hud.get("toasts")
		ok(toasts.text.contains("Цель — ") and toasts.text.contains("лёгкие идут на цель"), "%s %s: полоска фокуса всего флота: «%s»" % [renderer(), tag, toasts.text.replace("\n", " / ")])
		ok(not toasts.get_global_rect().intersects(status.get_global_rect()), "%s %s: полоска (%s) не наезжает на строку статуса (%s)" % [renderer(), tag, str(toasts.get_global_rect()), str(status.get_global_rect())])
		ok(not toasts.get_global_rect().intersects(hint.get_global_rect()), "%s %s: и на подсказку клавиш (%s)" % [renderer(), tag, str(hint.get_global_rect())])
		ok(toasts.get_global_rect().position.x >= 0.0 and toasts.get_global_rect().end.x <= float(got.x), "%s %s: полоска в пределах экрана" % [renderer(), tag])
		tree.root.get_texture().get_image().save_png(_shots_dir().path_join("toast_%s_%s.png" % [renderer(), tag]))
		if got.x < 1500:
			PolygonHud.rollback_toast_center = true
			await hooks.frames(2)
			ok(toasts.get_global_rect().intersects(status.get_global_rect()), "%s %s: откат «полоска по середине экрана» наезжает на статус (%s) — проверка краснеет" % [renderer(), tag, str(toasts.get_global_rect())])
			PolygonHud.rollback_toast_center = false
		main.queue_free()
		await hooks.frames(3)
		b.dispose()
