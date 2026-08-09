extends Area2D
## 投射物：由 spell_caster.setup() 注入速度/射程/伤害/元素/修饰参数。
## 命中敌人 → enemy.take_damage(dmg, element, is_crit) + EventBus 事件。
## 支持 homing / pierce / bounce / orbit / delay / explode / 毒雾 / 冰锥 / 暴击。

const ARENA_MIN := Vector2(16.0, 16.0)
const ARENA_MAX := Vector2(1264.0, 704.0)
const CONTACT_RADIUS := 9.0
const ORBIT_RADIUS := 28.0
const ORBIT_SPEED := 4.5
const STATUS_TEXTURES := {
	"fire": "res://assets/sprites/gen/proj_fireball.png",
	"ice": "res://assets/sprites/gen/proj_ice.png",
	"lightning": "res://assets/sprites/gen/proj_lightning.png",
	"poison": "res://assets/sprites/gen/proj_poison.png",
	"blade": "res://assets/sprites/gen/proj_blade.png",
}

var _spawn_pos := Vector2.ZERO
var _dir := Vector2.RIGHT
var _speed := 0.0
var _range := 360.0
var _damage := 0.0
var _element := "fire"
var _aoe := 0.0
var _mods: Dictionary = {}
var _travelled := 0.0
var _pierce_left := 0
var _bounce_left := 0
var _delay_left := 0.0
var _instant := false
var _orbit_mode := false
var _orbit_center := Vector2.ZERO
var _orbit_angle := 0.0
var _orbit_life := 2.0
var _player_ref: Node2D = null
var _hit_enemies := {}  # instance_id -> true：同一投射物对同一敌人只结算一次
var _impacted := false


func setup(p: Dictionary) -> void:
	_spawn_pos = p.get("position", Vector2.ZERO)
	global_position = _spawn_pos
	var d: Vector2 = p.get("direction", Vector2.RIGHT)
	_dir = d.normalized()
	_speed = float(p.get("speed", 0.0))
	_range = float(p.get("range", 360.0))
	_damage = float(p.get("damage", 0.0))
	_element = str(p.get("element", "fire"))
	_aoe = float(p.get("aoe", 0.0))
	_mods = p.get("mods", {})
	_pierce_left = int(_mods.get("pierce", 0))
	_bounce_left = int(_mods.get("bounce", 0))
	_delay_left = float(_mods.get("delay", 0.0))
	_instant = _speed <= 0.0
	_orbit_mode = bool(_mods.get("orbit", false))
	_orbit_life = maxf(float(_mods.get("orbit", 2.0)), 0.5)


func _ready() -> void:
	var spr := $Sprite2D as Sprite2D
	if spr != null:
		spr.texture = load(STATUS_TEXTURES.get(_element, STATUS_TEXTURES["fire"]))
	_player_ref = get_tree().get_first_node_in_group("player")
	if _orbit_mode:
		_orbit_angle = _dir.angle()
		_orbit_center = _player_ref.global_position if _player_ref != null else _spawn_pos


func _physics_process(delta: float) -> void:
	if _impacted:
		return
	if _delay_left > 0.0:
		_delay_left -= delta
		return
	if _orbit_mode:
		_orbit_step(delta)
		return
	if _instant:
		global_position = _spawn_pos + _dir * _range
		_explode_at(global_position)
		return
	_move_step(delta)


func _move_step(delta: float) -> void:
	if _mods.get("homing", false):
		var target := _nearest_enemy()
		if target != null:
			var to: Vector2 = (target.global_position - global_position).normalized()
			_dir = _dir.lerp(to, minf(6.0 * delta, 1.0)).normalized()
	position += _dir * _speed * delta
	_travelled += _speed * delta
	if _bounce_left > 0:
		# 弹射：触墙（Clamp 边界）或射程尽头反弹，弹数耗尽则消失。
		var clamped := position.clamp(ARENA_MIN, ARENA_MAX)
		if clamped != position or _travelled >= _range:
			_bounce_at(clamped)
			return
	else:
		position = position.clamp(ARENA_MIN, ARENA_MAX)
		if _travelled >= _range:
			queue_free()
			return
	_scan_contact()


func _scan_contact() -> void:
	for e in _enemies_in_radius(global_position, CONTACT_RADIUS):
		var id: int = e.get_instance_id()
		if _hit_enemies.has(id):
			continue
		_hit_enemies[id] = true
		if _aoe > 0.0:
			_explode_at(global_position)
			return
		_hit_enemy(e)
		if _pierce_left > 0:
			_pierce_left -= 1
		else:
			queue_free()
			return


## 爆炸结算：范围内敌人全部受击，随后消失。
func _explode_at(pos: Vector2) -> void:
	_impacted = true
	EventBus.fx_explosion.emit(pos, _element)
	for e in _enemies_in_radius(pos, maxf(_aoe, 1.0)):
		var id: int = e.get_instance_id()
		if _hit_enemies.has(id):
			continue
		_hit_enemies[id] = true
		_hit_enemy(e)
	queue_free()


func _bounce_at(clamped: Vector2) -> void:
	_bounce_left -= 1
	var before := position
	position = clamped
	_travelled = 0.0
	var axis := Vector2.ZERO
	if not is_equal_approx(clamped.x, before.x):
		axis.x = 1.0
	if not is_equal_approx(clamped.y, before.y):
		axis.y = 1.0
	_dir = _dir.reflect(axis.normalized()) if axis != Vector2.ZERO else -_dir


func _orbit_step(delta: float) -> void:
	_orbit_life -= delta
	if _orbit_life <= 0.0:
		queue_free()
		return
	if _player_ref != null and is_instance_valid(_player_ref):
		_orbit_center = _player_ref.global_position
	_orbit_angle += ORBIT_SPEED * delta
	global_position = _orbit_center + Vector2.from_angle(_orbit_angle) * ORBIT_RADIUS
	for e in _enemies_in_radius(global_position, CONTACT_RADIUS):
		var id: int = e.get_instance_id()
		if _hit_enemies.has(id):
			continue
		_hit_enemies[id] = true
		_hit_enemy(e)


func _hit_enemy(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	var crit: bool = randf() < float(GameState.run.get("crit_chance", 0.03))
	var mult: float = GameState.run.get("crit_dmg_bonus", 1.5) if crit else 1.0
	var final_dmg := roundi(_damage * mult)
	if enemy.has_method("take_damage"):
		enemy.take_damage(final_dmg, _element, crit)
	EventBus.damage_dealt.emit(final_dmg, enemy.global_position, crit)
	EventBus.fx_hit_flash.emit(enemy)
	if _element == "poison":
		EventBus.apply_status.emit(enemy, "poison", 1)
	elif _element == "ice":
		EventBus.apply_status.emit(enemy, "freeze", 1)


func _nearest_enemy() -> Node:
	var best: Node = null
	var best_d := INF
	for e in _all_enemies():
		if not is_instance_valid(e):
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _enemies_in_radius(center: Vector2, radius: float) -> Array:
	var result: Array = []
	for e in _all_enemies():
		if not is_instance_valid(e):
			continue
		# 命中判定按敌人实际体型放大（大体积 Boss 的碰撞圈远大于中心 9px）
		var hit_r: float = radius + e.scale.x * 8.0
		var d: float = center.distance_to(e.global_position)
		if d <= hit_r:
			result.append(e)
	return result


## 敌人扫描：优先 group "enemy"；组缺失时回退全树找 take_damage 节点。
func _all_enemies() -> Array:
	var grouped := get_tree().get_nodes_in_group("enemy")
	if not grouped.is_empty():
		return grouped
	var scene := get_tree().current_scene
	if scene == null:
		return []
	var found: Array = []
	for child in scene.get_children():
		_collect_enemies(child, found)
	return found


func _collect_enemies(node: Node, found: Array) -> void:
	if node != self and node.has_method("take_damage"):
		found.append(node)
	for child in node.get_children():
		_collect_enemies(child, found)
