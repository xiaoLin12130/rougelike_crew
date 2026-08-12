extends SceneTree
## 初始技能随机化单测（2026-08-12 需求）：
## 开局随机 2 个「核心×外壳」技能，30 次开局断言：
##  a) 每个技能核心/外壳均非空（无空技能、必带外壳）
##  b) 两个技能的流派（核心 element）必须不同
##  c) 核心/外壳 id 均存在于 data/spells.json
##  d) 组合经 _invalid_combo 校验有效
## 运行：godot --headless --path . -s res://scripts/tests/test_starter_spells.gd

var failures: Array[String] = []
var _frame := 0
var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _frame < 3:
		return false
	_done = true
	_run()
	if failures.is_empty():
		print("STARTER SPELLS TEST OK")
	else:
		for f in failures:
			push_error("STARTER SPELLS FAIL: " + f)
	quit(0 if failures.is_empty() else 1)
	return true

func fail(msg: String) -> void:
	failures.append(msg)

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		fail("GameState autoload missing")
		return
	var cores: Array = gs.tables.get("spells", {}).get("cores", [])
	var shells: Array = gs.tables.get("spells", {}).get("shells", [])
	if cores.is_empty() or shells.is_empty():
		fail("spells.json cores/shells 为空")
		return
	var core_by_id := {}
	var shell_by_id := {}
	for c in cores:
		core_by_id[str(c.get("id", ""))] = c
	for s in shells:
		shell_by_id[str(s.get("id", ""))] = s
	for i in 30:
		gs.new_run()
		var grid: Array = gs.run.get("grid", [])
		if grid.size() != 2:
			fail("第 %d 次开局 grid 数量 %d != 2" % [i, grid.size()])
			continue
		var els: Array = []
		for j in 2:
			var slot: Dictionary = grid[j]
			var cid: String = str(slot.get("core", ""))
			var sid: String = str(slot.get("shell", ""))
			if cid.is_empty():
				fail("第 %d 次开局第 %d 槽核心为空" % [i, j])
			if sid.is_empty():
				fail("第 %d 次开局第 %d 槽外壳为空（必带外壳）" % [i, j])
			if not core_by_id.has(cid):
				fail("第 %d 次开局核心 %s 不在 spells.json" % [i, cid])
				continue
			if not shell_by_id.has(sid):
				fail("第 %d 次开局外壳 %s 不在 spells.json" % [i, sid])
				continue
			var core: Dictionary = core_by_id[cid]
			var shell: Dictionary = shell_by_id[sid]
			els.append(str(core.get("element", "")))
			if gs._invalid_combo(core, shell):
				fail("第 %d 次开局组合无效：%s × %s" % [i, cid, sid])
		if els.size() == 2 and els[0] == els[1]:
			fail("第 %d 次开局两技能流派相同：%s == %s" % [i, els[0], els[1]])
	print("starter spell elements sampled: ok (30 runs)")
