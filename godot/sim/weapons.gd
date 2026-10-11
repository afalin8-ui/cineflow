# sim/weapons.gd — оружие по ролям, цели, выстрел, урон, ПВО, снаряды (часть 03;
# доктрина 09, раздел 1; план G2, пп. 1–3, 7–8). Перенос space.js (коммит e8af7be)
# с пометками: `# space.js:NNNN имяJS · часть, раздел`; отличие — только помеченное
# `# ОТЛИЧИЕ: …` или `# ДОКТРИНА 09, …` (архитектура, 2.14).
#
# Оружие — по РОЛИ (main, sec, light, missile, pd), а не guns[0] (09, 9.5 п. 1):
# - главный калибр (main) — только в поясе [0,4 R; R]: в мёртвой зоне не стреляет,
#   перезарядку не тратит, не раскрывает, не заряжается (09, 1.2). Целью берёт сначала
#   тяжёлых и носители (вес эскорта main.escort_weight). Под чужим куполом и под
#   ослеплением с планеты — та же дальность, но таймер перезарядки идёт в mainSlow раз
#   медленнее (09, 1.7, вопрос 2);
# - батарея (sec) — у каждой установки свой таймер со случайным стартом, круговой
#   сектор, только по КОРАБЛЯМ, под помехами — только ближе lockRange (09, 1.3);
# - лёгкое орудие (light) и ракетный пакет «Синхо» (missile) — как сейчас (09, 1.4, 1.6);
# - ПВО (pd) — сначала ракеты, потом машины (03, ловушка 22), без конуса, без сложности.
# Перезарядка идёт ВСЕГДА, после выстрела — ровно cd (03, ловушка 19; 09, 9.5 п. 8).
# Каждый выстрел раскрывает (09, 9.5 п. 7). Ноль в таблице урона проверяется везде:
# в выборе цели, выстреле и damage (09, 9.5 п. 6; машины — G3).
#
# Тяжёлые в G2 приказы огня принимают как ВЫБОР ЦЕЛИ и с места не сходят (план G2,
# п. 4): пояс, подход и отход — G4. Прежнего подхода «на 0,68 R» у тяжёлых нет нигде.
extends RefCounted

const State := preload("res://sim/state.gd")
const Defs := preload("res://sim/defs.gd")
const Ship := preload("res://sim/ship.gd")
const Proj := preload("res://sim/proj.gd")
const Ecm := preload("res://sim/ecm.gd")
const Vision := preload("res://sim/vision.gd")
const Movement := preload("res://sim/movement.gd")

# Числа JS, перенесённые как есть (часть 03); числа доктрины — в doctrine.json.
const RETARGET_MIN := 0.8          # space.js:1244: пересмотр цели раз в 0,8–1,6 с
const RETARGET_MAX := 1.6
const PD_START_MAX := 0.4          # space.js:357: ствол ПВО стартует с rnd(0; 0,4)
const SCORE := 1000.0              # space.js:1050: m × 1000 − d + …
const HURT_BONUS := 400.0          # space.js:1050: добить раненого
const CARRIER_BONUS := 250.0       # space.js:1050: носитель
const JAMMER_SCORE := 3000.0       # space.js:1086: глушитель перевешивает любую цель
const JAM_LEASH_K := 0.8           # space.js:1083: «Охрана» к глушителю — поводок + lock × 0,8
const HIT_PAD := 5.0               # space.js:1706: попадание снаряда — радиус класса + 5
const PROJ_TURN := 1.8             # space.js:1680: доворот ракеты, у торпеды 1,1
const TORP_TURN := 1.1
const ALARM_GAP := 25.0            # space.js:929: тревога «под огнём» — не чаще раза в 25 с
const ALARM_QUIET := 15.0          # …и только после 10 с тишины (alarmAt = max(…, t − 15))
const JAM_FEED_GAP := 25.0         # space.js:1254: лента «под помехами» — раз в 25 с на флот
const CHARGE_FX_STEPS := 3         # space.js:1384: вспышка накачки раз в 0,09 с (≈ 3 шага)

## ТОЛЬКО для проверок отката (план G2): в игре всегда false.
## Главный калибр стреляет и в мёртвой зоне (как в JS) — проверка «в мёртвой зоне не
## стреляет и перезарядку не тратит» обязана краснеть.
static var rollback_no_dead_zone := false
## Под помехами перезарядка главного калибра × k после выстрела, а не медленнее таймер
## (09, 1.7: вышедший из-под купола посреди перезарядки сразу стреляет в обычном темпе).
static var rollback_slow_cd := false
## Урон планеты не записывается в учёт (М7 «без остатка» обязана краснеть).
static var rollback_no_planet_book := false
## Ослепление снаряда — пока он под куполом, а не навсегда (03, ловушка 24).
static var rollback_blind_temporary := false
## Без цели перезарядка лёгкого орудия стоит (03, ловушка 19: «не замораживать»).
static var rollback_freeze_cd := false
## Батарея и ПВО не раскрывают стрелявшего (03, ловушка 25; 09, 9.5 п. 7).
static var rollback_quiet_shots := false


## Таймеры оружия при появлении (space.js:337 spawnShip · часть 03, 2.2): у каждой
## установки — свой, старт случайный rnd(0; cd) — первые выстрелы флота не идут залпом.
static func arm(b: State, s: Ship) -> void:
	s.main_cd = _timers(b, s.def.main)
	s.sec_cd = _timers(b, s.def.sec)
	s.light_cd = _timers(b, s.def.light)
	s.mis_cd = _timers(b, s.def.missile)
	s.pd_cd = PackedFloat64Array()
	if s.def.pd != null:
		for i in s.def.pd.mounts:
			s.pd_cd.append(b.rng.randf_range(0.0, PD_START_MAX))
	s.retarget = b.rng.randf_range(0.0, 1.0)


static func _timers(b: State, w: Defs.WeaponDef) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if w != null:
		for i in w.mounts:
			out.append(b.rng.randf_range(0.0, w.cd))
	return out


## Где цель для главного калибра (архитектура, 2.6; 09, 9.5 п. 5) — ОДНА функция на
## выстрел, выбор цели, подход и отход (G4), строку «чем занят» и М1:
## −1 ближе мёртвой зоны, 0 в поясе, 1 дальше дальности.
static func main_reach(s: Ship, d: float) -> int:
	var w := s.def.main
	if d < w.dead and not rollback_no_dead_zone:
		return -1
	return 1 if d > w.rng else 0


# space.js:3088 hitsStrike · часть 03, 2.14 — достаёт ли оружие корабля авиацию. Батарея
# по авиации 0 (09, 1.3), поэтому у тяжёлых «нет»: по приказу на звено они к машинам
# в свою мёртвую зону не пойдут (G3; ловушка 21 — четвёртое место проверки нуля).
static func hits_strike(b: State, s: Ship) -> bool:
	var strike := Defs.CLASSES.find(&"strike")
	for w: Defs.WeaponDef in [s.def.main, s.def.sec, s.def.light, s.def.missile]:
		if w != null and b.defs.dmg_mult(w.key, strike) > 0.0:
			return true
	return false


## Множитель сложности (space.js:309 aiMul): у игрока 1, у ИИ — aim сложности.
static func aim_of(b: State, side: int) -> float:
	return b.sides[side].aim


# ───────────────────────────── цели (часть 03, 2.7–2.9) ─────────────────────────────

# space.js:1225–1258 (цели и помехи в updateShip) · часть 03, 2.7
## Цели корабля на этом шаге — ДО движения: главное орудие (главный калибр у тяжёлого,
## лёгкое у лёгкого), батарея, ракетный пакет; помехи над кораблём.
static func think(b: State, s: Ship) -> void:
	s.retarget -= State.STEP
	var t := s.target as Ship
	if t != null and (t.dead or not Vision.sees(b, s.side, t)):
		s.target = null              # C18: цель ушла — приказ снят
	var fz := s.forced as Ship
	if fz != null and (fz.dead or not Vision.sees(b, s.side, fz)):
		s.forced = null
		if s.guard_of == null:
			s.anchor = s.pos         # цель фокуса погибла — участок там, где стоим (03, ловушка 13)
	s.jam = Ecm.profile(b, s.pos, s.side) if s.can_hurt() else null
	if s.jam_shot != null and s.jam_shot != s.target:
		s.jam_shot = null            # цель сменили приказом — «под помехами» уже не та
	var want := _forced_primary(s)
	if s.target == null or s.retarget <= 0.0 or (want != null and s.target != want and s.jam_shot == null):
		s.target = want if want != null else acquire(b, s)
		s.jam_shot = null
		s.retarget = b.rng.randf_range(RETARGET_MIN, RETARGET_MAX)
	if s.jam_shot != null and s.jam == null:
		# вышли из-под купола или глушитель сбит — к своей цели (03, ловушка 7)
		s.jam_shot = null
		s.target = want if want != null else acquire(b, s)
	var lock := 0.0
	if s.jam != null:
		var jp: Defs.EcmDef = s.jam
		lock = jp.lock_range
	# ДОКТРИНА 09, 1.7: «первым — глушитель» — только у лёгких; тяжёлый к глушителю не
	# идёт (это в упор, глубоко в мёртвой зоне), его главный калибр бьёт и под помехами
	if not s.heavy() and s.jam != null and s.jam_shot == null:
		var cur := s.target as Ship
		if cur == null or s.pos.distance_to(cur.pos) > lock:
			var j := jam_pick(b, s)
			if j != null:
				s.target = j
				s.jam_shot = j
	_jam_feed(b, s, lock)
	if s.def.sec != null:
		s.sec_target = sec_pick(b, s)
	if s.def.missile != null:
		s.mis_target = missile_pick(b, s)


## Фокус годится главному орудию: лёгкому — всегда (пока жив и виден); тяжёлому —
## только в поясе: в мёртвой зоне главный калибр бьёт лучшую СВОЮ цель в поясе, а не
## стоит молча (09, 1.2; 6.3 — урок ловушки 5 части 03 в новом виде).
static func _forced_primary(s: Ship) -> Ship:
	var fz := s.forced as Ship
	if fz == null:
		return null
	if s.heavy() and main_reach(s, s.pos.distance_to(fz.pos)) != 0 and not Movement.rollback_heavy_approach:
		return null
	return fz


static func acquire(b: State, s: Ship) -> Ship:
	if s.def.main != null:
		return main_acquire(b, s)
	if s.def.light != null:
		return light_acquire(b, s)
	return null                     # безоружный цель не ищет (03, 2.7)


static func _stance(b: State, s: Ship) -> Defs.StanceDef:
	var st: Defs.StanceDef = b.defs.stances.get(s.stance)
	return st if st != null else b.defs.stances.get(&"guard")


# ДОКТРИНА 09, 1.2 main_acquire (вместо space.js:1037 shipAcquire по guns[0])
## Своя цель главного калибра: в поясе и в досягаемости тактики (R × reach); вес
## эскорта — main.escort_weight (тяжёлые и носители первыми). «Охрана» без приказа
## идти — не дальше поводка 0,5 R + R от участка. «Охота» без целей — ближайший, но
## тоже НЕ ближе мёртвой зоны (иначе встала бы молча с целью под носом, 03, 7.2 п. 2).
static func main_acquire(b: State, s: Ship) -> Ship:
	var w := s.def.main
	var d_ := b.defs.doctrine
	var reach := _stance(b, s).reach
	var fence := 0.0
	if s.stance == &"guard" and not s.station and not s.has_move and not s.has_amove:
		fence = d_.leash_capital_k * w.rng + w.rng
	var best: Ship = null
	var best_score := -INF
	var near: Ship = null
	var nd := INF
	for o in b.ships:
		if o.dead or o.side == s.side or not Vision.sees(b, s.side, o):
			continue
		if b.defs.dmg_mult(w.key, o.def.cls_i) <= 0.0:
			continue                 # ноль в таблице — не цель (09, 9.5 п. 6)
		var d := s.pos.distance_to(o.pos)
		if main_reach(s, d) < 0:
			continue                 # ДОКТРИНА 09, 1.2: в мёртвой зоне — не цель главного калибра
		if d < nd:
			nd = d
			near = o
		if d > w.rng * reach:
			continue
		if fence > 0.0 and o.pos.distance_to(s.anchor) > fence:
			continue
		var wgt := d_.main_escort_weight if o.def.cls == &"escort" else 1.0
		var score := wgt * SCORE - d + (1.0 - o.hp_frac()) * HURT_BONUS + (CARRIER_BONUS if o.def.cls == &"carrier" else 0.0)
		if score > best_score:
			best_score = score
			best = o
	if best == null and s.stance == &"hunt" and not s.station:
		return near
	return best


## Поводок «Охраны» лёгкого (space.js:1031 leashOf): max(240; 0,4 × дальность).
static func leash_of(b: State, s: Ship) -> float:
	var g: Defs.StanceDef = b.defs.stances.get(&"guard")
	return maxf(g.leash, s.range0() * 0.4)


# space.js:1037 shipAcquire · часть 03, 2.8 (у лёгких — по роли light, а не guns[0])
static func light_acquire(b: State, s: Ship) -> Ship:
	var w := s.def.light
	var reach := _stance(b, s).reach
	var fence := 0.0
	if s.stance == &"guard" and not s.station and not s.has_move and not s.has_amove:
		fence = leash_of(b, s) + w.rng
	var best: Ship = null
	var best_score := -INF
	var near: Ship = null
	var nd := INF
	for o in b.ships:
		if o.dead or o.side == s.side or not Vision.sees(b, s.side, o):
			continue
		var m := b.defs.dmg_mult(w.key, o.def.cls_i)
		if m <= 0.0:
			continue
		var d := s.pos.distance_to(o.pos)
		if d < nd:
			nd = d
			near = o
		if d > w.rng * reach:
			continue
		if fence > 0.0 and o.pos.distance_to(s.anchor) > fence:
			continue
		var score := m * SCORE - d + (1.0 - o.hp_frac()) * HURT_BONUS + (CARRIER_BONUS if o.def.cls == &"carrier" else 0.0)
		if score > best_score:
			best_score = score
			best = o
	if best == null and s.stance == &"hunt" and not s.station:
		return near
	return best


# space.js:1067 jamPick · часть 03, 2.9 — ТОЛЬКО у лёгких (09, 1.7)
## Под помехами: первым — сам глушитель (3000 − d), к нему идут «вольные» (фокус,
## атака с ходу, «Охота», «Охрана» — если дотянется, не сходя с поводка); «Держать»
## бьёт только то, что ближе lockRange (03, ловушка 8).
static func jam_pick(b: State, s: Ship) -> Ship:
	if s.def.light == null or s.jam == null:
		return null
	var jp: Defs.EcmDef = s.jam
	var lock := jp.lock_range
	var key := s.def.light.key
	var roam := not s.station and (s.forced != null or s.has_amove or s.stance == &"hunt" or s.stance == &"guard" or Movement.rollback_hold_approach)
	var best: Ship = null
	var bs := -INF
	for f in b.fields:
		if f.mode != &"jam" or f.side == s.side or f.src == null or f.src.dead:
			continue
		if not Vision.sees(b, s.side, f.src) or not Ecm.in_field(f, s.pos):
			continue
		var src := f.src
		if b.defs.dmg_mult(key, src.def.cls_i) <= 0.0:
			continue
		var d := src.pos.distance_to(s.pos)
		if d > lock and not roam:
			continue
		if d > lock and s.forced == null and not s.has_amove and s.stance == &"guard" \
				and src.pos.distance_to(s.anchor) > leash_of(b, s) + lock * JAM_LEASH_K:
			continue                 # «Охрана» к глушителю — только если дотянется
		var sc := JAMMER_SCORE - d
		if sc > bs:
			bs = sc
			best = src
	for o in b.ships:
		if o.dead or o.side == s.side or not Vision.sees(b, s.side, o):
			continue
		var m := b.defs.dmg_mult(key, o.def.cls_i)
		if m <= 0.0:
			continue
		var d := s.pos.distance_to(o.pos)
		if d > lock:
			continue
		var sc := m * SCORE - d
		if sc > bs:
			bs = sc
			best = o
	return best


## Дальность, на которой оружие (кроме главного калибра) сейчас бьёт: под помехами —
## lockRange профиля, под ослеплением с планеты — lockRange обычного профиля (03, 2.17).
static func _lock(b: State, s: Ship, rng: float) -> float:
	var r := rng
	if s.jam != null:
		var jp: Defs.EcmDef = s.jam
		r = minf(r, jp.lock_range)
	if s.is_off(&"aim", b.time):
		r = minf(r, b.defs.ecm_base.lock_range)
	return r


# ДОКТРИНА 09, 1.3: цель батареи
## Цель фокуса, если она в дальности батареи; иначе прежняя, пока в дальности и жива;
## иначе ближайший видимый чужой КОРАБЛЬ в её дальности (как ПВО берёт nearest).
## Под помехами дальность — lockRange: батарея не держит цель, по которой молчит.
static func sec_pick(b: State, s: Ship) -> Ship:
	var w := s.def.sec
	var r := _lock(b, s, w.rng)
	var fz := s.forced as Ship
	if fz != null and not fz.dead and s.pos.distance_to(fz.pos) <= r and b.defs.dmg_mult(w.key, fz.def.cls_i) > 0.0:
		return fz
	var cur := s.sec_target as Ship
	if cur != null and not cur.dead and Vision.sees(b, s.side, cur) and s.pos.distance_to(cur.pos) <= r:
		return cur
	var best: Ship = null
	var bd := r * r
	for o in b.ships:
		if o.dead or o.side == s.side or not Vision.sees(b, s.side, o):
			continue
		if b.defs.dmg_mult(w.key, o.def.cls_i) <= 0.0:
			continue                 # батарея по авиации и ракетам — 0 (09, 1.3)
		var d2 := s.pos.distance_squared_to(o.pos)
		if d2 < bd:
			bd = d2
			best = o
	return best


# ДОКТРИНА 09, 1.6: своя цель ракетного пакета «Синхо»
## Цель главного калибра, если она ближе дальности пакета; иначе лучшая в дальности
## пакета по счёту лёгкого орудия (эскорт первым).
static func missile_pick(b: State, s: Ship) -> Ship:
	var w := s.def.missile
	var t := s.target as Ship
	if t != null and not t.dead and s.pos.distance_to(t.pos) <= w.rng:
		return t
	var best: Ship = null
	var bs := -INF
	for o in b.ships:
		if o.dead or o.side == s.side or not Vision.sees(b, s.side, o):
			continue
		var m := b.defs.dmg_mult(w.key, o.def.cls_i)
		if m <= 0.0:
			continue
		var d := s.pos.distance_to(o.pos)
		if d > w.rng:
			continue
		var sc := m * SCORE - d + (1.0 - o.hp_frac()) * HURT_BONUS
		if sc > bs:
			bs = sc
			best = o
	return best


# space.js:1254 — свои под помехами одной строкой ленты, не чаще раза в 25 с на флот
static func _jam_feed(b: State, s: Ship, lock: float) -> void:
	if s.jam == null or s.side != b.player_side or s.station or b.time - b.jam_feed_at <= JAM_FEED_GAP:
		return
	var t := s.target as Ship
	if s.heavy():
		# ДОКТРИНА 09, 1.7: главный калибр под помехами бьёт, но вдвое реже
		b.jam_feed_at = b.time
		var jp: Defs.EcmDef = s.jam
		b.feed("Наш %s под помехами РЭБ — главный калибр в %s раза реже" % [short_name(s), _times(jp.main_slow)], &"warn")
	elif t != null and s.pos.distance_to(t.pos) > lock:
		b.jam_feed_at = b.time
		b.feed("Наш %s под помехами РЭБ — бьёт только вблизи" % short_name(s), &"warn")


static func _times(k: float) -> String:
	return ("%.1f" % k).replace(".", ",").trim_suffix(",0")


## «Крейсер «Рэш» II» → «Рэш» II: собственное имя с номером (space.js:985 shortName).
static func short_name(s: Ship) -> String:
	var n := s.name
	var i := n.find("«")
	return n.substr(i) if i >= 0 else n


# ───────────────────────────── выстрел (часть 03, 2.10, 2.12) ─────────────────────────────

# space.js:1368–1421 — оружие ПОСЛЕ движения этого шага (03, 2.1 п. 6): расстояние
# и конус — от нового места и курса.
static func fire(b: State, s: Ship) -> void:
	_fire_main(b, s)
	_fire_light(b, s)
	_fire_missile(b, s)
	_fire_sec(b, s)
	_fire_pd(b, s)


static func _arc(b: State, s: Ship) -> float:
	return b.defs.consts.turret_arc_station if s.station else b.defs.consts.turret_arc_ship


# space.js:1368 (главный калибр) · часть 03, 2.10; ДОКТРИНА 09, 1.2 и 1.7
static func _fire_main(b: State, s: Ship) -> void:
	var w := s.def.main
	if w == null:
		return
	var jp: Defs.EcmDef = s.jam
	var blind := s.is_off(&"aim", b.time)
	# ДОКТРИНА 09, 1.7: под чужим «Глушением» и при ослеплении с планеты таймер
	# перезарядки идёт в mainSlow раз медленнее; дальность и мёртвая зона — те же
	var slow := 1.0
	if not b.old_ecm:
		if jp != null:
			slow = jp.main_slow
		elif blind:
			slow = b.defs.ecm_base.main_slow
	if rollback_slow_cd:
		slow = 1.0
	var t := s.target as Ship
	var why := _main_block(b, s, t, jp, blind)
	var ready := false
	var fired := false
	for i in s.main_cd.size():
		s.main_cd[i] -= State.STEP / slow     # перезарядка идёт ВСЕГДА (03, ловушка 19)
		if why != &"":
			if s.main_cd[i] <= 0.0:
				ready = true
			continue
		if t.dead:                            # первая башня добила — второй бить некого
			if s.main_cd[i] <= 0.0:
				ready = true
			continue
		if w.charge > 0.0 and s.main_cd[i] > 0.0 and s.main_cd[i] <= w.charge and b.steps % CHARGE_FX_STEPS == 0:
			b.events.append([&"charge", s.uid, i, 1.0 - s.main_cd[i] / w.charge])
		if s.main_cd[i] > 0.0:
			continue
		s.main_cd[i] = w.cd * (jp.main_slow if rollback_slow_cd and jp != null and not b.old_ecm else 1.0)
		fired = true
		Vision.reveal(b, s)                   # выстрел раскрывает (09, 9.5 п. 7)
		if b.metrics.first_gun <= 0.0:
			b.metrics.first_gun = b.time      # первый выстрел ГЛАВНОГО калибра по КОРАБЛЮ (03, ловушка 34)
		b.metrics.main_shots[s.side] += 1
		b.events.append([&"fire", s.uid, t.uid, &"main", i])
		damage(b, t, w.dmg * aim_of(b, s.side), w.key, s, (t.pos - s.pos).normalized())
	if ready and not fired:
		var r := why if why != &"" else &"no_target"
		s.idle_reason = r
		b.metrics.idle_step(s.side, r, State.STEP)   # журнал «почему не выстрелил» (03, 7.5)
	else:
		s.idle_reason = &""


## Почему главный калибр не может выстрелить по цели (порядок проверок 09, 1.2):
## &"" — может.
static func _main_block(b: State, s: Ship, t: Ship, jp: Defs.EcmDef, blind: bool) -> StringName:
	if t == null or t.dead:
		# цели в поясе нет, а чужой корабль вплотную — молчит из-за мёртвой зоны: цель
		# главного калибра в ней не выбирается (09, 1.2), но причина — она, а не «нет цели»
		if s.si >= 0 and b.space.near[s.si] >= 0 and main_reach(s, sqrt(b.space.near_d2[s.si])) < 0:
			return &"dead_zone"
		return &"no_target"
	var d := s.pos.distance_to(t.pos)
	var reach := main_reach(s, d)
	if reach > 0:
		return &"too_far"
	if reach < 0:
		return &"dead_zone"                   # ДОКТРИНА 09, 1.2: до накачки
	if b.defs.dmg_mult(s.def.main.key, t.def.cls_i) <= 0.0:
		return &"no_target"
	if s.dir.dot((t.pos - s.pos) / maxf(d, 1e-6)) < _arc(b, s):
		return &"cone"
	# флажок отката «старые помехи»: главный калибр под куполом — только ближе lockRange
	if b.old_ecm and jp != null and d > jp.lock_range:
		return &"jam"
	if b.old_ecm and blind and d > b.defs.ecm_base.lock_range:
		return &"blind"
	return &""


# space.js:1368 (лёгкие орудия) · часть 03, 2.10; 09, 1.4 — без изменений
static func _fire_light(b: State, s: Ship) -> void:
	var w := s.def.light
	if w == null:
		return
	var t := s.target as Ship
	if not (rollback_freeze_cd and (t == null or t.dead)):
		for i in s.light_cd.size():
			s.light_cd[i] -= State.STEP       # перезарядка идёт ВСЕГДА, и без цели (03, ловушка 19)
	if t == null or t.dead:
		return
	var d := s.pos.distance_to(t.pos)
	if d > w.rng or b.defs.dmg_mult(w.key, t.def.cls_i) <= 0.0:
		return
	if s.dir.dot((t.pos - s.pos) / maxf(d, 1e-6)) < _arc(b, s):
		return
	if d > _lock(b, s, w.rng):
		return                                # под помехами и ослеплением — только вблизи
	for i in s.light_cd.size():
		if s.light_cd[i] > 0.0 or t.dead:
			continue
		s.light_cd[i] = w.cd
		Vision.reveal(b, s)
		b.events.append([&"fire", s.uid, t.uid, &"light", i])
		damage(b, t, w.dmg * aim_of(b, s.side), w.key, s, (t.pos - s.pos).normalized())


# space.js:1438 fireMainGun (ракетный пакет) · часть 03, 2.10–2.11; 09, 1.6
static func _fire_missile(b: State, s: Ship) -> void:
	var w := s.def.missile
	if w == null:
		return
	for i in s.mis_cd.size():
		s.mis_cd[i] -= State.STEP
	var t := s.mis_target as Ship
	if t == null or t.dead:
		return
	var d := s.pos.distance_to(t.pos)
	if d > w.rng or b.defs.dmg_mult(w.key, t.def.cls_i) <= 0.0:
		return
	if s.dir.dot((t.pos - s.pos) / maxf(d, 1e-6)) < _arc(b, s):
		return
	if d > _lock(b, s, w.rng):
		return
	var c := b.defs.consts
	for i in s.mis_cd.size():
		if s.mis_cd[i] > 0.0:
			continue
		s.mis_cd[i] = w.cd
		Vision.reveal(b, s)
		for k in maxi(1, w.salvo):
			var spread := w.spread if w.spread > 0.0 else 0.05
			var dir := (t.pos - s.pos).normalized() + Vector2(b.rng.randf_range(-1.0, 1.0), b.rng.randf_range(-1.0, 1.0)) * spread
			spawn_proj(b, s, t, w.dmg * aim_of(b, s.side), w.key, c.ship_missile_speed, c.ship_missile_hp, dir.normalized())


# space.js:531 spawnProjectile · часть 03, 2.11
static func spawn_proj(b: State, owner: Ship, t: Ship, dmg: float, key: StringName, speed: float, hp: float, dir: Vector2) -> Proj:
	var c := b.defs.consts
	var p := Proj.new()
	p.uid = b.next_uid()
	p.side = owner.side
	p.owner = owner
	p.target = t
	p.key = key
	p.dmg = dmg
	p.speed = speed
	p.turn_k = TORP_TURN if key == &"torp" else PROJ_TURN
	p.hp = hp
	p.max_hp = hp
	p.armor = c.projectile_armor
	p.radius = c.projectile_radius
	p.life = c.projectile_life
	p.cls_i = Defs.CLASSES.find(c.projectile_cls)
	p.pos = owner.pos
	p.dir = dir
	p.jumped_at_step = b.steps
	b.projs.append(p)
	b.events.append([&"proj", p.uid])
	return p


# ДОКТРИНА 09, 1.3 — батарея: круговой сектор, у каждой установки свой таймер
static func _fire_sec(b: State, s: Ship) -> void:
	var w := s.def.sec
	if w == null:
		return
	for i in s.sec_cd.size():
		s.sec_cd[i] -= State.STEP             # перезарядка идёт всегда (09, 9.5 п. 8)
	var t := s.sec_target as Ship
	if t == null or t.dead:
		return
	var d := s.pos.distance_to(t.pos)
	if d > w.rng or b.defs.dmg_mult(w.key, t.def.cls_i) <= 0.0:
		return                                # ноль по авиации — четвёртое место (09, 9.5 п. 6)
	if d > _lock(b, s, w.rng):
		return
	for i in s.sec_cd.size():
		if s.sec_cd[i] > 0.0 or t.dead:
			continue
		s.sec_cd[i] = w.cd
		if not rollback_quiet_shots:
			Vision.reveal(b, s)               # батарея тоже раскрывает (09, 1.3)
		b.events.append([&"fire", s.uid, t.uid, &"sec", i])
		damage(b, t, w.dmg * aim_of(b, s.side), w.key, s, (t.pos - s.pos).normalized())


# space.js:1395 ПВО · часть 03, 2.12 — без изменений, кроме pd → torpedo (09, 1.5)
static func _fire_pd(b: State, s: Ship) -> void:
	var w := s.def.pd
	if w == null:
		return
	var c := b.defs.consts
	var pen := -1.0                           # штраф помех — один раз на шаг, по запросу
	for i in s.pd_cd.size():
		s.pd_cd[i] -= State.STEP
		if s.pd_cd[i] > 0.0:
			continue
		# сначала ракеты и торпеды, потом машины (03, ловушка 22; машины — G3)
		var t := nearest_proj(b, s.pos, w.rng, s.side)
		if t == null:
			s.pd_cd[i] = c.pd_retarget_idle
			continue
		s.pd_cd[i] = w.cd * b.rng.randf_range(c.pd_retarget_cd_jitter[0], c.pd_retarget_cd_jitter[1])
		if pen < 0.0:
			# свой вызов помех, а не s.jam: штраф и у безоружных (04, 2.17)
			var jp := Ecm.profile(b, s.pos, s.side)
			pen = jp.pd_penalty if jp != null else 1.0
		if not rollback_quiet_shots:
			Vision.reveal(b, s)               # выстрел ПВО тоже раскрывает (03, ловушка 25)
		b.events.append([&"pd", s.uid, i, t.pos, t.uid])
		damage(b, t, w.dmg * pen, w.key, s, (t.pos - s.pos).normalized())


# space.js:1012 nearest (по снарядам) — ближайший чужой СТРОГО ближе r
static func nearest_proj(b: State, from: Vector2, r: float, side: int) -> Proj:
	var best: Proj = null
	var bd := r * r
	for p in b.projs:
		if p.dead or p.side == side:
			continue
		var d2 := from.distance_squared_to(p.pos)
		if d2 < bd:
			bd = d2
			best = p
	return best


# ───────────────────────────── снаряды (часть 03, 2.11) ─────────────────────────────

# space.js:1673 updateProjectile
static func update_proj(b: State, p: Proj) -> void:
	var dt := State.STEP
	p.life -= dt
	if p.life <= 0.0:
		p.dead = true
		b.events.append([&"proj_end", p.uid, p.pos])
		return
	var t := p.target as Ship
	if t != null and t.dead:
		p.target = null
		t = null                              # дальше летит прямо до конца жизни
	# под чужим куполом головка слепнет НАВСЕГДА (03, ловушка 24)
	if t != null and b.defs.ecm_base.missile_blind and Ecm.jammed(b, p.pos, p.side):
		p.blind = true
	elif rollback_blind_temporary:
		p.blind = false
	if t != null and not p.blind:
		var to := (t.pos - p.pos).normalized()
		var nd := p.dir.lerp(to, clampf(p.turn_k * dt, 0.0, 1.0))
		if nd.length_squared() > 1e-12:
			p.dir = nd.normalized()
	p.pos += p.dir * (p.speed * dt)
	# попадание только в СВОЮ цель и по радиусу КЛАССА + 5 (03, ловушка 23; 01, ловушка 8)
	if t != null and p.pos.distance_to(t.pos) < t.def.radius + HIT_PAD:
		b.events.append([&"proj_hit", p.uid, p.pos])
		p.dead = true
		damage(b, t, p.dmg, p.key, p, p.dir)


# ───────────────────────────── урон (часть 03, 2.5) ─────────────────────────────

# space.js:896 damage · часть 03, 2.5; ДОКТРИНА 09, 10.2 (с направлением), М7
## Одна дверь урона. t — корабль или снаряд; src — корабль, снаряд (урон — его
## владельцу) или null у планеты (тогда book = &"planet"). → нанесённое (без
## переубийства). Ноль в таблице — урона нет (09, 9.5 п. 6); цель без прочности
## (звено — G3) урона не принимает (C14).
static func damage(b: State, t: RefCounted, amount: float, key: StringName, src: RefCounted, from_dir: Vector2, book: StringName = &"") -> float:
	if t == null or not (amount > 0.0):
		return 0.0
	var ship := t as Ship
	var proj := t as Proj
	if ship == null and proj == null:
		return 0.0
	var cls_i := ship.def.cls_i if ship != null else proj.cls_i
	if (ship.dead if ship != null else proj.dead):
		return 0.0
	var mult := b.defs.dmg_mult(key, cls_i)
	if mult <= 0.0:
		return 0.0
	var armor := ship.armor_toward(from_dir) if ship != null else proj.armor_toward(from_dir)
	var before := ship.hp if ship != null else proj.hp
	var after := before - amount * mult * (1.0 - armor)
	var dealt := before - maxf(0.0, after)
	var who := src
	var sp := src as Proj
	if sp != null:
		who = sp.owner                        # урон снаряда — его владельцу (07, ловушка 57)
	var by := who as Ship
	if ship != null:
		ship.hp = maxf(0.0, after)
	else:
		proj.hp = maxf(0.0, after)
	_credit(b, by, dealt, book if book != &"" else key, cls_i)
	if ship != null:
		_under_fire(b, ship)
	if after <= 0.0:
		if ship != null:
			destroy_ship(b, ship, by)
		else:
			proj.dead = true
			b.events.append([&"proj_end", proj.uid, proj.pos])
	return dealt


# space.js:912 credit · часть 03, 2.5; ДОКТРИНА 09, М7 — учёт по КЛЮЧУ и классу цели
static func _credit(b: State, by: Ship, dealt: float, book: StringName, cls_i: int) -> void:
	if not (dealt > 0.0):
		return
	var side := -1
	if book == &"planet":
		if rollback_no_planet_book:
			return
		side = 1 - b.gun.side if b.gun != null else Ship.DEFENDER   # планета — оборона защитника
	elif by != null:
		side = by.side
		by.dealt += dealt
		if b.metrics.first_hit <= 0.0:
			b.metrics.first_hit = b.time      # первое попадание НЕ с планеты (М11)
	if side >= 0:
		b.metrics.book(side, book, cls_i, dealt)


# space.js:928 underFire — тревога у своих крупных, редко (03, ловушка 30)
static func _under_fire(b: State, t: Ship) -> void:
	if t.side != b.player_side or (t.def.cls != &"capital" and t.def.cls != &"carrier"):
		return
	if b.time - t.alarm_at < ALARM_GAP:
		t.alarm_at = maxf(t.alarm_at, b.time - ALARM_QUIET)
		return
	t.alarm_at = b.time
	b.feed("%s %s под огнём" % ["Наша" if t.station else "Наш", short_name(t)], &"warn")


# space.js:936 destroy (корабль) · часть 03, 2.5
static func destroy_ship(b: State, e: Ship, by: Ship) -> void:
	if e.dead:
		return
	e.dead = true
	e.hp = 0.0
	if by != null:
		by.kills += 1
	b.events.append([&"destroyed", e.uid, by.uid if by != null else 0])
	# свой или чужой — словом (03, ловушка 31); имя с номером
	var nm := e.name.substr(0, 1).to_lower() + e.name.substr(1)
	if e.side == b.player_side:
		b.feed(("Потеряна наша %s" if e.station else "Потерян наш %s") % nm, &"bad")
	else:
		b.feed(("Уничтожена вражеская %s" if e.station else "Уничтожен вражеский %s") % nm, &"good")
