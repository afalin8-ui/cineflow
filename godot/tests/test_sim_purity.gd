# Чистота модели (архитектура, 1 и 10.2 п. 1): в sim/ нет узлов, настоящего
# времени, движка, ввода, случайности без генератора боя и сигналов наружу.
# Проверка — грепом по тексту без комментариев и строк.
extends "res://tests/case.gd"

## Запрещённое в sim/: образец → почему.
const BANNED := [
	["\\b(Node|Node2D|Node3D|Control|CanvasItem|CanvasLayer|SceneTree|Viewport|Window)\\b", "узлы и дерево сцены — дело view/ и ui/"],
	["get_tree\\s*\\(", "дерево сцены"],
	["\\b(Time|Engine|Input|OS|DisplayServer|RenderingServer|PhysicsServer3D)\\s*\\.", "настоящее время, движок, ввод, ОС — модель живёт на battle.time"],
	["(?<![.\\w])(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\s*\\(", "случайность — только battle.rng"],
	["\\bsignal\\b|\\bemit_signal\\b|\\.emit\\s*\\(", "сигналов из шага нет — события шага списком"],
	["\\bawait\\b", "шаг модели не ждёт"],
]


## Текст скрипта без комментариев и строковых литералов: запрещённое слово
## в пояснении или в тексте ошибки — не нарушение.
static func code_only(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var buf := ""
		var quote := ""
		var i := 0
		while i < line.length():
			var ch := line[i]
			if quote != "":
				if ch == "\\":
					i += 2
					continue
				if ch == quote:
					quote = ""
				i += 1
				continue
			if ch == "#":
				break
			if ch == "\"" or ch == "'":
				quote = ch
				buf += " "
				i += 1
				continue
			buf += ch
			i += 1
		out.append(buf)
	return "\n".join(out)


## Нарушения в одном тексте: «строка N: слово — почему».
static func violations(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := code_only(text).split("\n")
	for pat: Array in BANNED:
		var re := RegEx.create_from_string(str(pat[0]))
		for n in lines.size():
			var m := re.search(lines[n])
			if m != null:
				out.append("строка %d: «%s» — %s" % [n + 1, m.get_string(), str(pat[1])])
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
	for f in files:
		var v := violations(FileAccess.get_file_as_string(f))
		ok(v.is_empty(), "%s: %s" % [f, "; ".join(v)])


func test_rollback_dirty_text_is_caught() -> void:
	# откат: каждое запрещённое обязано краснеть, пояснения и строки — нет
	var dirty := {
		"extends Node": "узлы",
		"var t := Time.get_ticks_msec()": "время",
		"	var x := randf()": "случайность",
		"	get_tree().quit()": "дерево",
		"signal hit(who)": "сигнал",
		"	var k := Input.is_key_pressed(KEY_H)": "ввод",
		"	await step()": "ожидание",
	}
	for line: String in dirty:
		ok(violations(line).size() > 0, "грязная строка поймана (%s): %s" % [dirty[line], line])
	var clean := "# Node, Time.now и randf() в пояснении — не нарушение\nvar s := \"Engine.stop() в строке\"\nvar r := rng.randf()\nvar node_count := 3"
	ok(violations(clean).is_empty(), "пояснения, строки и rng.randf() — не нарушения: %s" % "; ".join(violations(clean)))
