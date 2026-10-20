# Свои углы модели (sim/fmath.gd, пакет GТ): синус, косинус и арктангенс считаются в модели
# сложением и умножением double, а не библиотекой C — у Windows-сборки (MinGW, x87) она другая
# в последнем бите, и бой Linux и Windows расходился. Здесь — точность и особые точки; что бой
# на «математике Windows» тот же, проверяет обёртка (run_tests.sh, «математика Windows-сборки»:
# x87 подменой LD_PRELOAD), а что в модели нет библиотечных углов — сторож test_sim_purity.
extends "res://tests/case.gd"

const Fmath := preload("res://sim/fmath.gd")

## Десятичная запись тех же чисел — так выглядела первая выкладка (константы const с длинной
## десятичной записью): разбор GDScript её не округляет точно. Откат проверки точности: on — поставить
## десятичные, off — вернуть биты. Статическое поле класса по имени строкой не поставить (Fmath.set —
## ошибка разбора), поэтому по одному.
static var _bits: Array[float] = []


static func _decimal(on: bool) -> void:
	if on:
		_bits = [Fmath.INVPIO2, Fmath.PIO2_1, Fmath.PIO2_2, Fmath.PIO2_2T, Fmath.PIO2_3, Fmath.PIO2_3T, Fmath.S1, Fmath.S2, Fmath.C1, Fmath.C2]
		Fmath.INVPIO2 = 6.36619772367581382433e-01
		Fmath.PIO2_1 = 1.57079632673412561417e+00
		Fmath.PIO2_2 = 6.07710050630396597660e-11
		Fmath.PIO2_2T = 2.02226624879595063154e-21
		Fmath.PIO2_3 = 2.02226624871116645580e-21
		Fmath.PIO2_3T = 8.47842766036889956997e-32
		Fmath.S1 = -1.66666666666666324348e-01
		Fmath.S2 = 8.33333333332248946124e-03
		Fmath.C1 = 4.16666666666666019037e-02
		Fmath.C2 = -1.38888888888741095749e-03
	elif _bits.size() == 10:
		Fmath.INVPIO2 = _bits[0]
		Fmath.PIO2_1 = _bits[1]
		Fmath.PIO2_2 = _bits[2]
		Fmath.PIO2_2T = _bits[3]
		Fmath.PIO2_3 = _bits[4]
		Fmath.PIO2_3T = _bits[5]
		Fmath.S1 = _bits[6]
		Fmath.S2 = _bits[7]
		Fmath.C1 = _bits[8]
		Fmath.C2 = _bits[9]


## Худшее отклонение от библиотеки C в долях 2^-52·|ответ| (это не больше 1 ulp, когда ≤ 1) и сколько
## ответов не совпали в последнем бите — по n случайным углам и векторам.
func _accuracy(n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var worst := 0.0
	var diff := 0
	var eps := pow(2.0, -52.0)
	for i in n:
		var a := rng.randf_range(-60.0, 60.0)
		var y := rng.randf_range(-1000.0, 1000.0)
		var x := rng.randf_range(-1000.0, 1000.0)
		for pair: Array in [[Fmath.sin_(a), sin(a)], [Fmath.cos_(a), cos(a)], [Fmath.atan2_(y, x), atan2(y, x)]]:
			var got: float = pair[0]
			var want: float = pair[1]
			if got != want:
				diff += 1
				worst = maxf(worst, absf(got - want) / (eps * maxf(absf(want), 1e-300)))
	return {"worst": worst, "diff": diff}


func test_accuracy_vs_libm() -> void:
	var r := _accuracy(30000)
	note("свои углы против библиотеки C: 90 000 ответов, в последнем бите не совпали %d, худшее %.2f × 2^-52 от ответа" % [whole(r["diff"]), num(r["worst"])])
	ok(num(r["worst"]) <= 1.0, "свои sin, cos, atan2 — не дальше 1 ulp от библиотеки C (худшее %.2f)" % num(r["worst"]))
	# откат: константы десятичной записью, как в первой выкладке
	_decimal(true)
	var o := _accuracy(3000)
	var o_pi := Fmath.sin_(PI)
	_decimal(false)
	ok(Fmath.sin_(PI) == sin(PI), "биты вернулись после отката")
	note("откат «константы десятичной записью»: худшее %.1f × 2^-52, sin(π) = %s" % [num(o["worst"]), str(o_pi)])
	ok(num(o["worst"]) > 1.0 or o_pi != sin(PI), "откат «константы десятичной записью» краснеет: худшее %.1f, sin(π) %s" % [num(o["worst"]), str(o_pi)])


func test_special_points_exact() -> void:
	# −0 — из строки: «-1.0 * 0.0» GDScript сворачивает в константу, а константы 0.0 и −0.0 у него
	# сливаются (равны по ==), и тогда и обычный 0.0 в этом файле стал бы −0.0
	var nz := "-0.0".to_float()
	ok(1.0 / nz < 0.0, "−0 настоящий (1/−0 = −∞)")
	var cases := {
		"sin 0": [Fmath.sin_(0.0), sin(0.0)],
		"sin π": [Fmath.sin_(PI), sin(PI)],
		"sin −π": [Fmath.sin_(-PI), sin(-PI)],
		"cos π": [Fmath.cos_(PI), cos(PI)],
		"sin π/2": [Fmath.sin_(PI * 0.5), sin(PI * 0.5)],
		"cos π/2": [Fmath.cos_(PI * 0.5), cos(PI * 0.5)],
		"sin 2π": [Fmath.sin_(TAU), sin(TAU)],
		"atan2(0, −1)": [Fmath.atan2_(0.0, -1.0), atan2(0.0, -1.0)],
		"atan2(−0, −1)": [Fmath.atan2_(nz, -1.0), atan2(nz, -1.0)],
		"atan2(1, 0)": [Fmath.atan2_(1.0, 0.0), atan2(1.0, 0.0)],
		"atan2(−1, 0)": [Fmath.atan2_(-1.0, 0.0), atan2(-1.0, 0.0)],
		"atan2(0, 1)": [Fmath.atan2_(0.0, 1.0), atan2(0.0, 1.0)],
		"atan2(−1, −1)": [Fmath.atan2_(-1.0, -1.0), atan2(-1.0, -1.0)],
	}
	var bad := PackedStringArray()
	for k: String in cases:
		var p: Array = cases[k]
		var got: float = p[0]
		var want: float = p[1]
		if got != want or (got == 0.0 and (1.0 / got > 0.0) != (1.0 / want > 0.0)):
			bad.append("%s: %s против %s" % [k, str(got), str(want)])
	ok(bad.is_empty(), "особые точки — один в один с библиотекой C (sin(π) — ровно остаток π − double(π), знак нуля у atan2): %s" % "; ".join(bad))
	# нос по курсу — тот же вектор, что (−sin, −cos), и на всех четвертях
	var nb := PackedStringArray()
	for a: float in [0.0, 0.3, -0.3, PI * 0.5, 2.0, PI, -2.5, 4.0, -PI * 1.5, 55.5]:
		if Fmath.nose(a) != Vector2(-Fmath.sin_(a), -Fmath.cos_(a)):
			nb.append(str(a))
	ok(nb.is_empty(), "Fmath.nose(a) = (−sin a, −cos a) на всех четвертях: %s" % ", ".join(nb))
