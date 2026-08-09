extends SceneTree
## 敌人精灵回归测试：验证全部敌人（含 Retro-Lines 新 4 种 + Kenney slime）的
## sprite 路径可加载、帧数正确、帧 PNG 存在且尺寸合法。
## Run: godot --headless --path . -s res://scripts/tests/enemy_sprite_test.gd

var failures: Array[String] = []
var _frame := 0

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var gs := root.get_node("GameState")
	var enemies: Array = gs.tables.get("enemies", {}).get("enemies", [])
	var all: Array = enemies.duplicate()
	all.append_array(gs.tables.get("enemies", {}).get("bosses", []))
	for e in all:
		var base: String = str(e.get("sprite", ""))
		var frames: int = int(e.get("frames", 1))
		if base.is_empty() or not ResourceLoader.exists(base):
			fail("%s: 基础精灵不存在 %s" % [e.get("id", "?"), base])
			continue
		for i in frames:
			var p := base.replace("_1.png", "_%d.png" % (i + 1)) if frames > 1 else base
			if not ResourceLoader.exists(p):
				fail("%s: 帧缺失 %s" % [e.get("id", "?"), p])
				continue
			var tex: Texture2D = load(p)
			if tex == null:
				fail("%s: 帧加载失败 %s" % [e.get("id", "?"), p])
			elif tex.get_width() <= 0 or tex.get_height() <= 0:
				fail("%s: 帧尺寸非法 %s %dx%d" % [e.get("id", "?"), p, tex.get_width(), tex.get_height()])
	if failures.is_empty():
		print("ENEMY SPRITES OK (%d entities)" % all.size())
	else:
		for f in failures:
			push_error("SPRITE FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true

func fail(msg: String) -> void:
	failures.append(msg)
