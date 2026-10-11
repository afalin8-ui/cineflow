# sim/squad.gd — звено и ангар (space.js:375, 430 launchSquadron · часть 04, 2.1–2.2).
# Поля; логика — sim/hangar.gd и sim/air.gd.
#
# - У звена НЕТ прочности (C14; 04, ловушка 1): прочность — у машин. Звено — не Body,
#   поэтому урон «по звену» отбрасывается по устройству, а приказ на звено — это
#   приказ бить его МАШИНЫ (sim/hangar.gd → live_craft).
# - Звено — данные, а не узел сцены (04, 5.2): у него нет модели, только центр машин,
#   выбор и (с G7) метка.
# - Ангар — отдельной частью корабля (04, 7.4): места, постройка за выбитое, поднятые.
#   Инвариант C99: free + rebuild + (живые звенья с home = этот) ≤ bays в КАЖДЫЙ миг.
extends RefCounted

const Defs := preload("res://sim/defs.gd")
const Craft := preload("res://sim/craft.gd")


## Ангар носителя или станции (space.js:375): bays — мест, free — можно поднять сейчас,
## rebuild — моменты игрового времени, когда вернётся место за ВЫБИТОЕ звено (26 с),
## launched — звенья, числящиеся за носителем (поднятые им и приписанные rehome).
class Hangar:
	var bays := 0
	var free := 0
	var rebuild := PackedFloat64Array()
	var launched: Array[RefCounted] = []


var uid: int
var side: int
var clan: StringName             # клан носителя, поднявшего звено (машины — его)
var role: StringName
var def: Defs.CraftDef
var home: RefCounted             # носитель (Ship), на который звено садится; null — нет
var craft: Array[Craft] = []     # живые машины звена
var size := 0                    # машин при пуске — для панели «4/5»
var dead := false
var recall := false              # «На посадку» (V) или кончились ракеты (04, 2.9)
## Приказ игрока: корабль (Ship) или чужое звено (Squad) — бить; null — сами (04, 2.13).
var target: RefCounted
var has_move := false            # приказ «идти» в точку: не снимается по прибытии (04, 2.13)
var move_to := Vector2.ZERO
var pos := Vector2.ZERO          # центр живых машин, пересчитывается каждый шаг
## ДОКТРИНА 09, 4.4: с какого фланга заходит звено бомбардировщиков, если цель на оси
## (+1 / −1 по lat). Постоянна у звена: заход не мечется с фланга на фланг.
var flank := 1.0
## Сказать ОДИН раз на звено (C8; 04, ловушка 6): ракеты кончились, садиться некуда.
var told_empty := false
var told_leave := false
var told_no_home := false
var launched_at := 0.0
## Итоги: урон машин звена (по всему, что принимает урон) и добитые КОРАБЛИ (04, 2.11).
var dealt := 0.0
var kills := 0


func unlink() -> void:
	home = null
	target = null
	for c in craft:
		c.unlink()
	craft.clear()
