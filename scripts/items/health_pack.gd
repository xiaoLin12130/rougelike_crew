class_name HealthPack
extends Area2D
## 血包掉落物：精英/Boss 击杀掉落，玩家接触后按最大生命百分比回血。
## 数据契约：drops.json -> elite_drops.heal_pct / boss_drops.heal_pct

const LIFETIME := 25.0
const BOB_AMPLITUDE := 2.0
const BOB_SPEED := 3.0
const MAGNET_RADIUS := 160.0
const MAGNET_SPEED := 260.0
const PICKUP_DISTANCE := 22.0

var _heal_pct := 0.10
var _bob_base_y := 0.0
var _t := 0.0

func setup(pct: float) -> void:
	_heal_pct = maxf(pct, 0.0)

func _ready() -> void:
	add_to_group("health_pack")
	body_entered.connect(_on_body_entered)
	_bob_base_y = global_position.y
	# 到期前 5 秒闪烁提醒，25 秒后消失
	var blink := create_tween()
	blink.set_loops()
	blink.tween_interval(LIFETIME - 5.0)
	blink.tween_property(self, "modulate:a", 0.25, 0.2)
	blink.tween_property(self, "modulate:a", 1.0, 0.2)
	var kill := get_tree().create_timer(LIFETIME)
	kill.timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	_t += delta
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		var dist: float = global_position.distance_to(player.global_position)
		if dist <= MAGNET_RADIUS:
			# 磁吸：玩家靠近后血包自动飞向玩家（怪堆里的血包也能吃到）
			global_position += (player.global_position - global_position).normalized() * MAGNET_SPEED * delta
			if global_position.distance_to(player.global_position) <= PICKUP_DISTANCE:
				_on_body_entered(player)
			return
	global_position.y = _bob_base_y + sin(_t * BOB_SPEED) * BOB_AMPLITUDE

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	var healed: int = GameState.heal(GameState.run.max_hp * _heal_pct)
	if healed > 0:
		EventBus.fx_heal_text.emit(global_position, healed)
	EventBus.fx_explosion.emit(global_position, "heal")
	queue_free()
