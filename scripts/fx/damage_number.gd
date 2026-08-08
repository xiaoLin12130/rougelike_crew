class_name DamageNumber
extends Node2D
## 伤害飘字：上飘 + 淡出，0.6s 后自毁。由 fx_manager 实例化并调用 play()。

const BASE_FONT_SIZE := 14
const RISE_DISTANCE := 18.0
const LIFETIME := 0.6
const FADE_DURATION := 0.35

@onready var _label: Label = $Label

func play(value: int, is_crit: bool) -> void:
	_label.text = str(value)
	var font_size: int = BASE_FONT_SIZE
	var font_color := Color.WHITE
	if is_crit:
		font_size = roundi(float(BASE_FONT_SIZE) * 1.6)
		font_color = Color(1.0, 0.84, 0.2)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", font_color)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_label.add_theme_constant_override("outline_size", 3)
	position += Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 0.0))
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - RISE_DISTANCE, LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION).set_delay(LIFETIME - FADE_DURATION)
	tween.chain().tween_callback(queue_free)
