# «Стол» без окна (ярус ui; план G0, п. 6; раздел 0, критерий 3): худший бой, какой
# может собрать игрок, собран целиком, а пропавшая модель — громкий отказ.
# - на столе ровно 83 корабля и 240 машин: 34 + 14 резерва у атакующего, 34 и станция
#   у защитника, состав по id — как в данных (откат — данные без резерва: «Стол»
#   не собирается молча меньшим, 69 вместо 83);
# - строка «На столе: 83 корабля, 240 машин» в итоге замера сходится со счётом;
# - пропал файл обмера моделей, одна .glb или обмер битый — беда словами на экране
#   и в stderr, «Стол» и замер не начинаются (замечание к G0b: раньше пустое место
#   молча, а итог замера всё равно писал «83 корабля»);
# - числа доктрины — из doctrine.json: носители по carrier_lat, высоты в
#   ±view.height_spread, маршрут замера — расстояния camera.*; правка числа
#   (--set) меняет «Стол» (откат — число вписано в код).
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Showcase := preload("res://tools/showcase.gd")
const ShipModels := preload("res://view/ship_models.gd")
const MainScene := preload("res://main.tscn")
const MainScript := preload("res://main.gd")

const FACTION := &"plektor"


static func _counts(entries: Array[Defs.FleetEntry], into: Dictionary) -> void:
	for e in entries:
		var c: int = into.get(String(e.id), 0)
		into[String(e.id)] = c + e.count


## Словарь в строку с отсортированными ключами — сравнивать составы.
static func _flat(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k: Variant in keys:
		parts.append("%s×%d" % [k, whole(d[k])])
	return " ".join(parts)


func _build(defs: Defs) -> Showcase:
	var sc := Showcase.new()
	sc.name = "Showcase"
	tree.root.add_child(sc)
	sc.setup(defs)
	await hooks.frames(1)
	return sc


func test_table_is_the_worst_battle() -> void:
	var defs := Defs.load_default({}) as Defs
	var sc := await _build(defs)
	ok(sc.problems.is_empty(), "«Стол» собрался без бед: %s" % "; ".join(sc.problems))
	eq(sc.ship_count(), 83, "кораблей на «Столе» — 83 (34 + 14 резерва + 34 + станция)")
	eq(sc.craft_count(), 240, "машин над серединой — 240")
	# состав по сторонам — как в данных быстрого боя
	var want_own := {}
	var want_foe := {}
	_counts(defs.quick.fleet(&"big", FACTION), want_own)
	var l: Defs.Lineup = defs.quick.reserve.get(FACTION)
	if ok(l != null, "в данных есть резерв Плэктора"):
		_counts(l.entries, want_own)
	_counts(defs.quick.fleet(&"big", FACTION), want_foe)
	want_foe["station"] = 1
	var own := {}
	var foe := {}
	var stations := 0
	for i in sc.ships.size():
		var into := own if sc.side_of[i] > 0 else foe
		var id := String(sc.ships[i].ship_id)
		var c: int = into.get(id, 0)
		into[id] = c + 1
		if id == "station":
			stations += 1
	eq(_flat(own), _flat(want_own), "атакующий: флот «Генерального» и резерв")
	eq(_flat(foe), _flat(want_foe), "защитник: флот «Генерального» и станция")
	var n_own := 0
	for k: Variant in own:
		n_own += whole(own[k])
	eq(n_own, 48, "у атакующего 34 + 14 резерва")
	eq(sc.ship_count() - n_own, 35, "у защитника 34 и станция")
	eq(stations, 1, "станция одна")
	# числа доктрины: высота-картинка в ±height_spread, носители по carrier_lat вбок
	var d := defs.doctrine
	var hmax := 0.0
	var carr_x := PackedFloat64Array()
	for i in sc.ships.size():
		hmax = maxf(hmax, absf(sc.base_pos[i].y))
		if sc.ships[i].ship_id == &"carrier" and sc.side_of[i] > 0:
			carr_x.append(sc.base_pos[i].x)
	ok(hmax <= d.view_height_spread and hmax > d.view_height_spread * 0.5, "высоты кораблей в ±%.0f (наибольшая %.1f)" % [d.view_height_spread, hmax])
	carr_x.sort()
	if ok(carr_x.size() >= 2, "у атакующего не меньше двух носителей (%d)" % carr_x.size()):
		near(carr_x[1] - carr_x[0], d.deploy_carrier_lat, 1e-3, "носители по carrier_lat вбок")
	var dists := sc.path_dists()
	ok(d.camera_dist_work in dists and d.camera_dist_max in dists and dists[0] == d.camera_dist_start,
		"маршрут замера — расстояния доктрины: старт, рабочий вид и предел (%s)" % [dists])
	sc.queue_free()
	await hooks.frames(1)
	# откат: данные без резерва — «Стол» не собирается молча меньшим (было бы 69)
	var bare := Defs.load_default({}) as Defs
	var bl: Defs.Lineup = bare.quick.reserve.get(FACTION)
	var bare_n := 0
	for e in bare.quick.fleet(&"big", FACTION):
		bare_n += e.count * 2
	bare.quick.reserve.erase(FACTION)
	var sc2 := await _build(bare)
	ok(not sc2.problems.is_empty() and "\n".join(sc2.problems).contains("резерв"), "откат «без резерва»: беда названа (%s)" % "; ".join(sc2.problems))
	ok(sc2.ship_count() != 83, "откат «без резерва» краснеет в счёте (%d кораблей, без резерва данные дают %d)" % [sc2.ship_count(), bare_n + 1])
	ok(bl != null and bare_n + 1 == 69, "без резерва вышло бы 69 кораблей (%d)" % [bare_n + 1])
	sc2.queue_free()
	await hooks.frames(1)


func test_bench_line_matches_the_table() -> void:
	MainScript.boot = &"table"             # с G1 по умолчанию — «Полигон»; «Стол» — F6 или F5
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	MainScript.boot = &""
	await hooks.frames(2)
	var bench: Node = main.get("bench")
	if ok(bench != null, "замер кадров заведён"):
		var line: String = bench.get("extra_line")
		ok(line.begins_with("На столе: 83 корабля, 240 машин"), "строка итога сходится со счётом: «%s»" % line)
	main.queue_free()
	await hooks.frames(2)


## Главная сцена с испорченным обмером моделей: беда на экране, ни «Стола», ни
## «Полигона», ни замера нет. boot — с чего начинает главная сцена.
func _main_with(models_file: String, boot: StringName = &"table") -> Dictionary:
	ShipModels.use_file(models_file)
	MainScript.boot = boot
	var main := MainScene.instantiate()
	tree.root.add_child(main)
	MainScript.boot = &""
	await hooks.frames(2)
	var out := {
		"view": main.get("view") != null or main.get("polygon") != null,
		"bench": main.get("bench") != null,
		"text": str(main.get("error_text")),
		"shown": main.find_child("Errors", false, false) != null,
	}
	main.queue_free()
	await hooks.frames(2)
	ShipModels.use_file("")
	return out


func _write(path: String, text: String) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


func test_missing_models_are_loud() -> void:
	# 1) пропал сам файл обмера
	var r1 := await _main_with("res://data/нет_такого_обмера.json")
	ok(not flag(r1["view"]) and not flag(r1["bench"]), "нет файла обмера: «Стола» и замера нет")
	var t1: String = r1["text"]
	ok(flag(r1["shown"]) and t1.contains("модели кораблей с ошибкой") and t1.contains("нет файла"), "нет файла обмера: беда на экране — «%s»" % t1.replace("\n", " / "))
	# 2) пропала одна .glb: крейсер Плэктора ссылается на файл, которого нет
	var j := JSON.new()
	ok(j.parse(FileAccess.get_file_as_string(ShipModels.DATA_PATH)) == OK, "обмер читается")
	var data := dict(j.data)
	var ships := dict(data["ships"])
	var plek := dict(ships["plektor"])
	var cr := dict(plek["cruiser"])
	cr["file"] = "res://view/ships/plektor_cruiser_пропал.glb"
	var broken := _write(tmp("ship_models_broken.json"), JSON.stringify(data))
	var r2 := await _main_with(broken)
	var t2: String = r2["text"]
	ok(not flag(r2["view"]) and not flag(r2["bench"]), "пропала одна .glb: «Стола» и замера нет")
	ok(t2.contains("plektor.cruiser") and t2.contains("plektor_cruiser_пропал.glb"), "пропала одна .glb: беда называет корабль и файл — «%s»" % t2.replace("\n", " / "))
	# то же у «Полигона» (с G1 он открывается по умолчанию): пустого места молча нет
	var r2p := await _main_with(broken, &"")
	var t2p: String = r2p["text"]
	ok(not flag(r2p["view"]) and not flag(r2p["bench"]) and t2p.contains("plektor.cruiser"), "«Полигон» с пропавшей .glb не собирается: «%s»" % t2p.replace("\n", " / "))
	# та же беда — у самого «Стола», ДО расстановки: пустого места молча нет
	ShipModels.use_file(broken)
	var defs := Defs.load_default({}) as Defs
	var sc := await _build(defs)
	ok(sc.ship_count() == 0 and "\n".join(sc.problems).contains("plektor.cruiser"), "«Стол» с пропавшей .glb не собирается меньшим (кораблей на нём: %d; %s)" % [sc.ship_count(), "; ".join(sc.problems)])
	sc.queue_free()
	await hooks.frames(1)
	ShipModels.use_file("")
	# 3) обмер битый — беда с номером строки
	var bad := _write(tmp("ship_models_bad.json"), "{\n  \"ships\": {\n    \"plektor\": [\n")
	var r3 := await _main_with(bad)
	var t3: String = r3["text"]
	ok(not flag(r3["view"]) and t3.contains("строка"), "битый обмер: беда с номером строки — «%s»" % t3.replace("\n", " / "))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(broken))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad))
	# и обычный обмер после проверок снова целый
	ok(ShipModels.problems(FACTION, [&"cruiser", &"station"], [&"bomber"]).is_empty(), "обычный обмер вернулся")


## Правка числа доктрины меняет «Стол»: числа берутся из doctrine.json, а не из кода
## (замечание к G0b: высота ±40, покачивание ±3, носители по 260 и расстояния пути
## были вписаны в showcase.gd литералами).
func test_table_follows_doctrine() -> void:
	var defs := Defs.load_default({"deploy.carrier_lat": 333.0, "view.height_spread": 12.0, "view.bob": 0.0,
		"camera.dist_work": 2222.0, "camera.dist_start": 3777.0}) as Defs
	if not ok(defs.ok, "правки приняты: %s" % "; ".join(defs.errors)):
		return
	var sc := await _build(defs)
	var hmax := 0.0
	var carr_x := PackedFloat64Array()
	for i in sc.ships.size():
		hmax = maxf(hmax, absf(sc.base_pos[i].y))
		if sc.ships[i].ship_id == &"carrier" and sc.side_of[i] > 0:
			carr_x.append(sc.base_pos[i].x)
	carr_x.sort()
	ok(carr_x.size() >= 2 and absf(carr_x[1] - carr_x[0] - 333.0) < 1e-3, "носители по 333 вбок после правки (%s)" % [carr_x])
	ok(hmax <= 12.0, "высоты в ±12 после правки (наибольшая %.1f)" % hmax)
	var dists := sc.path_dists()
	ok(2222.0 in dists and dists[0] == 3777.0, "маршрут замера — с правленными расстояниями (%s)" % [dists])
	# покачивание 0 — корабль стоит на своей высоте
	await hooks.frames(3)
	var drift := 0.0
	for i in sc.ships.size():
		drift = maxf(drift, absf(sc.ships[i].position.y - sc.base_pos[i].y))
	ok(drift < 1e-4, "покачивание 0 после правки — корабли не качаются (%.5f)" % drift)
	sc.queue_free()
	await hooks.frames(1)
