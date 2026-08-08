extends Node
## 特效总控（Agent F）：由 GameRoot 实例化并挂载，统一监听 EventBus 信号，
## 产出粒子爆散 / 扩散圆环 / 伤害飘字 / 受击白闪 / 震屏 / 慢动作。
## 契约：特效一律由本节点产出，其他模块禁止自行 new 粒子。

const ParticleBurstScene: PackedScene = preload("res://scenes/fx/particle_burst.tscn")
const ExplosionScene: PackedScene = preload("res://scenes/fx/explosion.tscn")
const DamageNumberScene: PackedScene = preload("res://scenes/fx/damage_number.tscn")

const KIND_COLORS := {
	"fire": Color(1.0, 0.45, 0.15),
	"ice": Color(0.45, 0.78, 1.0),
	"lightning": Color(1.0, 0.86, 0.25),
	"poison": Color(0.45, 0.9, 0.3),
	"blade": Color(0.92, 0.94, 1.0),
}
const DEFAULT_KIND := "fire"

const BURST_AMOUNT_MIN := 16
const BURST_AMOUNT_MAX := 32
const RING_SCALE := 2.6
const RING_DURATION := 0.3
const SHAKE_SMALL := 3.0
const SHAKE_PLAYER_HIT := 2.5
const FLASH_COLOR := Color(3.0, 3.0, 3.0, 1.0)
const SLOW_MO_MIN_FACTOR := 0.05

static var _white_particle_texture: Texture2D

var _slow_mo_tween: Tween

func _ready() -> void:
	EventBus.fx_explosion.connect(_on_fx_explosion)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.fx_hit_flash.connect(_on_fx_hit_flash)
	EventBus.screen_shake.connect(_on_screen_shake)
	EventBus.slow_mo.connect(_on_slow_mo)
	# 契约：player_hit 的监听方包含特效（受击反馈）
	EventBus.player_hit.connect(_on_player_hit)

func _on_fx_explosion(pos: Vector2, kind: String) -> void:
	var color: Color = KIND_COLORS.get(kind, KIND_COLORS[DEFAULT_KIND])
	# 一次性粒子爆散（amount 16-32，速度 60-180，2x2 白色程序化纹理，按元素着色）
	var burst: CPUParticles2D = ParticleBurstScene.instantiate()
	burst.position = pos
	burst.amount = randi_range(BURST_AMOUNT_MIN, BURST_AMOUNT_MAX)
	burst.color = color
	burst.texture = _get_white_texture()
	burst.finished.connect(burst.queue_free)
	add_child(burst)
	# 扩散圆环（程序化 Line2D，Tween 缩放 + 淡出）
	var ring: Node2D = ExplosionScene.instantiate()
	ring.position = pos
	ring.modulate = color
	add_child(ring)
	var ring_tween: Tween = ring.create_tween()
	ring_tween.tween_property(ring, "scale", Vector2(RING_SCALE, RING_SCALE), RING_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ring_tween.parallel().tween_property(ring, "modulate:a", 0.0, RING_DURATION)
	ring_tween.tween_callback(ring.queue_free)
	# 爆炸 0.1s 后触发小威力震屏
	get_tree().create_timer(0.1).timeout.connect(_emit_small_shake)

func _emit_small_shake() -> void:
	EventBus.screen_shake.emit(SHAKE_SMALL)

func _on_damage_dealt(dmg: int, pos: Vector2, is_crit: bool) -> void:
	var number: DamageNumber = DamageNumberScene.instantiate()
	number.position = pos
	add_child(number)
	number.play(dmg, is_crit)

func _on_fx_hit_flash(target: Node) -> void:
	if not is_instance_valid(target) or not (target is CanvasItem):
		return
	var item := target as CanvasItem
	var original: Color = item.modulate
	var tween: Tween = item.create_tween()
	tween.tween_property(item, "modulate", FLASH_COLOR, 0.04)
	tween.tween_property(item, "modulate", original, 0.04)

func _on_slow_mo(factor: float, duration: float) -> void:
	var f: float = clampf(factor, SLOW_MO_MIN_FACTOR, 1.0)
	var d: float = maxf(duration, 0.01)
	if _slow_mo_tween != null and _slow_mo_tween.is_valid():
		_slow_mo_tween.kill()
	Engine.time_scale = f
	# 4.7 文档：create_tween() 默认即 TWEEN_PROCESS_IDLE；
	# 配合 set_ignore_time_scale(true) 让恢复按真实时间走，不被慢动作本身拖慢。
	_slow_mo_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_slow_mo_tween.set_ignore_time_scale(true)
	_slow_mo_tween.tween_property(Engine, "time_scale", 1.0, d)

func _on_screen_shake(power: float) -> void:
	var camera := get_tree().get_first_node_in_group("camera")
	if is_instance_valid(camera) and camera.has_method("shake"):
		camera.shake(power)

func _on_player_hit(_dmg: int, _pos: Vector2) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		_on_fx_hit_flash(player)
	EventBus.screen_shake.emit(SHAKE_PLAYER_HIT)

static func _get_white_texture() -> Texture2D:
	if _white_particle_texture == null:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white_particle_texture = ImageTexture.create_from_image(image)
	return _white_particle_texture
