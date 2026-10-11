# input/picking.gd — кто под курсором (архитектура, 4; часть 06, 2.4.4). Своя функция
# без физического движка, в порядке части 06:
#   1. луч по КАПСУЛЕ КОРПУСА — по длине и ширине модели из выгрузки и по
#      НАРИСОВАННОМУ (интерполированному) положению и курсу; ближайшее попадание
#      вдоль луча. Кораблём считается корпус, а не свечение и не факел (C29; 08,
#      ловушка 10): эффектов в списке кандидатов нет по устройству;
#   2. подпись — G7 (подписей ещё нет);
#   3. ближайший центр в 30 точках экрана.
# Скрытые и мёртвые отсекаются ОДНИМ фильтром видимости (shown) — тем же, что
# у кораблей на экране, колец и (с G6–G7) подписей и миникарты (C18; 04, ловушка 21).
extends RefCounted

const Ship := preload("res://sim/ship.gd")

## «Ближайший» — центр корабля на экране не дальше 30 точек (06, 2.4.3).
const NEAR_PX := 30.0

## ТОЛЬКО для проверки отката «малый за факелом» (08, ловушка 10): выбирать по рамке
## всего нарисованного (с факелами), а не по капсуле корпуса. В игре всегда false.
static var rollback_drawn_box := false


## Единый фильтр видимости: живой и (свой или видимый нам). Скрытности в срезе нет
## (sim/vision.gd «видит всегда» — G2); когда появится, её спрашивают ЗДЕСЬ, и тогда
## выбор, корабль на экране, кольцо и подпись разойтись не могут.
static func shown(s: Ship, _my_side: int) -> bool:
	return not s.dead


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
	if best != null:
		return best
	# подпись — G7
	return nearest(view, screen, NEAR_PX)


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
		if p.x >= rect.position.x and p.x <= rect.end.x and p.y >= rect.position.y and p.y <= rect.end.y:
			out.append(s.uid)
	return out


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
