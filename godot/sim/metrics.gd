# sim/metrics.gd — замеры боя (архитектура, 2.3; доктрина 09, раздел 8). С G2:
# - урон по КЛЮЧУ оружия и по КЛАССУ цели, без остатка (М7; 09, 9.5 п. 11):
#   главный калибр (heavy), батарея (sec), лёгкие (light), ракетный пакет (missile),
#   ПВО (pd), авиация (gunInt, gunFig, torp — G3) и планета (planet) — отдельной
#   строкой; урон по снарядам (класс torpedo) — тоже отдельно, это «сбитые ракеты»
#   ПВО, а не урон по кораблям (03, 7.2 п. 9);
# - журнал «почему главный калибр не выстрелил» (03, 7.5; план G2, п. 8): у готового
#   главного калибра каждый шаг без выстрела — с причиной; это первый шаг порядка
#   поиска ошибки доктрины (09, 8.4: «кто почему не стрелял»);
# - темп: первое попадание (не с планеты) и первый выстрел главного калибра по
#   кораблю (М11; 03, ловушка 34).
# М1–М13 целиком — G5 (стенд).
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

## Урон по [сторона-источник][ключ] → по классу цели (5 столбцов Defs.CLASSES).
## Планета — сторона защитника (она его оборона), ключ &"planet".
var dmg: Array[Dictionary] = [{}, {}]
## Секунды молчания готового главного калибра по причинам: [сторона][причина].
var idle: Array[Dictionary] = [{}, {}]
## Выстрелы главного калибра (по сторонам) — знаменатель для долей причин.
var main_shots: PackedInt32Array = PackedInt32Array([0, 0])
var first_hit := 0.0
var first_gun := 0.0


func book(side: int, key: StringName, cls_i: int, dealt: float) -> void:
	var d: Dictionary = dmg[side]
	var row: PackedFloat64Array = d.get(key, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	row[cls_i] += dealt
	d[key] = row


func idle_step(side: int, reason: StringName, dt: float) -> void:
	var d: Dictionary = idle[side]
	var v: float = d.get(reason, 0.0)
	d[reason] = v + dt


## Урон стороны по кораблям (без снарядов) по ключу.
func to_ships(side: int, key: StringName) -> float:
	var row: PackedFloat64Array = dmg[side].get(key, PackedFloat64Array())
	var t := 0.0
	for i in row.size():
		if i != TORPEDO_CLS:
			t += row[i]
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
