# Ярус tempo (run_tests.sh: sim → tempo → ui; отдельно от sim, чтобы тот держался под 900 с).
# Темп боя (пакет GТ): старт дальше и сближение видно; тяжёлые медленнее и спокойнее —
# множители хода ОДНОЙ дверью (Ship.thrust/turn/max_speed, Defs.move_k); всё влезает в поле;
# М16 «суета» ниже, чем было. Каждая проверка — с откатом (правкой чисел доктрины: все правки
# GТ — числа doctrine.json, и прежние числа — OLD_TEMPO в tests/case.gd — дают бой 0.7.1 до бита).
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Formation := preload("res://sim/formation.gd")
const Polygon := preload("res://tools/polygon.gd")
const BenchCore := preload("res://tools/bench_core.gd")
const QuickMenu := preload("res://ui/quick_menu.gd")
const MainScript := preload("res://main.gd")
const Flight := preload("res://tests/test_sim_flight.gd")

## Отпечатки 0.6–0.7.1 (godot/CLAUDE.md, раздел 13): показательный бой «Полигона» и 60 с «ИИ против
## ИИ» по выбору меню — те, что `--selftest` печатал до пакета GТ.
const FP_DEMO_071 := "33376cfd2837a559"
const FP_AI_071 := "d8a38543cb272206"
## Окно первого выстрела главного калибра в быстром бою по умолчанию (план GТ, п. 1): 25–40 с на 1×.
const FIRST_GUN_MIN := 25.0
const FIRST_GUN_MAX := 40.0
const HEAVY_IDS: Array[StringName] = [&"cruiser", &"carrier", &"capital", &"sinho"]
## Сколько боёв «Стычки» на один замер М16 (зёрна с 1000).
const M16_SEEDS := 4

var defs: Defs


func _defs() -> Defs:
	if defs == null:
		defs = Defs.load_default() as Defs
	return defs


# ───────────────────────── первый выстрел: старт дальше (09, 5.5) ─────────────────────────

## Быстрый бой как «В бой» из меню (Тройден × Плэктор, «Сражение», «Офицер», резерв, орудие
## планеты), игрок приказов не даёт. → время первого выстрела главного калибра по кораблю
## (М11, `metrics.first_gun`), −1 — не было за 90 с.
func _first_gun(d: Defs, seed_n: int, watch: bool = false) -> float:
	var b := Battle.create(d, Polygon.quick_setup(QuickMenu.default_cfg(d, watch), seed_n), "capella-проверка") as Battle
	var t := -1.0
	while b.time < 90.0 and not b.over:
		b.step()
		if b.metrics.first_gun > 0.0:
			t = b.metrics.first_gun
			break
	b.dispose()
	return t


func test_first_main_gun_window() -> void:
	var seeds: Array[int] = [Polygon.SEED, 1, 2, 3, 4, 5]
	var got := PackedStringArray()
	var bad := 0
	for sn in seeds:
		var t := _first_gun(_defs(), sn)
		got.append("%.1f" % t)
		if t < FIRST_GUN_MIN or t > FIRST_GUN_MAX:
			bad += 1
	note("быстрый бой по умолчанию, первый главный калибр по зёрнам %s: %s с" % [str(seeds), ", ".join(got)])
	ok(bad == 0, "быстрый бой по умолчанию: первый выстрел главного калибра на %d–%d с, на 1× (%s)" % [roundi(FIRST_GUN_MIN), roundi(FIRST_GUN_MAX), ", ".join(got)])
	var w := PackedStringArray()
	for sn: int in [Polygon.SEED, 1, 2]:
		w.append("%.1f" % _first_gun(_defs(), sn, true))
	note("«ИИ против ИИ» по умолчанию: первый главный калибр %s с (оба ИИ идут навстречу — раньше)" % ", ".join(w))
	# откат: прежняя расстановка ±650 при новом ходе тяжёлых — выстрел раньше окна
	var old := Defs.load_default({"deploy.heavy_z": 650.0}) as Defs
	var og := PackedStringArray()
	var early := 0
	for sn in seeds:
		var t := _first_gun(old, sn)
		og.append("%.1f" % t)
		if t < FIRST_GUN_MIN:
			early += 1
	note("откат «старт ±650»: %s с" % ", ".join(og))
	ok(early == seeds.size(), "откат «старт ±650, как в 0.7.1»: первый выстрел раньше %d с во всех боях (%s) — проверка краснеет" % [roundi(FIRST_GUN_MIN), ", ".join(og)])
	var o2 := _first_gun(Defs.load_default(OLD_TEMPO) as Defs, Polygon.SEED)
	note("прежний темп целиком (0.7.1): первый главный калибр на %.1f с" % o2)


# ───────────────────────── тяжёлые медленнее — одной дверью (09, 2.11; 9.5 п. 4) ─────────────────────────

func _lab(d: Defs) -> Battle:
	var b := Battle.create(d, {"attacker": &"troyden", "defender": &"plektor", "size": &"small", "seed": 7, "reserve": false}) as Battle
	b.ships.clear()
	return b


static func _clan(id: StringName) -> StringName:
	return &"plektor" if id == &"sinho" else &"troyden"


## Множители хода — у корабля, через Defs.move_k (одна функция на все места создания корабля):
## предел хода, тяга и разворот тяжёлых — × heavy.*_k, у лёгких и станции — как в данных.
func test_heavy_multipliers_one_door() -> void:
	var d := _defs()
	var dc := d.doctrine
	var b := _lab(d)
	var bad := PackedStringArray()
	for id: StringName in Flight.CLASSES:
		var s := b.spawn(Ship.ATTACKER, d.ship(_clan(id), id), Vector2.ZERO)
		var heavy := s.def.cls != &"escort"
		var ks := dc.heavy_speed_k if heavy else 1.0
		var kt := dc.heavy_thrust_k if heavy else 1.0
		var kr := dc.heavy_turn_k if heavy else 1.0
		if absf(s.max_speed() - s.def.max_speed * ks) > 1e-9 or absf(s.thrust() - s.def.thrust * kt) > 1e-9 or absf(s.turn() - s.def.turn * kr) > 1e-9:
			bad.append("%s: ход %.2f, тяга %.3f, разворот %.3f" % [id, s.max_speed(), s.thrust(), s.turn()])
	var st := b.spawn(Ship.DEFENDER, d.ship(&"plektor", &"station"), Vector2(0, -2000)) if d.ship(&"plektor", &"station") != null else null
	if st != null and (absf(st.turn() - st.def.turn) > 1e-9 or absf(st.thrust() - st.def.thrust) > 1e-9):
		bad.append("станция: тяга %.3f, разворот %.3f — а она не ходит вовсе" % [st.thrust(), st.turn()])
	b.dispose()
	ok(bad.is_empty(), "предел хода, тяга и разворот: тяжёлые × %.1f / %.1f / %.1f, лёгкие и станция — как в данных (%s)" % [dc.heavy_speed_k, dc.heavy_thrust_k, dc.heavy_turn_k, "; ".join(bad)])
	ok(dc.heavy_speed_k < 1.0 and dc.heavy_thrust_k < 1.0 and dc.heavy_turn_k < 1.0, "тяжёлые медленнее: множители хода %.2f, тяги %.2f, разворота %.2f" % [dc.heavy_speed_k, dc.heavy_thrust_k, dc.heavy_turn_k])


## Тормозной путь — от той же тяги, что разгон (ловушка 4 части 09, 9.5): путь v²/(2·rev·тяга) при
## ходе × k и тяге × k — ровно × k (0,6) от замера JS. У лёгких — как в JS. Откат «множитель только на
## ход» (тяга без множителя): путь × k² / 1 = × 0,36 — тяжёлый тормозил бы втрое резче, чем
## разгоняется, то есть дверь хода и дверь тяги разошлись бы.
func _brake(d: Defs, id: StringName) -> float:
	var b := _lab(d)
	var s := b.spawn(Ship.ATTACKER, d.ship(_clan(id), id), Vector2.ZERO)
	s.vel = s.dir * s.max_speed()
	var p0 := s.pos
	b.queue({"op": &"stance", "ids": [s.uid], "stance": &"hold"})
	for i in 4000:
		b.step()
		if s.vel.length() < 0.5:
			break
	var path := s.pos.distance_to(p0)
	b.dispose()
	return path


func test_brake_path_same_door() -> void:
	var d := _defs()
	var k := d.doctrine.heavy_speed_k * d.doctrine.heavy_speed_k / d.doctrine.heavy_thrust_k
	var say := PackedStringArray()
	var bad := 0
	for id: StringName in Flight.CLASSES:
		var ref: float = Flight.BRAKE_REF[id]
		var heavy := d.ship(_clan(id), id).cls != &"escort"
		var want := ref * k if heavy else ref
		var got := _brake(d, id)
		say.append("%s %.1f (ждали %.1f)" % [id, got, want])
		if absf(got - want) > want * 0.02:
			bad += 1
	note("тормозной путь с полного хода: %s" % ", ".join(say))
	ok(bad == 0, "тормозной путь: тяжёлые — × %.2f от замера JS, лёгкие — как в JS (±2%%): %s" % [k, ", ".join(say)])
	var o := Defs.load_default({"heavy.thrust_k": 1.0}) as Defs
	var oc := _brake(o, &"cruiser")
	var ref_c: float = Flight.BRAKE_REF[&"cruiser"]
	note("откат «множитель только на ход»: крейсер тормозит за %.1f (× %.2f от JS)" % [oc, oc / ref_c])
	ok(absf(oc - ref_c * k) > ref_c * k * 0.02, "откат «множитель только на ход, тяга прежняя»: тормозной путь крейсера %.1f вместо %.1f — проверка краснеет" % [oc, ref_c * k])


# ───────────────────────── прежний темп — тот же бой (все правки GТ — числа) ─────────────────────────

func _fps(d: Defs) -> PackedStringArray:
	var rec := Polygon.make_record(d, "capella-проверка")
	var ab := Battle.create(d, Polygon.quick_setup(QuickMenu.default_cfg(d, true), Polygon.SEED), "capella-проверка") as Battle
	for i in MainScript.AI_SELFTEST_STEPS:
		ab.step()
	var out := PackedStringArray([str(rec["fp"]), ab.fingerprint()])
	ab.dispose()
	return out


## С прежними числами (OLD_TEMPO) показательный бой и «ИИ против ИИ» дают ровно отпечатки 0.7.1: всё,
## что GТ поменял в бою, — числа doctrine.json (кроме замера М16, который в отпечаток не входит).
## Откат — прежние числа без одного (heavy.thrust_k оставлен новым): отпечатки другие.
func test_old_tempo_same_battle() -> void:
	var f := _fps(Defs.load_default(OLD_TEMPO) as Defs)
	note("прежний темп: показательный бой %s, «ИИ против ИИ» %s (0.7.1: %s, %s)" % [f[0], f[1], FP_DEMO_071, FP_AI_071])
	ok(f[0] == FP_DEMO_071 and f[1] == FP_AI_071, "прежние числа доктрины — бой 0.7.1 до бита: показательный %s, «ИИ» %s" % [f[0], f[1]])
	var now := _fps(_defs())
	note("новый темп: показательный бой %s, «ИИ против ИИ» %s" % [now[0], now[1]])
	ok(now[0] != FP_DEMO_071 and now[1] != FP_AI_071, "новый темп — другой бой (отпечатки %s, %s)" % [now[0], now[1]])
	var part := OLD_TEMPO.duplicate()
	part.erase("heavy.thrust_k")
	var o := _fps(Defs.load_default(part) as Defs)
	ok(o[0] != FP_DEMO_071 and o[1] != FP_AI_071, "откат «прежние числа без heavy.thrust_k»: отпечатки %s, %s — проверка краснеет" % [o[0], o[1]])


# ───────────────────────── всё влезает в поле (09, 5.5) ─────────────────────────

## Расстановка старта всех масштабов быстрого боя и всех пар кланов (с резервом, носители и станция
## на своих местах): каждый корабль не ближе retreat.edge к краю поля, линии тяжёлых — на 2 × heavy_z,
## носители позади своей линии, станция позади линии защитника. Подкрепление, вызванное на первом
## шаге, выходит из-за своей линии и внутри поля, а не у края. → беды словами.
func _fit_problems(d: Defs) -> Dictionary:
	var out := PackedStringArray()
	var lim := d.consts.field_half - d.doctrine.retreat_edge
	var worst := 0.0
	var arrivals := 0
	var cases := 0
	for size: StringName in d.quick.size_ids:
		for att: StringName in d.faction_ids:
			for dfn: StringName in d.faction_ids:
				var b := Battle.create(d, Polygon.quick_setup({"attacker": str(att), "defender": str(dfn), "size": str(size)}, 7), "capella-проверка") as Battle
				cases += 1
				var line: Array[Vector2] = [Formation.line_of(b.ships, 0).center, Formation.line_of(b.ships, 1).center]
				for s in b.ships:
					worst = maxf(worst, maxf(absf(s.pos.x), absf(s.pos.y)))
					if absf(s.pos.x) > lim or absf(s.pos.y) > lim:
						out.append("%s %s×%s: %s %s в %s — за краем %.0f" % [size, att, dfn, s.side, s.def.id, str(s.pos), lim])
					var sz := b.sides[s.side].sign_z
					if s.station and s.pos.y * sz <= line[s.side].y * sz:
						out.append("%s %s×%s: станция не позади своей линии" % [size, att, dfn])
					if s.hangar != null and not s.station and s.pos.y * sz <= line[s.side].y * sz:
						out.append("%s %s×%s: носитель %s не позади своей линии" % [size, att, dfn, s.name])
				# центр тяжёлых — на линии старта или чуть позади (у «Генерального» вторая шеренга тяжёлых
				# стоит на line.rank2_back за первой)
				var gap := absf(line[0].y - line[1].y)
				var want := 2.0 * d.doctrine.deploy_heavy_z
				if gap < want - 1.0 or gap > want + 2.0 * d.doctrine.line_rank2_back:
					out.append("%s %s×%s: линии тяжёлых в %.0f, а не в %.0f" % [size, att, dfn, gap, want])
				if b.call_reinforcements(Ship.ATTACKER):
					b.sides[Ship.ATTACKER].reinforce_at = Battle.STEP * 0.5       # выйдут на первых же шагах
					for k in 3:
						b.step()
						for e in b.events:
							if e[0] != &"jump_in":
								continue
							var u: int = e[1]
							var s := b.ship_by_uid(u)
							arrivals += 1
							var sz := b.sides[s.side].sign_z
							if absf(s.pos.x) >= lim - 0.5 or absf(s.pos.y) >= lim - 0.5:
								out.append("%s %s×%s: подкрепление %s вышло у края %s" % [size, att, dfn, s.def.id, str(s.pos)])
							if s.pos.y * sz < s.anchor.y * sz - 1.0:
								out.append("%s %s×%s: подкрепление %s вышло ВПЕРЕДИ своего места" % [size, att, dfn, s.def.id])
				b.dispose()
	return {"bad": out, "worst": worst, "arrivals": arrivals, "cases": cases, "lim": lim}


func test_start_fits_field() -> void:
	var r := _fit_problems(_defs())
	var bad: PackedStringArray = r["bad"]
	note("расстановка: %d боёв (масштабы × пары кланов), дальше всех от центра — %.0f при пределе %.0f; подкреплений вышло %d" % [whole(r["cases"]), num(r["worst"]), num(r["lim"]), whole(r["arrivals"])])
	ok(whole(r["arrivals"]) > 0, "подкрепление выходило (%d кораблей) — проверке есть что ловить" % whole(r["arrivals"]))
	ok(bad.is_empty(), "все масштабы и пары кланов: строй, носители, станция и выход подкрепления — в поле, на своих местах (%s)" % "; ".join(bad.slice(0, 6)))
	var o := _fit_problems(Defs.load_default({"deploy.heavy_z": 2000.0}) as Defs)
	var ob: PackedStringArray = o["bad"]
	ok(not ob.is_empty(), "откат «старт ±2000»: за краем %d — проверка краснеет (%s)" % [ob.size(), "; ".join(ob.slice(0, 2))])


# ───────────────────────── М16 «суета» тяжёлых (09, 8.2) ─────────────────────────

## М16 по «Стычке» (4 зерна 1000–1003, оба ИИ, до итога): МЕДИАНЫ по боям, как в сводке стенда
## (summarize.py), — путь, смены направления вдоль оси и трогания с места на минуту тяжёлого,
## вставшего в пояс («держит дистанцию»), и доля времени в движении. Зёрен четыре, а не восемь,
## ради яруса sim (бой «Стычки» до итога — ~7 с; 24 боя давали 163 с из 900): на 1000–1007 стенд
## даёт те же выводы (godot/CLAUDE.md, 23), а все восемь — в сводке стенда.
func _m16(d: Defs) -> Dictionary:
	var cols := {"m16_path": PackedFloat64Array(), "m16_flips": PackedFloat64Array(), "m16_starts": PackedFloat64Array(), "m16_move": PackedFloat64Array()}
	var n := 0
	for i in M16_SEEDS:
		var r := BenchCore.run_one(d, BenchCore.setup_for("skirmish", 1000 + i, false, {}), BenchCore.MAX_S, "capella-проверка")
		if num(r.get("m16_path", -1.0)) < 0.0:
			continue
		n += 1
		for k: String in cols:
			var a: PackedFloat64Array = cols[k]
			a.append(num(r[k]))
	var out := {"n": n}
	for k: String in cols:
		var a: PackedFloat64Array = cols[k]
		a.sort()
		var m := a.size()
		out[k] = -1.0 if m == 0 else (a[m >> 1] if m % 2 == 1 else 0.5 * (a[(m >> 1) - 1] + a[m >> 1]))
	return out


static func _m16_text(r: Dictionary) -> String:
	return "путь %.0f, смен направления %.2f, троганий %.2f на минуту, в движении %.2f" % [num(r["m16_path"]), num(r["m16_flips"]), num(r["m16_starts"]), num(r["m16_move"])]


static func _calmer(now: Dictionary, was: Dictionary) -> bool:
	return num(now["m16_flips"]) <= 0.5 * num(was["m16_flips"]) and num(now["m16_starts"]) < num(was["m16_starts"]) and num(now["m16_path"]) < num(was["m16_path"])


## Тяжёлые в поясе дёргаются меньше, чем в 0.7.1 (прежний темп целиком — OLD_TEMPO, бой тот же до
## бита): смен направления вдвое меньше, троганий и пути — меньше. Откат — прежний пересмотр места
## линии (сдвиг 120 и поворот 15° за тик, без мёртвой зоны, без «не дёргаться») при новом ходе: суета
## возвращается, и то же правило краснеет.
func test_m16_calmer_than_before() -> void:
	var now := _m16(_defs())
	var was := _m16(Defs.load_default(OLD_TEMPO) as Defs)
	note("М16, «Стычка», %d зерна: сейчас — %s; в 0.7.1 — %s" % [M16_SEEDS, _m16_text(now), _m16_text(was)])
	ok(whole(now["n"]) == M16_SEEDS and whole(was["n"]) == M16_SEEDS, "М16 посчитан во всех боях (%d и %d из %d)" % [whole(now["n"]), whole(was["n"]), M16_SEEDS])
	ok(_calmer(now, was), "М16 ниже, чем в 0.7.1, на тех же зёрнах: смен направления %.2f против %.2f (не больше половины), троганий %.2f против %.2f, путь %.0f против %.0f" % [
		num(now["m16_flips"]), num(was["m16_flips"]), num(now["m16_starts"]), num(was["m16_starts"]), num(now["m16_path"]), num(was["m16_path"])])
	var rb := Defs.load_default({"line.shift_max": 120.0, "line.turn_max_deg": 15.0, "line.shift_dead": 0.0, "line.turn_dead_deg": 0.0, "heavy.settle": 0.0}) as Defs
	var o := _m16(rb)
	note("откат «прежний пересмотр места»: %s" % _m16_text(o))
	ok(not _calmer(o, was), "откат «прежний пересмотр места линии, без мёртвой зоны и «не дёргаться»»: %s — проверка краснеет" % _m16_text(o))
