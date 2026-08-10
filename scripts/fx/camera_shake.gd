extends Camera2D
## 相机：position_smoothing 跟随玩家；shake() 随机噪声震屏，0.15s 内衰减归零。
## 挂入组 "camera"，fx_manager 与战斗模块通过组查找调用。

const SHAKE_DURATION := 0.15
const MAX_SHAKE_POWER := 20.0
const SMOOTHING_SPEED := 7.0
const PORTRAIT_ZOOM := Vector2(1.15, 1.15)  # 视角放大（摄影机降低）：基准视口下画面放大 15%
const DESIGN_VIEW_H := 640.0  # 基准逻辑视口高（project.godot 设计分辨率 360x640）
var _arena_size := Vector2i(1280, 720)
var _viewport_size_override := Vector2.ZERO  # 测试钩子：headless 无法真正改窗口，注入视口尺寸

var _shake_tween: Tween

func _ready() -> void:
	add_to_group("camera")
	make_current()  # 激活本相机：否则视口不跟随，角色会跑出屏幕
	position_smoothing_enabled = true
	position_smoothing_speed = SMOOTHING_SPEED
	_arena_size = Vector2i(GameState.MAP_SIZE)
	limit_left = 0
	limit_top = 0
	limit_right = _arena_size.x
	limit_bottom = _arena_size.y
	_apply_orientation_zoom()
	# 窗口尺寸变化时重算 zoom（为后续横竖自适应预留；当前设计分辨率恒为竖版）
	get_viewport().size_changed.connect(_apply_orientation_zoom)

func is_portrait() -> bool:
	## 横竖屏判定（2026-08-10）：以实际窗口尺寸为准——
	## PC 横屏窗口 -> 横屏模式（地图高度填满视口，居中，四周窄黑边）；
	## 手机竖屏 -> 竖屏模式（保持原有适配）。测试钩子优先。
	if _viewport_size_override != Vector2.ZERO:
		return _viewport_size_override.x < _viewport_size_override.y
	var ws := DisplayServer.window_get_size()
	return ws.x < ws.y

func _viewport_size() -> Vector2:
	if _viewport_size_override != Vector2.ZERO:
		return _viewport_size_override
	return get_viewport_rect().size

func _apply_orientation_zoom() -> void:
	## 横竖屏 zoom 策略（2026-08-10）：
	## - 竖屏（手机）：zoom = PORTRAIT_ZOOM(1.0) x 640 / 视口高，ARENA 全高可见，
	##   玩家/怪物/技能放大（对比旧 0.72 提升 39%）。
	## - 横屏（PC）：zoom = 视口高 / 地图高(720)——地图高度恰好填满视口高，
	##   地图居中显示；横向超出（16:9 恰好、更宽屏裁切）由相机跟随覆盖；
	##   横向富余（超宽屏）两侧露出暗色底（level.gd 暗带/底板），即"四周黑边"。
	##   这样 PC 端地图占屏幕主体（背景大）、黑边窄、角色移动空间大。
	var vp: Vector2 = _viewport_size()
	if vp.y <= 0.0:
		vp.y = DESIGN_VIEW_H
	if is_portrait():
		zoom = PORTRAIT_ZOOM * (DESIGN_VIEW_H / vp.y) * _user_zoom()
	else:
		# 横屏（PC）：地图完整显示并四周留黑边（letterbox/pillarbox）——
		# zoom = min(视口宽/1280, 视口高/720) × 0.94，地图居中且四周有明确黑色边框，
		# 黑色区域小（约 5%）、地图主体大、角色移动空间大。
		var map_w := float(_arena_size.x)
		var map_h := float(_arena_size.y)
		zoom = Vector2.ONE * maxf(minf(vp.x / map_w, vp.y / map_h) * 1.15 * _user_zoom(), 0.05)

func _user_zoom() -> float:
	## 玩家设置视角缩放（Settings autoload）：按当前横竖屏取对应档位
	if Settings != null:
		return float(Settings.current_zoom(is_portrait()))
	return 1.0

func _physics_process(_delta: float) -> void:
	## 相机跟随（官方做法）：物理帧设置 position，position_smoothing 自动缓动；
	## 不使用 _process 硬设 global_position（会与 smoothing 冲突导致画面抖动/世界滑动）。
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		position = player.position
	# 无玩家时保持当前位置静止

func snap_to_player() -> void:
	## 开局/切关立即对准玩家（跳过 smoothing，避免从角落滑入）
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		position = player.position
		reset_smoothing()

func shake(power: float) -> void:
	var p := clampf(power, 0.0, MAX_SHAKE_POWER)
	if p <= 0.0:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_method(_apply_shake_offset, p, 0.0, SHAKE_DURATION)
	_shake_tween.tween_callback(_stop_shake)

func _apply_shake_offset(amount: float) -> void:
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount

func _stop_shake() -> void:
	offset = Vector2.ZERO
