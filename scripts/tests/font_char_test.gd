extends SceneTree
## 字体字形验证：检查 Godot 导入后的 FontFile 是否包含指定字形（与 Web 运行时同路径）。
## Run: godot --headless --path . -s res://scripts/tests/font_char_test.gd

func _init() -> void:
	print("STEP1 loading font...")
	var font: Font = load("res://assets/fonts/LXGWWenKai_subset.ttf")
	if font == null:
		print("FONT LOAD FAILED")
		quit(1)
		return
	print("STEP2 loaded, checking glyphs...")
	var text := "法术构筑·割草·雨中冒险式抉择秘法残卷开始继续退出"
	var missing := []
	for ch in text:
		if not font.has_char(ch.unicode_at(0)):
			missing.append("%s(U+%04X)" % [ch, ch.unicode_at(0)])
	print("STEP3 done")
	print("FONT GLYPHS: total_has=%d missing=%s" % [text.length() - missing.size(), str(missing)])
	var has_data: bool = font.get_data().data.size() > 0
	print("FONT FILE has data: ", has_data)
	quit(0 if missing.is_empty() else 1)
