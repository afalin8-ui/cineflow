# sim/vision.gd — кто кого видит (архитектура, 2.3; план G2, п. 7; часть 03, 2.6;
# часть 04, 2.19–2.20). В срезе скрытности нет (Рииза в срезе нет): sees() — «да»
# всегда. Но всё, что скрытность потом спросит, заведено уже сейчас:
# - reveal() зовётся из КАЖДОГО выстрела — главного калибра, батареи, лёгкого орудия,
#   ракетного пакета и ПВО (03, ловушка 25; 09, 9.5 п. 7);
# - seen_pos / seen_at пишутся в начале шага, до ИИ (05, ловушка 39): по ним ИИ ищет
#   скрытых (04, ловушка 27).
# Когда скрытность появится, спрашивать её — ЗДЕСЬ, а фильтр видимости вида
# (input/picking.gd → shown) — оттуда же.
extends RefCounted

const State := preload("res://sim/state.gd")
const Ship := preload("res://sim/ship.gd")


## Видит ли сторона корабль. В срезе — «да» (скрытности нет).
static func sees(_b: State, _side: int, _s: Ship) -> bool:
	return true


# space.js:1003 updateExposure (хвост: «где видели последний раз», P5)
static func update(b: State) -> void:
	for s in b.ships:
		if not s.dead:
			s.seen_pos = s.pos
			s.seen_at = b.time


# space.js:643 reveal · часть 03, 2.6: выстрел срывает маскировку на STEALTH.revealFor.
## Ставится только скрытному (как в JS); у остальных — ничего.
static func reveal(b: State, s: Ship) -> void:
	if s.stealth:
		s.reveal_until = b.time + b.defs.stealth.reveal_for
