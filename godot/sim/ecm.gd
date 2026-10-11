# sim/ecm.gd — поля помех РЭБ, мощность купола, режимы (часть 04, 2.16–2.17; доктрина
# 09, 1.7). Построчно из space.js (коммит e8af7be) с пометками; отличие — только
# помеченное.
#
# - Поле собирается ЗАНОВО в начале каждого шага, по положениям начала шага, и
#   читается всем шагом (04, ловушка 20): глушитель, сбитый посреди шага, глушит до
#   конца шага.
# - ОТЛИЧИЕ (09, 11.6; вопрос 3 — бой плоский): поле — круг на плоскости боя, а не
#   блин ±144 по высоте; «Выше/Ниже» в срез не входят.
# - Профиль — по клану корабля РЭБ (Девиан злее); mainSlow — замедление перезарядки
#   главного калибра под помехами (09, 1.7, вопрос 2).
extends RefCounted

const State := preload("res://sim/state.gd")
const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")

## space.js:559: поле действует при мощности больше 0,05.
const ACTIVE := 0.05
## space.js:558: мощность тянется к цели долей min(1, dt / spinUp × 2,5).
const SPIN_K := 2.5

## ТОЛЬКО для проверки отката: глушит поле с мощностью, а не в режиме «Глушение» —
## «Молчать» снимало бы помехи не со следующего шага, а через ~3 с (04, 2.16).
static var rollback_mode_by_power := false


## Профиль купола корабля: клановый (у Девиана радиус ×1,45, lockRange ×0,6…).
static func prof_of(b: State, s: Ship) -> Defs.EcmDef:
	var f: Defs.FactionDef = b.defs.factions.get(b.sides[s.side].clan)
	return f.ecm if f != null else b.defs.ecm_base


# space.js:552 updateEcm · часть 04, 2.16
static func update(b: State) -> void:
	b.fields.clear()
	for s in b.ships:
		if s.dead or not s.def.ecm:
			continue
		var e := prof_of(b, s)
		# «Молчать» и накачка гипера — мощность гаснет к 0; поле живёт, пока > 0,05
		var want := 0.0 if (s.ecm_mode == &"off" or s.charging()) else 1.0
		s.ecm_power += (want - s.ecm_power) * minf(1.0, State.STEP / e.spin_up * SPIN_K)
		if s.ecm_power > ACTIVE:
			var f := State.Field.new()
			f.pos = s.pos
			f.side = s.side
			f.mode = s.ecm_mode
			f.prof = e
			f.src = s
			b.fields.append(f)


# space.js:610 inField. ОТЛИЧИЕ: только круг на плоскости (бой плоский, 09, 11.6).
static func in_field(f: State.Field, pos: Vector2) -> bool:
	return f.pos.distance_squared_to(pos) < f.prof.radius * f.prof.radius


# space.js:619 jamProfile · часть 04, 2.16
## Помехи в точке для стороны: профиль ПЕРВОГО чужого поля «Глушение» над точкой;
## своё «Прикрытие» над точкой снимает их. null — помех нет.
static func profile(b: State, pos: Vector2, side: int) -> Defs.EcmDef:
	var hit: Defs.EcmDef = null
	for f in b.fields:
		if (f.mode != &"jam" and not (rollback_mode_by_power and f.mode == &"off")) or f.side == side:
			continue
		if in_field(f, pos):
			hit = f.prof
			break
	if hit == null:
		return null
	for f in b.fields:
		if f.mode != &"shield" or f.side != side:
			continue
		if in_field(f, pos):
			return null                    # свой щит снял чужие помехи
	return hit


static func jammed(b: State, pos: Vector2, side: int) -> bool:
	return profile(b, pos, side) != null
