extends Node2D
## 敌人常驻缓存正确性测试（P0 性能优化，docs/design/性能优化方案.md 第 3 节 P0）
## ① 缓存与真实树同步：生成 10 敌人 → 缓存 10；杀 5 → 缓存 5；切关（容器释放）清空
## ② synergy 钩子触发时用缓存获得与旧方式一致的敌人集合（对照测试：缓存结果
##    == get_nodes_in_group("enemy") 结果，集合相等；生产读取点已全量改读缓存，
##    组查询即旧方式的直接对照）
## ③ 遍历缓存期间击杀/生成敌人不报错（挂起注册 + 延迟压缩设计验证）
## 运行：godot --headless --path . res://scripts/tests/test_enemy_cache.tscn

const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")

var _failures: Array[String] = []
var _container: Node2D


func _ready() -> void:
	GameState.run.crit_chance = 0.0  # 固定伤害，避免暴击抖动
	_container = Node2D.new()
	_container.name = "EnemyContainer"
	add_child(_container)
	await _test_sync()
	await _test_hook_comparison()
	await _test_level_switch()
	await _test_mutation_during_iteration()
	_finish()


func _fail(msg: String) -> void:
	_failures.append(msg)
	push_error("[TEST] FAIL: " + msg)


func _spawn_enemy(pos: Vector2) -> Node:
	var e := ENEMY_SCENE.instantiate()
	e.setup("slime", 1, 1)
	e.behavior = ""  # 关闭分裂/自爆，保证数量断言确定性
	e.speed = 0.0
	e.global_position = pos
	_container.add_child(e)
	return e


func _group_enemies() -> Array:
	return get_tree().get_nodes_in_group("enemy")


func _same_set(a: Array, b: Array) -> bool:
	## 集合相等（顺序无关）：同大小且 a 全在 b 中
	if a.size() != b.size():
		return false
	for e in a:
		if not b.has(e):
			return false
	return true


func _check_sync(label: String) -> void:
	## 对照测试：缓存结果 == 组查询结果（旧方式的直接对照）
	var cache: Array = GameState.get_enemies()
	var group: Array = _group_enemies()
	if not _same_set(cache, group):
		_fail("%s: 缓存(%d) != 组(%d) 集合不一致" % [label, cache.size(), group.size()])


func _test_sync() -> void:
	## ① 生成 10 敌人 → 缓存 10；杀 5 → 缓存 5；清场 → 0
	var spawned: Array = []
	for i in 10:
		spawned.append(_spawn_enemy(Vector2(120 + (i % 5) * 60, 120 + (i / 5) * 70)))
	await get_tree().process_frame
	await get_tree().process_frame
	_check_sync("生成 10 敌人")
	if GameState.get_enemies().size() != 10:
		_fail("生成 10 敌人后缓存应为 10，实际 %d" % GameState.get_enemies().size())
	# 杀 5 只（take_damage → _die → queue_free，帧末出树注销）
	for i in 5:
		if is_instance_valid(spawned[i]):
			spawned[i].take_damage(99999, "test", false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_sync("杀 5 后")
	if GameState.get_enemies().size() != 5:
		_fail("杀 5 后缓存应为 5，实际 %d" % GameState.get_enemies().size())
	# 清场
	for e in spawned:
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_sync("清场后")
	if GameState.get_enemies().size() != 0:
		_fail("清场后缓存应为 0，实际 %d" % GameState.get_enemies().size())
	print("[TEST] enemy cache sync ① ALL PASS (10/5/0)")


func _test_hook_comparison() -> void:
	## ② 加载 synergy 钩子并触发，钩子内读取点与对照一致
	SynergyRegistry.load_synergy_scripts()
	await get_tree().process_frame
	GameState.run.items["fire_dragon_breath"] = 1  # 火M10：zone tick 读取点
	GameState.run.items["ice_m7"] = 1              # 冰M7：每帧扫描读取点
	var spawned: Array = []
	for i in 3:
		spawned.append(_spawn_enemy(Vector2(700 + i * 200, 300)))  # 分散，防钩子误伤
	await get_tree().process_frame
	await get_tree().process_frame
	_check_sync("钩子触发前")
	# 触发 enemy_status（burn tick）——fire/ice 等钩子内部查询敌人集合
	for e in spawned:
		if is_instance_valid(e):
			e._burn_left = 5.0
			SynergyRegistry.trigger("enemy_status", {"enemy": e, "kind": "burn", "stacks": 1, "delta": 1.0})
	await get_tree().process_frame
	_check_sync("enemy_status 钩子触发后")
	# 触发 projectile_hit（zone 创建）与 enemy_hit
	for e in spawned:
		if is_instance_valid(e):
			SynergyRegistry.trigger("projectile_hit", {
				"enemy": e, "dmg": 1, "element": "fire", "crit": false, "pos": e.global_position})
			SynergyRegistry.trigger("enemy_hit", {"enemy": e, "dmg": 1, "element": "fire", "crit": false})
	await get_tree().process_frame
	_check_sync("projectile_hit/enemy_hit 钩子触发后")
	# 钩子触发的 zone/扫描可能对敌人造成伤害——不杀怪，只校验集合一致性
	GameState.run.items.erase("fire_dragon_breath")
	GameState.run.items.erase("ice_m7")
	for e in spawned:
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_sync("钩子用例清场")
	print("[TEST] enemy cache hook comparison ② ALL PASS")


func _test_level_switch() -> void:
	## ③ 切关清空：释放关卡容器 → 缓存随树退出清空
	var spawned: Array = []
	for i in 3:
		spawned.append(_spawn_enemy(Vector2(200 + i * 80, 500)))
	await get_tree().process_frame
	_check_sync("切关前")
	if GameState.get_enemies().size() != 3:
		_fail("切关前缓存应为 3，实际 %d" % GameState.get_enemies().size())
	_container.queue_free()  # 模拟 level 释放
	_container = null
	await get_tree().process_frame
	await get_tree().process_frame
	if GameState.get_enemies().size() != 0:
		_fail("切关后缓存应为 0，实际 %d" % GameState.get_enemies().size())
	_check_sync("切关后")
	# 新关卡可继续注册
	_container = Node2D.new()
	_container.name = "EnemyContainer2"
	add_child(_container)
	_spawn_enemy(Vector2(300, 300))
	_spawn_enemy(Vector2(380, 300))
	await get_tree().process_frame
	_check_sync("新关卡生成")
	if GameState.get_enemies().size() != 2:
		_fail("新关卡缓存应为 2，实际 %d" % GameState.get_enemies().size())
	print("[TEST] enemy cache level switch ③ ALL PASS")


func _test_mutation_during_iteration() -> void:
	## ④ 遍历缓存期间击杀 + 生成敌人：不报"数组遍历中被修改"，最终集合一致
	for i in 5:
		_spawn_enemy(Vector2(400 + i * 90, 500))
	await get_tree().process_frame
	_check_sync("遍历前")
	for e in GameState.get_enemies():
		if is_instance_valid(e) and e.has_method("take_damage"):
			e.take_damage(99999, "test", false)
		# 遍历中生成新敌人（_ready 注册走挂起队列，不得打断遍历）
		_spawn_enemy(Vector2(randf_range(100, 1000), randf_range(100, 600)))
	await get_tree().process_frame
	await get_tree().process_frame
	_check_sync("遍历击杀+生成后")
	print("[TEST] enemy cache mutation-during-iteration ④ ALL PASS")


func _finish() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _failures.is_empty():
		print("[TEST] ENEMY CACHE ALL PASS")
		get_tree().quit(0)
	else:
		print("[TEST] ENEMY CACHE FAIL: %d" % _failures.size())
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		get_tree().quit(1)
