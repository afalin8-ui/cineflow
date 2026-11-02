# Ручная модель крейсера Тройдена и нейтральный свет (CLAUDE.md, разделы 15 и 24). Ярус ui —
# без окна: всё здесь меряется по узлам, материалам и числам, а не по точкам снимка (снимок факела
# реверса — ярус fx, test_fx_effects → test_backing_heavy_no_main_plume). Каждая проверка —
# с откатом, и откат краснит СВОЮ проверку:
# - модель стоит в своём размере (--fit none), узлы на месте, башня-спинал не вращается
#   (откат — запись без `fixed`); масштаб записи (--fit model_len, для следующих моделей) — на той же
#   модели, уменьшенной как поставила бы установка: длина, дуло, факелы;
# - материалы trim_*: цвет вершин, AO на прямом свете, общий лист; свечения glow_engine_lo
#   и glow_throat (откат `ShipModels.rollback_plain_trim`);
# - реактор вращается от ИГРОВОГО времени: на паузе стоит (откат — от настоящих часов), остальные
#   узлы не шевелятся, отпечаток боя с видом и без — один (контроль: испорченный бой расходится);
# - факел реверса у rev_* — только при тяге назад, прячется в откате «по скорости», на разгоне
#   гипера и до прогрева; знак у носа у такого корабля не рисуется, а генератор вида расходуется
#   как со знаком (откат `BattleView.rollback_rev_plume_always`);
# - пламя двигателей по КЛАНУ, а не по стороне: зеркальный бой — один цвет, Тройден × Плэктор и
#   Плэктор × Тройден — по клану (откат `BattleView.rollback_plume_by_side`);
# - нейтральный свет — числами (откат `SpaceEnv.rollback_old_light`);
# - флот Тройдена целиком (с 0.11: корвет, фрегат, РЭБ, носитель, флагман «Ланселот», станция) —
#   своим размером (--fit none, длина в 1% от model_len), узлы и масштаб, реактор вращается у всех,
#   спинал флагмана не вращается (а вторая башня — да); факелы — от узлов engine_*/rev_*, сколько
#   обещает модель, цветом клана, и ни одна линия ядра факела не упирается в корпус (у флагмана
#   задняя пара гондол маршевая, передняя — реверс). У каждой — свой откат.
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
	# размер — тем --fit, каким ставили (раздел 15): крейсер Тройдена стоит КАК ЕСТЬ (none, 129,82 при
	# model_len 112,86 — в ±20%); model_len — уменьшен до длины корабля в бою. Масштаб как механизм
	# проверяет test_hero_model_scale_mechanism
	var model_len := defs.ship(&"troyden", &"cruiser").model_len
	var fit: String = hand.get("fit", "")
	var raw := num(hand.get("raw_len"))
	var k_want := model_len / raw if fit == "model_len" else 1.0
	eq(fit, "none", "крейсер Тройдена поставлен --fit none — в размере, который проверял критик")
	ok(absf(raw - model_len) <= model_len * 0.2, "длина модели %.2f в ±20%% от model_len %.2f" % [raw, model_len])
	var want := raw * k_want
	near(num(rec.get("len")), want, 0.01, "длина в обмере = длина модели × масштаб (--fit %s)" % fit)
	var v := _visual(&"troyden", &"cruiser")
	near(v.model_scale(), k_want, 1e-4, "масштаб вида — по --fit (%s)" % fit)
	# длина того, что на экране: рамка геометрии модели с масштабом вида
	var box := ModelsTest.model_aabb(v)
	var got := maxf(box.size.x, box.size.z)
	ok(absf(got - want) <= want * 0.01, "длина нарисованной модели %.2f при длине в обмере %.2f" % [got, want])
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


## Запись крейсера Тройдена, уменьшенная в k раз так, как её поставил бы `install_model.py --fit
## model_len` (обмер в единицах боя, `scale` — во сколько вид уменьшает модель), — на время проверки
## в общем обмере. Отдаёт прежнюю запись: вернуть её — _put_record.
func _scale_record(k: float) -> Dictionary:
	var keep := ShipModels.ship(&"troyden", &"cruiser")
	var r := keep.duplicate(true)
	for key: String in ["len", "len_z", "width", "height"]:
		if r.has(key):
			r[key] = num(r[key]) * k
	var box: Array = []
	for corner: Variant in arr(r.get("aabb")):
		var c: Array = []
		for x: Variant in arr(corner):
			c.append(num(x) * k)
		box.append(c)
	r["aabb"] = box
	for n: String in dict(r.get("nodes")):
		var nd := dict(dict(r["nodes"])[n])
		if nd.has("pos"):
			var p: Array = []
			for x: Variant in arr(nd["pos"]):
				p.append(num(x) * k)
			nd["pos"] = p
		if nd.has("size"):
			nd["size"] = num(nd["size"]) * k
		if typeof(nd.get("plume")) == TYPE_DICTIONARY and dict(nd["plume"]).has("size"):
			dict(nd["plume"])["size"] = num(dict(nd["plume"])["size"]) * k
	r["scale"] = num(keep.get("scale", 1.0)) * k
	_put_record(r)
	return keep


func _put_record(r: Dictionary, id: StringName = &"cruiser") -> void:
	dict(dict(ShipModels.data().get("ships")).get("troyden"))[id] = r


func test_hero_model_scale_mechanism() -> void:
	const K := 0.8
	var keep := _scale_record(K)
	var rec := ShipModels.ship(&"troyden", &"cruiser")
	var v := _visual(&"troyden", &"cruiser")
	near(v.model_scale(), K, 1e-6, "масштаб записи 0,8 — вид уменьшает модель")
	var box := ModelsTest.model_aabb(v)
	var want := num(rec.get("len"))
	var got := maxf(box.size.x, box.size.z)
	ok(absf(got - want) <= want * 0.01, "масштаб 0,8: длина нарисованной %.2f = длине в обмере %.2f" % [got, want])
	var mz := arr(dict(dict(rec.get("nodes")).get("muzzle_0")).get("pos"))
	var mp := v.to_local(v.part_point(&"muzzle_0"))
	ok(mp.distance_to(Vector3(num(mz[0]), num(mz[1]), num(mz[2]))) < 0.05, "масштаб 0,8: дуло там, где в записи (%s)" % mp)
	# откат «вид масштаб не ставит»: модель в своём размере — длина расходится с записью
	v.model.scale = Vector3.ONE
	var raw := ModelsTest.model_aabb(v)
	ok(absf(maxf(raw.size.x, raw.size.z) - want) > want * 0.1, "откат «без масштаба модели»: длина %.2f при записи %.2f — проверка краснеет" % [maxf(raw.size.x, raw.size.z), want])
	v.queue_free()
	# факелы висят ВНУТРИ уменьшенной модели — длина в мире обязана совпасть со счётом
	var lab := await _lab()
	for i in 5:
		lab.draw_state()
	var back := _rev_draw(lab, 0.0, 1.0)
	var size := num(dict(dict(dict(rec.get("nodes")).get("rev_0")).get("plume")).get("size"))
	near(num(back["len"]), size * 2.0, 0.01, "масштаб 0,8: факел реверса — 2 размера раструба (в единицах боя)")
	near(num(back["world"]), num(back["len"]), 0.01, "масштаб 0,8: факел реверса в мире той же длины, что в счёте")
	var fwd := _rev_draw(lab, 1.0, 0.0)
	near(num(fwd["main_world"]), num(fwd["main"]), 0.01, "масштаб 0,8: маршевый факел в мире той же длины, что в счёте")
	await _drop(lab)
	_put_record(keep)


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


# ───────────────────────── пламя по клану ─────────────────────────

## Бой attacker × defender (без резерва), вид без окна, два кадра → {сторона: [цвета пламени
## её кораблей]} — из материала маршевых факелов и из plume_color (им же красится знак у носа).
func _plume_colors(attacker: StringName, defender: StringName) -> Dictionary:
	var defs := _get_defs()
	var b := Battle.create(defs, {"attacker": attacker, "defender": defender, "size": &"small", "seed": 5, "reserve": false}) as Battle
	var v := BattleView.new()
	tree.root.add_child(v)
	v.setup(defs, b, false)
	v.paused = true
	v.set_process(false)
	for i in 12:
		_step(v)
	# «now» ставится ВСЕМ материалам пламени (по одному на клан), а не двум, как было
	var nows: Array[float] = []
	for pm: ShaderMaterial in v._plume_mats.values():
		nows.append(num(pm.get_shader_parameter("now")))
	var lo := BIG
	var hi := -BIG
	for x in nows:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	ok(BattleView.rollback_plume_by_side or nows.size() == (1 if attacker == defender else 2) and lo > 0.1 and lo == hi, "%s × %s: материалов пламени %d (по клану), у всех игровое время %s" % [attacker, defender, nows.size(), str(nows)])
	var out := {0: [], 1: []}
	for s in b.ships:
		var list: Array = v._plume.get(s.uid, [])
		var c := v.plume_color(s)
		if not list.is_empty():
			var mi: MeshInstance3D = list[0]
			var m := mi.material_override as ShaderMaterial
			var cv: Vector3 = m.get_shader_parameter("color")
			c = Color(cv.x, cv.y, cv.z)
		arr(out[s.side]).append(c)
	v.queue_free()
	await hooks.frames(2)
	b.dispose()
	return out


static func _all(cols: Array, c: Color) -> bool:
	for x: Color in cols:
		if not x.is_equal_approx(c):
			return false
	return not cols.is_empty()


func test_plume_color_by_clan() -> void:
	var p := _get_defs().doctrine.plume
	for clan: StringName in _get_defs().faction_ids:
		ok(p.has(clan), "цвет пламени клана %s — в doctrine.json → view.plume" % clan)
	var tr: Color = p[&"troyden"]
	var pk: Color = p[&"plektor"]
	ok(not tr.is_equal_approx(pk), "пламя Тройдена и Плэктора разного цвета")
	var mir := await _plume_colors(&"troyden", &"troyden")
	ok(_all(arr(mir[0]), tr) and _all(arr(mir[1]), tr), "зеркальный бой Тройден × Тройден: пламя обеих сторон — цвет Тройдена")
	var tp := await _plume_colors(&"troyden", &"plektor")
	ok(_all(arr(tp[0]), tr) and _all(arr(tp[1]), pk), "Тройден × Плэктор: у Тройдена — его цвет, у Плэктора — его")
	var pt := await _plume_colors(&"plektor", &"troyden")
	ok(_all(arr(pt[0]), pk) and _all(arr(pt[1]), tr), "Плэктор × Тройден (Плэктор — свои): пламя по клану, не по стороне")
	# откат «по стороне» (как до 02.11.2026): в зеркальном бою стороны разного цвета, у своего
	# Плэктора — голубое
	BattleView.rollback_plume_by_side = true
	var omir := await _plume_colors(&"troyden", &"troyden")
	var opt := await _plume_colors(&"plektor", &"troyden")
	BattleView.rollback_plume_by_side = false
	ok(not _all(arr(omir[1]), tr) and _all(arr(opt[0]), tr), "откат «пламя по стороне»: в зеркальном бою у чужих не цвет клана, у своего Плэктора — голубое — проверка краснеет")


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


# ───────────────────────── флот Тройдена (с 0.11) ─────────────────────────

const FLEET: Array[StringName] = [&"corvette", &"frigate", &"ecm", &"carrier", &"capital"]
## Сколько маршевых сопел и раструбов реверса у модели (записка автора моделей, круг 2.1): у флагмана
## восемь было в круге 2, стало четыре — задняя пара гондол только маршевая, передняя только реверс.
const FLEET_JETS := {&"corvette": [2, 2], &"frigate": [2, 2], &"ecm": [3, 2], &"cruiser": [3, 2], &"carrier": [2, 2], &"capital": [2, 2]}
## Спинальные орудия (не вращаются): у флагмана turret_0, вторая башня (turret_1) — поворотная.
const FLEET_FIXED := {&"capital": [&"turret_0"]}


func _fleet_def(id: StringName) -> Defs.ShipDef:
	return _get_defs().station if id == &"station" else _get_defs().ship(&"troyden", id)


## Беды записи и модели корабля флота. Пусто — всё как обещано.
func _fleet_problems(id: StringName) -> PackedStringArray:
	var bad := PackedStringArray()
	var rec := ShipModels.ship(&"troyden", id)
	var hand := dict(rec.get("hand", {}))
	if hand.is_empty():
		bad.append("не ручная модель")
		return bad
	var s := _fleet_def(id)
	var fit: String = hand.get("fit", "")
	if fit != "none":
		bad.append("--fit %s, а не none" % fit)
	var raw := num(hand.get("raw_len"))
	if absf(raw - s.model_len) > s.model_len * 0.01:
		bad.append("длина модели %.2f дальше 1%% от model_len %.2f" % [raw, s.model_len])
	var v := ShipVisualScene.instantiate() as ShipVisual
	if not v.setup(&"troyden", id):
		v.free()
		bad.append("модель не встала")
		return bad
	tree.root.add_child(v)
	if absf(v.model_scale() - 1.0) > 1e-6:
		bad.append("масштаб вида %.3f, а не 1" % v.model_scale())
	var box := ModelsTest.model_aabb(v)
	var want := num(rec.get("len"))
	var got := maxf(box.size.x, box.size.z)
	if absf(got - want) > want * 0.01:
		bad.append("длина нарисованной %.2f при записи %.2f" % [got, want])
	for p in s.nodes:
		if not ModelsTest.has_node_named(v.model, p.model):
			bad.append("нет узла %s (%s)" % [p.model, p.name])
	var nodes := dict(rec.get("nodes"))
	for key: String in nodes:
		if v.part(StringName(key)) == null:
			bad.append("узла записи %s нет в модели" % key)
	var sp := v.spinning()
	if sp.size() != 1 or sp[0] != v.part(&"reactor"):
		bad.append("вращается узлов %d, а не один reactor" % sp.size())
	var fixed: Array = FLEET_FIXED.get(id, [])
	for key: String in nodes:
		if key.begins_with("turret_"):
			var turns := v.turret_can_turn(StringName(key))
			if turns == fixed.has(StringName(key)):
				bad.append("%s %s" % [key, "вращался бы (спинал)" if turns else "не вращается"])
	v.queue_free()
	return bad


func test_hero_fleet_records() -> void:
	for id: StringName in FLEET + [&"station"]:
		var bad := _fleet_problems(id)
		ok(bad.is_empty(), "troyden.%s: своим размером %.2f (model_len %.2f), узлы, реактор, башни: %s" % [
			id, num(ShipModels.ship(&"troyden", id).get("len")), _fleet_def(id).model_len, "; ".join(bad)])
	await hooks.frames(1)
	# откаты — каждый на своей записи и краснит СВОЮ строку
	var cases := [
		[&"capital", "fixed", "turret_0 вращался бы"],
		[&"carrier", "spin", "вращается узлов 0"],
		[&"ecm", "node", "узла записи aux_9 нет"],
		[&"frigate", "len", "длина нарисованной"],
		[&"corvette", "fit", "--fit model_len"],
	]
	for c: Array in cases:
		var id: StringName = c[0]
		var what: String = c[1]
		var tail: String = c[2]
		var keep := ShipModels.ship(&"troyden", id)
		var r := keep.duplicate(true)
		match what:
			"fixed":
				dict(dict(r["nodes"])["turret_0"]).erase("fixed")
			"spin":
				dict(dict(r["nodes"])["reactor"]).erase("spin_axis")
			"node":
				dict(r["nodes"])["aux_9"] = {"pos": [0.0, 0.0, 0.0]}
			"len":
				r["len"] = num(r["len"]) * 1.3
			"fit":
				dict(r["hand"])["fit"] = "model_len"
		_put_record(r, id)
		var bad := _fleet_problems(id)
		_put_record(keep, id)
		ok(bad.size() == 1 and bad[0].contains(tail), "откат «%s» у %s краснеет своей строкой: %s" % [what, id, "; ".join(bad)])
	await hooks.frames(1)


func _lab_ship(id: StringName, side: int = Ship.ATTACKER) -> BattleView:
	var defs := _get_defs()
	var att := &"troyden" if side == Ship.ATTACKER else &"plektor"
	var dfn := &"plektor" if side == Ship.ATTACKER else &"troyden"
	var b := Battle.create(defs, {"attacker": att, "defender": dfn, "size": &"small", "seed": 7, "reserve": false}) as Battle
	b.ships.clear()
	var c := b.spawn(side, defs.ship(&"troyden", id), Vector2(0, 0))
	c.stance = &"hold"
	c.hp = BIG
	c.max_hp = BIG
	var foe := b.spawn(1 - side, defs.ship(&"plektor", &"corvette"), Vector2(2400, -2400))
	foe.stance = &"hold"
	var v := BattleView.new()
	v.name = "FleetLab"
	tree.root.add_child(v)
	v.setup(defs, b, false)
	v.paused = true
	v.set_process(false)
	await hooks.frames(1)
	for i in 5:
		v.draw_state()                                   # прогрев кончился
	return v


## Треугольники всего нарисованного у модели, кроме самих факелов, — в мире.
static func _hull_tris(v: BattleView, vis: ShipVisual) -> PackedVector3Array:
	var out := PackedVector3Array()
	var stack: Array[Node] = [vis.model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null and mi.mesh != v._plume_mesh:
			out.append_array(mi.global_transform * mi.mesh.get_faces())
		for ch in n.get_children():
			stack.append(ch)
	return out


## Сколько линий ЯДРА факела упирается в корпус: ось и четыре линии на полширины видимого языка
## (обе плоскости), от 5% длины (у самого сопла ось касается раструба) до кончика с дрожью
## (×1,11 — plume.gdshader). Ширина языка сходит к кончику так же, как в шейдере.
static func _plume_hits(mi: MeshInstance3D, tris: PackedVector3Array) -> int:
	var xf := mi.global_transform
	var lines: Array[PackedVector3Array] = []
	for off: Vector3 in [Vector3.ZERO, Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(0, 0, -0.5)]:
		var pts := PackedVector3Array()
		for i in 9:
			var t := 0.05 + (1.11 - 0.05) * float(i) / 8.0
			var hw := 2.0 * (0.5 - 0.40 * pow(minf(t, 1.0), 0.6))
			pts.append(xf * Vector3(off.x * hw, -0.5 + t, off.z * hw))
		lines.append(pts)
	var box := AABB(lines[0][0], Vector3.ZERO)
	for pts in lines:
		for p in pts:
			box = box.expand(p)
	box = box.grow(0.5)
	var near_tris := PackedVector3Array()
	for i in range(0, tris.size(), 3):
		var tb := AABB(tris[i], Vector3.ZERO).expand(tris[i + 1]).expand(tris[i + 2])
		if tb.intersects(box):
			near_tris.append(tris[i])
			near_tris.append(tris[i + 1])
			near_tris.append(tris[i + 2])
	var hits := 0
	for pts in lines:
		var hit := false
		for j in pts.size() - 1:
			for i in range(0, near_tris.size(), 3):
				if Geometry3D.segment_intersects_triangle(pts[j], pts[j + 1], near_tris[i], near_tris[i + 1], near_tris[i + 2]) != null:
					hit = true
					break
			if hit:
				break
		if hit:
			hits += 1
	return hits


## Видимые факелы корабля лаборатории: маршевые и реверса, у каждого — имя узла-родителя.
static func _shown(list: Array) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in list:
		if mi.visible and mi.scale.y > 0.05:
			out.append(mi)
	return out


func test_hero_fleet_plumes() -> void:
	var tr: Color = _get_defs().doctrine.plume[&"troyden"]
	for id: StringName in FLEET + [&"cruiser"]:
		var v := await _lab_ship(id)
		var s := v.battle.ships[0]
		var vis: ShipVisual = v._vis[s.uid]
		var jets: Array = FLEET_JETS[id]
		var fwd := _rev_draw(v, 1.0, 0.0)
		var mains := _shown(arr(v._plume.get(s.uid, [])))
		var revs_off := _shown(arr(v._rev_plume.get(s.uid, [])))
		ok(mains.size() == whole(jets[0]) and revs_off.is_empty(), "%s: тяга по носу — маршевых факелов %d (ждали %d), реверса %d" % [id, mains.size(), whole(jets[0]), revs_off.size()])
		var tris := _hull_tris(v, vis)
		var hit_m := 0
		var from_nodes := true
		var col_ok := true
		for mi in mains:
			hit_m += _plume_hits(mi, tris)
			from_nodes = from_nodes and String(mi.get_parent().name).begins_with("engine_")
			var cv: Vector3 = (mi.material_override as ShaderMaterial).get_shader_parameter("color")
			col_ok = col_ok and Color(cv.x, cv.y, cv.z).is_equal_approx(tr)
		eq(hit_m, 0, "%s: маршевые факелы (%.1f ед.) в корпус не упираются — линий ядра в корпусе" % [id, num(fwd["main"])])
		var back := _rev_draw(v, 0.0, 1.0)
		var revs := _shown(arr(v._rev_plume.get(s.uid, [])))
		ok(revs.size() == whole(jets[1]) and flag(back["ahead"]), "%s: тяга назад — факелов реверса %d (ждали %d), вперёд к носу" % [id, revs.size(), whole(jets[1])])
		var hit_r := 0
		for mi in revs:
			hit_r += _plume_hits(mi, tris)
			from_nodes = from_nodes and String(mi.get_parent().name).begins_with("rev_")
			var cv: Vector3 = (mi.material_override as ShaderMaterial).get_shader_parameter("color")
			col_ok = col_ok and Color(cv.x, cv.y, cv.z).is_equal_approx(tr)
		eq(hit_r, 0, "%s: факелы реверса (%.1f ед.) в корпус не упираются — линий ядра в корпусе" % [id, num(back["len"])])
		note("%s: маршевых %d по %.1f ед., реверса %d по %.1f ед., треугольников корпуса %d, линий ядра в корпусе %d и %d" % [
			id, mains.size(), num(fwd["main"]), revs.size(), num(back["len"]), tris.size() / 3, hit_m, hit_r])
		ok(from_nodes, "%s: маршевые висят на узлах engine_*, реверс — на rev_*" % id)
		ok(col_ok, "%s: пламя цвета клана Тройден %s" % [id, tr])
		if id == &"capital":
			# тандем «Ланселота»: передняя пара гондол тормозит, задняя гонит — сопла реверса ближе
			# к носу (−z), чем любое маршевое
			var rear := _rear_front(vis.record)
			ok(rear, "флагман: маршевые сопла — задняя пара гондол, раструбы реверса — передняя")
			var swapped := vis.record.duplicate(true)
			var nd := dict(swapped["nodes"])
			var e0: Variant = nd["engine_0"]
			nd["engine_0"] = nd["rev_0"]
			nd["rev_0"] = e0
			ok(not _rear_front(swapped), "откат «пары гондол перепутаны» — проверка краснеет")
			# откат: факелы реверса развёрнуты назад, как маршевые (так светила бы передняя пара,
			# будь у неё маршевые сопла, как в круге 2) — ядро уходит в свою же гондолу
			for mi in revs:
				mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
				mi.position = Vector3(0.0, 0.0, mi.scale.y * 0.5)
			var hit_o := 0
			for mi in revs:
				hit_o += _plume_hits(mi, tris)
			note("флагман, откат «реверс бьёт назад»: линий ядра в корпусе %d из %d" % [hit_o, revs.size() * 5])
			ok(hit_o > 0, "откат «реверс бьёт назад»: линий ядра в корпусе %d — проверка краснеет" % hit_o)
		await _drop(v)
	# откаты числа и цвета: `plume` строкой (как в extras) — реверса нет; пламя по стороне —
	# Тройден на стороне защитника горит чужим цветом
	var keep := ShipModels.ship(&"troyden", &"frigate")
	var r := keep.duplicate(true)
	for key: String in ["rev_0", "rev_1"]:
		var nd := dict(dict(r["nodes"])[key])
		nd["plume"] = JSON.stringify(nd["plume"])
	_put_record(r, &"frigate")
	var w := await _lab_ship(&"frigate")
	_rev_draw(w, 0.0, 1.0)
	var lost := _shown(arr(w._rev_plume.get(w.battle.ships[0].uid, [])))
	_put_record(keep, &"frigate")
	ok(lost.size() != whole(FLEET_JETS[&"frigate"][1]), "откат «plume строкой»: факелов реверса %d — проверка краснеет" % lost.size())
	await _drop(w)
	BattleView.rollback_plume_by_side = true
	var d := await _lab_ship(&"carrier", Ship.DEFENDER)
	_rev_draw(d, 1.0, 0.0)
	var dm := _shown(arr(d._plume.get(d.battle.ships[0].uid, [])))
	BattleView.rollback_plume_by_side = false
	var cv0: Vector3 = (dm[0].material_override as ShaderMaterial).get_shader_parameter("color") if not dm.is_empty() else Vector3.ZERO
	ok(not Color(cv0.x, cv0.y, cv0.z).is_equal_approx(tr), "откат «пламя по стороне»: носитель Тройдена у защитника — не цвет клана — проверка краснеет")
	await _drop(d)


## Маршевые сопла дальше от носа (больше z), чем все раструбы реверса.
static func _rear_front(rec: Dictionary) -> bool:
	var nodes: Dictionary = rec.get("nodes", {})
	var eng_min := 1.0e9
	var rev_max := -1.0e9
	for key: String in nodes:
		var nd: Dictionary = nodes[key]
		var pos: Array = nd.get("pos", [0.0, 0.0, 0.0])
		var z: float = pos[2]
		if key.begins_with("engine_"):
			eng_min = minf(eng_min, z)
		elif key.begins_with("rev_"):
			rev_max = maxf(rev_max, z)
	return eng_min > rev_max
