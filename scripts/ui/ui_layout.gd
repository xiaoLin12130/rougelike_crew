class_name UiLayout
## 竖版 UI 布局工具（静态）：本轮所有 UI 以 360x640 逻辑坐标设计（Agent M1 将
## project.godot 视口切换为 360x640；本文件集中提供尺寸/安全区常量与竖版判断，
## 后续横竖自适应只需在此与各面板的锚点处调整，UI 脚本内尽量少用魔法数字）。
##
## 依据（H:\ai-playbook\ui-rag）：
##  - 触控目标 >= 44x44（touch_min），按钮放拇指可达区（屏幕下半部）；
##  - 手机 UI 低信息密度：HUD 只留战斗必须，次要信息折叠；
##  - 竖屏面板宽 <= 340（360 减去左右边距），避免横向滚动/超屏。

const DESIGN_W := 360.0  # 竖版逻辑视口宽（设计基准）
const DESIGN_H := 640.0  # 竖版逻辑视口高（设计基准）

const SAFE_TOP := 0.0    # 顶部安全区：Web 端无刘海；原生手机刘海屏适配时改 24
const SAFE_BOTTOM := 24.0  # 底部安全区：web 手机浏览器地址栏 / Home 指示条遮挡
const TOUCH_MIN := 44.0    # 触控目标最小尺寸（>= 44x44）
const PANEL_MAX_W := 340.0 # 竖版面板最大宽度（360 - 2*10 边距）
const PANEL_W := 320.0     # 标准面板宽度（留 20px 左右边距）
const PANEL_H := 520.0     # 标准面板高度（640 - 2*60，含上下安全区余量）

static var _portrait_override := -1  # 测试钩子：-1=自动，0=横屏，1=竖屏

static func is_portrait() -> bool:
	## 预留接口：判断当前视口是否为竖版（宽高比 <1）。
	## 本轮全部 UI 按竖版设计（不分支）；横竖自适应时在各面板此处取分支。
	if _portrait_override >= 0:
		return _portrait_override == 1
	var ws := DisplayServer.window_get_size()
	if ws.x > 0 and ws.y > 0:
		return ws.x < ws.y
	return true  # 无窗口上下文（headless 早期帧）→ 按设计基准竖版

static func force_portrait(v: bool) -> void:
	## 测试钩子：headless 下强制竖版判断（避免依赖窗口尺寸）。
	_portrait_override = 1 if v else 0

static func viewport_size() -> Vector2:
	## 实时逻辑视口尺寸：expand 下随窗口变化（竖屏手机 390x844 → ≈360x779）；
	## headless 测试通过设置 root.size 模拟。取不到时回退设计基准。
	var st := Engine.get_main_loop() as SceneTree
	if st != null and st.root != null:
		var s := st.root.get_visible_rect().size
		if s.x > 0.0 and s.y > 0.0:
			return s
	return Vector2(DESIGN_W, DESIGN_H)

static func safe_top() -> float:
	return SAFE_TOP

static func safe_bottom() -> float:
	return SAFE_BOTTOM

static func touch_min() -> float:
	return TOUCH_MIN

static func panel_w() -> float:
	return PANEL_W

static func panel_h() -> float:
	return PANEL_H

static func center_panel(panel: Control, w: float, h: float) -> void:
	## 面板锚 CENTER 且对称偏移：UiTheme.style 内容边距左右 10 / 上下 6，
	## 面板最小尺寸（内容+边距）成长后仍严格居中——expand 下视口变高时
	## 面板保持水平居中，任何屏幕比例不贴边、不越界。
	## 垂直在居中基础上让出 6px 顶部（样式上边距）：大面板顶缘恰在 y=50，
	## 不与顶部 HUD 波次横幅（y<=50）重叠，与既有设计位置完全一致。
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var hw := (w + 20.0) / 2.0  # 左右内容边距 10+10
	var hh := (h + 12.0) / 2.0  # 上下内容边距 6+6
	panel.offset_left = -hw
	panel.offset_right = hw
	panel.offset_top = -hh + 6.0
	panel.offset_bottom = hh + 6.0
