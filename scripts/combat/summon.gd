extends Node2D
## 召唤蝙蝠：跟随玩家移动，每 1s 攻击最近敌人（base_damage），存活 30s。
## 上限 = GameState.total_stacks("summon_book") + 1，超限销毁最旧召唤物。

const BAT_TEXTURE := "res://assets/sprites/gen/enemy_bat_1.png"
const LIFETIME := 30.0
const ATTACK_INTERVAL := 1.0
const ATTACK_RANGE := 48.0
const FOLLOW_RANGE := 64.0
const MOVE_SPEED := 170.0

static var _spawn_counter := 0

var _player: Node2D = null
var _damage := 6.0
var _element := "summon"
var _life := LIFETIME
var _atk_timer := 0.0
var _spawn_order := 0


func setup(player: Node2D, damage: float, element: String) -> void:
	_player = player
	_damage = damage
	_element = element


func _ready() -> void:
	add_to_group("summons")
	_spawn_order = _spawn_counter
	_spawn_counter += 1
	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	spr.texture = load(BAT_TEXTURE)
	add_child(spr)
	_enforce_cap()


## 召唤上限 = 召唤之书层数 + 1；超限销毁最旧者。
func _enforce_cap() -> void:
	var cap: int = GameState.total_stacks("summon_book") + 1
	var group: Array = get_tree().get_nodes_in_group("summons")
	if group.size() <= cap:
		return
	var oldest: Node = null
	var oldest_order: int = 1 << 30
	for s in group:
		if s == self or not is_instance_valid(s):
			continue
		var order: int = int(s.get("_spawn_order"))
		if order < oldest_order:
			oldest_order = order
			oldest = s
	if oldest != null:
		oldest.queue_free()


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if _player == null or not is_instance_valid(_player):
		queue_free()
		return
	var to_player := _player.global_position - global_position
	if to_player.length() > FOLLOW_RANGE:
		global_position += to_player.normalized() * MOVE_SPEED * delta
	_atk_timer += delta
	if _atk_timer >= ATTACK_INTERVAL:
		_atk_timer = 0.0
		_attack()


func _attack() -> void:
	var target := _nearest_enemy()
	if target == null:
		return
	var final_dmg := roundi(_damage)
	if target.has_method("take_damage"):
		target.take_damage(final_dmg, _element, false)
	EventBus.damage_dealt.emit(final_dmg, target.global_position, false)
	EventBus.fx_hit_flash.emit(target)


func _nearest_enemy() -> Node:
	var best: Node = null
	var best_d := ATTACK_RANGE
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best
