extends Control
## 主菜单：像素风背景 + 大标题 + 开始/继续/退出

@onready var start_button: Button = $StartButton
@onready var continue_button: Button = $ContinueButton

func _ready() -> void:
	_build_background()
	_build_title()
	_style_buttons()
	continue_button.disabled = not SaveStore.has_save()
	start_button.pressed.connect(_on_start)
	continue_button.pressed.connect(_on_continue)
	$QuitButton.pressed.connect(_on_quit)

func _build_background() -> void:
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.colors = PackedColorArray([Color("#0d0a18"), Color("#1b1230"), Color("#14111f")])
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = grad
	bg.z_index = -10  # 背景必须垫底，否则盖住 tscn 预置的按钮
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var stars := CPUParticles2D.new()
	stars.z_index = -10
	stars.amount = 90
	stars.lifetime = 4.0
	stars.explosiveness = 0.0
	stars.emitting = true
	stars.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	stars.emission_rect_extents = Vector2(320, 180)
	stars.initial_velocity_min = 8.0
	stars.initial_velocity_max = 20.0
	stars.direction = Vector2(0, 1)
	stars.gravity = Vector2.ZERO
	stars.scale_amount_min = 0.6
	stars.scale_amount_max = 1.6
	stars.color = Color(0.85, 0.8, 1.0, 0.7)
	add_child(stars)

func _build_title() -> void:
	var title := UiTheme.label("像素肉鸽", 44, UiTheme.GOLD)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-180, 40)
	title.custom_minimum_size = Vector2(360, 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 4)
	add_child(title)
	var sub := UiTheme.label("法术构筑 · 割草 · 雨中冒险式抉择", 12, Color("#9d8fc4"))
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-200, 96)
	sub.custom_minimum_size = Vector2(400, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

func _style_buttons() -> void:
	for b in [$StartButton, $ContinueButton, $QuitButton]:
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UiTheme.font_cn())
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", UiTheme.GOLD)
		b.add_theme_color_override("font_hover_color", Color("#ffe9a8"))
		b.add_theme_color_override("font_pressed_color", UiTheme.WHITE)
		b.add_theme_stylebox_override("normal", UiTheme.style(UiTheme.PANEL, UiTheme.BORDER_DIM, 2, 4))
		b.add_theme_stylebox_override("hover", UiTheme.style(UiTheme.PANEL_LIGHT, UiTheme.BORDER, 2, 4))
		b.add_theme_stylebox_override("pressed", UiTheme.style(Color("#191527"), UiTheme.GOLD, 2, 4))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hint := UiTheme.label("WASD 移动 · 空格闪避 · 自动施法 · Esc 暂停", 10, Color("#7a6fa0"))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-220, -48)
	hint.custom_minimum_size = Vector2(440, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	var ver := UiTheme.label("v0.1 DEMO", 9, Color("#5a5278"))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-70, -8)
	ver.custom_minimum_size = Vector2(60, 14)
	add_child(ver)

func _on_start() -> void:
	SfxBus.play("res://assets/audio/sfx_two_tone.ogg", -15.0)
	GameState.new_run()
	SaveStore.clear_save()
	get_tree().change_scene_to_file("res://scenes/game/game_root.tscn")

func _on_continue() -> void:
	var data := SaveStore.load_run()
	if data.is_empty():
		_on_start()
		return
	GameState.run = data
	get_tree().change_scene_to_file("res://scenes/game/game_root.tscn")

func _on_quit() -> void:
	get_tree().quit()
