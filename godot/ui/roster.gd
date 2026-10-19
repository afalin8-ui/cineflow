# ui/roster.gd — ростер флота (07, 1.7 и 2.8; 09, 6.8; план GИ, п. 4): свои корабли и звенья
# ячейками по классу — «Корвет ×8», «Крейсер ×2», «Флагман» — тремя группами с разделителем:
# тяжёлые · лёгкие и РЭБ · носители и звенья. Под словом — полоска средней прочности класса,
# цвет — по самому раненому. Щелчок — весь класс, следующий — по одному, после последнего —
# снова все; Shift — добавить к выбранным (решает input/battle_input.gd → roster_click).
# Номеров отрядов в ячейке нет: отрядов ещё нет (G6).
# Ячейки не пересоздаются (C30): ключ класса → кнопка; исчезнувший класс уходит.
extends HBoxContainer

const Builder := preload("res://ui/builder.gd")
const Texts := preload("res://ui/texts.gd")
const Ship := preload("res://sim/ship.gd")
const Squad := preload("res://sim/squad.gd")
const Picking := preload("res://input/picking.gd")

## Порядок ячеек (07, 2.8) и группа (09, 6.8): 0 — тяжёлые, 1 — лёгкие и РЭБ, 2 — носители и звенья.
const ORDER := {&"capital": 0, &"sinho": 1, &"cruiser": 2, &"carrier": 3, &"ecm": 4, &"frigate": 5,
	&"corvette": 6, &"interceptor": 10, &"fighter": 11, &"bomber": 12}
const CELL := Vector2(88.0, 38.0)

## Щелчок по ячейке: on_click.call(uid кораблей класса, Shift).
var on_click: Callable
var tooltip: Node
var cells: Dictionary[String, Button] = {}
## Кто в ячейке сейчас: ключ → uid (живые, по порядку).
var members: Dictionary[String, Array] = {}
var _groups: Array[HBoxContainer] = []
var _seps: Array[ColorRect] = []


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for g in 3:
		if g > 0:
			var sep := ColorRect.new()
			sep.color = Color(0.5, 0.65, 0.85, 0.35)
			sep.custom_minimum_size = Vector2(1.0, CELL.y)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(sep)
			_seps.append(sep)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		_groups.append(h)


static func _ord(kind: StringName) -> int:
	var o: int = ORDER.get(kind, 9)
	return o


static func group_of(kind: StringName) -> int:
	var o: int = ORDER.get(kind, 6)
	if o <= 2:
		return 0
	if o == 3 or o >= 10:
		return 2
	return 1


## Слово класса: «Флагман», «Тяжёлый крейсер», «Корвет» (роль корабля до « · »).
static func word_of(s: Ship) -> String:
	var r := s.def.role_text
	var i := r.find(" · ")
	return r.substr(0, i) if i > 0 else s.def.name


func refresh(b: Object, my_side: int, sel: Array[int]) -> void:
	var by: Dictionary[String, Array] = {}
	var words: Dictionary[String, String] = {}
	var kinds: Dictionary[String, StringName] = {}
	var hp_sum: Dictionary[String, float] = {}
	var hp_min: Dictionary[String, float] = {}
	var ships: Array = b.get("ships")
	for o: Object in ships:
		var s := o as Ship
		if s.dead or s.side != my_side or s.station or not Picking.shown(s, my_side):
			continue
		var k := "s:%s" % s.def.id
		if not by.has(k):
			by[k] = []
			words[k] = word_of(s)
			kinds[k] = s.def.id
			hp_sum[k] = 0.0
			hp_min[k] = 1.0
		by[k].append(s.uid)
		hp_sum[k] += s.hp_frac()
		hp_min[k] = minf(hp_min[k], s.hp_frac())
	var squads: Array = b.get("squads")
	var defs: Object = b.get("defs")
	var roles: Dictionary = defs.get("strike_roles")
	for o2: Object in squads:
		var q := o2 as Squad
		if q.dead or q.side != my_side or q.craft.is_empty():
			continue
		var k2 := "q:%s" % q.role
		if not by.has(k2):
			by[k2] = []
			var rd: Object = roles.get(q.role)
			words[k2] = str(rd.get("label")) if rd != null else str(q.role)
			kinds[k2] = q.role
			hp_sum[k2] = 0.0
			hp_min[k2] = 1.0
		by[k2].append(q.uid)
		var hq := 0.0
		for c in q.craft:
			hq += c.hp_frac()
		hq /= float(q.craft.size())
		hp_sum[k2] += hq
		hp_min[k2] = minf(hp_min[k2], hq)
	# исчезнувшие классы уходят, новые встают на место по порядку
	for k: String in cells.keys():
		if not by.has(k):
			var old := cells[k]
			old.get_parent().remove_child(old)
			old.queue_free()
			cells.erase(k)
	var keys: Array[String] = []
	for k: String in by:
		keys.append(k)
	keys.sort_custom(func(x: String, y: String) -> bool: return _ord(kinds[x]) < _ord(kinds[y]))
	for k in keys:
		var g := group_of(kinds[k])
		if not cells.has(k):
			var cb := Builder.button(k, "", CELL, 13)
			var bar := ColorRect.new()
			bar.name = "bar"
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cb.add_child(bar)
			var key := k
			cb.pressed.connect(func() -> void:
				if on_click.is_valid():
					on_click.call(members.get(key, []), Input.is_key_pressed(KEY_SHIFT)))
			if tooltip != null:
				tooltip.call("attach", cb)
			_groups[g].add_child(cb)
			cells[k] = cb
		var c := cells[k]
		_groups[g].move_child(c, -1)
		var n := by[k].size()
		var text := words[k] if n == 1 else "%s ×%d" % [words[k], n]
		if c.text != text:
			c.text = text
		members[k] = by[k]
		var any_sel := false
		for u: int in by[k]:
			if u in sel:
				any_sel = true
				break
		var how := Builder.Look.ON if any_sel else Builder.Look.NORMAL
		var was: int = c.get_meta(&"cf_look", -1)
		if was != how:
			Builder.look(c, how)
		var avg := hp_sum[k] / float(n)
		var mn := hp_min[k]
		var bar_c := Color(0.56, 1.0, 0.78) if mn > 0.55 else (Color(0.88, 0.66, 0.31) if mn > 0.25 else Color(0.88, 0.33, 0.33))
		var br := c.get_node("bar") as ColorRect
		br.color = bar_c
		br.position = Vector2(6.0, c.size.y - 6.0)
		br.size = Vector2(maxf((c.size.x - 12.0) * clampf(avg, 0.0, 1.0), 1.0), 3.0)
		var tip := (Texts.ROSTER_HINT % n) if n > 1 else (Texts.ROSTER_ONE % words[k])
		c.set_meta(&"cf_tip", "%s\n%s" % [text, tip])
	for k: String in members.keys():
		if not by.has(k):
			members.erase(k)
	# разделитель — только между непустыми группами
	for i in _seps.size():
		_seps[i].visible = _groups[i].get_child_count() > 0 and _groups[i + 1].get_child_count() > 0
	Builder.finish(self)
