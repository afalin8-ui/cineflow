extends CanvasLayer
## Интерфейс боя. Только показывает и зовёт world.cmd_*.

var v                        # battle_view
var w: World
var overlay: Control
var top: Label
var sel_box: PanelContainer
var sel_body: VBoxContainer
var st_box: PanelContainer
var st_body: VBoxContainer
var build_btns := {}
var mini: Control
var feed: Label
var menu_box: PanelContainer
var help_box: PanelContainer
var end_box: PanelContainer
var hp_target = null         # чужой корабль, по чьим хардпоинтам выбираем
var hp_choice := ""
var flash := []              # [{p: Vector2 | unit, t}]
var refresh_t := 0.0
var sel_sig := ""
var abil_slots := []         # [[unit, abil]]

const MINI := 230.0

func setup(view) -> void:
	v = view
	w = view.world
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	var tp := PanelContainer.new()
	tp.position = Vector2(8, 8)
	tp.mouse_filter = Control.MOUSE_FILTER_STOP
	top = Label.new()
	tp.add_child(top)
	add_child(tp)
	feed = Label.new()
	feed.position = Vector2(12, 60)
	feed.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	feed.add_theme_font_size_override("font_size", 14)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feed)
	sel_box = _panel()
	sel_body = VBoxContainer.new()
	sel_box.add_child(sel_body)
	add_child(sel_box)
	st_box = _panel()
	st_body = VBoxContainer.new()
	st_box.add_child(st_body)
	add_child(st_box)
	if v.me >= 0:
		_build_station_panel()
	else:
		st_box.visible = false
	mini = Control.new()
	mini.custom_minimum_size = Vector2(MINI, MINI)
	mini.size = Vector2(MINI, MINI)
	mini.mouse_filter = Control.MOUSE_FILTER_STOP
	mini.draw.connect(_draw_mini)
	mini.gui_input.connect(_mini_input)
	add_child(mini)
	_make_menu()
	_make_help()
	end_box = _panel()
	end_box.visible = false
	add_child(end_box)

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.92)
	sb.border_color = Color(0.25, 0.3, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p

func _btn(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _lbl(text: String, size := 14, col := Color(0.9, 0.92, 0.96)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

# ----------------------------------------------------------- обновление

func _process(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	mini.position = Vector2(vp.x - MINI - 10, 10)
	sel_box.position = Vector2(10, vp.y - sel_box.size.y - 10)
	st_box.position = Vector2(vp.x - st_box.size.x - 10, vp.y - st_box.size.y - 10)
	end_box.position = (vp - end_box.size) / 2
	menu_box.position = (vp - menu_box.size) / 2
	help_box.position = (vp - help_box.size) / 2
	overlay.queue_redraw()
	mini.queue_redraw()
	refresh_t -= delta
	if refresh_t <= 0:
		refresh_t = 0.2
		_refresh()
	if w.winner >= 0 and not end_box.visible:
		_show_end()

func _refresh() -> void:
	var t := int(w.time)
	var line := "%02d:%02d" % [t / 60, t % 60]
	if v.me >= 0:
		var tm: Dictionary = w.teams[v.me]
		var st: Unit = tm.station
		line = "Руда %d  (+%.1f/с)    Флот %d / %d    Станция ур. %d    %s" % [tm.ore, Defs.STATION_INCOME[st.level], w.fleet_points(v.me), w.fleet_cap(v.me), st.level, line]
	else:
		line = "Автобой ИИ против ИИ    " + line
	line += "    Скорость ×%s%s" % [str(v.speed), "    ПАУЗА" if v.paused else ""]
	line += "    F1 — справка"
	top.text = line
	var fl := []
	for e in w.events:
		if (v.me < 0 or e.team == v.me) and w.time - e.t < 12:
			fl.append(e.text)
	feed.text = "\n".join(fl.slice(max(0, fl.size() - 6)))
	_refresh_sel()
	if v.me >= 0:
		_refresh_station()

# --------------------------------------------------------- выбранное

func _refresh_sel() -> void:
	var list: Array = v.sel
	var ht = v.hover if v.hover != null and v.hover.team != v.me and not v.hover.hps.is_empty() else null
	if ht == null and hp_target != null and hp_target.alive and v.seen(hp_target):
		ht = hp_target
	elif ht == null:
		var my: Array = v.mine_sel()
		for u in my:
			if u.target != null and u.target.alive and not u.target.hps.is_empty():
				ht = u.target
				break
	if ht != hp_target:
		hp_target = ht
		hp_choice = ""
	var sig := ""
	for u in list:
		sig += "%d," % u.id
	sig += "|%s|%s" % [hp_target.id if hp_target else -1, hp_choice]
	for u in list:
		for h in u.hps:
			sig += "%d" % int(h.hp > 0)
		sig += str(u.abil_cd.values().map(func(x): return x <= 0)) + str(u.siege) + str(u.charge > 0) + w.squad_block(u)
	if sig == sel_sig:
		_update_sel_values()
		return
	sel_sig = sig
	for c in sel_body.get_children():
		sel_body.remove_child(c)
		c.queue_free()
	abil_slots.clear()
	sel_box.visible = not list.is_empty() or hp_target != null
	if list.size() == 1:
		_unit_card(list[0], true)
	elif list.size() > 1:
		var counts := {}
		for u in list:
			counts[u.def.name] = counts.get(u.def.name, 0) + 1
		var parts := []
		for k in counts:
			parts.append("%s ×%d" % [k, counts[k]])
		sel_body.add_child(_lbl("Выбрано: %d" % list.size(), 16))
		var l := _lbl(", ".join(parts), 13, Color(0.75, 0.8, 0.9))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size.x = 380
		sel_body.add_child(l)
		_abilities_row(list)
	if not v.mine_sel().is_empty():
		var row := HBoxContainer.new()
		row.add_child(_btn("Атака-движение (A)", func(): v.attack_move = true, "Затем щёлкните по месту: корабли пойдут туда, вступая в бой по пути"))
		row.add_child(_btn("Стоп (S)", func(): w.cmd_stop(v.mine_sel())))
		row.add_child(_btn("Отход (R)", func(): w.cmd_retreat(v.mine_sel()), "Зарядка гиперпрыжка %d с, затем корабль уходит к своей станции" % Defs.RETREAT_CHARGE))
		sel_body.add_child(row)
	if hp_target != null and not v.mine_sel().is_empty():
		sel_body.add_child(HSeparator.new())
		sel_body.add_child(_lbl("Цель: %s — бить по хардпоинту:" % hp_target.def.name, 14, Color(1, 0.7, 0.6)))
		var g := GridContainer.new()
		g.columns = 3
		var any := _btn("корпус" + (" ✓" if hp_choice == "" else ""), func(): _set_hp(""))
		g.add_child(any)
		for h in hp_target.hps:
			var hid: String = h.id
			var b := _btn(h.label + (" ✓" if hp_choice == hid else ""), func(): _set_hp(hid))
			b.disabled = h.hp <= 0
			g.add_child(b)
		sel_body.add_child(g)
		sel_body.add_child(_lbl("Щёлкните хардпоинт, затем ПКМ по цели — или он сразу применится к текущей атаке", 11, Color(0.6, 0.65, 0.75)))

func _set_hp(hid: String) -> void:
	hp_choice = hid
	var my: Array = v.mine_sel()
	var atk := my.filter(func(u): return u.target == hp_target)
	if atk.is_empty():
		atk = my
	w.cmd_attack(atk, hp_target, hid)
	v._mark_player(atk)
	sel_sig = ""

func _unit_card(u: Unit, full: bool) -> void:
	var who := "" if v.me < 0 or u.team == v.me else "  (противник)"
	var nm: String = u.def.name
	if u.is_squad():
		nm += " — звено, машин %d из %d" % [u.craft_alive(), u.def.squad_n]
	sel_body.add_child(_lbl(nm + who, 17))
	sel_body.add_child(_lbl(_cls_ru(u), 12, Color(0.65, 0.7, 0.8)))
	var bars := Label.new()
	bars.name = "bars"
	bars.add_theme_font_size_override("font_size", 13)
	sel_body.add_child(bars)
	if not u.hps.is_empty():
		var g := GridContainer.new()
		g.columns = 2
		g.name = "hps"
		for h in u.hps:
			var l := _lbl("", 12)
			l.custom_minimum_size.x = 190
			g.add_child(l)
		sel_body.add_child(g)
	_update_sel_values()
	if not full or v.me < 0 or u.team != v.me:
		return
	_abilities_row([u])
	if u.def.bays > 0:
		var why := w.squad_block(u)
		var ti: String = u.def.sq_types[w.active_bays(u) % u.def.sq_types.size()]
		var b := _btn("+ звено %s (%d руды)" % [Defs.ship(ti).name, Defs.ship(ti).cost], func(): w.cmd_buy_squad(u),
			"Звеньев в ангаре: %d из %d. %s" % [w.active_bays(u), u.def.bays, why])
		b.disabled = why != ""
		sel_body.add_child(b)

func _abilities_row(list: Array) -> void:
	if v.me < 0:
		return
	var seen_ab := {}
	var row := HBoxContainer.new()
	for u in list:
		if u.team != v.me:
			continue
		for a in u.abil_cd:
			if seen_ab.has(a):
				continue
			seen_ab[a] = true
			var keyname: String = ["Z", "X", "C"][abil_slots.size()] if abil_slots.size() < 3 else ""
			abil_slots.append(a)
			var ab: Dictionary = Defs.ABIL[a]
			var lab: String = ab.name
			if a == "siege" and u.siege:
				lab += " (вкл)"
			var b := _btn("%s%s" % [lab, " [%s]" % keyname if keyname != "" else ""], func(): use_ability(a))
			b.name = "ab_" + a
			row.add_child(b)
	if row.get_child_count() > 0:
		sel_body.add_child(row)

func use_ability_slot(i: int) -> void:
	if i < abil_slots.size():
		use_ability(abil_slots[i])

func use_ability(a: String) -> void:
	var msg := ""
	var used := false
	for u in v.mine_sel():
		if u.abil_cd.has(a):
			var r: String = w.cmd_ability(u, a)
			if r == "":
				used = true
			else:
				msg = r
	if not used and msg != "":
		w.note(v.me, "%s: %s" % [Defs.ABIL[a].name, msg])
	sel_sig = ""

func _update_sel_values() -> void:
	if v.sel.size() != 1:
		return
	var u: Unit = v.sel[0]
	var bars = sel_body.get_node_or_null("bars")
	if bars:
		var s := "Корпус %d / %d" % [u.hull, u.hull_max]
		if u.shield_max > 0:
			s += "    Щит %d / %d" % [u.shield, u.shield_max] if u.shield_works() else "    Щит выбит"
		if u.def.armor > 0:
			s += "    Броня %d%%" % int(u.def.armor * 100)
		if u.charge > 0:
			s += "    ГИПЕРПРЫЖОК через %d с" % int(ceil(u.charge))
		if u.cls == "harvester":
			s += "    Груз %d / %d" % [u.cargo, Defs.HARVEST_CAP]
		if u.jam > 0:
			s += "    ЗАГЛУШЕНО"
		for a in u.abil_cd:
			if u.abil_cd[a] > 0:
				s += "\n%s — %d с" % [Defs.ABIL[a].name, int(ceil(u.abil_cd[a]))]
		bars.text = s
	var g = sel_body.get_node_or_null("hps")
	if g:
		for i in u.hps.size():
			var h: Dictionary = u.hps[i]
			var l: Label = g.get_child(i)
			l.text = "%s: %s" % [h.label, ("%d%%" % int(100.0 * h.hp / h.max)) if h.hp > 0 else "ВЫБИТ"]
			l.add_theme_color_override("font_color", Color(0.6, 1, 0.6) if h.hp > h.max * 0.5 else (Color(1, 0.85, 0.4) if h.hp > 0 else Color(1, 0.4, 0.35)))

func _cls_ru(u: Unit) -> String:
	var m := {"craft": "истребители · ближний пояс", "bomber": "бомбардировщики · ближний пояс",
		"scout": "разведчик", "corvette": "корвет · средний пояс", "frigate": "фрегат · средний пояс",
		"cruiser": "крейсер · дальний пояс (ближе 3 км не попадает)", "carrier": "носитель",
		"capital": "флагман · дальний пояс", "harvester": "харвестер — возит руду", "station": "станция"}
	return m.get(u.cls, u.cls)

# ----------------------------------------------------------- станция

func _build_station_panel() -> void:
	st_body.add_child(_lbl("Станция", 16))
	var up := _btn("", func(): w.cmd_upgrade(v.me))
	up.name = "up"
	st_body.add_child(up)
	var g := GridContainer.new()
	g.columns = 3
	var fac: String = w.teams[v.me].fac
	var ids: Array = Defs.faction_ids(fac)
	ids.sort_custom(func(a, b): return Defs.ship(a).lvl * 100000 + Defs.ship(a).cost < Defs.ship(b).lvl * 100000 + Defs.ship(b).cost)
	for id in ids:
		var d := Defs.ship(id)
		var b := _btn("%s\n%d · %d оч." % [d.name, d.cost, d.pts], func(): w.cmd_build(v.me, id))
		b.custom_minimum_size = Vector2(128, 44)
		b.add_theme_font_size_override("font_size", 13)
		build_btns[id] = b
		g.add_child(b)
	st_body.add_child(g)
	var q := _lbl("", 12, Color(0.75, 0.8, 0.9))
	q.name = "queue"
	q.custom_minimum_size.x = 390
	q.autowrap_mode = TextServer.AUTOWRAP_WORD
	st_body.add_child(q)
	var cancel := _btn("Отменить последний в очереди", func():
		var s: Unit = w.teams[v.me].station
		w.cmd_cancel_build(v.me, s.build_queue.size() - 1))
	cancel.name = "cancel"
	st_body.add_child(cancel)

func _refresh_station() -> void:
	var st: Unit = w.teams[v.me].station
	if not st.alive:
		st_box.visible = false
		return
	var up: Button = st_body.get_node("up")
	if st.level >= 4:
		up.text = "Станция ур. 4 — наивысший"
		up.disabled = true
	elif st.upgrading > 0:
		up.text = "Улучшение до ур. %d: %d с" % [st.level + 1, int(ceil(st.upgrading))]
		up.disabled = true
	else:
		var why := w.upgrade_block(v.me)
		up.text = "Улучшить до ур. %d — %d руды" % [st.level + 1, Defs.STATION_UPGRADE[st.level + 1]]
		up.disabled = why != ""
		up.tooltip_text = "Ур. %d: доход %.1f/с, лимит флота %d, доступ к новым кораблям. %s" % [st.level + 1, Defs.STATION_INCOME[st.level + 1], Defs.FLEET_CAP[st.level + 1], why]
	for id in build_btns:
		var b: Button = build_btns[id]
		var why2 := w.build_block(v.me, id)
		b.disabled = why2 != ""
		var d := Defs.ship(id)
		b.tooltip_text = "%s — %s\nКорпус %d%s\nСтройка %d с. %s" % [d.name, _cls_ru_d(d), d.hull, (", щит %d" % d.shield) if d.shield > 0 else "", d.build, ("Нельзя: " + why2) if why2 != "" else ""]
		b.modulate = Color(1, 1, 1) if why2 == "" or why2 == "мало руды" or why2 == "лимит флота" else Color(0.55, 0.55, 0.6)
	var ql: Label = st_body.get_node("queue")
	if st.build_queue.is_empty():
		ql.text = "Очередь пуста"
	else:
		var parts := []
		for i in st.build_queue.size():
			var q: Dictionary = st.build_queue[i]
			parts.append(("%s %d с" % [Defs.ship(q.id).name, ceil(q.t)]) if i == 0 else Defs.ship(q.id).name)
		ql.text = "Строится: " + " → ".join(parts)
	st_body.get_node("cancel").visible = not st.build_queue.is_empty()

func _cls_ru_d(d: Dictionary) -> String:
	var u := Unit.new()
	u.cls = d.cls
	return _cls_ru(u)

# ------------------------------------------------------------ оверлей

func flash_point(p: Vector2) -> void:
	flash.append({"p": p, "t": 0.6})

func flash_target(u: Unit) -> void:
	flash.append({"u": u, "t": 0.6})

func _draw_overlay() -> void:
	var o := overlay
	var dt := get_process_delta_time()
	for u in w.units:
		if not u.alive or u.in_hyper > 0 or not v.seen(u):
			continue
		var sp = v.screen_of(u)
		if sp == null:
			continue
		var col: Color = v.TEAM_COL[u.team]
		var r: float = v.screen_radius(u)
		var selected: bool = v.sel.has(u)
		if u.is_squad():
			o.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -6), sp + Vector2(6, 0), sp + Vector2(0, 6), sp + Vector2(-6, 0)]), col)
			if r < 30:
				o.draw_string(ThemeDB.fallback_font, sp + Vector2(8, 4), str(u.craft_alive()), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		elif r < 14:
			o.draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), col, false, 1.5)
		if selected:
			o.draw_arc(sp, r + 4, 0, TAU, 32, Color(0.5, 1, 0.5), 1.5)
		if v.hover == u:
			o.draw_arc(sp, r + 7, 0, TAU, 32, Color(1, 1, 1, 0.5), 1.0)
		# Полосы прочности — у выбранных, наведённых и подбитых.
		if not u.is_squad() and (selected or v.hover == u or u.hull < u.hull_max * 0.98 or u.shield < u.shield_max * 0.98):
			var bw: float = clamp(r * 1.6, 26, 90)
			var bp: Vector2 = sp + Vector2(-bw / 2, -r - 10)
			o.draw_rect(Rect2(bp, Vector2(bw, 3)), Color(0, 0, 0, 0.6))
			o.draw_rect(Rect2(bp, Vector2(bw * u.hull / u.hull_max, 3)), Color(0.4, 0.9, 0.4))
			if u.shield_max > 0:
				o.draw_rect(Rect2(bp + Vector2(0, -4), Vector2(bw * u.shield / u.shield_max, 2)), Color(0.4, 0.7, 1.0))
		if u.charge > 0:
			o.draw_string(ThemeDB.fallback_font, sp + Vector2(-20, r + 16), "прыжок %d" % ceil(u.charge), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.9, 1))
	# Приказы и дистанции выбранных.
	for u in v.sel:
		if v.me >= 0 and u.team != v.me:
			continue
		var sp = v.screen_of(u)
		if sp == null:
			continue
		if u.order == "move" or u.order == "amove":
			var gp = _ground_screen(u.order_pos)
			if gp != null:
				o.draw_line(sp, gp, Color(0.5, 1, 0.5, 0.5) if u.order == "move" else Color(1, 0.7, 0.3, 0.6), 1.0)
		if u.target != null and u.target.alive:
			var tp = v.screen_of(u.target)
			if tp != null:
				o.draw_line(sp, tp, Color(1, 0.35, 0.3, 0.6), 1.0)
		if u.is_big() and v.sel.size() <= 3:
			var mx: float = w._max_range(u)
			_ground_circle(u.pos, mx, Color(1, 0.7, 0.3, 0.35))
			_ground_circle(u.pos, Defs.BIG_MIN_RANGE, Color(1, 0.3, 0.3, 0.45))
		if u.def.ecm_r > 0:
			_ground_circle(u.pos, u.def.ecm_r * (2.0 if u.abil_on.has("wide_jam") else 1.0), Color(0.7, 0.5, 1.0, 0.4))
		if u.def.repair_r > 0:
			_ground_circle(u.pos, u.def.repair_r, Color(0.4, 1.0, 0.6, 0.3))
	var keep := []
	for f in flash:
		f.t -= dt
		if f.t <= 0:
			continue
		keep.append(f)
		var p = _ground_screen(f.p) if f.has("p") else (v.screen_of(f.u) if f.u.alive else null)
		if p != null:
			o.draw_arc(p, 18.0 * (1.0 - f.t) + 6, 0, TAU, 24, Color(0.5, 1, 0.5) if f.has("p") else Color(1, 0.4, 0.3), 2.0)
	flash = keep
	_draw_hp_markers()
	if v.drag_start != null:
		var rr := Rect2(v.drag_start, v.drag_now - v.drag_start).abs()
		if rr.size.length() > 6:
			o.draw_rect(rr, Color(0.5, 1, 0.5, 0.12))
			o.draw_rect(rr, Color(0.5, 1, 0.5, 0.8), false, 1.0)
	if v.attack_move:
		var m := get_viewport().get_mouse_position()
		o.draw_string(ThemeDB.fallback_font, m + Vector2(14, 0), "атака-движение: ЛКМ по месту", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.7, 0.3))
	if v.hover != null and v.hover.alive:
		var hp_ = v.screen_of(v.hover)
		if hp_ != null:
			var txt: String = v.hover.def.name
			if v.hover.is_squad():
				txt += " ×%d" % v.hover.craft_alive()
			o.draw_string(ThemeDB.fallback_font, hp_ + Vector2(v.screen_radius(v.hover) + 8, -6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))

# ------------------------------------------------- хардпоинты на корпусе

## Где на корпусе стоит хардпоинт (доля длины вдоль носа и поперёк).
const HP_PLACE := {"engine": -0.42, "reactor": -0.22, "dock": -0.12, "shieldgen": -0.02,
	"hangar": 0.08, "ecm": 0.05, "shieldproj": 0.05, "weapon": 0.3}

func hp_markers(u: Unit) -> Array:
	var out := []
	if u == null or not u.alive or u.hps.is_empty() or not v.seen(u):
		return out
	var L: float = ShipMesh.vis_len(u.def) / v.S
	var fwd := Vector2.from_angle(u.heading)
	var side := Vector2(-sin(u.heading), cos(u.heading))
	var used := {}
	for h in u.hps:
		var k: String = h.kind
		var n: int = used.get(k, 0)
		used[k] = n + 1
		var x: float = HP_PLACE.get(k, 0.0) - (0.12 * n if k == "weapon" else 0.0)
		var z: float = 0.0 if n == 0 and k != "weapon" else (0.1 if n % 2 == 0 else -0.1)
		if u.is_station():
			var a := TAU * out.size() / u.hps.size()
			x = cos(a) * 0.32
			z = sin(a) * 0.32
		var p: Vector2 = u.pos + fwd * (x * L) + side * (z * L)
		var p3 := Vector3(p.x * v.S, u.height * v.S + 3, p.y * v.S)
		if v.cam.is_position_behind(p3):
			continue
		out.append({"h": h, "unit": u, "sp": v.cam.unproject_position(p3)})
	return out

## Цель для хардпоинтов: наведённый враг или цель выбранных.
func hp_focus():
	if v.me < 0 or v.mine_sel().is_empty():
		return null
	var hv = v.hover
	if hv != null and hv.team != v.me and not hv.hps.is_empty():
		return hv
	if hp_target != null and hp_target.alive and v.seen(hp_target):
		return hp_target
	return null

func hp_marker_at(m: Vector2):
	var u = hp_focus()
	for mk in hp_markers(u):
		if mk.h.hp > 0 and (mk.sp - m).length() < 14:
			return mk
	return null

func _draw_hp_markers() -> void:
	var u = hp_focus()
	if u == null:
		return
	var m := get_viewport().get_mouse_position()
	var picked: String = ""
	for s2 in v.mine_sel():
		if s2.target == u:
			picked = s2.target_hp
	for mk in hp_markers(u):
		var h: Dictionary = mk.h
		var sp: Vector2 = mk.sp
		var alive: bool = h.hp > 0
		var frac: float = h.hp / h.max
		var col := Color(0.4, 1, 0.5) if frac > 0.5 else (Color(1, 0.85, 0.3) if alive else Color(1, 0.35, 0.3))
		var over: bool = alive and (sp - m).length() < 14
		overlay.draw_circle(sp, 11, Color(0, 0, 0, 0.55))
		overlay.draw_arc(sp, 9, -PI / 2, -PI / 2 + TAU * frac, 24, col, 3.0)
		if not alive:
			overlay.draw_line(sp + Vector2(-6, -6), sp + Vector2(6, 6), col, 2.0)
			overlay.draw_line(sp + Vector2(-6, 6), sp + Vector2(6, -6), col, 2.0)
		if h.id == picked and alive:
			overlay.draw_circle(sp, 5, Color(1, 0.4, 0.3))
		if over:
			overlay.draw_arc(sp, 14, 0, TAU, 24, Color(1, 1, 1), 2.0)
			overlay.draw_string(ThemeDB.fallback_font, sp + Vector2(16, 5), "%s %d%% — щёлкните, чтобы бить сюда" % [h.label, int(frac * 100)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1))
		elif v.hover == u or h.id == picked:
			overlay.draw_string(ThemeDB.fallback_font, sp + Vector2(13, 4), h.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))

func _ground_screen(p: Vector2):
	var p3 := Vector3(p.x * v.S, 0, p.y * v.S)
	if v.cam.is_position_behind(p3):
		return null
	return v.cam.unproject_position(p3)

func _ground_circle(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		var sp = _ground_screen(c + Vector2(cos(a), sin(a)) * r)
		if sp == null:
			return
		pts.append(sp)
	overlay.draw_polyline(pts, col, 1.0)

# ---------------------------------------------------------- мини-карта

## Мини-карта повёрнута как камера по умолчанию: своя станция внизу.
func _rot(p: Vector2) -> Vector2:
	return Vector2(p.y, -p.x) if v.me != 1 else Vector2(-p.y, p.x)

func _unrot(q: Vector2) -> Vector2:
	return Vector2(-q.y, q.x) if v.me != 1 else Vector2(q.y, -q.x)

func _m2mini(p: Vector2) -> Vector2:
	return (_rot(p) / w.map_w + Vector2(0.5, 0.5)) * MINI

func _mini2m(q: Vector2) -> Vector2:
	return _unrot((q / MINI - Vector2(0.5, 0.5)) * w.map_w)

func _draw_mini() -> void:
	var m := mini
	m.draw_rect(Rect2(Vector2.ZERO, Vector2(MINI, MINI)), Color(0.03, 0.04, 0.07, 0.92))
	m.draw_rect(Rect2(Vector2.ZERO, Vector2(MINI, MINI)), Color(0.3, 0.35, 0.45), false, 1.0)
	var k := MINI / w.map_w
	for nb in w.nebulas:
		m.draw_circle(_m2mini(nb.pos), nb.r * k, Color(0.55, 0.3, 0.75, 0.25))
	for f in w.fields:
		var c := Color(0.75, 0.65, 0.45, 0.8) if f.ore > 0 else Color(0.3, 0.3, 0.3, 0.5)
		m.draw_arc(_m2mini(f.pos), max(f.r * k, 3.0), 0, TAU, 16, c, 1.5)
	for u in w.units:
		if not u.alive or u.in_hyper > 0 or not v.seen(u):
			continue
		var p := _m2mini(u.pos)
		var col: Color = v.TEAM_COL[u.team]
		if u.is_station():
			m.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), col)
		elif u.is_squad():
			m.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), col)
		else:
			var s := 4.0 if u.is_big() else 2.5
			m.draw_rect(Rect2(p - Vector2(s, s) / 2, Vector2(s, s)), col)
	# что видит камера
	var vp := get_viewport().get_visible_rect().size
	var corners := []
	for c2 in [Vector2.ZERO, Vector2(vp.x, 0), vp, Vector2(0, vp.y)]:
		var g = v.ground_at(c2)
		if g == null:
			g = Vector2(v.pivot.x / v.S, v.pivot.z / v.S)
		corners.append(_m2mini(g))
	corners.append(corners[0])
	m.draw_polyline(PackedVector2Array(corners), Color(1, 1, 1, 0.5), 1.0)

func _mini_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		var p: Vector2 = _mini2m(ev.position)
		if ev.button_index == MOUSE_BUTTON_LEFT:
			v.focus(p)
		elif ev.button_index == MOUSE_BUTTON_RIGHT and not v.mine_sel().is_empty():
			w.cmd_move(v.mine_sel(), p, Input.is_key_pressed(KEY_CTRL))
			v._mark_player(v.mine_sel())
	elif ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
		v.focus(_mini2m(ev.position))

# --------------------------------------------------------- меню и конец

func _make_menu() -> void:
	menu_box = _panel()
	var b := VBoxContainer.new()
	b.add_child(_lbl("Пауза", 20))
	b.add_child(_btn("Продолжить", toggle_menu))
	b.add_child(_btn("Выйти в меню", func(): v.exit_to_menu.emit()))
	menu_box.add_child(b)
	menu_box.visible = false
	add_child(menu_box)

func toggle_menu() -> void:
	menu_box.visible = not menu_box.visible
	v.paused = menu_box.visible

func _make_help() -> void:
	help_box = _panel()
	var b := VBoxContainer.new()
	var t := _lbl("""Управление
ЛКМ — выбрать, рамкой — несколько. Shift — добавить к выбору.\nДвойной щелчок или Ctrl+щелчок — все корабли этого типа на экране.
ПКМ по месту — лететь. ПКМ по врагу — атаковать. Ctrl+ПКМ — атака-движение.
A — атака-движение, S — стоп, R — отход (гиперпрыжок к своей станции).
Z / X / C — способности выбранных. H — станция.
Ctrl+1…9 — запомнить отряд, 1…9 — выбрать, дважды — камера к нему.
Камера: стрелки или курсор у края — сдвиг, колесо — ближе/дальше,
средняя кнопка — поворот и наклон, Q / E — поворот.
Пробел — пауза (приказы можно отдавать на паузе). + / − — скорость.
Мини-карта: ЛКМ — камера туда, ПКМ — отправить выбранных.

Как воюют
Крейсеры и флагманы бьют с 6–15 км и ближе 3 км не попадают — сами отходят.
Фрегаты лезут под этот минимум. Зенитные корветы режут звенья.
Истребители и бомбардировщики не строятся: их выпускают ангары
носителей и станции. Выбил ангар — поток звеньев кончился.
Выберите своих, наведите на врага — внизу появятся его хардпоинты.
Победа — только уничтожив станцию врага.""", 14)
	b.add_child(t)
	b.add_child(_btn("Закрыть (F1)", toggle_help))
	help_box.add_child(b)
	help_box.visible = false
	add_child(help_box)

func toggle_help() -> void:
	help_box.visible = not help_box.visible

func _show_end() -> void:
	end_box.visible = true
	var b := VBoxContainer.new()
	var title := ""
	if v.me < 0:
		title = "Победил %s" % Defs.fac_name(w.teams[w.winner].fac)
	else:
		title = "Победа!" if w.winner == v.me else "Поражение"
	b.add_child(_lbl(title, 28))
	var s := w.stats
	var tot: float = s.big_far + s.big_close
	b.add_child(_lbl("Бой длился %.1f мин. Потери: вы %d, враг %d." % [w.time / 60.0, s.lost[max(v.me, 0)], s.lost[1 - max(v.me, 0)]], 15))
	b.add_child(_lbl("Крупные корабли держали дистанцию больше 3 км %d%% времени боя." % int(100.0 * s.big_far / max(tot, 1.0)), 14, Color(0.7, 0.8, 0.9)))
	b.add_child(_lbl("Звенья сбили друг у друга %d звеньев." % s.sq_kills_sq, 14, Color(0.7, 0.8, 0.9)))
	b.add_child(_btn("В меню", func(): v.exit_to_menu.emit()))
	end_box.add_child(b)
