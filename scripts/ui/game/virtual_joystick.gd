extends CanvasLayer
## 触屏虚拟移动摇杆（方案 A：全屏动态摇杆，2026-08-10 重构）
## - 全屏：触摸屏幕任意非 UI 区域 → 按下处生成移动底盘，拖动写
##   InputRouter.move_vector + external_move（iOS/安卓/横竖屏行为一致）
## - 攻击方向由自动索敌接管（瞄准摇杆已废弃；aim_override 仍供自动脚本直写）
## - 右下角：闪避按钮（触控目标 72px），点击调 player.request_dash()
## - 多指：移动摇杆最多一个（第一指），后续手指忽略（避免双摇杆打架）；
##   闪避按钮区域任何时候优先消费（不受单摇杆限制）
## - 桌面/无触摸环境：visible=false 且不拦截任何事件（overlay mouse_filter=IGNORE）
## 纯程序化绘制（_draw 圆环+圆头），配色取自 UiTheme 色板，零贴图。

const MOVE_RADIUS := 56.0      # 移动摇杆底盘半径
const KNOB_RADIUS := 24.0      # 摇杆头半径
const DEAD_ZONE := 0.18        # 死区（占半径比例），低于视为零输入
const DASH_SIZE := 72.0        # 闪避按钮边长（触控目标 >= 56px）
const DASH_MARGIN := 14.0      # 闪避按钮距右下角边距

@export var force_enable := false  # 测试/无触摸环境强制显示

var router: Node                 # InputRouter autoload
var dash_button: Button          # 右下角闪避按钮（供测试与鼠标点击）
var _overlay: Control            # 全屏绘制层（IGNORE，不拦截输入）
var _active := {}                # index -> {kind, origin, vec, radius, press_ms, drag_dist}
var _dash_press := {}            # index -> 按下位置（闪避按钮区域触摸）


func _ready() -> void:
	router = get_node_or_null("/root/InputRouter")
	_build_overlay()
	_build_dash_button()
	_update_visibility()


func _update_visibility() -> void:
	var touch_ok: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("touch")
	visible = touch_ok or force_enable


func _build_overlay() -> void:
	_overlay = JoystickOverlay.new()
	_overlay.host = self
	_overlay.name = "JoystickOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


func _build_dash_button() -> void:
	dash_button = Button.new()
	dash_button.name = "DashButton"
	dash_button.text = "闪避"
	dash_button.custom_minimum_size = Vector2(DASH_SIZE, DASH_SIZE)
	dash_button.focus_mode = Control.FOCUS_NONE
	dash_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	dash_button.add_theme_font_override("font", UiTheme.font_cn())
	dash_button.add_theme_font_size_override("font_size", 15)
	dash_button.add_theme_color_override("font_color", UiTheme.GOLD)
	dash_button.add_theme_color_override("font_hover_color", Color("#ffe9a8"))
	dash_button.add_theme_color_override("font_pressed_color", UiTheme.WHITE)
	var normal := UiTheme.style(UiTheme.PANEL, UiTheme.BORDER_DIM, 2, 36)
	var hover := UiTheme.style(UiTheme.PANEL_LIGHT, UiTheme.BORDER, 2, 36)
	var pressed := UiTheme.style(Color("#191527"), UiTheme.GOLD, 2, 36)
	dash_button.add_theme_stylebox_override("normal", normal)
	dash_button.add_theme_stylebox_override("hover", hover)
	dash_button.add_theme_stylebox_override("pressed", pressed)
	dash_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	dash_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dash_button.position = Vector2(-(DASH_SIZE + DASH_MARGIN), -(DASH_SIZE + DASH_MARGIN))
	dash_button.pressed.connect(_on_dash_pressed)
	add_child(dash_button)


func _input(event: InputEvent) -> void:
	if not visible or router == null:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.pressed, event.position)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)


func reset_state() -> void:
	## 恢复游戏时调用：清空残留触摸跟踪（升级/暂停期间 touch up 被丢弃，
	## _active 残留旧 index 会导致恢复后摇杆不响应——iOS 升级后动不了的根因）
	_active.clear()
	_dash_press.clear()
	if router != null:
		router.external_move = false
		router.move_vector = Vector2.ZERO
	_overlay.queue_redraw()


## 测试/模拟入口：等价于 InputEventScreenTouch
func simulate_touch(index: int, pressed: bool, pos: Vector2) -> void:
	_handle_touch(index, pressed, pos)


## 测试/模拟入口：等价于 InputEventScreenDrag
func simulate_drag(index: int, pos: Vector2) -> void:
	_handle_drag(index, pos)


func _handle_touch(index: int, pressed: bool, pos: Vector2) -> void:
	if router == null:
		return
	# 暂停（升级三选一/替换界面/商店等）时摇杆完全让位，避免抢占 UI 触摸
	if get_tree() != null and get_tree().paused:
		return
	if pressed:
		if _active.has(index):
			return
		# 闪避按钮区域：本组件消费，避免与 GUI 按钮双触发
		if _inside_dash_button(pos):
			_dash_press[index] = pos
			get_viewport().set_input_as_handled()
			return
		# 其它 UI（HUD 按钮等）区域：不抢触摸
		if _hit_foreign_control(pos):
			return
		# 移动摇杆最多一个（第一指优先；后续手指忽略，避免双摇杆打架）
		if not _active.is_empty():
			return
		_active[index] = {
			"kind": "move",
			"origin": pos,
			"vec": Vector2.ZERO,
			"radius": MOVE_RADIUS,
			"press_ms": 0,
			"drag_dist": 0.0,
		}
		router.external_move = true
		router.move_vector = Vector2.ZERO
		_overlay.queue_redraw()
		return
	# 松手
	if _dash_press.erase(index):
		get_viewport().set_input_as_handled()
		_on_dash_pressed()
		return
	var s: Dictionary = _active.get(index, {})
	if s.is_empty():
		return
	_active.erase(index)
	router.move_vector = Vector2.ZERO
	_overlay.queue_redraw()


func _handle_drag(index: int, pos: Vector2) -> void:
	if router == null:
		return
	var s: Dictionary = _active.get(index, {})
	if s.is_empty():
		return
	var delta: Vector2 = pos - s.origin
	s.vec = delta
	s.drag_dist = delta.length()
	router.external_move = true
	router.move_vector = _dir_from_vec(delta, s.radius)
	_overlay.queue_redraw()


func _physics_process(_delta: float) -> void:
	## external_move 是单帧消费语义：移动摇杆激活期间每帧重写，
	## 保证无新 drag 事件（手指静止）时键盘不覆盖 move_vector
	if router == null:
		return
	for k in _active:
		var s: Dictionary = _active[k]
		if s.kind == "move":
			router.external_move = true
			router.move_vector = _dir_from_vec(s.vec, s.radius)
			return


func _dir_from_vec(vec: Vector2, radius: float) -> Vector2:
	if vec.length() < DEAD_ZONE * radius:
		return Vector2.ZERO
	return vec.normalized()


func _inside_dash_button(pos: Vector2) -> bool:
	return _dash_button_rect().has_point(pos)


func _dash_button_rect() -> Rect2:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var top_left: Vector2 = vp - Vector2(DASH_SIZE + DASH_MARGIN, DASH_SIZE + DASH_MARGIN)
	return Rect2(top_left, Vector2(DASH_SIZE, DASH_SIZE))


func _hit_foreign_control(pos: Vector2) -> bool:
	## 触摸落在其它可交互 Control（HUD 按钮等）上时不抢事件
	var vp := get_viewport()
	if not vp.has_method("gui_get_control_at_position"):
		return false
	var ctl: Control = vp.gui_get_control_at_position(pos)
	return ctl != null and ctl != dash_button and ctl != _overlay


func _on_dash_pressed() -> void:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("request_dash"):
		p.request_dash()


## 程序化绘制层：底盘 = 半透明 PANEL 圆 + BORDER 圆环；摇杆头 = PANEL_LIGHT 圆 + GOLD 圆环
class JoystickOverlay extends Control:
	var host: CanvasLayer = null

	func _draw() -> void:
		if host == null:
			return
		for idx in host._active:
			var s: Dictionary = host._active[idx]
			var radius: float = s.radius
			var origin: Vector2 = s.origin
			var knob: Vector2 = origin + (s.vec as Vector2).limit_length(radius)
			var base := UiTheme.PANEL
			base.a = 0.58
			var ring := UiTheme.BORDER
			ring.a = 0.90
			draw_circle(origin, radius, base)
			draw_arc(origin, radius, 0.0, TAU, 48, ring, 2.0, true)
			var fill := UiTheme.PANEL_LIGHT
			fill.a = 0.95
			draw_circle(knob, host.KNOB_RADIUS, fill)
			draw_arc(knob, host.KNOB_RADIUS, 0.0, TAU, 32, UiTheme.GOLD, 2.0, true)
