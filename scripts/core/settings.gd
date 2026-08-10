extends Node
## 全局玩家设置（2026-08-10）：视角缩放等，持久化到 user://settings.json

const SETTINGS_PATH := "user://settings.json"
const ZOOM_MIN := 0.7
const ZOOM_MAX := 1.8
const ZOOM_PORTRAIT_DEFAULT := 1.3   # 手机（竖屏）默认视角
const ZOOM_LANDSCAPE_DEFAULT := 1.8  # PC（横屏）默认视角

var camera_zoom_portrait: float = ZOOM_PORTRAIT_DEFAULT
var camera_zoom_landscape: float = ZOOM_LANDSCAPE_DEFAULT

func _ready() -> void:
	load_settings()

func set_camera_zoom(v: float, portrait: bool) -> void:
	## 按当前横竖屏写入对应视角档位（手机/PC 各自记忆）
	if portrait:
		camera_zoom_portrait = clampf(v, ZOOM_MIN, ZOOM_MAX)
	else:
		camera_zoom_landscape = clampf(v, ZOOM_MIN, ZOOM_MAX)
	save_settings()
	# 通知相机实时应用
	var cam := get_tree().get_first_node_in_group("camera")
	if is_instance_valid(cam) and cam.has_method("_apply_orientation_zoom"):
		cam.call("_apply_orientation_zoom")

func current_zoom(portrait: bool) -> float:
	return camera_zoom_portrait if portrait else camera_zoom_landscape

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		camera_zoom_portrait = clampf(float(parsed.get("camera_zoom_portrait", ZOOM_PORTRAIT_DEFAULT)), ZOOM_MIN, ZOOM_MAX)
		camera_zoom_landscape = clampf(float(parsed.get("camera_zoom_landscape", ZOOM_LANDSCAPE_DEFAULT)), ZOOM_MIN, ZOOM_MAX)

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"camera_zoom_portrait": camera_zoom_portrait,
			"camera_zoom_landscape": camera_zoom_landscape,
		}))
