# input/picking.gd — кто под курсором (архитектура, 4; часть 06, 2.4.4). Своя функция
# без физического движка, в порядке части 06:
#   1. луч по КАПСУЛЕ КОРПУСА — по длине и ширине модели из выгрузки и по
#      НАРИСОВАННОМУ (интерполированному) положению и курсу; ближайшее попадание
#      вдоль луча. Кораблём считается корпус, а не свечение и не факел (C29; 08,
#      ловушка 10): эффектов в списке кандидатов нет по устройству;
#   2. ТАКТИЧЕСКИЙ ЗНАК (view/markers.gd; план GИ, п. 6) — щелчок по рамке, полоске или имени
#      выбирает корабль знака. Знак считается «не дальше своего корабля по лучу»: его
#      глубина — расстояние от камеры до корабля, и корпус, который ближе к камере, чем
#      корабль знака, важнее знака (и наоборот: знак ближнего корабля важнее дальнего корпуса);
#   3. ближайший центр в 30 точках экрана.
# Скрытые и мёртвые отсекаются ОДНИМ фильтром видимости (shown) — тем же, что
# у кораблей на экране, колец и (с G6–G7) подписей и миникарты (C18; 04, ловушка 21).
extends RefCounted

const Ship := preload("res://sim/ship.gd")
const Craft := preload("res://sim/craft.gd")
const Squad := preload("res://sim/squad.gd")

## «Ближайший» — центр корабля на экране не дальше 30 точек (06, 2.4.3).
const NEAR_PX := 30.0

## ТОЛЬКО для проверки отката «малый за факелом» (08, ловушка 10): выбирать по рамке
## всего нарисованного (с факелами), а не по капсуле корпуса. В игре всегда false.
static var rollback_drawn_box := false


## ТОЛЬКО для проверки отката (план GИ): выбор не знает знаков — щелчок по знаку, отошедшему
## от корабля на дальнем плане, уходит в пустоту.
static var rollback_no_markers := false
## ТОЛЬКО для проверки отката: знак главнее корпуса ВСЕГДА — щелчок по ближнему крейсеру,
## на который лёг знак дальнего корабля, выбирает дальний. В игре false.
static var rollback_marker_first := false


## ТОЛЬКО для проверок (замечание к G2): uid кораблей, которых фильтр считает
## скрытыми, — пока скрытности в срезе нет, иначе проверить, что купол, пояс и круг
## спрашивают ЭТОТ фильтр, нечем. В игре всегда пусто.
static var test_hidden: Dictionary[int, bool] = {}


## Единый фильтр видимости: живой и (свой или видимый нам). Скрытности в срезе нет
## (sim/vision.gd «видит всегда» — G2); когда появится, её спрашивают ЗДЕСЬ, и тогда
## выбор, корабль на экране, кольцо купола, пояс и подпись разойтись не могут.
static func shown(s: Ship, _my_side: int) -> bool:
	return not s.dead and not test_hidden.has(s.uid)


## Луч (o + n·t, |n| = 1) против капсулы (отрезок a–b, радиус r) → расстояние вдоль
## луча до входа в капсулу; −1 — мимо.
static func ray_capsule(o: Vector3, n: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var d := b - a
	var w0 := o - a
	var bb := n.dot(d)
	var cc := d.dot(d)
	var dd := n.dot(w0)
	var ee := d.dot(w0)
	var den := cc - bb * bb
	var u := 0.0
	if cc > 1e-9:
		u = clampf((ee - bb * dd) / den, 0.0, 1.0) if den > 1e-9 else 0.0
	var t := maxf(0.0, bb * u - dd)
	# уточнить: ближайшая точка отрезка к точке луча и обратно
	if cc > 1e-9:
		u = clampf((o + n * t - a).dot(d) / cc, 0.0, 1.0)
		t = maxf(0.0, (a + d * u - o).dot(n))
	var q := a + d * u
	var dist := (o + n * t).distance_to(q)
	if dist > r:
		return -1.0
	return maxf(0.0, t - sqrt(r * r - dist * dist))


## Кто под точкой экрана: капсула корпуса → ближайший в 30 точках. view —
## view/battle_view.gd (нарисованные положения, камера). null — никого.
static func pick(view: Node3D, screen: Vector2) -> Ship:
	var cam := _cam(view)
	if cam == null:
		return null
	var o := cam.project_ray_origin(screen)
	var n := cam.project_ray_normal(screen)
	var b: Variant = view.get("battle")
	var ships: Array[Ship] = _ships(b)
	var my_side: int = view.get("my_side")
	var best: Ship = null
	var best_t := INF
	for s in ships:
		if not shown(s, my_side):
			continue
		var t := -1.0
		if rollback_drawn_box:
			var box: AABB = view.call("drawn_box", s)
			var hit: Variant = box.intersects_ray(o, n)
			if hit != null:
				var hp: Vector3 = hit
				t = (hp - o).dot(n)
		else:
			var cap: Array = view.call("capsule", s)
			var ca: Vector3 = cap[0]
			var cb: Vector3 = cap[1]
			var cr: float = cap[2]
			t = ray_capsule(o, n, ca, cb, cr)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = s
	var mk := marker_at(view, screen)
	if not mk.is_empty() and not bool_of(mk[2]):
		var md: float = mk[1]
		if md < best_t or rollback_marker_first:
			var mu: int = mk[0]
			for s in ships:
				if s.uid == mu:
					best = s
					best_t = md
	if best != null:
		return best
	return nearest(view, screen, NEAR_PX)


## Знак под точкой экрана: [uid, глубина его корабля, звено ли]; пусто — нет (или откат).
static func marker_at(view: Node3D, screen: Vector2) -> Array:
	if rollback_no_markers:
		return []
	var m: Object = view.get("markers")
	if m == null:
		return []
	var got: Array = m.call("hit_at", screen)
	return got


static func bool_of(v: Variant) -> bool:
	return v == true


## Чей корпус ТОЧНО под точкой: только капсула, без «ближайшего в 30 точках» (охрана
## своего — только прямым попаданием, 03, ловушка 14: щедрая зона заведена ради врага).
static func pick_hull(view: Node3D, screen: Vector2) -> Ship:
	var cam := _cam(view)
	if cam == null:
		return null
	var o := cam.project_ray_origin(screen)
	var n := cam.project_ray_normal(screen)
	var my_side: int = view.get("my_side")
	var best: Ship = null
	var best_t := INF
	for s in _ships(view.get("battle")):
		if not shown(s, my_side):
			continue
		var cap: Array = view.call("capsule", s)
		var ca: Vector3 = cap[0]
		var cb: Vector3 = cap[1]
		var cr: float = cap[2]
		var t := ray_capsule(o, n, ca, cb, cr)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = s
	return best


## Ближайший центр в px точках экрана (перед камерой).
static func nearest(view: Node3D, screen: Vector2, px: float) -> Ship:
	var cam := _cam(view)
	if cam == null:
		return null
	var ships: Array[Ship] = _ships(view.get("battle"))
	var my_side: int = view.get("my_side")
	var best: Ship = null
	var best_d := px
	for s in ships:
		if not shown(s, my_side):
			continue
		var c: Vector3 = view.call("ship_point", s)
		if cam.is_position_behind(c):
			continue
		var d := cam.unproject_position(c).distance_to(screen)
		if d <= best_d:
			best_d = d
			best = s
	return best


## Рамка (06, 2.5): свои живые корабли без станции, чей центр на экране внутри рамки
## (границы включены). → uid.
static func in_box(view: Node3D, rect: Rect2) -> Array[int]:
	var out: Array[int] = []
	var cam := _cam(view)
	if cam == null:
		return out
	var my_side: int = view.get("my_side")
	for s in _ships(view.get("battle")):
		if s.side != my_side or s.station or not shown(s, my_side):
			continue
		var c: Vector3 = view.call("ship_point", s)
		if cam.is_position_behind(c):
			continue
		var p := cam.unproject_position(c)
		var inside := p.x >= rect.position.x and p.x <= rect.end.x and p.y >= rect.position.y and p.y <= rect.end.y
		# рамка берёт корабль и по его знаку (план GИ, п. 6): знак мог отойти от корабля
		var fc: Variant = _marker_center(view, s.uid)
		if not inside and fc != null:
			var fp: Vector2 = fc
			inside = rect.has_point(fp) or (fp.x >= rect.position.x and fp.x <= rect.end.x and fp.y >= rect.position.y and fp.y <= rect.end.y)
		if inside:
			out.append(s.uid)
	return out


## Середина рамки знака (uid) на этом кадре; нет знака (или откат) — null.
static func _marker_center(view: Node3D, uid: int) -> Variant:
	if rollback_no_markers:
		return null
	var m: Object = view.get("markers")
	if m == null:
		return null
	var mk: Object = m.call("mark_of", uid)
	if mk == null:
		return null
	var fr: Rect2 = mk.get("frame")
	return fr.get_center()


static func _cam(view: Node3D) -> Camera3D:
	var rig: Node3D = view.get("rig")
	if rig == null:
		return null
	var c: Camera3D = rig.get("camera")
	return c


static func _ships(b: Variant) -> Array[Ship]:
	var out: Array[Ship] = []
	if typeof(b) != TYPE_OBJECT:
		return out
	var o: Object = b
	if o == null:
		return out
	var list: Array[Ship] = o.get("ships")
	return list



# ───────────────────────── авиация (G3; часть 04, 1.1) ─────────────────────────

## Звено под точкой экрана: ближайшая к курсору машина в 30 точках — её звено целиком
## (машину отдельно выбрать нельзя, 04, 1.1). Фильтр видимости — тот же (C18; 04,
## ловушка 24: скрытая машина прячется так же, как корабль). → [звено, расстояние] или [].
static func pick_squad(view: Node3D, screen: Vector2, px: float = NEAR_PX) -> Array:
	var cam := _cam(view)
	if cam == null:
		return []
	var b: Variant = view.get("battle")
	if typeof(b) != TYPE_OBJECT:
		return []
	var bo: Object = b
	var crafts: Array[Craft] = bo.get("crafts")
	var best: Craft = null
	var best_d := px
	for c in crafts:
		if c.dead or test_hidden.has(c.uid):
			continue
		var p: Vector3 = view.call("craft_point", c)
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(screen)
		if d <= best_d:
			best_d = d
			best = c
	if best == null or best.squad == null:
		return []
	return [best.squad as Squad, best_d]


## Кто под точкой: корабль (капсула корпуса — первым) или звено; ближе к курсору из
## «ближайшего корабля в 30» и «ближайшей машины в 30». → Ship, Squad или null.
static func pick_any(view: Node3D, screen: Vector2) -> RefCounted:
	var cam := _cam(view)
	if cam == null:
		return null
	var hull := pick_hull(view, screen)
	var mk := marker_at(view, screen)
	if not mk.is_empty():
		var md: float = mk[1]
		var hull_t := INF
		if hull != null:
			var cap: Array = view.call("capsule", hull)
			var ca: Vector3 = cap[0]
			var cb: Vector3 = cap[1]
			var cr: float = cap[2]
			hull_t = ray_capsule(cam.project_ray_origin(screen), cam.project_ray_normal(screen), ca, cb, cr)
		if md < hull_t or rollback_marker_first:
			var mu: int = mk[0]
			if bool_of(mk[2]):
				var bo: Object = view.get("battle")
				var mq: Squad = bo.call("squad_by_uid", mu)
				if mq != null:
					return mq
			else:
				for s in _ships(view.get("battle")):
					if s.uid == mu:
						return s
	if hull != null:
		return hull
	var sq := pick_squad(view, screen)
	var near_s := nearest(view, screen, NEAR_PX)
	if sq.is_empty():
		return near_s
	if near_s == null:
		var q0: Squad = sq[0]
		return q0
	var sp: Vector3 = view.call("ship_point", near_s)
	var ds := cam.unproject_position(sp).distance_to(screen)
	var dq: float = sq[1]
	if dq < ds:
		var q1: Squad = sq[0]
		return q1
	return near_s


## Свои звенья, чей центр на экране внутри рамки (06, 2.5; 04, 1.1).
static func squads_in_box(view: Node3D, rect: Rect2) -> Array[int]:
	var out: Array[int] = []
	var cam := _cam(view)
	if cam == null:
		return out
	var my_side: int = view.get("my_side")
	var b: Variant = view.get("battle")
	if typeof(b) != TYPE_OBJECT:
		return out
	var bo: Object = b
	var squads: Array[Squad] = bo.get("squads")
	for q in squads:
		if q.dead or q.side != my_side:
			continue
		var c: Vector3 = view.call("squad_point", q)
		if cam.is_position_behind(c):
			continue
		var p := cam.unproject_position(c)
		if p.x >= rect.position.x and p.x <= rect.end.x and p.y >= rect.position.y and p.y <= rect.end.y:
			out.append(q.uid)
	return out
