extends Area2D
## 敌方弹幕：直线飞行，命中玩家发 player_hit

var _dir := Vector2.RIGHT
var _speed := 180.0
var _damage := 8
var _range := 420.0
var _travelled := 0.0

func setup(pos: Vector2, dir: Vector2, speed: float, damage: int, range: float) -> void:
	global_position = pos
	_dir = dir.normalized()
	_speed = speed
	_damage = damage
	_range = range

func _ready() -> void:
	body_entered.connect(_on_body)

func _physics_process(delta: float) -> void:
	global_position += _dir * _speed * delta
	_travelled += _speed * delta
	if _travelled >= _range:
		queue_free()

func _on_body(body: Node) -> void:
	if body.is_in_group("player"):
		EventBus.player_hit.emit(_damage, global_position)
		EventBus.fx_explosion.emit(global_position, "fire")
		queue_free()
