# tests/probe_smooth.gd — проба плавности (план G1, игровые проверки; архитектура, 3)
# ОТДЕЛЬНЫМ процессом под Movie Maker: движок пишет каждый кадр картинкой с постоянным
# шагом времени, и сдвиг корабля между соседними кадрами меряется по ТОЧКАМ кадра,
# а не по числам вида. Запускает tests/test_render_polygon.gd:
#   godot --path godot --write-movie ПАПКА/f.png --fixed-fps 60|144 --quit-after N \
#         -s res://tests/probe_smooth.gd -- smooth|raw
# smooth — как в игре (своя интерполяция); raw — откат: рисуем нынешнее положение
# без смешивания, и на 60 Гц корабль шагает через кадр (7, 0, 7, 0 — замер C).
# Сцена: один корвет на чёрном фоне идёт поперёк кадра полным ходом, камера стоит.
extends SceneTree

const Defs := preload("res://sim/defs.gd")
const Battle := preload("res://sim/battle.gd")
const Ship := preload("res://sim/ship.gd")
const BattleView := preload("res://view/battle_view.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "smooth"
	# покачивание выключено: меряем ход по x, высота не нужна
	var defs := Defs.load_default({"view.bob": 0.0}) as Defs
	var b := Battle.create(defs, {"attacker": &"troyden", "defender": &"plektor", "size": &"small", "seed": 3, "reserve": false}) as Battle
	b.ships.clear()
	var s := b.spawn(Ship.ATTACKER, defs.ship(&"troyden", &"corvette"), Vector2(-70.0, 0.0))
	# противник далеко за кадром: без него бой кончился бы на первом шаге («сторона ушла»)
	b.spawn(Ship.DEFENDER, defs.ship(&"plektor", &"corvette"), Vector2(0.0, -2400.0))
	s.set_yaw(-PI * 0.5)                         # нос — по +x
	s.vel = Vector2(s.max_speed(), 0.0)
	b.queue({"op": &"move", "ids": [s.uid], "x": 3000.0, "z": 0.0})
	var v := BattleView.new()
	root.add_child(v)
	v.setup(defs, b, false)
	v.smooth = mode != "raw"
	v.rig.edge_enabled = false
	v.rig.input_enabled = false
	v.rig.set_view(Vector3.ZERO, 0.0, 500.0, true)
	print("PROBE smooth=%s fixed-fps кадров %d" % [str(v.smooth), Engine.get_frames_drawn()])
