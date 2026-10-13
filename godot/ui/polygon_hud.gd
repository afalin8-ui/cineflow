# ui/polygon_hud.gd — экран «Полигона» (план G1): что выбрано и чем занято,
# время и скорость боя, полоски о приказах, рамка выбора, конец боя.
# Полный экран боя (панель команд, ростер, лента, подписи) — G6–G7; здесь — минимум,
# чтобы видеть, что сделали клавиши и мышь.
# - Полоски о приказах берутся из ЖУРНАЛА модели (toast_log, с игровым временем:
#   02, ловушка 30; 05, ловушка 38): интерфейс их только показывает и гасит по
#   игровым часам — на паузе полоска стоит. Свои полоски интерфейса («Сначала
#   выбери свои корабли») — по настоящему времени: боя они не касаются.
# - Раскладочные узлы — IGNORE (у Control по умолчанию STOP — C135); нижняя панель —
#   STOP целиком, как настоящая панель: щелчок по ней до поля не доходит, а жест,
#   начатый на поле и кончившийся над ней, дослушивается в _input (архитектура, 6.5).
# - Числа в текст — форматом, а не str() (07, 5.2).
extends CanvasLayer

const Ship := preload("res://sim/ship.gd")
const State := preload("res://sim/state.gd")
const Weapons := preload("res://sim/weapons.gd")
const Defs := preload("res://sim/defs.gd")
const FrameBench := preload("res://ui/frame_bench.gd")
const Squad := preload("res://sim/squad.gd")
const Craft := preload("res://sim/craft.gd")
const Body := preload("res://sim/body.gd")
const Air := preload("res://sim/air.gd")

## Сколько игровых секунд живёт полоска модели и сколько настоящих — своя.
const TOAST_GAME_S := 4.5
const TOAST_REAL_MS := 4000
const TOASTS_MAX := 3
## Подсказок ввода — не больше двух: третья строка остаётся полоске модели.
const HINTS_MAX := 2
## Полоски — ниже подсказки клавиш (две строки слева сверху, ui/fps_counter.gd).
const TOAST_Y := 70.0
## Зазор полосок до края экрана и до строки статуса справа.
const TOAST_GAP := 16.0

## ТОЛЬКО для проверок отката (замечания к G2), в игре всегда false:
## полоски — по середине экрана, как было: на 1366 длинная полоса фокуса всего флота
## наезжала на строку статуса справа («…идут на цельПланета (Ядерная ракета): 23 с»);
static var rollback_toast_center := false
## строка «чем занят» молчит о цели фокуса вне пояса (приказ выглядел невыполненным);
static var rollback_focus_unnamed := false
## «враг вплотную — … · бьёт батарея» без проверки, может ли батарея стрелять.
static var rollback_bat_claim := false
## Хвосты G2 (замечания проверяющих), в игре всегда false:
## подсказки ввода («A — щёлкните точку или врага», «Сначала выбери…») — ПОСЛЕ полосок
## модели, как было: три полоски приказов вытесняли подсказку целиком;
static var rollback_hints_last := false
## тяжёлый со своей целью вне пояса пишет «охота · целей не видно», а лёгкий под
## помехами дальше lockRange — «бьёт X», хотя выстрел невозможен.
static var rollback_doing_g2 := false

## Вид боя (view/battle_view.gd): модель, выбор, скорость.
var view: Node3D
## Ввод (input/battle_input.gd): ждёт ли A щелчка — подсказка держится, пока ждёт.
var input: Node
var title := ""

var status: Label
var toasts: Label
var panel: PanelContainer
var sel_label: Label
var box: Panel
var banner: Label
## Свои полоски интерфейса: [текст, мс настоящего времени, когда гаснет].
var _local: Array[Array] = []
var _last_status := ""
var _last_sel := ""
var _last_toasts := ""


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	status = _label(18, Color(0.85, 0.92, 1.0))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(status)
	toasts = _label(17, Color(1.0, 0.93, 0.7))
	toasts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toasts)
	panel = PanelContainer.new()
	panel.name = "SelPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.86)
	sb.border_color = Color(0.35, 0.55, 0.8, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	sel_label = _label(15, Color(0.85, 0.92, 1.0))
	panel.add_child(sel_label)
	add_child(panel)
	box = Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.56, 1.0, 0.78, 0.08)
	bs.border_color = Color(0.56, 1.0, 0.78, 0.85)
	bs.set_border_width_all(1)
	box.add_theme_stylebox_override("panel", bs)
	box.visible = false
	add_child(box)
	banner = _label(24, Color(1.0, 0.9, 0.6))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.visible = false
	add_child(banner)


static func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	return l


## Своя полоска интерфейса (не о приказе): «Сначала выбери свои корабли».
func say(text: String) -> void:
	_local.append([text, Time.get_ticks_msec() + TOAST_REAL_MS])


## Рамка выбора: пустая — спрятать.
func show_box(r: Rect2) -> void:
	box.visible = r.has_area()
	if box.visible:
		box.position = r.position
		box.size = r.size


func _process(_delta: float) -> void:
	if view == null:
		return
	var b: Object = view.get("battle")
	if b == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var st := _status_text(b)
	if st != _last_status:
		_last_status = st
		status.text = st
	status.reset_size()
	status.position = Vector2(vs.x - status.size.x - 16.0, 12.0)
	var over: bool = b.get("over")
	# бой кончился — часы стоят, и полоски модели висели бы вечно; итог говорит баннер
	var tt := "" if over else _toast_text(b)
	if tt != _last_toasts:
		_last_toasts = tt
		toasts.text = tt
	_place_toasts(vs)
	var sl := _sel_text(b)
	if sl != _last_sel:
		_last_sel = sl
		sel_label.text = sl
		panel.reset_size()
	panel.position = Vector2(((vs.x - panel.size.x) * 0.5), vs.y - panel.size.y - 14.0)
	banner.visible = over
	if over:
		var w: int = b.get("winner")
		var my_side: int = view.get("my_side")
		banner.text = "Бой окончен: %s.\nF8 — начать заново" % ("ничья" if w < 0 else ("наша сторона держит орбиту" if w == my_side else "орбиту держит противник"))
		banner.reset_size()
		banner.position = ((vs - banner.size) * 0.5).floor() - Vector2(0.0, vs.y * 0.18)


## Полоски — по середине экрана, если там им хватает места; иначе — в промежутке
## между левым краем и строкой статуса справа (она стоит на той же высоте: заголовок,
## часы, резерв, планета), а не шире его: длинная полоска переносится по словам.
func _place_toasts(vs: Vector2) -> void:
	toasts.autowrap_mode = TextServer.AUTOWRAP_OFF
	toasts.custom_minimum_size = Vector2.ZERO
	toasts.reset_size()
	var w := toasts.size.x
	var right := status.position.x - TOAST_GAP
	var left := TOAST_GAP
	var x := (vs.x - w) * 0.5
	if not rollback_toast_center and x + w > right:
		var band := maxf(right - left, 120.0)
		if w > band:
			toasts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			toasts.custom_minimum_size = Vector2(band, 0.0)
			toasts.size = Vector2(band, 0.0)
			toasts.reset_size()
			w = toasts.size.x
		x = left + (band - w) * 0.5
	toasts.position = Vector2(x, TOAST_Y)


func _status_text(b: Object) -> String:
	var t: float = b.get("time")
	var paused: bool = view.get("paused")
	var speed: int = view.get("speed")
	var clock := "%d:%02d" % [floori(t / 60.0), floori(t) % 60]
	var lines := PackedStringArray([title, "%s · %s" % [clock, "пауза" if paused else "%d×" % speed]])
	var my_side: int = view.get("my_side")
	var sides: Array = b.get("sides")
	var sd: Object = sides[my_side]
	var res_at: float = sd.get("reinforce_at")
	var reserve: Array = sd.get("reserve")
	if res_at > 0.0:
		lines.append("Подкрепление выйдет через %d с" % ceili(res_at - t))
	elif not reserve.is_empty():
		var n := 0
		for e: Object in reserve:
			var c: int = e.get("count")
			n += c
		lines.append("В резерве %d %s · B — вызвать" % [n, FrameBench.plural(n, "корабль", "корабля", "кораблей")])
	# часы «Давления Земли» (03, 2.17): «залп», если осталось меньше секунды
	var gun: Object = b.get("gun")
	if gun != null:
		var gd: Defs.GroundGunDef = gun.get("def")
		var nxt: float = gun.get("next")
		var left := nxt - t
		lines.append("Планета (%s): %s" % [gd.name, "залп" if left < 1.0 else "%d с" % ceili(left)])
	return "\n".join(lines)


## Подсказка ввода, которая держится, пока ввод в этом состоянии (A ждёт щелчка).
func input_hint() -> String:
	if input == null:
		return ""
	var armed: bool = input.get("amove_armed")
	return "A — щёлкните точку или врага · Esc — отмена" if armed else ""


func _toast_text(b: Object) -> String:
	# подсказки ввода — ПЕРВЫМИ и всегда (хвост G2): полоски модели о приказах шли
	# первыми, и три приказа подряд вытесняли «A — щёлкните точку или врага» целиком
	var hints := PackedStringArray()
	var ih := input_hint()
	if ih != "":
		hints.append(ih)
	var now := Time.get_ticks_msec()
	var keep: Array[Array] = []
	for l in _local:
		var until: int = l[1]
		if until > now:
			keep.append(l)
	_local = keep
	for j in range(_local.size() - 1, -1, -1):
		if hints.size() >= HINTS_MAX:
			break
		hints.append(str(_local[j][0]))
	var room := TOASTS_MAX if rollback_hints_last else TOASTS_MAX - hints.size()
	var out := PackedStringArray()
	var log: Array[Dictionary] = b.get("toast_log")
	var t: float = b.get("time")
	var i := log.size() - 1
	while i >= 0 and out.size() < room:
		var e: Dictionary = log[i]
		var et: float = e["t"]
		if t - et > TOAST_GAME_S:
			break
		out.append(str(e["text"]))
		i -= 1
	if rollback_hints_last:
		for h in hints:
			if out.size() >= TOASTS_MAX:
				break
			out.append(h)
		return "\n".join(out)
	hints.append_array(out)
	return "\n".join(hints)


## Что выбрано и чем занято: «Выбрано: 3 · идут», имена — до четырёх.
func _sel_text(b: Object) -> String:
	var sel: Array[int] = view.get("selection")
	var my_side: int = view.get("my_side")
	if sel.is_empty():
		return "Ничего не выбрано · ЛКМ — выбрать, протяжка — рамка, щелчок по машине — её звено\nНоситель: Z / X / C — поднять звено · B — подкрепление · Пробел — пауза · 1, 2, 4 — скорость"
	var names := PackedStringArray()
	var own := 0
	var own_carriers := 0
	var free_bays := 0
	var own_squads := 0
	var acts: Dictionary[String, int] = {}
	for u in sel:
		var s: Ship = b.call("ship_by_uid", u)
		var q: Squad = b.call("squad_by_uid", u) if s == null else null
		if q != null and not q.dead:
			# звено: «Перехватчик «Зонг» ×4/5» (04, 1.1)
			if names.size() < 4:
				names.append(squad_name(q, b as State))
			if q.side == my_side:
				own += 1
				own_squads += 1
				var qa := squad_doing(q, b as State)
				var qc: int = acts.get(qa, 0)
				acts[qa] = qc + 1
			continue
		if s == null or s.dead:
			continue
		if names.size() < 4:
			names.append(s.name)
		if s.side == my_side:
			own += 1
			if s.hangar != null:
				own_carriers += 1
				free_bays += s.hangar.free
			var a := doing(s, b as State)
			var c: int = acts.get(a, 0)
			acts[a] = c + 1
	var head := "Выбрано: %d" % sel.size() if own > 0 else "Противник"
	var act_list := PackedStringArray()
	for a: String in acts:
		act_list.append(a if acts.size() == 1 else "%s %d" % [a, acts[a]])
	var more := "" if sel.size() <= names.size() else ", …"
	var line := "%s — %s%s" % [head, ", ".join(names), more]
	if not act_list.is_empty():
		line += "\n" + ", ".join(act_list)
	if own_carriers > 0:
		line += "\nZ — перехватчики · X — истребители · C — бомбардировщики · свободно мест в ангаре: %d" % free_bays
	if own_squads > 0 and own_squads == own:
		line += "\nПКМ — лететь, по врагу или чужому звену — бить · V — на посадку"
	elif own > 0:
		line += "\nПКМ — лететь, по врагу — бить его · A — атака с ходу · H/S — стоять · Y — охрана · T — охота · G — гипер · D — дрифт"
	return line


## «Перехватчик «Зонг» ×4/5» — роль, имя машины, живых из поднятых (04, 1.1).
static func squad_name(q: Squad, b: State) -> String:
	var rd: Defs.StrikeRoleDef = b.defs.strike_roles.get(q.role)
	return "%s %s ×%d/%d" % [rd.label if rd != null else str(q.role), q.def.name, q.craft.size(), q.size]


## Чем занято своё звено (04, 1.1: «атакует», «идёт к точке», «перезаряжается»,
## «патрулирует»; доктрина 09, 4.2 и 4.4 — обход с фланга и патруль над своей линией).
static func squad_doing(q: Squad, b: State) -> String:
	if q.recall:
		return "на посадку"
	var reloading := 0
	var flank := 0
	var fighting := 0
	var leaving := 0
	for c in q.craft:
		if c.leaving:
			leaving += 1
		elif c.reloading > 0.0:
			reloading += 1
		elif Air.routing(b, c):
			flank += 1
		elif c.target != null:
			fighting += 1
	if leaving > 0:
		return "ракет нет — уходит с поля"
	if reloading * 2 >= q.craft.size():
		return "перезаряжается у носителя"
	if flank * 2 >= q.craft.size():
		return "обходит строй с фланга"
	if fighting > 0:
		var t := q.target as Ship
		return "атакует %s" % Weapons.short_name(t) if t != null and not t.dead else "атакует"
	if q.has_move:
		return "ждёт у точки" if q.pos.distance_to(q.move_to) < Air.LEG_REACH * 2.0 else "идёт к точке"
	if q.role == &"interceptor":
		return "патрулирует над своей линией"
	return "кружит у носителя"


## Чем занят свой корабль — одной строкой (07, 7.2 п. 2; 09, 6.7: слово «бьёт» — только
## когда выстрел возможен). b — бой: докуда батарея бьёт сейчас (под помехами —
## lockRange).
static func doing(s: Ship, b: State) -> String:
	if s.charging():
		return "копит гипер %d с" % ceili(s.hyper_left)
	if s.drift:
		return "дрейф"
	if s.has_move:
		return "идёт в точку"
	var t := s.target as Ship
	var sec := s.sec_target as Ship
	var fz := s.forced as Ship
	var jam := ""
	if s.jam != null and s.heavy():
		var jp: Defs.EcmDef = s.jam
		jam = " · под помехами — главный калибр %s" % Weapons.slower(jp.main_slow)
	if s.heavy():
		# «батареей по …» — только если батарея по ней СЕЙЧАС достаёт (под помехами —
		# ближе lockRange, 09, 1.3): иначе это обещание выстрела, которого нет
		var bat := ""
		if sec != null and not sec.dead and s.pos.distance_to(sec.pos) <= Weapons.sec_reach(b, s):
			bat = " · батареей по %s" % Weapons.short_name(sec)
		# цель фокуса вне пояса, а главный калибр бьёт свою цель в поясе (09, 6.3): приказ
		# не потерян — строка называет, почему по цели фокуса не бьёт
		var off := ""
		if fz != null and not fz.dead and fz != t and not rollback_focus_unnamed:
			off = " · %s вне пояса (%d)" % [Weapons.short_name(fz), roundi(s.pos.distance_to(fz.pos))]
		if s.idle_reason == &"dead_zone":
			if rollback_bat_claim and bat == "":
				bat = " · бьёт батарея"
			return "враг вплотную — главный калибр не бьёт%s%s%s" % [bat, off, jam]
		if t != null and not t.dead and Weapons.main_reach(s, s.pos.distance_to(t.pos)) == 0:
			return "главным по %s (%d)%s%s%s" % [Weapons.short_name(t), roundi(s.pos.distance_to(t.pos)), bat, off, jam]
		if fz != null and not fz.dead and not rollback_focus_unnamed:
			return "цель %s вне пояса (%d) — стоит%s%s" % [Weapons.short_name(fz), roundi(s.pos.distance_to(fz.pos)), bat, jam]
		# своя цель вне пояса (на «Охоте» — до 1,8 R): пока тяжёлый в пояс не ходит (G4),
		# он стоит, и строка обязана это сказать, а не «целей не видно» (хвост G2)
		if t != null and not t.dead and not s.has_amove and not rollback_doing_g2:
			var dt_ := s.pos.distance_to(t.pos)
			return "цель %s %s (%d) — стоит%s%s" % [Weapons.short_name(t), "вне пояса" if Weapons.main_reach(s, dt_) > 0 else "в мёртвой зоне", roundi(dt_), bat, jam]
		if s.has_amove:
			return "идёт с боем%s" % jam
		if bat != "":
			return "держит позицию%s%s%s" % [bat, off, jam]
	elif s.target != null:
		var tb := s.target as Body
		if tb != null and not tb.dead:
			var d := s.pos.distance_to(tb.pos)
			var tn := Weapons.short_name(t) if t != null else "машины звена"
			# под помехами лёгкое бьёт только ближе lockRange: «бьёт X» дальше — обещание
			# выстрела, которого нет (хвост G2; 09, 6.7)
			if s.def.light != null and d <= s.def.light.rng and d > Weapons.light_reach(b, s) and not rollback_doing_g2:
				return "под помехами — бьёт только вблизи (%s в %d)" % [tn, roundi(d)]
			if s.has_amove or s.forced != null or s.stance == &"hunt":
				return ("бьёт %s" if s.def.light != null and d <= s.def.light.rng else "идёт на %s") % tn
			return ("бьёт %s" if s.def.light != null and d <= s.def.light.rng else "охрана · видит %s") % tn
	if s.has_amove:
		return "идёт с боем"
	if s.vel.length() > 3.0:
		return "тормозит" if s.stance == &"hold" else "идёт на участок"
	match s.stance:
		&"hunt":
			return "охота · целей не видно"
		&"hold":
			return "стоит%s" % jam
	return "стоит%s" % jam
