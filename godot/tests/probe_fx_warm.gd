# Проба прогрева эффектов боя ОТДЕЛЬНЫМ процессом (пакет GЭ, п. 7; 07, ловушка 29; 08, ловушка 15):
#   godot --path godot [--rendering-method …] -s res://tests/probe_fx_warm.gd -- warm|cold <файл итога>
# Бой-проба с небом и планетой, как в игре; 24 кадра ждём, запоминаем счётчики сборок конвейеров
# и дальше по очереди делаем всё, что впервые рисует новое: факелы на ходу, выбор одного РЭБ
# (стенка купола), гибель корабля (огонь, искры, обломки, дым), подбитый горит и дымит, гипер
# (воронка ухода и выхода), залп главного калибра. Сборки после первых кадров по шагам — в итог.
# warm — как в игре; cold — откат BattleFx.rollback_no_warm: пулы огня и дыма заводятся на первом
# взрыве, стенка купола, воронки и факелы впервые рисуются при первом случае.
# Почему отдельным процессом: конвейер, однажды собранный, живёт до конца процесса (тот же урок,
# что у tests/probe_warmup.gd), и в общем прогоне откат ничего бы не собрал.
extends SceneTree

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const BattleView := preload("res://view/battle_view.gd")
const BattleFx := preload("res://view/battle_fx.gd")
const HyperFx := preload("res://view/hyper_fx.gd")
const Probe := preload("res://tests/probe_warmup.gd")

const BIG := 1.0e9


func _initialize() -> void:
	_run.call_deferred()


func _put(b: Battle, side: int, id: StringName, pos: Vector2, look: Vector2, quiet: bool) -> Ship:
	var s := b.spawn(side, b.defs.ship(b.sides[side].clan, id), pos)
	s.set_yaw(Ship.yaw_of(look - pos))
	s.stance = &"hold"
	s.hp = BIG
	s.max_hp = BIG
	if quiet:
		s.switch_off(&"engines", BIG)
		s.main_cd = PackedFloat64Array()
		s.sec_cd = PackedFloat64Array()
		s.light_cd = PackedFloat64Array()
		s.mis_cd = PackedFloat64Array()
		s.pd_cd = PackedFloat64Array()
	return s


static func _kinds() -> Array[int]:
	var out: Array[int] = []
	for k: RenderingServer.RenderingInfo in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		out.append(RenderingServer.get_rendering_info(k))
	return out


func _steps(v: BattleView, n: int) -> void:
	for i in n:
		v.paused = false
		v.advance(Battle.STEP)
		v.paused = true
		v.draw_state()
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "warm"
	var out := args[1] if args.size() > 1 else ""
	await process_frame
	root.size = Vector2i(960, 540)
	await process_frame
	BattleFx.rollback_no_warm = mode == "cold"
	var defs := Defs.load_default({}) as Defs
	var b := Battle.create(defs, {"attacker": &"troyden", "defender": &"plektor", "size": &"small", "seed": 3, "reserve": false}) as Battle
	b.ships.clear()
	var ecm := _put(b, Ship.ATTACKER, &"ecm", Vector2(-300, 200), Vector2(-300, -400), true)
	var cr := _put(b, Ship.ATTACKER, &"cruiser", Vector2(0, 200), Vector2(0, -400), false)
	var mover := _put(b, Ship.ATTACKER, &"frigate", Vector2(300, 250), Vector2(300, -400), true)
	var foe := _put(b, Ship.DEFENDER, &"cruiser", Vector2(0, -400), Vector2(0, 200), true)
	var dying := _put(b, Ship.DEFENDER, &"corvette", Vector2(250, -350), Vector2(0, 200), true)
	cr.main_cd = PackedFloat64Array([BIG])
	var v := BattleView.new()
	root.add_child(v)
	v.setup(defs, b, true)
	v.paused = true
	v.set_process(false)
	v.rig.edge_enabled = false
	v.rig.input_enabled = false
	v.rig.set_view(Vector3(0, 0, -100), 0.0, 1500.0, true)
	for i in 40:
		v.draw_state()
		await process_frame
	var before := Probe.compilations()
	var steps := {}
	# покой: ничего нового — сборок быть не должно и без прогрева
	await _steps(v, 12)
	steps["покой"] = Probe.compilations() - before
	# факелы: фрегат идёт вперёд (двигатели — модель, тяга — по приказу)
	mover.off_until.erase(&"engines")
	b.queue({"op": &"move", "ids": [mover.uid], "to": Vector2(300, -200)})
	await _steps(v, 20)
	steps["факел"] = Probe.compilations() - before
	# выбран крейсер — кольцо выбора линией (оно было и до GЭ; меряется отдельно)
	v.selection = [cr.uid]
	await _steps(v, 4)
	steps["выбор"] = Probe.compilations() - before
	# выбран один РЭБ — стенка купола
	v.selection = [ecm.uid]
	await _steps(v, 6)
	steps["купол"] = Probe.compilations() - before
	v.selection = []
	# гибель корвета — огонь, искры, обломки, дым
	dying.dead = true
	v.bfx.consume([&"destroyed", dying.uid, 0])
	await _steps(v, 12)
	steps["взрыв"] = Probe.compilations() - before
	# подбитый чужой крейсер горит и дымит
	foe.hp = foe.max_hp * 0.15
	await _steps(v, 12)
	steps["дым"] = Probe.compilations() - before
	# гипер: воронка ухода и выход
	foe.hyper_left = 2.3
	await _steps(v, 10)
	v.hyper.consume([&"jump_in", ecm.uid])
	await _steps(v, 8)
	steps["гипер"] = Probe.compilations() - before
	# залп главного калибра
	cr.main_cd = PackedFloat64Array([0.0])
	cr.target = foe
	await _steps(v, 12)
	steps["залп"] = Probe.compilations() - before
	var after := Probe.compilations()
	var res := {"mode": mode, "before": before, "after": after, "steps": steps, "booms": v.bfx.booms,
		"renderer": RenderingServer.get_current_rendering_method()}
	BattleFx.rollback_no_warm = false
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(res))
			f.close()
	print("FXWARM ", JSON.stringify(res))
	v.queue_free()
	await process_frame
	b.dispose()
	quit(0)
