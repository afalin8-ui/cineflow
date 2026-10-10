# sim/defs.gd — определения боя: выгрузка space_data.json + доктрина doctrine.json
# → типизированные классы. Архитектура, 7; часть 01, 4.2; часть 09, 0.1.
#
# Дальше модель читает ТОЛЬКО классы: опечатка в ключе — отказ при загрузке,
# а не тихий ноль посреди боя. Отказ громкий: список бед со словами и путём
# к полю (а у битого JSON — с номером строки), ok = false. Кто грузит
# (main.gd, тесты, стенд), обязан показать errors и не начинать бой.
#
# Ловушки чисел (проверено судьёй, архитектура 7):
# - все числа JSON в 4.7.2 — float, даже 3 и элементы массивов. int() — ТОЛЬКО
#   здесь (_conv), и только для целого значения: 2.5 там, где ждут целое, — отказ,
#   а не тихое 2;
# - JSON.parse_string на битом тексте молча отдаёт null: берём JSON.new().parse()
#   и его get_error_line() — она считает строки С НУЛЯ (проверено), человеку
#   называем +1. И разбор Godot прощает лишнюю запятую в конце списка, а Node — нет:
#   doctrine.mjs --check ловит то, что пропустит загрузчик;
# - таблица урона — PackedFloat64Array, а не Float32: 0,45 во float32 — это
#   0,449999988, и сверка с выгрузкой (допуск 1e-9) поймала бы это сразу.
#
# Между модулями — preload, а не class_name (архитектура, 2.3):
#   const Defs := preload("res://sim/defs.gd")
#   var d := Defs.load_default()        # или Defs.from_texts(...)
#   if not d.ok: ... d.errors ...
extends RefCounted

const SPACE_PATH := "res://data/space_data.json"
const DOCTRINE_PATH := "res://data/doctrine.json"

## Классы целей — столбцы таблицы урона (часть 01, 2.2).
const CLASSES: Array[StringName] = [&"capital", &"carrier", &"escort", &"strike", &"torpedo"]
## Роль оружия по типу из выгрузки (часть 09, 1.1). Батарея (sec) приходит из доктрины.
const ROLE_OF_TYPE: Dictionary[String, StringName] = {"heavy": &"main", "missile": &"missile", "light": &"light"}
## Ключ строки таблицы урона по роли.
const KEY_OF_ROLE: Dictionary[StringName, StringName] = {&"main": &"heavy", &"sec": &"sec", &"missile": &"missile", &"light": &"light", &"pd": &"pd"}
## Записи доктрины, которые раскладываются не в поле Doctrine, а по своим местам.
const DOCTRINE_SPECIAL: Array[String] = ["sec.mounts", "space_dmg.sec", "ecm.main_slow", "clan", "nodes"]


# ───────────────────────────── классы определений ─────────────────────────────

class WeaponDef:
	var role: StringName        # &"main" &"sec" &"light" &"missile" &"pd"
	var key: StringName         # строка таблицы урона: &"heavy" &"sec" &"light" &"missile" &"pd"
	var dmg: float
	var cd: float
	var rng: float
	var dead: float             # мёртвая зона; 0 — нет
	var charge: float           # накачка главного калибра; 0 — нет
	var salvo: int              # ракетный пакет: ракет в залпе; 0 — не пакет
	var spread: float
	var mounts: int             # установок (у ПВО — стволов), у каждой свой таймер


class PartDef:
	## Узел корабля (09, 10.1): в срезе все целы, урон их не трогает.
	var name: StringName
	var part: StringName        # &"weapon" &"engines" &"system" &"sides"
	var weapon: StringName      # роль оружия у part = weapon
	var index: int
	var system: StringName      # &"ecm" &"hangar"
	var model: String           # имя узла в сцене корабля; «*» — несколько точек
	var affects: PackedStringArray
	var sides: PackedStringArray


class ShipDef:
	var id: StringName
	var faction: StringName     # у станции — пусто: множители клана к ней не применяются
	var cls: StringName
	var cls_i: int              # номер класса в CLASSES — индекс в таблице урона
	var tier: int
	var role_text: String       # «Флагман · главный калибр» (поле role выгрузки)
	var name: String
	var canon: bool
	var desc: String
	var hp: float
	var armor: float
	var max_speed: float
	var thrust: float
	var turn: float
	var radius: float
	var hyper_charge: float
	var flee: float             # 0 — сам в гипер не уходит
	var hangar: int
	var ecm: bool
	var stealth: bool
	var station: bool
	var has_drive: bool
	var hyper_time: float
	var model_len: float        # длина модели (часть 01, 2.17)
	var hull: float             # корпус для расталкивания и строя
	var main: WeaponDef
	var sec: WeaponDef
	var light: WeaponDef
	var missile: WeaponDef
	var pd: WeaponDef
	var nodes: Array[PartDef] = []

	func weapon(role: StringName) -> WeaponDef:
		match role:
			&"main": return main
			&"sec": return sec
			&"light": return light
			&"missile": return missile
			&"pd": return pd
		return null


class CraftDef:
	var id: StringName
	var role: StringName        # &"interceptor" &"fighter" &"bomber"
	var name: String
	var canon: bool
	var cls: StringName
	var hp: float
	var armor: float
	var max_speed: float
	var thrust: float
	var turn: float
	var weapon_kind: StringName # &"gun" &"missile"
	var weapon: StringName      # строка таблицы урона: &"gunInt" &"gunFig" &"torp"
	var dmg: float              # НЕ округлён: 16.099999999999998 — настоящее число игры (01, ловушка 3)
	var cd: float
	var rng: float
	var stealth: bool
	var ammo: int
	var reloads: int
	var reload_time: float
	var miss_chance: float
	var missile_speed: float    # у торпеды — из доктрины (torp.speed)
	var missile_hp: float
	var torpedo: bool
	var model_len: float


class EcmDef:
	var radius: float
	var height: float
	var lock_range: float
	var missile_blind: bool
	var pd_penalty: float
	var spin_up: float
	var main_slow: float        # во сколько раз медленнее перезарядка главного калибра (09, 1.7)


class GroundGunDef:
	var name: String
	var short: String
	var period: float
	var warn: float
	var kind: StringName        # &"beam" &"emp" &"nuke" &"blind"
	var dmg: float
	var disable: float
	var sabotage: float
	var radius: float
	var blind: float
	var color: int
	var color_hex: String
	var desc: String


class FactionDef:
	var id: StringName
	var name: String
	var short: String
	var tag: String
	var color: int
	var color_css: String
	var style: StringName
	var gun_mod: float          # из доктрины (clan): нужны батарее
	var cd_mod: float
	var squad_size: int
	var ship_order: Array[StringName] = []
	var ships: Dictionary[StringName, ShipDef] = {}
	var strike: Dictionary[StringName, CraftDef] = {}
	var ecm: EcmDef
	var ground_gun: GroundGunDef


class StealthDef:
	var reveal_for: float
	var detect_range: float
	var ground_detect: float


class HyperDef:
	var reinforce_delay: float
	var jump_charge: float
	var flee_threshold: float
	var first_wave: float
	var far_max_hops: int
	var far_base_delay: float
	var far_per_hop: float


class DifficultyDef:
	var id: StringName
	var name: String
	var eco: float
	var tempo: float
	var wave: int
	var aim: float
	var camp: float
	var push: float
	var auto: float
	var focus: float
	var desc: String


class StanceDef:
	var id: StringName
	var name: String
	var key: String
	var reach: float
	var leash: float            # 0 — поводка нет
	var hint: String


class StrikeRoleDef:
	var label: String
	var short: String
	var hint: String


class FleetEntry:
	var id: StringName
	var count: int


class Lineup:
	var entries: Array[FleetEntry] = []


class QuickBattleDef:
	var size_ids: Array[StringName] = []
	var size_names: Dictionary[StringName, String] = {}
	var default_mine: StringName
	var default_foe: StringName
	var default_size: StringName
	var default_difficulty: StringName
	var player_side: StringName
	var biome: StringName
	var ground_gun: StringName
	var station_on: Array[StringName] = []
	var fleets: Dictionary[StringName, Lineup] = {}    # ключ «размер:клан»
	var reserve: Dictionary[StringName, Lineup] = {}   # ключ — клан

	func fleet(size: StringName, clan: StringName) -> Array[FleetEntry]:
		var l: Lineup = fleets.get(StringName("%s:%s" % [size, clan]))
		return l.entries if l != null else ([] as Array[FleetEntry])


class BattleConsts:
	## battle_constants выгрузки: вложенные значения развёрнуты через «_»
	## (deploy_z.attacker → deploy_z_attacker). Правила словами (deploy_cols,
	## flee_rule, ecm_power_rate, blind_lock, ai_think) — переносятся кодом.
	var field_half: float
	var field_half_y: float
	var deploy_z_attacker: float
	var deploy_z_defender: float
	var deploy_step_x: float
	var deploy_step_z: float
	var deploy_carrier_back: float
	var deploy_y_jitter: float
	var deploy_y_carrier_up: float
	var deploy_station_x_jitter: float
	var deploy_station_y: float
	var deploy_station_z_back: float
	var ai_opening_line_z: float
	var ai_opening_xy_k: float
	var len_fallback_k: float
	var hull_formula_radius_k: float
	var hull_formula_len_k: float
	var default_stance_ship: StringName
	var default_stance_station: StringName
	var name_numbering: StringName
	var squad_rebuild: float
	var craft_radius: float
	var projectile_life: float
	var projectile_radius: float
	var projectile_armor: float
	var projectile_cls: StringName
	var missile_defaults_speed: float
	var missile_defaults_hp: float
	var missile_miss_life: float
	var ship_missile_speed: float
	var ship_missile_hp: float
	var hyper_default_charge: float
	var ecm_field_half_height_k: float
	var ecm_active_power: float
	var stealth_corvette_k: float
	var stealth_craft_k_k: float
	var stealth_craft_k_no_pd_range: float
	var reinforce_drop_base_z: float
	var reinforce_drop_per_row: int
	var reinforce_drop_step_x: float
	var reinforce_drop_step_z: float
	var reinforce_drop_exit_speed_k: float
	var reinforce_drop_exit_free_sec: float
	var reinforce_drop_goto_x_k: float
	var reinforce_drop_goto_z: float
	var ground_gun_first: float
	var ground_gun_origin: PackedFloat64Array
	var emp_targets: int
	var updown_step: float
	var brake_k: float
	var ship_speed_cap_k: float
	var craft_speed_cap_k: float
	var turret_arc_ship: float
	var turret_arc_station: float
	var pd_retarget_idle: float
	var pd_retarget_cd_jitter: PackedFloat64Array
	var sim_step_max_frame: float
	var sim_step_speeds: PackedInt32Array
	var side_colors_mine: String
	var side_colors_foe: String
	var side_colors_mine_dim: String
	var side_colors_foe_dim: String


class Doctrine:
	## Числа части 09 (приложение) — путь записи doctrine.json с «_» вместо точек:
	## main.dead_k → main_dead_k. Поле без записи и запись без поля — отказ загрузки.
	var main_dead_k: float
	var main_escort_weight: float
	var sec_dmg: float
	var sec_cd: float
	var sec_range_k: float
	var space_dmg_pd_torpedo: float
	var torp_speed: float
	var belt_work_k: float
	var belt_far_k: float
	var belt_back_on_k: float
	var belt_back_off_k: float
	var belt_clear_k: float
	var approach_share: String          # правило словами (rule)
	var approach_foe_brake_k: float
	var retreat_futile_window_s: float
	var retreat_futile_gain: float
	var retreat_futile_speed_k: float
	var retreat_pinned_side_k: float
	var retreat_futile_forget_k: float
	var retreat_futile_forget_min_s: float
	var retreat_edge: float
	var leash_capital_k: float
	var leash_frigate_ai: float
	var line_L_k: float
	var line_corvette_k: float
	var line_frigate_k: float
	var line_ecm_k: float
	var line_light_min_width: float
	var line_advance_k: float
	var line_carrier_back: float
	var line_carrier_back_close: float
	var line_carrier_close_dist: float
	var line_step_heavy: float
	var line_step_heavy_min: float
	var line_step_light: float
	var line_width_over: float
	var line_width_floor: float
	var line_rank2_back: float
	var line_rear: float
	var line_shift_max: float
	var line_turn_max_deg: float
	var deploy_heavy_z: float
	var ai_corvette_intercept_take: float
	var ai_corvette_intercept_drop: float
	var ai_corvette_intercept_share: float
	var ai_help_after_s: float
	var ai_help_lights: int
	var ai_help_max_s: float
	var ai_air_e_over_i: int
	var ai_air_bomber_slots_k: float
	var ai_air_bomber_min: int
	var air_patrol_k: float
	var air_bomber_flank_extra: float
	var air_bomber_flank_points_k: PackedFloat64Array
	var amove_resume_s: float
	var camera_fov_deg: float
	var camera_tilt_deg: float
	var camera_dist_min: float
	var camera_dist_max: float
	var camera_dist_start: float
	var camera_dist_work: float
	var camera_edge_speed_k: float
	var camera_wheel_step: float
	var camera_rotate_speed: float
	var camera_drag_k: float
	var camera_near: float
	var camera_far: float
	# раскладываются по местам (DOCTRINE_SPECIAL), здесь — для справки и стенда
	var sec_mounts: Dictionary[StringName, int] = {}
	var ecm_main_slow_default: float


# ───────────────────────────── что загружено ─────────────────────────────

var ok := false
var errors: PackedStringArray = []
## Правки поверх файлов (--set, --overrides) в порядке применения: «путь=новое (было старое)».
var overrides_applied: PackedStringArray = []
## Отпечаток данных: sha256 обоих текстов и правок — в заголовок записи боя (архитектура, 2.9).
var fingerprint := ""

var faction_ids: Array[StringName] = []
var factions: Dictionary[StringName, FactionDef] = {}
var station: ShipDef
var dmg_table: Dictionary[StringName, PackedFloat64Array] = {}
var space_tough: float
var squad_size_default: int
var strike_roles: Dictionary[StringName, StrikeRoleDef] = {}
var stealth: StealthDef
var ecm_base: EcmDef
var hyper: HyperDef
var hyper_own: Array[StringName] = []
var difficulty_ids: Array[StringName] = []
var difficulty: Dictionary[StringName, DifficultyDef] = {}
var stance_ids: Array[StringName] = []
var stances: Dictionary[StringName, StanceDef] = {}
var reverse_k: float              # space_move.reverse
var quick: QuickBattleDef
var consts: BattleConsts
var doctrine: Doctrine


## Множитель урона оружия `key` по классу цели (часть 01, 2.2). Неизвестная пара — 1.
func dmg_mult(key: StringName, cls_i: int) -> float:
	var row: PackedFloat64Array = dmg_table.get(key, PackedFloat64Array())
	if row.is_empty() or cls_i < 0 or cls_i >= row.size():
		return 1.0
	return row[cls_i]


func ship(clan: StringName, id: StringName) -> ShipDef:
	if id == &"station":
		return station
	var f: FactionDef = factions.get(clan)
	return f.ships.get(id) if f != null else null


# ───────────────────────────── загрузка ─────────────────────────────

static func load_default(overrides: Dictionary = {}) -> RefCounted:
	return load_files(SPACE_PATH, DOCTRINE_PATH, overrides)


static func load_files(space_path: String, doctrine_path: String, overrides: Dictionary = {}) -> RefCounted:
	var d := new()
	var space_text := FileAccess.get_file_as_string(space_path)
	if space_text.is_empty():
		d.errors.append("%s: файл не прочитан (%s)" % [space_path, error_string(FileAccess.get_open_error())])
		return d
	var doctrine_text := FileAccess.get_file_as_string(doctrine_path)
	if doctrine_text.is_empty():
		d.errors.append("%s: файл не прочитан (%s)" % [doctrine_path, error_string(FileAccess.get_open_error())])
		return d
	d._load(space_text, doctrine_text, overrides, space_path.get_file(), doctrine_path.get_file())
	return d


static func from_texts(space_text: String, doctrine_text: String, overrides: Dictionary = {}) -> RefCounted:
	var d := new()
	d._load(space_text, doctrine_text, overrides, "space_data.json", "doctrine.json")
	return d


## Разбор JSON с номером строки. Битый текст — беда в errors и null.
func parse_json(text: String, what: String) -> Variant:
	var j := JSON.new()
	var err := j.parse(text)
	if err != OK:
		errors.append("%s, строка %d: файл не читается как JSON — %s" % [what, j.get_error_line() + 1, j.get_error_message()])
		return null
	return j.data


func _load(space_text: String, doctrine_text: String, overrides: Dictionary, space_name: String, doctrine_name: String) -> void:
	var sv: Variant = parse_json(space_text, space_name)
	var dv: Variant = parse_json(doctrine_text, doctrine_name)
	if not errors.is_empty():
		return
	if typeof(sv) != TYPE_DICTIONARY or typeof(dv) != TYPE_DICTIONARY:
		errors.append("%s / %s: в корне ждали объект { … }" % [space_name, doctrine_name])
		return
	var space: Dictionary = sv
	var doc: Dictionary = dv
	for path: String in overrides:
		var val: Variant = overrides[path]
		if typeof(val) != TYPE_FLOAT and typeof(val) != TYPE_INT:
			errors.append("правка %s: ждали число, а пришло %s" % [path, var_to_str(val)])
			continue
		var num: float = val
		var e := _apply_override(space, doc, path, num)
		if e != "":
			errors.append(e)
	var ftext := space_text.sha256_text() + doctrine_text.sha256_text() + ",".join(overrides_applied)
	fingerprint = ftext.sha256_text().substr(0, 16)
	if errors.is_empty():
		_build(space, doc)
	ok = errors.is_empty()


# ───────────────────────────── правки --set и --overrides ─────────────────────────────

## Ключи командной строки → набор правок {путь: число}. Порядок: файлы --overrides,
## затем --set (поздний побеждает). Беды — в поле "errors".
## Пути: доктрина — как в doctrine.json (main.escort_weight, sec.mounts.cruiser,
## clan.troyden.gunMod); выгрузка — с приставкой space. и id вместо номера в списке
## (space.ships.plektor.cruiser.hp).
static func overrides_from_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var errs: PackedStringArray = []
	var sets: Array[String] = []
	var files: Array[String] = []
	var i := 0
	while i < args.size():
		var a := args[i]
		if a == "--set" and i + 1 < args.size():
			sets.append(args[i + 1])
			i += 1
		elif a.begins_with("--set="):
			sets.append(a.substr(6))
		elif a == "--overrides" and i + 1 < args.size():
			files.append(args[i + 1])
			i += 1
		elif a.begins_with("--overrides="):
			files.append(a.substr(12))
		i += 1
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		if text.is_empty():
			errs.append("--overrides=%s: файл не прочитан (%s)" % [f, error_string(FileAccess.get_open_error())])
			continue
		var j := JSON.new()
		if j.parse(text) != OK:
			errs.append("--overrides=%s, строка %d: файл не читается как JSON — %s" % [f, j.get_error_line() + 1, j.get_error_message()])
			continue
		if typeof(j.data) != TYPE_DICTIONARY:
			errs.append("--overrides=%s: ждали объект {\"путь\": число}" % f)
			continue
		var m: Dictionary = j.data
		for k: Variant in m:
			var v: Variant = m[k]
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
				errs.append("--overrides=%s: %s — не число" % [f, str(k)])
				continue
			out[str(k)] = v
	for s in sets:
		var eq := s.find("=")
		var val := s.substr(eq + 1).strip_edges() if eq > 0 else ""
		if eq <= 0 or not val.is_valid_float():
			errs.append("--set %s: ждали путь=число" % s)
			continue
		out[s.substr(0, eq).strip_edges()] = val.to_float()
	return {"overrides": out, "errors": errs}


func _apply_override(space: Dictionary, doc: Dictionary, path: String, value: float) -> String:
	var segs := path.split(".")
	var in_space := segs[0] == "space"
	var node: Variant = space if in_space else doc
	var holder: Variant = null
	var key: Variant = null
	var i := 1 if in_space else 0
	if i >= segs.size():
		return "правка %s: путь пуст" % path
	while true:
		if typeof(node) == TYPE_DICTIONARY:
			var d: Dictionary = node
			if not in_space and d.has("why"):
				# запись доктрины: число живёт в её v; ссылку и правило не правим
				if d.has("ref"):
					return "правка %s: эта запись — ссылка на %s, правь её" % [path, str(d["ref"])]
				if not d.has("v"):
					return "правка %s: у записи нет числа (правило словами)" % path
				holder = d
				key = "v"
				node = d["v"]
				continue
		if i >= segs.size():
			break
		var s := segs[i]
		if typeof(node) == TYPE_DICTIONARY:
			var d2: Dictionary = node
			if not d2.has(s):
				return "правка %s: нет такого числа (нет «%s»)" % [path, s]
			holder = d2
			key = s
			node = d2[s]
		elif typeof(node) == TYPE_ARRAY:
			var a: Array = node
			var idx := -1
			if s.is_valid_int():
				idx = s.to_int()
			else:
				for j in a.size():
					if typeof(a[j]) == TYPE_DICTIONARY:
						var aj: Dictionary = a[j]
						if str(aj.get("id", "")) == s:
							idx = j
			if idx < 0 or idx >= a.size():
				return "правка %s: в списке нет «%s»" % [path, s]
			holder = a
			key = idx
			node = a[idx]
		else:
			return "правка %s: нет такого числа" % path
		i += 1
	if typeof(node) != TYPE_FLOAT and typeof(node) != TYPE_INT:
		return "правка %s: путь кончается не на числе" % path
	_put_in(holder, key, value)
	overrides_applied.append("%s=%s (было %s)" % [path, _fmt(value), _fmt(node)])
	return ""


static func _get_in(holder: Variant, key: Variant) -> Variant:
	if typeof(holder) == TYPE_DICTIONARY:
		var d: Dictionary = holder
		return d.get(key)
	var a: Array = holder
	var i: int = key
	return a[i]


static func _put_in(holder: Variant, key: Variant, value: Variant) -> void:
	if typeof(holder) == TYPE_DICTIONARY:
		var d: Dictionary = holder
		d[key] = value
	else:
		var a: Array = holder
		var i: int = key
		a[i] = value


static func _fmt(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		var f: float = v
		return ("%d" % int(f)) if f == floorf(f) and absf(f) < 1e15 else String.num(f)
	return var_to_str(v)


# ───────────────────────────── раскладка по классам ─────────────────────────────

func _err(path: String, msg: String) -> void:
	errors.append("%s: %s" % [path, msg])


## Значение JSON → тип поля. int() — только здесь и только для целого.
func _conv(v: Variant, type: int, path: String) -> Variant:
	var t := typeof(v)
	match type:
		TYPE_FLOAT:
			if t == TYPE_FLOAT or t == TYPE_INT:
				var f: float = v
				return f
		TYPE_INT:
			if t == TYPE_FLOAT or t == TYPE_INT:
				var f: float = v
				if f != floorf(f) or absf(f) > 2147483647.0:
					_err(path, "ждали целое, а в файле %s" % _fmt(f))
					return null
				return int(f)
		TYPE_BOOL:
			if t == TYPE_BOOL:
				return v
		TYPE_STRING:
			if t == TYPE_STRING:
				return v
		TYPE_STRING_NAME:
			if t == TYPE_STRING or t == TYPE_STRING_NAME:
				var s: String = v
				return StringName(s)
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_STRING_ARRAY:
			if t == TYPE_ARRAY:
				var src: Array = v
				var et := TYPE_FLOAT if type == TYPE_PACKED_FLOAT64_ARRAY else (TYPE_INT if type == TYPE_PACKED_INT32_ARRAY else TYPE_STRING)
				var out: Array = []
				for i in src.size():
					var x: Variant = _conv(src[i], et, "%s[%d]" % [path, i])
					if x == null:
						return null
					out.append(x)
				if type == TYPE_PACKED_FLOAT64_ARRAY:
					return PackedFloat64Array(out)
				if type == TYPE_PACKED_INT32_ARRAY:
					return PackedInt32Array(out)
				return PackedStringArray(out)
	_err(path, "ждали %s, а в файле %s" % [type_string(type), var_to_str(v).left(60)])
	return null


## Заполнить объект из словаря: поле ← ключ JSON с тем же именем в snake_case
## (maxSpeed → max_speed). rename — особые имена JSON→поле; manual — поля, которые
## заполняет вызывающий; optional — поля, которых в записи может не быть (или null).
func _fill(obj: Object, d: Dictionary, path: String, rename: Dictionary = {}, manual: Array[String] = [], optional: Array[String] = []) -> void:
	var by_field: Dictionary = {}
	for k: Variant in d:
		var ks: String = str(k)
		var f: String = rename.get(ks, ks.to_snake_case())
		by_field[f] = ks
	for p: Dictionary in obj.get_property_list():
		var usage: int = p["usage"]
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var pname: String = p["name"]
		if pname in manual:
			continue
		var ptype: int = p["type"]
		if not by_field.has(pname) or d[by_field[pname]] == null:
			if pname in optional:
				continue
			_err(path, "нет поля «%s»" % [by_field.get(pname, pname)])
			continue
		var key: String = by_field[pname]
		var val: Variant = _conv(d[key], ptype, "%s.%s" % [path, key])
		if val != null:
			obj.set(pname, val)


func _dict(v: Variant, path: String) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		_err(path, "ждали объект { … }, а в файле %s" % var_to_str(v).left(60))
		return {}
	var d: Dictionary = v
	return d


func _arr(v: Variant, path: String) -> Array:
	if typeof(v) != TYPE_ARRAY:
		_err(path, "ждали список [ … ], а в файле %s" % var_to_str(v).left(60))
		return []
	var a: Array = v
	return a


func _need(d: Dictionary, key: String, path: String) -> Variant:
	if not d.has(key):
		_err(path, "нет поля «%s»" % key)
		return null
	return d[key]


func _num(d: Dictionary, key: String, path: String) -> float:
	var v: Variant = _conv(_need(d, key, path), TYPE_FLOAT, "%s.%s" % [path, key])
	if v == null:
		return 0.0
	var f: float = v
	return f


func _int(d: Dictionary, key: String, path: String) -> int:
	var v: Variant = _conv(_need(d, key, path), TYPE_INT, "%s.%s" % [path, key])
	if v == null:
		return 0
	var i: int = v
	return i


func _names(v: Variant, path: String) -> Array[StringName]:
	var out: Array[StringName] = []
	var a := _arr(v, path)
	for i in a.size():
		var s: Variant = _conv(a[i], TYPE_STRING_NAME, "%s[%d]" % [path, i])
		if s != null:
			var sn: StringName = s
			out.append(sn)
	return out


func _build(space: Dictionary, doc: Dictionary) -> void:
	_build_doctrine(doc)
	if not errors.is_empty():
		return
	var docd := _flatten_doctrine(doc)
	var clan := _dict(_v_of(docd, "clan"), "doctrine.clan")
	var main_slow := _dict(_v_of(docd, "ecm.main_slow"), "doctrine.ecm.main_slow")
	var nodes := _dict(_v_of(docd, "nodes"), "doctrine.nodes")
	var sec_row := _dict(_v_of(docd, "space_dmg.sec"), "doctrine.space_dmg.sec")

	# таблица урона: выгрузка + строка sec и pd → torpedo из доктрины
	var sd := _dict(_need(space, "space_dmg", "space_data"), "space_data.space_dmg")
	for w: Variant in sd:
		var ws: String = str(w)
		dmg_table[StringName(ws)] = _dmg_row(_dict(sd[w], "space_dmg." + ws), "space_dmg." + ws)
	if dmg_table.has(&"sec"):
		_err("doctrine.space_dmg.sec", "в выгрузке уже есть строка sec — доктрина её затёрла бы")
	dmg_table[&"sec"] = _dmg_row(sec_row, "doctrine.space_dmg.sec")
	if dmg_table.has(&"pd"):
		dmg_table[&"pd"][CLASSES.find(&"torpedo")] = doctrine.space_dmg_pd_torpedo
	space_tough = _num(space, "space_tough", "space_data")
	squad_size_default = _int(space, "squad_size_default", "space_data")

	var model_len := _dict(_need(space, "model_len", "space_data"), "space_data.model_len")
	var len_ship := _dict(_need(model_len, "ship", "model_len"), "model_len.ship")
	var len_hull := _dict(_need(model_len, "hull", "model_len"), "model_len.hull")
	var len_strike := _dict(_need(model_len, "strike", "model_len"), "model_len.strike")

	faction_ids = _names(_need(space, "faction_ids", "space_data"), "space_data.faction_ids")
	var fac := _dict(_need(space, "factions", "space_data"), "space_data.factions")
	var ships := _dict(_need(space, "ships", "space_data"), "space_data.ships")
	var strike := _dict(_need(space, "strike", "space_data"), "space_data.strike")
	var squad := _dict(_need(space, "squad_size", "space_data"), "space_data.squad_size")
	var ecm := _dict(_need(space, "ecm", "space_data"), "space_data.ecm")
	var ground := _dict(_need(space, "orbital_defence", "space_data"), "space_data.orbital_defence")
	for f in faction_ids:
		var fp := "factions." + f
		var fd := FactionDef.new()
		_fill(fd, _dict(_need(fac, f, "factions"), fp), fp, {}, ["gun_mod", "cd_mod", "squad_size", "ship_order", "ships", "strike", "ecm", "ground_gun"])
		var cm := _dict(_need(clan, f, "doctrine.clan"), "doctrine.clan." + f)
		fd.gun_mod = _num(cm, "gunMod", "doctrine.clan." + f)
		fd.cd_mod = _num(cm, "cdMod", "doctrine.clan." + f)
		fd.squad_size = _int(squad, f, "space_data.squad_size")
		var list := _arr(_need(ships, f, "ships"), "ships." + f)
		for i in list.size():
			var sp := "ships.%s[%d]" % [f, i]
			var s := _ship(_dict(list[i], sp), sp, fd, len_ship, len_hull, nodes)
			if s != null:
				fd.ship_order.append(s.id)
				fd.ships[s.id] = s
		var sk := _dict(_need(strike, f, "strike"), "strike." + f)
		for r: Variant in sk:
			var rp := "strike.%s.%s" % [f, str(r)]
			var c := CraftDef.new()
			var cd := _dict(sk[r], rp)
			_fill(c, cd, rp, {"range": "rng"}, ["model_len"], ["ammo", "reloads", "reload_time", "miss_chance", "missile_speed", "missile_hp", "torpedo"])
			if c.torpedo:
				c.missile_speed = doctrine.torp_speed       # ДОКТРИНА 09, 4.4: 88 → 130
			c.model_len = _num(len_strike, str(r), "model_len.strike")
			fd.strike[StringName(str(r))] = c
		fd.ecm = _ecm(_dict(_need(ecm, f, "ecm"), "ecm." + f), "ecm." + f, main_slow, f)
		var gg := GroundGunDef.new()
		_fill(gg, _dict(_need(ground, f, "orbital_defence"), "orbital_defence." + f), "orbital_defence." + f, {}, [], ["dmg", "disable", "sabotage", "radius", "blind"])
		fd.ground_gun = gg
		factions[f] = fd
	for f: Variant in clan:
		if not factions.has(StringName(str(f))):
			_err("doctrine.clan." + str(f), "такого клана нет в выгрузке")

	station = _ship(_dict(_need(space, "station", "space_data"), "station"), "station", null, {"station": model_len.get("station")}, len_hull, nodes)

	var roles := _dict(_need(space, "strike_roles", "space_data"), "space_data.strike_roles")
	for r: Variant in roles:
		var rd := StrikeRoleDef.new()
		_fill(rd, _dict(roles[r], "strike_roles." + str(r)), "strike_roles." + str(r))
		strike_roles[StringName(str(r))] = rd
	stealth = StealthDef.new()
	_fill(stealth, _dict(_need(space, "stealth", "space_data"), "stealth"), "stealth")
	ecm_base = _ecm(_dict(_need(space, "ecm_base", "space_data"), "ecm_base"), "ecm_base", main_slow, "")
	hyper = HyperDef.new()
	_fill(hyper, _dict(_need(space, "hyper", "space_data"), "hyper"), "hyper")
	hyper_own = _names(_need(space, "hyper_own", "space_data"), "hyper_own")
	difficulty_ids = _names(_need(space, "difficulty_ids", "space_data"), "difficulty_ids")
	var dif := _dict(_need(space, "difficulty", "space_data"), "difficulty")
	for k in difficulty_ids:
		var dd := DifficultyDef.new()
		_fill(dd, _dict(_need(dif, k, "difficulty"), "difficulty." + k), "difficulty." + k)
		difficulty[k] = dd
	stance_ids = _names(_need(space, "space_stance_ids", "space_data"), "space_stance_ids")
	var st := _dict(_need(space, "space_stances", "space_data"), "space_stances")
	for k in stance_ids:
		var sdf := StanceDef.new()
		_fill(sdf, _dict(_need(st, k, "space_stances"), "space_stances." + k), "space_stances." + k, {}, [], ["leash"])
		stances[k] = sdf
	reverse_k = _num(_dict(_need(space, "space_move", "space_data"), "space_move"), "reverse", "space_move")
	quick = _quick(_dict(_need(space, "quick_battle", "space_data"), "quick_battle"))
	consts = _consts(_dict(_need(space, "battle_constants", "space_data"), "battle_constants"))


func _dmg_row(d: Dictionary, path: String) -> PackedFloat64Array:
	var row := PackedFloat64Array()
	row.resize(CLASSES.size())
	for i in CLASSES.size():
		row[i] = _num(d, CLASSES[i], path)
	for k: Variant in d:
		if not CLASSES.has(StringName(str(k))):
			_err(path, "класс цели «%s» неизвестен" % str(k))
	return row


func _ecm(d: Dictionary, path: String, main_slow: Dictionary, clan: String) -> EcmDef:
	var e := EcmDef.new()
	_fill(e, d, path, {}, ["main_slow"])
	e.main_slow = _num(main_slow, clan, "doctrine.ecm.main_slow") if main_slow.has(clan) else _num(main_slow, "default", "doctrine.ecm.main_slow")
	return e


func _weapon(role: StringName, g: Dictionary, path: String) -> WeaponDef:
	var w := WeaponDef.new()
	w.role = role
	w.key = KEY_OF_ROLE[role]
	w.dmg = _num(g, "dmg", path)
	w.cd = _num(g, "cd", path)
	w.rng = _num(g, "range", path)
	w.charge = _num(g, "charge", path) if g.has("charge") else 0.0
	w.salvo = _int(g, "salvo", path) if g.has("salvo") else 0
	w.spread = _num(g, "spread", path) if g.has("spread") else 0.0
	w.mounts = 1
	for k: Variant in g:
		if not (str(k) in ["type", "dmg", "cd", "range", "charge", "salvo", "spread"]):
			_err(path, "поле орудия «%s» загрузчику неизвестно" % str(k))
	return w


static func _same_weapon(a: WeaponDef, b: WeaponDef) -> bool:
	return a.dmg == b.dmg and a.cd == b.cd and a.rng == b.rng and a.charge == b.charge and a.salvo == b.salvo and a.spread == b.spread


func _ship(d: Dictionary, path: String, fd: FactionDef, len_ship: Dictionary, len_hull: Dictionary, nodes: Dictionary) -> ShipDef:
	if d.is_empty():
		return null
	var s := ShipDef.new()
	_fill(s, d, path, {"role": "role_text"},
		["faction", "cls_i", "model_len", "hull", "main", "sec", "light", "missile", "pd", "nodes"],
		["tier", "flee", "hangar", "ecm", "stealth", "station", "has_drive", "hyper_time", "canon"])
	s.faction = fd.id if fd != null else &""
	s.cls_i = CLASSES.find(s.cls)
	if s.cls_i < 0:
		_err(path + ".cls", "класс «%s» неизвестен" % s.cls)
	s.model_len = _num(len_ship, s.id, "model_len.ship")
	s.hull = _num(len_hull, s.id, "model_len.hull")
	# оружие — по РОЛИ, а не guns[0] (09, 1.1; 9.5 п. 1). Одинаковые одной роли — одна
	# установка с mounts; разные — отказ, а не молча взятое первое.
	var guns := _arr(_need(d, "guns", path), path + ".guns")
	for i in guns.size():
		var gp := "%s.guns[%d]" % [path, i]
		var g := _dict(guns[i], gp)
		var type: String = str(g.get("type", ""))
		if not ROLE_OF_TYPE.has(type):
			_err(gp, "тип орудия «%s» неизвестен" % type)
			continue
		var role: StringName = ROLE_OF_TYPE[type]
		var w := _weapon(role, g, gp)
		var have := s.weapon(role)
		if have == null:
			s.set(String(role), w)
		elif _same_weapon(have, w):
			have.mounts += 1
		else:
			_err(gp, "второе орудие роли %s не такое, как первое — свести в одно нельзя" % role)
	var pdd := _dict(_need(d, "pd", path), path + ".pd")
	if not pdd.is_empty():
		var p := WeaponDef.new()
		p.role = &"pd"
		p.key = &"pd"
		p.mounts = _int(pdd, "count", path + ".pd")
		p.dmg = _num(pdd, "dmg", path + ".pd")
		p.cd = _num(pdd, "cd", path + ".pd")
		p.rng = _num(pdd, "range", path + ".pd")
		s.pd = p
	if s.main != null:
		s.main.dead = doctrine.main_dead_k * s.main.rng     # ДОКТРИНА 09, 1.2
		s.sec = _battery(s, fd, path)
	elif doctrine.sec_mounts.has(s.id):
		_err("doctrine.sec.mounts." + s.id, "у корабля нет главного калибра — батарее не от чего считать дальность")
	s.nodes = _parts(nodes, s.id)
	return s


## Батарея (09, 1.3): база доктрины × множители клана той же формулой, что data.js
## у орудий: dmg = round(dmg × gunMod), cd = до сотых(cd × cdMod). Станция — без множителей.
func _battery(s: ShipDef, fd: FactionDef, path: String) -> WeaponDef:
	if not doctrine.sec_mounts.has(s.id):
		_err(path, "у тяжёлого «%s» нет числа установок батареи (doctrine sec.mounts)" % s.id)
		return null
	var w := WeaponDef.new()
	w.role = &"sec"
	w.key = &"sec"
	w.mounts = doctrine.sec_mounts[s.id]
	var gm := fd.gun_mod if fd != null else 1.0
	var cm := fd.cd_mod if fd != null else 1.0
	w.dmg = clan_dmg(doctrine.sec_dmg, gm)
	w.cd = clan_cd(doctrine.sec_cd, cm)
	w.rng = doctrine.sec_range_k * s.main.rng
	return w


## Формула клана data.js:278 для урона: Math.round (половина — вверх; у положительных
## roundf то же самое).
static func clan_dmg(base: float, gun_mod: float) -> float:
	return roundf(base * gun_mod)


## Формула клана для перезарядки: Number((cd × cdMod).toFixed(2)). snappedf даёт то же
## на всех числах игры (тест: 84 числа из 84).
static func clan_cd(base: float, cd_mod: float) -> float:
	return snappedf(base * cd_mod, 0.01)


func _parts(nodes: Dictionary, id: StringName) -> Array[PartDef]:
	var out: Array[PartDef] = []
	var path := "doctrine.nodes." + id
	var list := _dict(_need(nodes, id, "doctrine.nodes"), path)
	for n: Variant in list:
		var pd := PartDef.new()
		var np := "%s.%s" % [path, str(n)]
		_fill(pd, _dict(list[n], np), np, {}, ["name"], ["weapon", "index", "system", "affects", "sides"])
		pd.name = StringName(str(n))
		out.append(pd)
	return out


func _lineup(v: Variant, path: String) -> Lineup:
	var l := Lineup.new()
	var a := _arr(v, path)
	for i in a.size():
		var e := FleetEntry.new()
		_fill(e, _dict(a[i], "%s[%d]" % [path, i]), "%s[%d]" % [path, i])
		l.entries.append(e)
	return l


func _quick(q: Dictionary) -> QuickBattleDef:
	var o := QuickBattleDef.new()
	o.size_ids = _names(_need(q, "size_ids", "quick_battle"), "quick_battle.size_ids")
	var names := _dict(_need(q, "size_names", "quick_battle"), "quick_battle.size_names")
	for k: Variant in names:
		o.size_names[StringName(str(k))] = str(names[k])
	var df := _dict(_need(q, "defaults", "quick_battle"), "quick_battle.defaults")
	o.default_mine = StringName(str(_need(df, "mine", "quick_battle.defaults")))
	o.default_foe = StringName(str(_need(df, "foe", "quick_battle.defaults")))
	o.default_size = StringName(str(_need(df, "size", "quick_battle.defaults")))
	o.default_difficulty = StringName(str(_need(df, "difficulty", "quick_battle.defaults")))
	o.player_side = StringName(str(_need(q, "player_side", "quick_battle")))
	o.biome = StringName(str(_need(q, "biome", "quick_battle")))
	o.ground_gun = StringName(str(_need(q, "ground_gun", "quick_battle")))
	o.station_on = _names(_need(q, "station_on", "quick_battle"), "quick_battle.station_on")
	var fl := _dict(_need(q, "fleets", "quick_battle"), "quick_battle.fleets")
	for size: Variant in fl:
		var by_clan := _dict(fl[size], "quick_battle.fleets." + str(size))
		for f: Variant in by_clan:
			o.fleets[StringName("%s:%s" % [str(size), str(f)])] = _lineup(by_clan[f], "quick_battle.fleets.%s.%s" % [str(size), str(f)])
	var rs := _dict(_need(q, "reserve", "quick_battle"), "quick_battle.reserve")
	for f: Variant in rs:
		o.reserve[StringName(str(f))] = _lineup(rs[f], "quick_battle.reserve." + str(f))
	return o


## Плоский словарь «путь_через_подчёркивание → значение» из battle_constants.*.value.
static func _flat(prefix: String, v: Variant, out: Dictionary) -> void:
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		for k: Variant in d:
			_flat("%s_%s" % [prefix, str(k)], d[k], out)
	else:
		out[prefix] = v


func _consts(bc: Dictionary) -> BattleConsts:
	var c := BattleConsts.new()
	var flat: Dictionary = {}
	for k: Variant in bc:
		var e := _dict(bc[k], "battle_constants." + str(k))
		if e.has("value"):
			_flat(str(k), e["value"], flat)
	_fill(c, flat, "battle_constants", {}, [], [])
	return c


# ───────────────────────────── доктрина ─────────────────────────────

## v записи доктрины по пути (нет записи — null; отказ скажет вызывающий).
static func _v_of(entries: Dictionary, path: String) -> Variant:
	if not entries.has(path):
		return null
	var e: Dictionary = entries[path]
	return e.get("v")


## Все записи doctrine.json по путям («main.dead_k» → запись). Запись — объект с why.
static func _flatten_doctrine(doc: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	_walk_doctrine(doc, "", out)
	return out


static func _walk_doctrine(node: Dictionary, at: String, out: Dictionary) -> void:
	for k: Variant in node:
		var ks: String = str(k)
		if ks.begins_with("_"):
			continue
		var p := ks if at == "" else "%s.%s" % [at, ks]
		var v: Variant = node[k]
		if typeof(v) != TYPE_DICTIONARY:
			out[p] = {"__stray": v}
			continue
		var d: Dictionary = v
		if d.has("why"):
			out[p] = d
		else:
			_walk_doctrine(d, p, out)


func _build_doctrine(doc: Dictionary) -> void:
	doctrine = Doctrine.new()
	var entries := _flatten_doctrine(doc)
	var by_field: Dictionary = {}
	for p: String in entries:
		var e: Dictionary = entries[p]
		if e.has("__stray"):
			_err("doctrine." + p, "число вне записи — у него нет why (часть 09, 0.1)")
			continue
		if str(e.get("why", "")).strip_edges() == "":
			_err("doctrine." + p, "пустое why")
		if p in DOCTRINE_SPECIAL:
			continue
		by_field[p.replace(".", "_")] = p
	for p: Dictionary in doctrine.get_property_list():
		var usage: int = p["usage"]
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var pname: String = p["name"]
		if pname in ["sec_mounts", "ecm_main_slow_default"]:
			continue
		if not by_field.has(pname):
			_err("doctrine", "нет записи для поля %s (ждали «%s»)" % [pname, pname.replace("_", ".")])
			continue
		var path: String = by_field[pname]
		by_field.erase(pname)
		var val: Variant = _doctrine_value(entries, path, 0)
		if val == null:
			continue
		var ptype: int = p["type"]
		var conv: Variant = _conv(val, ptype, "doctrine." + path)
		if conv != null:
			doctrine.set(pname, conv)
	for f: String in by_field:
		_err("doctrine." + str(by_field[f]), "запись загрузчику неизвестна — заведи поле %s в Doctrine (sim/defs.gd)" % f)
	var mounts := _dict(_v_of(entries, "sec.mounts"), "doctrine.sec.mounts")
	for id: Variant in mounts:
		var n: Variant = _conv(mounts[id], TYPE_INT, "doctrine.sec.mounts." + str(id))
		if n != null:
			var ni: int = n
			doctrine.sec_mounts[StringName(str(id))] = ni
	var ms := _dict(_v_of(entries, "ecm.main_slow"), "doctrine.ecm.main_slow")
	doctrine.ecm_main_slow_default = _num(ms, "default", "doctrine.ecm.main_slow")
	for sp: String in DOCTRINE_SPECIAL:
		if not entries.has(sp):
			_err("doctrine", "нет записи %s" % sp)


func _doctrine_value(entries: Dictionary, path: String, depth: int) -> Variant:
	var e: Dictionary = entries[path]
	if e.has("ref"):
		var target: String = str(e["ref"])
		if depth > 4 or not entries.has(target):
			_err("doctrine." + path, "ref «%s» — такой записи нет" % target)
			return null
		return _doctrine_value(entries, target, depth + 1)
	if e.has("v"):
		return e["v"]
	if e.has("rule"):
		return e["rule"]
	_err("doctrine." + path, "у записи нет ни v, ни ref, ни rule")
	return null
