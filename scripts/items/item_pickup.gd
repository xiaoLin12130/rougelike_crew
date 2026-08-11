class_name ItemPickup
extends Area2D
## 道具掉落物（实体）：物品/法术部件/饰品以掉落物形式出现，玩家触碰拾取。
## 目的：掉落不再自动进包，玩家自己决定构筑方向（不影响流派概率预期）。

const LIFETIME := 25.0
const BOB_AMPLITUDE := 2.0
const BOB_SPEED := 3.0
const MAGNET_RADIUS := 100.0
const MAGNET_SPEED := 240.0
const PICKUP_DISTANCE := 22.0

var _kind := "item"        # item / spell_part / trinket
var _payload := ""         # item_id 或 "core:shell"
var _t := 0.0
var _bob_base_y := 0.0

func setup(kind: String, payload: String, icon_path: String) -> void:
	_kind = kind
	_payload = payload
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr != null and ResourceLoader.exists(icon_path):
		spr.texture = load(icon_path)

func _ready() -> void:
	add_to_group("item_pickup")
	body_entered.connect(_on_body_entered)
	_bob_base_y = global_position.y
	var blink := create_tween()
	blink.set_loops()
	blink.tween_interval(LIFETIME - 5.0)
	blink.tween_property(self, "modulate:a", 0.25, 0.2)
	blink.tween_property(self, "modulate:a", 1.0, 0.2)
	var kill := get_tree().create_timer(LIFETIME)
	kill.timeout.connect(queue_free)


## N2 磁铁：拾取范围 +30%/层（magnet 曲线经 pickup tag 聚合）
func _magnet_radius() -> float:
	var bonus := 0.0
	if GameState != null and GameState.has_method("aggregate_bonus"):
		bonus = float(GameState.aggregate_bonus("pickup"))
	return MAGNET_RADIUS * (1.0 + bonus)

func _physics_process(delta: float) -> void:
	_t += delta
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		var dist: float = global_position.distance_to(player.global_position)
		if dist <= _magnet_radius():
			global_position += (player.global_position - global_position).normalized() * MAGNET_SPEED * delta
			if global_position.distance_to(player.global_position) <= PICKUP_DISTANCE:
				_pickup(player)
			return
	global_position.y = _bob_base_y + sin(_t * BOB_SPEED) * BOB_AMPLITUDE

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_pickup(body)

func _pickup(_player: Node) -> void:
	match _kind:
		"item":
			GameState.add_item(_payload)
			var def := GameState.item_def(_payload)
			EventBus.item_picked.emit(_payload, GameState.total_stacks(_payload))
			EventBus.fx_explosion.emit(global_position, "heal")
		"spell_part":
			var parts := _payload.split(":")
			GameState.add_spell_part(
				parts[0] if parts.size() > 0 else "",
				parts[1] if parts.size() > 1 else "")
			## 落雷误触发修复：拾取特效按法术核心元素取色（无雷核心不再闪雷）
			var core_el := GameState.spell_core_element(parts[0] if parts.size() > 0 else "")
			EventBus.fx_explosion.emit(global_position, core_el if not core_el.is_empty() else "gold")
		"trinket":
			GameState.add_trinket(_payload)
			EventBus.fx_explosion.emit(global_position, "blade")
	queue_free()
