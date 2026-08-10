extends Node
## 存档抽象层：File / Web(IndexedDB) / Wx 三实现，DEMO 用 File

const SAVE_PATH := "user://save.json"
## 图鉴收集档案（跨局持久化，与局内存档分离——删档不清除收集进度）
const COLLECTION_PATH := "user://collection.json"

func save_run(run_data: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(run_data))

func load_run() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func clear_save() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

## ===== 图鉴收集档案（P3，只增不改既有接口）=====
## 结构：{"version": 1, "categories": {"items": [...], "wands": [...], ...}}
## categories 由 GameState 统一维护（mark_collected/collection_of），SaveStore 只负责落盘。

func save_collection(collection: Dictionary) -> void:
	var f := FileAccess.open(COLLECTION_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": 1, "categories": collection}))

func load_collection() -> Dictionary:
	## 返回原始档案字典（含 version/categories 包装）；不存在或损坏时返回 {}
	if not FileAccess.file_exists(COLLECTION_PATH):
		return {}
	var f := FileAccess.open(COLLECTION_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func clear_collection() -> void:
	## 仅测试/调试用：物理删除收集档案（不经过 GameState）
	DirAccess.remove_absolute(ProjectSettings.globalize_path(COLLECTION_PATH))
