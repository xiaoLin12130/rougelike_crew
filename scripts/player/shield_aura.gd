extends Node2D
## 玩家护盾光环（2026-08-12，docs/design/藤蔓护盾音效修复报告.md）：
## 淡蓝色半透明圆环 + 脚下柔光 + 旋转刻度，随护盾池存在/消失。
## - 挂载：player.gd _ready() 挂到玩家下（z_index -1，玩家脚底，自动跟随移动）
## - 数据只读：defense_synergy._shield（synergy 内部状态，非 run 字段），
##   按脚本路径定位节点，未挂载（如 headless 测试）返回 0 → 光环隐藏。
## - 全部程序化 _draw，禁止新增静态贴图文件（项目铁律）。

const SHIELD_SCRIPT_PATH := "res://scripts/synergies/defense_synergy.gd"

const RING_COLOR := Color(0.62, 0.82, 1.0)
const RING_BRIGHT := Color(0.88, 0.96, 1.0)
const DOME_COLOR := Color(0.55, 0.78, 1.0)
const RING_RADIUS := 21.0
const DOME_RADIUS := 15.0
const PULSE_SPEED := 5.0

var _shield_source: Node = null
var _phase := 0.0


func _ready() -> void:
	z_index = -1
	position = Vector2(0, 6)  # 脚底偏移（玩家 32x32，光环贴地）


func _process(delta: float) -> void:
	var shield := _shield_value()
	visible = shield > 0.0
	if not visible:
		return
	_phase += delta
	queue_redraw()


## 只读查询防御流护盾池（hud.gd 同款路径定位逻辑）。
func _shield_value() -> float:
	var src := _shield_source_node()
	if src == null:
		return 0.0
	var v = src.get("_shield")
	return 0.0 if v == null else float(v)


func _shield_source_node() -> Node:
	if _shield_source != null and is_instance_valid(_shield_source):
		return _shield_source
	_shield_source = _find_synergy_node(get_tree().root)
	return _shield_source


func _find_synergy_node(node: Node) -> Node:
	var script: Script = node.get_script()
	if script != null and script.resource_path == SHIELD_SCRIPT_PATH:
		return node
	for child in node.get_children():
		var hit := _find_synergy_node(child)
		if hit != null:
			return hit
	return null


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_phase * PULSE_SPEED)
	# 脚下柔光（半透明圆，呼吸）
	draw_circle(Vector2.ZERO, DOME_RADIUS, Color(DOME_COLOR, 0.06 + 0.035 * pulse))
	# 主环（浅蓝，脉动宽度）
	draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 32,
		Color(RING_COLOR, 0.30 + 0.16 * pulse), 2.2 + 0.6 * pulse)
	# 内细亮环（更亮更细，反相脉动）
	draw_arc(Vector2.ZERO, RING_RADIUS - 3.2, 0.0, TAU, 28,
		Color(RING_BRIGHT, 0.16 + 0.12 * (1.0 - pulse)), 1.0)
	# 旋转刻度（4 段短弧，顺时针缓慢转动，表现护盾能量流转）
	var rot := _phase * 1.4
	for i in 4:
		var a0 := rot + TAU * float(i) / 4.0
		draw_arc(Vector2.ZERO, RING_RADIUS + 1.5, a0, a0 + 0.55, 6,
			Color(RING_BRIGHT, 0.55 + 0.25 * pulse), 2.0)
	# 顶部高光点（护盾能量核心）
	var glow_a := rot + TAU * 0.25
	draw_circle(Vector2.from_angle(glow_a) * (RING_RADIUS - 1.0), 1.6,
		Color(RING_BRIGHT, 0.5 + 0.4 * pulse))
