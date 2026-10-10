# Чистота модели (архитектура, 1 и 10.2 п. 1): sim/ не знает о view/, ui/,
# input/, audio/ (ни preload, ни load, ни extends, ни их глобальных классов);
# в sim/ нет узлов и ресурсов картинки (спрашиваем ClassDB, а не список имён),
# настоящего времени, движка, ввода, случайности без генератора боя и сигналов.
# Двери ищем в тексте без комментариев (строки-пути нужны), остальное — в тексте
# без комментариев и строк: слово в пояснении или в тексте ошибки — не нарушение.
extends "res://tests/case.gd"

## Двери в чужие слои: путь в preload/load/extends. uid:// — тоже: по нему не видно,
## куда он ведёт. Ищется по тексту СО строками (путь живёт в строке).
const DOORS := [
	["\\b(?:pre)?load\\s*\\(\\s*[\"']res://(?:(?:view|ui|input|audio|tests|tools)/|main\\.)", "модель не знает о view/, ui/, input/, audio/ (и о tests/, tools/, main) — двери односторонние"],
	["\\bextends\\s+[\"']res://(?!sim/)", "модель наследует только своё (sim/)"],
	["\\b(?:pre)?load\\s*\\(\\s*[\"']uid://", "путь по uid в модели — не видно, в какой слой он ведёт"],
]

## Запрещённое по образцу (текст без строк): образец → почему.
const BANNED := [
	["get_tree\\s*\\(", "дерево сцены"],
	["(?<![.\\w])(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\s*\\(", "случайность — только battle.rng"],
	["\\bsignal\\b|\\bSignal\\b|\\bemit_signal\\b|\\.emit\\s*\\(|\\.connect\\s*\\(", "сигналов из шага нет — события шага списком"],
	["\\bawait\\b", "шаг модели не ждёт"],
]

## Классы движка, которые модели НЕ узлы и не ресурсы, но всё равно чужие.
const EXTRA_BANNED := {
	"SceneTree": "дерево сцены", "MainLoop": "дерево сцены", "SceneTreeTimer": "дерево сцены",
	"Tween": "анимация вида", "Thread": "потоки — отдельным решением с замером",
}
## Ресурсы, без которых загрузчику не обойтись: JSON — разбор с номером строки.
const ALLOWED_RESOURCES := ["JSON"]
## Синглтоны движка, которые модели можно: чистая геометрия и кодировки.
const ALLOWED_SINGLETONS := ["Geometry2D", "Geometry3D", "Marshalls"]


## Текст скрипта без комментариев; keep_strings = false — и без строковых литералов.
static func code_only(text: String, keep_strings: bool = false) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var buf := ""
		var quote := ""
		var i := 0
		while i < line.length():
			var ch := line[i]
			if quote != "":
				if ch == "\\":
					if keep_strings:
						buf += line.substr(i, 2)
					i += 2
					continue
				if ch == quote:
					quote = ""
				if keep_strings:
					buf += ch
				i += 1
				continue
			if ch == "#":
				break
			if ch == "\"" or ch == "'":
				quote = ch
				buf += ch if keep_strings else " "
				i += 1
				continue
			buf += ch
			i += 1
		out.append(buf)
	return "\n".join(out)


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


## Нарушения в одном тексте: «строка N: слово — почему».
static func violations(text: String, foreign: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	var with_strings := code_only(text, true).split("\n")
	for pat: Array in DOORS:
		var re := RegEx.create_from_string(str(pat[0]))
		for n in with_strings.size():
			var m := re.search(with_strings[n])
			if m != null:
				out.append("строка %d: «%s» — %s" % [n + 1, m.get_string(), str(pat[1])])
	var lines := code_only(text).split("\n")
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


static func sim_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(sim_files(dir.path_join(d)))
	return out


func test_sim_is_pure() -> void:
	var files := sim_files("res://sim")
	ok(files.size() >= 1, "в sim/ есть файлы: %d" % files.size())
	var foreign := foreign_classes()
	for f in files:
		var v := violations(FileAccess.get_file_as_string(f), foreign)
		ok(v.is_empty(), "%s: %s" % [f, "; ".join(v)])


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
		"const V := preload(\"res://view/space_stub.gd\")": "дверь в view/",
		"const Fps := preload('res://ui/fps_counter.gd')": "дверь в ui/",
		"	var c: Script = load(\"res://input/controls.gd\")": "дверь в input/",
		"	var s := ResourceLoader.load(\"res://audio/sound.gd\")": "дверь в audio/ через ResourceLoader",
		"extends \"res://view/space_stub.gd\"": "наследник вида",
		"const U := preload(\"uid://b3k2x\")": "uid",
		"const H := preload(\"res://tests/hooks.gd\")": "дверь в tests/",
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
	}
	for line: String in dirty:
		ok(violations(line).size() > 0, "грязная строка поймана (%s): %s" % [dirty[line], line])
	# глобальный класс вида (class_name SpaceView в view/) — тоже дверь
	ok(violations("var s := SpaceView.new()", {"SpaceView": "res://view/space_view.gd"}).size() > 0, "грязная строка поймана (class_name из view/)")
	var clean := "\n".join([
		"# Node, Time.now, randf() и preload(\"res://view/x.gd\") в пояснении — не нарушение",
		"const Defs := preload(\"res://sim/defs.gd\")",
		"extends \"res://sim/base.gd\"",
		"var s := \"Engine.stop() и res://view/x.gd в строке\"",
		"var r := rng.randf()",
		"var rng := RandomNumberGenerator.new()",
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
