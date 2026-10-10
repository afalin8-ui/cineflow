# Чистота модели (архитектура, 1 и 10.2 п. 1): sim/ не знает о view/, ui/,
# input/, audio/ (ни preload, ни load, ни extends, ни их глобальных классов);
# в sim/ нет узлов и ресурсов картинки (спрашиваем ClassDB, а не список имён),
# настоящего времени, движка, ввода, случайности без генератора боя и сигналов.
#
# Двери — по правилу «можно только своё», а не «нельзя вот это»: путь из preload/
# load/ResourceLoader.load/extends разворачивается так же, как его разворачивает
# Godot, и обязан лежать в res://sim/. Разворачивают они ПО-РАЗНОМУ (проверено
# в 4.7.2, G1): у preload и extends относительный путь — от папки самого файла,
# а у load() и ResourceLoader.load — от res:// («view/x.gd» из sim/ — это
# res://view/x.gd, «./ui/…» — res://ui/…); «..», «./» и обратные косые
# схлопываются. Путь не одной строкой (константа, переменная, склейка) — дверь:
# не видно, куда он ведёт. Любая строка-путь в модели — только в sim/ или data/
# (так закрыта константа-путь, отданная в load). Глобальная функция, взятая как
# значение (var l := load, var f := str_to_var, var r := randf), — та же дверь,
# что её вызов; Expression вызывает их по строке. Случайное — только из rng
# и fx_rng боя: генератор без зерна (RandomNumberGenerator.new() без .seed
# следующей строкой, randomize()), Array.shuffle() и pick_random() (общий генератор
# движка), Crypto — нарушение; порядок по номеру объекта (get_instance_id, hash(объект))
# — тоже: номер зависит от того, сколько объектов завёл вид, а hash объекта — от адреса
# в памяти, разного у каждого запуска. Остальное ищется в коде без
# комментариев и строк: слово в пояснении или в тексте ошибки — не нарушение.
extends "res://tests/case.gd"

## Куда модель может грузить и от чего наследовать: только своё.
const OWN_SCRIPTS: Array[String] = ["res://sim"]
## Какие пути модель может упоминать строкой: своё и данные (doctrine.json, выгрузка).
const OWN_LITERALS: Array[String] = ["res://sim", "res://data"]
## Файл, от которого разворачиваются относительные пути строк-проб (не файлов sim/).
const PROBE_FILE := "res://sim/probe.gd"

## Метки на месте строкового литерала в коде: \u0001N\u0002, N — номер литерала.
const LIT_OPEN := "\u0001"
const LIT_CLOSE := "\u0002"
## Загрузка: preload(…), load(…), ResourceLoader.load*(…); группа 1 — «preload»,
## «load» или пусто (ResourceLoader), группа 2 — номер литерала, если путь отдан
## ОДНОЙ строкой (дальше — «,» или «)»), иначе пусто.
const LOADER := "(?:(?<![\\w.])(preload|load)|\\bResourceLoader\\s*\\.\\s*load\\w*)\\s*\\((?:\\s*\\x01(\\d+)\\x02\\s*[,)])?"
## load как значение (без скобок следом): var l := load — дальше l.call(путь), и путь
## уже не виден сторожу.
const LOAD_VALUE := "(?<![\\w.])load\\b(?!\\s*\\()"
## Генератор: «X := RandomNumberGenerator.new()» — зерно обязано стоять следующей
## строкой кода («X.seed = …»), иначе Godot берёт его из часов, и бой не повторится.
const RNG_NEW := "RandomNumberGenerator\\s*\\.\\s*new\\s*\\("
const RNG_LINE := "^\\s*(?:var\\s+)?([\\w.]+)\\s*(?::\\s*\\w+\\s*)?:?=\\s*RandomNumberGenerator\\s*\\.\\s*new\\s*\\(\\s*\\)\\s*$"
## Наследование от пути (от имени класса — см. foreign_classes).
const EXTENDS_PATH := "\\bextends\\s+\\x01(\\d+)\\x02"
## Путь res:// внутри строки (в том числе посреди текста).
const RES_IN_TEXT := "res://[^\\s\"'<>|?*]*"

## Запрещённое по образцу (текст без строк): образец → почему.
const BANNED := [
	["get_tree\\s*\\(", "дерево сцены"],
	# и вызов, и значение: var r := randf — та же глобальная случайность (проверено в 4.7.2)
	["(?<![.\\w])(randf|randi|randf_range|randi_range|randfn|randomize|seed|rand_from_seed)\\b", "случайность — только rng и fx_rng боя"],
	["\\.\\s*randomize\\s*\\(", "генератор без зерна: randomize() берёт зерно из часов — бой не повторится"],
	# у Array.shuffle() и pick_random() свой генератор не передать: они берут ОБЩИЙ генератор
	# движка (документация Godot: «use a common, global random seed») — с тем же зерном боя
	# выйдет другой бой, и на Windows не тот, что на Linux (замечание к G1)
	["\\.\\s*(?:shuffle|pick_random)\\s*\\(", "общий генератор движка, а не rng боя: тот же бой с тем же зерном выйдет другим — выбирать через rng.randi_range"],
	# номер объекта — счётчик ВСЕХ созданных объектов: вид и интерфейс заводят свои раньше
	# или позже модели, и порядок «по номеру» с видом и без вида разный; hash(объект) — от
	# АДРЕСА в памяти, он разный даже у двух запусков подряд (проверено в 4.7.2)
	["\\bget_instance_id\\b|(?<![.\\w])hash\\s*\\(", "номер объекта зависит от того, сколько объектов завели вид и интерфейс, а hash(объект) — от адреса в памяти (разный у каждого запуска): порядок по ним не повторится — у корабля свой uid, у строки — sha256_text()"],
	["\\bsignal\\b|\\bSignal\\b|\\bemit_signal\\b|\\.emit\\s*\\(|\\.connect\\s*\\(", "сигналов из шага нет — события шага списком"],
	["\\bawait\\b", "шаг модели не ждёт"],
	["(?<![.\\w])(?:str_to_var|bytes_to_var_with_objects|dict_to_inst|instance_from_id)\\b|\\bto_native\\b",
		"объект по строке или номеру — в обход сторожа узлов: str_to_var(\"Object(Node3D…)\") создаёт узел (проверено); взятая как значение (var f := str_to_var) — та же дверь"],
]

## Классы движка, которые модели НЕ узлы и не ресурсы, но всё равно чужие.
const EXTRA_BANNED := {
	"SceneTree": "дерево сцены", "MainLoop": "дерево сцены", "SceneTreeTimer": "дерево сцены",
	"Tween": "анимация вида", "Thread": "потоки — отдельным решением с замером",
	"Expression": "выражение строкой вызывает load, str_to_var и прочие глобальные функции в обход сторожа (проверено в 4.7.2)",
	"Crypto": "случайность ОС (generate_random_bytes) — бой не повторится; случайное — только rng и fx_rng боя",
}
## Ресурсы, без которых загрузчику не обойтись: JSON — разбор с номером строки.
const ALLOWED_RESOURCES := ["JSON"]
## Синглтоны движка, которые модели можно: чистая геометрия и кодировки.
const ALLOWED_SINGLETONS := ["Geometry2D", "Geometry3D", "Marshalls"]
## Расширения, которые load() превращает в код, сцену или ресурс.
const CODE_EXT: Array[String] = ["gd", "gdc", "tscn", "scn", "tres", "res", "gdshader", "glb", "gltf"]
## Раскрытие escape-последовательностей в строке GDScript (\u и \U — отдельно).
const ESCAPES := {"n": "\n", "t": "\t", "r": "\r", "a": "\u0007", "b": "\u0008", "f": "\u000c", "v": "\u000b"}


## Лексер GDScript в той мере, что нужна сторожу. Убирает комментарии, вынимает
## строковые литералы — "…", '…', тройные, r"…", &"…", ^"…" — с их ЗНАЧЕНИЕМ
## (escape раскрыты, \uXXXX тоже: «res://\u0076iew/…» — это view/) и ставит
## на их место метку LIT_OPEN N LIT_CLOSE. Переводы строк внутри литерала
## остаются после метки, поэтому номера строк кода не съезжают.
## Итог: {code, lits (значения), at (строка, где литерал начался)}.
static func scan(text: String) -> Dictionary:
	var parts := PackedStringArray()
	var lits := PackedStringArray()
	var at := PackedInt32Array()
	var line := 1
	var run := 0
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		if ch == "\n":
			line += 1
			i += 1
		elif ch == "#":
			parts.append(text.substr(run, i - run))
			var e := text.find("\n", i)
			i = n if e < 0 else e
			run = i
		elif ch == "\"" or ch == "'":
			parts.append(text.substr(run, i - run))
			var raw := i > 0 and text[i - 1] == "r" and (i < 2 or not _word_char(text[i - 2]))
			var ql := 3 if text.substr(i, 3) == ch.repeat(3) else 1
			var quote := ch.repeat(ql)
			var start_line := line
			var val := PackedStringArray()
			var j := i + ql
			var seg := j
			var inner_lines := 0
			while j < n:
				var c := text[j]
				if c == "\\":
					val.append(text.substr(seg, j - seg))
					var nx := text[j + 1] if j + 1 < n else ""
					var used := 2
					if raw:
						val.append("\\" + nx if nx == ch or nx == "\\" else "\\")
						used = 2 if nx == ch or nx == "\\" else 1
					elif nx == "u" or nx == "U":
						var hl := 4 if nx == "u" else 6
						var hx := text.substr(j + 2, hl)
						val.append(String.chr(hx.hex_to_int()) if hx.is_valid_hex_number() else nx)
						used = 2 + hl if hx.is_valid_hex_number() else 2
					elif nx == "\n":
						inner_lines += 1
						line += 1
					else:
						val.append(str(ESCAPES.get(nx, nx)))
					j += used
					seg = j
					continue
				if c == "\n":
					if ql == 1:
						break   # незакрытая строка: дальше — снова код
					inner_lines += 1
					line += 1
				if c == ch and text.substr(j, ql) == quote:
					val.append(text.substr(seg, j - seg))
					j += ql
					seg = -1
					break
				j += 1
			if seg >= 0:
				val.append(text.substr(seg, j - seg))
			lits.append("".join(val))
			at.append(start_line)
			parts.append(LIT_OPEN + str(lits.size() - 1) + LIT_CLOSE + "\n".repeat(inner_lines))
			i = j
			run = i
		else:
			i += 1
	parts.append(text.substr(run))
	return {"code": "".join(parts), "lits": lits, "at": at}


static func _word_char(c: String) -> bool:
	return c == "_" or (c >= "0" and c <= "9") or (c.to_lower() != c.to_upper())


## Текст скрипта без комментариев и строк (строка — один пробел).
static func code_only(text: String) -> String:
	var code: String = scan(text)["code"]
	return RegEx.create_from_string("\\x01\\d+\\x02").sub(code, " ", true)


## Путь так, как его развернёт Godot (проверено в 4.7.2): у preload и extends
## относительный — от папки файла; у load() и ResourceLoader.load (from_root) —
## от res:// («view/x.gd» из sim/a.gd — res://view/x.gd). «..», «./» и обратные
## косые схлопнуты (String.simplify_path).
static func resolve(path: String, file: String, from_root: bool = false) -> String:
	var p := path.replace("\\", "/")
	if p.is_relative_path():
		var base := "res://" if from_root else file.get_base_dir()
		return base.path_join(p).simplify_path()
	return p.simplify_path()


static func inside(path: String, roots: Array[String]) -> bool:
	for r in roots:
		if path == r or path.begins_with(r + "/"):
			return true
	return false


## Почему путь из preload/load/extends — дверь ("" — свой). from_root — путь отдан
## load() или ResourceLoader.load: относительный разворачивается от res://.
static func script_door(path: String, file: String, from_root: bool = false) -> String:
	if path.begins_with("uid://"):
		return "путь по uid — не видно, в какой слой он ведёт"
	var full := resolve(path, file, from_root)
	if not inside(full, OWN_SCRIPTS):
		return "модель грузит и наследует только своё (sim/), а этот путь — %s" % full
	if full.get_extension() != "gd":
		return "модель грузит только скрипты: %s — сцена или ресурс, его instantiate() — это узел без единого слова Node" % full
	return ""


## Почему строка-путь в модели — дверь ("" — не путь или свой). Константа с путём
## в view/ и load(константа) — тот же preload, только без слова preload.
static func literal_door(v: String, file: String) -> String:
	if v.contains("uid://"):
		return "путь по uid — не видно, в какой слой он ведёт"
	for m in RegEx.create_from_string(RES_IN_TEXT).search_all(v):
		var full := m.get_string().simplify_path()
		if not inside(full, OWN_LITERALS):
			return "путь вне sim/ и data/ (%s) — даже строкой: load() с ним — дверь" % full
	# относительная строка: куда она поведёт, зависит от того, кто её возьмёт —
	# preload (от папки файла) или load (от res://); дверь, если хоть одна дорога
	# выводит из sim/ и data/
	if _looks_relative(v):
		for from_root: bool in [false, true]:
			var full := resolve(v, file, from_root)
			if not inside(full, OWN_LITERALS):
				return "относительный путь ведёт в %s — вне sim/ и data/ (load разворачивает его от res://)" % full
	return ""


## Строка похожа на относительный путь к файлу проекта: начинается с ./ или ../,
## кончается расширением скрипта, сцены или ресурса, или её первая часть — папка
## проекта («view/…», «ui\\…»). Обычный текст («урон/с», «x.json») — не путь.
static func _looks_relative(v: String) -> bool:
	if v.contains(" ") or v.contains("://") or v.is_empty():
		return false
	var p := v.replace("\\", "/")
	if p.begins_with("./") or p.begins_with("../"):
		return true
	if p.get_extension() in CODE_EXT:
		return true
	var first := p.get_slice("/", 0)
	return p.contains("/") and first != "" and DirAccess.dir_exists_absolute("res://" + first)


## Почему слово с заглавной буквы запрещено в модели ("" — можно). Узлы и ресурсы
## узнаём у ClassDB: новый узел (Area3D, Timer, MeshInstance3D…) не надо вписывать
## в список, чтобы он стал нарушением. foreign — глобальные классы чужих слоёв.
static func why_banned(word: String, foreign: Dictionary) -> String:
	if foreign.has(word):
		return "класс чужого слоя (%s) — двери односторонние" % str(foreign[word])
	if EXTRA_BANNED.has(word):
		return str(EXTRA_BANNED[word])
	if Engine.has_singleton(word) and word not in ALLOWED_SINGLETONS:
		return "синглтон движка: время, ввод, ОС, отрисовка, звук, настройки — модель живёт на battle.time и своих данных"
	if not ClassDB.class_exists(word):
		return ""
	if ClassDB.is_parent_class(word, "Node"):
		return "узел — дело view/ и ui/; в модели классы на RefCounted"
	if ClassDB.is_parent_class(word, "Resource") and word not in ALLOWED_RESOURCES:
		return "ресурс (сцена, сетка, материал, текстура…) — дело view/; .tres для чисел боя нет"
	return ""


## Глобальные классы (class_name) вне sim/: их имя в модели — та же дверь, что preload.
static func foreign_classes() -> Dictionary:
	var out := {}
	for c: Dictionary in ProjectSettings.get_global_class_list():
		var path: String = c["path"]
		if not path.begins_with("res://sim/"):
			out[str(c["class"])] = path
	return out


static func _line_at(code: String, pos: int) -> int:
	return code.substr(0, pos).count("\n") + 1


## Нарушения в одном тексте: «строка N: что — почему». file — где лежит текст:
## от его папки разворачиваются относительные пути.
static func violations(text: String, foreign: Dictionary = {}, file: String = PROBE_FILE) -> PackedStringArray:
	var out := PackedStringArray()
	var s := scan(text)
	var code: String = s["code"]
	var lits: PackedStringArray = s["lits"]
	var at: PackedInt32Array = s["at"]
	# двери: загрузка и наследование — одной строкой и только в sim/
	var judged := {}          # литералы, уже судимые как путь preload/load/extends
	for m in RegEx.create_from_string(LOADER).search_all(code):
		var k := m.get_string(2)
		var by_load := m.get_string(1) != "preload"      # load( и ResourceLoader.load — от res://
		var why := "путь не одной строкой (константа, переменная, склейка) — не видно, куда ведёт; в модели только preload(\"res://sim/…\")"
		if k != "":
			why = script_door(lits[k.to_int()], file, by_load)
			judged[k.to_int()] = true
		if why != "":
			out.append("строка %d: дверь: %s — %s" % [_line_at(code, m.get_start()), "загрузка load()" if by_load else "загрузка", why])
	for m in RegEx.create_from_string(EXTENDS_PATH).search_all(code):
		var why := script_door(lits[m.get_string(1).to_int()], file)
		judged[m.get_string(1).to_int()] = true
		if why != "":
			out.append("строка %d: дверь: extends — %s" % [_line_at(code, m.get_start()), why])
	# строки-пути: только своё и данные
	for k in lits.size():
		if judged.has(k):
			continue
		var why := literal_door(lits[k], file)
		if why != "":
			out.append("строка %d: дверь: «%s» — %s" % [at[k], lits[k], why])
	var lines := RegEx.create_from_string("\\x01\\d+\\x02").sub(code, " ", true).split("\n")
	# load, взятый как значение: дальше вызов через Callable, и путь сторожу не виден
	var lv := RegEx.create_from_string(LOAD_VALUE)
	for n in lines.size():
		if lv.search(lines[n]) != null:
			out.append("строка %d: дверь: load как значение (var l := load; l.call(путь)) — путь не виден" % (n + 1))
	# генератор: зерно — следующей строкой кода, иначе зерно из часов
	var rl := RegEx.create_from_string(RNG_LINE)
	var rn := RegEx.create_from_string(RNG_NEW)
	for n in lines.size():
		if rn.search(lines[n]) == null:
			continue
		var m := rl.search(lines[n])
		var nxt := n + 1
		while nxt < lines.size() and lines[nxt].strip_edges() == "":
			nxt += 1
		var seeded := m != null and nxt < lines.size() and RegEx.create_from_string("^\\s*" + m.get_string(1).replace(".", "\\.") + "\\.(seed|state)\\s*=").search(lines[nxt]) != null
		if not seeded:
			out.append("строка %d: генератор без зерна — RandomNumberGenerator.new() и сразу следующей строкой X.seed = …; случайное — только rng и fx_rng боя" % (n + 1))
	for pat: Array in BANNED:
		var re := RegEx.create_from_string(str(pat[0]))
		for n in lines.size():
			var m := re.search(lines[n])
			if m != null:
				out.append("строка %d: «%s» — %s" % [n + 1, m.get_string(), str(pat[1])])
	var word := RegEx.create_from_string("\\b[A-Z][A-Za-z0-9_]*\\b")
	for n in lines.size():
		for m in word.search_all(lines[n]):
			var w := m.get_string()
			var why := why_banned(w, foreign)
			if why != "":
				out.append("строка %d: «%s» — %s" % [n + 1, w, why])
	return out


## Все файлы папки (со вложенными); only_gd — только скрипты.
static func sim_files(dir: String, only_gd: bool = true) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or not only_gd:
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(sim_files(dir.path_join(d), only_gd))
	return out


## Файлы, которым в sim/ не место: модель — только скрипты (.gd и их .uid). Сцена
## или .tres рядом с моделью грузились бы preload'ом «из sim/» и давали узел.
static func not_scripts(files: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for f in files:
		if not (f.ends_with(".gd") or f.ends_with(".gd.uid")):
			out.append(f)
	return out


func test_sim_is_pure() -> void:
	var files := sim_files("res://sim")
	ok(files.size() >= 1, "в sim/ есть файлы: %d" % files.size())
	var stray := not_scripts(sim_files("res://sim", false))
	ok(stray.is_empty(), "в sim/ только скрипты: %s" % ", ".join(stray))
	ok(not_scripts(PackedStringArray(["res://sim/defs.gd", "res://sim/defs.gd.uid", "res://sim/ship.tscn", "res://sim/n.tres"])).size() == 2, "откат: сцена и .tres в sim/ замечены")
	var foreign := foreign_classes()
	for f in files:
		var v := violations(FileAccess.get_file_as_string(f), foreign, f)
		ok(v.is_empty(), "%s: %s" % [f, "; ".join(v)])


## Сколько дверей (путей в чужое) нашлось — а не любых нарушений: строка
## «var c: Script = load(…)» краснела бы и словом Script, и тогда откат двери
## был бы зелёным при сломанном поиске путей.
static func doors(v: PackedStringArray) -> int:
	var n := 0
	for s in v:
		if s.contains(": дверь: "):
			n += 1
	return n


func test_rollback_dirty_text_is_caught() -> void:
	# откат: каждое запрещённое обязано краснеть, пояснения, строки и своё — нет
	var dirty := {
		"extends Node": "узел",
		"var a := Area3D.new()": "узел не из списка — ClassDB",
		"var t := Timer.new()": "узел-таймер",
		"var m := MeshInstance3D.new()": "узел картинки",
		"var p: PackedScene": "сцена",
		"var mat := StandardMaterial3D.new()": "материал",
		"extends Resource": "ресурс",
		"var t := Time.get_ticks_msec()": "время",
		"	var x := randf()": "случайность",
		"	get_tree().quit()": "дерево",
		"	var tw := Tween.new()": "анимация",
		"signal hit(who)": "сигнал",
		"	ship.died.connect(_on_died)": "подписка на сигнал",
		"	var k := Input.is_key_pressed(KEY_H)": "ввод",
		"	var w := ProjectSettings.get_setting(\"x\")": "настройки",
		"	WorkerThreadPool.add_task(f)": "потоки движка",
		"	await step()": "ожидание",
		"	var o := str_to_var(\"Object(Node3D,\\\"name\\\":\\\"x\\\")\")": "узел строкой в обход ClassDB",
		"	var o := dict_to_inst(d)": "объект из словаря с путём",
		"	var o := instance_from_id(id)": "объект по номеру",
		"	var o := JSON.to_native(d, true)": "объекты из JSON",
		# хвосты G0, найденные к G1 (на копии теста без правки — все зелёные, проверено)
		"	var f := str_to_var": "str_to_var как значение (f.call(…))",
		"	var r := randf": "randf как значение",
		"	var x := r.call() if r != null else randi_range": "randi_range как значение",
		"	randomize()": "зерно из часов",
		"	rng.randomize()": "зерно генератора из часов",
		"	var g := RandomNumberGenerator.new()": "генератор без зерна",
		"	var g := RandomNumberGenerator.new()\n	var k := 3\n	g.seed = 5": "зерно не следующей строкой",
		"	rng = RandomNumberGenerator.new()\n	fx.seed = 5": "зерно чужому генератору",
		"	var a := rand_from_seed(7)": "своя случайность мимо rng боя",
		"	var e := Expression.new()": "выражение строкой — load и str_to_var по имени",
		# замечание проверяющего к G1: общий генератор движка мимо rng боя и порядок по
		# номеру объекта (на копии теста без правки — все зелёные, 0 нарушений, проверено)
		"	ships.shuffle()": "перемешать общим генератором движка",
		"	var s: Ship = ships.pick_random()": "выбрать общим генератором движка",
		"	var t = targets . pick_random ()": "pick_random с пробелами",
		"	var id := s.get_instance_id()": "номер объекта",
		"	list.sort_custom(func(a: Ship, b: Ship) -> bool: return a.get_instance_id() < b.get_instance_id())": "порядок по номеру объекта",
		"	var h := hash(s)": "hash объекта — адрес в памяти",
		"	var c := Crypto.new()": "случайность ОС",
	}
	for line: String in dirty:
		ok(violations(line).size() > 0, "грязная строка поймана (%s): %s" % [dirty[line], line])
	# двери в чужие слои: ловиться обязаны ИМЕННО как дверь (см. doors)
	var door_lines := {
		"const V := preload(\"res://view/space_stub.gd\")": "дверь в view/",
		"const Fps := preload('res://ui/fps_counter.gd')": "дверь в ui/",
		"	var c: Script = load(\"res://input/controls.gd\")": "дверь в input/",
		"	var s := ResourceLoader.load(\"res://audio/sound.gd\")": "дверь в audio/ через ResourceLoader",
		"extends \"res://view/space_stub.gd\"": "наследник вида",
		"const U := preload(\"uid://b3k2x\")": "uid",
		"const H := preload(\"res://tests/hooks.gd\")": "дверь в tests/",
		"const M := preload(\"res://main.gd\")": "дверь в главную сцену",
		"const S := preload(\"res://sim/ship.tscn\")": "сцена «из sim/» — узел через instantiate()",
		# замечание проверяющего к доработке G0a: прежний тест (префикс res://view/)
		# эти четыре пропускал — Godot их принимает, и модель становилась узлом вида
		"const V := preload(\"../view/space_stub.gd\")": "относительный путь",
		"const Fps = preload(\"./../ui/fps_counter.gd\")": "относительный через ./..",
		"extends \"../view/space_stub.gd\"": "наследник вида относительным путём",
		"const U := preload(\"res://sim/../ui/fps_counter.gd\")": "res://sim/.. в ui/",
		"const B := preload(\"..\\\\view\\\\space_stub.gd\")": "обратные косые (Godot их принимает)",
		"const P := \"res://ui/fps_counter.gd\"": "путь константой (дальше load(P))",
		"	return load(P)": "load не строкой",
		"const X := preload(P)": "preload константы (Godot 4.7 принимает)",
		"	var s := load(\"res://\" + name)": "путь склейкой",
		"const P := \"\"\"res://ui/fps_counter.gd\"\"\"": "тройные кавычки",
		"const P := \"res://\\u0076iew/space_stub.gd\"": "\\u в пути",
		"const P := \"uid://b3k2x\"": "uid строкой",
		"var s := \"Engine.stop() и res://view/x.gd в строке\"": "путь в чужой слой даже в тексте",
		"const V := preload(\n\t\"../view/space_stub.gd\"\n)": "preload на трёх строках",
		# хвосты G0 (замечание к G0): у load() относительный путь — от res://, а не от
		# папки файла; прежний тест разворачивал его как у preload и пропускал
		"	var s := load(\"view/space_stub.gd\")": "load(\"view/…\") — это res://view",
		"	var s := load(\"./ui/fps_counter.gd\")": "load(\"./ui/…\") — это res://ui",
		"	var s := ResourceLoader.load(\"ui\\\\fps_counter.gd\")": "ResourceLoader.load с обратной косой",
		"	var l := load": "load как значение",
		"	var c: Callable = load": "load как значение с типом",
		"const P := \"view/space_stub.gd\"": "строка-путь в view/ без ./ (load(P) уведёт туда)",
		"const P := \"main.gd\"": "строка-путь к скрипту вне sim/ (load(P) — res://main.gd)",
	}
	for line: String in door_lines:
		ok(doors(violations(line)) > 0, "дверь поймана (%s): %s" % [door_lines[line], line])
	# из вложенной папки «..» — это ещё sim/, а «../..» — уже нет
	ok(doors(violations("const D := preload(\"../defs.gd\")", {}, "res://sim/ai/brain.gd")) == 0, "sim/ai → ../defs.gd — своё")
	ok(doors(violations("const V := preload(\"../../view/space_stub.gd\")", {}, "res://sim/ai/brain.gd")) > 0, "sim/ai → ../../view — дверь")
	# константа-путь и load(P) — обе строки, и номера строк верны после многострочной строки
	var two := violations("\n".join(["var doc := \"\"\"первая", "вторая\"\"\"", "const P := \"../ui/fps_counter.gd\"", "func f() -> Object:", "	return load(P)"]))
	var two_s := "; ".join(two)
	ok(doors(two) == 2 and two_s.contains("строка 3: дверь: «../ui") and two_s.contains("строка 5: дверь: загрузка"), "константа и load(P): две двери, строки 3 и 5: %s" % two_s)
	# глобальный класс вида (class_name SpaceView в view/) — тоже дверь
	ok(violations("var s := SpaceView.new()", {"SpaceView": "res://view/space_view.gd"}).size() > 0, "грязная строка поймана (class_name из view/)")
	var clean := "\n".join([
		"# Node, Time.now, randf() и preload(\"res://view/x.gd\") в пояснении — не нарушение",
		"const Defs := preload(\"res://sim/defs.gd\")",
		"const S := preload(\"./ships.gd\")",
		"const W := preload(\"../sim/weapons.gd\")",
		"const B := preload(",
		"	\"res://sim/battle.gd\"",
		")",
		"extends \"res://sim/base.gd\"",
		"const SPACE_PATH := \"res://data/space_data.json\"",
		"var d := Defs.load_files(SPACE_PATH, DOCTRINE_PATH)",
		"	d._load(a, b, {}, \"x.json\", \"y.json\")",
		"var doc := \"\"\"",
		"Node, Timer и await в длинной строке",
		"\"\"\"",
		"var s := \"Engine.stop() и Node в строке\"",
		"var msg := \"нет «%s» в doctrine.json, см. ../data\" % k",
		"var r := rng.randf()",
		"var rng := RandomNumberGenerator.new()",
		"rng.seed = battle_seed",
		"	fx_rng = RandomNumberGenerator.new()",
		"",
		"	fx_rng.seed = battle_seed ^ 0x5bd1e995",
		"var u := rng.randi_range(0, 3)",
		"var pick: Ship = ships[rng.randi_range(0, ships.size() - 1)]",
		"var key := name.hash() ^ ftext.sha256_text().hash()",
		"var shuffled := 0",
		"var hash_len := 16",
		"const SHIP := preload(\"ship.gd\")",
		"var label := \"урон/с\"",
		"var unit := \"x.json\"",
		"var j := JSON.new()",
		"var f := FileAccess.open(p, FileAccess.READ)",
		"var hit := Geometry3D.segment_intersects_sphere(a, b, c, r)",
		"var v := Vector3.ZERO",
		"var arr: PackedFloat64Array = []",
		"var ship := ShipDef.new()",
		"var node_count := 3",
	])
	ok(violations(clean).is_empty(), "пояснения, строки, своё и rng.randf() — не нарушения: %s" % "; ".join(violations(clean)))


## Строгая типизация (архитектура, 10.2 п. 2): все unsafe_* и untyped_declaration —
## ошибки. Спрашиваем у самих настроек проекта: новое unsafe_* в следующей версии
## Godot без «2» тоже покраснеет (так был пропущен unsafe_void_return).
func test_strict_typing_settings() -> void:
	var seen := 0
	for p: Dictionary in ProjectSettings.get_property_list():
		var n: String = p["name"]
		if not n.begins_with("debug/gdscript/warnings/"):
			continue
		var key := n.get_file()
		if key.begins_with("unsafe_") or key == "untyped_declaration":
			seen += 1
			var level: int = ProjectSettings.get_setting(n)
			eq(level, 2, "%s — ошибка (2)" % key)
	ok(seen >= 6, "настроек unsafe_* и untyped_declaration: %d (в 4.7.2 их шесть)" % seen)
