# Данные: загрузчик sim/defs.gd против выгрузки и доктрины (план, G0 — проверки).
# У каждой проверки — откат: та же проверка на испорченной копии обязана краснеть.
extends "res://tests/case.gd"

const Defs := preload("res://sim/defs.gd")
const EPS := 1e-9

var D: Defs
var J: Dictionary            # выгрузка как есть
var _bad: PackedStringArray = []
var _n := 0


func _space_text() -> String:
	return FileAccess.get_file_as_string(Defs.SPACE_PATH)


func _doctrine_text() -> String:
	return FileAccess.get_file_as_string(Defs.DOCTRINE_PATH)


func _parse(text: String) -> Dictionary:
	var j := JSON.new()
	var err := j.parse(text)
	assert(err == OK)
	var d: Dictionary = j.data
	return d


func test_loads() -> void:
	D = Defs.load_default() as Defs
	J = _parse(_space_text())
	if not ok(D.ok, "данные грузятся без бед: %s" % "; ".join(D.errors.slice(0, 5))):
		return
	eq(D.faction_ids.size(), 4, "кланов")
	ok(D.fingerprint.length() == 16, "отпечаток данных есть")


# ───────────── загрузчик против выгрузки поле за полем (01, 4.2 п. 1) ─────────────

func _cmp(path: String, want: Variant, got: Variant) -> void:
	_n += 1
	var tw := typeof(want)
	var tg := typeof(got)
	if tw == TYPE_FLOAT or tw == TYPE_INT:
		if tg != TYPE_FLOAT and tg != TYPE_INT:
			_bad.append("%s: ждали число %s, загружено %s" % [path, var_to_str(want), var_to_str(got)])
			return
		var a: float = want
		var b: float = got
		if absf(a - b) > EPS:
			_bad.append("%s: в выгрузке %.15f, загружено %.15f" % [path, a, b])
	elif tw == TYPE_STRING:
		if (tg != TYPE_STRING and tg != TYPE_STRING_NAME) or str(got) != str(want):
			_bad.append("%s: в выгрузке «%s», загружено %s" % [path, str(want), var_to_str(got)])
	elif tw == TYPE_BOOL:
		if tg != TYPE_BOOL or flag(got) != flag(want):
			_bad.append("%s: в выгрузке %s, загружено %s" % [path, str(want), var_to_str(got)])
	elif tw == TYPE_ARRAY:
		var wa: Array = want
		var ga: Array = arr(got)
		if ga.size() != wa.size():
			_bad.append("%s: в выгрузке %d элементов, загружено %d" % [path, wa.size(), ga.size()])
			return
		for i in wa.size():
			_cmp("%s[%d]" % [path, i], wa[i], ga[i])
	elif tw == TYPE_NIL:
		var empty: bool = got == null or (tg == TYPE_FLOAT and float(str(got)) == 0.0) or (tg == TYPE_INT and str(got) == "0") or (tg == TYPE_BOOL and not bool(str(got) == "true"))
		if not empty:
			_bad.append("%s: в выгрузке null, загружено %s" % [path, var_to_str(got)])
	else:
		_bad.append("%s: сверять %s не умею" % [path, type_string(tw)])


func _props(obj: Object) -> Dictionary:
	var out: Dictionary = {}
	for p: Dictionary in obj.get_property_list():
		var usage: int = p["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[p["name"]] = true
	return out


## Каждое поле записи выгрузки обязано быть загружено (или названо пропуском с причиной).
func _cmp_obj(path: String, want: Dictionary, obj: Object, rename: Dictionary = {}, skip: Dictionary = {}, override: Dictionary = {}) -> void:
	if obj == null:
		_bad.append("%s: не загружено вовсе" % path)
		return
	var props := _props(obj)
	for k: Variant in want:
		var ks: String = str(k)
		if skip.has(ks):
			continue
		var prop: String = rename.get(ks, ks.to_snake_case())
		if not props.has(prop):
			_bad.append("%s.%s: поле не загружено и не названо пропуском" % [path, ks])
			continue
		_cmp("%s.%s" % [path, ks], override.get(ks, want[k]), obj.get(prop))


const SHIP_SKIP := {"cost": "кампания", "build": "кампания", "guns": "по ролям — ниже", "pd": "ПВО — ниже"}
const FACTION_SKIP := {"doctrine": "кампания", "motto": "текст меню выбора клана", "desc": "текст меню выбора клана",
	"perks": "текст меню выбора клана", "weakness": "текст меню выбора клана", "color_hex": "то же, что colorCss"}
const QUICK_SKIP := {"_src": "места в коде JS", "summary": "сводка для части 01, бой не читает"}
const CONST_RULES := ["deploy_cols", "flee_rule", "ecm_power_rate", "blind_lock", "ai_think_first", "ai_think_every"]
const TOP_SKIP := {"_meta": "описание выгрузки"}


func _cmp_ship(path: String, want: Dictionary, s: Defs.ShipDef) -> void:
	_cmp_obj(path, want, s, {"role": "role_text"}, SHIP_SKIP)
	if s == null:
		return
	var guns: Array = want["guns"]
	var by_role: Dictionary = {}
	for i in guns.size():
		var g: Dictionary = guns[i]
		var role: StringName = Defs.ROLE_OF_TYPE.get(str(g["type"]), &"")
		var w := s.weapon(role)
		var gp := "%s.guns[%d]" % [path, i]
		if w == null:
			_bad.append("%s: орудия роли %s у корабля нет" % [gp, role])
			continue
		by_role[role] = whole(by_role.get(role, 0)) + 1
		_cmp(gp + ".dmg", g["dmg"], w.dmg)
		_cmp(gp + ".cd", g["cd"], w.cd)
		_cmp(gp + ".range", g["range"], w.rng)
		_cmp(gp + ".charge", g.get("charge", 0.0), w.charge)
		_cmp(gp + ".salvo", g.get("salvo", 0.0), w.salvo)
		_cmp(gp + ".spread", g.get("spread", 0.0), w.spread)
		for k: Variant in g:
			if not (str(k) in ["type", "dmg", "cd", "range", "charge", "salvo", "spread"]):
				_bad.append("%s.%s: поле орудия не сверено" % [gp, str(k)])
	for role: Variant in by_role:
		var rn: StringName = role
		_cmp("%s.guns[роль %s].mounts" % [path, rn], by_role[role], s.weapon(rn).mounts)
	var pd: Dictionary = want["pd"]
	if s.pd == null:
		_bad.append(path + ".pd: ПВО не загружено")
	else:
		_cmp(path + ".pd.count", pd["count"], s.pd.mounts)
		_cmp(path + ".pd.dmg", pd["dmg"], s.pd.dmg)
		_cmp(path + ".pd.cd", pd["cd"], s.pd.cd)
		_cmp(path + ".pd.range", pd["range"], s.pd.rng)


func _cmp_flat(prefix: String, v: Variant, obj: Object, props: Dictionary) -> void:
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		for k: Variant in d:
			_cmp_flat("%s_%s" % [prefix, str(k)], d[k], obj, props)
		return
	if prefix in CONST_RULES:
		return
	if not props.has(prefix):
		_bad.append("battle_constants.%s: поле не загружено и не названо правилом" % prefix)
		return
	_cmp("battle_constants." + prefix, v, obj.get(prefix))


## Сверка всей выгрузки J с загруженным d. Возвращает беды; число сверенных — в _n.
func compare(j: Dictionary, d: Defs) -> PackedStringArray:
	_bad = []
	_n = 0
	var handled := ["faction_ids", "factions", "space_dmg", "space_tough", "ships", "station", "strike", "strike_roles",
		"squad_size_default", "squad_size", "stealth", "ecm_base", "ecm", "hyper", "hyper_own", "orbital_defence",
		"difficulty_ids", "difficulty", "space_stance_ids", "space_stances", "space_move", "quick_battle",
		"battle_constants", "model_len"]
	for k: Variant in j:
		if not (str(k) in handled) and not TOP_SKIP.has(str(k)):
			_bad.append("%s: раздел выгрузки не загружен и не назван пропуском" % str(k))
	var doc := d.doctrine
	_cmp("faction_ids", j["faction_ids"], d.faction_ids)
	var facs: Dictionary = j["factions"]
	for f: Variant in facs:
		_cmp_obj("factions." + str(f), dict(facs[f]), obj(d.factions.get(StringName(str(f)))), {}, FACTION_SKIP)
	var sd: Dictionary = j["space_dmg"]
	for w: Variant in sd:
		var row: Dictionary = sd[w]
		for c: Variant in row:
			var want: Variant = row[c]
			if str(w) == "pd" and str(c) == "torpedo":
				want = doc.space_dmg_pd_torpedo            # ДОКТРИНА 09, 4.4
			_cmp("space_dmg.%s.%s" % [str(w), str(c)], want, d.dmg_mult(StringName(str(w)), Defs.CLASSES.find(StringName(str(c)))))
	_cmp("space_tough", j["space_tough"], d.space_tough)
	_cmp("squad_size_default", j["squad_size_default"], d.squad_size_default)
	var ships: Dictionary = j["ships"]
	for f: Variant in ships:
		var list: Array = ships[f]
		for i in list.size():
			var sw: Dictionary = list[i]
			_cmp_ship("ships.%s[%d]" % [str(f), i], sw, d.ship(StringName(str(f)), StringName(str(sw["id"]))))
	_cmp_ship("station", dict(j["station"]), d.station)
	var strike: Dictionary = j["strike"]
	for f: Variant in strike:
		var by_role: Dictionary = strike[f]
		var fd: Defs.FactionDef = d.factions.get(StringName(str(f)))
		for r: Variant in by_role:
			var cw: Dictionary = by_role[r]
			var ov: Dictionary = {"missileSpeed": doc.torp_speed} if flag(cw.get("torpedo", false)) else {}
			_cmp_obj("strike.%s.%s" % [str(f), str(r)], cw, obj(fd.strike.get(StringName(str(r)))) if fd != null else null, {"range": "rng"}, {}, ov)
	var roles: Dictionary = j["strike_roles"]
	for r: Variant in roles:
		_cmp_obj("strike_roles." + str(r), dict(roles[r]), obj(d.strike_roles.get(StringName(str(r)))))
	var squad: Dictionary = j["squad_size"]
	for f: Variant in squad:
		_cmp("squad_size." + str(f), squad[f], d.factions[StringName(str(f))].squad_size)
	_cmp_obj("stealth", dict(j["stealth"]), d.stealth)
	_cmp_obj("ecm_base", dict(j["ecm_base"]), d.ecm_base)
	var ecm: Dictionary = j["ecm"]
	for f: Variant in ecm:
		_cmp_obj("ecm." + str(f), dict(ecm[f]), d.factions[StringName(str(f))].ecm)
	_cmp_obj("hyper", dict(j["hyper"]), d.hyper)
	_cmp("hyper_own", j["hyper_own"], d.hyper_own)
	var od: Dictionary = j["orbital_defence"]
	for f: Variant in od:
		_cmp_obj("orbital_defence." + str(f), dict(od[f]), d.factions[StringName(str(f))].ground_gun)
	_cmp("difficulty_ids", j["difficulty_ids"], d.difficulty_ids)
	var dif: Dictionary = j["difficulty"]
	for k: Variant in dif:
		_cmp_obj("difficulty." + str(k), dict(dif[k]), obj(d.difficulty.get(StringName(str(k)))))
	_cmp("space_stance_ids", j["space_stance_ids"], d.stance_ids)
	var st: Dictionary = j["space_stances"]
	for k: Variant in st:
		_cmp_obj("space_stances." + str(k), dict(st[k]), obj(d.stances.get(StringName(str(k)))))
	var sm: Dictionary = j["space_move"]
	for k: Variant in sm:
		if str(k) == "reverse":
			_cmp("space_move.reverse", sm[k], d.reverse_k)
		else:
			_bad.append("space_move.%s: поле не загружено" % str(k))
	var q: Dictionary = j["quick_battle"]
	for k: Variant in q:
		var ks := str(k)
		if QUICK_SKIP.has(ks):
			continue
		match ks:
			"size_ids": _cmp("quick_battle.size_ids", q[k], d.quick.size_ids)
			"size_names":
				var sn: Dictionary = q[k]
				for s: Variant in sn:
					_cmp("quick_battle.size_names." + str(s), sn[s], d.quick.size_names.get(StringName(str(s))))
			"defaults":
				var df: Dictionary = q[k]
				for s: Variant in df:
					_cmp("quick_battle.defaults." + str(s), df[s], d.quick.get("default_" + str(s)))
			"player_side", "biome", "ground_gun": _cmp("quick_battle." + ks, q[k], d.quick.get(ks))
			"station_on": _cmp("quick_battle.station_on", q[k], d.quick.station_on)
			"fleets":
				var fl: Dictionary = q[k]
				for size: Variant in fl:
					var bc: Dictionary = fl[size]
					for f: Variant in bc:
						_cmp_lineup("quick_battle.fleets.%s.%s" % [str(size), str(f)], bc[f], d.quick.fleet(StringName(str(size)), StringName(str(f))))
			"reserve":
				var rs: Dictionary = q[k]
				for f: Variant in rs:
					var l: Defs.Lineup = d.quick.reserve.get(StringName(str(f)))
					_cmp_lineup("quick_battle.reserve." + str(f), rs[f], l.entries if l != null else ([] as Array[Defs.FleetEntry]))
			"sizes":
				# вход формулы составов (G1 собирает бой из них и сверяет с fleets)
				var sz: Dictionary = q[k]
				for size: Variant in sz:
					var rows: Dictionary = sz[size]
					var l: Defs.Lineup = d.quick.sizes.get(StringName(str(size)))
					var got: Array[Defs.FleetEntry] = l.entries if l != null else ([] as Array[Defs.FleetEntry])
					if rows.size() != got.size():
						_bad.append("quick_battle.sizes.%s: в выгрузке %d строк, загружено %d" % [str(size), rows.size(), got.size()])
						continue
					var i := 0
					for id: Variant in rows:
						_cmp("quick_battle.sizes.%s.%s (вид)" % [str(size), str(id)], str(id), String(got[i].id))
						_cmp("quick_battle.sizes.%s.%s" % [str(size), str(id)], rows[id], got[i].count)
						i += 1
			"scale":
				var sc: Dictionary = q[k]
				for f: Variant in sc:
					if str(f) == "note":
						continue
					var m: Dictionary = sc[f]
					var scd: Defs.ScaleDef = d.quick.scale.get(StringName(str(f)))
					if scd == null:
						_bad.append("quick_battle.scale.%s: не загружено" % str(f))
						continue
					_cmp("quick_battle.scale.%s.mul" % str(f), m["mul"], scd.mul)
					_cmp("quick_battle.scale.%s.min" % str(f), m.get("min", 0.0), float(scd.at_least))
					_cmp("quick_battle.scale.%s.round" % str(f), m.has("round"), scd.rounds)
			_: _bad.append("quick_battle.%s: поле не загружено и не названо пропуском" % ks)
	var bc2: Dictionary = j["battle_constants"]
	var cprops := _props(d.consts)
	for k: Variant in bc2:
		var e: Dictionary = bc2[k]
		_cmp_flat(str(k), e["value"], d.consts, cprops)
	var ml: Dictionary = j["model_len"]
	var mship: Dictionary = ml["ship"]
	var mhull: Dictionary = ml["hull"]
	var mstrike: Dictionary = ml["strike"]
	for f in d.faction_ids:
		var fd: Defs.FactionDef = d.factions[f]
		for id in fd.ship_order:
			_cmp("model_len.ship.%s (%s)" % [id, f], mship[String(id)], fd.ships[id].model_len)
			_cmp("model_len.hull.%s (%s)" % [id, f], mhull[String(id)], fd.ships[id].hull)
		for r: StringName in fd.strike:
			_cmp("model_len.strike.%s (%s)" % [r, f], mstrike[String(r)], fd.strike[r].model_len)
	_cmp("model_len.station", ml["station"], d.station.model_len)
	_cmp("model_len.hull.station", mhull["station"], d.station.hull)
	return _bad


func _cmp_lineup(path: String, want: Variant, got: Array[Defs.FleetEntry]) -> void:
	var wa: Array = want
	if wa.size() != got.size():
		_bad.append("%s: в выгрузке %d строк, загружено %d" % [path, wa.size(), got.size()])
		return
	for i in wa.size():
		_cmp_obj("%s[%d]" % [path, i], dict(wa[i]), got[i])


func test_vs_export_field_by_field() -> void:
	if D == null or not D.ok:
		ok(false, "данные не загрузились")
		return
	var bad := compare(J, D)
	ok(bad.is_empty(), "загрузчик против выгрузки: %d бед: %s" % [bad.size(), "; ".join(bad.slice(0, 8))])
	ok(_n > 900, "сверено полей: %d (ждали больше 900)" % _n)
	note("сверено %d полей выгрузки" % _n)
	# откат: испорченная копия обязана краснеть — значение, float32 и лишнее поле
	var spoiled := Defs.load_default() as Defs
	spoiled.ship(&"troyden", &"cruiser").hp += 1.0
	spoiled.dmg_table[&"light"][Defs.CLASSES.find(&"carrier")] = PackedFloat32Array([0.45])[0]
	var j2 := _parse(_space_text())
	var t0: Dictionary = arr(dict(j2["ships"])["troyden"])[0]
	t0["shield"] = 5
	var bad2 := compare(j2, spoiled)
	var joined := " | ".join(bad2)
	ok(joined.contains("ships.troyden[3].hp"), "откат: прочность +1 замечена")
	ok(joined.contains("space_dmg.light.carrier"), "откат: float32 вместо float64 (0,45 → 0,449999988) замечен")
	ok(joined.contains("ships.troyden[0].shield"), "откат: поле выгрузки без загрузки замечено")


# ───────────── формула клана: 84 числа из 84 (09, 0.1) ─────────────

# БАЗА нынешних орудий и ПВО — часть 01, 2.4 (game/js/data.js:283–366), до множителей.
const BASE := {
	"corvette": {"gun": [40.0, 2.2], "pd": [15.0, 120.0]}, "frigate": {"gun": [66.0, 2.6], "pd": [17.0, 130.0]},
	"ecm": {"pd": [14.0, 120.0]}, "cruiser": {"gun": [430.0, 9.0], "pd": [14.0, 115.0]},
	"carrier": {"pd": [15.0, 135.0]}, "capital": {"gun": [820.0, 12.0], "pd": [18.0, 145.0]},
	"sinho": {"gun": [560.0, 11.0], "pd": [16.0, 130.0]}}
# Множители ПВО клана (pdDmg, pdRange) — часть 01, 2.4 (data.js:268). Урон и перезарядку
# (gunMod, cdMod) берём из doctrine.json — их и проверяем.
const PD_MOD := {"troyden": [1.30, 1.35], "plektor": [0.9, 1.0], "reez": [0.9, 1.0], "devian": [0.85, 0.85]}


## Формула ПВО клана (часть 01, 2.4; data.js:268): урон — до десятых, дальность — до целого.
static func pd_dmg(base: float, m: float) -> float:
	return snappedf(base * m, 0.1)


static func pd_rng(base: float, m: float) -> float:
	return roundf(base * m)


## Применить формулу клана к базе и сверить с загруженным (= выгрузкой, сверено выше).
## Все четыре половины формулы — параметрами: у каждой свой откат (иначе сверку ПВО
## можно выключить, и счёт «84» этого не заметит — он считает сверки, а не беды).
func clan_formula(d: Defs, dmg_f: Callable, cd_f: Callable, pdd_f: Callable, pdr_f: Callable) -> Array:
	var n := 0
	var bad: PackedStringArray = []
	for f in d.faction_ids:
		var fd: Defs.FactionDef = d.factions[f]
		var pm: Array = PD_MOD[String(f)]
		for id in fd.ship_order:
			var s: Defs.ShipDef = fd.ships[id]
			var b: Dictionary = BASE[String(id)]
			if b.has("gun"):
				var g: Array = b["gun"]
				var w := s.main if s.main != null else s.light   # первое орудие корабля: главный калибр или лёгкое
				var gdmg: float = dmg_f.call(g[0], fd.gun_mod)
				var gcd: float = cd_f.call(g[1], fd.cd_mod)
				n += 2
				if gdmg != w.dmg:
					bad.append("%s %s орудие урон %s ≠ %s" % [f, id, gdmg, w.dmg])
				if absf(gcd - w.cd) > EPS:
					bad.append("%s %s орудие перезарядка %s ≠ %s" % [f, id, gcd, w.cd])
			var p: Array = b["pd"]
			var pdmg: float = pdd_f.call(p[0], pm[0])
			var prng: float = pdr_f.call(p[1], pm[1])
			n += 2
			if absf(pdmg - s.pd.dmg) > EPS:
				bad.append("%s %s ПВО урон %s ≠ %s" % [f, id, pdmg, s.pd.dmg])
			if prng != s.pd.rng:
				bad.append("%s %s ПВО дальность %s ≠ %s" % [f, id, prng, s.pd.rng])
	return [n, bad]


func test_clan_formula_84() -> void:
	if D == null or not D.ok:
		ok(false, "данные не загрузились")
		return
	var r := clan_formula(D, Defs.clan_dmg, Defs.clan_cd, pd_dmg, pd_rng)
	var bad: PackedStringArray = r[1]
	eq(r[0], 84, "чисел нынешних орудий и ПВО")
	ok(bad.is_empty(), "формула клана: %d из %d сошлись; беды: %s" % [whole(r[0]) - bad.size(), whole(r[0]), "; ".join(bad.slice(0, 6))])
	# откат: не та формула обязана краснеть — у каждой из четырёх половин свой,
	# и беда обязана быть ИМЕННО в этой половине (а не где-то ещё)
	var raw := func(base: float, _m: float) -> float: return base
	var floor_x := func(base: float, m: float) -> float: return floorf(base * m)
	var round_x := func(base: float, m: float) -> float: return roundf(base * m)
	var spoiled := [
		["floor вместо round у урона орудия", "орудие урон", clan_formula(D, floor_x, Defs.clan_cd, pd_dmg, pd_rng)],
		["перезарядка без cdMod", "орудие перезарядка", clan_formula(D, Defs.clan_dmg, raw, pd_dmg, pd_rng)],
		["урон ПВО без множителя клана", "ПВО урон", clan_formula(D, Defs.clan_dmg, Defs.clan_cd, raw, pd_rng)],
		["урон ПВО до целого, а не до десятых", "ПВО урон", clan_formula(D, Defs.clan_dmg, Defs.clan_cd, round_x, pd_rng)],
		["дальность ПВО без множителя клана", "ПВО дальность", clan_formula(D, Defs.clan_dmg, Defs.clan_cd, pd_dmg, raw)],
		["дальность ПВО floor вместо round", "ПВО дальность", clan_formula(D, Defs.clan_dmg, Defs.clan_cd, pd_dmg, floor_x)],
	]
	for sp: Array in spoiled:
		var res: Array = sp[2]
		var hits := 0
		for line in strs(res[1]):
			if line.contains(" %s " % sp[1]):
				hits += 1
		ok(hits > 0, "откат «%s» не сходится (бед «%s»: %d)" % [sp[0], sp[1], hits])


# ───────────── батарея по кланам (09, 1.3) ─────────────

const BATTERY := [
	["troyden", "cruiser", 2, 26.0, 2.25, 351.0, 23.1], ["troyden", "capital", 4, 26.0, 2.25, 405.0, 46.2],
	["plektor", "cruiser", 2, 19.0, 2.5, 351.0, 15.2], ["plektor", "capital", 4, 19.0, 2.5, 405.0, 30.4],
	["plektor", "sinho", 3, 19.0, 2.5, 378.0, 22.8],
	["reez", "cruiser", 2, 29.0, 2.5, 351.0, 23.2], ["reez", "capital", 4, 29.0, 2.5, 405.0, 46.4],
	["devian", "cruiser", 2, 22.0, 2.5, 351.0, 17.6], ["devian", "capital", 4, 22.0, 2.5, 405.0, 35.2]]


static func dps(w: Defs.WeaponDef) -> float:
	return snappedf(w.mounts * w.dmg / w.cd, 0.1)


func test_battery_by_clan() -> void:
	if D == null or not D.ok:
		ok(false, "данные не загрузились")
		return
	for row: Array in BATTERY:
		var s := D.ship(StringName(str(row[0])), StringName(str(row[1])))
		var tag := "%s %s" % [row[0], row[1]]
		if not ok(s != null and s.sec != null, tag + ": батарея есть"):
			continue
		eq(s.sec.mounts, whole(row[2]), tag + ": установок")
		near(s.sec.dmg, num(row[3]), EPS, tag + ": урон одной")
		near(s.sec.cd, num(row[4]), EPS, tag + ": перезарядка")
		near(s.sec.rng, num(row[5]), EPS, tag + ": дальность 0,45 R")
		near(dps(s.sec), num(row[6]), EPS, tag + ": урон в секунду")
		eq(s.sec.key, &"sec", tag + ": ключ урона свой")
	near(D.station.sec.dmg, 24.0, EPS, "станция без множителей клана: урон")
	near(D.station.sec.rng, 414.0, EPS, "станция: дальность батареи")
	near(dps(D.station.sec), 38.4, EPS, "станция: урон в секунду")
	for c in Defs.CLASSES:
		var want: float = {&"capital": 0.3, &"carrier": 0.45, &"escort": 1.0, &"strike": 0.0, &"torpedo": 0.0}[c]
		near(D.dmg_mult(&"sec", Defs.CLASSES.find(c)), want, EPS, "строка урона sec по " + c)
	# откат: без cdMod Тройдена таблица обязана разойтись (23,1 → 20,8)
	var no_cd := Defs.load_default({"clan.troyden.cdMod": 1.0}) as Defs
	var tr := no_cd.ship(&"troyden", &"cruiser")
	ok(absf(dps(tr.sec) - 23.1) > 0.5, "откат: без cdMod крейсер Тройдена %.1f, а не 23,1" % dps(tr.sec))


# ───────────── JSON: float → int() (архитектура, 7) ─────────────

func test_json_float_to_int() -> void:
	# сама ловушка жива: число JSON — float даже у «3» и в массиве
	var raw: Variant = JSON.parse_string("{\"n\": 3, \"a\": [2]}")
	var rd: Dictionary = raw
	eq(typeof(rd["n"]), TYPE_FLOAT, "JSON отдаёт 3 как float")
	var ra: Array = rd["a"]
	eq(typeof(ra[0]), TYPE_FLOAT, "и элемент массива — float")
	eq(str(rd["n"]), "3.0", "str() такого числа — «3.0» (поэтому числа в текст — только форматом)")
	if D == null or not D.ok:
		ok(false, "данные не загрузились")
		return
	var cr := D.ship(&"troyden", &"carrier")
	eq(typeof(cr.hangar), TYPE_INT, "ангар — int")
	eq(cr.hangar, 3, "ангар носителя Тройдена")
	eq(typeof(D.ship(&"troyden", &"capital").main.mounts), TYPE_INT, "башен главного калибра — int")
	eq(D.ship(&"troyden", &"capital").main.mounts, 2, "у флагмана две башни главного калибра")
	eq(typeof(D.factions[&"plektor"].squad_size), TYPE_INT, "размер звена — int")
	eq(typeof(D.factions[&"troyden"].strike[&"fighter"].ammo), TYPE_INT, "боезапас — int")
	eq(typeof(D.quick.fleet(&"big", &"plektor")[0].count), TYPE_INT, "число кораблей в составе — int")
	eq(typeof(D.doctrine.sec_mounts[&"cruiser"]), TYPE_INT, "установок батареи — int")
	eq("%d" % D.ship(&"troyden", &"cruiser").pd.mounts, "3", "стволов ПВО крейсера — «3», а не «3.0»")
	# откат: дробное там, где ждут целое, — громкий отказ, а не тихое 2
	var frac := Defs.load_default({"sec.mounts.cruiser": 2.5}) as Defs
	ok(not frac.ok, "2,5 установки батареи — отказ")
	ok(" ".join(frac.errors).contains("ждали целое"), "отказ говорит «ждали целое»: %s" % " ".join(frac.errors).left(200))
	var whole := Defs.load_default({"sec.mounts.cruiser": 3.0}) as Defs
	ok(whole.ok and whole.ship(&"plektor", &"cruiser").sec.mounts == 3, "3.0 установки — это 3")


# ───────────── битый файл — громкий отказ ─────────────

func test_broken_file_is_loud() -> void:
	var dt := _doctrine_text()
	var lines := dt.split("\n")
	var at := -1
	for i in lines.size():
		if lines[i].contains("\"dead_k\""):
			at = i
	if not ok(at >= 0, "в doctrine.json есть dead_k"):
		return
	lines[at] = lines[at].replace("\"v\": 0.4,", "\"v\": 0.4")
	var broken := "\n".join(lines)
	eq(JSON.parse_string(broken), null, "JSON.parse_string на битом молча отдаёт null (поэтому его не берём)")
	var d := Defs.from_texts(_space_text(), broken) as Defs
	ok(not d.ok, "битый doctrine.json — отказ")
	ok(" ".join(d.errors).contains("doctrine.json, строка %d" % (at + 1)), "отказ называет строку %d: %s" % [at + 1, " ".join(d.errors)])

	var j := _parse(_space_text())
	var s0: Dictionary = arr(dict(j["ships"])["troyden"])[0]
	s0.erase("hp")
	var d2 := Defs.from_texts(JSON.stringify(j), _doctrine_text()) as Defs
	ok(not d2.ok and " ".join(d2.errors).contains("ships.troyden[0]: нет поля «hp»"), "нет прочности — отказ с путём: %s" % " ".join(d2.errors).left(200))

	j = _parse(_space_text())
	s0 = arr(dict(j["ships"])["troyden"])[0]
	s0["hp"] = "много"
	var d3 := Defs.from_texts(JSON.stringify(j), _doctrine_text()) as Defs
	ok(not d3.ok and " ".join(d3.errors).contains("ships.troyden[0].hp: ждали float"), "строка вместо числа — отказ: %s" % " ".join(d3.errors).left(200))

	j = _parse(_space_text())
	var cap: Dictionary = arr(dict(j["ships"])["troyden"])[5]
	var g1: Dictionary = arr(cap["guns"])[1]
	g1["dmg"] = 1.0
	var d4 := Defs.from_texts(JSON.stringify(j), _doctrine_text()) as Defs
	ok(not d4.ok and " ".join(d4.errors).contains("свести в одно нельзя"), "две разные башни одной роли — отказ, а не guns[0]")

	var doc := _parse(_doctrine_text())
	dict(doc["main"])["extra_k"] = {"v": 1.0, "sec": "1.2", "why": "запись, которой нет в загрузчике"}
	var d5 := Defs.from_texts(_space_text(), JSON.stringify(doc)) as Defs
	ok(not d5.ok and " ".join(d5.errors).contains("main.extra_k: запись загрузчику неизвестна"), "лишняя запись доктрины — отказ")

	doc = _parse(_doctrine_text())
	dict(doc["main"])["stray"] = 3
	var d6 := Defs.from_texts(_space_text(), JSON.stringify(doc)) as Defs
	ok(not d6.ok and " ".join(d6.errors).contains("число вне записи"), "число без why — отказ")

	var d7 := Defs.load_files("res://data/нет_такого.json", Defs.DOCTRINE_PATH) as Defs
	ok(not d7.ok and d7.errors.size() > 0, "нет файла — отказ словами")


# ───────────── правки --set и --overrides ─────────────

func test_overrides() -> void:
	var ov: Dictionary = Defs.overrides_from_args(PackedStringArray(["--bench", "--set", "main.escort_weight=1.0", "--set=sec.mounts.cruiser=3", "--set", "space.ships.plektor.cruiser.hp=5000", "--set", "clan.troyden.gunMod=1.2"]))
	var errs: PackedStringArray = ov["errors"]
	ok(errs.is_empty(), "ключи разобраны: %s" % " ".join(errs))
	var d := Defs.load_default(dict(ov["overrides"])) as Defs
	if not ok(d.ok, "с правками грузится: %s" % " ".join(d.errors)):
		return
	near(d.doctrine.main_escort_weight, 1.0, EPS, "--set main.escort_weight")
	eq(d.ship(&"troyden", &"cruiser").sec.mounts, 3, "--set sec.mounts.cruiser")
	near(d.ship(&"plektor", &"cruiser").hp, 5000.0, EPS, "--set space.ships.plektor.cruiser.hp")
	near(d.ship(&"troyden", &"cruiser").sec.dmg, 29.0, EPS, "--set clan.troyden.gunMod=1.2 → батарея round(28,8) = 29")
	eq(d.overrides_applied.size(), 4, "правки записаны")
	ok(" ".join(d.overrides_applied).contains("main.escort_weight=1 (было 0.6)"), "запись правки: %s" % " ".join(d.overrides_applied))
	ok(d.fingerprint != D.fingerprint, "отпечаток с правками другой")
	var bad := Defs.load_default({"main.escort_wieght": 1.0}) as Defs
	ok(not bad.ok and " ".join(bad.errors).contains("нет такого числа"), "опечатка в пути — отказ: %s" % " ".join(bad.errors))
	var refd := Defs.load_default({"belt.back_on_k": 0.3}) as Defs
	ok(not refd.ok and " ".join(refd.errors).contains("ссылка на main.dead_k"), "правка ссылки — отказ с подсказкой")
	var follow := Defs.load_default({"main.dead_k": 0.35}) as Defs
	near(follow.doctrine.belt_back_on_k, 0.35, EPS, "ref: правка мёртвой зоны двигает и порог отхода")
	near(follow.ship(&"troyden", &"cruiser").main.dead, 273.0, EPS, "мёртвая зона крейсера 0,35 × 780")
	# путь user:// проверяется КАК путь (правки принимают и его), а файл — свой на процесс:
	# два прогона разом не трут друг другу файлы (хвост G1)
	var upath := "user://g0a_overrides_%d.json" % OS.get_process_id()
	var f := FileAccess.open(upath, FileAccess.WRITE)
	f.store_string("{\"main.dead_k\": 0.42,\n \"belt.clear_k\": 0.46}")
	f.close()
	var ov2: Dictionary = Defs.overrides_from_args(PackedStringArray(["--overrides=" + upath, "--set", "belt.clear_k=0.47"]))
	var d2 := Defs.load_default(dict(ov2["overrides"])) as Defs
	near(d2.doctrine.main_dead_k, 0.42, EPS, "--overrides=файл")
	near(d2.doctrine.belt_clear_k, 0.47, EPS, "--set после файла побеждает")
	f = FileAccess.open(upath, FileAccess.WRITE)
	f.store_string("{\"main.dead_k\": 0.42,,}")
	f.close()
	var ov3: Dictionary = Defs.overrides_from_args(PackedStringArray(["--overrides=" + upath]))
	ok(strs(ov3["errors"]).size() == 1 and strs(ov3["errors"])[0].contains("строка 1"), "битый файл правок — отказ со строкой")
	var ov4: Dictionary = Defs.overrides_from_args(PackedStringArray(["--set", "main.dead_k=много"]))
	ok(strs(ov4["errors"]).size() == 1, "--set без числа — отказ")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(upath))


## Относительный путь файла правок — от папок запуска (архитектура, 7: «--overrides=tune.json»).
## Откат: overrides_from_args без bases — «файл не прочитан». Целиком, с настоящей
## сменой папки процесса, это гоняют run_tests.sh (редактор с --path) и CI (выгрузки).
func test_overrides_relative_path() -> void:
	var dir := tmp("g0a_rel")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("tune.json"), FileAccess.WRITE)
	f.store_string("{\"main.dead_k\": 0.43}")
	f.close()
	var nowhere := dir.path_join("нет_такой_папки")
	var ov: Dictionary = Defs.overrides_from_args(PackedStringArray(["--overrides=tune.json"]), PackedStringArray([nowhere, dir]))
	ok(strs(ov["errors"]).is_empty(), "относительный путь найден во второй папке запуска: %s" % " ".join(strs(ov["errors"])))
	var d := Defs.load_default(dict(ov["overrides"])) as Defs
	near(d.doctrine.main_dead_k, 0.43, EPS, "правка из относительного файла применена")
	var miss: Dictionary = Defs.overrides_from_args(PackedStringArray(["--overrides", "tune.json"]), PackedStringArray([nowhere]))
	var e := " ".join(strs(miss["errors"]))
	ok(e.contains(nowhere.path_join("tune.json")) and e.contains("полный путь"), "не нашёлся — отказ называет, где искали: %s" % e)
	eq(Defs.override_candidates("user://x.json", PackedStringArray([dir])), PackedStringArray(["user://x.json"]), "user:// — как есть")  # путь, не файл
	eq(Defs.override_candidates("/abs/x.json", PackedStringArray([dir])), PackedStringArray(["/abs/x.json"]), "полный путь — как есть")
	eq(Defs.override_candidates("sub/x.json", PackedStringArray(["/a", "", "/a"])), PackedStringArray(["/a/sub/x.json", "sub/x.json"]), "папки по порядку без повторов, последним — как есть")
	DirAccess.remove_absolute(dir.path_join("tune.json"))
	DirAccess.remove_absolute(dir)


# ───────────── оружие по ролям и узлы (09, 1.1; 10.1) ─────────────

func test_weapons_by_role_and_nodes() -> void:
	if D == null or not D.ok:
		ok(false, "данные не загрузились")
		return
	for f in D.faction_ids:
		var fd: Defs.FactionDef = D.factions[f]
		for id in fd.ship_order:
			var s: Defs.ShipDef = fd.ships[id]
			var tag := "%s %s" % [f, id]
			ok(s.pd != null, tag + ": ПВО по роли pd")
			if s.main != null:
				near(s.main.dead, 0.4 * s.main.rng, EPS, tag + ": мёртвая зона 0,4 R")
				ok(s.sec != null and s.light == null, tag + ": у тяжёлого батарея, лёгкого орудия нет")
			var names: Dictionary = {}
			for p in s.nodes:
				names[String(p.name)] = p
			ok(names.has("hull"), tag + ": узел hull")
			if s.sec != null:
				for i in s.sec.mounts:
					ok(names.has("sec_%d" % i), tag + ": узел sec_%d на каждую установку" % i)
			if s.main != null:
				for i in s.main.mounts:
					ok(names.has("main_%d" % i), tag + ": узел main_%d на каждую башню" % i)
			ok(names.has("engines") == (s.max_speed > 0.0), tag + ": двигатели у тех, кто летает")
	var sinho := D.ship(&"plektor", &"sinho")
	ok(sinho.main != null and sinho.missile != null and sinho.missile.salvo == 3, "«Синхо»: главный калибр и ракетный пакет по ролям")
	ok(D.ship(&"troyden", &"carrier").main == null and D.ship(&"troyden", &"carrier").sec == null, "носитель безоружен")
	ok(D.station.main != null and D.station.sec != null and D.station.faction == &"", "станция: главный калибр, батарея, без клана")
	near(D.factions[&"devian"].ecm.main_slow, 2.5, EPS, "помехи Девиана злее (09, 1.7)")
	near(D.factions[&"troyden"].ecm.main_slow, 2.0, EPS, "помехи прочих — вдвое")
	near(D.factions[&"troyden"].strike[&"bomber"].missile_speed, 130.0, EPS, "торпеда 130 (09, 4.4)")
	near(D.factions[&"troyden"].strike[&"fighter"].missile_speed, 150.0, EPS, "ракета истребителя не тронута")
