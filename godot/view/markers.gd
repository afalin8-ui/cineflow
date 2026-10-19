# view/markers.gd — тактические знаки над кораблями (план GИ, п. 6; решение пользователя
# 19.10.2026: «значок класса в рамке», как в стратегиях вроде Empire at War).
# Над каждым кораблём — рамка цвета СТОРОНЫ с простым значком класса (флагман, крейсер,
# «Синхо», носитель, РЭБ, фрегат, корвет, станция) и тонкой полоской прочности под ней;
# над звеном — маленькая рамка со значком РОЛИ звена (не по машине). Размер постоянный
# в точках экрана: знак читается и на пределе камеры 5000, где корабль — пара точек.
# - Свой и чужой различаются и ЦВЕТОМ (мятный / красный, 07, 2.1, C43), и ФОРМОЙ рамки: своя
#   сторона — прямоугольник, чужая — шестиугольник с острыми боками. Цвет без формы при
#   цветовой слепоте не читается; форма без цвета — издали. В «ИИ против ИИ» и в зеркальном
#   бою — так же по СТОРОНЕ (сторона атакующего — «своя» рамка), а не по клану: у зеркала
#   кланы одинаковые.
# - Имя — только у того, что под курсором, и у выбранных (решение пользователя). Имя —
#   часть места знака: значок на имя не ложится по устройству.
# - КАША НА ДАЛЬНЕМ ПЛАНЕ: знаки раскладываются по важности (под курсором → выбран → класс →
#   крупнее на экране) и не наезжают друг на друга ВОВСЕ. Знак, которому на своём месте
#   тесно, отходит в ближайшее свободное место (до двух шагов в сторону) с тонкой линией
#   к своему кораблю; места нет и там — знак СКЛАДЫВАЕТСЯ в соседний знак своей стороны,
#   и тот пишет «+N». Имя, которому тесно, пропадает раньше значка (кроме того, что под
#   курсором). Корабль со сложенным знаком виден моделью и выбирается щелчком по ней.
# - Выше шапки и под панелями знаков нет (avoid, top — их даёт экран боя каждый кадр).
# - Выбор: hits — прямоугольники знаков с uid и глубиной корабля (input/picking.gd: знак —
#   «не дальше своего корабля по лучу», ближний корпус перед ним важнее).
# Рисуется одним узлом (_draw): сотня знаков — сотня вызовов рисования на одном холсте,
# а не сотня узлов. Раскладка — каждый кадр (камера и корабли движутся), сетка по 32 точки.
extends CanvasLayer

const Ship := preload("res://sim/ship.gd")
const Squad := preload("res://sim/squad.gd")
const Craft := preload("res://sim/craft.gd")
const Weapons := preload("res://sim/weapons.gd")
const Picking := preload("res://input/picking.gd")

## Цвета сторон (07, 2.1; C43) — те же, что у колец вида.
const SIDE_A := Color(0.56, 1.0, 0.78)
const SIDE_B := Color(1.0, 0.42, 0.35)
## Рамка корабля и звена, точки экрана.
const FRAME := Vector2(26.0, 20.0)
const SQ_FRAME := Vector2(18.0, 14.0)
const BAR_H := 3.0
const BAR_GAP := 2.0
const NAME_SIZE := 13
const NAME_GAP := 2.0
## Зазор между знаками (точки) — «не наезжают» с запасом в точку.
const PAD := 1.0
## Шаг отхода знака от своего места (доли рамки) и сетка поиска соседей.
const CELL := 32.0
## Насколько знак стоит над кораблём: низ полоски — на max(MIN_UP, доля полудлины корпуса).
const MIN_UP := 8.0
const UP_K := 0.45
## Важность класса (раскладка: важный встаёт первым на своё место).
const RANK := {&"station": 9, &"capital": 8, &"sinho": 7, &"cruiser": 6, &"carrier": 5, &"ecm": 4,
	&"frigate": 3, &"corvette": 2}

## ТОЛЬКО для проверок отката (план GИ), в игре всегда false:
## знаки на своих местах без раскладки — на дальнем плане лежат друг на друге;
static var rollback_no_layout := false
## имя не входит в место знака — значок соседа ложится на буквы;
static var rollback_names_free := false
## знаки и под шапкой (раньше подписи C78 правило «выше шапки нет» держали отдельно);
static var rollback_no_top := false
## одна форма рамки у обеих сторон — различие только цветом (при цветовой слепоте не читается);
static var rollback_one_shape := false
## цвет по КЛАНУ, а не по стороне (C43): в зеркальном бою стороны одного цвета.
static var rollback_clan_color := false
## знак только у корабля, который на экране длиннее 20 точек (как подписи C78 «по близости»):
## на пределе камеры 5000 у корветов и фрегатов знаков нет.
static var rollback_fade_far := false

## Знак на этом кадре. Проверки читают drawn (что нарисовано), а не экран.
class Mark:
	var uid := 0
	var squad := false
	var side := 0
	var clan: StringName
	var kind: StringName
	var p := Vector2.ZERO           # корабль на экране
	var rpx := 0.0                  # полудлина корпуса на экране
	var sel := false
	var hover := false
	var hp := 1.0
	var depth := 0.0                # от камеры до корабля (выбор по лучу)
	var label := ""
	var jump := false
	var pri := 0.0
	# раскладка
	var unit := Rect2()             # всё место знака: рамка, полоска, имя
	var frame := Rect2()
	var bar := Rect2()
	var name_r := Rect2()
	var name := ""                  # нарисованное имя (пусто — без имени)
	var moved := false              # отошёл от своего места — линия к кораблю
	var anchor := Vector2.ZERO
	var di := 0                     # какой отход из TRY взят
	var more := 0                   # сложено в этот знак
	var badge := Rect2()


## Вид боя (view/battle_view.gd): модель, камера, нарисованные положения, выбор, курсор.
var view: Node3D
## Знаки включены (кнопка «Знаки» и I; помнится — view/settings.gd).
var on := true
## Куда знакам нельзя: панели экрана боя (их прямоугольники) и низ шапки.
var avoid: Array[Rect2] = []
var top := 0.0
## Что нарисовано на этом кадре.
var drawn: Array[Mark] = []
## Сложено в соседние знаки (uid) — у этих кораблей своего знака на кадре нет.
var folded: Array[int] = []
var _canvas: Control
var _font: Font
## Отход каждого знака на прошлом кадре (uid → номер в TRY): знак под курсором и выбранный
## сначала пробуют прежнее место. Иначе наведение поднимает знак в важности, он встаёт на своё
## место — и уезжает из-под курсора, а щелчок, который шёл по нему, приходится в пустоту.
var _last_di: Dictionary[int, int] = {}
## ТОЛЬКО для проверки отката (план GИ): знак под курсором встаёт заново, без памяти о прошлом
## месте. В игре false.
static var rollback_hover_jumps := false
## ТОЛЬКО для проверки отката: имя только у выбранных — под курсором его нет. В игре false.
static var rollback_hover_no_name := false
var _name_w: Dictionary[String, float] = {}


func _ready() -> void:
	layer = 5                         # ниже экрана боя (10): шапка и панели — поверх знаков (C78)
	_canvas = Control.new()
	_canvas.name = "MarkersCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)
	_font = ThemeDB.fallback_font


## Цвет стороны знака (по стороне, а не по клану; откат — по клану).
func side_color(side: int, clan: StringName) -> Color:
	var my_side: int = view.get("my_side")
	if rollback_clan_color:
		return SIDE_A if clan == &"troyden" else SIDE_B
	return SIDE_A if side == my_side else SIDE_B


## Форма рамки стороны: &"rect" — своя (атакующий в «ИИ против ИИ»), &"hex" — чужая.
func side_shape(side: int) -> StringName:
	var my_side: int = view.get("my_side")
	if rollback_one_shape:
		return &"rect"
	return &"rect" if side == my_side else &"hex"


## Значок корабля по классу: id корабля, у станции — station.
static func kind_of(s: Ship) -> StringName:
	if s.station:
		return &"station"
	if RANK.has(s.def.id):
		return s.def.id
	return &"capital" if s.def.cls == &"capital" else &"corvette"


func _name_width(text: String) -> float:
	if _name_w.has(text):
		return _name_w[text]
	if _name_w.size() > 500:
		_name_w.clear()
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
	_name_w[text] = w
	return w


## Раскладка знаков на этот кадр (зовёт вид после того, как расставил корабли).
func layout() -> void:
	drawn.clear()
	folded.clear()
	if not on or view == null:
		_canvas.queue_redraw()
		return
	var b: Object = view.get("battle")
	var rig: Node3D = view.get("rig")
	var cam: Camera3D = rig.get("camera") if rig != null else null
	if b == null or cam == null:
		_canvas.queue_redraw()
		return
	var vs := _canvas.get_viewport_rect().size
	var my_side: int = view.get("my_side")
	var sel: Array[int] = view.get("selection")
	var hover: int = view.get("hover_uid")
	var right := cam.global_transform.basis.x
	var items: Array[Mark] = []
	var sides: Array = b.get("sides")
	var ships: Array = b.get("ships")
	for o: Object in ships:
		var s := o as Ship
		if not Picking.shown(s, my_side):
			continue
		var vis: Node3D = view.call("visual_of", s)
		if vis == null:
			continue
		var pt: Vector3 = vis.global_position
		if cam.is_position_behind(pt):
			continue
		var p := cam.unproject_position(pt)
		if p.x < -60.0 or p.y < -60.0 or p.x > vs.x + 60.0 or p.y > vs.y + 60.0:
			continue
		var vlen: float = vis.call("length")
		var m := Mark.new()
		m.rpx = cam.unproject_position(pt + right * maxf(vlen, 1.0) * 0.5).distance_to(p)
		if rollback_fade_far and m.rpx < 10.0:
			continue
		m.uid = s.uid
		m.side = s.side
		var sd: Object = sides[s.side]
		m.clan = sd.get("clan")
		m.kind = kind_of(s)
		m.p = p
		m.sel = s.uid in sel
		m.hover = s.uid == hover
		m.hp = s.hp_frac()
		m.depth = cam.global_position.distance_to(pt)
		m.label = Weapons.short_name(s)
		m.jump = s.charging()
		var rk: int = RANK.get(m.kind, 1)
		m.pri = (4.0e6 if m.hover else 0.0) + (2.0e6 if m.sel else 0.0) + float(rk) * 1000.0 + m.rpx
		items.append(m)
	var squads: Array = b.get("squads")
	for o2: Object in squads:
		var q := o2 as Squad
		if q.dead or q.craft.is_empty():
			continue
		if q.side != my_side and _all_hidden(q):
			continue
		var qp: Vector3 = view.call("squad_point", q)
		if cam.is_position_behind(qp):
			continue
		var p2 := cam.unproject_position(qp)
		if p2.x < -60.0 or p2.y < -60.0 or p2.x > vs.x + 60.0 or p2.y > vs.y + 60.0:
			continue
		var hpq := 0.0
		for c in q.craft:
			hpq += c.hp_frac()
		var mq := Mark.new()
		mq.uid = q.uid
		mq.squad = true
		mq.side = q.side
		var sd2: Object = sides[q.side]
		mq.clan = sd2.get("clan")
		mq.kind = q.role
		mq.p = p2
		mq.rpx = 6.0
		mq.sel = q.uid in sel
		mq.hover = q.uid == hover
		mq.hp = hpq / float(q.craft.size())
		mq.depth = cam.global_position.distance_to(qp)
		mq.label = "%s ×%d" % [_role_short(b, q.role), q.craft.size()]
		mq.pri = (4.0e6 if mq.hover else 0.0) + (2.0e6 if mq.sel else 0.0) + 500.0
		items.append(mq)
	items.sort_custom(func(x: Mark, y: Mark) -> bool: return x.pri > y.pri)
	var grid: Dictionary[Vector2i, Array] = {}
	var placed: Array[Rect2] = []
	for m in items:
		var want_name := (m.hover and not rollback_hover_no_name) or m.sel
		var got := _place(m, want_name, vs, grid, placed)
		if got != PLACED and want_name:
			got = _place(m, false, vs, grid, placed)
		if got == PLACED:
			drawn.append(m)
		elif got == CROWDED:
			folded.append(m.uid)
			_fold_into(m)
	_badges(vs, placed)
	_last_di.clear()
	for m in drawn:
		_last_di[m.uid] = m.di
	_canvas.queue_redraw()


func _all_hidden(q: Squad) -> bool:
	for c in q.craft:
		if not c.dead and not Picking.test_hidden.has(c.uid):
			return false
	return true


static func _role_short(b: Object, role: StringName) -> String:
	var defs: Object = b.get("defs")
	var roles: Dictionary = defs.get("strike_roles")
	var rd: Object = roles.get(role)
	return str(rd.get("short")) if rd != null else str(role)


## Отходы знака от своего места (в шагах рамки): сначала на месте, потом вверх и в стороны,
## потом вниз; два кольца.
const TRY: Array[Vector2] = [Vector2(0, 0), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, -1), Vector2(1, -1),
	Vector2(0, 1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, -2), Vector2(-2, 0), Vector2(2, 0),
	Vector2(-2, -1), Vector2(2, -1), Vector2(-1, -2), Vector2(1, -2), Vector2(0, 2), Vector2(-2, 1), Vector2(2, 1)]
## Исход раскладки знака: поставлен · тесно (сложить в соседа) · спрятан правилом (шапка,
## панель, край окна) — такой не складываем: корабль просто под панелью.
const PLACED := 0
const CROWDED := 1
const HIDDEN := 2


## Место знака: рамка, полоска и (если надо) имя; свободное от уже поставленных, в окне,
## не выше шапки и не под панелями. Нашлось — поля раскладки у m заполнены.
func _place(m: Mark, with_name: bool, vs: Vector2, grid: Dictionary[Vector2i, Array], placed: Array[Rect2]) -> int:
	var fr := SQ_FRAME if m.squad else FRAME
	var up := maxf(MIN_UP, m.rpx * UP_K)
	var base := Vector2(m.p.x, m.p.y - up)          # низ полоски
	var nw := _name_width(m.label) + 6.0 if with_name else 0.0
	var nh := float(NAME_SIZE) + 3.0
	var step := Vector2(fr.x + 4.0, fr.y + BAR_H + BAR_GAP + (nh * 0.5 if with_name else 0.0))
	var tries: Array[Vector2] = TRY
	var idx: Array[int] = []
	for i in TRY.size():
		idx.append(i)
	if (m.hover or m.sel) and _last_di.has(m.uid) and not rollback_hover_jumps:
		idx.push_front(_last_di[m.uid])
	if rollback_no_layout:
		idx = [0]
	var rules_any := false
	for i in idx:
		var d := tries[i]
		var a := base + Vector2(d.x * step.x, d.y * step.y)
		var bar := Rect2(a.x - fr.x * 0.5, a.y - BAR_H, fr.x, BAR_H)
		var frame := Rect2(a.x - fr.x * 0.5, bar.position.y - BAR_GAP - fr.y, fr.x, fr.y)
		var unit := frame.merge(bar)
		var name_r := Rect2()
		if with_name:
			name_r = Rect2(a.x - nw * 0.5, frame.position.y - NAME_GAP - nh, nw, nh)
			if not rollback_names_free:
				unit = unit.merge(name_r)
		if not _rules_ok(unit, vs):
			continue
		rules_any = true
		if not rollback_no_layout and _hits_placed(unit, grid, placed):
			continue
		_add(unit, grid, placed)
		m.unit = unit
		m.frame = frame
		m.bar = bar
		m.name_r = name_r
		m.name = m.label if with_name else ""
		m.moved = d != Vector2.ZERO
		m.anchor = a
		m.di = i
		return PLACED
	return CROWDED if rules_any else HIDDEN


## Знак в окне, ниже шапки и не под панелями экрана боя.
func _rules_ok(r: Rect2, vs: Vector2) -> bool:
	if r.position.x < 0.0 or r.end.x > vs.x or r.end.y > vs.y or r.position.y < 0.0:
		return false
	if not rollback_no_top and r.position.y < top:
		return false
	for a in avoid:
		if a.intersects(r):
			return false
	return true


func _cells(r: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cx in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
		for cy in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
			out.append(Vector2i(cx, cy))
	return out


func _hits_placed(r: Rect2, grid: Dictionary[Vector2i, Array], placed: Array[Rect2]) -> bool:
	var g := r.grow(PAD)
	for c in _cells(g):
		var list: Array = grid.get(c, [])
		for i: int in list:
			if placed[i].intersects(g):
				return true
	return false


func _add(r: Rect2, grid: Dictionary[Vector2i, Array], placed: Array[Rect2]) -> void:
	placed.append(r)
	var i := placed.size() - 1
	for c in _cells(r):
		if not grid.has(c):
			grid[c] = []
		grid[c].append(i)


## Знак, которому нет места, складывается в ближайший знак своей стороны: тот пишет «+N».
func _fold_into(m: Mark) -> void:
	var best: Mark = null
	var bd := INF
	for d in drawn:
		if d.side != m.side or d.squad != m.squad:
			continue
		var dd := d.p.distance_to(m.p)
		if dd < bd:
			bd = dd
			best = d
	if best != null:
		best.more += 1


## Место под «+N» у сложивших: справа от рамки, нет — слева, нет — внутри угла рамки.
func _badges(vs: Vector2, placed: Array[Rect2]) -> void:
	for d in drawn:
		if d.more <= 0:
			continue
		var txt := "+%d" % d.more
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 4.0
		var cands: Array[Rect2] = [Rect2(d.frame.end.x + 1.0, d.frame.position.y, w, 13.0), Rect2(d.frame.position.x - 1.0 - w, d.frame.position.y, w, 13.0)]
		var got := Rect2()
		for c in cands:
			if not _rules_ok(c, vs):
				continue
			var clash := false
			for r in placed:
				if r != d.unit and r.grow(PAD).intersects(c):
					clash = true
					break
			if not clash:
				got = c
				break
		if not got.has_area():
			got = Rect2(d.frame.end.x - w, d.frame.position.y, w, 11.0)    # внутри угла своей рамки
		else:
			placed.append(got)
		d.badge = got


## Знак под точкой экрана: [uid, глубина корабля, звено ли]; пусто — нет.
func hit_at(screen: Vector2) -> Array:
	if not on:
		return []
	for d in drawn:
		if d.frame.grow(2.0).has_point(screen) or d.bar.grow(2.0).has_point(screen) or (d.name_r.has_area() and d.name_r.has_point(screen)):
			return [d.uid, d.depth, d.squad]
	return []


## Знак корабля или звена на этом кадре; нет — null.
func mark_of(uid: int) -> Mark:
	for d in drawn:
		if d.uid == uid:
			return d
	return null


# ───────────────────────── рисование ─────────────────────────

func _draw_all() -> void:
	var c := _canvas
	for d in drawn:
		var col := side_color(d.side, d.clan)
		var fr := d.frame
		if d.moved:
			c.draw_line(Vector2(d.anchor.x, fr.end.y + BAR_GAP + BAR_H), d.p, Color(col.r, col.g, col.b, 0.45), 1.0, true)
		var edge := col.lerp(Color.WHITE, 0.55) if d.hover else col
		var w := 2.5 if d.sel else 1.5
		var shape := side_shape(d.side)
		if d.sel:
			_frame(c, fr.grow(2.5), shape, Color(0, 0, 0, 0), Color(col.r, col.g, col.b, 0.35), 3.0)
		var fill := Color(0.05, 0.12, 0.2, 0.85) if d.jump else Color(0.02, 0.03, 0.05, 0.72)
		_frame(c, fr, shape, fill, edge, w)
		var gc := col.lerp(Color.WHITE, 0.25) if d.sel or d.hover else col
		_glyph(c, d.kind, fr.get_center(), gc, d.squad)
		c.draw_rect(d.bar, Color(0, 0, 0, 0.7))
		c.draw_rect(Rect2(d.bar.position, Vector2(d.bar.size.x * clampf(d.hp, 0.0, 1.0), d.bar.size.y)), col)
		if d.name != "":
			var tp := Vector2(d.name_r.position.x + 3.0, d.name_r.end.y - 4.0)
			var tc := Color(1, 1, 1) if d.hover else col.lerp(Color.WHITE, 0.6)
			c.draw_string_outline(_font, tp, d.name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, 4, Color(0, 0, 0, 0.9))
			c.draw_string(_font, tp, d.name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, tc)
		if d.badge.has_area():
			c.draw_rect(d.badge, Color(0.02, 0.03, 0.05, 0.85))
			c.draw_string(_font, Vector2(d.badge.position.x + 2.0, d.badge.end.y - 2.0), "+%d" % d.more, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


## Рамка: прямоугольник (своя сторона) или шестиугольник с острыми боками (чужая).
static func _frame(c: Control, r: Rect2, shape: StringName, fill: Color, edge: Color, w: float) -> void:
	var pts := PackedVector2Array()
	if shape == &"hex":
		var k := minf(r.size.y * 0.5, 6.0)
		var my := r.position.y + r.size.y * 0.5
		pts = PackedVector2Array([Vector2(r.position.x + k, r.position.y), Vector2(r.end.x - k, r.position.y),
			Vector2(r.end.x, my), Vector2(r.end.x - k, r.end.y), Vector2(r.position.x + k, r.end.y), Vector2(r.position.x, my)])
	else:
		pts = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	if fill.a > 0.0:
		c.draw_colored_polygon(pts, fill)
	var loop := pts.duplicate()
	loop.append(pts[0])
	c.draw_polyline(loop, edge, w, true)


## Значок класса (или роли звена) в рамке, по середине c.
static func _glyph(c: Control, kind: StringName, o: Vector2, col: Color, small: bool) -> void:
	var s := 0.7 if small else 1.0
	match kind:
		&"capital":                               # флагман — ромб
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(0, -6.5), o + Vector2(7, 0), o + Vector2(0, 6.5), o + Vector2(-7, 0)]), col)
		&"cruiser":                               # крейсер — треугольник
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(0, -5.5), o + Vector2(6.5, 5), o + Vector2(-6.5, 5)]), col)
		&"sinho":                                 # «Синхо», ракетный — стрела вверх с оперением
			c.draw_line(o + Vector2(0, 6), o + Vector2(0, -5), col, 2.0, true)
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(0, -7), o + Vector2(4.5, -1.5), o + Vector2(-4.5, -1.5)]), col)
			c.draw_line(o + Vector2(-4, 6), o + Vector2(0, 3), col, 1.5, true)
			c.draw_line(o + Vector2(4, 6), o + Vector2(0, 3), col, 1.5, true)
		&"carrier":                               # носитель — палуба и «крылья» звена над ней
			c.draw_rect(Rect2(o + Vector2(-8, 1.5), Vector2(16, 4)), col)
			c.draw_polyline(PackedVector2Array([o + Vector2(-4, -1.5), o + Vector2(0, -5.5), o + Vector2(4, -1.5)]), col, 1.6, true)
		&"ecm":                                   # РЭБ — излучатель и волны
			c.draw_circle(o, 2.0, col)
			c.draw_arc(o, 4.5, -0.9, 0.9, 8, col, 1.4, true)
			c.draw_arc(o, 4.5, PI - 0.9, PI + 0.9, 8, col, 1.4, true)
			c.draw_arc(o, 7.5, -0.7, 0.7, 8, col, 1.4, true)
			c.draw_arc(o, 7.5, PI - 0.7, PI + 0.7, 8, col, 1.4, true)
		&"frigate":                               # фрегат — круг
			c.draw_circle(o, 4.5, col)
		&"corvette":                              # корвет — шеврон
			c.draw_polyline(PackedVector2Array([o + Vector2(-5.5, 3.5), o + Vector2(0, -3.5), o + Vector2(5.5, 3.5)]), col, 2.2, true)
		&"station":                               # станция — квадрат с проёмом
			c.draw_rect(Rect2(o - Vector2(6, 6), Vector2(12, 12)), col)
			c.draw_rect(Rect2(o - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.02, 0.03, 0.05, 1.0))
		&"interceptor":                           # перехватчик — «ласточка»
			c.draw_polyline(PackedVector2Array([o + Vector2(-5, -3) * s * 1.3, o + Vector2(0, 3) * s * 1.3, o + Vector2(5, -3) * s * 1.3]), col, 1.8, true)
		&"fighter":                               # истребитель — крест
			c.draw_line(o + Vector2(-4, -4) * s * 1.2, o + Vector2(4, 4) * s * 1.2, col, 1.8, true)
			c.draw_line(o + Vector2(4, -4) * s * 1.2, o + Vector2(-4, 4) * s * 1.2, col, 1.8, true)
		&"bomber":                                # бомбардировщик — капля вниз
			c.draw_colored_polygon(PackedVector2Array([o + Vector2(-4.5, -3.5) * s * 1.2, o + Vector2(4.5, -3.5) * s * 1.2, o + Vector2(0, 4) * s * 1.2]), col)
		_:
			c.draw_circle(o, 3.0, col)
