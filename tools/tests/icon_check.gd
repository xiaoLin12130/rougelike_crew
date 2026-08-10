extends SceneTree
## 图标路径 ResourceLoader 双重核实（headless）
## Run: godot --headless --path . -s res://tools/tests/icon_check.gd

var _missing: Array[String] = []
var _total := 0

func _init() -> void:
	var files := [
		"res://data/items.json",
		"res://data/spells.json",
		"res://data/wands.json",
		"res://data/summons.json",
	]
	for f in files:
		var txt := FileAccess.get_file_as_string(f)
		if txt.is_empty():
			push_error("cannot read " + f)
			quit(1)
			return
		var data: Variant = JSON.parse_string(txt)
		_collect_icons(data)
	if _missing.is_empty():
		print("RESOURCE LOADER ICON CHECK OK (icons=", _total, ")")
		quit(0)
	else:
		for m in _missing:
			push_error("icon missing: " + m)
		quit(1)

func _collect_icons(node: Variant) -> void:
	if node is Dictionary:
		if node.has("icon") and typeof(node["icon"]) == TYPE_STRING:
			_total += 1
			if not ResourceLoader.exists(node["icon"]):
				_missing.append(str(node["icon"]))
		for v in node.values():
			_collect_icons(v)
	elif node is Array:
		for v in node:
			_collect_icons(v)
