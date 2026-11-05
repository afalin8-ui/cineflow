class_name Defs
## Все числа игры в одном месте. Расстояния — метры, время — секунды.
## Правишь баланс — правь здесь, логика боя чисел не знает.

# Классы целей для таблицы «кто кого бьёт».
const T_CRAFT := 0     # истребители
const T_BOMBER := 1    # бомбардировщики
const T_SMALL := 2     # разведчики, корветы, харвестеры
const T_FRIGATE := 3
const T_BIG := 4       # крейсеры, носители, флагманы
const T_STATION := 5

# Эффективность оружия по классу цели: множитель и к попаданию, и к урону.
const EFF := {
	"gun":     [1.0, 1.3, 0.35, 0.15, 0.06, 0.05],  # пушки истребителей
	"intc":    [1.4, 1.6, 0.3, 0.1, 0.05, 0.05],    # перехватчик
	"flak":    [1.4, 1.5, 0.3, 0.12, 0.05, 0.05],   # зенитки
	"laser":   [0.2, 0.25, 1.0, 1.0, 0.7, 0.5],     # средний калибр фрегатов
	"heavy":   [0.03, 0.03, 0.9, 1.2, 0.8, 0.8],    # батареи крейсеров
	"main":    [0.0, 0.0, 0.5, 0.9, 1.3, 1.5],      # главный калибр
	"torpedo": [0.0, 0.0, 0.25, 0.7, 1.5, 1.4],     # торпеды (снаряд, глушится РЭБ)
	"missile": [0.15, 0.15, 1.0, 0.7, 0.9, 0.8],    # ракеты Шерманов (снаряд)
}

const CLS_TARGET := {
	"craft": T_CRAFT, "bomber": T_BOMBER, "scout": T_SMALL, "corvette": T_SMALL,
	"harvester": T_SMALL, "frigate": T_FRIGATE, "cruiser": T_BIG, "carrier": T_BIG,
	"capital": T_BIG, "station": T_STATION,
}

# Пояса дистанции (для проверки «не свалка» и для поведения).
const BIG_MIN_RANGE := 3000.0
const DMG_K := 2.0   # общий множитель урона: двигает длительность боя
# Тяжесть залпа по классу оружия. Крупный калибр бьёт РЕДКО и БОЛЬНО:
# корвет гибнет с одного залпа крейсера, крупный корабль — за 6–8 залпов
# один на один. Пушки истребителей и зенитки — как были: они берут числом.
const CLS_K := {"heavy": 6.0, "main": 3.0, "torpedo": 2.0, "missile": 1.5, "laser": 3.0,
	"gun": 1.0, "intc": 1.0, "flak": 1.0}

const START_ORE := 1500
const FLEET_CAP := [0, 40, 60, 90, 120]          # по уровню станции
const STATION_INCOME := [0, 4.0, 6.0, 8.0, 10.0] # руды в секунду
const STATION_UPGRADE := [0, 0, 900, 1900, 3200]
const STATION_UPGRADE_TIME := [0, 0, 40, 60, 80]
const LIMIT_BIG := 5        # крупных (крейсер, носитель) на сторону
const LIMIT_CAPITAL := 1    # флагман

const HARVEST_CAP := 400
const HARVEST_RATE := 25.0  # руды в секунду при добыче
const FIELD_ORE := 14000

const RETREAT_CHARGE := 20.0   # зарядка гиперпрыжка
const HYPER_TIME := 12.0       # сколько корабль в гиперпространстве до возврата к станции
const NEBULA_SIGHT := 2500.0   # внутри туманности видно только вблизи
const SQUAD_REPLACE := 25.0    # время восполнения звена

static var _ships := {}

static func ship(id: String) -> Dictionary:
	if _ships.is_empty():
		_build()
	return _ships[id]

static func all_ids() -> Array:
	if _ships.is_empty():
		_build()
	return _ships.keys()

static func faction_ids(fac: String) -> Array:
	var out := []
	for id in all_ids():
		var d: Dictionary = _ships[id]
		if d.fac == fac and d.buildable:
			out.append(id)
	return out

static func fac_name(fac: String) -> String:
	return "Тройден" if fac == "troyden" else "Плэктор"

static func harvester_of(fac: String) -> String:
	return "campbell" if fac == "troyden" else "tolstyak"

static func station_of(fac: String) -> String:
	return "station_t" if fac == "troyden" else "station_p"

# w(класс, урон, перезарядка, мин, макс, точность, хардпоинт, дуга, выстрелов)
static func w(cls: String, dmg: float, cd: float, rmin: float, rmax: float, acc: float, hp := "", arc := 360.0, shots := 1) -> Dictionary:
	return {"cls": cls, "dmg": dmg * DMG_K * CLS_K.get(cls, 1.0), "cd": cd, "min": rmin, "max": rmax, "acc": acc, "hp": hp, "arc": arc, "shots": shots}

static func hp(id: String, kind: String, v: float, label: String) -> Dictionary:
	return {"id": id, "kind": kind, "max": v, "label": label}

static func _add(d: Dictionary) -> void:
	var base := {
		"shield": 0.0, "regen": 0.0, "armor": 0.0, "turn": 90.0, "reverse": 0.5,
		"sensor": 8000.0, "hps": [], "weapons": [], "abil": [], "bays": 0, "start_sq": 0,
		"sq_types": [], "squad_n": 1, "repair": 0.0, "repair_r": 0.0, "ecm": "", "ecm_r": 0.0,
		"buildable": true, "lvl": 1, "pts": 1, "cost": 100, "build": 20.0, "sees_nebula": false,
		"limit": 0, "self_build": false,
	}
	for k in d:
		base[k] = d[k]
	_ships[base.id] = base

static func _build() -> void:
	# ---------------- ТРОЙДЕН ----------------
	_add({"id": "slider", "name": "Слайдер", "fac": "troyden", "cls": "craft", "size": 18.0,
		"squad_n": 4, "hull": 80.0, "speed": 520.0, "turn": 220.0, "sensor": 5000.0,
		"weapons": [w("gun", 7, 0.5, 0, 1200, 0.7)], "abil": ["boost"],
		"cost": 120, "pts": 1, "build": 25.0, "buildable": false})
	_add({"id": "palarmo", "name": "Палармо", "fac": "troyden", "cls": "bomber", "size": 30.0,
		"squad_n": 3, "hull": 190.0, "speed": 330.0, "turn": 120.0, "sensor": 5000.0,
		"weapons": [w("torpedo", 300, 9.0, 0, 1500, 0.9)], "abil": ["torp_salvo"],
		"cost": 220, "pts": 2, "build": 35.0, "buildable": false})
	_add({"id": "tracer", "name": "Трейсер", "fac": "troyden", "cls": "scout", "size": 40.0,
		"hull": 600.0, "shield": 400.0, "regen": 15.0, "speed": 420.0, "turn": 90.0,
		"sensor": 20000.0, "sees_nebula": true,
		"weapons": [w("gun", 6, 0.6, 0, 1200, 0.6)], "abil": ["scan"],
		"cost": 150, "pts": 1, "build": 15.0, "lvl": 1})
	_add({"id": "warden", "name": "Уорден", "fac": "troyden", "cls": "corvette", "size": 150.0,
		"hull": 1500.0, "shield": 1400.0, "regen": 30.0, "speed": 300.0, "turn": 50.0,
		"hps": [hp("proj", "shieldproj", 600, "щит-проектор"), hp("flak", "weapon", 600, "зенитки")],
		"weapons": [w("flak", 9, 0.35, 0, 2500, 0.6, "flak", 360, 2)], "abil": ["shield_ally"],
		"cost": 420, "pts": 3, "build": 20.0, "lvl": 1})
	_add({"id": "silencer", "name": "Сайленсер", "fac": "troyden", "cls": "corvette", "size": 200.0,
		"hull": 1700.0, "shield": 1600.0, "regen": 30.0, "speed": 280.0, "turn": 45.0,
		"hps": [hp("ant", "ecm", 700, "антенна РЭБ")],
		"weapons": [w("laser", 20, 2.0, 0, 4000, 0.7)], "ecm": "jam", "ecm_r": 4000.0,
		"abil": ["wide_jam"], "cost": 520, "pts": 3, "build": 25.0, "lvl": 2})
	_add({"id": "dixon", "name": "Диксон", "fac": "troyden", "cls": "frigate", "size": 400.0,
		"hull": 4200.0, "shield": 3200.0, "regen": 45.0, "armor": 0.1, "speed": 220.0, "turn": 22.0,
		"hps": [hp("guns", "weapon", 1500, "орудия"), hp("eng", "engine", 1200, "двигатели")],
		"weapons": [w("laser", 48, 2.0, 0, 6000, 0.8, "guns", 360, 2), w("flak", 7, 0.5, 0, 2000, 0.5)],
		"abil": ["shield_boost"], "cost": 650, "pts": 4, "build": 30.0, "lvl": 2})
	_add({"id": "howard", "name": "Ховард", "fac": "troyden", "cls": "cruiser", "size": 1200.0,
		"hull": 11000.0, "shield": 7000.0, "regen": 70.0, "armor": 0.1, "speed": 120.0, "turn": 6.0,
		"reverse": 0.6, "sensor": 14000.0,
		"hps": [hp("sh", "shieldgen", 2500, "генератор щита"), hp("eng", "engine", 2500, "двигатели"),
			hp("b1", "weapon", 2500, "батарея 1"), hp("b2", "weapon", 2500, "батарея 2")],
		"weapons": [w("heavy", 150, 4.0, 3000, 13000, 0.75, "b1"), w("heavy", 150, 4.0, 3000, 13000, 0.75, "b2")],
		"abil": ["hp_volley"], "cost": 1500, "pts": 8, "build": 50.0, "lvl": 3})
	_add({"id": "hunter", "name": "Хантер", "fac": "troyden", "cls": "carrier", "size": 1400.0,
		"hull": 12000.0, "shield": 7000.0, "regen": 70.0, "armor": 0.1, "speed": 110.0, "turn": 6.0,
		"reverse": 0.6, "sensor": 14000.0,
		"hps": [hp("hang", "hangar", 3000, "ангар"), hp("sh", "shieldgen", 2500, "генератор щита"),
			hp("eng", "engine", 2500, "двигатели"), hp("dock", "dock", 2000, "ремонтный док")],
		"weapons": [w("flak", 8, 0.5, 0, 2500, 0.5, "", 360, 2)],
		"bays": 5, "start_sq": 4, "sq_types": ["slider", "palarmo", "slider", "palarmo", "slider"],
		"repair": 60.0, "repair_r": 3000.0, "abil": ["repair_surge"],
		"cost": 1700, "pts": 9, "build": 55.0, "lvl": 3})
	_add({"id": "grosser", "name": "Гроссер", "fac": "troyden", "cls": "cruiser", "size": 1800.0,
		"hull": 14000.0, "shield": 8000.0, "regen": 70.0, "armor": 0.15, "speed": 90.0, "turn": 5.0,
		"reverse": 0.6, "sensor": 15000.0,
		"hps": [hp("main", "weapon", 3500, "главный калибр"), hp("sh", "shieldgen", 3000, "генератор щита"),
			hp("eng", "engine", 3000, "двигатели")],
		"weapons": [w("main", 650, 6.0, 4000, 15000, 0.85, "main", 70.0),
			w("flak", 8, 0.45, 0, 2500, 0.55, "", 360, 2)],
		"abil": ["siege"], "cost": 2100, "pts": 10, "build": 65.0, "lvl": 4})
	_add({"id": "lancelot", "name": "Ланселот", "fac": "troyden", "cls": "capital", "size": 2500.0,
		"hull": 30000.0, "shield": 14000.0, "regen": 120.0, "armor": 0.15, "speed": 85.0, "turn": 4.0,
		"reverse": 0.6, "sensor": 16000.0, "limit": 1,
		"hps": [hp("reac", "reactor", 5000, "реактор"), hp("main", "weapon", 4000, "главный калибр"),
			hp("sh1", "shieldgen", 3500, "щит 1"), hp("sh2", "shieldgen", 3500, "щит 2"),
			hp("eng", "engine", 4000, "двигатели"), hp("hang", "hangar", 3000, "ангар")],
		"weapons": [w("heavy", 160, 4.0, 3000, 13000, 0.75, "main"), w("heavy", 160, 4.0, 3000, 13000, 0.75, "main"),
			w("flak", 8, 0.5, 0, 2500, 0.5, "", 360, 2)],
		"bays": 2, "start_sq": 2, "sq_types": ["slider", "palarmo"],
		"abil": ["main_shot"], "cost": 4000, "pts": 15, "build": 90.0, "lvl": 4})
	_add({"id": "campbell", "name": "Кэмпбелл", "fac": "troyden", "cls": "harvester", "size": 120.0,
		"hull": 1500.0, "shield": 600.0, "regen": 15.0, "speed": 250.0, "turn": 60.0,
		"cost": 350, "pts": 1, "build": 18.0, "lvl": 1})
	_add({"id": "station_t", "name": "Станция Тройдена", "fac": "troyden", "cls": "station", "size": 1600.0,
		"hull": 40000.0, "shield": 10000.0, "regen": 60.0, "armor": 0.2, "speed": 0.0, "turn": 0.0,
		"sensor": 15000.0, "buildable": false,
		"hps": [hp("hang", "hangar", 5000, "ангар"), hp("sh", "shieldgen", 4500, "генератор щита"),
			hp("b1", "weapon", 4000, "батарея 1"), hp("b2", "weapon", 4000, "батарея 2")],
		"weapons": [w("heavy", 70, 4.0, 0, 10000, 0.75, "b1"), w("heavy", 70, 4.0, 0, 10000, 0.75, "b2"),
			w("flak", 9, 0.35, 0, 2500, 0.6, "", 360, 3)],
		"bays": 3, "start_sq": 3, "sq_types": ["slider", "palarmo", "slider", "palarmo", "slider", "palarmo"],
		"repair": 80.0, "repair_r": 5000.0})

	# ---------------- ПЛЭКТОР ----------------
	_add({"id": "bronco", "name": "Бронко", "fac": "plector", "cls": "craft", "size": 15.0,
		"squad_n": 6, "hull": 50.0, "speed": 540.0, "turn": 230.0, "sensor": 5000.0,
		"weapons": [w("gun", 5, 0.5, 0, 1100, 0.65)], "abil": ["boost"],
		"cost": 70, "pts": 1, "build": 20.0, "buildable": false})
	_add({"id": "drakkar", "name": "Драккар", "fac": "plector", "cls": "craft", "size": 16.0,
		"squad_n": 4, "hull": 60.0, "speed": 620.0, "turn": 260.0, "sensor": 5000.0,
		"weapons": [w("intc", 7, 0.45, 0, 1100, 0.7)], "abil": ["dash"],
		"cost": 90, "pts": 1, "build": 20.0, "buildable": false})
	_add({"id": "sherman", "name": "Шерман", "fac": "plector", "cls": "bomber", "size": 22.0,
		"squad_n": 6, "hull": 75.0, "speed": 380.0, "turn": 150.0, "sensor": 5000.0,
		"weapons": [w("missile", 55, 6.0, 0, 1500, 0.85)], "abil": ["missile_salvo"],
		"cost": 110, "pts": 1, "build": 25.0, "buildable": false})
	_add({"id": "ogr", "name": "Огр", "fac": "plector", "cls": "corvette", "size": 120.0,
		"hull": 1300.0, "shield": 200.0, "regen": 5.0, "armor": 0.3, "speed": 310.0, "turn": 55.0,
		"hps": [hp("flak", "weapon", 500, "зенитки")],
		"weapons": [w("flak", 8, 0.35, 0, 2500, 0.6, "flak", 360, 3)], "abil": ["barrage"],
		"cost": 220, "pts": 2, "build": 14.0, "lvl": 1})
	_add({"id": "garpia", "name": "Гарпия", "fac": "plector", "cls": "corvette", "size": 180.0,
		"hull": 1400.0, "shield": 200.0, "regen": 5.0, "armor": 0.25, "speed": 290.0, "turn": 50.0,
		"hps": [hp("ant", "ecm", 600, "антенна РЭБ")],
		"weapons": [w("laser", 16, 2.0, 0, 3500, 0.65)], "ecm": "spoof", "ecm_r": 4000.0,
		"abil": ["decoys"], "cost": 320, "pts": 2, "build": 18.0, "lvl": 2})
	_add({"id": "troll", "name": "Тролль", "fac": "plector", "cls": "frigate", "size": 350.0,
		"hull": 3400.0, "shield": 500.0, "regen": 10.0, "armor": 0.3, "speed": 240.0, "turn": 28.0,
		"hps": [hp("guns", "weapon", 1200, "орудия"), hp("eng", "engine", 1000, "двигатели")],
		"weapons": [w("laser", 42, 1.8, 0, 4500, 0.8, "guns", 360, 2)], "abil": ["ram"],
		"cost": 360, "pts": 2, "build": 20.0, "lvl": 2})
	_add({"id": "norman", "name": "Норман", "fac": "plector", "cls": "frigate", "size": 700.0,
		"hull": 5200.0, "shield": 600.0, "regen": 10.0, "armor": 0.3, "speed": 160.0, "turn": 12.0,
		"hps": [hp("hang", "hangar", 1800, "ангар"), hp("eng", "engine", 1500, "двигатели")],
		"weapons": [w("flak", 7, 0.5, 0, 2000, 0.5)],
		"bays": 3, "start_sq": 2, "sq_types": ["bronco", "sherman", "bronco"], "self_build": true,
		"abil": ["emergency_launch"], "cost": 900, "pts": 4, "build": 30.0, "lvl": 2})
	_add({"id": "ork", "name": "Орк", "fac": "plector", "cls": "carrier", "size": 1300.0,
		"hull": 12500.0, "shield": 1200.0, "regen": 15.0, "armor": 0.4, "speed": 110.0, "turn": 6.0,
		"reverse": 0.6, "sensor": 14000.0,
		"hps": [hp("h1", "hangar", 3000, "ангар 1"), hp("h2", "hangar", 3000, "ангар 2"),
			hp("eng", "engine", 2500, "двигатели")],
		"weapons": [w("flak", 8, 0.45, 0, 2500, 0.55, "", 360, 2)],
		"bays": 6, "start_sq": 5, "sq_types": ["bronco", "sherman", "drakkar", "sherman", "bronco", "sherman"], "self_build": true,
		"abil": ["armor_hangars"], "cost": 1650, "pts": 7, "build": 45.0, "lvl": 3})
	_add({"id": "whiteshark", "name": "Уайт Шарк", "fac": "plector", "cls": "cruiser", "size": 1500.0,
		"hull": 14500.0, "shield": 1500.0, "regen": 15.0, "armor": 0.4, "speed": 125.0, "turn": 7.0,
		"reverse": 0.6, "sensor": 13000.0,
		"hps": [hp("b1", "weapon", 2800, "батарея 1"), hp("b2", "weapon", 2800, "батарея 2"),
			hp("eng", "engine", 2800, "двигатели")],
		"weapons": [w("heavy", 125, 4.0, 2000, 10000, 0.72, "b1"), w("heavy", 125, 4.0, 2000, 10000, 0.72, "b2")],
		"abil": ["engine_power"], "cost": 1400, "pts": 6, "build": 45.0, "lvl": 3})
	_add({"id": "goliath", "name": "Голиаф", "fac": "plector", "cls": "capital", "size": 2200.0,
		"hull": 27000.0, "shield": 3000.0, "regen": 25.0, "armor": 0.4, "speed": 85.0, "turn": 4.0,
		"reverse": 0.6, "sensor": 15000.0, "limit": 1,
		"hps": [hp("h1", "hangar", 3500, "ангар 1"), hp("h2", "hangar", 3500, "ангар 2"),
			hp("main", "weapon", 4000, "главный калибр"), hp("e1", "engine", 3000, "двигатель 1"),
			hp("e2", "engine", 3000, "двигатель 2")],
		"weapons": [w("main", 1100, 22.0, 3000, 12000, 0.85, "main", 20.0), w("flak", 8, 0.45, 0, 2500, 0.55, "", 360, 3)],
		"bays": 6, "start_sq": 6, "sq_types": ["bronco", "sherman", "drakkar", "sherman", "bronco", "sherman"], "self_build": true,
		"abil": ["launch_all"], "cost": 4300, "pts": 12, "build": 80.0, "lvl": 4})
	_add({"id": "tolstyak", "name": "Толстяк", "fac": "plector", "cls": "harvester", "size": 140.0,
		"hull": 1900.0, "shield": 100.0, "regen": 5.0, "armor": 0.3, "speed": 230.0, "turn": 55.0,
		"cost": 300, "pts": 1, "build": 15.0, "lvl": 1})
	_add({"id": "station_p", "name": "Станция Плэктора", "fac": "plector", "cls": "station", "size": 1600.0,
		"hull": 46000.0, "shield": 3000.0, "regen": 20.0, "armor": 0.3, "speed": 0.0, "turn": 0.0,
		"sensor": 15000.0, "buildable": false,
		"hps": [hp("h1", "hangar", 5000, "ангар 1"), hp("h2", "hangar", 5000, "ангар 2"),
			hp("b1", "weapon", 4000, "батарея 1"), hp("b2", "weapon", 4000, "батарея 2")],
		"weapons": [w("heavy", 65, 4.0, 0, 9500, 0.72, "b1"), w("heavy", 65, 4.0, 0, 9500, 0.72, "b2"),
			w("flak", 8, 0.35, 0, 2500, 0.6, "", 360, 4)],
		"bays": 4, "start_sq": 3, "sq_types": ["bronco", "sherman", "bronco", "drakkar", "sherman", "bronco"],
		"self_build": true, "repair": 80.0, "repair_r": 5000.0})

const ABIL := {
	"boost": {"name": "Форсаж", "cd": 30.0, "dur": 6.0},
	"dash": {"name": "Рывок", "cd": 25.0, "dur": 4.0},
	"torp_salvo": {"name": "Торпедный залп", "cd": 40.0, "dur": 0.0},
	"missile_salvo": {"name": "Ракетный залп", "cd": 35.0, "dur": 0.0},
	"scan": {"name": "Дальний скан", "cd": 45.0, "dur": 12.0},
	"shield_ally": {"name": "Щит на союзника", "cd": 30.0, "dur": 12.0},
	"wide_jam": {"name": "Широкий глушитель", "cd": 45.0, "dur": 15.0},
	"shield_boost": {"name": "Энергия в щиты", "cd": 35.0, "dur": 8.0},
	"hp_volley": {"name": "Залп по хардпоинту", "cd": 40.0, "dur": 9.0},
	"repair_surge": {"name": "Ремонт рядом", "cd": 50.0, "dur": 12.0},
	"siege": {"name": "Осадный режим", "cd": 5.0, "dur": 0.0},
	"main_shot": {"name": "Главный калибр", "cd": 60.0, "dur": 0.0},
	"barrage": {"name": "Заградительный огонь", "cd": 35.0, "dur": 8.0},
	"decoys": {"name": "Ложные цели", "cd": 40.0, "dur": 10.0},
	"ram": {"name": "Таран", "cd": 45.0, "dur": 6.0},
	"emergency_launch": {"name": "Срочный выпуск", "cd": 60.0, "dur": 0.0},
	"armor_hangars": {"name": "Бронирование ангаров", "cd": 45.0, "dur": 12.0},
	"engine_power": {"name": "Энергия в двигатели", "cd": 40.0, "dur": 10.0},
	"launch_all": {"name": "Выпуск всех звеньев", "cd": 90.0, "dur": 0.0},
}

static func is_big(cls: String) -> bool:
	return cls == "cruiser" or cls == "carrier" or cls == "capital"

static func is_squad(cls: String) -> bool:
	return cls == "craft" or cls == "bomber"
