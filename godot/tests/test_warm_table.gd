# Прогрев «Стола» (07, ловушка 29; 08, ловушка 15; 08, 4.2 п. 3) — ярус `warm` под xvfb в обоих
# отрисовщиках: счётчики сборок конвейеров не растут после первых кадров (откат — эффекты впервые на
# 30-м кадре). Проба — отдельным процессом (tests/probe_warmup.gd): конвейер, однажды собранный,
# живёт до конца процесса. Своим ярусом с 0.12: «Стол» стал ручными моделями Плэктора, и две пробы
# (в CI по ~180 с в Forward+) вместе с остальным «Столом» (test_table_render) шли 734 с из 900.
extends "res://tests/case.gd"


static func renderer() -> String:
	return RenderingServer.get_current_rendering_method()


## Зависла — значит проба МОЛЧИТ: ни одного шага за PROBE_STALL_MS (шаг пробы — 10 кадров; в CI
## на ручных моделях это ~20 с, здесь ~4). Плюс общий предел: две пробы обязаны уложиться
## в 900 с яруса. До 0.12 «зависла» значило «не кончилась за 240 с», и проба, честно идущая
## 180 с на «Столе» ручных моделей, оказывалась на волосок от провала (прогон 41583526844).
const PROBE_STALL_MS := 120000
const PROBE_WAIT_MS := 420000


## Проба прогрева в своём процессе (tests/probe_warmup.gd): тот же отрисовщик.
func _warm_probe(mode: String) -> Dictionary:
	var out := tmp("probe_warmup_%s.json" % mode)
	DirAccess.remove_absolute(out)
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--rendering-method", renderer(),
		"-s", "res://tests/probe_warmup.gd", "--", mode, out])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if not ok(pid > 0, "проба прогрева %s запустилась" % mode):
		return {}
	var t0 := Time.get_ticks_msec()
	var last := t0
	var seen := 0
	while OS.is_process_running(pid):
		await hooks.frames(1)
		var now := Time.get_ticks_msec()
		var n := FileAccess.get_file_as_string(out + ".log").length()
		if n != seen:
			seen = n
			last = now
		if now - last > PROBE_STALL_MS or now - t0 > PROBE_WAIT_MS:
			break
	var steps := FileAccess.get_file_as_string(out + ".log").strip_edges().replace("\n", "; ")
	DirAccess.remove_absolute(out + ".log")
	if OS.is_process_running(pid):
		OS.kill(pid)                      # только свой PID, никакого pkill
		ok(false, "проба прогрева %s зависла; её ход: %s" % [mode, steps])
		return {}
	note("проба прогрева %s: %s" % [mode, steps.get_slice("; ", steps.get_slice_count("; ") - 1)])
	var j := JSON.new()
	var text := FileAccess.get_file_as_string(out)
	DirAccess.remove_absolute(out)
	if not ok(j.parse(text) == OK and typeof(j.data) == TYPE_DICTIONARY, "проба прогрева %s оставила итог: «%s»" % [mode, text]):
		return {}
	return dict(j.data)


func test_warmup_no_compilations_mid_game() -> void:
	var r := await _warm_probe("warm")
	if r.is_empty():
		return
	var before := whole(r["before"])
	var after := whole(r["after"])
	if renderer() != "forward_plus":
		# в Compatibility конвейеров Vulkan нет — счётчики сборок молчат; проверка — в Forward+
		note("%s: сборок конвейеров %d → %d (проверка — в Forward+)" % [renderer(), before, after])
		ok(true, "Compatibility: проверка прогрева не применима")
		return
	ok(before > 0, "счётчики сборок конвейеров отвечают (%d к 20-му кадру)" % before)
	eq(after, before, "после первых кадров новых сборок конвейеров нет (облёт по пути замера)")
	var rb := await _warm_probe("cold")
	if rb.is_empty():
		return
	var b2 := whole(rb["before"])
	var a2 := whole(rb["after"])
	ok(a2 > b2, "откат «эффекты впервые на 30-м кадре» краснеет: %d → %d" % [b2, a2])
	note("прогрев: как в игре %d → %d, откат %d → %d" % [before, after, b2, a2])
