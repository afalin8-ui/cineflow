# ui/hud_header.gd — шапка экрана боя (07, 1.2–1.3 и 2.4–2.5; план GИ, п. 2).
# Слева — полосы силы двух сторон: точка цвета клана, слово «Мы» / «Противник» (в «ИИ против
# ИИ» — имя клана: у зрителя нет «своих»), метка клана, полоса цвета СТОРОНЫ (доля стороны
# в общей прочности обеих сторон сейчас) и число живых кораблей. Первая строка — атакующий.
# По середине — название боя и часы (только текст: щелчок по нему уходит в поле, C135).
# Справа — часы орудия планеты (только если оно есть: пустой плашки нет), пауза и скорость,
# кнопка подкрепления в трёх режимах, «Отход» (с вопросом) и «В меню».
# Фон шапки — градиент, а не плашка: ловят мышь только кнопки (ui/builder.gd → finish).
extends Control

const Builder := preload("res://ui/builder.gd")
const Texts := preload("res://ui/texts.gd")
const Ship := preload("res://sim/ship.gd")
const Defs := preload("res://sim/defs.gd")

const HEIGHT := 46.0
const BTN_H := 32.0
const BTN_Y := 7.0
const ROW_H := 18.0
## Зазор «Отхода» от соседей (07, 2.2: 18 — от кнопок скорости, C34).
const RETREAT_GAP := 18.0

## Нажатие кнопки шапки: on_press.call(id).
var on_press: Callable
var tooltip: Node
var buttons: Dictionary[StringName, Button] = {}
## Строки силы: по стороне — точка, слово, метка, подложка полосы, полоса, число.
var dot: Array[ColorRect] = []
var word: Array[Label] = []
var tag: Array[Label] = []
var bar_bg: Array[ColorRect] = []
var bar: Array[ColorRect] = []
var count: Array[Label] = []
## Название боя и часы — та же строка, что раньше стояла справа сверху (имя «status» оставлено:
## его меряют проверки снимков).
var status: Label
## Часы орудия планеты (кнопка ради подсказки с описанием орудия; нажатие ничего не делает).
var gun_btn: Button
## «ИИ против ИИ»: резерв атакующего словами с кланом (кнопки подкрепления у зрителя нет).
var reserve_label: Label
var watch := false
var quick := false
## «В меню» спрятана на время карточки итога (на карточке своя).
var menu_on := true
## ТОЛЬКО для проверки отката (07, 1.3): у кнопки подкрепления нет режима «Прибывшие (N)» —
## пришедшие не напоминают о себе. В игре false.
static var rollback_no_arrived := false
## ТОЛЬКО для проверки отката: название боя ставится целиком, даже когда между полосами силы
## и кнопками ему тесно, — на 1366 длинное название ложится на кнопки. В игре false.
static var rollback_title_free := false
## ТОЛЬКО для проверки отката: квадратик у полосы силы — цветом КЛАНА (как было в первой
## выкладке GИ). Знаки красятся по стороне, и квадратик цвета клана (синий у Тройдена,
## оранжевый у Плэктора) не совпадал ни с одним знаком на экране, а в зеркале был одинаков
## у обеих сторон. В игре false.
static var rollback_dot_clan := false
var _back: TextureRect


func _ready() -> void:
	name = "Header"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back = TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.05, 0.9))
	g.set_color(1, Color(0.02, 0.03, 0.05, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(0.0, 1.0)
	gt.width = 4
	gt.height = 64
	_back.texture = gt
	_back.stretch_mode = TextureRect.STRETCH_SCALE
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	for i in 2:
		var d := ColorRect.new()
		d.size = Vector2(9.0, 9.0)
		add_child(d)
		dot.append(d)
		var w := Builder.label(13, Builder.TEXT)
		add_child(w)
		word.append(w)
		var t := Builder.label(12, Builder.DIM)
		add_child(t)
		tag.append(t)
		var bb := ColorRect.new()
		bb.color = Color(0.0, 0.0, 0.0, 0.55)
		add_child(bb)
		bar_bg.append(bb)
		var br := ColorRect.new()
		add_child(br)
		bar.append(br)
		var c := Builder.label(13, Builder.TEXT)
		add_child(c)
		count.append(c)
	status = Builder.label(16, Builder.TEXT)
	status.name = "Status"
	add_child(status)
	gun_btn = Builder.button("gun", "", Vector2(110.0, BTN_H), 14)
	add_child(gun_btn)
	reserve_label = Builder.label(14, Color(1.0, 0.86, 0.45))
	add_child(reserve_label)
	for id: StringName in [&"pause", &"speed1", &"speed2", &"speed4", &"reinforce", &"retreat", &"menu"]:
		var w2 := 64.0 if id == &"pause" else (46.0 if id.begins_with("speed") else (210.0 if id == &"reinforce" else (150.0 if id == &"retreat" else 100.0)))
		var b := Builder.button(str(id), Texts.cmd(id, "word"), Vector2(w2, BTN_H), 15)
		b.pressed.connect(func() -> void:
			if on_press.is_valid():
				on_press.call(id))
		add_child(b)
		buttons[id] = b
	Builder.finish(self)
	if tooltip != null:
		for id: StringName in buttons:
			tooltip.call("attach", buttons[id])
		tooltip.call("attach", gun_btn)


## Все кнопки шапки, видимые сейчас (сканер кнопок, проверки).
func shown_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for id: StringName in buttons:
		if buttons[id].is_visible_in_tree():
			out.append(buttons[id])
	if gun_btn.is_visible_in_tree():
		out.append(gun_btn)
	return out


## Текст и вид шапки по бою (каждый кадр — но в Label пишется, только если строка сменилась).
func refresh(b: Object, view: Node3D, input: Node, title: String) -> void:
	var defs: Defs = b.get("defs")
	var my_side: int = view.get("my_side")
	var sides: Array = b.get("sides")
	var ships: Array = b.get("ships")
	var hp := PackedFloat64Array([0.0, 0.0])
	var n := PackedInt32Array([0, 0])
	for o: Object in ships:
		var s := o as Ship
		if s.dead:
			continue
		hp[s.side] += s.hp
		n[s.side] += 1
	var tot := maxf(1.0, hp[0] + hp[1])
	var voice: bool = b.call("clan_voice")
	for i in 2:
		var sd: Object = sides[i]
		var clan: StringName = sd.get("clan")
		var fd: Defs.FactionDef = defs.factions.get(clan)
		# квадратик — легенда знаков: цвет СТОРОНЫ, как у рамок над кораблями и у полосы силы;
		# в «ИИ против ИИ» он и говорит, какой клан мятный, а какой красный
		dot[i].color = Builder.OWN if i == my_side else Builder.FOE
		if rollback_dot_clan:
			dot[i].color = Color.hex((fd.color << 8) | 0xff) if fd != null else Color.WHITE
		var wt := (fd.short if fd != null else str(clan)) if voice else (Texts.WE if i == my_side else Texts.FOE)
		_put(word[i], wt)
		word[i].add_theme_color_override("font_color", Builder.OWN if i == my_side else Builder.FOE)
		_put(tag[i], "" if voice else (fd.tag if fd != null else ""))
		bar[i].color = Builder.OWN if i == my_side else Builder.FOE
		bar[i].set_meta(&"frac", hp[i] / tot)
		_put(count[i], "%d" % n[i])
	var t: float = b.get("time")
	var clock := "%d:%02d" % [floori(t / 60.0), floori(t) % 60]
	var paused: bool = view.get("paused")
	status.set_meta(&"full", "%s · %s" % [title, clock])
	status.set_meta(&"clock", clock)
	# часы орудия планеты (03, 2.17; 07, 2.4): «залп» — меньше секунды
	var gun: Object = b.get("gun")
	gun_btn.visible = gun != null
	if gun != null:
		var gd: Defs.GroundGunDef = gun.get("def")
		var gclan: StringName = gun.get("clan")
		var nxt: float = gun.get("next")
		var left := nxt - t
		var gt := "%s %s" % [gd.short, "залп" if left < 1.0 else "%d с" % ceili(left)]
		_set_btn(gun_btn, gt)
		var gfd: Defs.FactionDef = defs.factions.get(gclan)
		gun_btn.set_meta(&"cf_tip", "Орудие планеты%s: %s\n%s" % [(" (%s)" % gfd.short) if gfd != null and voice else "", gd.name, gd.desc])
		var warn := left <= gd.warn
		_look(gun_btn, Builder.Look.ON if warn else Builder.Look.NORMAL)
	# скорость и пауза: горит выбранная (07, 2.4)
	var speed: int = view.get("speed")
	for id: StringName in [&"pause", &"speed1", &"speed2", &"speed4"]:
		var on := (id == &"pause" and paused) or (not paused and id == StringName("speed%d" % speed))
		_look(buttons[id], Builder.Look.ON if on else Builder.Look.NORMAL)
		buttons[id].set_meta(&"cf_tip", Texts.tip(id, Texts.cmd(id, "word"), false))
	# подкрепление: три режима (07, 1.3 и 2.5); у зрителя — строкой с кланом
	var me: Object = sides[my_side]
	var reserve: Array = me.get("reserve")
	var res_n := 0
	for e: Object in reserve:
		var cnt: int = e.get("count")
		res_n += cnt
	var res_at: float = me.get("reinforce_at")
	var retreat: bool = me.get("retreat")
	var conceded: bool = me.get("conceded")
	var rb := buttons[&"reinforce"]
	var tb := buttons[&"retreat"]
	rb.visible = not watch
	tb.visible = not watch
	buttons[&"menu"].visible = quick and menu_on
	if watch:
		var my_clan: StringName = me.get("clan")
		var who := "%s: " % _clan_short(defs, my_clan) if voice else ""
		var rt := ""
		if res_at > 0.0:
			rt = "%sподкрепление выйдет через %d с" % [who, ceili(res_at - t)]
		elif res_n > 0:
			rt = "%sв резерве %d" % [who, res_n]
		_put(reserve_label, rt)
		reserve_label.visible = rt != ""
	else:
		reserve_label.visible = false
		var arr := 0
		if input != null:
			arr = input.call("arrived_left")
		var text := Texts.RESERVE_NONE
		var how2 := Builder.Look.OFF
		var tip_id := &"reinforce"
		if retreat:
			text = (Texts.RESERVE_HOME % res_n) if res_n > 0 else Texts.RESERVE_NONE
		elif res_at > 0.0:
			text = Texts.RESERVE_FLY % maxi(0, ceili(res_at - t))
		elif res_n > 0:
			text = "%s · B" % (Texts.RESERVE_CALL % res_n)
			how2 = Builder.Look.NORMAL
		elif arr > 0 and not rollback_no_arrived:
			text = "%s · N" % (Texts.RESERVE_ARRIVED % arr)
			how2 = Builder.Look.ON
			tip_id = &"arrived"
		_set_btn(rb, text)
		_look(rb, how2)
		rb.disabled = how2 == Builder.Look.OFF
		rb.set_meta(&"mode", tip_id)
		rb.set_meta(&"cf_tip", Texts.tip(tip_id, text, rb.disabled))
		var rtext := Texts.RETREAT_GONE if conceded else (Texts.RETREAT_ON if retreat else Texts.cmd(&"retreat", "word"))
		_set_btn(tb, rtext)
		tb.disabled = conceded
		_look(tb, Builder.Look.OFF if conceded else (Builder.Look.ON if retreat else Builder.Look.NORMAL))
		tb.set_meta(&"cf_tip", Texts.tip(&"retreat", rtext, conceded))
	buttons[&"menu"].set_meta(&"cf_tip", Texts.tip(&"menu", Texts.cmd(&"menu", "word"), false))


static func _clan_short(defs: Defs, clan: StringName) -> String:
	var fd: Defs.FactionDef = defs.factions.get(clan)
	return fd.short if fd != null else str(clan)


static func _put(l: Label, text: String) -> void:
	if l.text != text:
		l.text = text


static func _set_btn(b: Button, text: String) -> void:
	if b.text != text:
		b.text = text


static func _look(b: Button, how: Builder.Look) -> void:
	var was: int = b.get_meta(&"cf_look", -1)
	if was != how:
		Builder.look(b, how)


## Раскладка шапки по ширине окна: полосы силы слева, кнопки справа, название — в промежутке.
func place(vs: Vector2) -> void:
	position = Vector2.ZERO
	size = Vector2(vs.x, HEIGHT)
	_back.position = Vector2.ZERO
	_back.size = Vector2(vs.x, HEIGHT + 18.0)
	var x0 := 12.0
	var wword := 0.0
	for i in 2:
		word[i].reset_size()
		tag[i].reset_size()
		wword = maxf(wword, word[i].size.x)
	var wtag := 0.0
	for i in 2:
		wtag = maxf(wtag, tag[i].size.x)
	var bar_w := 120.0 if vs.x >= 1600.0 else 96.0
	for i in 2:
		var y := 4.0 + float(i) * (ROW_H + 2.0)
		dot[i].position = Vector2(x0, y + 5.0)
		word[i].position = Vector2(x0 + 14.0, y - 1.0)
		tag[i].position = Vector2(x0 + 18.0 + wword, y)
		var bx := x0 + 22.0 + wword + wtag
		bar_bg[i].position = Vector2(bx, y + 6.0)
		bar_bg[i].size = Vector2(bar_w, 7.0)
		var fr: float = bar[i].get_meta(&"frac", 0.0)
		bar[i].position = bar_bg[i].position
		bar[i].size = Vector2(maxf(bar_w * clampf(fr, 0.0, 1.0), 1.0), 7.0)
		count[i].reset_size()
		count[i].position = Vector2(bx + bar_w + 6.0, y - 1.0)
	var left_end := x0 + 22.0 + wword + wtag + bar_w + 6.0 + 30.0
	# справа налево: В меню · Отход · подкрепление · скорость · пауза · орудие
	var x := vs.x - 12.0
	var order: Array[Control] = []
	if buttons[&"menu"].visible:
		order.append(buttons[&"menu"])
	if buttons[&"retreat"].visible:
		order.append(buttons[&"retreat"])
	if buttons[&"reinforce"].visible:
		order.append(buttons[&"reinforce"])
	if reserve_label.visible:
		order.append(reserve_label)
	for id: StringName in [&"speed4", &"speed2", &"speed1", &"pause"]:
		order.append(buttons[id])
	if gun_btn.visible:
		order.append(gun_btn)
	for i in order.size():
		var c := order[i]
		c.reset_size()
		var w := c.size.x
		var gap := 4.0
		if i > 0 and order[i - 1] == buttons[&"retreat"]:
			gap = RETREAT_GAP
		elif i > 0 and (c == buttons[&"speed4"] or order[i - 1] == buttons[&"pause"] or c == buttons[&"reinforce"] or c == reserve_label):
			gap = 12.0
		x -= w + (gap if i > 0 else 0.0)
		c.position = Vector2(x, BTN_Y if c is Button else BTN_Y + 6.0)
	# название — в промежутке между полосами силы и кнопками; не влезает — только часы
	var room := x - 16.0 - left_end
	var full: String = status.get_meta(&"full", status.text)
	var clock: String = status.get_meta(&"clock", "")
	_put(status, full)
	status.reset_size()
	if status.size.x > room and not rollback_title_free:
		_put(status, clock)
		status.reset_size()
	status.visible = room >= status.size.x or rollback_title_free
	status.position = Vector2(left_end + (room - status.size.x) * 0.5, 13.0).floor()
