# Эффекты боя (пакет GЭ; ярус fx — под xvfb в ОБОИХ отрисовщиках, run_tests.sh render). Каждая
# проверка — с откатом, и откат краснит СВОЮ проверку:
# - пятящийся тяжёлый без маршевого факела, у реверса свой знак (08, 7.2 п. 7); откат —
#   «факел по скорости», как thrustNow в JS: факел горит у пятящегося; факел тянется с тягой
#   (тот же откат: у стоящего с полной тягой факела нет);
# - источник выстрела различим НА СНИМКЕ (08, 7.4): у главного калибра, батареи, лёгкого, ПВО,
#   авиации, ракеты и орудия планеты — свой цвет, толщина или длина, замером по точкам снимка;
#   откат — все одним видом (тонкий сиреневый луч): различить нечем;
# - взрыв не белый (08, ловушка 6): белое — маленькое короткое ядро, дальше огонь; гибель
#   тяжёлого крупнее и дольше лёгкого; откат — прежняя вспышка с белой серединой во весь размер;
# - подбитый дымит (08, 1.3); откат — не дымит;
# - купол РЭБ: в покое — без стенки, у выбранного — полный, отдельным узлом, на паузе так же,
#   уходит с кораблём; откат — полный купол и в покое, как в JS;
# - гипер: воронка ухода раскрывается за 2,4 с до перехода, воронка выхода живёт 2,0 с; откат —
#   воронки нет;
# - прогрев: после первых кадров боя ни взрыв, ни купол, ни гипер, ни дым, ни залп не собирают
#   конвейеров (отдельным процессом, tests/probe_fx_warm.gd); откат — прогрева нет;
# - снимки боя на 1920 и 1366: старт, огонь на 40-й секунде, крупно; место планеты на старте —
#   у края и не на кораблях; дымка у края планеты ярче со стороны звезды (откат — ровная, как до GЭ); М14 на
#   рабочем виде — откат `--old-camera` краснеет;
# - «Что попробовать» выпуска 0.9 — событиями ввода на 1366 и 1920 (откаты «белая клякса»
#   и «без воронки»).
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Weapons := preload("res://sim/weapons.gd")
const Hangar := preload("res://sim/hangar.gd")
const Squad := preload("res://sim/squad.gd")
const Proj := preload("res://sim/proj.gd")
const Craft := preload("res://sim/craft.gd")
const BattleView := preload("res://view/battle_view.gd")
const BattleFx := preload("res://view/battle_fx.gd")
const HyperFx := preload("res://view/hyper_fx.gd")
const SpaceEnv := preload("res://view/space_env.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const MainScene := preload("res://main.tscn")
const MainScript := preload("res://main.gd")
const Polygon := preload("res://tools/polygon.gd")
const SK := preload("res://tests/test_render_skirmish.gd")

const BIG := 1.0e9

var _sk: SK


## Лаборатория и помощники — у проверок «Перестрелки» (tests/test_render_skirmish.gd): вторая
## копия разошлась бы с первой.
func _lab() -> SK:
	if _sk == null:
		_sk = SK.new()
	_sk.tree = tree
	_sk.hooks = hooks
	return _sk


static func renderer() -> String:
	return SK.renderer()


static func lum(c: Color) -> float:
	return SK.lum(c)


func _step_draw(v: BattleView, frac: float = 0.5) -> void:
	v.paused = false
	v.advance(Battle.STEP)
	v.acc = frac * Battle.STEP
	v.paused = true
	v.draw_state()


func _shot(name: String = "") -> Image:
	await hooks.frames(3)
	var img := tree.root.get_texture().get_image()
	if name != "":
		img.save_png(_lab()._shots_dir().path_join("%s_%s.png" % [name, renderer()]))
	return img


## Свет снимка b сверх снимка a (по каналам, не меньше нуля).
static func _over(a: Image, b: Image, x: int, y: int) -> Color:
	var c1 := b.get_pixel(x, y)
	var c0 := a.get_pixel(x, y)
	return Color(maxf(c1.r - c0.r, 0.0), maxf(c1.g - c0.g, 0.0), maxf(c1.b - c0.b, 0.0))


# ───────────────────────── пятящийся тяжёлый без маршевого факела ─────────────────────────

## Крейсер на «Охране», чужой корвет в его мёртвой зоне: тяжёлый пятится носом к нему (09, 2.5).
## → сколько шагов он пятился, на скольких горел маршевый факел и знак реверса, и свет факела
## на снимке (снимок с факелами минус тот же кадр без них).
func _backing(by_speed: bool) -> Dictionary:
	BattleView.rollback_plume_by_speed = by_speed
	var sk := _lab()
	var v := await sk._lab_view(func(b: Battle) -> void:
		var c := sk._quiet(sk._put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -600)))
		c.off_until.erase(&"engines")
		c.stance = &"guard"
		sk._quiet(sk._put(b, Ship.DEFENDER, &"corvette", Vector2(0, -230), Vector2(0, 0))))
	var s := v.battle.ships[0]
	v.rig.set_view(Vector3(0, 0, 80), 0.0, 900.0, true)
	var backing := 0
	var main_on := 0
	var rev_on := 0
	var thr_rev := 0
	var lit := -1
	for i in 150:
		_step_draw(v)
		var along := s.vel.dot(s.dir)
		if i < 20 or along > -2.0:
			continue
		backing += 1
		if s.thrust_rev > 0.0 and s.thrust_fwd <= 0.0:
			thr_rev += 1
		var dp: Vector2 = v.drawn_plumes.get(s.uid, Vector2.ZERO)
		if dp.x > 0.0:
			main_on += 1
		if dp.y >= BattleView.REV_MIN:
			rev_on += 1
		if backing == 20:
			# свет маршевых факелов на снимке ПОКА пятится: кадр как есть минус тот же кадр с
			# погашенными факелами
			var with := await _shot("backing_%s" % ("speed" if by_speed else "ok"))
			var plumes: Array = v._plume.get(s.uid, [])
			var was: Array[bool] = []
			for p: MeshInstance3D in plumes:
				was.append(p.visible)
				p.visible = false
			var without := await _shot()
			for k in plumes.size():
				var p2: MeshInstance3D = plumes[k]
				p2.visible = was[k]
			lit = 0
			for y in range(0, with.get_height(), 2):
				for x in range(0, with.get_width(), 2):
					if lum(_over(without, with, x, y)) > 0.03:
						lit += 1
			break
	BattleView.rollback_plume_by_speed = false
	note("%s · пятится%s: шагов %d, тяга назад на %d, маршевый факел на %d, знак реверса на %d, света факелов на снимке %d точек" % [renderer(), " (откат «по скорости»)" if by_speed else "", backing, thr_rev, main_on, rev_on, lit])
	await sk._drop(v)
	return {"back": backing, "rev_thrust": thr_rev, "main": main_on, "rev": rev_on, "lit": lit}


func test_backing_heavy_no_main_plume() -> void:
	var r := await _backing(false)
	var n := whole(r["back"])
	ok(n >= 20, "%s: крейсер пятится от корвета в мёртвой зоне (%d шагов задним ходом)" % [renderer(), n])
	ok(whole(r["rev_thrust"]) >= n * 0.9, "%s: модель даёт тягу назад, а не вперёд (%d из %d)" % [renderer(), whole(r["rev_thrust"]), n])
	eq(whole(r["main"]), 0, "%s: у пятящегося тяжёлого маршевого факела нет (08, 7.2 п. 7)" % renderer())
	ok(whole(r["rev"]) >= n * 0.8, "%s: у реверса свой знак у носа (%d из %d)" % [renderer(), whole(r["rev"]), n])
	ok(whole(r["lit"]) == 0, "%s: на снимке пятящегося маршевые факелы не светят (%d точек)" % [renderer(), whole(r["lit"])])
	var o := await _backing(true)
	ok(whole(o["main"]) >= whole(o["back"]) * 0.8 and whole(o["lit"]) > 20, "%s: откат «факел по скорости»: пятящийся «газует вперёд» — факел на %d шагах из %d, %d точек света — проверка краснеет" % [renderer(), whole(o["main"]), whole(o["back"]), whole(o["lit"])])


## Факел тянется с тягой: стоящий крейсер, тяга по носу 0 / 0,25 / 1 (сглаживание сброшено) →
## длина нарисованного факела. Откат «факел по скорости»: стоящий корабль без факела при любой тяге.
func _plume_by_thrust(by_speed: bool) -> PackedFloat64Array:
	BattleView.rollback_plume_by_speed = by_speed
	var sk := _lab()
	var v := await sk._lab_view(func(b: Battle) -> void:
		var c := sk._quiet(sk._put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -600)))
		c.off_until.erase(&"engines")
		sk._quiet(sk._put(b, Ship.DEFENDER, &"corvette", Vector2(2300, -2300), Vector2(0, 0))))
	var s := v.battle.ships[0]
	var out := PackedFloat64Array()
	for t: float in [0.0, 0.25, 1.0]:
		s.thrust_fwd = t
		s.thrust_rev = 0.0
		v._plume_k.erase(s.uid)
		v.draw_state()
		var dp: Vector2 = v.drawn_plumes.get(s.uid, Vector2.ZERO)
		out.append(dp.x)
	BattleView.rollback_plume_by_speed = false
	note("%s · факел по тяге 0 / 0,25 / 1%s: %s" % [renderer(), " (откат «по скорости»)" if by_speed else "", str(out)])
	await sk._drop(v)
	return out


func test_plume_follows_thrust() -> void:
	var r := await _plume_by_thrust(false)
	ok(r[0] == 0.0 and r[1] > 0.0 and r[2] >= r[1] * 2.0, "%s: факел тянется с тягой — без тяги нет, на полной вдвое длиннее, чем на четверти (%.1f, %.1f, %.1f)" % [renderer(), r[0], r[1], r[2]])
	var o := await _plume_by_thrust(true)
	ok(o[2] == 0.0, "%s: откат «факел по скорости» — у стоящего с полной тягой факела нет (%.1f), проверка краснеет" % [renderer(), o[2]])


# ───────────────────────── источник выстрела различим на снимке ─────────────────────────

const SOURCES: Array[StringName] = [&"main", &"sec", &"light", &"pd", &"craft", &"missile", &"gun"]

## Признаки выстрела по снимку (разница с кадром до выстрела) в полосе ±28 точек вокруг отрезка
## «стрелок → цель» на экране: цвет света (оттенок и насыщенность), какая доля длины отрезка
## светится (луч — вся, очередь и росчерк — часть) и толщина светящегося в точках.
static func _features(img0: Image, img1: Image, a: Vector2, b: Vector2) -> Dictionary:
	var w := img1.get_width()
	var h := img1.get_height()
	var d := b - a
	var len := maxf(d.length(), 1.0)
	var u := d / len
	var nrm := Vector2(-u.y, u.x)
	# видимая часть отрезка
	var t0 := 0.0
	var t1 := 1.0
	var rect := Rect2(Vector2(4, 4), Vector2(w - 8, h - 8))
	var first := -1.0
	var last := -1.0
	for k in 201:
		var t := float(k) / 200.0
		if rect.has_point(a + d * t):
			if first < 0.0:
				first = t
			last = t
	if first < 0.0:
		return {"lit": 0, "span": 0.0, "thick": 0.0, "hue": -1.0, "sat": 0.0}
	t0 = first
	t1 = last
	var bins := 40
	var cover := PackedInt32Array()
	cover.resize(bins)
	var rs := 0.0
	var gs := 0.0
	var bs := 0.0
	var lit := 0
	var steps := int(len * (t1 - t0))
	for k in steps + 1:
		var t := lerpf(t0, t1, float(k) / maxf(float(steps), 1.0))
		var p := a + d * t
		for o in range(-28, 29):
			var q := (p + nrm * o).round()
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
				continue
			var dc := _over(img0, img1, int(q.x), int(q.y))
			var dl := lum(dc)
			if dl > 0.04:
				lit += 1
				rs += dc.r
				gs += dc.g
				bs += dc.b
				if absi(o) <= 6:
					cover[clampi(int(float(k) / maxf(float(steps), 1.0) * bins), 0, bins - 1)] = 1
	var cov := 0
	for c in cover:
		cov += c
	var span := float(cov) / bins
	var col := Color(rs, gs, bs)
	var m := maxf(maxf(col.r, col.g), col.b)
	if m > 0.0:
		col = Color(col.r / m, col.g / m, col.b / m)
	var thick := float(lit) / maxf(float(cov) * maxf(len * (t1 - t0) / bins, 1.0), 1.0)
	return {"lit": lit, "span": span, "thick": thick, "hue": col.h * 360.0 if m > 0.0 else -1.0, "sat": col.s if m > 0.0 else 0.0}


## Один выстрел источника kind в лаборатории: стрелки и цель стоят, событие выстрела подано
## прямо в вид (то же, что приходит из модели), снимок — через 0,08 с игрового времени.
func _source_shot(kind: StringName) -> Dictionary:
	var sk := _lab()
	var v := await sk._lab_view(func(b: Battle) -> void:
		sk._quiet(sk._put(b, Ship.ATTACKER, &"cruiser", Vector2(-160, 0), Vector2(-160, -600)))
		sk._quiet(sk._put(b, Ship.ATTACKER, &"frigate", Vector2(160, 0), Vector2(160, -600)))
		sk._quiet(sk._put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -520), Vector2(0, 0)))
		sk._quiet(sk._put(b, Ship.ATTACKER, &"carrier", Vector2(0, 260), Vector2(0, -600))), {"ground_gun": "defender"})
	var b := v.battle
	var cr := b.ships[0]
	var fr := b.ships[1]
	var t := b.ships[2]
	var car := b.ships[3]
	v.rig.set_view(Vector3(0, 0, -200), 0.0, 1400.0, true)
	var cam := v.rig.camera
	var a3 := v.ship_point(cr)
	var b3 := v.ship_point(t)
	var pr: Variant = null
	var sq: Squad = null
	if kind == &"pd":
		pr = Weapons.spawn_proj(b, t, fr, 10.0, &"missile", 20.0, BIG, Vector2(0, 1))
		var pp: Proj = pr
		pp.pos = Vector2(160, -200)
	elif kind == &"craft":
		sq = Hangar.launch(b, car, &"interceptor")
	_step_draw(v)
	var img0 := await _shot()
	match kind:
		&"main", &"sec":
			v.bfx.consume([&"fire", cr.uid, t.uid, kind, 0, t.pos])
			a3 = v.bfx._node_pt(cr, "muzzle_" if kind == &"main" else "aux_", 0)
		&"light":
			v.bfx.consume([&"fire", fr.uid, t.uid, &"light", 0, t.pos])
			a3 = v.bfx._node_pt(fr, "muzzle_", 0)
		&"pd":
			var pp2: Proj = pr
			var to3: Vector3 = v.bfx._proj_at.get(pp2.uid, Vector3(pp2.pos.x, 0.0, pp2.pos.y))
			v.bfx.consume([&"pd", fr.uid, 0, pp2.pos, pp2.uid])
			a3 = v.bfx._node_pt(fr, "pd_", 0)
			b3 = to3
		&"craft":
			var c: Craft = null
			if not b.crafts.is_empty():
				c = b.crafts[0]
			if c != null:
				v.air.consume([&"craft_fire", c.uid, t.uid, t.pos])
				a3 = v.air.point_of(c, 1.0)
		&"gun":
			v.bfx.consume([&"gun_fire", &"beam", t.pos, PackedInt32Array([t.uid])])
			a3 = SpaceEnv.PLANET_CENTER + (b3 - SpaceEnv.PLANET_CENTER).normalized() * SpaceEnv.PLANET_RADIUS
		&"missile":
			# ракета выходит перед носом (у крейсера пакета нет — точка пуска своя): у корпуса её
			# закрыл бы сам корабль
			var m := Weapons.spawn_proj(b, cr, t, 10.0, &"missile", 160.0, BIG, Vector2(0, -1))
			m.pos = cr.pos + Vector2(0, -110)
			v.bfx.consume([&"proj", m.uid])
			a3 = Vector3(m.pos.x, a3.y, m.pos.y)
	var n := 10 if kind == &"missile" else 2
	for i in n:
		_step_draw(v)
	var img1 := await _shot("source_%s%s" % [kind, "_one" if BattleFx.rollback_one_look else ""])
	# начало отрезка на экране: точка позади камеры (луч с планеты) — сдвигаем к цели
	var a := cam.unproject_position(a3)
	if cam.is_position_behind(a3):
		a = cam.unproject_position(b3.lerp(a3, 0.3))
	var f := _features(img0, img1, a, cam.unproject_position(b3))
	f["kind"] = kind
	await sk._drop(v)
	return f


## Отличаются ли два выстрела на снимке: цветом (оттенок на 25° и больше при насыщенности не ниже
## 0,15), толщиной (в 1,4 раза) или длиной (доля отрезка на 0,35).
static func _distinct(p: Dictionary, q: Dictionary) -> bool:
	var hp: float = p["hue"]
	var hq: float = q["hue"]
	var sp: float = p["sat"]
	var sq2: float = q["sat"]
	var dh := absf(hp - hq)
	dh = minf(dh, 360.0 - dh)
	if hp >= 0.0 and hq >= 0.0 and sp >= 0.15 and sq2 >= 0.15 and dh >= 25.0:
		return true
	var tp: float = p["thick"]
	var tq: float = q["thick"]
	if maxf(tp, tq) >= 1.4 * maxf(minf(tp, tq), 0.5):
		return true
	var ap: float = p["span"]
	var aq: float = q["span"]
	return absf(ap - aq) >= 0.35


func _sources(one: bool) -> Array[Dictionary]:
	BattleFx.rollback_one_look = one
	var out: Array[Dictionary] = []
	for k in SOURCES:
		var f := await _source_shot(k)
		out.append(f)
		note("%s · %s%s: светится %d точек, доля отрезка %.2f, толщина %.1f, оттенок %.0f°, насыщенность %.2f" % [renderer(), k, " (откат)" if one else "",
			whole(f["lit"]), num(f["span"]), num(f["thick"]), num(f["hue"]), num(f["sat"])])
	BattleFx.rollback_one_look = false
	return out


func test_shot_source_reads_on_screen() -> void:
	var fs := await _sources(false)
	var same := PackedStringArray()
	for i in fs.size():
		ok(whole(fs[i]["lit"]) > 12, "%s: выстрел «%s» виден на снимке (%d точек)" % [renderer(), fs[i]["kind"], whole(fs[i]["lit"])])
		for j in range(i + 1, fs.size()):
			if not _distinct(fs[i], fs[j]):
				same.append("%s ~ %s" % [fs[i]["kind"], fs[j]["kind"]])
	ok(same.is_empty(), "%s: все семь источников различимы на снимке (не различаются: %s)" % [renderer(), ", ".join(same)])
	# откат: все выстрелы одним видом — шесть источников (все, кроме ракеты) не различить
	var os := await _sources(true)
	var same_o := 0
	for i in os.size():
		for j in range(i + 1, os.size()):
			if os[i]["kind"] != &"missile" and os[j]["kind"] != &"missile" and not _distinct(os[i], os[j]):
				same_o += 1
	ok(same_o >= 10, "%s: откат «все одним видом»: неразличимых пар %d из 15 — проверка краснеет" % [renderer(), same_o])


# ───────────────────────── взрыв не белый ─────────────────────────

## Гибель корабля id в лаборатории: доли белого и тёплого среди светящегося на 0,05 / 0,25 / 0,6 с
## и площадь света на 1,2 с.
func _boom(id: StringName, white: bool) -> Dictionary:
	BattleFx.rollback_white_boom = white
	var sk := _lab()
	var v := await sk._lab_view(func(b: Battle) -> void:
		sk._quiet(sk._put(b, Ship.DEFENDER, id, Vector2(0, 0), Vector2(0, 500)))
		sk._quiet(sk._put(b, Ship.ATTACKER, &"corvette", Vector2(2300, 2300), Vector2(0, 0)))
		# второй защитник за кадром: без него бой кончится на гибели первого, и вид встанет (раздел 2)
		sk._quiet(sk._put(b, Ship.DEFENDER, &"corvette", Vector2(-2300, -2300), Vector2(0, 0))))
	var s := v.battle.ships[0]
	v.rig.set_view(Vector3(0, 0, 60), 0.0, 1100.0, true)
	_step_draw(v)
	var img0 := await _shot()
	s.dead = true
	v.bfx.consume([&"destroyed", s.uid, 0])
	var out := {}
	var age := 0.0
	for want: float in [0.05, 0.25, 0.6, 1.2]:
		while age + 0.001 < want - Battle.STEP * 0.5:
			_step_draw(v, 0.5)
			age += Battle.STEP
		var img := await _shot("boom_%s_%03d%s" % [id, roundi(want * 100.0), "_white" if white else ""])
		var lit := 0
		var wh := 0
		var warm := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var dc := _over(img0, img, x, y)
				if lum(dc) <= 0.05:
					continue
				lit += 1
				var c := img.get_pixel(x, y)
				if minf(minf(c.r, c.g), c.b) > 0.85:
					wh += 1
				elif c.r > c.g * 1.2 and c.r > c.b * 1.5:
					warm += 1
		out["lit_%03d" % roundi(want * 100.0)] = lit
		out["white_%03d" % roundi(want * 100.0)] = float(wh) / maxf(float(lit), 1.0)
		out["warm_%03d" % roundi(want * 100.0)] = float(warm) / maxf(float(lit), 1.0)
	BattleFx.rollback_white_boom = false
	note("%s · гибель «%s»%s: %s" % [renderer(), id, " (откат «белая клякса»)" if white else "", str(out)])
	await sk._drop(v)
	return out


func test_explosion_not_white() -> void:
	var r := await _boom(&"cruiser", false)
	ok(num(r["white_005"]) <= 0.15, "%s: в начале взрыва белого мало — %.3f светящегося (ядро маленькое)" % [renderer(), num(r["white_005"])])
	ok(num(r["white_025"]) <= 0.05 and num(r["white_060"]) <= 0.05, "%s: дальше белого почти нет (%.3f, %.3f)" % [renderer(), num(r["white_025"]), num(r["white_060"])])
	ok(num(r["warm_025"]) >= 0.3, "%s: взрыв — огонь: тёплого %.2f светящегося на 0,25 с" % [renderer(), num(r["warm_025"])])
	var o := await _boom(&"cruiser", true)
	ok(num(o["white_005"]) > 0.15, "%s: откат «белая клякса» краснеет: белого %.3f светящегося (как в игре — %.3f)" % [renderer(), num(o["white_005"]), num(r["white_005"])])
	# гибель тяжёлого крупнее и дольше лёгкого
	var cap := await _boom(&"capital", false)
	var cor := await _boom(&"corvette", false)
	ok(whole(cap["lit_025"]) > whole(cor["lit_025"]) * 2 and whole(cap["lit_120"]) > whole(cor["lit_120"]) * 2,
		"%s: гибель флагмана крупнее и дольше корвета: света на 0,25 с — %d против %d, на 1,2 с — %d против %d" % [renderer(),
		whole(cap["lit_025"]), whole(cor["lit_025"]), whole(cap["lit_120"]), whole(cor["lit_120"])])


# ───────────────────────── подбитый дымит ─────────────────────────

func _hurt(hp_frac: float, off: bool) -> Dictionary:
	BattleFx.rollback_no_hurt_smoke = off
	var sk := _lab()
	var v := await sk._lab_view(func(b: Battle) -> void:
		var c := sk._quiet(sk._put(b, Ship.DEFENDER, &"cruiser", Vector2(0, 0), Vector2(0, 500)))
		c.hp = c.max_hp * hp_frac
		sk._quiet(sk._put(b, Ship.ATTACKER, &"corvette", Vector2(2300, 2300), Vector2(0, 0))))
	v.rig.set_view(Vector3(0, 0, 60), 0.0, 900.0, true)
	var puffs0 := v.bfx.hurt_puffs
	var sm0 := v.bfx.gfx.smokes_written
	for i in 90:
		_step_draw(v)
	await _shot("hurt_%02d%s" % [roundi(hp_frac * 100.0), "_off" if off else ""])
	var out := {"puffs": v.bfx.hurt_puffs - puffs0, "smokes": v.bfx.gfx.smokes_written - sm0}
	BattleFx.rollback_no_hurt_smoke = false
	await sk._drop(v)
	return out


func test_hurt_ship_smokes() -> void:
	var r := await _hurt(0.2, false)
	ok(whole(r["puffs"]) >= 6 and whole(r["smokes"]) >= 6, "%s: подбитый (20%%) дымит: клубов %d за 3 с" % [renderer(), whole(r["puffs"])])
	var c := await _hurt(1.0, false)
	eq(whole(c["puffs"]), 0, "%s: целый не дымит" % renderer())
	var o := await _hurt(0.2, true)
	eq(whole(o["puffs"]), 0, "%s: откат «подбитые не дымят» — клубов нет, проверка краснеет" % renderer())


# ───────────────────────── купол РЭБ ─────────────────────────

func _wall(v: BattleView, s: Ship) -> MeshInstance3D:
	var parts: Array = v.bfx._domes.get(s.uid, [])
	return parts[1] if parts.size() > 1 else null


## Свет стенки на снимке: точки на окружности поля над и под плоскостью кольца (стенка 90 в
## высоту) — светятся ли.
func _wall_light(v: BattleView, s: Ship, img: Image) -> float:
	var cam := v.rig.camera
	var y := v.ship_point(s).y
	var r := v.battle.defs.factions[&"troyden"].ecm.radius
	var n := 0
	var lit := 0
	for k in 48:
		var ang := TAU * k / 48.0
		var on_ring := cam.unproject_position(Vector3(cos(ang) * r, y, sin(ang) * r))
		for dy: float in [-30.0, 30.0]:
			var p := cam.unproject_position(Vector3(cos(ang) * r, y + dy, sin(ang) * r))
			if p.x < 2 or p.y < 2 or p.x > img.get_width() - 3 or p.y > img.get_height() - 3:
				continue
			# у боков кольцо на экране идёт вверх-вниз, и точка над ним ложится на само кольцо
			var near_ring := false
			for k2 in 24:
				var a2 := ang + (float(k2) - 12.0) * 0.01
				var q := cam.unproject_position(Vector3(cos(a2) * r, y, sin(a2) * r))
				near_ring = near_ring or q.distance_to(p) < 5.0
			if near_ring or on_ring.distance_to(p) < 5.0:
				continue
			n += 1
			if lum(img.get_pixel(roundi(p.x), roundi(p.y))) > 0.03:
				lit += 1
	return float(lit) / maxf(float(n), 1.0)


func _dome(full_rest: bool) -> Dictionary:
	BattleFx.rollback_dome_full_rest = full_rest
	var sk := _lab()
	var v := await sk._lab_view(func(b: Battle) -> void:
		sk._quiet(sk._put(b, Ship.ATTACKER, &"ecm", Vector2(0, 0), Vector2(0, -100)))
		sk._quiet(sk._put(b, Ship.DEFENDER, &"corvette", Vector2(2200, -2200), Vector2(0, 0))))
	var s := v.battle.ships[0]
	v.rig.set_view(Vector3(0, 0, 0), 0.0, 2000.0, true)
	for i in 90:
		_step_draw(v)
	var img_rest := await _shot("dome_rest%s" % ("_full" if full_rest else ""))
	var wall := _wall(v, s)
	var out := {"rest_wall": wall != null and wall.visible, "rest_light": _wall_light(v, s, img_rest)}
	v.selection = [s.uid]
	v.draw_state()
	var img_sel := await _shot("dome_selected")
	out["sel_wall"] = wall != null and wall.visible
	out["sel_light"] = _wall_light(v, s, img_sel)
	out["own_node"] = wall != null and wall.get_parent() == v.bfx
	# на паузе так же: кадры идут, игровое время стоит
	v.set_process(true)
	await hooks.frames(10)
	v.set_process(false)
	out["pause_wall"] = wall != null and wall.visible
	# уходит с кораблём
	s.dead = true
	v.draw_state()
	var parts: Array = v.bfx._domes.get(s.uid, [])
	var any := false
	for p: MeshInstance3D in parts:
		any = any or p.visible
	out["gone"] = not any
	v.selection = []
	BattleFx.rollback_dome_full_rest = false
	note("%s · купол%s: %s" % [renderer(), " (откат «полный и в покое»)" if full_rest else "", str(out)])
	await sk._drop(v)
	return out


func test_dome_full_only_when_selected() -> void:
	var r := await _dome(false)
	ok(not flag(r["rest_wall"]) and num(r["rest_light"]) < 0.1, "%s: в покое стенки нет (свет над и под кольцом на %.0f%% точек)" % [renderer(), num(r["rest_light"]) * 100.0])
	ok(flag(r["sel_wall"]) and num(r["sel_light"]) >= 0.5, "%s: у выбранного РЭБ купол полный (свет стенки на %.0f%% точек)" % [renderer(), num(r["sel_light"]) * 100.0])
	ok(flag(r["own_node"]), "%s: стенка купола — свой узел, а не часть модели" % renderer())
	ok(flag(r["pause_wall"]), "%s: на паузе купол тот же" % renderer())
	ok(flag(r["gone"]), "%s: погиб или ушёл — купола нет" % renderer())
	var o := await _dome(true)
	ok(flag(o["rest_wall"]) and num(o["rest_light"]) >= 0.5, "%s: откат «полный купол и в покое, как в JS» виден (%.0f%%) — проверка краснеет" % [renderer(), num(o["rest_light"]) * 100.0])


# ───────────────────────── гипер ─────────────────────────

func _hyper(off: bool) -> Dictionary:
	HyperFx.rollback_no_funnel = off
	var sk := _lab()
	var v := await sk._lab_view(func(b: Battle) -> void:
		var c := sk._quiet(sk._put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 0), Vector2(0, -600)))
		c.off_until.erase(&"engines")
		sk._quiet(sk._put(b, Ship.DEFENDER, &"corvette", Vector2(2300, -2300), Vector2(0, 0)))
		sk._quiet(sk._put(b, Ship.ATTACKER, &"frigate", Vector2(300, 300), Vector2(300, -600))))
	var b := v.battle
	var s := b.ships[0]
	var fr := b.ships[2]
	v.rig.set_view(Vector3(0, 0, -150), 0.0, 1300.0, true)
	b.queue({"op": &"hyper", "ids": [s.uid]})
	var opened_at := -1.0
	var shot := false
	var out_at := -1.0
	var closed_after := -1.0
	for i in 600:
		_step_draw(v)
		var op: float = v.hyper.drawn_open.get(s.uid, 0.0)
		if op > 0.0 and opened_at < 0.0:
			opened_at = s.hyper_left
		if op >= 1.0 and not shot:
			shot = true
			await _shot("hyper_open%s" % ("_off" if off else ""))
		if s.dead and out_at < 0.0:
			out_at = b.time
		if out_at >= 0.0 and closed_after < 0.0:
			var any := false
			for k: int in v.hyper.drawn_open:
				any = any or k < 0
			if not any:
				closed_after = b.time - out_at
		if closed_after >= 0.0:
			break
	# выход: воронка позади вышедшего живёт 2,0 с
	v.hyper.consume([&"jump_in", fr.uid])
	var t_in := b.time
	var live := 0.0
	for i in 90:
		_step_draw(v)
		var any2 := false
		for k: int in v.hyper.drawn_open:
			any2 = any2 or k < 0
		if any2:
			live = b.time - t_in
	HyperFx.rollback_no_funnel = false
	var out := {"opened_at": opened_at, "closed_after": closed_after, "in_life": live}
	note("%s · гипер%s: %s" % [renderer(), " (откат «без воронки»)" if off else "", str(out)])
	await sk._drop(v)
	return out


func test_hyper_funnel_timings() -> void:
	var r := await _hyper(false)
	var at := num(r["opened_at"])
	ok(at > HyperFx.OPEN_LEFT - Battle.STEP * 1.5 and at <= HyperFx.OPEN_LEFT + 1e-6, "%s: воронка ухода раскрывается за 2,4 с до перехода (до перехода оставалось %.3f с)" % [renderer(), at])
	ok(num(r["closed_after"]) >= 0.0 and num(r["closed_after"]) <= HyperFx.CLOSE_S + Battle.STEP * 2.0, "%s: после перехода воронка схлопывается (%.2f с)" % [renderer(), num(r["closed_after"])])
	ok(absf(num(r["in_life"]) - HyperFx.IN_LIFE) <= Battle.STEP * 2.0, "%s: воронка выхода живёт 2,0 с (%.2f)" % [renderer(), num(r["in_life"])])
	var o := await _hyper(true)
	ok(num(o["opened_at"]) < 0.0 and num(o["in_life"]) <= 0.0, "%s: откат «без воронки» — воронок нет, проверка краснеет" % renderer())


# ───────────────────────── прогрев — отдельным процессом ─────────────────────────

const PROBE_WAIT_MS := 240000


func _warm_probe(mode: String) -> Dictionary:
	var out := tmp("probe_fx_warm_%s.json" % mode)
	DirAccess.remove_absolute(out)
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--rendering-method", renderer(),
		"-s", "res://tests/probe_fx_warm.gd", "--", mode, out])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if not ok(pid > 0, "проба прогрева эффектов %s запустилась" % mode):
		return {}
	var t0 := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < PROBE_WAIT_MS:
		await hooks.frames(1)
	if OS.is_process_running(pid):
		OS.kill(pid)                      # только свой PID
		ok(false, "проба прогрева эффектов %s зависла" % mode)
		return {}
	var j := JSON.new()
	var text := FileAccess.get_file_as_string(out)
	DirAccess.remove_absolute(out)
	if not ok(j.parse(text) == OK and typeof(j.data) == TYPE_DICTIONARY, "проба прогрева эффектов %s оставила итог: «%s»" % [mode, text]):
		return {}
	return dict(j.data)


func test_effects_warmed_no_compilations_mid_battle() -> void:
	var r := await _warm_probe("warm")
	if r.is_empty():
		return
	ok(whole(r["booms"]) == 1, "проба дошла до взрыва")
	if renderer() != "forward_plus":
		note("%s: сборок конвейеров %d → %d (проверка — в Forward+: в Compatibility счётчики молчат)" % [renderer(), whole(r["before"]), whole(r["after"])])
		ok(true, "Compatibility: проверка прогрева не применима")
		return
	ok(whole(r["before"]) > 0, "счётчики сборок конвейеров отвечают (%d)" % whole(r["before"]))
	eq(whole(r["after"]), whole(r["before"]), "после первых кадров боя ни факел, ни выбор, ни купол, ни взрыв, ни дым, ни гипер, ни залп не собирают конвейеров (%s)" % str(r["steps"]))
	var o := await _warm_probe("cold")
	if o.is_empty():
		return
	ok(whole(o["after"]) > whole(o["before"]), "откат «без прогрева» краснеет: %d → %d (%s)" % [whole(o["before"]), whole(o["after"]), str(o["steps"])])
	note("прогрев эффектов: как в игре %d → %d, откат %d → %d" % [whole(r["before"]), whole(r["after"]), whole(o["before"]), whole(o["after"])])


# ───────────────────────── снимки боя, место планеты, М14 ─────────────────────────

## Быстрый бой по выбору меню (зерно 1010): снимок старта, огня на 40-й секунде (кадр в 0,1 с
## после выстрела главного калибра) и крупно; на старте — где планета.
func _battle_shots(size: Vector2i) -> Dictionary:
	var got := await hooks.set_window_size(size)
	MainScript.seed_override = 1010
	MainScript.out_override = tmp("battle_shots")
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	await hooks.frames(4)
	main.call("open_battle", {"attacker": "troyden", "defender": "plektor", "size": "mid", "difficulty": "normal", "watch": false})
	await hooks.frames(4)
	var p: Polygon = main.get("polygon")
	var view := p.view
	view.paused = true
	view.rig.edge_enabled = false
	await hooks.frames(6)
	var tag := "%dx%d" % [got.x, got.y]
	var img := await _shot("battle_start_%s" % tag)
	# планета на старте: у края, не на кораблях, не огромная
	var cam := view.rig.camera
	var pc := cam.unproject_position(SpaceEnv.PLANET_CENTER)
	var edge := cam.unproject_position(SpaceEnv.PLANET_CENTER + cam.global_transform.basis.x * SpaceEnv.PLANET_RADIUS)
	var pr := pc.distance_to(edge)
	var on_ships := 0
	for s in view.battle.ships:
		if s.dead:
			continue
		var sp := cam.unproject_position(view.ship_point(s))
		if sp.distance_to(pc) < pr * 1.08:
			on_ships += 1
	var out := {"planet": pc, "planet_r": pr, "on_ships": on_ships, "tag": tag, "w": float(got.x), "h": float(got.y)}
	# 40-я секунда: идём до первого выстрела главного калибра после 38 с
	var b := view.battle
	var main0 := 0
	while b.time < 38.0:
		view.paused = false
		view.advance(Battle.STEP)
		view.paused = true
	main0 = whole(view.bfx.fired.get(&"main", 0))
	var guard := 0
	while whole(view.bfx.fired.get(&"main", 0)) == main0 and guard < 900:
		view.paused = false
		view.advance(Battle.STEP)
		view.paused = true
		guard += 1
	for i in 3:
		_step_draw(view)
	out["fire_t"] = b.time
	# камера — к середине между стреляющим и целью: рабочий вид
	var c := Vector2.ZERO
	var n := 0
	for s in b.ships:
		if not s.dead and s.heavy():
			c += s.pos
			n += 1
	c /= maxf(1.0, float(n))
	view.rig.set_view(Vector3(c.x, 0.0, c.y), view.rig.yaw, 2400.0, true)
	view.draw_state()
	await _shot("battle_fire_%s" % tag)
	var best: Ship = null
	for s in b.ships:
		if not s.dead and s.heavy() and (best == null or s.pos.distance_to(c) < best.pos.distance_to(c)):
			best = s
	if best != null:
		view.rig.set_view(Vector3(best.pos.x, 0.0, best.pos.y), view.rig.yaw, 900.0, true)
		view.draw_state()
		await _shot("battle_close_%s" % tag)
	main.queue_free()
	await hooks.frames(3)
	b.dispose()
	MainScript.seed_override = -1
	MainScript.out_override = ""
	return out


func test_battle_snapshots_and_planet_place() -> void:
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1366, 768)]:
		var r := await _battle_shots(size)
		var pc: Vector2 = r["planet"]
		var w := num(r["w"])
		var h := num(r["h"])
		note("%s %s: планета на старте в %s радиусом %.0f; выстрел главного калибра на %.1f с" % [renderer(), str(r["tag"]), str(pc.round()), num(r["planet_r"]), num(r["fire_t"])])
		ok(pc.x > w * 0.6 and pc.y < h * 0.4, "%s %s: планета на старте — у края, справа сверху (%s)" % [renderer(), str(r["tag"]), str(pc.round())])
		ok(num(r["planet_r"]) < h * 0.2, "%s %s: планета скромная — радиус %.0f точек (меньше пятой части высоты)" % [renderer(), str(r["tag"]), num(r["planet_r"])])
		eq(whole(r["on_ships"]), 0, "%s %s: планета не на кораблях" % [renderer(), str(r["tag"])])
		ok(num(r["fire_t"]) >= 38.0 and num(r["fire_t"]) < 60.0, "%s %s: к 40-й секунде бьёт главный калибр (%.1f с)" % [renderer(), str(r["tag"]), num(r["fire_t"])])


## Дымка у края планеты знает, где звезда (план GЭ, п. 6): свет, который добавляют дымка и венец (кадр
## с ними минус тот же кадр без них — `haze_k` = 0 и венец спрятан), в кольце 0,8–1,2 радиуса вокруг
## диска — со стороны звезды (направление на звезду по экрану, ±0,5 рад) и с обратной. Разностью,
## а не яркостью: у края диска на дневной стороне светится и сама освещённая планета, а она от отката
## не меняется. → (со стороны звезды, с обратной).
func _haze_sides(with: Image, without: Image, cam: Camera3D, sd: Vector3) -> Vector2:
	var c := SpaceEnv.PLANET_CENTER
	var pc := cam.unproject_position(c)
	var pr := pc.distance_to(cam.unproject_position(c + cam.global_transform.basis.x * SpaceEnv.PLANET_RADIUS))
	var d := (cam.unproject_position(c + sd * SpaceEnv.PLANET_RADIUS) - pc).normalized()
	var sums := PackedFloat64Array([0.0, 0.0])
	for side in 2:
		var base := d if side == 0 else -d
		for k in 21:
			var dir := base.rotated(float(k - 10) * 0.05)
			for j in 21:
				var p := pc + dir * pr * (0.8 + 0.02 * float(j))
				if p.x >= 1.0 and p.y >= 1.0 and p.x <= with.get_width() - 2 and p.y <= with.get_height() - 2:
					sums[side] += lum(_over(without, with, roundi(p.x), roundi(p.y)))
	return Vector2(sums[0], sums[1])


func _haze(flat: bool) -> Vector2:
	SpaceEnv.rollback_flat_haze = flat
	var got := await hooks.set_window_size(Vector2i(1366, 768))
	MainScript.seed_override = 1010
	MainScript.out_override = tmp("haze")
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	await hooks.frames(4)
	main.call("open_battle", {"attacker": "troyden", "defender": "plektor", "size": "mid", "difficulty": "normal", "watch": false})
	await hooks.frames(4)
	var p: Polygon = main.get("polygon")
	p.view.paused = true
	p.view.rig.edge_enabled = false
	# кнопки шапки лежат на верхнем крае диска — на время замера убираем интерфейс
	p.hud.visible = false
	await hooks.frames(12)
	var img := await _shot("haze%s_%dx%d" % ["_flat" if flat else "", got.x, got.y])
	var env: SpaceEnv = p.view.env
	env.planet_mat.set_shader_parameter("haze_k", 0.0)
	env.corona.visible = false
	var bare := await _shot()
	# null — значение по умолчанию из шейдера (своего значения материал не задавал)
	env.planet_mat.set_shader_parameter("haze_k", null)
	env.corona.visible = true
	var r := _haze_sides(img, bare, p.view.rig.camera, env.sun_dir())
	var b := p.battle
	main.queue_free()
	await hooks.frames(3)
	b.dispose()
	MainScript.seed_override = -1
	MainScript.out_override = ""
	SpaceEnv.rollback_flat_haze = false
	return r


func test_haze_knows_the_star() -> void:
	var r := await _haze(false)
	var o := await _haze(true)
	note("%s: свет дымки и венца со стороны звезды %.1f, с обратной %.1f; откат «дымка ровная» — %.1f и %.1f" % [renderer(), r.x, r.y, o.x, o.y])
	# Как в игре — 2,6 (Forward+) и 3,3 (Compatibility); откат — 0,56 и 0,94, копия до GЭ — 0,50 и 0,59
	# (на снимке дымка была заметнее с тёмной стороны; раздел 24 godot/CLAUDE.md).
	ok(r.y > 0.0 and r.x >= r.y * 2.0, "%s: дымка у края со стороны звезды вдвое ярче, чем с обратной (%.1f против %.1f)" % [renderer(), r.x, r.y])
	ok(o.y > 0.0 and o.x < o.y * 2.0, "%s: откат «дымка о звезде не знает» (как до GЭ) — со стороны звезды не вдвое ярче (%.1f и %.1f), проверка краснеет" % [renderer(), o.x, o.y])


func test_m14_working_view_old_camera() -> void:
	# ключ командной строки ставит откат камеры (main.gd → apply_flags)
	MainScript.apply_flags(PackedStringArray())
	ok(not CameraRig.old_camera, "без ключа — камера игры")
	MainScript.apply_flags(PackedStringArray(["--old-camera"]))
	ok(CameraRig.old_camera, "--old-camera из командной строки ставит камеру JS-версии")
	CameraRig.old_camera = false
	var sk := _lab()
	var r := await sk._lines_view({}, Vector2i(1366, 768), false)
	ok(flag(r["on"]) and not flag(r["under"]) and num(r["gap"]) >= 0.2, "%s: М14 на рабочем виде — обе линии в кадре, не под панелью, центры через %.2f высоты (≥ 0,2)" % [renderer(), num(r["gap"])])
	CameraRig.old_camera = true
	var o := await sk._lines_view({}, Vector2i(1366, 768), true)
	CameraRig.old_camera = false
	note("%s: М14 рабочий вид — %.2f высоты, откат «--old-camera» — %.2f" % [renderer(), num(r["gap"]), num(o["gap"])])
	ok(num(o["gap"]) < 0.2, "%s: откат «--old-camera» (обзор 52°, наклон 0,52 рад) — центры линий через %.2f высоты, М14 краснеет" % [renderer(), num(o["gap"])])


# ───────────────────────── текст выпуска 0.9 «Эффекты и свет» — шаг за шагом ─────────────────────────

## «Что попробовать» capella-v0.9 (godot/RELEASE) событиями ввода, как у игрока — на 1366 и 1920:
## 1) меню «Смотреть: ИИ против ИИ» (настоящий щелчок): около 23-й секунды первый залп главного
##    калибра и гибель первого корабля — взрыв огнём, искрами, обломками и дымом (в шаге гибели
##    в пулы легли и частицы огня, и обломки с дымом);
## 2) около 35-й секунды выходит подкрепление — позади вышедших раскрываются воронки, и хотя бы
##    одна из них на экране стартовой камеры;
## 3) к 50-й секунде в ход идут батареи, лёгкие орудия и ПВО; Пробел — пауза (часы боя стоят),
##    колесо — ближе;
## 4) «В бой»: щелчок по своему корвету, G — перед его носом за 2,4 с до ухода раскрывается воронка,
##    корвет уходит.
## Откаты: «белая клякса» (`BattleFx.rollback_white_boom`) — в шаге гибели ни обломков, ни дыма;
## «без воронки» (`HyperFx.rollback_no_funnel`) — воронок нет ни у вышедших, ни у корвета.
## Помощники меню и щелчка — у проверок интерфейса (tests/test_ui_hud.gd): вторая копия разошлась бы.
const HUD := preload("res://tests/test_ui_hud.gd")


func _hud() -> HUD:
	var h := HUD.new()
	h.tree = tree
	h.hooks = hooks
	return h


## Шаги 1–3 в «ИИ против ИИ», открытом кнопкой меню. → замеры словами.
func _walk_watch(h: HUD, size: Vector2i, until: float) -> Dictionary:
	var out := {"opened": false}
	var p: Polygon = await h._open_by_menu(size, "watch")
	if p == null:
		await h._close()
		return out
	out["opened"] = true
	var v := p.view
	var b := p.battle
	var first_main := -1.0
	var first_dead := -1.0
	var boom_parts := 0
	var boom_smokes := 0
	var arrived: Array[int] = []
	var funnels := 0
	var funnel_on_screen := false
	var cam := v.rig.camera
	var vp := Rect2(Vector2.ZERO, Vector2(size))
	v.paused = false
	while b.time < until and not b.over:
		var p0 := v.bfx.gfx.parts_written
		var s0 := v.bfx.gfx.smokes_written
		var boom0 := v.bfx.booms
		v.advance(Battle.STEP)
		if first_main < 0.0 and whole(v.bfx.fired.get(&"main", 0)) > 0:
			first_main = b.time
		if v.bfx.booms > boom0 and first_dead < 0.0:
			first_dead = b.time
			boom_parts = v.bfx.gfx.parts_written - p0
			boom_smokes = v.bfx.gfx.smokes_written - s0
		for e: Array in b.events:
			if e[0] == &"jump_in":
				var ju: int = e[1]
				arrived.append(ju)
		if b.time > 33.0 and b.time < 40.0:
			v.draw_state()
			var n := 0
			for k: int in v.hyper.drawn_open:
				if k < 0:
					n += 1
			funnels = maxi(funnels, n)
			if n > 0 and not funnel_on_screen:
				for u in arrived:
					var s := b.ship_by_uid(u)
					if s != null and not s.dead and not cam.is_position_behind(v.ship_point(s)) and vp.has_point(cam.unproject_position(v.ship_point(s))):
						funnel_on_screen = true
	out["first_main"] = first_main
	out["first_dead"] = first_dead
	out["boom_parts"] = boom_parts
	out["boom_smokes"] = boom_smokes
	out["arrived"] = arrived.size()
	out["funnels"] = funnels
	out["funnel_on_screen"] = funnel_on_screen
	out["sec"] = whole(v.bfx.fired.get(&"sec", 0))
	out["light"] = whole(v.bfx.fired.get(&"light", 0))
	out["pd"] = whole(v.bfx.fired.get(&"pd", 0))
	out["t"] = b.time
	# шаг 3: Пробел — пауза, колесо — ближе (настоящие события)
	await hooks.frames(2)
	var mid := Vector2(size) * 0.5
	await hooks.move(mid)
	await hooks.key(KEY_SPACE)
	await hooks.frames(2)
	var t0 := b.time
	await hooks.frames(10)
	out["paused"] = v.paused and absf(b.time - t0) < 1e-9
	var d0 := v.rig.dist
	for i in 6:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP
		ev.pressed = true
		ev.position = mid
		ev.global_position = mid
		Input.parse_input_event(ev)
		await hooks.frames(1)
	await hooks.frames(10)
	out["closer"] = v.rig.dist < d0 * 0.9
	await h._close()
	return out


## Шаг 4: «В бой», щелчок по знаку своего корвета, G. → сколько оставалось до ухода, когда
## воронка раскрылась, и ушёл ли он.
func _walk_corvette(h: HUD, size: Vector2i) -> Dictionary:
	var out := {"opened": false}
	var p: Polygon = await h._open_by_menu(size, "go")
	if p == null:
		await h._close()
		return out
	out["opened"] = true
	var v := p.view
	var b := p.battle
	await hooks.frames(3)
	var corv: Ship = null
	var at := Vector2.ZERO
	for m in v.markers.drawn:
		if m.squad or m.side != v.my_side:
			continue
		var s := b.ship_by_uid(m.uid)
		if s != null and s.def.id == &"corvette" and m.more == 0:
			corv = s
			at = m.frame.get_center()
			break
	if corv == null:
		await h._close()
		return out
	await hooks.move(at)
	await hooks.click(at)
	await hooks.frames(2)
	out["selected"] = v.selection == [corv.uid]
	await hooks.key(KEY_G)
	await hooks.frames(2)
	var opened_left := -1.0
	var gone := false
	v.paused = false
	for i in roundi(12.0 / Battle.STEP):
		v.advance(Battle.STEP)
		v.draw_state()
		if i == 0:
			out["charging"] = corv.hyper_left > 0.0      # приказ G ложится в бой на следующем шаге
		var op: float = v.hyper.drawn_open.get(corv.uid, 0.0)
		if op > 0.0 and opened_left < 0.0:
			opened_left = corv.hyper_left
		for e: Array in b.events:
			var eu: int = e[1] if e.size() > 1 and e[1] is int else -1
			if e[0] == &"jump_out" and eu == corv.uid:
				gone = true
		if gone:
			break
	v.paused = true
	out["opened_left"] = opened_left
	out["gone"] = gone
	await h._close()
	return out


func test_release_walkthrough() -> void:
	var h := _hud()
	for size: Vector2i in [Vector2i(1366, 768), Vector2i(1920, 1080)]:
		var tag := "%s %d×%d" % [renderer(), size.x, size.y]
		var w := await _walk_watch(h, size, 50.0)
		if not ok(flag(w["opened"]), "%s, шаг 1: «Смотреть: ИИ против ИИ» нажимается" % tag):
			continue
		note("%s: первый главный калибр %.1f с, первая гибель %.1f с (частиц огня %d, обломков и дыма %d), вышло из гипера %d, воронок разом %d, на экране %s; к %.0f-й секунде батарей %d, лёгких %d, ПВО %d; пауза %s, ближе %s" % [
			tag, num(w["first_main"]), num(w["first_dead"]), whole(w["boom_parts"]), whole(w["boom_smokes"]), whole(w["arrived"]),
			whole(w["funnels"]), str(w["funnel_on_screen"]), num(w["t"]), whole(w["sec"]), whole(w["light"]), whole(w["pd"]), str(w["paused"]), str(w["closer"])])
		ok(num(w["first_main"]) >= 20.0 and num(w["first_main"]) <= 27.0 and num(w["first_dead"]) >= 20.0 and num(w["first_dead"]) <= 27.0,
			"%s, шаг 1: около 23-й секунды первый залп главного калибра (%.1f с) и первая гибель (%.1f с)" % [tag, num(w["first_main"]), num(w["first_dead"])])
		ok(whole(w["boom_parts"]) >= 10 and whole(w["boom_smokes"]) >= 7, "%s, шаг 1: взрыв — огонь и искры (%d), обломки и дым (%d)" % [tag, whole(w["boom_parts"]), whole(w["boom_smokes"])])
		ok(whole(w["arrived"]) > 0 and whole(w["funnels"]) > 0 and flag(w["funnel_on_screen"]), "%s, шаг 2: около 35-й секунды выходит подкрепление (%d), позади вышедших воронки (%d разом), видны стартовой камерой" % [tag, whole(w["arrived"]), whole(w["funnels"])])
		ok(whole(w["sec"]) > 0 and whole(w["light"]) > 0 and whole(w["pd"]) > 0, "%s, шаг 3: к 50-й секунде стреляют батареи (%d), лёгкие орудия (%d) и ПВО (%d)" % [tag, whole(w["sec"]), whole(w["light"]), whole(w["pd"])])
		ok(flag(w["paused"]) and flag(w["closer"]), "%s, шаг 3: Пробел — пауза, колесо — ближе" % tag)
		var c := await _walk_corvette(h, size)
		note("%s, шаг 4: %s" % [tag, str(c)])
		ok(flag(c["opened"]) and flag(c.get("selected", false)) and flag(c.get("charging", false)), "%s, шаг 4: «В бой», щелчок по своему корвету выбирает его, G — он копит гипер" % tag)
		var ol := num(c.get("opened_left", -1.0))
		ok(ol > HyperFx.OPEN_LEFT - Battle.STEP * 1.5 and ol <= HyperFx.OPEN_LEFT + 1e-6 and flag(c.get("gone", false)), "%s, шаг 4: за 2,4 с до ухода перед носом раскрывается воронка (оставалось %.2f с), корвет ушёл" % [tag, ol])
	# откаты — на 1366
	BattleFx.rollback_white_boom = true
	var o1 := await _walk_watch(h, Vector2i(1366, 768), 27.0)
	BattleFx.rollback_white_boom = false
	note("откат «белая клякса»: в шаге гибели частиц огня %d, обломков и дыма %d" % [whole(o1.get("boom_parts", 0)), whole(o1.get("boom_smokes", 0))])
	ok(flag(o1["opened"]) and whole(o1["boom_smokes"]) < 7, "откат «белая клякса» краснеет шаг 1: обломков и дыма %d" % whole(o1.get("boom_smokes", 0)))
	HyperFx.rollback_no_funnel = true
	var o2 := await _walk_watch(h, Vector2i(1366, 768), 38.0)
	var o3 := await _walk_corvette(h, Vector2i(1366, 768))
	HyperFx.rollback_no_funnel = false
	note("откат «без воронки»: воронок у вышедших %d, у корвета раскрылась за %.2f с" % [whole(o2.get("funnels", 0)), num(o3.get("opened_left", -1.0))])
	ok(whole(o2.get("funnels", 0)) == 0 and num(o3.get("opened_left", -1.0)) < 0.0, "откат «без воронки» краснеет шаги 2 и 4: воронок нет")
