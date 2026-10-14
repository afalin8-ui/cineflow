# sim/ai.gd — ИИ ОДНОЙ стороны (архитектура, 2.3; доктрина 09, раздел 7; план G5, п. 1).
# Объект на сторону: свой таймер тика, своя доля корабля (share — от первого uid СВОЕЙ
# стороны, 09, 7.2 и 9.5 п. 12), общая цель тяжёлых, помощь прижатому, перехват корветов,
# очередь пусков звеньев. Сам ничего в бою не меняет посреди раздумья: battle.gd сначала
# собирает ПЛАНЫ обеих сторон по одному состоянию начала шага (09, 4.5 и 8.1 — иначе
# «ИИ против ИИ» меряет сторону, а не клан), потом применяет их по очереди.
#
# Тик (09, 7.1), раз в rnd(2,5; 4) × tempo (первый — на 3 × tempo):
# 1. списки mine / foes;  2. купол РЭБ «щит или глушение» (как сейчас);  3. звенья — правило
# 4.5 по снимку;  4. никого не видно — поиск скрытых (в срезе скрытности нет: тик кончен);
# 5. отход всем флотом (05, 2.6 пп. 5, 7) — его отдаёт battle.gd, у него гипер и лента;
# 6. линия: F_h, ax, R_line, L = 0,85 R_line, P = F_h − ax × L (сдвиг ≤ 120, поворот ≤ 15°,
# не впереди своих тяжёлых дальше line.lead_max, не за тыловым рубежом, не у края);
# 7. места по полосам sim/formation.gd → places() (раздача по положению, 5.4);
# 8. общая цель тяжёлых (7.3);  9. роли (7.2), перехват корветов в своей полосе (3.4),
# помощь прижатому (7.4).
#
# Шаги 6–7 — это бывшая заглушка строя (sim/line_stub.gd, план G4, п. 6), перенесённая
# сюда без изменений: та же арифметика и тот же расход генератора. Режим «только строй»
# (full = false) — ровно она: так ведёт противника лаборатория «Бой линий» (tools/polygon.gd),
# и её показательный бой даёт тот же отпечаток, что в G4.
#
# Модель — чистый GDScript (RefCounted), ни одного узла; случайное — только rng боя;
# углы — без тригонометрии библиотеки C (godot/CLAUDE.md, 20: Linux и Windows расходились).
extends RefCounted

const State := preload("res://sim/state.gd")
const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")
const Squad := preload("res://sim/squad.gd")
const Craft := preload("res://sim/craft.gd")
const Formation := preload("res://sim/formation.gd")
const Vision := preload("res://sim/vision.gd")
const Ecm := preload("res://sim/ecm.gd")
const Hangar := preload("res://sim/hangar.gd")
const HeavyDoctrine := preload("res://sim/heavy_doctrine.gd")

# space.js:1757 aiThink — как часто думает ИИ: первый тик на 3 × tempo, дальше
# rnd(2,5; 4) × tempo (battle_constants.ai_think — «переносятся кодом»)
const THINK_FIRST := 3.0
const THINK_MIN := 2.5
const THINK_MAX := 4.0
## Тики двух ИИ разнесены (архитектура, 2.4): второй впервые думает на шаг позже первого,
## чтобы тяжёлые тики не складывались в один худший шаг. Сдвиг перевеса не даёт — это
## меряет зеркальный бой (М13, tools/summarize.py).
const THINK_PHASE := 1.0 / 30.0
## space.js:1736 share — доля корабля: (номер × 0,6180339) mod 1 — постоянная, не жребий.
const SHARE_K := 0.6180339
## Безоружный и станция — не цели ИИ-фокуса; машина звена-угрозы — звено ближе этого
## к своему кораблю (только откат --old-ai: JS, часть 05, 2.9 «threats … 750»).
const OLD_THREAT_R := 750.0
const OLD_INTERCEPT_SHARE := 0.7
## Только откат --old-ai: кольцо охранения hull + hull + 60, углы n × 2,1 + 0,5 рад, РЭБ
## на +330, носители −440 по 260 вбок, корветы без тяжёлых — +120 по 110 (space.js:1876, 2.7).
const OLD_RING_PAD := 60.0
const OLD_RING_A := 2.1
const OLD_RING_A0 := 0.5
const OLD_ECM_FWD := 330.0
const OLD_ECM_LAT := 260.0
const OLD_CARRIER_LAT := 260.0
const OLD_LONE_FWD := 120.0
const OLD_LONE_LAT := 110.0
const OLD_FREE_FWD := 80.0
const OLD_FREE_LAT := 300.0
const OLD_REACH_MIN := 300.0
const OLD_FOCUS_FAR := 1.3
const OLD_FOCUS_DROP := 1.8
const OLD_FOCUS_FAR_K := 0.3

## ТОЛЬКО для проверок отката (в игре false):
## общая цель — без правила «в поясе у большинства бьющих» (09, 7.3), лучшая по счёту;
static var rollback_focus_any := false
## помощи прижатому нет (09, 7.4);
static var rollback_no_help := false
## корвет перехватывает звено, подошедшее к ЛЮБОМУ своему кораблю ближе 750, доля 0,7 (как
## в JS; 09, 3.4);
static var rollback_intercept_any := false
## роли звеньев — как в JS: бомбардировщики, пока видна чужая не-мелочь (09, 4.5);
static var rollback_air_js := false
## share — от общего uid боя, как в JS (09, 7.2 и 9.5 п. 12): у двух одинаковых флотов общую
## цель бьют разные корабли.
static var rollback_share_global := false
## побитый тяжёлый уходит к дальнему краю пояса и ЗА тыловой рубеж (до находки стенда G5).
static var rollback_hurt_past_rear := false


## Сторона и режим.
var side := 0
## true — ИИ целиком (тик 7.1); false — только строй (шаги 6–7, лаборатория «Бой линий»).
var full := true
## Откат 09, 8.4 «старый ИИ» (`--old-ai`): кольцо охранения, тяжёлые на «Охоте».
var old := false
## Первый uid своей стороны — от него доля корабля (7.2).
var first_uid := 1
## Общая цель тяжёлых (7.3).
var focus: Ship
## Наибольшая суммарная прочность своего флота за бой (05, 2.6 п. 5).
var hp0 := 0.0
var had_heavy := false
var reserve_asked := false
## Помощь прижатому (7.4): тяжёлый uid → когда чужой вплотную начался; активные помощи
## [uid тяжёлого, uid врага, до какого времени, PackedInt32Array uid лёгких].
var close_since: Dictionary[int, float] = {}
var helps: Array[Array] = []
## Пуски звеньев — по одному за шаг (архитектура, 2.4: худший шаг пробы A — первый тик,
## когда все носители поднимали всё разом): [uid носителя, роль].
var launch_q: Array[Array] = []
## Раздумья со сменой режима купола (04, 7.4, вопрос 1 — «РЭБ ИИ мигает»): тики с РЭБ
## и тики, где режим сменился.
var dome_ticks := 0
var dome_flips := 0
var dome_last: StringName = &""
## Сколько раз звал помощь и сколько перехватов начал (отчёт стенда).
var help_calls := 0
var intercepts := 0


## План одного тика: что ИИ решил по состоянию начала шага. Применяет battle.gd
## (гипер, отход и резерв — у него) и apply() (роли и места).
class Plan:
	var lines: Array = []               # [mine, Formation.Out] — шаги 6–7; пусто — мест не трогаем
	var p := Vector2.ZERO
	var ax := Vector2(0.0, -1.0)
	var f_h := Vector2.ZERO             # центр видимых чужих тяжёлых в строю (нет — видимых чужих)
	var leaderless := false
	var dome: StringName = &""          # режим купола всем своим РЭБ (&"" — РЭБ нет)
	var launch: Array[Array] = []       # [Ship носитель, роль]
	var retreat := false
	var jumps: Array[Ship] = []         # тяжёлые ниже ai.flee_hp — в гипер
	var reserve := false
	var focus: Ship


## Завести ИИ стороне: первый тик, тыловой рубеж, место линии — линия старта (как заглушка G4).
static func arm(b: State, p_side: int, p_full: bool) -> RefCounted:
	var a := new()
	a.side = p_side
	a.full = p_full
	a.old = b.old_ai and p_full
	var sd := b.sides[p_side]
	sd.ai_on = true
	sd.ai_full = p_full
	sd.ai_next = THINK_FIRST * tempo(b) + (THINK_PHASE * float(p_side) if p_full else 0.0)
	sd.rear_z = b.defs.doctrine.deploy_heavy_z + b.defs.doctrine.line_rear
	sd.line_p = Vector2(0.0, sd.sign_z * b.defs.doctrine.deploy_heavy_z)
	sd.line_ax = Vector2(0.0, -sd.sign_z)
	sd.line_set = true
	var first := 0
	for s in b.ships:
		if s.side == p_side and (first == 0 or s.uid < first):
			first = s.uid
	a.first_uid = maxi(first, 1)
	return a


static func dif_of(b: State) -> Defs.DifficultyDef:
	return b.defs.difficulty.get(StringName(str(b.setup.get("difficulty", b.defs.quick.default_difficulty))))


static func tempo(b: State) -> float:
	var dif := dif_of(b)
	if dif == null or dif.tempo <= 0.0:
		return 1.0
	return dif.tempo


static func focus_share(b: State) -> float:
	var dif := dif_of(b)
	return dif.focus if dif != null else 0.0


## Доля корабля (7.2): от первого uid СВОЕЙ стороны — у двух одинаковых флотов общую цель
## бьют одни и те же места строя (05, 2.18 п. 2; 09, 9.5 п. 12).
func share(s: Ship) -> float:
	var n := s.uid if rollback_share_global else s.uid - first_uid + 1
	var x := float(n) * SHARE_K
	return x - floorf(x)


# ───────────────────────────── раздумье ─────────────────────────────

## Пора ли думать.
func due(b: State) -> bool:
	var sd := b.sides[side]
	return sd.ai_on and not sd.retreat and b.time >= sd.ai_next


## Раздумье (09, 7.1) по состоянию начала шага: → план или null (думать не о чем).
## Время следующего тика ставится здесь — тот же расход генератора, что у заглушки G4.
func think(b: State) -> Plan:
	var sd := b.sides[side]
	sd.ai_next = b.time + b.rng.randf_range(THINK_MIN, THINK_MAX) * tempo(b)
	if not full:
		return _plan_lines(b)
	return _plan_full(b)


## Только строй (шаги 6–7) — бывшая заглушка: план или null (никого не видно / нет своих
## тяжёлых — тогда мест не трогает, как в G4).
func _plan_lines(b: State) -> Plan:
	var pl := Plan.new()
	var lf := _line(b, false)
	if lf.is_empty():
		return null
	pl.lines = lf
	return pl


## Шаги 6–7 (вынесено из sim/line_stub.gd без изменений): → [mine, Out] или [].
## leaderless — своих тяжёлых нет: заглушка возвращала пусто, ИИ ставит P от противника
## (05, 2.7: «нет тяжёлых в строю — от противника, а не от себя», ловушка 9 части 05).
func _line(b: State, leaderless_ok: bool) -> Array:
	var d := b.defs.doctrine
	var sd := b.sides[side]
	# F_h: видимые чужие тяжёлые в строю (без станции и копящих гипер); нет — видимые чужие
	var fh := Vector2.ZERO
	var nh := 0
	var fa := Vector2.ZERO
	var na := 0
	var foe_dead := INF
	var foe_air := false
	for o in b.ships:
		if o.dead or o.side == side or not Vision.sees(b, side, o):
			continue
		if o.hangar != null:
			foe_air = true
		if o.station:
			continue
		fa += o.pos
		na += 1
		if o.heavy() and not o.charging():
			fh += o.pos
			nh += 1
			foe_dead = minf(foe_dead, o.def.main.dead)
	if na == 0:
		return []
	var f := fh / float(nh) if nh > 0 else fa / float(na)
	var mine: Array[Ship] = []
	for s in b.ships:
		if not s.dead and s.side == side and not s.station and not s.charging():
			mine.append(s)
	if mine.is_empty():
		return []
	var members := Formation.members_from(mine)
	var l := Formation.line_l(b.defs, members)
	var want_back := l
	if l <= 0.0:
		if not leaderless_ok:
			# своих тяжёлых нет: шаги 6–7 без R_line не считаются (P = F_h — лёгкие шли бы прямо
			# в чужую линию, найдено стендом G4) — режим «только строй» мест не трогает
			return []
		# без тяжёлых P — в 500 от F к своим (05, 2.7: C = F + back × max(500, reach × 0,68)) —
		# чтобы носители и лёгкие не отсчитывались от самих себя (ловушка 9 части 05)
		want_back = d.ai_leaderless_back
	# ось — от прежнего P к F_h, поворот не больше turn_max (5.6). БЕЗ atan2/sin/cos
	# библиотеки C: они у Linux (glibc) и Windows (MSVC) расходятся в последнем бите, и бой
	# расходился между системами (найдено CI G4: с правкой main.dead_k отпечатки разные).
	# Поворот на предел — сложением с постоянными cos/sin, посчитанными рядом (_cos_sin);
	# в пределе — сама желаемая ось
	var want_ax := f - sd.line_p
	if want_ax.length_squared() < 1.0:
		want_ax = sd.line_ax
	want_ax = want_ax.normalized()
	var ax := want_ax
	var cs := _cos_sin(deg_to_rad(d.line_turn_max_deg))
	if sd.line_ax.dot(want_ax) < cs.x:
		var sgn := 1.0 if sd.line_ax.cross(want_ax) >= 0.0 else -1.0
		ax = (sd.line_ax * cs.x + Vector2(-sd.line_ax.y, sd.line_ax.x) * (sgn * cs.y)).normalized()
	var p_want := f - ax * want_back
	var step := p_want - sd.line_p
	if step.length() > d.line_shift_max:
		step = step * (d.line_shift_max / step.length())
	var p := sd.line_p + step
	# P не убегает вперёд своей линии тяжёлых дальше line.lead_max (найдено стендом G4: P
	# считается от чужих тяжёлых, которые ещё в пути, и P обеих сторон съезжались до 300 —
	# шеренги лёгких проходили сквозь друг друга). ТОЛЬКО ВПЕРЁД: если свои отошли, P на месте
	# — отход своих точку линии назад не тянет (09, 9.5 п. 3)
	var own := Formation.line_of(b.ships, side)
	if own.heavy:
		var lead := (p - own.center).dot(ax)
		var allow := maxf((sd.line_p - own.center).dot(ax), d.line_lead_max)
		if lead > allow:
			p -= ax * (lead - allow)
	# тыловой рубеж: P не дальше линии старта + line.rear вглубь своей стороны (2.6). Упёрлись —
	# P встаёт на рубеж НА ОСИ от F_h (ближе L), а не срезается по z: срезанная только по z
	# точка уползала вбок с каждым тиком (ось считается от прежнего P)
	if p.y * sd.sign_z > sd.rear_z:
		var lim_y := sd.sign_z * sd.rear_z
		if absf(p.y - f.y) > 1e-6:
			p = f + (p - f) * ((lim_y - f.y) / (p.y - f.y))
		p.y = lim_y
	# край поля: P и носители позади (−carrier_back по оси) — не ближе line.edge к краю
	var edge := b.mp.field - d.line_edge
	var back := p - ax * d.line_carrier_back
	for k in 2:
		var over_p := maxf(absf(p[k]) - edge, 0.0)
		var over_b := maxf(absf(back[k]) - edge, 0.0)
		var sh := maxf(over_p, over_b)
		if sh > 0.0:
			var sgn := signf(p[k]) if over_p >= over_b else signf(back[k])
			p[k] -= sgn * sh
	sd.line_p = p
	sd.line_ax = ax
	# состав сменился (гибель, гипер, прибывшие) — места заново по положению (5.4)
	var roster := PackedStringArray()
	for s in mine:
		roster.append("%d" % s.uid)
	var key := ",".join(roster)
	var spec := Formation.Spec.new()
	spec.p = p
	spec.ax = ax
	spec.foe_width = Formation.line_width(b.ships, 1 - side, Vector2(-ax.y, ax.x))
	spec.foe_air = foe_air
	spec.by_pos = key != sd.roster
	spec.ecm_01l = b.ecm_01l
	sd.roster = key
	# носитель уходит на −760, если чужой корабль ближе line.carrier_close_dist к нему
	for s in mine:
		if s.hangar == null:
			continue
		for o in b.ships:
			if not o.dead and o.side != side and not o.station and Vision.sees(b, side, o) and o.pos.distance_to(s.pos) < d.line_carrier_close_dist:
				spec.carrier_close = true
	# середина выиграна (3.5): нет видимых чужих лёгких, кроме РЭБ, в полосе [0,2 L; 0,8 L]
	if l > 0.0 and foe_dead < INF:
		var held := false
		for o in b.ships:
			if o.dead or o.side == side or o.heavy() or o.def.ecm or o.hangar != null or o.station or not Vision.sees(b, side, o):
				continue
			var pr := (o.pos - p).dot(ax)
			if pr >= d.line_frigate_k * l and pr <= (1.0 - d.line_frigate_k) * l:
				held = true
				break
		if not held:
			spec.advance_dead = foe_dead
	var o := Formation.places(b.defs, members, spec)
	return [mine, o, f]


## cos и sin малого угла рядом Тейлора — одни сложения и умножения, то есть одинаково
## до бита на любой системе (в отличие от sin/cos библиотеки C). Для |x| ≤ π/2 двенадцати
## членов хватает с запасом до точности double.
static func _cos_sin(x: float) -> Vector2:
	var x2 := x * x
	var c := 1.0
	var s := x
	var tc := 1.0
	var ts := x
	for k in range(1, 13):
		tc *= -x2 / float((2 * k - 1) * (2 * k))
		ts *= -x2 / float((2 * k) * (2 * k + 1))
		c += tc
		s += ts
	return Vector2(c, s)


## ИИ целиком (09, 7.1): → план.
func _plan_full(b: State) -> Plan:
	var pl := Plan.new()
	var d := b.defs.doctrine
	var sd := b.sides[side]
	# 1. списки (05, 2.6 п. 1): all — живые свои (с копящими гипер), mine — не копящие,
	# foes — видимые чужие (копящие гипер и станция в них есть)
	var all_hp := 0.0
	var mine: Array[Ship] = []
	for s in b.ships:
		if s.dead or s.side != side:
			continue
		all_hp += maxf(0.0, s.hp)
		if not s.charging():
			mine.append(s)
	var foes: Array[Ship] = []
	var foe_hp := 0.0
	for o in b.ships:
		if o.dead or o.side == side:
			continue
		foe_hp += maxf(0.0, o.hp)          # отход считает и скрытых (05, вопрос 6.3)
		if Vision.sees(b, side, o):
			foes.append(o)
	if mine.is_empty():
		return null
	# резерв (если он есть у ИИ — «ИИ против ИИ», атакующий): зовёт сразу, как ИИ пробы
	# части 05, 2.18 («резерв зовёт сам, сразу»)
	if not reserve_asked and not sd.reserve.is_empty():
		reserve_asked = true
		pl.reserve = true
	# 2. купол РЭБ: хоть один свой под чужими помехами — все РЭБ «Прикрытие», иначе «Глушение»
	var under := false
	var has_ecm := false
	for s in mine:
		has_ecm = has_ecm or s.def.ecm
		under = under or Ecm.jammed(b, s.pos, side)
	if has_ecm:
		pl.dome = &"shield" if under else &"jam"
	# 3. звенья — правило 4.5 по снимку начала шага
	_plan_air(b, pl, mine, foes)
	# 4. никого не видно — поиск скрытых (7.5). В срезе скрытности нет (Vision.sees — «да»),
	# и пустой foes значит, что противника на орбите нет вовсе: бой кончится сам
	if foes.is_empty():
		return pl
	# 5. отход всем флотом (05, 2.6 п. 5): сил меньше трети от наибольшей за бой и противник
	# вдвое сильнее — или все вооружённые побиты; пока резерв в пути — нет
	hp0 = maxf(hp0, all_hp)
	var armed := 0
	var broken := 0
	var free: Array[Ship] = []
	var heavies: Array[Ship] = []
	for s in mine:
		if s.station:
			continue
		free.append(s)
		if s.heavy():
			heavies.append(s)
		if s.can_hurt():
			armed += 1
			if s.hp_frac() < d.ai_hurt_hp:
				broken += 1
	var waiting := sd.reinforce_at > 0.0
	if ((all_hp < hp0 * d.ai_retreat_hp_k and all_hp * d.ai_retreat_foe_k < foe_hp) or (armed > 0 and broken == armed)) and not waiting and not free.is_empty():
		pl.retreat = true
		return pl
	# 7 (05, 2.6 п. 7): тяжёлые были и кончились, у противника вооружённый тяжёлый есть
	# (станция тоже), и мы слабее — уходим всем флотом
	if not heavies.is_empty():
		had_heavy = true
	var foe_heavy := false
	for o in foes:
		foe_heavy = foe_heavy or (o.heavy() and o.can_hurt())
	if had_heavy and heavies.is_empty() and foe_heavy and all_hp < foe_hp and not waiting and not free.is_empty():
		pl.retreat = true
		return pl
	pl.leaderless = heavies.is_empty()
	# 6–7. линия и места
	pl.lines = _line(b, true)
	if not pl.lines.is_empty():
		pl.f_h = pl.lines[2]
	pl.p = sd.line_p
	pl.ax = sd.line_ax
	# 8. общая цель тяжёлых (7.3); без тяжёлых — общая цель лёгких: только лёгкие противника
	pl.focus = _pick_focus(b, heavies, foes, pl.leaderless)
	# тяжёлые ниже ai.flee_hp — в гипер (как сейчас)
	for s in heavies:
		if s.hp_frac() < d.ai_flee_hp:
			pl.jumps.append(s)
	return pl


# ───────────────────────────── 4.5: звенья ─────────────────────────────

## Роли звеньев (09, 4.5) по снимку начала шага, для каждого носителя со свободным местом:
##   E > I + 2                                          → перехватчики
##   виден чужой тяжёлый или носитель, и (своё звено перехватчиков в воздухе или чужих машин
##   нет), и звеньев бомбардировщиков у носителя < max(1, мест × 0,5) → бомбардировщики
##   видны чужие лёгкие в мёртвой зоне своих тяжёлых     → истребители (4.3)
##   виден чужой тяжёлый                                 → бомбардировщики
##   иначе                                               → истребители
func _plan_air(b: State, pl: Plan, mine: Array[Ship], foes: Array[Ship]) -> void:
	var d := b.defs.doctrine
	var e := 0
	var own_int := 0
	var int_squad := false
	for c in b.crafts:
		if c.dead or c.leaving:
			continue
		if c.side != side:
			if Vision.sees_body(b, side, c):
				e += 1
		elif c.role == &"interceptor":
			own_int += 1
	for q in b.squads:
		if not q.dead and q.side == side and q.role == &"interceptor":
			int_squad = true
	var foe_big := false
	var foe_heavy := false
	for o in foes:
		foe_big = foe_big or o.heavy() or o.hangar != null
		foe_heavy = foe_heavy or o.heavy()
	var light_dead := false
	for o in foes:
		if o.heavy() or o.station or o.def.cls != &"escort":
			continue
		for s in mine:
			if s.heavy() and not s.station and s.pos.distance_to(o.pos) < s.def.main.dead:
				light_dead = true
				break
		if light_dead:
			break
	for s in mine:
		if s.hangar == null or s.hangar.free <= 0:
			continue
		var queued := 0
		for q in launch_q:
			var qu: int = q[0]
			if qu == s.uid:
				queued += 1
		if queued >= s.hangar.free:
			continue
		var role := &"fighter"
		if rollback_air_js:
			# откат: как в JS (05, 2.6 п. 3) — бомбардировщики, пока видна чужая не-мелочь
			if e > own_int + 4:
				role = &"interceptor"
			else:
				for o in foes:
					if o.def.cls != &"escort":
						role = &"bomber"
						break
		else:
			var bombers := 0
			for q in b.squads:
				if not q.dead and q.home == s and q.role == &"bomber":
					bombers += 1
			for q in launch_q:
				var qu2: int = q[0]
				var qr: StringName = q[1]
				if qu2 == s.uid and qr == &"bomber":
					bombers += 1
			var cap := maxi(d.ai_air_bomber_min, floori(float(s.hangar.bays) * d.ai_air_bomber_slots_k))
			if e > own_int + d.ai_air_e_over_i:
				role = &"interceptor"
			elif foe_big and (int_squad or e == 0) and bombers < cap:
				role = &"bomber"
			elif light_dead:
				role = &"fighter"
			elif foe_heavy and bombers < cap:
				role = &"bomber"
			else:
				role = &"fighter"
		pl.launch.append([s, role])


# ───────────────────────────── 7.3: общая цель ─────────────────────────────

## Угроза цели × действенность главного калибра / прочность (focusScore, 05, 2.8; 7.3 —
## «как сейчас»): урон в секунду её оружия (главный калибр, батарея, лёгкое, ракеты) плюс
## ангар и купол.
func focus_score(b: State, f: Ship) -> float:
	var d := b.defs.doctrine
	var th := 0.0
	for w: Defs.WeaponDef in [f.def.main, f.def.sec, f.def.light, f.def.missile]:
		if w != null and w.cd > 0.0:
			th += w.dmg * float(maxi(w.mounts, 1)) * float(maxi(w.salvo, 1)) / w.cd
	if f.hangar != null:
		th += d.ai_threat_hangar
	if f.def.ecm:
		th += d.ai_threat_dome if f.ecm_power > d.ai_threat_dome_power else d.ai_threat_dome_weak
	return th * b.defs.dmg_mult(&"heavy", f.def.cls_i) * (1.0 - f.def.armor) / maxf(1.0, f.hp)


## Годится ли цель общей (7.3): в поясе (D ≤ d ≤ R) у БОЛЬШЕ ЧЕМ ПОЛОВИНЫ тяжёлых, которые
## её бьют (доля корабля < focus сложности). Цель в мёртвой зоне — работа батарей и лёгких.
func _focus_ok(b: State, t: Ship, shooters: Array[Ship]) -> bool:
	if t == null or t.dead or not Vision.sees(b, side, t):
		return false
	if rollback_focus_any or shooters.is_empty():
		return true
	var inb := 0
	for s in shooters:
		var dd := s.pos.distance_to(t.pos)
		if dd >= s.def.main.dead and dd <= s.def.main.rng:
			inb += 1
	return inb * 2 > shooters.size()


func _pick_focus(b: State, heavies: Array[Ship], foes: Array[Ship], leaderless: bool) -> Ship:
	var d := b.defs.doctrine
	if old:
		return _pick_focus_old(b, heavies, foes)
	var fs := focus_share(b)
	var shooters: Array[Ship] = []
	for s in heavies:
		if share(s) < fs and s.hp_frac() >= d.ai_hurt_hp:
			shooters.append(s)
	if not leaderless and shooters.is_empty():
		return null
	var best: Ship = null
	var bs := -INF
	for o in foes:
		if leaderless and (o.heavy() or o.station):
			continue                     # без тяжёлых — только лёгкие противника (7.2, leaderless)
		if not leaderless and not _focus_ok(b, o, shooters):
			continue
		var sc := focus_score(b, o)
		if sc > bs:
			bs = sc
			best = o
	var cur := focus
	if cur != null and not cur.dead and (leaderless or _focus_ok(b, cur, shooters)) and not (leaderless and cur.heavy()):
		if best == null or focus_score(b, cur) * d.ai_focus_keep >= bs:
			return cur
	return best


## Откат --old-ai: общая цель как в JS (05, 2.8) — штраф дальше 1,3 maxR от строя, сброс
## дальше 1,8 maxR.
func _pick_focus_old(b: State, heavies: Array[Ship], foes: Array[Ship]) -> Ship:
	var d := b.defs.doctrine
	var c := _old_center(b, heavies, foes)
	var max_r := OLD_REACH_MIN
	for s in heavies:
		max_r = maxf(max_r, s.def.main.rng)
	var best: Ship = null
	var bs := -INF
	for o in foes:
		var sc := focus_score(b, o) * (OLD_FOCUS_FAR_K if o.pos.distance_to(c) > max_r * OLD_FOCUS_FAR else 1.0)
		if sc > bs:
			bs = sc
			best = o
	var cur := focus
	if cur != null and not cur.dead and cur.pos.distance_to(c) <= max_r * OLD_FOCUS_DROP:
		var cs := focus_score(b, cur) * (OLD_FOCUS_FAR_K if cur.pos.distance_to(c) > max_r * OLD_FOCUS_FAR else 1.0)
		if cs * d.ai_focus_keep >= bs:
			return cur
	return best


## Откат --old-ai: точка строя C (05, 2.7) — центр тяжёлых в строю, нет — от противника.
func _old_center(b: State, heavies: Array[Ship], foes: Array[Ship]) -> Vector2:
	var d := b.defs.doctrine
	var c := Vector2.ZERO
	var n := 0
	for s in heavies:
		if s.hp_frac() >= d.ai_hurt_hp:
			c += s.pos
			n += 1
	if n > 0:
		return c / float(n)
	var f := Vector2.ZERO
	for o in foes:
		f += o.pos
	f /= float(maxi(foes.size(), 1))
	var own := Vector2.ZERO
	var m := 0
	for s in b.ships:
		if not s.dead and s.side == side and not s.station:
			own += s.pos
			m += 1
	own /= float(maxi(m, 1))
	var back := own - f
	if back.length_squared() < 1.0:
		back = Vector2(0.0, b.sides[side].sign_z)
	return f + back.normalized() * b.defs.doctrine.ai_leaderless_back


## Точка за тыловым рубежом стороны — на рубеж, вдоль оси ax (как P в плане линии), с допуском
## прихода внутрь (HeavyDoctrine.ARRIVED) — как гасит ход у рубежа отход (HeavyDoctrine.rear_gap).
static func _not_past_rear(sd: State.SideState, p: Vector2, ax: Vector2) -> Vector2:
	var lim := sd.rear_z - HeavyDoctrine.ARRIVED
	if sd.rear_z == INF or p.y * sd.sign_z <= lim:
		return p
	var lim_y := sd.sign_z * lim
	if absf(ax.y) > 1e-6:
		p += ax * ((lim_y - p.y) / ax.y)
	p.y = lim_y
	return p


# ───────────────────────────── применить план ─────────────────────────────

## Роли и места (09, 7.2) по плану. Гипер, отход, резерв, купол и пуски — в battle.gd
## до этого (apply_flow): сюда план приходит, только если флот не отходит.
func apply(b: State, pl: Plan) -> void:
	if not full:
		_apply_lines(b, pl.lines)
		return
	focus = pl.focus
	if pl.lines.is_empty():
		return
	var d := b.defs.doctrine
	var mine: Array[Ship] = pl.lines[0]
	var o: Formation.Out = pl.lines[1]
	_apply_lines(b, pl.lines)          # места строя — как у заглушки G4 (М10, ловушки 9.5 пп. 9, 20)
	var fs := focus_share(b)
	var ax := pl.ax
	var lat := Vector2(-ax.y, ax.x)
	var slow := 0.0
	var nh := 0
	for s in mine:
		if s.heavy():
			nh += 1
			slow = s.max_speed() if nh == 1 else minf(slow, s.max_speed())
	if nh < 2:
		slow = 0.0
	for i in mine.size():
		var s := mine[i]
		if s.station:
			continue
		s.guard_of = null
		s.stance = &"guard"
		var hpf := s.hp_frac()
		if s.heavy():
			if s in pl.jumps:
				continue
			s.group_speed = slow
			if hpf < d.ai_hurt_hp:
				# побитый тяжёлый — дальний край пояса (5.1): столько назад, чтобы до F_h было
				# 0,92 R своей; место вбок — своё в линии
				var back := (pl.p - s.slot).dot(ax) + (pl.f_h - pl.p).dot(ax) - d.belt_far_k * s.def.main.rng
				s.slot += ax * minf(back, 0.0)
				# но не за тыловой рубеж (2.6): у рубежа место встаёт НА него, по оси, — как P.
				# Найдено стендом G5 («Стычка», зёрна 1002, 1010, 1011, 1016): место побитого
				# стояло на 888–994 при рубеже 800, тяжёлый уходил туда и стоял за рубежом до гибели
				if not rollback_hurt_past_rear:
					s.slot = _not_past_rear(b.sides[s.side], s.slot, ax)
				s.anchor = s.slot
				s.forced = null
				s.group_speed = 0.0
				continue
			if old:
				_old_heavy(b, s, fs)
				continue
			s.forced = focus if (focus != null and share(s) < fs) else null
			continue
		# лёгкие, носители, РЭБ
		s.group_speed = 0.0
		if hpf < d.ai_hurt_hp and s.hangar == null:
			# побитый — за линию (5.1, 3.5): ai.hurt_back назад, разброс вбок по доле корабля
			s.slot = pl.p - ax * d.ai_hurt_back + lat * ((share(s) - 0.5) * d.ai_hurt_lat)
			s.anchor = s.slot
			s.forced = null
			s.leash_set = 0.0
			continue
		if s.hangar != null or s.def.ecm or not s.can_hurt():
			s.forced = null              # безоружным forced не ставим (C100; ловушка 8 части 05)
			if old:
				_old_place(b, s, pl)
			continue
		if old:
			_old_light(b, s, pl, fs)
			continue
		var q := s.forced as Squad
		if q != null:
			continue                     # перехватывает звено: бросит сам, по шагу (step())
		if s.def.id == &"corvette" and _intercept(b, s):
			continue
		if pl.leaderless:
			# без тяжёлых эскорт сам идёт бить (05, ловушка 10; 7.2 leaderless): «Охота» на общую
			s.stance = &"hunt"
			s.forced = focus if (focus != null and share(s) < fs) else null
			continue
		s.forced = null
	if not old and not rollback_no_help:
		_help(b, mine)
	elif old:
		helps.clear()


## Места строя на «Охране» (шаги 6–7): как заглушка G4, без изменений.
func _apply_lines(b: State, lines: Array) -> void:
	if lines.is_empty():
		return
	var mine: Array[Ship] = lines[0]
	var o: Formation.Out = lines[1]
	var d := b.defs.doctrine
	for i in mine.size():
		var s := mine[i]
		if o.band[i] == Formation.NONE:
			continue
		s.has_slot = true
		s.slot = o.at[i]
		if not old:
			s.anchor = o.at[i]
			s.stance = &"guard"
		# порядок в полосе для следующего тика: пока состав тот же, места держатся (5.4)
		s.slot_order = float(o.rank[i])
		s.slot_band = o.band[i]
		s.leash_set = d.leash_frigate_ai if o.band[i] == Formation.FRIGATE and not s.def.ecm and not old else 0.0
	# М10, строй против расталкивания (9.5 п. 20): пары новых мест ближе hull + hull — один раз
	# на раздачу; замер (battle → _sample_lines) считает их по шагам, пока оба живы и в строю
	var sd := b.sides[side]
	sd.slot_clash = PackedInt32Array()
	for i in mine.size():
		if o.band[i] == Formation.NONE:
			continue
		for j in range(i + 1, mine.size()):
			if o.band[j] == Formation.NONE:
				continue
			var mn := mine[i].hull + mine[j].hull
			if o.at[i].distance_squared_to(o.at[j]) < mn * mn:
				sd.slot_clash.append(mine[i].uid)
				sd.slot_clash.append(mine[j].uid)


# ───────────────────────────── 3.4: перехват корветов ─────────────────────────────

## Корвет перехватывает звено, только если оно ближе ai.corvette_intercept_take к ЕГО месту
## в шеренге, и только доля шеренги (share < ai.corvette_intercept_share) — вторая половина
## держит линию всегда. Бросает — дальше ai.corvette_intercept_drop от места (step()).
func _intercept(b: State, s: Ship) -> bool:
	var d := b.defs.doctrine
	var take := d.ai_corvette_intercept_take
	var sh := d.ai_corvette_intercept_share
	if rollback_intercept_any:
		take = OLD_THREAT_R
		sh = OLD_INTERCEPT_SHARE
	if share(s) >= sh:
		return false
	var best: Squad = null
	var bd := INF
	for q in b.squads:
		if q.dead or q.side == side or q.craft.is_empty():
			continue
		var at := s.slot if (s.has_slot and not rollback_intercept_any) else s.pos
		var dd := q.pos.distance_to(at)
		if rollback_intercept_any:
			# откат: звено ближе 750 к ЛЮБОМУ своему кораблю (JS «threats»)
			var near := false
			for o in b.ships:
				if not o.dead and o.side == side and o.pos.distance_to(q.pos) < take:
					near = true
					break
			if not near:
				continue
		elif dd > take:
			continue
		if dd < bd:
			bd = dd
			best = q
	if best == null:
		return false
	var c := Hangar.live_craft(best, s.pos)
	if c == null:
		return false
	s.forced = best
	s.target = c
	s.jam_shot = null
	intercepts += 1
	return true


# ───────────────────────────── 7.4: помощь прижатому ─────────────────────────────

## Тяжёлый, у которого чужой корабль вплотную дольше ai.help_after_s (отход не помог —
## «не оторваться» или рубеж), зовёт помощь: двое ближайших своих лёгких (не побитых, не
## перехватывающих звено, не помогающих уже) получают фокус «тот, кто вплотную» — до его
## гибели, ухода дальше 0,5 R от тяжёлого или ai.help_max_s.
func _help(b: State, mine: Array[Ship]) -> void:
	var d := b.defs.doctrine
	# держащиеся помощи — заново поставить фокус (роли выше его сняли)
	var busy: Dictionary[int, bool] = {}
	for h in helps:
		var fu: int = h[1]
		var foe := b.ship_by_uid(fu)
		var lights: PackedInt32Array = h[3]
		for u in lights:
			busy[u] = true
			var l := b.ship_by_uid(u)
			if l != null and not l.dead and foe != null and not foe.dead:
				l.forced = foe
				l.stance = &"guard"
	for s in mine:
		if not s.heavy() or s.station or s.dead or s.charging():
			continue
		if not close_since.has(s.uid) or b.time - close_since[s.uid] < d.ai_help_after_s:
			continue
		var helped := false
		for h in helps:
			var hu: int = h[0]
			helped = helped or hu == s.uid
		if helped:
			continue
		# кто вплотную — ближайший видимый чужой корабль
		var foe: Ship = null
		var fd := INF
		for o in b.ships:
			if o.dead or o.side == side or o.station or not Vision.sees(b, side, o):
				continue
			var dd := s.pos.distance_to(o.pos)
			if dd < fd:
				fd = dd
				foe = o
		if foe == null or fd >= s.def.main.dead:
			continue
		var pick: Array[Ship] = []
		for k in d.ai_help_lights:
			var best: Ship = null
			var bd := INF
			for l in mine:
				if l.heavy() or l.station or l.hangar != null or l.def.ecm or not l.can_hurt() or l in pick or busy.has(l.uid):
					continue
				if l.hp_frac() < d.ai_hurt_hp or l.forced is Squad:
					continue
				var dl := l.pos.distance_to(foe.pos)
				if dl < bd:
					bd = dl
					best = l
			if best != null:
				pick.append(best)
		if pick.is_empty():
			continue
		var us := PackedInt32Array()
		for l in pick:
			us.append(l.uid)
			busy[l.uid] = true
			l.forced = foe
			l.stance = &"guard"
		helps.append([s.uid, foe.uid, b.time + d.ai_help_max_s, us])
		help_calls += 1


# ───────────────────────────── каждый шаг ─────────────────────────────

## Каждый шаг, ДО кораблей (battle.gd): часы «чужой вплотную» у тяжёлых (7.4), конец помощи,
## конец перехвата (3.4) и один пуск звена из очереди (пуски разнесены по шагам).
func step(b: State) -> void:
	if not full:
		return
	var d := b.defs.doctrine
	var sp := b.space
	for s in b.ships:
		if s.dead or s.side != side or s.station or not s.heavy() or s.charging():
			if close_since.has(s.uid):
				close_since.erase(s.uid)
			continue
		var dd := s.def.main.dead
		var close := s.si >= 0 and sp.near_d2[s.si] < dd * dd
		if close:
			if not close_since.has(s.uid):
				close_since[s.uid] = b.time
		elif close_since.has(s.uid):
			close_since.erase(s.uid)
	# конец помощи: враг погиб, ушёл дальше 0,5 R от тяжёлого, тяжёлого нет или время вышло
	if not helps.is_empty():
		var keep: Array[Array] = []
		for h in helps:
			var hu: int = h[0]
			var fu: int = h[1]
			var hv := b.ship_by_uid(hu)
			var foe := b.ship_by_uid(fu)
			var until: float = h[2]
			var done := hv == null or hv.dead or hv.charging() or foe == null or foe.dead or b.time >= until
			if not done and hv.pos.distance_to(foe.pos) > d.belt_back_off_k * hv.def.main.rng:
				done = true
			if done:
				var lights: PackedInt32Array = h[3]
				for u in lights:
					var l := b.ship_by_uid(u)
					if l != null and not l.dead and l.forced == foe:
						l.forced = null
						if l.has_slot:
							l.anchor = l.slot
			else:
				keep.append(h)
		helps = keep
	# конец перехвата: звено дальше ai.corvette_intercept_drop от места корвета или погибло
	var drop := d.ai_corvette_intercept_drop
	for s in b.ships:
		if s.dead or s.side != side:
			continue
		var q := s.forced as Squad
		if q == null:
			continue
		var at := s.slot if s.has_slot else s.anchor
		if q.dead or q.craft.is_empty() or (not rollback_intercept_any and q.pos.distance_to(at) > drop):
			s.forced = null
			s.target = null
			if s.has_slot:
				s.anchor = s.slot
	# один пуск за шаг
	while not launch_q.is_empty():
		var e: Array = launch_q.pop_front()
		var cu: int = e[0]
		var c := b.ship_by_uid(cu)
		if c == null or c.dead or c.charging() or c.hangar == null or c.hangar.free <= 0:
			continue
		var role: StringName = e[1]
		Hangar.launch(b, c, role)
		break


## Режим купола (п. 2 тика): счёт раздумий со сменой режима (04, 7.4, вопрос 1).
func set_dome(b: State, mode: StringName) -> void:
	if mode == &"":
		return
	dome_ticks += 1
	if dome_last != &"" and dome_last != mode:
		dome_flips += 1
	dome_last = mode
	for s in b.ships:
		if not s.dead and s.side == side and s.def.ecm:
			s.ecm_mode = mode


# ───────────────────────────── откат «старый ИИ» ─────────────────────────────

## Откат --old-ai (09, 8.4): тяжёлый — «Охота» на общую цель, как в JS (05, 2.9 п. 5).
func _old_heavy(_b: State, s: Ship, fs: float) -> void:
	s.stance = &"hunt"
	if focus != null and share(s) < fs:
		s.forced = focus
	elif s.forced != null and not (s.forced is Ship):
		s.forced = null


## Откат --old-ai: носитель и РЭБ — точки JS от центра тяжёлых (05, 2.7).
func _old_place(b: State, s: Ship, pl: Plan) -> void:
	var c := _old_c(b)
	var ax := _old_ax(b, c)
	var lat := Vector2(-ax.y, ax.x)
	if s.hangar != null:
		var carriers: Array[Ship] = []
		for o in b.ships:
			if not o.dead and o.side == side and not o.station and o.hangar != null and not o.charging():
				carriers.append(o)
		var ci := carriers.find(s)
		var close := false
		for o in b.ships:
			close = close or (not o.dead and o.side != side and o.pos.distance_to(s.pos) < b.defs.doctrine.line_carrier_close_dist)
		var back := b.defs.doctrine.line_carrier_back_close if close else b.defs.doctrine.line_carrier_back
		s.anchor = c - ax * back + lat * ((float(ci) - float(carriers.size() - 1) * 0.5) * OLD_CARRIER_LAT)
	elif s.def.ecm:
		s.anchor = c + ax * OLD_ECM_FWD + lat * ((share(s) - 0.5) * OLD_ECM_LAT)
	if pl != null:
		pass


## Откат --old-ai: фрегаты — кольцом у носителя и тяжёлых, корветы — перехват в 750 от
## любого своего с долей 0,7, иначе кольцом у тяжёлых (05, 2.9 пп. 9–10).
func _old_light(b: State, s: Ship, pl: Plan, fs: float) -> void:
	var heavies: Array[Ship] = []
	var carriers: Array[Ship] = []
	var frig: Array[Ship] = []
	var corv: Array[Ship] = []
	for o in b.ships:
		if o.dead or o.side != side or o.station or o.charging():
			continue
		if o.heavy():
			heavies.append(o)
		elif o.hangar != null:
			carriers.append(o)
		elif o.def.ecm or not o.can_hurt():
			continue
		elif o.def.id == &"frigate":
			frig.append(o)
		else:
			corv.append(o)
	if pl.leaderless:
		s.stance = &"hunt"
		s.forced = focus if (focus != null and share(s) < fs) else null
		return
	if s.def.id == &"frigate":
		var fi := frig.find(s)
		var ward: Ship = null
		if fi == 0 and not carriers.is_empty():
			ward = carriers[0]
		elif not heavies.is_empty():
			ward = heavies[fi % heavies.size()]
		_old_escort(s, ward, fi)
		s.forced = null
		return
	# корвет: звено-угроза ближе 750 к любому своему, доля < 0,7
	var q: Squad = null
	var qd := INF
	for sq in b.squads:
		if sq.dead or sq.side == side or sq.craft.is_empty():
			continue
		var near := false
		for o in b.ships:
			if not o.dead and o.side == side and o.pos.distance_to(sq.pos) < OLD_THREAT_R:
				near = true
				break
		if near and sq.pos.distance_to(s.pos) < qd:
			qd = sq.pos.distance_to(s.pos)
			q = sq
	if q != null and share(s) < OLD_INTERCEPT_SHARE:
		var c := Hangar.live_craft(q, s.pos)
		if c != null:
			s.forced = q
			s.target = c
			s.anchor = s.pos
			return
	if s.forced is Squad:
		s.forced = null
	var vi := corv.find(s)
	if not heavies.is_empty():
		_old_escort(s, heavies[vi % heavies.size()], vi + 3)
	else:
		var c0 := _old_c(b)
		var ax := _old_ax(b, c0)
		s.anchor = c0 + ax * OLD_LONE_FWD + Vector2(-ax.y, ax.x) * ((float(vi) - float(corv.size() - 1) * 0.5) * OLD_LONE_LAT)


static func _old_escort(s: Ship, ward: Ship, n: int) -> void:
	if ward == null or ward == s:
		s.guard_of = null
		return
	if s.guard_of == ward:
		return
	# угол — рядом Тейлора (без sin/cos библиотеки C, godot/CLAUDE.md, 20)
	var a := float(n) * OLD_RING_A + OLD_RING_A0
	a = fposmod(a, TAU)
	var cs := _cos_sin_any(a)
	s.guard_of = ward
	s.guard_off = cs * (ward.hull + s.hull + OLD_RING_PAD)


## cos/sin любого угла 0…2π через _cos_sin четверти (только откат --old-ai).
static func _cos_sin_any(a: float) -> Vector2:
	var q := floori(a / (PI * 0.5))
	var r := a - float(q) * PI * 0.5
	var v := _cos_sin(r)
	match q % 4:
		1: return Vector2(-v.y, v.x)
		2: return Vector2(-v.x, -v.y)
		3: return Vector2(v.y, -v.x)
	return v


func _old_c(b: State) -> Vector2:
	var heavies: Array[Ship] = []
	var foes: Array[Ship] = []
	for o in b.ships:
		if o.dead:
			continue
		if o.side == side and not o.station and o.heavy() and not o.charging():
			heavies.append(o)
		elif o.side != side:
			foes.append(o)
	return _old_center(b, heavies, foes)


func _old_ax(b: State, c: Vector2) -> Vector2:
	var f := Vector2.ZERO
	var n := 0
	for o in b.ships:
		if not o.dead and o.side != side:
			f += o.pos
			n += 1
	var v := (f / float(maxi(n, 1))) - c
	return v.normalized() if v.length_squared() >= 1.0 else Vector2(0.0, -b.sides[side].sign_z)


## Разорвать ссылки (архитектура, 2.12).
func unlink() -> void:
	focus = null
	helps.clear()
	launch_q.clear()
