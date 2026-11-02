# Ручная модель крейсера Тройдена и нейтральный свет (CLAUDE.md, разделы 15 и 24). Ярус ui —
# без окна: всё здесь меряется по узлам, материалам и числам, а не по точкам снимка (снимок факела
# реверса — ярус fx, test_fx_effects → test_backing_heavy_no_main_plume). Каждая проверка —
# с откатом, и откат краснит СВОЮ проверку:
# - модель встаёт в длину корабля в бою (scale записи), узлы на месте, башня-спинал не вращается
#   (откат — запись без `fixed`);
# - материалы trim_*: цвет вершин, AO на прямом свете, общий лист; свечения glow_engine_lo
#   и glow_throat (откат `ShipModels.rollback_plain_trim`);
# - реактор вращается от ИГРОВОГО времени: на паузе стоит (откат — от настоящих часов), остальные
#   узлы не шевелятся, отпечаток боя с видом и без — один (контроль: испорченный бой расходится);
# - факел реверса у rev_* — только при тяге назад, прячется в откате «по скорости», на разгоне
#   гипера и до прогрева; знак у носа у такого корабля не рисуется, а генератор вида расходуется
#   как со знаком (откат `BattleView.rollback_rev_plume_always`);
# - нейтральный свет — числами (откат `SpaceEnv.rollback_old_light`).
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Movement := preload("res://sim/movement.gd")
const BattleView := preload("res://view/battle_view.gd")
const ShipVisual := preload("res://view/ship_visual.gd")
const ShipVisualScene := preload("res://view/ship_visual.tscn")
const ShipModels := preload("res://view/ship_models.gd")
const SpaceEnv := preload("res://view/space_env.gd")
const FxPool := preload("res://view/fx_pool.gd")
const ModelsTest := preload("res://tests/test_render_models.gd")

const BIG := 1.0e9

var _defs: Defs


func _get_defs() -> Defs:
	if _defs == null:
		_defs = Defs.load_default({}) as Defs
	return _defs


func _visual(clan: StringName, id: StringName) -> ShipVisual:
	var v := ShipVisualScene.instantiate() as ShipVisual
	ok(v.setup(clan, id), "%s.%s: модель встала" % [clan, id])
	tree.root.add_child(v)
	return v


# ───────────────────────── запись, размер, узлы ─────────────────────────

func test_hero_cruiser_record_size_nodes() -> void:
	var defs := _get_defs()
	var rec := ShipModels.ship(&"troyden", &"cruiser")
	var hand := dict(rec.get("hand", {}))
	ok(not hand.is_empty(), "крейсер Тройдена — ручная модель (поле hand)")
	var file: String = rec.get("file", "")
	ok(file.begins_with("res://view/hero/"), "файл ручной модели в view/hero/: %s" % file)
	ok(ShipModels.ship(&"plektor", &"cruiser").get("hand") == null, "крейсер Плэктора — прежний, из выгрузки three.js")
	var want := defs.ship(&"troyden", &"cruiser").model_len
	near(num(rec.get("len")), want, 0.01, "длина в обмере = model_len корабля в бою (расталкивание и строй не тронуты)")
	var v := _visual(&"troyden", &"cruiser")
	near(v.model_scale(), want / num(hand.get("raw_len")), 1e-4, "масштаб вида = model_len / длина модели")
	# длина того, что на экране: рамка геометрии модели с масштабом вида
	var box := ModelsTest.model_aabb(v)
	var got := maxf(box.size.x, box.size.z)
	ok(absf(got - want) <= want * 0.01, "длина нарисованной модели %.2f при model_len %.2f" % [got, want])
	near(box.size.x, v.width(), 0.05, "ширина в обмере = ширина нарисованной (капсула выбора)")
	for nm: StringName in [&"hull", &"turret_0", &"muzzle_0", &"engines", &"engine_0", &"engine_1", &"engine_2",
			&"pd_0", &"pd_1", &"pd_2", &"aux_0", &"aux_1", &"bay", &"reactor", &"rev_0", &"rev_1"]:
		ok(v.part(nm) != null, "узел %s на месте" % nm)
	# узел из обмера стоит там, где обещает запись (в единицах боя, у ShipVisual)
	var nodes := dict(rec.get("nodes"))
	var mz := arr(dict(nodes.get("muzzle_0")).get("pos"))
	var mp := v.to_local(v.part_point(&"muzzle_0"))
	ok(mp.distance_to(Vector3(num(mz[0]), num(mz[1]), num(mz[2]))) < 0.05, "дуло там, где в записи (%s)" % mp)
	ok(typeof(dict(nodes.get("rev_0")).get("plume")) == TYPE_DICTIONARY, "plume у rev_0 — словарь, а не строка из extras")
	# спинальное орудие не вращают; у крейсера Плэктора башня поворотная
	ok(not v.turret_can_turn(&"turret_0"), "turret_0 крейсера Тройдена — fixed, не вращать")
	var p := _visual(&"plektor", &"cruiser")
	ok(p.turret_can_turn(&"turret_0"), "у крейсера Плэктора башня поворотная")
	# откат: запись без fixed — «башню можно вращать», проверка краснеет
	var spoiled := v.record.duplicate(true)
	dict(dict(spoiled["nodes"])["turret_0"]).erase("fixed")
	var keep := v.record
	v.record = spoiled
	ok(v.turret_can_turn(&"turret_0"), "откат «без fixed»: спинал вращался бы — проверка краснеет")
	v.record = keep
	v.queue_free()
	p.queue_free()
	await hooks.frames(1)


# ───────────────────────── материалы ─────────────────────────

## Материалы свежей копии модели (мимо кэша — у кэшированной сцены _dress уже сработал).
func _materials(plain: bool) -> Dictionary:
	ShipModels.rollback_plain_trim = plain
	var file: String = ShipModels.ship(&"troyden", &"cruiser").get("file", "")
	var ps := ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var root := ps.instantiate()
	ShipModels._dress(root)
	ShipModels.rollback_plain_trim = false
	var out: Dictionary[String, StandardMaterial3D] = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
				if m != null:
					out[m.resource_name] = m
		for c in n.get_children():
			stack.append(c)
	root.free()
	return out


func _trim_ok(mats: Dictionary) -> int:
	var good := 0
	for name: String in mats:
		if not name.begins_with("trim_"):
			continue
		var m: StandardMaterial3D = mats[name]
		if m.vertex_color_use_as_albedo and m.ao_enabled and m.ao_texture != null and m.ao_light_affect == 1.0 \
				and m.albedo_texture == ShipModels.TRIM_ALBEDO and m.normal_texture == ShipModels.TRIM_NORMAL:
			good += 1
	return good


func test_hero_cruiser_materials() -> void:
	var mats := _materials(false)
	var trims := 0
	for name: String in mats:
		if name.begins_with("trim_"):
			trims += 1
	ok(trims >= 4, "материалов trim_* у крейсера %d (hull, soft, paint, dark)" % trims)
	eq(_trim_ok(mats), trims, "все trim_*: цвет вершин в цвет, AO гасит прямой свет, общий лист флота")
	for g: String in ["glow_engine_lo", "glow_throat"]:
		var m: StandardMaterial3D = mats.get(g)
		ok(m != null and m.emission_enabled and m.emission.get_luminance() > 0.05, "%s светится" % g)
	var paint: StandardMaterial3D = mats.get("trim_paint")
	ok(paint != null and paint.albedo_color.b > paint.albedo_color.r + 0.2, "цвет клана (baseColorFactor trim_paint) не стёрт: %s" % (paint.albedo_color if paint != null else Color.BLACK))
	var plain := _materials(true)
	ok(_trim_ok(plain) == 0, "откат «trim_* как из импорта»: ни один не годится (%d) — проверка краснеет" % _trim_ok(plain))


# ───────────────────────── бой-лаборатория ─────────────────────────

func _lab(cruiser_clan: StringName = &"troyden") -> BattleView:
	var defs := _get_defs()
	var b := Battle.create(defs, {"attacker": cruiser_clan, "defender": &"plektor", "size": &"small", "seed": 7, "reserve": false}) as Battle
	b.ships.clear()
	var c := b.spawn(Ship.ATTACKER, defs.ship(cruiser_clan, &"cruiser"), Vector2(0, 0))
	c.stance = &"hold"
	c.hp = BIG
	c.max_hp = BIG
	var foe := b.spawn(Ship.DEFENDER, defs.ship(&"plektor", &"corvette"), Vector2(2400, -2400))
	foe.stance = &"hold"
	var v := BattleView.new()
	v.name = "HeroLab"
	tree.root.add_child(v)
	v.setup(defs, b, false)
	v.paused = true
	v.set_process(false)
	await hooks.frames(1)
	return v


func _drop(v: BattleView) -> void:
	var b := v.battle
	v.queue_free()
	await hooks.frames(2)
	b.dispose()


func _step(v: BattleView) -> void:
	v.paused = false
	v.advance(Battle.STEP)
	v.paused = true
	v.draw_state()


## Угол поворота узла вокруг его оси z против исходного (рад, 0…TAU).
static func _angle(n: Node3D, base: Basis) -> float:
	var d := base.inverse() * n.basis
	return fposmod(atan2(d.x.y, d.x.x), TAU)


func _spin_case(real_clock: bool) -> Dictionary:
	ShipVisual.rollback_spin_real_clock = real_clock
	var v := await _lab()
	var s := v.battle.ships[0]
	var vis: ShipVisual = v._vis[s.uid]
	var reactor := vis.part(&"reactor")
	var hull := vis.part(&"hull")
	var base := Basis()
	for d in vis._spin:
		base = d["base"]
	var hull0 := hull.basis
	for i in 45:
		_step(v)
	var t := v.battle.time - Battle.STEP + v.alpha() * Battle.STEP
	var a1 := _angle(reactor, base)
	# пауза: настоящие часы вида идут (покачивание), игровые — нет
	v.paused = true
	v.clock += 5.0
	v.draw_state()
	var a2 := _angle(reactor, base)
	var r := {"spinning": vis.spinning().size(), "t": t, "a1": a1, "a2": a2, "hull_same": hull.basis.is_equal_approx(hull0)}
	ShipVisual.rollback_spin_real_clock = false
	await _drop(v)
	return r


func test_hero_reactor_spins_in_view_only() -> void:
	var r := await _spin_case(false)
	eq(whole(r["spinning"]), 1, "вращается один узел — reactor")
	var want := fposmod(ShipVisual.SPIN_RATE * num(r["t"]), TAU)
	near(num(r["a1"]), want, 1e-3, "реактор повёрнут на 0,6 × игровое время (%.2f с)" % num(r["t"]))
	ok(num(r["a1"]) > 0.3, "за 1,5 с боя реактор заметно повернулся (%.2f рад)" % num(r["a1"]))
	near(num(r["a2"]), num(r["a1"]), 1e-6, "на паузе реактор стоит (часы вида шли 5 с)")
	ok(flag(r["hull_same"]), "корпус не вращается")
	var o := await _spin_case(true)
	ok(absf(num(o["a2"]) - num(o["a1"])) > 0.5, "откат «от настоящих часов»: на паузе реактор вертится (%.2f → %.2f) — проверка краснеет" % [num(o["a1"]), num(o["a2"])])


## Бой с крейсером Тройдена: шагами вида (с отрисовкой и вращением) и без вида — отпечаток один.
func _battle_print(with_view: bool, spoil: bool) -> String:
	var defs := _get_defs()
	var b := Battle.create(defs, {"attacker": &"troyden", "defender": &"plektor", "size": &"small", "seed": 11, "reserve": false}) as Battle
	var has := false
	for s in b.ships:
		if s.side == Ship.ATTACKER and s.def.id == &"cruiser":
			has = true
	if not has:
		b.spawn(Ship.ATTACKER, defs.ship(&"troyden", &"cruiser"), Vector2(0, 300))
	var v: BattleView = null
	if with_view:
		v = BattleView.new()
		tree.root.add_child(v)
		v.setup(defs, b, false)
		v.set_process(false)
	for i in 240:
		if b.over:
			break
		if v != null:
			_step(v)
		else:
			b.step()
		if spoil and i == 120:
			b.ships[0].vel += Vector2(1e-6, 0.0)
	var fp := b.fingerprint()
	if v != null:
		v.queue_free()
		await hooks.frames(2)
	b.dispose()
	return fp


func test_hero_view_keeps_battle_print() -> void:
	var bare := await _battle_print(false, false)
	var seen := await _battle_print(true, false)
	eq(seen, bare, "бой с крейсером Тройдена: с видом (реактор, факелы) и без — один отпечаток")
	var bad := await _battle_print(false, true)
	ok(bad != bare, "контроль: бой, в который вмешались, расходится — сверка видит разницу")


# ───────────────────────── факел реверса ─────────────────────────

## Нарисовать крейсер с тягой (по носу, назад) и состоянием гипера → длина факела реверса, видимость,
## куда он смотрит, длина в мире и сработал ли знак у носа (вспышки в пуле).
func _rev_draw(v: BattleView, fwd: float, rev: float, hyper: float = 0.0) -> Dictionary:
	var s := v.battle.ships[0]
	s.thrust_fwd = fwd
	s.thrust_rev = rev
	s.hyper_left = hyper
	v._plume_k.erase(s.uid)
	v._rev_t.erase(s.uid)
	var flashes := v.bfx.gfx._flash_next
	var rng0 := v._fx_rng.state
	v.draw_state()
	var vis: ShipVisual = v._vis[s.uid]
	var list: Array = v._rev_plume.get(s.uid, [])
	var shown := 0
	var ahead := true
	var world := 0.0
	var fwd_dir := -vis.global_transform.basis.z.normalized()
	for mi: MeshInstance3D in list:
		if mi.visible and mi.scale.y > 0.05:
			shown += 1
			var root := mi.get_parent() as Node3D
			ahead = ahead and (mi.global_position - root.global_position).dot(fwd_dir) > 0.0
			world = maxf(world, mi.global_transform.basis.y.length())
	var main_world := 0.0
	var mains: Array = v._plume.get(s.uid, [])
	for mi: MeshInstance3D in mains:
		if mi.visible and mi.scale.y > 0.05:
			main_world = maxf(main_world, mi.global_transform.basis.y.length())
	var dp: Vector2 = v.drawn_plumes.get(s.uid, Vector2.ZERO)
	return {"len": v.drawn_rev.get(s.uid, 0.0), "shown": shown, "n": list.size(), "ahead": ahead, "world": world,
		"main": dp.x, "main_world": main_world,
		"nose": v.bfx.gfx._flash_next != flashes, "rng": v._fx_rng.state != rng0}


func test_hero_reverse_plume_rules() -> void:
	var v := await _lab()
	for i in 5:
		v.draw_state()                                   # прогрев кончился
	var still := _rev_draw(v, 0.0, 0.0)
	eq(whole(still["n"]), 2, "у крейсера Тройдена два факела реверса (rev_0, rev_1)")
	ok(whole(still["shown"]) == 0 and num(still["len"]) == 0.0, "без тяги назад факела реверса нет")
	var back := _rev_draw(v, 0.0, 1.0)
	eq(whole(back["shown"]), 2, "тяга назад — оба факела реверса горят")
	ok(flag(back["ahead"]), "факел реверса бьёт ВПЕРЁД, к носу")
	var rev0 := dict(dict(ShipModels.ship(&"troyden", &"cruiser").get("nodes")).get("rev_0"))
	var size := num(dict(rev0.get("plume")).get("size"))
	near(num(back["len"]), size * 2.0, 0.01, "длина на полной тяге назад — 2 размера раструба")
	near(num(back["world"]), num(back["len"]), 0.01, "в мире факел той же длины (масштаб модели учтён)")
	ok(not flag(back["nose"]), "знака у носа нет: реверс не показан дважды")
	ok(flag(back["rng"]), "генератор вида расходуется как со знаком (высоты кораблей не сдвигаются)")
	var low := _rev_draw(v, 0.0, BattleView.REV_MIN * 0.5)
	eq(whole(low["shown"]), 0, "малая тяга назад (меньше REV_MIN) — факела нет")
	var fwd := _rev_draw(v, 1.0, 0.0)
	ok(whole(fwd["shown"]) == 0 and num(fwd["main"]) > 0.0, "тяга по носу — маршевый факел, реверса нет")
	near(num(fwd["main_world"]), num(fwd["main"]), 0.01, "маршевый факел в мире той же длины, что в счёте (масштаб модели учтён)")
	var run := _rev_draw(v, 0.0, 1.0, Movement.HYPER_RUN * 0.5)
	eq(whole(run["shown"]), 0, "на разгоне гипера факела реверса нет")
	BattleView.rollback_plume_by_speed = true
	var spd := _rev_draw(v, 0.0, 1.0)
	BattleView.rollback_plume_by_speed = false
	eq(whole(spd["shown"]), 0, "в откате «факел по скорости» факела реверса нет")
	# откат: факел реверса без правил маршевого — горит всегда, знак у носа рисуется
	BattleView.rollback_rev_plume_always = true
	var o := _rev_draw(v, 0.0, 0.0)
	var o2 := _rev_draw(v, 0.0, 1.0)
	BattleView.rollback_rev_plume_always = false
	ok(whole(o["shown"]) == 2 and flag(o2["nose"]), "откат «реверс всегда»: факел без тяги (%d) и знак у носа (%s) — проверка краснеет" % [whole(o["shown"]), str(flag(o2["nose"]))])
	await _drop(v)
	# прогрев: первые кадры факел реверса виден крошечным — его конвейер собирается сразу
	var w := await _lab()
	var s := w.battle.ships[0]
	var first: Array = w._rev_plume.get(s.uid, [])
	var warm_vis := 0
	for mi: MeshInstance3D in first:
		if mi.visible and mi.scale.y < 0.05:
			warm_vis += 1
	eq(warm_vis, 2, "в первые кадры (прогрев) факелы реверса видны крошечными")
	await _drop(w)
	# крейсер Плэктора без rev_* — знак у носа как был
	var p := await _lab(&"plektor")
	for i in 5:
		p.draw_state()
	var pr := _rev_draw(p, 0.0, 1.0)
	ok(whole(pr["n"]) == 0 and flag(pr["nose"]), "у крейсера без раструбов реверса — прежний знак у носа")
	await _drop(p)


# ───────────────────────── нейтральный свет ─────────────────────────

func _env_light(old: bool) -> Array[Color]:
	SpaceEnv.rollback_old_light = old
	var e := SpaceEnv.new()
	tree.root.add_child(e)
	var out: Array[Color] = [e.sun.light_color, e.fill.light_color, e.env.ambient_light_color, e.headlight.light_color]
	SpaceEnv.rollback_old_light = false
	e.queue_free()
	return out


func test_neutral_light_values() -> void:
	var c := _env_light(false)
	var want: Array[Color] = [Color(1.0, 0.95, 0.88), Color(0.6, 0.62, 0.72), Color(0.42, 0.43, 0.48), Color(0.9, 0.92, 1.0)]
	var names: Array[String] = ["ключ от звезды", "встречный", "окружающий", "фара"]
	for i in 4:
		ok(c[i].is_equal_approx(want[i]), "свет: %s %s (утверждён: %s)" % [names[i], c[i], want[i]])
	var o := _env_light(true)
	var same := 0
	for i in 4:
		if o[i].is_equal_approx(want[i]):
			same += 1
	ok(same == 0, "откат «свет GЭ»: ни один цвет не совпал (%d) — проверка краснеет" % same)
	await hooks.frames(1)
