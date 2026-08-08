extends Node
## 法术施放器：每帧按 GameState.run.grid 槽位顺序检查冷却，就绪即施放。
## 冷却 = core.cooldown × shell.mods.cooldown_mult × 法杖充能系数（item_value 曲线）。
## 施放方向 = InputRouter.aim_vector；鼠标与玩家距离 > 20px 时改瞄鼠标。

const PROJECTILE_SCENE := preload("res://scenes/game/projectile.tscn")
const SUMMON_SCRIPT := preload("res://scripts/combat/summon.gd")
const WAND_CHARGE_CURVE := {"curve": {"type": "multiplicative", "base": 0.9, "cap": 0.5}}
const MIN_CD := 0.05

var _cds: Array[float] = []
var _mouse_used := false


func _ready() -> void:
	EventBus.spell_arranged.connect(_on_grid_changed)


func _physics_process(delta: float) -> void:
	var player := _player()
	if player == null:
		return
	var grid: Array = GameState.run.get("grid", [])
	_sync_cds(grid.size())
	for i in grid.size():
		if _cds[i] > 0.0:
			_cds[i] -= delta
			continue
		var slot: Dictionary = grid[i]
		var core := _find_core(str(slot.get("core", "")))
		if core.is_empty():
			continue
		var shell := _find_shell(str(slot.get("shell", "")))
		_cast(player, core, shell.get("mods", {}))
		_cds[i] = _cooldown_of(core, shell.get("mods", {}))


func _player() -> Node2D:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null:
		return p as Node2D
	var parent := get_parent()
	if parent is Node2D:
		return parent as Node2D
	return null


func _sync_cds(size: int) -> void:
	while _cds.size() < size:
		_cds.append(0.0)  # 新槽位 0 → 就绪即施放
	while _cds.size() > size:
		_cds.pop_back()


func _on_grid_changed(_grid: Array) -> void:
	_sync_cds(_grid.size())


func _find_core(core_id: String) -> Dictionary:
	for c in GameState.tables.get("spells", {}).get("cores", []):
		if str(c.get("id", "")) == core_id:
			return c
	return {}


func _find_shell(shell_id: String) -> Dictionary:
	for s in GameState.tables.get("spells", {}).get("shells", []):
		if str(s.get("id", "")) == shell_id:
			return s
	return {}


func _cooldown_of(core: Dictionary, mods: Dictionary) -> float:
	var cd: float = float(core.get("cooldown", 1.0)) * float(mods.get("cooldown_mult", 1.0))
	var wand: float = GameState.item_value(WAND_CHARGE_CURVE, GameState.total_stacks("wand_charge"))
	return maxf(cd * wand, MIN_CD)


func _cast(player: Node2D, core: Dictionary, mods: Dictionary) -> void:
	var element: String = str(core.get("element", "fire"))
	var aim := _aim_dir(player)
	EventBus.fx_explosion.emit(player.global_position + aim * 10.0, element)
	if core.has("summon") or str(core.get("id", "")) == "summon_bat":
		_spawn_summon(player, core, mods)
		return
	var dmg := _spell_damage(core, mods, element)
	var aoe: float = float(core.get("aoe", 0.0)) * float(mods.get("aoe_mult", 1.0)) * (1.0 + GameState.aggregate_bonus("area"))
	var speed: float = float(core.get("speed", 0.0)) * float(mods.get("speed_mult", 1.0))
	var shots: int = maxi(int(mods.get("shots", 1)), 1)
	var spread: float = float(mods.get("spread_angle", 0.0))
	var base_angle := aim.angle()
	for i in shots:
		var dir := aim
		if shots > 1 and spread > 0.0:
			var t := float(i) / float(shots - 1) - 0.5
			dir = Vector2.from_angle(base_angle + deg_to_rad(spread) * t)
		_spawn_projectile(player, dir, core, mods, dmg, aoe, speed)


## 伤害 = core.base_damage × mods.damage_mult × (1+atk 加成) × (1+元素加成)。
func _spell_damage(core: Dictionary, mods: Dictionary, element: String) -> float:
	var dmg: float = float(core.get("base_damage", 0.0)) * float(mods.get("damage_mult", 1.0))
	dmg *= 1.0 + GameState.aggregate_bonus("atk")
	dmg *= 1.0 + GameState.aggregate_bonus(element)
	return dmg


func _spawn_projectile(player: Node2D, dir: Vector2, core: Dictionary, mods: Dictionary, dmg: float, aoe: float, speed: float) -> void:
	var proj := PROJECTILE_SCENE.instantiate()
	proj.setup({
		"position": player.global_position + dir * 12.0,
		"direction": dir,
		"speed": speed,
		"range": float(core.get("range", 360.0)),
		"damage": dmg,
		"element": str(core.get("element", "fire")),
		"aoe": aoe,
		"mods": mods,
	})
	get_tree().current_scene.add_child(proj)


func _spawn_summon(player: Node2D, core: Dictionary, mods: Dictionary) -> void:
	var summon := SUMMON_SCRIPT.new()
	summon.setup(player, _spell_damage(core, mods, "summon"), str(core.get("element", "summon")))
	get_tree().current_scene.add_child(summon)
	summon.global_position = player.global_position + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))


func _aim_dir(player: Node2D) -> Vector2:
	var aim: Vector2 = InputRouter.aim_vector
	var mouse := player.get_global_mouse_position()
	if _mouse_used and (mouse - player.global_position).length() > 20.0:
		return (mouse - player.global_position).normalized()
	if aim.length_squared() > 0.0:
		return aim.normalized()
	return Vector2.RIGHT

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_used = true
