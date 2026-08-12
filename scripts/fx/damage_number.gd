class_name DamageNumber
extends Node2D
## 伤害飘字：上飘 + 淡出，0.6s 后自毁。由 fx_manager 实例化并调用 play()。
## 打击感 G-3（S 级）：弹出动画（0.6 → 1.2 → 1.0 回弹）、聚合（add_value 合并显示）、
## 上限淘汰（dismiss 加速淡出）、暴击更大更亮（1.8x + 横移 ±10px + 旋转 ±4°）。

const BASE_FONT_SIZE := 14
const RISE_DISTANCE := 18.0
const LIFETIME := 0.6
const FADE_DURATION := 0.35
const POP_SCALE_MIN := 0.6
const POP_SCALE_PEAK := 1.2
const POP_DURATION := 0.18
const CRIT_SIZE_MULT := 1.8  # 暴击字号倍率（原 1.6 → 1.8）

@onready var _label: Label = $Label

var base_scale := 1.0  ## fx_manager 注入的 DPS 档位倍率（在 play 前设置）
var _total := 0        ## 聚合累计值（同帧同目标合并）

func play(value: int, is_crit: bool, heal: bool = false, dot_color: Color = Color(1, 1, 1, 1)) -> void:
	_total = value
	_label.text = str(_total)
	var font_size: int = BASE_FONT_SIZE
	var font_color := Color.WHITE
	if is_crit:
		font_size = roundi(float(BASE_FONT_SIZE) * CRIT_SIZE_MULT)
		font_color = Color(1.0, 0.84, 0.2)
	elif heal:
		font_color = Color(0.45, 1.0, 0.55)
	elif dot_color != Color(1, 1, 1, 1):
		font_color = dot_color
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", font_color)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_label.add_theme_constant_override("outline_size", 3)
	# 暴击差异化：随机横移 ±10px + 旋转 ±4°；普通 ±6px
	if is_crit:
		position += Vector2(randf_range(-10.0, 10.0), randf_range(-4.0, 0.0))
		rotation = deg_to_rad(randf_range(-4.0, 4.0))
	else:
		position += Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 0.0))
	# 弹出动画：0.6 → 1.2 → 1.0（0.18s 回弹，EASE_OUT）
	scale = Vector2.ONE * POP_SCALE_MIN * base_scale
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * POP_SCALE_PEAK * base_scale, POP_DURATION * 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE * base_scale, POP_DURATION * 0.45).set_delay(POP_DURATION * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", position.y - RISE_DISTANCE, LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION).set_delay(LIFETIME - FADE_DURATION)
	tween.chain().tween_callback(queue_free)

## 聚合（G-3）：同帧同目标后续伤害并入本数字——数值累加显示、重播回弹、
## 任一跳为暴击则整体升级为暴击样式（更大更亮）。
func add_value(value: int, is_crit: bool) -> void:
	_total += value
	_label.text = str(_total)
	if is_crit:
		var crit_size := roundi(float(BASE_FONT_SIZE) * CRIT_SIZE_MULT)
		_label.add_theme_font_size_override("font_size", crit_size)
		_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.2))
		rotation = deg_to_rad(randf_range(-4.0, 4.0))
	# 重播回弹（不重走上飘/淡出时间轴）
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * POP_SCALE_PEAK * base_scale, POP_DURATION * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE * base_scale, POP_DURATION * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 上限淘汰（G-3）：超限数字加速淡出（0.15s）后自毁，不再走完整寿命。
func dismiss(duration: float = 0.15) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, maxf(duration, 0.05))
	tween.tween_callback(queue_free)
