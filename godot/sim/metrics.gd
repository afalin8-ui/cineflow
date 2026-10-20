# sim/metrics.gd — замеры боя (архитектура, 2.3; доктрина 09, раздел 8). С G2:
# - урон по КЛЮЧУ оружия и по КЛАССУ цели, без остатка (М7; 09, 9.5 п. 11):
#   главный калибр (heavy), батарея (sec), лёгкие (light), ракетный пакет (missile),
#   ПВО (pd), авиация (gunInt, gunFig, torp — G3) и планета (planet) — отдельной
#   строкой; урон по снарядам (класс torpedo) — тоже отдельно, это «сбитые ракеты»
#   ПВО, а не урон по кораблям (03, 7.2 п. 9);
# - журнал «почему главный калибр не выстрелил» (03, 7.5; план G2, п. 8): у готового
#   главного калибра каждый шаг без выстрела — с причиной; это первый шаг порядка
#   поиска ошибки доктрины (09, 8.4: «кто почему не стрелял»);
# - темп: первое попадание по кораблю (не с планеты) и первый выстрел главного
#   калибра по кораблю (М11; 03, ловушка 34);
# - авиация (G3; 09, 4.7 и 8.2): урон машин по ключам gunInt / gunFig / torp (М7),
#   урон по кораблям на поднятое звено и доля сбитых звеньев (М8), «машина-секунды»
#   в середине (М5: проекция машины на ось своей стороны −100 ≤ p ≤ L + 100, без
#   взлёта и посадки — 250 от своего носителя).
# - доктрина тяжёлых и строй (G4; 09, 8.1–8.2): фазы боя (марш — до первого выстрела главного
#   калибра по кораблю; бой — до первого отхода стороны или конца; развязка), М1 (тяжёлые
#   в поясе), М2 (вплотную, с эпизодами), М3 (расстояние между линиями), М4 (лёгкие между
#   линиями), М6 (отход — не бегство), М9 (входы «свой в чужом», пары тяжёлых ближе 360),
#   М10 (строй ИИ держится: до своего места). Сами шаги замера — в battle.gd
#   (_sample_lines): метрикам нельзя грузить состояние боя (кольцо preload). Журнал смен
#   состояния пояса — battle.belt_log. Сводка — summary() одной строкой JSON (стенд).
# - часть 2 (G5; 09, 8.2): М7 доли урона по источникам за бой, М8 урон авиации на поднятое
#   звено и доля сбитых, М11 самый долгий промежуток без урона по кораблям после первого
#   попадания, М12 доля тяжёлый-секунд под чужими помехами и доля готового времени главного
#   калибра, сорванного помехами (журнал причин); М13 — победы, считает tools/summarize.py по
#   итогам боёв. Отчёт боя одной строкой JSON — sim/report.gd (стенд и бой человека — один).
extends RefCounted

## Причины молчания готового главного калибра (03, 7.5) — по порядку проверок выстрела.
const REASONS: Array[StringName] = [&"no_target", &"too_far", &"dead_zone", &"cone", &"jam", &"blind"]
const REASON_TEXT := {
	&"no_target": "нет цели", &"too_far": "дальше дальности", &"dead_zone": "мёртвая зона",
	&"cone": "вне конуса", &"jam": "помехи", &"blind": "ослепление",
}
## Ключи урона в отчёте — по порядку строки «урон по источникам».
const KEYS: Array[StringName] = [&"heavy", &"sec", &"light", &"missile", &"pd", &"gunInt", &"gunFig", &"torp", &"planet"]
const KEY_TEXT := {
	&"heavy": "главный калибр", &"sec": "батареи", &"light": "лёгкие", &"missile": "ракеты «Синхо»",
	&"pd": "ПВО", &"gunInt": "перехватчики", &"gunFig": "истребители", &"torp": "торпеды", &"planet": "планета",
}
const TORPEDO_CLS := 4                 # столбец «torpedo» в таблице урона (Defs.CLASSES)
const STRIKE_CLS := 3                  # столбец «strike» — машины
## Ключи урона авиации (М7, М8).
const AIR_KEYS: Array[StringName] = [&"gunInt", &"gunFig", &"torp"]
## М5 (09, 8.2): «в середине» — от 100 позади своей линии до 100 за чужой; машины ближе
## 250 к своему носителю — взлёт и посадка, не считаются.
const M5_BACK := 100.0
const M5_OVER := 100.0
const M5_HOME := 250.0

## Урон по [сторона-источник][ключ] → по классу цели (5 столбцов Defs.CLASSES).
## Планета — сторона защитника (она его оборона), ключ &"planet".
var dmg: Array[Dictionary] = [{}, {}]
## Секунды молчания готового главного калибра по причинам: [сторона][причина].
var idle: Array[Dictionary] = [{}, {}]
## Выстрелы главного калибра (по сторонам) — знаменатель для долей причин.
var main_shots: PackedInt32Array = PackedInt32Array([0, 0])
var first_hit := 0.0
var first_gun := 0.0
## М11: часы боя на этом шаге (battle → step), последний урон по кораблям не с планеты
## после первого попадания и самый долгий промежуток без него.
var now := 0.0
var last_hit := -1.0
var max_gap := 0.0
## М12: тяжёлый-секунды фазы «бой» под чужими помехами (09, 8.2).
var m12_jam_s := 0.0
## М5: машина-секунды в воздухе (без взлёта и посадки) и из них — в середине; [сторона].
var craft_s := PackedFloat64Array([0.0, 0.0])
var craft_mid_s := PackedFloat64Array([0.0, 0.0])

# ── доктрина тяжёлых и строй (G4; 09, 8.2) ──
## Фазы боя (09, 8.1): 0 марш, 1 бой, 2 развязка; когда начался и кончился бой.
var phase := 0
var fight_t0 := -1.0
var fight_t1 := -1.0
## Тяжёлый-секунды в фазе «бой» и из них: цель главного калибра в поясе (М1), чужой
## корабль ближе мёртвой зоны (М2), в отходе (М6).
var heavy_s := 0.0
var m1_s := 0.0
var m2_s := 0.0
var m6_s := 0.0
## Эпизоды М2 и М6 (длины, с) и их начала по uid.
var m2_eps := PackedFloat64Array()
var m6_eps := PackedFloat64Array()
var m2_run: Dictionary[int, float] = {}
var m6_run: Dictionary[int, float] = {}
## М3: L(t) между центрами тяжёлых двух сторон, по шагам фазы «бой»; R_line — наименьшая
## дальность главного калибра тяжёлых обеих линий; шаги с L < M3_FLOOR.
var m3 := PackedFloat64Array()
var r_line := INF
var m3_short := 0
## М4: лёгкий-секунды (корвет, фрегат, РЭБ; не побитые) в фазе «бой»: между линиями
## (0 ≤ p ≤ L) и за своими тяжёлыми (p < −M4_BEHIND).
var light_s := 0.0
var m4_mid_s := 0.0
var m4_back_s := 0.0
## М6: смещение центра своей линии назад за фазу «бой» (сумма шагов назад по оси стороны),
## тяжёлые-шаги за тыловым рубежом и ближе retreat.edge к краю поля.
var m6_back := PackedFloat64Array([0.0, 0.0])
var m6_prev: Array = [null, null]
var m6_rear := 0
var m6_edge := 0
## Вышедшие из гипера, ещё не дошедшие до своей стороны рубежа: точка выхода — место минус
## тормозной путь (09, 5.5), то есть за рубежом по построению, и подход к месту — не отход
## (найдено стендом G5: весь «М6 за рубежом» «Генерального» был подкреплением на подходе).
var m6_arriving: Dictionary[int, bool] = {}
## М9: пары «свой в чужом» ближе (hull + hull) × 1,15 сейчас, сколько было входов; шаги, когда
## пара чужих тяжёлых ближе M9_HEAVY.
var m9_in: Dictionary[int, bool] = {}
var m9_entries := 0
var m9_heavy := 0
## М10: расстояния до своего места (корабли под заглушкой строя) по шагам фазы «бой».
var m10_heavy := PackedFloat64Array()
var m10_corvette := PackedFloat64Array()
var m10_frigate := PackedFloat64Array()
## М10, строй против расталкивания (09, 9.5 п. 20; 5.3): шаги, на которых МЕСТА двух своих
## (под заглушкой строя) ближе радиуса расталкивания своих hull + hull — строй толкает сам
## себя. Откат --ecm-01L (РЭБ на 0,1 L перед флагманом) обязан это показать: расталкивание
## сдвигает тяжёлых на десятки, а не на сотни, и медиана М10 (≤ 150) этого не видит.
var m10_self := 0
## Места линий P двух сторон под заглушкой строя: ближе всего за фазу «бой» (INF — не было).
## P считается от чужих тяжёлых, которые ещё в пути, и без предела line.lead_max места обеих
## сторон съезжались до 300 — шеренги лёгких проходили сквозь друг друга (найдено стендом G4).
var p_min := INF
## М16 «суета» тяжёлых (пакет GТ; отзыв о capella-v0.6: «большие корабли слишком быстрые
## и активно маневрируют»): путь тяжёлых за фазу «бой», развороты хода вдоль оси своей стороны
## (вперёд ↔ назад: подход, отход, место линии) и доля тяжёлый-секунд в движении ПОСЛЕ того, как
## тяжёлый впервые вышел на дистанцию (цель главного калибра в поясе). Знак хода по uid — для
## разворотов; кто уже выходил на дистанцию — для доли.
var m16_path := 0.0
var m16_flips := 0
var m16_dir: Dictionary[int, int] = {}
var m16_set_s := 0.0
var m16_move_s := 0.0
var m16_settled: Dictionary[int, bool] = {}

## М3: ни одного шага L < 360, пока у обеих сторон есть линия (09, 8.2).
const M3_FLOOR := 360.0
## М4: «за своими тяжёлыми» — p < −50 (09, 8.2).
const M4_BEHIND := 50.0
## М4: побитые лёгкие (< 30%) уходят за линию по правилу (09, 3.5) и не считаются.
const M4_HURT := 0.3
## М9: пары чужих тяжёлых ближе 360 (09, 8.2). «Свой в чужом» — ближе (hull + hull) × 1,15
## (09, 5.7) — это ровно радиус расталкивания чужих (sim/space.gd → FOE_ROOM), и пары берутся
## из того же прохода пар снимка (space.foe_in, heavy_close).
const M9_HEAVY := 360.0
## М16: быстрее — «в движении», и ход вдоль оси быстрее этого засчитывается направлением (развороты
## хода — смена знака). То же число, что «стоит» у прихода части 02 (space.js:1287 «медленнее 3»,
## sim/movement.gd → ARRIVED_V): медленнее — корабль стоит, его доворот или толчок — не ход.
const M16_V := 3.0


## М16 за шаг: тяжёлый в фазе «бой» — скорость, ход вдоль оси своей стороны, в поясе ли.
func sample_fuss(uid: int, vel: Vector2, ax: Vector2, in_belt: bool, dt: float) -> void:
	var sp := vel.length()
	m16_path += sp * dt
	var along := vel.dot(ax)
	var dirn := 1 if along > M16_V else (-1 if along < -M16_V else 0)
	if dirn != 0:
		var prev: int = m16_dir.get(uid, 0)
		if prev != 0 and prev != dirn:
			m16_flips += 1
		m16_dir[uid] = dirn
	if in_belt:
		m16_settled[uid] = true
	if m16_settled.has(uid):
		m16_set_s += dt
		if sp > M16_V:
			m16_move_s += dt


func book(side: int, key: StringName, cls_i: int, dealt: float) -> void:
	if key != &"planet" and cls_i != TORPEDO_CLS and cls_i != STRIKE_CLS and dealt > 0.0:
		# М11: промежуток без урона по кораблям — после первой стычки, без залпов планеты
		if last_hit >= 0.0:
			max_gap = maxf(max_gap, now - last_hit)
		last_hit = now
	var d: Dictionary = dmg[side]
	var row: PackedFloat64Array = d.get(key, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	row[cls_i] += dealt
	d[key] = row


func idle_step(side: int, reason: StringName, dt: float) -> void:
	var d: Dictionary = idle[side]
	var v: float = d.get(reason, 0.0)
	d[reason] = v + dt


## Урон стороны по КОРАБЛЯМ (без машин и снарядов) по ключу.
func to_ships(side: int, key: StringName) -> float:
	var row: PackedFloat64Array = dmg[side].get(key, PackedFloat64Array())
	var t := 0.0
	for i in row.size():
		if i != TORPEDO_CLS and i != STRIKE_CLS:
			t += row[i]
	return t


## Урон по машинам (сбитая авиация) — отдельно от урона по кораблям, как и по снарядам
## (09, М7: «отдельно — урон по машинам и ракетам»).
func to_craft(side: int) -> float:
	var t := 0.0
	for key: StringName in dmg[side]:
		var row: PackedFloat64Array = dmg[side][key]
		t += row[STRIKE_CLS]
	return t


## Урон по снарядам (сбитые ракеты и торпеды) — отдельно от урона по кораблям.
func to_projs(side: int) -> float:
	var t := 0.0
	for key: StringName in dmg[side]:
		var row: PackedFloat64Array = dmg[side][key]
		t += row[TORPEDO_CLS]
	return t


## Весь записанный урон: по кораблям и по снарядам, обеих сторон.
func total() -> float:
	var t := 0.0
	for side in 2:
		for key: StringName in dmg[side]:
			var row: PackedFloat64Array = dmg[side][key]
			for v in row:
				t += v
	return t


## Строка «урон по источникам» стороны: «главный калибр 54% · батареи 9% · …» (09,
## вопрос 10). Пустая, если урона по кораблям не было.
func shares_text(side: int) -> String:
	var all := 0.0
	for k in KEYS:
		all += to_ships(side, k)
	if all <= 0.0:
		return ""
	var parts := PackedStringArray()
	for k in KEYS:
		var v := to_ships(side, k)
		if v > 0.0:
			parts.append("%s %d%%" % [KEY_TEXT[k], roundi(v * 100.0 / all)])
	return " · ".join(parts)


## Доли причин молчания главного калибра стороны: «мёртвая зона 40% · нет цели 60%».
func idle_text(side: int) -> String:
	var all := 0.0
	for r in REASONS:
		var v: float = idle[side].get(r, 0.0)
		all += v
	if all <= 0.0:
		return ""
	var parts := PackedStringArray()
	for r in REASONS:
		var v: float = idle[side].get(r, 0.0)
		if v > 0.0:
			parts.append("%s %d%%" % [REASON_TEXT[r], roundi(v * 100.0 / all)])
	return " · ".join(parts)


## М5 за шаг: машина в воздухе (не ближе M5_HOME к своему носителю) и её проекция p на
## ось своей стороны от своей линии; «в середине» — −M5_BACK ≤ p ≤ d + M5_OVER, где d —
## расстояние между линиями (в строю G4 — L). Геометрию даёт sim/air.gd (prepare).
func sample_craft(side: int, p: float, d: float, dt: float) -> void:
	craft_s[side] += dt
	if p >= -M5_BACK and p <= d + M5_OVER:
		craft_mid_s[side] += dt


## Доля машина-секунд в середине (М5); −1 — машин в воздухе не было.
func mid_share(side: int) -> float:
	return craft_mid_s[side] / craft_s[side] if craft_s[side] > 0.0 else -1.0


## Урон авиации стороны по КОРАБЛЯМ (М7, М8).
func air_to_ships(side: int) -> float:
	var t := 0.0
	for k in AIR_KEYS:
		t += to_ships(side, k)
	return t


# ───────────────────────── доктрина тяжёлых и строй (G4) ─────────────────────────

## Эпизод по uid: вошёл (on) — запомнить начало, вышел — записать длину.
static func episode(run: Dictionary[int, float], eps: PackedFloat64Array, uid: int, on: bool, now: float) -> void:
	if on:
		if not run.has(uid):
			run[uid] = now
	elif run.has(uid):
		var t0: float = run[uid]
		eps.append(now - t0)
		run.erase(uid)


## Закрыть незакрытые эпизоды (конец боя или фазы «бой»).
func close_episodes(now: float) -> void:
	for u: int in m2_run.keys():
		episode(m2_run, m2_eps, u, false, now)
	for u: int in m6_run.keys():
		episode(m6_run, m6_eps, u, false, now)


static func median(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return -1.0
	var s := a.duplicate()
	s.sort()
	var n := s.size()
	return s[n >> 1] if n % 2 == 1 else (s[(n >> 1) - 1] + s[n >> 1]) * 0.5


## Доля «худших» q (0,05 — 5% наименьших): значение на этой доле снизу.
static func low(a: PackedFloat64Array, q: float) -> float:
	if a.is_empty():
		return -1.0
	var s := a.duplicate()
	s.sort()
	return s[clampi(floori(q * float(s.size())), 0, s.size() - 1)]


static func share(part: float, whole_: float) -> float:
	return part / whole_ if whole_ > 0.0 else -1.0


## М7 (09, 8.2): доли урона стороны по КОРАБЛЯМ — главный калибр, батарея, лёгкие (с ракетами
## «Синхо»), авиация, ПВО и планета; −1 — урона не было.
func m7(side: int) -> Dictionary:
	var all := 0.0
	for k in KEYS:
		all += to_ships(side, k)
	if all <= 0.0:
		return {}
	return {"main": to_ships(side, &"heavy") / all, "sec": to_ships(side, &"sec") / all,
		"light": (to_ships(side, &"light") + to_ships(side, &"missile")) / all, "air": air_to_ships(side) / all,
		"pd": to_ships(side, &"pd") / all, "planet": to_ships(side, &"planet") / all, "total": all}


## Доля готового времени главного калибра, сорванного помехами (журнал причин; план G5 —
## свой замер отката --old-ecm): секунды «помехи» / (секунды молчания + выстрелы × шаг).
func jam_block(step: float) -> float:
	var idle_all := 0.0
	var jam := 0.0
	for side in 2:
		for r in REASONS:
			var v: float = idle[side].get(r, 0.0)
			idle_all += v
			if r == &"jam":
				jam += v
	var ready := idle_all + float(main_shots[0] + main_shots[1]) * step
	return jam / ready if ready > 0.0 else -1.0


## Сводка замеров G4 одним словарём (стенд пишет её строкой JSON; 09, 8.2).
func lines_summary() -> Dictionary:
	return {
		"fight_t0": fight_t0, "fight_t1": fight_t1,
		"m1": share(m1_s, heavy_s),
		"m2": share(m2_s, heavy_s), "m2_ep_med": median(m2_eps),
		"m3_med": median(m3), "m3_p5": low(m3, 0.05), "m3_short": m3_short, "r_line": r_line if r_line < INF else -1.0,
		"m3_med_k": median(m3) / r_line if r_line < INF and not m3.is_empty() else -1.0,
		"m4": share(m4_mid_s, light_s), "m4_back": share(m4_back_s, light_s),
		"m6": share(m6_s, heavy_s), "m6_ep_med": median(m6_eps), "m6_back": maxf(m6_back[0], m6_back[1]),
		"m6_rear": m6_rear, "m6_edge": m6_edge,
		"m9_entries": m9_entries, "m9_heavy": m9_heavy,
		"m10_heavy": median(m10_heavy), "m10_corvette": median(m10_corvette), "m10_frigate": median(m10_frigate),
		"m10_self": m10_self, "p_min": p_min if p_min < INF else -1.0,
		"first_hit": first_hit, "first_gun": first_gun,
		"m11_gap": max_gap, "m12_jam": share(m12_jam_s, heavy_s),
		# М16 (пакет GТ): путь и развороты — на тяжёлый-минуту фазы «бой»; доля в движении
		"m16_path": m16_path * 60.0 / heavy_s if heavy_s > 0.0 else -1.0,
		"m16_flips": float(m16_flips) * 60.0 / heavy_s if heavy_s > 0.0 else -1.0,
		"m16_move": share(m16_move_s, m16_set_s),
	}
