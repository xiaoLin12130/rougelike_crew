extends Node2D
## 护盾视觉测试（docs/design/藤蔓护盾音效修复报告.md）：
## ① 玩家身上挂 ShieldAura 护盾光环节点（player.gd 挂载）；
## ② 护盾池 > 0 时 ShieldAura 可见，归零后隐藏；
## ③ 护盾受击：EventBus.player_hit 时生成 ShieldRipple 涟漪 + 播 shield_hit 音
##    （替代 hurt）；护盾破碎（>0 → 0）生成破碎涟漪 + shield_break 音。
## Run: godot --headless --path . res://scripts/tests/test_shield_visual.tscn

const PLAYER_SCENE := preload("res://scenes/game/player.tscn")
const DEFENSE_SCRIPT := preload("res://scripts/synergies/defense_synergy.gd")
const FX_MANAGER_SCRIPT := preload("res://scripts/fx/fx_manager.gd")

var _failures: Array[String] = []
var _player: Node
var _ds: Node


func _ready() -> void:
	GameState.new_run()
	GameState.run.max_hp = 120
	GameState.run.hp = 100
	# 防御流 synergy 挂 SynergyRegistry 下（与运行期一致，hud/fx 按脚本路径定位）
	var reg := get_tree().root.get_node_or_null("SynergyRegistry")
	if reg == null:
		_fail("SynergyRegistry autoload missing")
		get_tree().quit(1)
		return
	_ds = DEFENSE_SCRIPT.new()
	_ds.name = "DefenseSynergy"
	reg.add_child(_ds)
	_player = PLAYER_SCENE.instantiate()
	_player.name = "TestPlayer"
	add_child(_player)
	await get_tree().process_frame
	await _test_aura_node()
	await _test_aura_visibility()
	await _test_ripple_factory()
	await _test_hit_feedback()
	_ds.queue_free()
	_player.queue_free()
	if _failures.is_empty():
		print("[TEST] SHIELD VISUAL ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		print("SHIELD VISUAL FAILED: %d" % _failures.size())
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[TEST] FAIL: " + msg)


func _find_ripple() -> Node:
	return find_child("ShieldRipple", true, false)


## ① 玩家身上有护盾视觉节点
func _test_aura_node() -> void:
	var aura := _player.get_node_or_null("ShieldAura")
	if aura == null:
		_fail("玩家身上应挂 ShieldAura 护盾视觉节点（player.gd 挂载）")
	else:
		print("[TEST] ShieldAura 挂载 → PASS")


## ② 有护盾可见 / 归零隐藏
func _test_aura_visibility() -> void:
	_ds._shield = 30.0
	await get_tree().process_frame
	await get_tree().process_frame
	var aura := _player.get_node_or_null("ShieldAura") as CanvasItem
	if aura == null:
		return
	if not aura.visible:
		_fail("护盾 30 时 ShieldAura 应可见")
	else:
		print("[TEST] 护盾 >0 → ShieldAura 可见 → PASS")
	_ds._shield = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if aura.visible:
		_fail("护盾归零后 ShieldAura 应隐藏")
	else:
		print("[TEST] 护盾归零 → ShieldAura 隐藏 → PASS")


## ③a 涟漪工厂：普通/破碎两种形态都能生成 ShieldRipple 节点
func _test_ripple_factory() -> void:
	var fx := FX_MANAGER_SCRIPT.new()
	fx.name = "TestFxManager"
	add_child(fx)
	var ripple := FX_MANAGER_SCRIPT.spawn_shield_hit_fx(Vector2(200, 200), false)
	if ripple == null or _find_ripple() == null:
		_fail("spawn_shield_hit_fx 应生成 ShieldRipple 涟漪节点")
	else:
		print("[TEST] 护盾受击涟漪生成 → PASS")
	ripple.queue_free()
	await get_tree().process_frame
	var broken := FX_MANAGER_SCRIPT.spawn_shield_hit_fx(Vector2(240, 200), true)
	if broken == null:
		_fail("破碎涟漪生成失败")
	broken.queue_free()
	await get_tree().process_frame


## ③b 受击反馈：有护盾时 player_hit → 涟漪 + shield_hit 音（非 hurt）
func _test_hit_feedback() -> void:
	var fx := get_node_or_null("TestFxManager")
	if fx == null:
		return
	_ds._shield = 20.0
	await get_tree().process_frame
	await get_tree().process_frame  # fx 护盾基线建立
	var hit_before := int(SfxBus.hit_stats().get("shield_hit", 0))
	var hurt_before := int(SfxBus.hit_stats().get("hurt", 0))
	EventBus.player_hit.emit(5, _player.global_position)
	await get_tree().process_frame
	if _find_ripple() == null:
		_fail("护盾受击应生成 ShieldRipple 涟漪")
	if int(SfxBus.hit_stats().get("shield_hit", 0)) <= hit_before:
		_fail("护盾受击应播 shield_hit 玻璃叮音")
	if int(SfxBus.hit_stats().get("hurt", 0)) != hurt_before:
		_fail("护盾在场时不应播 hurt 闷响")
	else:
		print("[TEST] 护盾受击 → 涟漪 + shield_hit 音（无 hurt）→ PASS")
	# 护盾破碎：>0 → 0 时生成破碎涟漪 + shield_break 音
	var brk_before := int(SfxBus.hit_stats().get("shield_break", 0))
	_ds._shield = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if _find_ripple() == null:
		_fail("护盾破碎应生成破碎涟漪")
	if int(SfxBus.hit_stats().get("shield_break", 0)) <= brk_before:
		_fail("护盾破碎应播 shield_break 音")
	else:
		print("[TEST] 护盾破碎 → 涟漪 + shield_break 音 → PASS")
