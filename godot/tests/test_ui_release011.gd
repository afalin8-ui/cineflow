# «Что попробовать» выпуска capella-v0.11 «Флот Тройдена» (godot/RELEASE) — настоящими событиями
# ввода (hooks.gd): щелчки по меню и ростеру, колесо, правая кнопка по полю, клавиши H и Пробел.
# Ярус ui, без окна: что горит и что крутится, читается из вида (факелы, их узлы, реактор), а не
# из точек снимка (снимки флота — ярус render, test_render_models; глазами — CLAUDE.md, раздел 15).
# Каждый шаг текста выпуска — своя проверка; откаты:
# - факел реверса горит всегда (`BattleView.rollback_rev_plume_always`) — шаг «тормозит передними
#   гондолами» краснеет на «пока идёт вперёд, реверса нет»;
# - модель флагмана из выгрузки three.js (запись без `hand`) — шаг «своя модель» краснеет;
# - реактор от настоящих часов (`ShipVisual.rollback_spin_real_clock`) — шаг «на паузе стоит».
extends "res://tests/case.gd"

const MainScene := preload("res://main.tscn")
const MainScript := preload("res://main.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const Polygon := preload("res://tools/polygon.gd")
const QuickMenu := preload("res://ui/quick_menu.gd")
const BattleView := preload("res://view/battle_view.gd")
const ShipVisual := preload("res://view/ship_visual.gd")
const ShipModels := preload("res://view/ship_models.gd")
const Settings := preload("res://view/settings.gd")

var _main: Node
var _size := Vector2i(1366, 768)


func _press(b: Button) -> bool:
	if b == null:
		return false
	var c := b.get_global_rect().get_center()
	if await hooks.hovered_at(c) != b:
		return false
	await hooks.click(c)
	return true


func _close() -> void:
	Settings.path = Settings.DEFAULT_PATH
	MainScript.out_override = ""
	MainScript.seed_override = -1
	if _main != null:
		_main.queue_free()
		_main = null
	await hooks.frames(2)


## Меню: «Твой клан», «Противник», «Масштаб» — щелчками, затем «В бой». Бой — на паузе (шаги
## дальше делает сама проверка: часы боя здесь — шаги модели, а не настоящее время).
func _open(mine: String, foe: String) -> Polygon:
	if _main == null:
		await hooks.set_window_size(_size)
		Settings.path = tmp("rel011_settings.cfg")
		if FileAccess.file_exists(Settings.path):
			DirAccess.remove_absolute(Settings.path)
		MainScript.out_override = tmp("rel011")
		MainScript.seed_override = 4242
		_main = MainScene.instantiate()
		tree.root.add_child(_main)
		await hooks.frames(4)
	var m: QuickMenu = _main.get("menu")
	for k: String in ["mine:" + mine, "foe:" + foe, "size:big", "go"]:
		var mb: Button = m.buttons.get(k) if m != null else null
		if not await _press(mb):
			return null
		await hooks.frames(1)
	await hooks.frames(4)
	var p: Polygon = _main.get("polygon")
	if p != null:
		p.view.paused = true
		p.view.rig.edge_enabled = false
		await hooks.frames(2)
	return p


## Камера догоняет точку взгляда сглаживанием по настоящим часам (раздел 15): ждать, пока догонит.
func _settle(v: BattleView) -> void:
	for i in 900:
		if v.rig.s_look.distance_to(v.rig.look) < 2.0 and absf(v.rig.s_dist - v.rig.dist) < 2.0:
			break
		await hooks.frames(1)
	await hooks.frames(2)


func _run(p: Polygon, secs: float) -> void:
	var v := p.view
	var t1 := p.battle.time + secs
	v.paused = false
	while p.battle.time < t1 and not p.battle.over:
		v.advance(Battle.STEP)
	v.paused = true
	v.draw_state()
	await hooks.frames(1)


static func _lit(list: Array, prefix: String) -> int:
	var n := 0
	for mi: MeshInstance3D in list:
		if mi.visible and mi.scale.y > 0.05 and String(mi.get_parent().name).begins_with(prefix):
			n += 1
	return n


## Шаги 1–4 текста выпуска на одном бою. → что увидели на каждом шаге.
func _walk() -> Dictionary:
	var out := {"opened": false}
	var p := await _open("troyden", "plektor")
	if p == null:
		await _close()
		return out
	out["opened"] = str(p.battle.setup.get("attacker")) == "troyden" and str(p.battle.setup.get("defender")) == "plektor" and str(p.battle.setup.get("size")) == "big"
	var v := p.view
	var b := p.battle
	var flag_ship: Ship = null
	for s in b.side_ships(Ship.ATTACKER):
		if s.def.id == &"capital":
			flag_ship = s
	if flag_ship == null:
		await _close()
		return out
	var vis: ShipVisual = v._vis[flag_ship.uid]
	var file: String = vis.record.get("file", "")
	out["hand"] = vis.record.get("hand") != null and file == "res://view/hero/troyden_capital.glb"
	# шаг 1: «Флагман» в ростере внизу слева — выбран «Ланселот», камера над ним
	var cell: Button = p.hud.roster.cells.get("s:capital")
	out["roster_text"] = cell.text if cell != null else ""
	out["roster"] = await _press(cell)
	await hooks.frames(2)
	var fp := v.ship_point(flag_ship)
	out["selected"] = v.selection == [flag_ship.uid]
	out["cam_on"] = Vector2(v.rig.look.x, v.rig.look.z).distance_to(Vector2(fp.x, fp.z)) < 60.0
	await _settle(v)
	# шаг 2: правой кнопкой по полю впереди — идёт, горят задние гондолы
	var cam := v.rig.camera
	var ahead := fp + Vector3(flag_ship.dir.x, 0.0, flag_ship.dir.y) * 700.0
	var at := cam.unproject_position(ahead)
	out["ahead_on_screen"] = Rect2(Vector2.ZERO, Vector2(_size)).has_point(at)
	await hooks.click(at, MOUSE_BUTTON_RIGHT, true)
	await hooks.frames(2)
	await _run(p, 3.0)
	var mains: Array = v._plume.get(flag_ship.uid, [])
	var revs: Array = v._rev_plume.get(flag_ship.uid, [])
	out["go_fwd"] = flag_ship.thrust_fwd
	out["go_main"] = _lit(mains, "engine_")
	out["go_rev"] = _lit(revs, "rev_")
	var cv := Vector3.ZERO
	if not mains.is_empty():
		var m0: MeshInstance3D = mains[0]
		var sm := m0.material_override as ShaderMaterial
		cv = sm.get_shader_parameter("color")
	out["clan_color"] = Color(cv.x, cv.y, cv.z).is_equal_approx(b.defs.doctrine.plume[&"troyden"])
	# шаг 3: колесом ближе (к курсору над флагманом)
	var d0 := v.rig.dist
	var mid := cam.unproject_position(v.ship_point(flag_ship))
	await hooks.move(mid)
	for i in 6:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP
		ev.pressed = true
		ev.position = mid
		ev.global_position = mid
		Input.parse_input_event(ev)
		await hooks.frames(1)
	await _settle(v)
	out["closer"] = v.rig.dist < d0 * 0.8
	out["dist"] = [d0, v.rig.dist]
	# шаг 4: H — «Держать»: тормозит передними гондолами, факел бьёт вперёд
	await hooks.key(KEY_H)
	await hooks.frames(2)
	var best_rev := 0
	var main_then := 99
	var rev_k := 0.0
	var only_rev := 0
	v.paused = false
	for i in 90:
		v.advance(Battle.STEP)
		v.draw_state()
		var n := _lit(revs, "rev_")
		var nm := _lit(mains, "engine_")
		if n == 2 and nm == 0:
			only_rev += 1
		if n > best_rev or (n == best_rev and nm < main_then):
			best_rev = n
			main_then = nm
			rev_k = flag_ship.thrust_rev
	v.paused = true
	out["brake_rev"] = best_rev
	out["brake_main"] = main_then
	out["brake_thrust"] = rev_k
	out["only_rev"] = only_rev
	# шаг 4б: Пробел — пауза, реактор стоит; Пробел — идёт, вертится
	var reactor := vis.part(&"reactor")
	v.paused = false
	await hooks.key(KEY_SPACE)
	out["paused"] = v.paused
	var r0 := reactor.basis
	v.clock += 3.0
	v.draw_state()
	await hooks.frames(5)
	out["still"] = reactor.basis.is_equal_approx(r0)
	await hooks.key(KEY_SPACE)
	await _run(p, 1.0)
	out["turns"] = not reactor.basis.is_equal_approx(r0)
	# шаг 5, начало: «В меню» вверху справа и «Выйти» — снова меню
	var yes := p.leave_panel.find_child("yes", true, false) as Button
	out["to_menu"] = await _press(p.leave_btn) and await _press(yes)
	await hooks.frames(3)
	out["to_menu"] = flag(out["to_menu"]) and str(_main.get("mode")) == "menu"
	return out


## Шаг 5: станция Тройдена — когда Тройден обороняется («Твой клан» — Плэктор). Колесом отдалить
## камеру и стрелкой ↑ уйти к флоту противника: станция стоит позади него.
func _walk_station() -> Dictionary:
	var out := {"opened": false}
	if _main == null or str(_main.get("mode")) != "menu":
		await _close()
		return out
	var p := await _open("plektor", "troyden")
	if p == null:
		await _close()
		return out
	var v := p.view
	var st: Ship = null
	for s in p.battle.ships:
		if s.station:
			st = s
	out["opened"] = st != null and st.side == Ship.DEFENDER
	if st == null:
		await _close()
		return out
	var vis: ShipVisual = v._vis[st.uid]
	var file: String = vis.record.get("file", "")
	out["hand"] = vis.record.get("hand") != null and file == "res://view/hero/troyden_station.glb"
	var cam := v.rig.camera
	var vp := Rect2(Vector2.ZERO, Vector2(_size))
	var on0 := not cam.is_position_behind(v.ship_point(st)) and vp.has_point(cam.unproject_position(v.ship_point(st)))
	var mid := Vector2(_size) * 0.5
	await hooks.move(mid)
	for i in 30:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = true
		ev.position = mid
		ev.global_position = mid
		Input.parse_input_event(ev)
		await hooks.frames(1)
	await _settle(v)
	# и стрелкой ↑ — к флоту противника, пока станция не встанет в кадр (не под шапку и не под панель)
	var inner := Rect2(Vector2(0, 150), Vector2(_size.x, _size.y - 150 - 220))
	var up := InputEventKey.new()
	up.physical_keycode = KEY_UP
	up.keycode = KEY_UP
	up.pressed = true
	Input.parse_input_event(up)
	var held := 0
	for i in 3000:
		await hooks.frames(1)
		held += 1
		if inner.has_point(cam.unproject_position(v.ship_point(st))):
			break
	var rel := up.duplicate() as InputEventKey
	rel.pressed = false
	Input.parse_input_event(rel)
	await hooks.frames(2)
	var sp := cam.unproject_position(v.ship_point(st))
	out["start_on"] = on0
	out["far_on"] = not cam.is_position_behind(v.ship_point(st)) and inner.has_point(sp)
	out["far_dist"] = v.rig.dist
	out["held"] = held
	out["at"] = sp
	out["spins"] = vis.spinning().size() == 1
	await _close()
	return out


func test_release_011_walkthrough() -> void:
	for size: Vector2i in [Vector2i(1366, 768), Vector2i(1920, 1080)]:
		_size = size
		await _walk_both("%d×%d" % [size.x, size.y])
	_size = Vector2i(1366, 768)
	# откаты — каждый краснит свой шаг
	BattleView.rollback_rev_plume_always = true
	var o1 := await _walk()
	await _close()
	BattleView.rollback_rev_plume_always = false
	ok(whole(o1.get("go_rev", 0)) > 0, "откат «реверс горит всегда»: на ходу вперёд горит и реверс (%d) — шаг 2 краснеет" % whole(o1.get("go_rev", 0)))
	var keep := ShipModels.ship(&"troyden", &"capital")
	var plain := keep.duplicate(true)
	plain.erase("hand")
	var troy := dict(dict(ShipModels.data().get("ships")).get("troyden"))
	troy["capital"] = plain
	var o2 := await _walk()
	await _close()
	troy["capital"] = keep
	ok(not flag(o2.get("hand", true)), "откат «модель без hand» — шаг «своя модель» краснеет")
	ShipVisual.rollback_spin_real_clock = true
	var o3 := await _walk()
	await _close()
	ShipVisual.rollback_spin_real_clock = false
	ok(not flag(o3.get("still", true)), "откат «реактор от настоящих часов»: на паузе вертится — шаг 4 краснеет")


## Шаги 1–5 текста выпуска на окне _size.
func _walk_both(tag: String) -> void:
	var w := await _walk()
	var st := await _walk_station()
	note("%s, шаги 1–4: %s" % [tag, str(w)])
	note("%s, шаг 5: %s" % [tag, str(st)])
	if not ok(flag(w["opened"]), "%s, шаг 1: в меню Тройден против Плэктора, «Генеральное», «В бой» — бой открыт" % tag):
		return
	ok(flag(w["hand"]), "%s: флагман Тройдена в бою — своя модель «Ланселота» (view/hero)" % tag)
	ok(flag(w["roster"]) and str(w["roster_text"]).begins_with("Флагман"), "%s, шаг 2: кнопка «Флагман» внизу слева нажимается («%s»)" % [tag, str(w["roster_text"])])
	ok(flag(w["selected"]) and flag(w["cam_on"]), "%s, шаг 2: выбран флагман, камера переехала к нему" % tag)
	ok(flag(w["ahead_on_screen"]), "%s, шаг 3: место в 700 впереди флагмана — на экране, по нему щёлкнули правой" % tag)
	ok(num(w["go_fwd"]) > 0.2 and whole(w["go_main"]) == 2 and whole(w["go_rev"]) == 0, "%s, шаг 3: пошёл — горят две задние (маршевые) гондолы, реверса нет (тяга %.2f, маршевых %d, реверса %d)" % [tag, num(w["go_fwd"]), whole(w["go_main"]), whole(w["go_rev"])])
	ok(flag(w["clan_color"]), "%s, шаг 3: пламя цвета клана Тройден" % tag)
	ok(flag(w["closer"]), "%s, шаг 3: колесо — ближе (%s)" % [tag, str(w["dist"])])
	ok(whole(w["brake_rev"]) == 2 and whole(w["brake_main"]) == 0 and num(w["brake_thrust"]) >= BattleView.REV_MIN and whole(w["only_rev"]) >= 10, "%s, шаг 4: H — тормозит передними гондолами: реверса %d, маршевых %d, тяга назад %.2f, шагов «горит только реверс» %d" % [tag, whole(w["brake_rev"]), whole(w["brake_main"]), num(w["brake_thrust"]), whole(w["only_rev"])])
	ok(flag(w["paused"]) and flag(w["still"]) and flag(w["turns"]), "%s, шаг 4: Пробел — пауза, реактор стоит; снова Пробел — вертится" % tag)
	ok(flag(w.get("to_menu", false)), "%s, шаг 5: «В меню» вверху справа и «Выйти» — снова меню" % tag)
	ok(flag(st["opened"]) and flag(st.get("hand", false)), "%s, шаг 5: «Твой клан» Плэктор, противник Тройден — у Тройдена станция, своя модель" % tag)
	ok(flag(st.get("far_on", false)) and flag(st.get("spins", false)), "%s, шаг 5: колесом отдалить и стрелкой ↑ — станция Тройдена в кадре (дистанция %.0f, в %s), реактор крутится" % [tag, num(st.get("far_dist", 0.0)), str(st.get("at"))])
