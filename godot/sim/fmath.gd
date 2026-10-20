# sim/fmath.gd — синус, косинус и арктангенс модели СВОИМИ силами (пакет GТ).
#
# Зачем. sin, cos и atan2 библиотеки C у Linux и Windows РАЗНЫЕ: выгруженная Windows-сборка
# Godot собрана MinGW, и её sin/cos/atan2 считает x87 (fsin, fcos, fpatan) — в последнем бите
# ответы расходятся с glibc. Замер на показательном бое (60 с): sin — 799 расхождений из 138 486
# вызовов, cos — 95 из 121 730, atan2 — 73 из 108 017; sin(π) у x87 — 1,2246064e-16 против
# 1,2246468e-16 у glibc. До пакета GТ все расхождения гасли: направление носа — float32, и
# разница в бите double до него почти никогда не доходит. С новым темпом одна не погасла: курс
# машины 43 на 133-м шаге разошёлся в последнем бите, и отпечаток боя Linux и Windows разошёлся
# (CI, прогон 39395472501: 3e7d77265b341601 против 6acf30ec42df922a). Воспроизведено здесь же:
# подмена sin/cos/atan2 на x87 (LD_PRELOAD) даёт на Linux ровно отпечаток Windows.
#
# Поэтому модель считает их сама — только сложением, вычитанием, умножением и делением double,
# а они по IEEE одинаковы везде. Алгоритмы — FreeBSD msun (fdlibm): приведение к [−π/4, π/4]
# тремя частями π/2 (Cody–Waite), ядра __kernel_sin и __kernel_cos, s_atan и e_atan2. Ошибка —
# меньше 1 ulp (с glibc в последнем бите совпадает не всегда, и бои Linux от этого другие, чем
# до правки, — но одинаковые на обеих системах). Сверено с glibc на 4 млн случайных значений:
# расхождение не больше 1 ulp, особые точки (0, ±π, π/2, 2π, ±0 у atan2) — один в один.
# Приведение верно, пока |x| < 2^20 · π/2 (≈ 1,6 млн): курсы и часы модели много меньше.
#
# В sim/ библиотечные sin, cos, atan2 (и угловые методы Vector2 — они float32 и тоже из
# библиотеки C) — нарушение: сторож test_sim_purity пускает их только сюда, за флажок отката.
extends RefCounted

## ТОЛЬКО для проверки отката: считать библиотекой C, как до правки. С ним прежние числа
## доктрины (OLD_TEMPO) дают бой 0.7.1 до бита — это и доказывает, что GТ поменял только числа
## и способ считать углы (tests/test_tempo_gt.gd). В игре — false.
static var rollback_libm := false

## Числа алгоритмов — БИТАМИ double, а не десятичной записью: разбор длинного десятичного
## числа в GDScript не округляет точно (проверено: с десятичными константами sin(π) выходил
## 5,7e-16 вместо 1,2e-16, sin(10) — с ошибкой в 6 ulp). Биты — из десятичной записи FreeBSD,
## переведённой точно (Python float).
static var TOINT := _d(0x4338000000000000)   # 1,5 · 2^52: (x + TOINT) − TOINT — округление к ближайшему
static var PIO4 := _d(0x3FE921FB54442D18)   # π/4
static var INVPIO2 := _d(0x3FE45F306DC9C883)   # 2/π
static var PIO2_1 := _d(0x3FF921FB54400000)   # первые 33 бита π/2
static var PIO2_2 := _d(0x3DD0B4611A600000)   # следующие 33 бита
static var PIO2_2T := _d(0x3BA3198A2E037073)   # π/2 − PIO2_1 − PIO2_2
static var PIO2_3 := _d(0x3BA3198A2E000000)   # и ещё 33 бита
static var PIO2_3T := _d(0x397B839A252049C1)   # остаток
static var S1 := -_d(0x3FC5555555555549)   # ядро синуса
static var S2 := _d(0x3F8111111110F8A6)
static var S3 := -_d(0x3F2A01A019C161D5)
static var S4 := _d(0x3EC71DE357B1FE7D)
static var S5 := -_d(0x3E5AE5E68A2B9CEB)
static var S6 := _d(0x3DE5D93A5ACFD57C)
static var C1 := _d(0x3FA555555555554C)   # ядро косинуса
static var C2 := -_d(0x3F56C16C16C15177)
static var C3 := _d(0x3EFA01A019CB1590)
static var C4 := -_d(0x3E927E4F809C52AD)
static var C5 := _d(0x3E21EE9EBDB4B1C4)
static var C6 := -_d(0x3DA8FAE9BE8838D4)
static var ATANHI_0 := _d(0x3FDDAC670561BB4F)   # atan(0,5)
static var ATANHI_1 := _d(0x3FE921FB54442D18)   # atan(1)
static var ATANHI_2 := _d(0x3FEF730BD281F69B)   # atan(1,5)
static var ATANHI_3 := _d(0x3FF921FB54442D18)   # atan(∞)
static var ATANLO_0 := _d(0x3C7A2B7F222F65E2)
static var ATANLO_1 := _d(0x3C81A62633145C07)
static var ATANLO_2 := _d(0x3C7007887AF0CBBD)
static var ATANLO_3 := _d(0x3C91A62633145C07)
static var AT0 := _d(0x3FD555555555550D)   # многочлен арктангенса
static var AT1 := -_d(0x3FC999999998EBC4)
static var AT2 := _d(0x3FC24924920083FF)
static var AT3 := -_d(0x3FBC71C6FE231671)
static var AT4 := _d(0x3FB745CDC54C206E)
static var AT5 := -_d(0x3FB3B0F2AF749A6D)
static var AT6 := _d(0x3FB10D66A0D03D51)
static var AT7 := -_d(0x3FADDE2D52DEFD9A)
static var AT8 := _d(0x3FA97B4B24760DEB)
static var AT9 := -_d(0x3FA2B4442C6A6C2F)
static var AT10 := _d(0x3F90AD3AE322DA11)
static var PI_HI := _d(0x400921FB54442D18)   # π
static var PI_LO := _d(0x3CA1A62633145C07)   # π − PI_HI
static var PIO2_HI := _d(0x3FF921FB54442D18)   # π/2
static var ATAN_BIG := _d(0x4410000000000000)   # 2^66
static var ATAN_TINY := _d(0x3E30000000000000)   # 2^-28
static var Q_BIG := _d(0x43B0000000000000)   # 2^60
static var Q_TINY := _d(0x3C30000000000000)   # 2^-60


static func _d(bits: int) -> float:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_s64(0, bits)
	return b.decode_double(0)


## Остаток приведения последнего вызова _reduce: x = n·π/2 + (_y0 + _y1).
static var _y0 := 0.0
static var _y1 := 0.0


## Приведение к [−π/4, π/4]: → n (четверть), остаток — в _y0 + _y1. Три части π/2 всегда: так
## точно и у кратных π (sin(π) — ровно остаток π − double(π)), а ветвиться по показателю
## степени, как FreeBSD, в GDScript нечем.
static func _reduce(x: float) -> int:
	var fn := (x * INVPIO2 + TOINT) - TOINT
	var r := x - fn * PIO2_1
	var t := r
	var w := fn * PIO2_2
	r = t - w
	w = fn * PIO2_2T - ((t - r) - w)
	t = r
	w = fn * PIO2_3
	r = t - w
	w = fn * PIO2_3T - ((t - r) - w)
	_y0 = r - w
	_y1 = (r - _y0) - w
	return int(fn)


## __kernel_sin: |x| ≤ π/4, y — хвост x (0 — нет хвоста).
static func _ksin(x: float, y: float, tail: bool) -> float:
	var z := x * x
	var w := z * z
	var r := S2 + z * (S3 + z * S4) + z * w * (S5 + z * S6)
	var v := z * x
	if not tail:
		return x + v * (S1 + z * r)
	return x - ((z * (0.5 * y - v * r) - y) - v * S1)


## __kernel_cos: |x| ≤ π/4, y — хвост x.
static func _kcos(x: float, y: float) -> float:
	var z := x * x
	var w := z * z
	var r := z * (C1 + z * (C2 + z * C3)) + w * w * (C4 + z * (C5 + z * C6))
	var hz := 0.5 * z
	w = 1.0 - hz
	return w + (((1.0 - w) - hz) + (z * r - x * y))


static func sin_(x: float) -> float:
	if rollback_libm:
		return sin(x)
	if absf(x) <= PIO4:
		return _ksin(x, 0.0, false)
	var n := _reduce(x) & 3
	if n == 0:
		return _ksin(_y0, _y1, true)
	if n == 1:
		return _kcos(_y0, _y1)
	if n == 2:
		return -_ksin(_y0, _y1, true)
	return -_kcos(_y0, _y1)


static func cos_(x: float) -> float:
	if rollback_libm:
		return cos(x)
	if absf(x) <= PIO4:
		return _kcos(x, 0.0)
	var n := _reduce(x) & 3
	if n == 0:
		return _kcos(_y0, _y1)
	if n == 1:
		return -_ksin(_y0, _y1, true)
	if n == 2:
		return -_kcos(_y0, _y1)
	return _ksin(_y0, _y1, true)


## Направление носа по курсу (0 — нос в −Z): (−sin a, −cos a) одним приведением на оба.
## Вектор float32, как и был (Ship.dir).
static func nose(a: float) -> Vector2:
	if rollback_libm:
		return Vector2(-sin(a), -cos(a))
	var s: float
	var c: float
	if absf(a) <= PIO4:
		s = _ksin(a, 0.0, false)
		c = _kcos(a, 0.0)
	else:
		var n := _reduce(a) & 3
		var ks := _ksin(_y0, _y1, true)
		var kc := _kcos(_y0, _y1)
		if n == 0:
			s = ks
			c = kc
		elif n == 1:
			s = kc
			c = -ks
		elif n == 2:
			s = -ks
			c = -kc
		else:
			s = -kc
			c = ks
	return Vector2(-s, -c)


## s_atan: арктангенс.
static func atan_(x: float) -> float:
	var ax := absf(x)
	var neg := x < 0.0
	if ax >= ATAN_BIG:
		return -(ATANHI_3 + ATANLO_3) if neg else ATANHI_3 + ATANLO_3
	var id := -1
	if ax < 0.4375:
		if ax < ATAN_TINY:                       # atan(x) = x
			return x
	else:
		x = ax
		if ax < 1.1875:
			if ax < 0.6875:
				id = 0
				x = (2.0 * x - 1.0) / (2.0 + x)
			else:
				id = 1
				x = (x - 1.0) / (x + 1.0)
		elif ax < 2.4375:
			id = 2
			x = (x - 1.5) / (1.0 + 1.5 * x)
		else:
			id = 3
			x = -1.0 / x
	var z := x * x
	var w := z * z
	var s1 := z * (AT0 + w * (AT2 + w * (AT4 + w * (AT6 + w * (AT8 + w * AT10)))))
	var s2 := w * (AT1 + w * (AT3 + w * (AT5 + w * (AT7 + w * AT9))))
	if id < 0:
		return x - x * (s1 + s2)
	var hi := ATANHI_0
	var lo := ATANLO_0
	if id == 1:
		hi = ATANHI_1
		lo = ATANLO_1
	elif id == 2:
		hi = ATANHI_2
		lo = ATANLO_2
	elif id == 3:
		hi = ATANHI_3
		lo = ATANLO_3
	z = hi - ((x * (s1 + s2) - lo) - x)
	return -z if neg else z


## e_atan2: угол вектора (x, y), знак нуля учитывается (atan2(−0, −1) = −π, как у библиотеки C).
static func atan2_(y: float, x: float) -> float:
	if rollback_libm:
		return atan2(y, x)
	if is_nan(x) or is_nan(y):
		return x + y
	if x == 1.0:
		return atan_(y)
	var yneg := y < 0.0 or (y == 0.0 and 1.0 / y < 0.0)
	var xneg := x < 0.0 or (x == 0.0 and 1.0 / x < 0.0)
	if y == 0.0:
		if not xneg:
			return y
		return -PI_HI if yneg else PI_HI
	if x == 0.0:
		return -PIO2_HI if yneg else PIO2_HI
	var q := absf(y / x)
	var z: float
	if q > Q_BIG:                                # |y| много больше |x|
		z = PIO2_HI + 0.5 * PI_LO
	elif xneg and q < Q_TINY:
		z = 0.0
	else:
		z = atan_(q)
	if not xneg:
		return -z if yneg else z
	if not yneg:
		return PI_HI - (z - PI_LO)
	return (z - PI_LO) - PI_HI
