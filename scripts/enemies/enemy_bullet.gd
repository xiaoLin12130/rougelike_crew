extends Area2D
## 敌方弹幕：直线飞行，命中玩家发 player_hit
## v2 扩展：homing=true 时缓慢转向玩家（弹速 120-150、转向率 3rad/s、寿命 4s）
## v3 扩展（2026-08-12）：敌我弹幕视觉区分——8 类暗色弹体贴图（assets/sprites/enemy/eb_*.png），
## 尖形弹随飞行方向旋转；按敌人 id 自动应用 enemies.json bullet_visual 配置（set_by_enemy），
## 发射点无需改动（缺省 eb_diamond_purple，兼容既有 setup 调用）

const SHAPE_TEXTURES := {
	"eb_diamond_purple": "res://assets/sprites/enemy/eb_diamond_purple.png",
	"eb_shard_red": "res://assets/sprites/enemy/eb_shard_red.png",
	"eb_cross_bone": "res://assets/sprites/enemy/eb_cross_bone.png",
	"eb_skull_dark": "res://assets/sprites/enemy/eb_skull_dark.png",
	"eb_bolt_bone": "res://assets/sprites/enemy/eb_bolt_bone.png",
	"eb_spore_green": "res://assets/sprites/enemy/eb_spore_green.png",
	"eb_orb_stone": "res://assets/sprites/enemy/eb_orb_stone.png",
	"eb_blade_shadow": "res://assets/sprites/enemy/eb_blade_shadow.png",
}
## 尖形弹：贴图尖头朝右绘制，随飞行方向旋转 sprite.rotation = dir.angle()
const ROTATING_SHAPES := ["eb_diamond_purple", "eb_shard_red", "eb_bolt_bone", "eb_blade_shadow"]

var _dir := Vector2.RIGHT
var _speed := 180.0
var _damage := 8
var _range := 420.0
var _travelled := 0.0
var _homing := false
var _turn_rate := 3.0
var _lifetime := 4.0
var _life := 0.0
var _sprite: Sprite2D
var _shape := "eb_diamond_purple"
var _rotating := false
var _enemy_id := ""

func setup(pos: Vector2, dir: Vector2, speed: float, damage: int, range: float,
		homing: bool = false, turn_rate: float = 3.0, lifetime: float = 4.0,
		enemy_id: String = "") -> void:
	global_position = pos
	_dir = dir.normalized()
	_speed = speed
	_damage = damage
	_range = range
	_homing = homing
	_turn_rate = turn_rate
	_lifetime = lifetime
	_enemy_id = enemy_id

func _ready() -> void:
	_sprite = get_node("Sprite2D")
	if not _enemy_id.is_empty():
		set_by_enemy(_enemy_id)
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
	if _rotating and _sprite != null:
		_sprite.rotation = _dir.angle()
	global_position += _dir * _speed * delta
	_travelled += _speed * delta
	if _travelled >= _range:
		queue_free()

func set_by_enemy(enemy_id: String) -> void:
	## 按敌人 id 查 enemies.json 的 bullet_visual 配置并应用弹体贴图/色调/旋转。
	## 未找到配置时保持缺省 eb_diamond_purple（向后兼容）。
	var gs := get_node_or_null("/root/GameState")
	var shape := "eb_diamond_purple"
	var tint_hex := ""
	if gs != null:
		for e in gs.tables.get("enemies", {}).get("enemies", []):
			if str(e.get("id", "")) == enemy_id:
				var bv: Dictionary = e.get("bullet_visual", {})
				shape = str(bv.get("shape", "eb_diamond_purple"))
				tint_hex = str(bv.get("tint", ""))
				break
	_apply_visual(shape, tint_hex, Color.WHITE)

func setup_visual(shape: String, tint: Color = Color.WHITE) -> void:
	## 手动指定弹体样式：换贴图 + 色调 + 旋转标志（尖形弹随飞行方向旋转）
	_apply_visual(shape, "", tint)

func _apply_visual(shape: String, tint_hex: String, tint: Color) -> void:
	if _sprite == null:
		_sprite = get_node_or_null("Sprite2D")
	if _sprite == null:
		return
	_shape = shape
	if SHAPE_TEXTURES.has(shape):
		_sprite.texture = load(SHAPE_TEXTURES[shape])
	_rotating = shape in ROTATING_SHAPES
	# 贴图已烘焙规范色；tint 作为乘色调（缺省白色 = 保持贴图原色）
	if tint_hex != "" and tint_hex != "#FFFFFF":
		_sprite.modulate = Color(tint_hex)
	elif tint != Color.WHITE:
		_sprite.modulate = tint
	else:
		_sprite.modulate = Color.WHITE
	if _rotating and _sprite != null:
		_sprite.rotation = _dir.angle()

func _on_body(body: Node) -> void:
	if body.is_in_group("player"):
		EventBus.player_hit.emit(_damage, global_position)
		EventBus.fx_explosion.emit(global_position, "fire")
		queue_free()
