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
#   часть места знака: значок на имя не ложится по устройству. Над рамкой тесно — справа или
#   слева от неё; знак под курсором и выбранный при этом с места не сходят (иначе щелчок по
#   знаку уходит в соседа).
# - КАША НА ДАЛЬНЕМ ПЛАНЕ: знаки раскладываются по важности (под курсором → выбран → класс →
#   крупнее на экране) и не наезжают друг на друга ВОВСЕ. Знак, которому на своём месте
#   тесно, отходит в ближайшее свободное место (до двух шагов в сторону) с тонкой линией
#   к своему кораблю; места нет и там — знак СКЛАДЫВАЕТСЯ в соседний знак своей стороны,
#   и тот пишет «+N». Имя, которому тесно, пропадает раньше значка (кроме того, что под
#   курсором). Корабль со сложенным знаком виден моделью и выбирается щелчком по ней.
# - Выше шапки и под панелями знаков нет (avoid, top — их даёт экран боя каждый кадр). Корабль
#   под самой шапкой получает знак сразу под ней, с линией вверх к кораблю (UNDER_TOP).
# - Выбор: hits — прямоугольники знаков с uid и глубиной корабля (input/picking.gd: знак —
#   «не дальше своего корабля по лучу»: корпус перед ним важнее, только если ближе к камере
#   на десятую долю, Picking.MARKER_HULL_AHEAD).
# Рисуется одним узлом (_draw): сотня знаков — сотня вызовов рисования на одном холсте,
# а не сотня узлов. Раскладка — каждый кадр (камера и корабли движутся), сетка по 32 точки.
extends CanvasLayer

const Ship := preload("res://sim/ship.gd")
const Squad := preload("res://sim/squad.gd")
const Craft := preload("res://sim/craft.gd")
const Weapons := preload("res://sim/weapons.gd")
const Picking := preload("res://input/picking.gd")

## Цвета сторон (07, 2.1; C43) — одно место на знаки, кольца и шапку (view/side_colors.gd).
const SideColors := preload("res://view/side_colors.gd")
const SIDE_A := SideColors.OWN
const SIDE_B := SideColors.FOE
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
## Отход каждого знака на прошлом кадре (uid → номер в TRY): знак под курсором ОСТАЁТСЯ на прежнем
## месте — с именем, если имя там влезает, иначе без имени. Иначе наведение поднимает знак в
## важности и даёт ему имя, он ищет место — и уезжает из-под курсора, а щелчок, который шёл по
## нему, приходится в соседа или в пустоту (замечание к GИ: 1–2 промаха из 30). Выбранный, но не
## под курсором — НЕ липкий (пакет GТ, хвост GИ): он, как все, сперва пробует своё место. Липкость
## выбранного держала знак в отходе насовсем: «Весь флот» (F2) на пределе 5000 разгонял знаки по
## отходам, и вернувшись к стартовой камере, где тесноты уже нет, они так и стояли в стороне от
## своих кораблей с линиями-выносками.
var _last_di: Dictionary[int, int] = {}
## ТОЛЬКО для проверки отката (пакет GТ) — как в capella-v0.7.1: выбранный знак тоже липкий и
## остаётся в отходе, хотя своё место уже свободно. В игре false.
static var rollback_sel_sticky := false
## ТОЛЬКО для проверки отката (пакет GТ, хвост GИ) — одна часть отката rollback_name_moves: шаг
## отхода считается с именем, и рамка того же отхода с именем стоит на полимени ниже-выше, чем
## без имени — знак, получив имя под курсором, сдвигается. В игре false.
static var rollback_step_by_name := false
## ТОЛЬКО для проверки отката (план GИ): знак под курсором встаёт заново, без памяти о прошлом
## месте. В игре false.
static var rollback_hover_jumps := false
## ТОЛЬКО для проверки отката (замечание к GИ) — как в capella-v0.7: знак под курсором сначала
## ищет место С ИМЕНЕМ (где угодно) и только потом остаётся на прежнем без имени, а шаг отхода
## зависит от имени — рамка того же отхода с именем стоит в другом месте. В игре false.
static var rollback_name_moves := false
## ТОЛЬКО для проверки отката: имя только у выбранных — под курсором его нет. В игре false.
static var rollback_hover_no_name := false
## ТОЛЬКО для проверки отката (замечание к GИ): полоска прочности под знаком всегда полная. В игре
## false.
static var rollback_hp_full := false
## ТОЛЬКО для проверки отката (замечание к GИ): выбранный знак рисуется как невыбранный — без
## толстой кромки и ореола. В игре false.
static var rollback_sel_plain := false
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


## Раскладка за кадр (пакет GТ, хвост GИ). Раскладка стоила ~3,5 мс на кадр в худшем бою и
## делалась КАЖДЫЙ кадр, даже на паузе с неподвижной камерой. Теперь сначала собирается только
## дешёвое — точки кораблей на экране и их признаки (выбран, под курсором, прочность, гипер), — и
## если ничего не сдвинулось больше SAME_PX с прошлой раскладки, раскладки и перерисовки нет:
## холст держит прежний рисунок. Отставание знака от корабля — меньше SAME_PX, и оно не копится:
## сравнение идёт с точками ПРОШЛОЙ РАСКЛАДКИ, а не прошлого кадра. Сама раскладка не заводит
## массивов на каждую пробу места (сетка соседей — плоская, места и имена считаются по номеру).
const SAME_PX := 0.5
## …и глубина (от камеры до корабля) не изменилась больше чем на эту долю (1%: покачивание вида —
## ±3 единицы — на рабочем виде 2400 его не переходит; выбор по лучу различает 10%).
const SAME_DEPTH := 0.01
## Сколько раз раскладка сделана и сколько раз пропущена (проверки читают; в игре — для замера).
var relaid := 0
var reused := 0
## ТОЛЬКО для проверки отката (пакет GТ): раскладка каждый кадр, как в capella-v0.7.1. В игре false.
static var rollback_relayout_always := false
## ТОЛЬКО для проверки отката (пакет GТ): пропуск раскладки смотрит лишь на точки экрана — корабль,
## ушедший вдоль луча камеры, остаётся со старой глубиной знака. В игре false.
static var rollback_screen_only := false
# собранное на этом кадре (_g_*) и на прошлой раскладке (_s_*) — меняются местами, без копий
var _g_obj: Array[Object] = []
var _g_pt := PackedVector3Array()
var _g_p := PackedVector2Array()
var _g_uid := PackedInt64Array()
var _g_hp := PackedFloat64Array()
var _g_fl := PackedInt32Array()
var _s_obj: Array[Object] = []
var _s_pt := PackedVector3Array()
var _s_p := PackedVector2Array()
var _s_uid := PackedInt64Array()
var _s_hp := PackedFloat64Array()
var _s_fl := PackedInt32Array()
var _s_ok := false
var _s_vs := Vector2.ZERO
var _s_top := 0.0
var _s_avoid: Array[Rect2] = []
var _s_cam := Transform3D()
var _s_rb := 0
var _s_side := -1
# постоянное у корабля — один раз на корабль (имя, длина модели)
var _lab: Dictionary[int, String] = {}
var _vlen: Dictionary[int, float] = {}
# сетка соседей: ячейки CELL × CELL по окну, у ячейки — список записей (голова и «следующий»)
var _placed: Array[Rect2] = []
var _gw := 1
var _gh := 1
var _head := PackedInt32Array()
var _nxt := PackedInt32Array()
var _ent := PackedInt32Array()


## Знаков нет вовсе (выключены, нет боя или камеры) — и раскладку на следующем кадре делать заново.
func _reset() -> void:
	drawn.clear()
	folded.clear()
	_s_ok = false
	_canvas.queue_redraw()


## Флажки отката как одно число: переключили посреди боя — раскладка заново.
static func _rb_mask() -> int:
	var flags: Array[bool] = [rollback_no_layout, rollback_names_free, rollback_no_top, rollback_one_shape,
		rollback_clan_color, rollback_fade_far, rollback_hover_jumps, rollback_name_moves, rollback_hover_no_name,
		rollback_hp_full, rollback_sel_plain, rollback_sel_sticky, rollback_step_by_name, rollback_no_under_top,
		rollback_badge_on_name]
	var m := 0
	for i in flags.size():
		if flags[i]:
			m |= 1 << i
	return m


## Раскладка знаков на этот кадр (зовёт вид после того, как расставил корабли).
func layout() -> void:
	if not on or view == null:
		_reset()
		return
	var b: Object = view.get("battle")
	var rig: Node3D = view.get("rig")
	var cam: Camera3D = rig.get("camera") if rig != null else null
	if b == null or cam == null:
		_reset()
		return
	var vs := _canvas.get_viewport_rect().size
	var my_side: int = view.get("my_side")
	var sel: Array[int] = view.get("selection")
	var hover: int = view.get("hover_uid")
	var vmap: Dictionary = view.get("_vis")
	# 1) дёшево: точки на экране и признаки
	_g_obj.clear()
	_g_pt.clear()
	_g_p.clear()
	_g_uid.clear()
	_g_hp.clear()
	_g_fl.clear()
	var ships: Array = b.get("ships")
	for o: Object in ships:
		var s := o as Ship
		if not Picking.shown(s, my_side):
			continue
		var vis: Node3D = vmap.get(s.uid)
		if vis == null:
			continue
		var pt: Vector3 = vis.global_position
		if cam.is_position_behind(pt):
			continue
		var p := cam.unproject_position(pt)
		if p.x < -60.0 or p.y < -60.0 or p.x > vs.x + 60.0 or p.y > vs.y + 60.0:
			continue
		_g_obj.append(s)
		_g_pt.append(pt)
		_g_p.append(p)
		_g_uid.append(s.uid)
		_g_hp.append(s.hp_frac())
		_g_fl.append((1 if s.uid in sel else 0) | (2 if s.uid == hover else 0) | (4 if s.charging() else 0) | (s.side << 4))
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
		_g_obj.append(q)
		_g_pt.append(qp)
		_g_p.append(p2)
		_g_uid.append(q.uid)
		_g_hp.append(hpq / float(q.craft.size()) + float(q.craft.size()) * 10.0)     # и число машин — в подписи
		_g_fl.append((1 if q.uid in sel else 0) | (2 if q.uid == hover else 0) | 8 | (q.side << 4))
	# 2) ничего не сдвинулось с прошлой раскладки — она и остаётся
	var rb := _rb_mask()
	var cxf := cam.global_transform
	if _s_ok and not rollback_relayout_always and vs == _s_vs and top == _s_top and avoid == _s_avoid and rb == _s_rb \
			and my_side == _s_side and _g_uid == _s_uid and _g_fl == _s_fl and _g_hp == _s_hp \
			and cxf.origin.distance_squared_to(_s_cam.origin) < 1e-4:
		var same := true
		var co := cxf.origin
		for i in _g_p.size():
			# и ГЛУБИНА: корабль, ушедший вдоль луча камеры, на экране стоит, а глубина у знака
			# (выбор по лучу, Picking.marker_beats — порог там 10% расстояния) и размер на экране —
			# другие. Допуск — SAME_DEPTH доли расстояния: покачивание вида (±view.bob, идёт и на
			# паузе) его не переходит, и раскладка на паузе по-прежнему не повторяется
			var dn := co.distance_to(_g_pt[i])
			if _g_p[i].distance_squared_to(_s_p[i]) > SAME_PX * SAME_PX or (absf(dn - co.distance_to(_s_pt[i])) > SAME_DEPTH * dn and not rollback_screen_only):
				same = false
				break
		if same:
			reused += 1
			return
	relaid += 1
	_relayout(cam, vs, vmap)
	_s_ok = true
	_s_vs = vs
	_s_top = top
	_s_avoid = avoid.duplicate()
	_s_rb = rb
	_s_side = my_side
	_s_cam = cxf
	# собранное становится прошлым — обменом, без копий
	var t_obj := _s_obj
	_s_obj = _g_obj
	_g_obj = t_obj
	var t_pt := _s_pt
	_s_pt = _g_pt
	_g_pt = t_pt
	var t_p := _s_p
	_s_p = _g_p
	_g_p = t_p
	var t_uid := _s_uid
	_s_uid = _g_uid
	_g_uid = t_uid
	var t_hp := _s_hp
	_s_hp = _g_hp
	_g_hp = t_hp
	var t_fl := _s_fl
	_s_fl = _g_fl
	_g_fl = t_fl


## Раскладка заново по собранному на этом кадре (_g_*).
func _relayout(cam: Camera3D, vs: Vector2, vmap: Dictionary) -> void:
	drawn.clear()
	folded.clear()
	var b: Object = view.get("battle")
	var sides: Array = b.get("sides")
	var right := cam.global_transform.basis.x
	var items: Array[Mark] = []
	for i in _g_obj.size():
		var m := Mark.new()
		m.p = _g_p[i]
		m.uid = _g_uid[i]
		var fl := _g_fl[i]
		m.sel = (fl & 1) != 0
		m.hover = (fl & 2) != 0
		m.depth = cam.global_position.distance_to(_g_pt[i])
		var sh := _g_obj[i] as Ship
		if sh != null:
			if not _vlen.has(sh.uid):
				var vis: Node3D = vmap.get(sh.uid)
				_vlen[sh.uid] = vis.call("length")
				_lab[sh.uid] = Weapons.short_name(sh)
			m.rpx = cam.unproject_position(_g_pt[i] + right * maxf(_vlen[sh.uid], 1.0) * 0.5).distance_to(m.p)
			if rollback_fade_far and m.rpx < 10.0:
				continue
			m.side = sh.side
			var sd: Object = sides[sh.side]
			m.clan = sd.get("clan")
			m.kind = kind_of(sh)
			m.hp = 1.0 if rollback_hp_full else sh.hp_frac()
			m.label = _lab[sh.uid]
			m.jump = (fl & 4) != 0
			var rk: int = RANK.get(m.kind, 1)
			m.pri = (4.0e6 if m.hover else 0.0) + (2.0e6 if m.sel else 0.0) + float(rk) * 1000.0 + m.rpx
		else:
			var q := _g_obj[i] as Squad
			var hpq := 0.0
			for c in q.craft:
				hpq += c.hp_frac()
			m.squad = true
			m.side = q.side
			var sd2: Object = sides[q.side]
			m.clan = sd2.get("clan")
			m.kind = q.role
			m.rpx = 6.0
			m.hp = 1.0 if rollback_hp_full else hpq / float(q.craft.size())
			m.label = "%s ×%d" % [_role_short(b, q.role), q.craft.size()]
			m.pri = (4.0e6 if m.hover else 0.0) + (2.0e6 if m.sel else 0.0) + 500.0
		items.append(m)
	items.sort_custom(func(x: Mark, y: Mark) -> bool: return x.pri > y.pri)
	_grid_begin(vs)
	for m in items:
		var want_name := (m.hover and not rollback_hover_no_name) or m.sel
		var got := CROWDED
		var keep := (m.hover or (m.sel and rollback_sel_sticky)) and _last_di.has(m.uid) and not rollback_hover_jumps
		if keep and not rollback_name_moves:
			# прежнее место — с именем, если влезает, иначе без имени, но НА МЕСТЕ
			got = _place(m, want_name, vs, _last_di[m.uid])
			if got != PLACED and want_name:
				got = _place(m, false, vs, _last_di[m.uid])
		if got != PLACED:
			got = _place(m, want_name, vs, -1, keep and rollback_name_moves)
		if got != PLACED and want_name:
			got = _place(m, false, vs, -1, keep and rollback_name_moves)
		if got == PLACED:
			drawn.append(m)
		elif got == CROWDED:
			folded.append(m.uid)
			_fold_into(m)
	_badges(vs, _placed)
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
## Корабль у верхнего края (его место выше низа шапки): знак встаёт СРАЗУ ПОД шапкой — ряд
## над кораблём и в стороны, потом второй ряд — с линией к кораблю, как у отошедшего (замечание
## к GИ: на старте носители и фрегат противника стояли под шапкой без знаков — отход TRY вниз
## на два шага до низа шапки не доставал). Номера этих мест в раскладке — после TRY.
const UNDER_TOP: Array[Vector2] = [Vector2(0, 0), Vector2(-1, 0), Vector2(1, 0), Vector2(-2, 0), Vector2(2, 0),
	Vector2(0, 1), Vector2(-1, 1), Vector2(1, 1), Vector2(-2, 1), Vector2(2, 1)]
## ТОЛЬКО для проверки отката (замечание к GИ) — как в capella-v0.7: мест под шапкой нет, и у
## корабля под шапкой знака нет вовсе (не сложен — спрятан). В игре false.
static var rollback_no_under_top := false
## Исход раскладки знака: поставлен · тесно (сложить в соседа) · спрятан правилом (шапка,
## панель, край окна) — такой не складываем: корабль просто под панелью.
const PLACED := 0
const CROWDED := 1
const HIDDEN := 2


## Место знака: рамка, полоска и (если надо) имя; свободное от уже поставленных, в окне,
## не выше шапки и не под панелями. Нашлось — поля раскладки у m заполнены. only ≥ 0 — только
## этот отход (прежнее место знака под курсором); old_first — откат rollback_name_moves.
## Места (TRY, потом UNDER_TOP) и места имени перебираются по номеру — массивов на пробу нет.
func _place(m: Mark, with_name: bool, vs: Vector2, only: int = -1, old_first: bool = false) -> int:
	var fr := SQ_FRAME if m.squad else FRAME
	var up := maxf(MIN_UP, m.rpx * UP_K)
	var base := Vector2(m.p.x, m.p.y - up)          # низ полоски
	var nw := _name_width(m.label) + 6.0 if with_name else 0.0
	var nh := float(NAME_SIZE) + 3.0
	# шаг отхода — от рамки, а НЕ от имени: рамка одного и того же отхода с именем и без стоит
	# на одном месте (имя — над рамкой), и знак, получив имя под курсором, не сдвигается
	var step := Vector2(fr.x + 4.0, fr.y + BAR_H + BAR_GAP)
	if (rollback_name_moves or rollback_step_by_name) and with_name:
		step.y += nh * 0.5
	# места: TRY от своего места, а у корабля под шапкой — ещё ряды сразу под шапкой (UNDER_TOP)
	var own_top := base.y - BAR_H - BAR_GAP - fr.y
	var under := not rollback_no_under_top and m.p.y >= 0.0 and own_top < top
	var n_spots := TRY.size() + (UNDER_TOP.size() if under else 0)
	var y0 := top + PAD + fr.y + BAR_GAP + BAR_H        # низ полоски: верх рамки — у низа шапки
	var first := -1
	var count := n_spots
	if only >= 0:
		count = 1 if only < n_spots else 0
	elif old_first and _last_di[m.uid] < n_spots:
		first = _last_di[m.uid]
		count += 1
	if rollback_no_layout:
		count = 1
	var rules_any := false
	for k in count:
		var i := k
		if rollback_no_layout:
			i = 0
		elif only >= 0:
			i = only
		elif first >= 0:
			i = first if k == 0 else k - 1
		var a := Vector2.ZERO
		if i < TRY.size():
			a = base + Vector2(TRY[i].x * step.x, TRY[i].y * step.y)
		else:
			var d := UNDER_TOP[i - TRY.size()]
			a = Vector2(m.p.x + d.x * step.x, y0 + d.y * step.y)
		var bar := Rect2(a.x - fr.x * 0.5, a.y - BAR_H, fr.x, BAR_H)
		var frame := Rect2(a.x - fr.x * 0.5, bar.position.y - BAR_GAP - fr.y, fr.x, fr.y)
		# имя — над рамкой; не влезает — справа или слева от рамки в её ряд (знак при этом на месте:
		# под шапкой, у края, рядом с соседом); у знака, чей корабль ВЫШЕ него (под шапкой), — ещё и
		# под полоской: линия к кораблю уходит вверх, и под знаком имени ничто не мешает
		var n_names := 1
		var sides_ok := with_name and not rollback_name_moves
		var below_ok := with_name and m.p.y < frame.position.y and not rollback_no_under_top
		if with_name:
			n_names = 1 + (2 if sides_ok else 0) + (1 if below_ok else 0)
		var unit0 := frame.merge(bar)
		for ni in n_names:
			var name_r := Rect2()
			if with_name:
				if ni == 0:
					name_r = Rect2(a.x - nw * 0.5, frame.position.y - NAME_GAP - nh, nw, nh)
				elif sides_ok and ni <= 2:
					var ny := frame.position.y + (fr.y - nh) * 0.5
					if ni == 1:
						name_r = Rect2(frame.end.x + NAME_GAP + 1.0, ny, nw, nh)
					else:
						name_r = Rect2(frame.position.x - NAME_GAP - 1.0 - nw, ny, nw, nh)
				else:
					name_r = Rect2(a.x - nw * 0.5, bar.end.y + NAME_GAP, nw, nh)
			var unit := unit0
			if name_r.has_area() and not rollback_names_free:
				unit = unit.merge(name_r)
			if not _rules_ok(unit, vs):
				continue
			rules_any = true
			if not rollback_no_layout and _hits_placed(unit):
				continue
			_add(unit)
			m.unit = unit
			m.frame = frame
			m.bar = bar
			m.name_r = name_r
			m.name = m.label if with_name else ""
			m.moved = i != 0
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


## Сетка соседей на кадр: ячейка CELL × CELL по окну (за краем — крайняя ячейка: сетка только
## указатель, пересечение всё равно проверяется точно), у ячейки — цепочка записей.
func _grid_begin(vs: Vector2) -> void:
	_gw = maxi(1, ceili(vs.x / CELL) + 1)
	_gh = maxi(1, ceili(vs.y / CELL) + 1)
	if _head.size() != _gw * _gh:
		_head.resize(_gw * _gh)
	_head.fill(-1)
	_nxt.clear()
	_ent.clear()
	_placed.clear()


func _hits_placed(r: Rect2) -> bool:
	var g := r.grow(PAD)
	var x0 := clampi(floori(g.position.x / CELL), 0, _gw - 1)
	var x1 := clampi(floori(g.end.x / CELL), 0, _gw - 1)
	var y0 := clampi(floori(g.position.y / CELL), 0, _gh - 1)
	var y1 := clampi(floori(g.end.y / CELL), 0, _gh - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var e := _head[cy * _gw + cx]
			while e >= 0:
				if _placed[_ent[e]].intersects(g):
					return true
				e = _nxt[e]
	return false


func _add(r: Rect2) -> void:
	_placed.append(r)
	var idx := _placed.size() - 1
	var x0 := clampi(floori(r.position.x / CELL), 0, _gw - 1)
	var x1 := clampi(floori(r.end.x / CELL), 0, _gw - 1)
	var y0 := clampi(floori(r.position.y / CELL), 0, _gh - 1)
	var y1 := clampi(floori(r.end.y / CELL), 0, _gh - 1)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c := cy * _gw + cx
			_ent.append(idx)
			_nxt.append(_head[c])
			_head[c] = _ent.size() - 1


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


## ТОЛЬКО для проверки отката (пакет GТ, хвост GИ) — как в capella-v0.7.1: «+N» не видит имени
## своего же знака и ложится на него, когда имя стоит сбоку от рамки. В игре false.
static var rollback_badge_on_name := false


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
			# своё место знака пропускаем (рамка и полоска — «+N» встаёт вплотную к ним), но СВОЁ ИМЯ —
			# препятствие, как чужое: имя сбоку от рамки стоит ровно там, куда просится «+N»
			# (пакет GТ, хвост GИ: проба нашла «+N» на собственном имени в 5 случаях из 16)
			var clash := not rollback_badge_on_name and d.name_r.has_area() and d.name_r.grow(PAD).intersects(c)
			for r in placed:
				if clash:
					break
				if r != d.unit and r.grow(PAD).intersects(c):
					clash = true
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
			# линия к кораблю — от низа знака, а если корабль выше знака (под шапкой) — от верха рамки
			var from := Vector2(d.anchor.x, fr.end.y + BAR_GAP + BAR_H) if d.p.y > fr.position.y else Vector2(d.anchor.x, fr.position.y)
			c.draw_line(from, d.p, Color(col.r, col.g, col.b, 0.45), 1.0, true)
		var edge := col.lerp(Color.WHITE, 0.55) if d.hover else col
		var sel := d.sel and not rollback_sel_plain
		var w := 2.5 if sel else 1.5
		var shape := side_shape(d.side)
		if sel:
			_frame(c, fr.grow(2.5), shape, Color(0, 0, 0, 0), Color(col.r, col.g, col.b, 0.35), 3.0)
		var fill := Color(0.05, 0.12, 0.2, 0.85) if d.jump else Color(0.02, 0.03, 0.05, 0.72)
		_frame(c, fr, shape, fill, edge, w)
		var gc := col.lerp(Color.WHITE, 0.25) if sel or d.hover else col
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
