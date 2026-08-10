extends Node2D
## 复现诊断：升级三选一选法术 → 网格满 → 替换界面 → 点击替换 → 检查恢复
## 运行：godot --headless --path . res://scripts/tests/diag_replace2.tscn

var _gr: Node
var _fail := ""

func _ready() -> void:
	await get_tree().physics_frame
	var gs: Node = get_tree().root.get_node("GameState")
	gs.run.max_hp = 999999
	gs.run.hp = 999999
	_gr = load("res://scenes/game/game_root.tscn").instantiate()
	add_child(_gr)
	await _frames(30)
	# 填满法术网格（5 格），触发升级
	gs.run.grid = []
	for i in 5:
		gs.run.grid.append({"core": "fireball", "shell": "rapid"})
	gs.run.player_level = 2  # _prev_level 初始为 1 → 触发 _check_levelup
	await _frames(15)
	var lv: Node = _gr.get_node_or_null("LevelUpOverlay")
	if lv == null or not lv.visible:
		_fail = "升级面板未显示"
		_finish()
		return
	# 模拟玩家点击"新法术"卡片
	lv.choice_made.emit("spell_part:ice_shard:split")
	await _frames(15)
	var sr: Node = _gr.get_node_or_null("SpellReplace")
	if sr == null or not sr.visible:
		_fail = "替换界面未显示（点击法术卡片后）"
		_finish()
		return
	# 模拟玩家点击"替换第 0 格"（走真实按钮路径：_on_choose 会 hide + emit）
	print("[DIAG] emit choose_made(0)，当前连接数=%d" % sr.choose_made.get_connections().size())
	sr._on_choose(0)
	await _frames(6)
	print("[DIAG] emit 后 0.1s：paused=%s busy=%s" % [get_tree().paused, _gr.get("_choice_busy")])
	await _frames(30)
	print("[DIAG] emit 后 0.6s：paused=%s busy=%s" % [get_tree().paused, _gr.get("_choice_busy")])
	# 阶段A：0.5s 内应恢复（信号竞速）
	await _frames(30)
	var paused_a: bool = get_tree().paused
	var busy_a: bool = bool(_gr.get("_choice_busy"))
	var grid_a: Array = gs.run.grid.duplicate()
	# 阶段B：等到 9s（8s 超时兜底应恢复：放弃新法术）
	await _frames(540)
	gs = get_tree().root.get_node("GameState")
	sr = _gr.get_node_or_null("SpellReplace")
	lv = _gr.get_node_or_null("LevelUpOverlay")
	if get_tree().paused:
		_fail = "卡死：paused 未恢复（阶段A paused=%s busy=%s grid0=%s；9s后仍卡）" % [
			paused_a, busy_a, str(grid_a[0])]
	elif lv != null and lv.visible:
		_fail = "卡死：升级面板仍显示（阶段A paused=%s busy=%s）" % [paused_a, busy_a]
	elif sr != null and sr.visible:
		_fail = "卡死：替换面板仍显示（阶段A paused=%s busy=%s）" % [paused_a, busy_a]
	else:
		var slot: Dictionary = gs.run.grid[0]
		if str(slot.get("core", "")) != "ice_shard" or str(slot.get("shell", "")) != "split":
			_fail = "grid[0] 未被替换: %s（阶段A paused=%s busy=%s grid0=%s）" % [
				str(slot), paused_a, busy_a, str(grid_a[0])]
		elif bool(_gr.get("_choice_busy")):
			_fail = "_choice_busy 未复位（阶段A paused=%s）" % paused_a
	_finish()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _finish() -> void:
	if _fail == "":
		print("DIAG REPLACE2 OK")
	else:
		print("DIAG REPLACE2 FAIL: " + _fail)
	get_tree().quit(0 if _fail == "" else 1)
