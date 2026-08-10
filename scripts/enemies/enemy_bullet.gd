extends Area2D
## 敌方弹幕：直线飞行，命中玩家发 player_hit
## v2 扩展：homing=true 时缓慢转向玩家（弹速 120-150、转向率 3rad/s、寿命 4s）

var _dir := Vector2.RIGHT
var _speed := 180.0
var _damage := 8
var _range := 420.0
var _travelled := 0.0
var _homing := false
var _turn_rate := 3.0
var _lifetime := 4.0
var _life := 0.0

func setup(pos: Vector2, dir: Vector2, speed: float, damage: int, range: float,
		homing: bool = false, turn_rate: float = 3.0, lifetime: float = 4.0) -> void:
	global_position = pos
	_dir = dir.normalized()
	_speed = speed
	_damage = damage
	_range = range
	_homing = homing
	_turn_rate = turn_rate
	_lifetime = lifetime

func _ready() -> void:
	body_entered.connect(_on_body)

func _physics_process(delta: float) -> void:
	if _homing:
		# 缓慢转向玩家（不超过转向率），弹幕因此可被走位甩开
		var p := get_tree().get_first_node_in_group("player")
		if p != null:
			var target: float = (p.global_position - global_position).angle()
			var cur: float = _dir.angle()
			var diff: float = angle_difference(cur, target)
			_dir = Vector2.from_angle(cur + clampf(diff, -_turn_rate * delta, _turn_rate * delta))
		_life += delta
		if _life >= _lifetime:
			queue_free()
			return
	global_position += _dir * _speed * delta
	_travelled += _speed * delta
	if _travelled >= _range:
		queue_free()

func _on_body(body: Node) -> void:
	if body.is_in_group("player"):
		EventBus.player_hit.emit(_damage, global_position)
		EventBus.fx_explosion.emit(global_position, "fire")
		queue_free()
