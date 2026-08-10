extends CanvasLayer
## 第5关通关抉择（竖版 360x640）：面板 320x300 居中（<=340 宽），
## 两个选项按钮纵向堆叠（280x48，触控最小 44），拇指可达。
const UiLayout := preload("res://scripts/ui/ui_layout.gd")

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	UiLayout.center_panel(panel, 320.0, 300.0)
	panel.custom_minimum_size = Vector2(320, 300)
	panel.add_theme_stylebox_override("panel", UiTheme.style(UiTheme.PANEL, UiTheme.GOLD, 3, 6))
	root.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var title := UiTheme.label("第 5 关已通关！", 24, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var sub := UiTheme.label("选择你的命运：", 12, Color("#c8c0e0"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)
	var btn_box := VBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 10)
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_box)
	var boss_btn := UiTheme.button("决战最终Boss", Vector2(280, 48))
	boss_btn.pressed.connect(_on_boss)
	btn_box.add_child(boss_btn)
	var loop_btn := UiTheme.button("回到第一关继续刷", Vector2(280, 48))
	loop_btn.pressed.connect(_on_loop)
	btn_box.add_child(loop_btn)
	var tip := UiTheme.label("继续刷：敌人与掉落数值按轮次指数膨胀", 10, Color("#7a6fa0"))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tip)

func _on_boss() -> void:
	EventBus.loop_choice.emit("boss")

func _on_loop() -> void:
	EventBus.loop_choice.emit("loop")
