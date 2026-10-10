extends RefCounted
## Сущности боя — те же поля, что у объектов space.js (camelCase → snake_case).
## Типизированные классы, а не словари: опечатка в имени поля — ошибка
## разбора, а не молча заведённый новый ключ (как в JS и в Dictionary).

class Ent:
	var uid: int = 0
	var kind: String = ""
	var side: String = ""
	var faction: String = ""
	var cls: String = ""
	var pos: Vector3 = Vector3.ZERO
	var vel: Vector3 = Vector3.ZERO
	var dir: Vector3 = Vector3(0, 0, -1)
	var hp: float = 0.0
	var max_hp: float = 0.0
	var armor: float = 0.0
	var radius: float = 8.0
	var dead: bool = false

class Gun:
	var def: Dictionary
	var idx: int = 0
	var cd: float = 0.0
	var role: String = "main"     # доктрина 1.1: main / sec / missile / light
	var charge_fx: float = 0.0

class Ship extends Ent:
	var def: Dictionary
	var name: String = ""
	var q: Quaternion = Quaternion.IDENTITY
	var len: float = 0.0
	var hull: float = 0.0
	var move_to = null            # Vector3 или null — как в JS
	var amove = null
	var target: Ent = null
	var forced: Ent = null
	var retarget: float = 0.0
	var stance: String = "guard"
	var anchor: Vector3 = Vector3.ZERO
	var guard_of: Ship = null
	var guard_off: Vector3 = Vector3.ZERO
	var group_speed: float = 0.0
	var arrive_t: float = 0.0
	var dealt: float = 0.0
	var kills: int = 0
	var guns: Array[Gun] = []
	var sec: Array[Gun] = []        # доктрина: батарея — отдельный список, не guns[0]
	var sec_target: Ship = null
	var main_target: Ship = null    # доктрина: своя цель главного калибра
	var pd_cd: PackedFloat32Array = PackedFloat32Array()
	var hangar: Dictionary = {}
	var station: bool = false
	var thrust_now: float = 0.0
	var stealth: bool = false
	var reveal_until: float = 0.0
	var exposed: bool = false
	var seen_pos: Vector3 = Vector3.ZERO
	var seen_at: float = 0.0
	var hyper: Dictionary = {}
	var fled: bool = false
	var ecm: Dictionary = {}
	var jam = null                  # профиль помех (Dictionary) или null
	var jam_shot: Ship = null
	var drift: bool = false
	var ion_until: float = 0.0
	var ionized: bool = false
	var exit_until: float = 0.0
	var fired_at: float = 0.0
	# доктрина: отход
	var backing: bool = false
	var futile: Dictionary = {}     # uid врага -> до какого времени он «не повод»
	var futile_clock: float = 0.0
	var futile_d0: float = 0.0
	var futile_uid: int = -1

class Craft extends Ent:
	var def: Dictionary
	var role: String = ""
	var squad = null
	var q: Quaternion = Quaternion.IDENTITY
	var cd: float = 0.0
	var target: Ent = null
	var phase: String = "out"
	var break_until: float = 0.0
	var slot: int = 0
	var ammo: int = 0
	var reloads: int = 0
	var reloading: float = 0.0
	var reveal_until: float = 0.0
	var exposed: bool = false
	var leaving: bool = false
	var leave_t: float = 0.0
	var ionized: bool = false

class Squad extends Ent:
	var role: String = ""
	var def: Dictionary
	var home: Ship = null
	var craft: Array = []
	var recall: bool = false
	var target: Ent = null
	var move_to = null
	var size: int = 0

class Proj extends Ent:
	var target: Ent = null
	var dmg: float = 0.0
	var weapon: String = ""
	var speed: float = 0.0
	var owner: Ent = null
	var life: float = 16.0
	var blind: bool = false
	var wobble: float = -1.0
