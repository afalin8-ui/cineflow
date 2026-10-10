extends SceneTree
# Сверка переноса: таблица 2.22 части 02 (приход в точку и торможение),
# снятая в JS шагом 1/30 с. Тот же код (face/thrust_to/arrive/update_ship).
const Battle = preload("res://sim/battle.gd")
const JS_ARRIVE := {"corvette": [12.67, 9.53, 13.07, 1.6], "frigate": [15.63, 11.73, 16.17, 1.2], "ecm": [17.7, 13.23, 18.3, 0.9],
	"cruiser": [20.77, 15.9, 21.63, 0.6], "carrier": [24.3, 18.33, 25.3, 0.5], "capital": [25.47, 19.37, 26.63, 0.4], "sinho": [27.53, 20.7, 28.7, 0.4]}
const JS_BRAKE := {"corvette": [99.0, 3.33], "frigate": [95.2, 3.97], "ecm": [91.2, 4.33], "cruiser": [119.7, 6.27],
	"carrier": [99.6, 6.37], "capital": [106.6, 7.03], "sinho": [94.5, 6.93]}

func load_json(p: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(p))

func one(D, DOC, fac: String, id: String) -> Array:
	var b = Battle.new(D, DOC, {"attacker": {"faction": fac, "ships": [{"id": id, "count": 1}]},
		"defender": {"faction": "troyden", "ships": []}, "ai_sides": []}, 1)
	var e = b.state.ships[0]
	e.pos = Vector3.ZERO; e.anchor = Vector3.ZERO
	for g in e.guns: g.cd = 99
	return [b, e]

func arrive_time(D, DOC, fac, id, goal: Vector3) -> Array:
	var r := one(D, DOC, fac, id); var b = r[0]; var e = r[1]
	e.move_to = goal
	var dt := 1.0 / 30.0
	var maxpast := 0.0
	var path := goal.normalized()
	while e.move_to != null and b.state.time < 120:
		b.state.time += dt
		b.update_ship(e, dt)
		maxpast = maxf(maxpast, e.pos.dot(path) - goal.length())
	return [b.state.time, maxpast, e.pos.distance_to(goal)]

func brake(D, DOC, fac, id) -> Array:
	var r := one(D, DOC, fac, id); var b = r[0]; var e = r[1]
	e.stance = "hold"
	e.vel = e.dir * float(e.def.maxSpeed)
	var p0: Vector3 = e.pos; var dt := 1.0 / 30.0; var t0: float = b.state.time
	while e.vel.length() >= 0.5 and b.state.time < 60:
		b.state.time += dt
		b.update_ship(e, dt)
	return [e.pos.distance_to(p0), b.state.time - t0]

func _init():
	var D := load_json("res://data/space_data.json"); var DOC := load_json("res://data/doctrine.json")
	var worst := 0.0
	print("класс       | вперёд 600  | вбок 400    | назад 600   | перелёт | встал | тормозной путь | время")
	for id in ["corvette", "frigate", "ecm", "cruiser", "carrier", "capital", "sinho"]:
		var fac := "plektor" if id == "sinho" else "troyden"
		var f := arrive_time(D, DOC, fac, id, Vector3(0, 0, -600))
		var s := arrive_time(D, DOC, fac, id, Vector3(400, 0, 0))
		var bk := arrive_time(D, DOC, fac, id, Vector3(0, 0, 600))
		var br := brake(D, DOC, fac, id)
		var js: Array = JS_ARRIVE[id]; var jb: Array = JS_BRAKE[id]
		for pair in [[f[0], js[0]], [s[0], js[1]], [bk[0], js[2]], [br[1], jb[1]]]:
			worst = maxf(worst, absf(pair[0] - pair[1]))
		print("%-11s | %5.2f (%5.2f) | %5.2f (%5.2f) | %5.2f (%5.2f) | %4.1f | %4.1f (%3.1f) | %6.1f (%6.1f) | %4.2f (%4.2f)" % [id, f[0], js[0], s[0], js[1], bk[0], js[2], maxf(f[1], 0.0), f[2], js[3], br[0], jb[0], br[1], jb[1]])
	print("наибольшее расхождение по времени с JS: %.3f с" % worst)
	quit()
