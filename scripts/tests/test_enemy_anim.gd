extends Node2D
## 怪物多帧动画测试（怪物帧动画落地任务）
## ① 旧怪（无 anims 字段）走原 frames 逻辑，不崩、只有 idle 动画
## ② 有 anims 的怪：idle/run 动画帧数与配置一致，帧纹理非空
## ③ 速度阈值切换：velocity > speed*0.4 切 run，否则 idle
## ④ flip_h：velocity.x<0 翻转，x>0 不翻转
## 运行：godot --headless --path . res://scripts/tests/test_enemy_anim.tscn

const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")

var _failures: Array[String] = []
var _container: Node2D


func _ready() -> void:
	_container = Node2D.new()
	_container.name = "AnimTestContainer"
	add_child(_container)
	await _test_old_path()
	await _test_anims_frames()
	await _test_state_switch()
	await _finish()


func _fail(msg: String) -> void:
	_failures.append(msg)
	push_error("[TEST] FAIL: " + msg)


func _spawn(eid: String) -> Node:
	var e := ENEMY_SCENE.instantiate()
	e.setup(eid, 1, 1)
	e.behavior = ""  # 关 AI，保证测试确定性
	e.speed = 0.0
	e.global_position = Vector2(300 + randi() % 600, 200 + randi() % 300)
	_container.add_child(e)
	return e


func _anim_of(e: Node) -> AnimatedSprite2D:
	return e.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func _test_old_path() -> void:
	## ① 无 anims 的旧怪：slime(3帧) / crystal_sentry(1帧)
	for eid in ["slime", "crystal_sentry"]:
		var e := _spawn(eid)
		await get_tree().process_frame
		await get_tree().process_frame
		var anim := _anim_of(e)
		if anim == null:
			_fail("%s: 无 AnimatedSprite2D" % eid)
			continue
		var sf := anim.sprite_frames
		# SpriteFrames 自带 "default" 槽；旧怪应只有 idle（无 run 等自定义动画）
		if not sf.has_animation("idle") or sf.has_animation("run"):
			_fail("%s: 旧怪应只有 idle 动画" % eid)
		if e.get("_has_anims") == true:
			_fail("%s: 旧怪不应启用 anims 路径" % eid)
		var expect := 3 if eid == "slime" else 1
		if sf.get_frame_count("idle") != expect:
			_fail("%s: idle 帧数应为 %d，实际 %d" % [eid, expect, sf.get_frame_count("idle")])
		if sf.get_frame_texture("idle", 0) == null:
			_fail("%s: idle 首帧纹理为空" % eid)
		# 旧怪 _update_anim 必须是安全 no-op（无 run 动画、不翻转）
		e.velocity = Vector2(500, 0)
		e._update_anim()
		if anim.animation != "idle" or anim.flip_h:
			_fail("%s: 旧怪动画状态被意外切换" % eid)
		e.queue_free()
		await get_tree().process_frame
	print("[TEST] old-path backward compat ① PASS")


func _test_anims_frames() -> void:
	## ② 遍历 enemies.json：anims 怪的帧数与配置一致
	var enemies: Array = GameState.tables.get("enemies", {}).get("enemies", [])
	var checked := 0
	for conf in enemies:
		var anims: Dictionary = conf.get("anims", {})
		if anims.is_empty():
			continue
		var eid := str(conf.get("id", ""))
		var e := _spawn(eid)
		await get_tree().process_frame
		await get_tree().process_frame
		var anim := _anim_of(e)
		if anim == null:
			_fail("%s: 无 AnimatedSprite2D" % eid)
			e.queue_free()
			continue
		var sf := anim.sprite_frames
		for name in anims:
			if not sf.has_animation(name):
				_fail("%s: 缺少动画 %s" % [eid, name])
				continue
			var spec: Dictionary = anims[name]
			var expect := int(spec.get("frames", 0))
			if sf.get_frame_count(name) != expect:
				_fail("%s.%s: 帧数应为 %d，实际 %d" % [eid, name, expect, sf.get_frame_count(name)])
			if sf.get_frame_count(name) > 0 and sf.get_frame_texture(name, 0) == null:
				_fail("%s.%s: 首帧纹理为空" % [eid, name])
			if sf.get_animation_speed(name) <= 0.0:
				_fail("%s.%s: FPS 非法 %f" % [eid, name, sf.get_animation_speed(name)])
		# 每怪帧数 >= 3（本次任务最低标准）
		if sf.has_animation("idle") and sf.get_frame_count("idle") < 3:
			_fail("%s: idle 帧数 < 3" % eid)
		checked += 1
		e.queue_free()
		await get_tree().process_frame
	if checked < 15:
		_fail("anims 怪数量异常少: %d" % checked)
	print("[TEST] anims frame counts ② PASS (%d enemies)" % checked)


func _test_state_switch() -> void:
	## ③④ boar：速度阈值切换 + flip_h
	var e := _spawn("boar")
	e.speed = 100.0
	await get_tree().process_frame
	await get_tree().process_frame
	var anim := _anim_of(e)
	if anim == null:
		_fail("boar: 无 AnimatedSprite2D")
		e.queue_free()
		return
	# 静止 -> idle
	e.velocity = Vector2.ZERO
	e._update_anim()
	if anim.animation != "idle":
		_fail("静止时应 idle，实际 " + anim.animation)
	# 速度 > speed*0.4 -> run
	e.velocity = Vector2(60, 0)
	e._update_anim()
	if anim.animation != "run":
		_fail("速度 60 > 40 时应 run，实际 " + anim.animation)
	# 低于阈值 -> idle
	e.velocity = Vector2(20, 0)
	e._update_anim()
	if anim.animation != "idle":
		_fail("速度 20 < 40 时应 idle，实际 " + anim.animation)
	# flip_h：向左
	e.velocity = Vector2(-100, 0)
	e._update_anim()
	if not anim.flip_h:
		_fail("向左移动时 flip_h 应为 true")
	if anim.animation != "run":
		_fail("向左快移时应 run，实际 " + anim.animation)
	# flip_h：向右
	e.velocity = Vector2(100, 0)
	e._update_anim()
	if anim.flip_h:
		_fail("向右移动时 flip_h 应为 false")
	# 有 run 的 Pixel Crawler 怪同样可用
	var e2 := _spawn("shadow_stalker")
	e2.speed = 100.0
	await get_tree().process_frame
	var anim2 := _anim_of(e2)
	if anim2 != null and anim2.sprite_frames.has_animation("run"):
		e2.velocity = Vector2(-80, 0)
		e2._update_anim()
		if anim2.animation != "run" or not anim2.flip_h:
			_fail("shadow_stalker: run/flip_h 未生效")
	e2.queue_free()
	e.queue_free()
	print("[TEST] state switch + flip_h ③④ PASS")


func _finish() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _failures.is_empty():
		print("[TEST] ENEMY ANIM ALL PASS")
		get_tree().quit(0)
	else:
		print("[TEST] ENEMY ANIM FAIL: %d" % _failures.size())
		for f in _failures:
			push_error("[TEST] FAIL: " + f)
		get_tree().quit(1)
