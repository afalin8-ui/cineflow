extends Node
## Меню скирмиша и запуск боя.

const FACS := ["troyden", "plector", "random"]
const FAC_RU := ["Тройден — мало крупных, щиты, дальний бой", "Плэктор — рой, носители, давление", "Случайно"]
const DIFF := ["easy", "medium", "hard"]
const DIFF_RU := ["Легко", "Средне", "Тяжело"]
const SIZES := ["S", "M", "L"]
const SIZE_RU := ["S — 60×60 км", "M — 90×90 км", "L — 120×120 км"]

var menu: Control
var battle: Node3D
var opts := {}

func _ready() -> void:
	# Проверка снимком: -- shot=<файл.png> t=<сек> me=<0|-1> facs=a,b size=S yaw=<рад> dist=<ед>
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if args.has("shot"):
		_autoshot(args)
		return
	_show_menu()

func _autoshot(a: Dictionary) -> void:
	var f: PackedStringArray = a.get("facs", "troyden,plector").split(",")
	var cfg := {"facs": [f[0], f[1]], "size": a.get("size", "S"), "seed": int(a.get("seed", "3")),
		"ai": ["hard" if a.get("me", "0") == "-1" else "", "hard"], "me": int(a.get("me", "0"))}
	battle = preload("res://scripts/view/battle_view.gd").new()
	add_child(battle)
	battle.start(cfg)
	var t := float(a.get("t", "1"))
	# прокрутить бой быстро до нужного времени
	while battle.world.time < t:
		battle.world.step()
	if a.has("dist"):
		battle.dist = float(a.dist)
	if a.has("focus"):
		var fp: PackedStringArray = a.focus.split(",")
		battle.focus(Vector2(float(fp[0]), float(fp[1])))
	if a.has("sel"):
		for u in battle.world.units:
			if u.alive and u.team == 0 and u.def.id == a.sel:
				battle.sel = [u]
				battle.focus(u.pos)
				break
	if a.has("menu"):
		battle.queue_free()
		battle = null
		_show_menu()
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a.shot)
	get_tree().quit()

func _opt(parent: Control, label: String, items: Array, key: String, def := 0) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 200
	row.add_child(l)
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(def)
	o.custom_minimum_size.x = 380
	o.item_selected.connect(func(i): opts[key] = i)
	opts[key] = def
	row.add_child(o)
	parent.add_child(row)

func _show_menu() -> void:
	if battle:
		battle.queue_free()
		battle = null
	menu = CenterContainer.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)
	holder.add_child(menu)
	add_child(holder)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	menu.add_child(v)
	var t := Label.new()
	t.text = "КАПЕЛЛА"
	t.add_theme_font_size_override("font_size", 48)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := Label.new()
	st.text = "Космический бой против компьютера · серый прототип"
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	v.add_child(st)
	v.add_child(HSeparator.new())
	_opt(v, "Ваша фракция", FAC_RU, "me")
	_opt(v, "Противник", FAC_RU, "enemy", 1)
	_opt(v, "Сложность", DIFF_RU, "diff", 1)
	_opt(v, "Карта", SIZE_RU, "size")
	v.add_child(HSeparator.new())
	var go := Button.new()
	go.text = "В бой"
	go.custom_minimum_size.y = 44
	go.pressed.connect(func(): _start(false))
	v.add_child(go)
	var watch := Button.new()
	watch.text = "Смотреть автобой: ИИ против ИИ"
	watch.pressed.connect(func(): _start(true))
	v.add_child(watch)
	var q := Button.new()
	q.text = "Выход"
	q.pressed.connect(func(): get_tree().quit())
	v.add_child(q)
	menu = holder

func _fac(i: int) -> String:
	if FACS[i] == "random":
		return ["troyden", "plector"][randi() % 2]
	return FACS[i]

func _start(spectate: bool) -> void:
	randomize()
	var cfg := {
		"facs": [_fac(opts.me), _fac(opts.enemy)],
		"size": SIZES[opts.size],
		"seed": randi(),
		"ai": [DIFF[opts.diff] if spectate else "", DIFF[opts.diff]],
		"me": -1 if spectate else 0,
	}
	menu.queue_free()
	battle = preload("res://scripts/view/battle_view.gd").new()
	add_child(battle)
	battle.start(cfg)
	battle.exit_to_menu.connect(_show_menu)
