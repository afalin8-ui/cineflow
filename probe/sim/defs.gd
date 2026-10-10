## Числа боя: загрузка из space_data.json + doctrine.json в типизированные описания.
## Без узлов. Загружается один раз, дальше только читается.
extends RefCounted

const CLS := {"capital": 0, "carrier": 1, "escort": 2, "strike": 3, "torpedo": 4}
const CAPITAL := 0
const CARRIER := 1
const ESCORT := 2
const STRIKE := 3
const TORPEDO := 4

class WeaponDef:
	var role: StringName      # main / sec / light / missile
	var key: StringName       # строка таблицы урона: heavy / sec / light / missile
	var dmg: float
	var cd: float
	var rng: float
	var dead: float           # мёртвая зона (0 — нет)
	var mounts: int = 1
	var salvo: int = 0

class ShipDef:
	var id: StringName
	var cls: int
	var hp: float
	var armor: float
	var max_speed: float
	var thrust: float
	var turn: float
	var radius: float
	var hull: float
	var weapons: Array[WeaponDef] = []
	var main: WeaponDef = null    # по РОЛИ, а не guns[0] (09, 1.1)
	var sec: WeaponDef = null
	var light: WeaponDef = null
	var missile: WeaponDef = null
	var pd_count: int
	var pd_dmg: float
	var pd_cd: float
	var pd_range: float
	var hangar: int
	var flee: float

class CraftDef:
	var role: StringName
	var hp: float
	var armor: float
	var max_speed: float
	var thrust: float
	var turn: float
	var missile: bool
	var key: StringName
	var dmg: float
	var cd: float
	var rng: float
	var ammo: int
	var reloads: int
	var reload_time: float
	var miss: float
	var m_speed: float
	var m_hp: float

var raw: Dictionary
var doctrine: Dictionary
var dmg_table: Dictionary = {}     # key -> PackedFloat32Array[5]
var ships: Dictionary = {}         # клан -> {id -> ShipDef}
var craft: Dictionary = {}         # клан -> {роль -> CraftDef}
var squad_size: Dictionary = {}

static func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("нет файла " + path)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func load_all(data_path := "res://data/space_data.json", doc_path := "res://data/doctrine.json") -> void:
	raw = load_json(data_path)
	doctrine = load_json(doc_path)
	var tbl: Dictionary = raw["space_dmg"].duplicate(true)
	for k in doctrine.get("space_dmg", {}):
		var row: Dictionary = tbl.get(k, {})
		row.merge(doctrine["space_dmg"][k], true)
		tbl[k] = row
	for k in tbl:
		var a := PackedFloat32Array([0, 0, 0, 0, 0])
		for c in CLS:
			a[CLS[c]] = float(tbl[k].get(c, 1.0))
		dmg_table[StringName(k)] = a
	var hulls: Dictionary = raw["model_len"]["hull"]
	var doc_sec: Dictionary = doctrine["sec"]
	var dead_k: float = doctrine["main"]["dead_k"]
	var clan_mod: Dictionary = doctrine["clan_gun_mod"]
	for clan in raw["ships"]:
		var by_id := {}
		for s in raw["ships"][clan]:
			by_id[StringName(s["id"])] = _ship(s, hulls, dead_k, doc_sec, clan_mod.get(clan, {"gun": 1.0, "cd": 1.0}))
		ships[clan] = by_id
		var cr := {}
		for role in raw["strike"][clan]:
			cr[StringName(role)] = _craft(raw["strike"][clan][role])
		craft[clan] = cr
		squad_size[clan] = int(raw["squad_size"].get(clan, raw["squad_size_default"]))
	var tsp: float = doctrine["torp"]["speed"]
	for clan in craft:
		craft[clan][&"bomber"].m_speed = tsp

func _ship(s: Dictionary, hulls: Dictionary, dead_k: float, doc_sec: Dictionary, mod: Dictionary) -> ShipDef:
	var d := ShipDef.new()
	d.id = StringName(s["id"])
	d.cls = CLS[s["cls"]]
	d.hp = s["hp"]
	d.armor = s["armor"]
	d.max_speed = s["maxSpeed"]
	d.thrust = s["thrust"]
	d.turn = s["turn"]
	d.radius = s["radius"]
	d.hull = hulls.get(s["id"], s["radius"] * 1.6)
	d.flee = s.get("flee", 0.0)
	d.hangar = int(s["hangar"]) if s.get("hangar") != null else 0
	for g in s["guns"]:
		var w := WeaponDef.new()
		w.key = StringName(g["type"])
		w.dmg = g["dmg"]; w.cd = g["cd"]; w.rng = g["range"]
		match g["type"]:
			"heavy":
				w.role = &"main"; w.dead = g["range"] * dead_k
				if d.main == null:
					d.main = w
				else:
					d.main.mounts += 1   # вторая башня флагмана — та же роль, свой таймер
					continue
			"missile":
				w.role = &"missile"; w.salvo = 3; d.missile = w
			_:
				w.role = &"light"; d.light = w
		d.weapons.append(w)
	if d.main != null and doc_sec["mounts"].has(String(d.id)):
		var w := WeaponDef.new()
		w.role = &"sec"; w.key = &"sec"
		w.mounts = doc_sec["mounts"][String(d.id)]
		w.dmg = roundf(doc_sec["dmg"] * mod["gun"])
		w.cd = snappedf(doc_sec["cd"] * mod["cd"], 0.01)
		w.rng = d.main.rng * doc_sec["range_k"]
		d.sec = w
		d.weapons.append(w)
	var pd: Dictionary = s["pd"]
	d.pd_count = pd["count"]; d.pd_dmg = pd["dmg"]; d.pd_cd = pd["cd"]; d.pd_range = pd["range"]
	return d

func _craft(c: Dictionary) -> CraftDef:
	var d := CraftDef.new()
	d.role = StringName(c["role"])
	d.hp = c["hp"]; d.armor = c["armor"]
	d.max_speed = c["maxSpeed"]; d.thrust = c["thrust"]; d.turn = c["turn"]
	d.missile = c["weaponKind"] == "missile"
	d.key = StringName(c["weapon"])
	d.dmg = c["dmg"]; d.cd = c["cd"]; d.rng = c["range"]
	d.ammo = c.get("ammo", 0); d.reloads = c.get("reloads", 0); d.reload_time = c.get("reloadTime", 0)
	d.miss = c.get("missChance", 0); d.m_speed = c.get("missileSpeed", 120); d.m_hp = c.get("missileHp", 24)
	return d

func mult(key: StringName, cls: int) -> float:
	return dmg_table[key][cls]
