extends SceneTree
## 连杀落雷门控回归测试（2026-08-12 二次修复 P0-4，docs/design/落雷与音效二次修复报告.md）
## 断言：
## ① 2 秒内 6 连杀触发慢动作时，无雷系 holdings 不发 lightning 特效（改发 gold）；
## ② 持有雷系物品后同条件恢复 lightning（正向对照）。
## Run: godot --headless --path . -s res://scripts/tests/test_no_lightning_leak2.gd

var failures: Array[String] = []
var _frame := 0
var _phase := 0
var _emitted: Array[String] = []  # EventBus.fx_explosion 记录的 kind
var _slow_mo_count := 0

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	match _phase:
		0:
			(root.get_node("EventBus") as Node).fx_explosion.connect(_on_fx_kind)
			(root.get_node("EventBus") as Node).slow_mo.connect(_on_slow_mo)
			_test_kill_streak_gate()
			_phase = 1
		1:
			if failures.is_empty():
				print("NO LIGHTNING LEAK2 ALL PASS")
			else:
				for f in failures:
					push_error("NO LIGHTNING LEAK2 FAIL: " + f)
			quit(0 if failures.is_empty() else 1)
			return true
	return false

func fail(msg: String) -> void:
	failures.append(msg)
	print("[FAIL] " + msg)

func _on_fx_kind(_pos: Vector2, kind: String) -> void:
	_emitted.append(kind)

func _on_slow_mo(_factor: float, _duration: float) -> void:
	_slow_mo_count += 1

func _test_kill_streak_gate() -> void:
	var gs := root.get_node_or_null("GameState")
	if gs == null:
		fail("GameState autoload missing")
		return
	gs.new_run()
	gs.run.items = {}  # 显式清空构筑，确保无雷
	gs.run.grid = []
	## 运行时 load（非 preload）：-s 启动期 autoload 全局未注册时 preload 会编译失败
	var fx_script: GDScript = load("res://scripts/fx/fx_manager.gd")
	if fx_script == null:
		fail("fx_manager.gd 加载失败")
		return
	var fx: Node = fx_script.new()
	fx.name = "FxKillStreakTest"
	root.add_child(fx)
	## ① 无雷系：2 秒内 6 连杀 → 慢动作触发 + 只发 gold 不发 lightning
	_emitted.clear()
	_slow_mo_count = 0
	for i in 6:
		fx._on_enemy_died("e%d" % i, Vector2(100 + i * 10, 200), 1, 1, false)
	if _slow_mo_count == 0:
		fail("6 连杀应触发慢动作（slow_mo 信号），实际 %d 次" % _slow_mo_count)
	if "lightning" in _emitted:
		fail("无雷系构筑时连杀庆祝仍发出 lightning 特效: %s" % str(_emitted))
	if "gold" not in _emitted:
		fail("无雷系构筑时连杀庆祝应发 gold 特效: %s" % str(_emitted))
	## ② 正向对照：持有雷系 → 恢复 lightning
	gs.run.items = {"thunder_1": 1}
	gs.run.grid = []
	if int(gs.school_holdings().get("lightning", 0)) <= 0:
		fail("thunder_1 应计入 lightning holdings")
	_emitted.clear()
	for i in 6:
		fx._on_enemy_died("f%d" % i, Vector2(200 + i * 10, 300), 1, 1, false)
	if "lightning" not in _emitted:
		fail("持有雷系后连杀庆祝应恢复 lightning 特效: %s" % str(_emitted))
	fx.free()
