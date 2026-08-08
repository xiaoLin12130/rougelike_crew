extends Node
## 自动通关脚本：headless 下驱动玩家（风筝走位 + 自动攻击 + 自动升级/抉择）
## 运行：godot --headless --path . res://scenes/game/game_root.tscn -- --auto-play
## 退出码：0=通关 1=失败 2=超时

var _dash_pressed := false
var _frames := 0
var _last_report := 0.0
var _log: FileAccess
var _last_heartbeat := 0.0
var _frames_total := 0
static var _instances := 0

func _log_line(msg: String) -> void:
	var exists := FileAccess.file_exists("H:/rougelike_crew/.tools/autoplay_run.log")
	var f := FileAccess.open("H:/rougelike_crew/.tools/autoplay_run.log",
		FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(msg)
		f.flush()
		f.close()
	print(msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 树暂停（升级三选一）时驱动仍然存活
	_instances += 1
	print("[AUTOPLAY] started")
	_log_line("[AUTOPLAY] started instances=%d" % _instances)

func _process(_delta: float) -> void:
	_frames += 1
	_frames_total += 1
	# 自愈：暂停但无任何覆盖层 → 强制恢复
	if get_tree().paused:
		var scene := get_tree().current_scene
		var any_ui := false
		if scene:
			for n in ["LevelUpOverlay", "LoopChoice", "GameOver", "PauseMenu"]:
				var node := scene.get_node_or_null(n)
				if node and node.visible:
					any_ui = true
					break
		if not any_ui:
			get_tree().paused = false
			_log_line("[AUTOPLAY] self-heal unpause")
	# 心跳：每 1 秒游戏时间写一次（含暂停/帧数）
	if GameState.run.time - _last_heartbeat >= 1.0:
		_last_heartbeat = GameState.run.time
		_log_line("[HB] t=%.1f paused=%s frames=%d fps_now=%d hp=%d kills=%d" % [
			GameState.run.time, get_tree().paused, _frames_total, _frames, GameState.run.hp, GameState.run.kills])
		_frames = 0
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _handle_overlays(scene):
		return
	if GameState.run.time > 1500.0:
		print("[AUTOPLAY] TIMEOUT kills=", GameState.run.kills, " level=", GameState.run.level)
		_log_line("[AUTOPLAY] TIMEOUT kills=%d level=%d" % [GameState.run.kills, GameState.run.level])
		get_tree().quit(2)
		return
	_drive_player()
	if GameState.run.time - _last_report > 5.0:
		_last_report = GameState.run.time
		var enemies := get_tree().get_nodes_in_group("enemy")
		var kinds := {}
		for e in enemies:
			if is_instance_valid(e) and e.has_method("get_enemy_id"):
				var kid: String = e.get_enemy_id()
				kinds[kid] = kinds.get(kid, 0) + 1
		_log_line("[AUTOPLAY] t=%d hp=%d lv=%d kills=%d enemies=%d dps=%d grid=%d items=%d" % [
			int(GameState.run.time), GameState.run.hp, GameState.run.player_level,
			GameState.run.kills, enemies.size(), int(GameState.estimate_dps()),
			GameState.run.grid.size(), GameState.run.items.size()])
		_log_line("[KINDS] " + str(kinds))

func _handle_overlays(scene: Node) -> bool:
	var lv := scene.get_node_or_null("LevelUpOverlay")
	if lv and lv.visible and not lv.current_choices.is_empty():
		var best: Dictionary = lv.current_choices[0]
		for c in lv.current_choices:
			if _choice_score(c) > _choice_score(best):
				best = c
		lv.choice_made.emit(str(best.get("id", "")))
		print("[AUTOPLAY] levelup -> ", best.get("name", "?"))
		_log_line("[AUTOPLAY] levelup -> %s" % best.get("name", "?"))
		return true
	var lc := scene.get_node_or_null("LoopChoice")
	if lc and lc.visible:
		if GameState.run.loop < 1:
			EventBus.loop_choice.emit("loop")
			print("[AUTOPLAY] loop farm -> loop=", GameState.run.loop + 1)
			_log_line("[AUTOPLAY] loop farm -> loop=%d" % (GameState.run.loop + 1))
		else:
			EventBus.loop_choice.emit("boss")
			print("[AUTOPLAY] final boss now")
			_log_line("[AUTOPLAY] final boss now")
		return true
	var go := scene.get_node_or_null("GameOver")
	if go and go.visible:
		var win: bool = GameState.run.hp > 0
		print("[AUTOPLAY] RESULT=", "VICTORY" if win else "DEFEAT",
			" kills=", GameState.run.kills, " time=", int(GameState.run.time),
			" loop=", GameState.run.loop, " level=", GameState.run.level,
			" hp=", GameState.run.hp, " gold=", GameState.run.gold)
		_log_line("[AUTOPLAY] RESULT=%s kills=%d time=%d loop=%d level=%d hp=%d gold=%d" % [
			"VICTORY" if win else "DEFEAT", GameState.run.kills, int(GameState.run.time),
			GameState.run.loop, GameState.run.level, GameState.run.hp, GameState.run.gold])
		get_tree().quit(0 if win else 1)
		return true
	return false

func _rarity_score(c: Dictionary) -> int:
	match str(c.get("rarity", "common")):
		"legendary":
			return 3
		"rare":
			return 2
		_:
			return 1

func _choice_score(c: Dictionary) -> int:
	## 选道具策略：DPS 词条 > 吸血（低血时）> 稀有度 > 其他
	var score := _rarity_score(c) * 100
	var tags: Array = c.get("tags", [])
	for t in ["atk", "attack_speed", "crit", "crit_dmg", "cooldown", "area"]:
		if t in tags:
			score += 40
	if GameState.run.hp < GameState.run.max_hp * 0.4 and "lifesteal" in tags:
		score += 60
	if "summon" in tags:
		score += 25
	if "drawback" in tags and GameState.run.hp < GameState.run.max_hp * 0.5:
		score -= 80
	return score

func _drive_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var enemies := get_tree().get_nodes_in_group("enemy")
	var nearest: Node2D = null
	var nearest_dist := INF
	var ranged_target: Node2D = null
	var ranged_dist := INF
	var near_count := 0
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d: float = player.global_position.distance_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
		if e.has_method("is_ranged") and e.is_ranged() and d < ranged_dist:
			ranged_dist = d
			ranged_target = e
		if d < 90.0:
			near_count += 1
	var mv := Vector2.ZERO
	var aim := Vector2.RIGHT
	var aim_target := ranged_target if ranged_target != null else nearest
	if nearest == null:
		mv = (Vector2(320, 180) - player.global_position).normalized() * 0.5
	else:
		if aim_target != null:
			aim = (aim_target.global_position - player.global_position).normalized()
		# 敌群质心：从质心反方向逃跑，避免"逃离最近却被包围"
		var centroid := Vector2.ZERO
		var count := 0
		for e in enemies:
			if is_instance_valid(e) and player.global_position.distance_to(e.global_position) < 300.0:
				centroid += e.global_position
				count += 1
		var away: Vector2
		if count > 0:
			away = (player.global_position - centroid / count).normalized()
		else:
			away = (player.global_position - nearest.global_position).normalized()
		var side := Vector2(-away.y, away.x)
		if _frames % 120 < 60:
			side = -side
		var flee := 0.0
		var danger := 170.0
		if GameState.run.hp < 40:
			danger = 260.0  # 低血量 → 更早拉开距离
		var many_ranged: bool = ranged_target != null and enemies.size() >= 4
		if many_ranged and nearest_dist > 140.0:
			# 远程怪多 → 主动压向最近的远程怪（近战怪跟着跑，逐个解决）
			mv = (ranged_target.global_position - player.global_position).normalized() * 0.85
		elif nearest_dist > 240.0:
			# 远处没有威胁 → 去安全角落（离敌群最远的角），避免开局被合围
			var corner := _safe_corner(player.global_position, centroid, count)
			mv = (corner - player.global_position).normalized() * 0.9
			if enemies.size() <= 3:
				mv = (nearest.global_position - player.global_position).normalized() * 0.9  # 收尾：追击
		elif nearest_dist < danger:
			flee = 1.0 - nearest_dist / danger
			mv = away * flee * 0.9 + side * 0.55
		elif enemies.size() <= 2:
			# 收尾阶段：绕圈压近，避免与最后一只远程怪僵持
			mv = (nearest.global_position - player.global_position).normalized() * 0.6 + side * 0.5
		else:
			mv = side * 0.55  # 安全距离 → 环绕
	InputRouter.move_vector = mv.normalized() if mv.length_squared() > 0.01 else Vector2.ZERO
	InputRouter.aim_override = aim
	# 近身(≤70px)必闪；低血量时更积极
	var dash_now: bool = nearest_dist < 70.0 if nearest != null else false
	if GameState.run.hp < 40:
		dash_now = dash_now or near_count >= 1
	if dash_now and not _dash_pressed:
		Input.action_press("dash")
		_dash_pressed = true
	elif _dash_pressed:
		Input.action_release("dash")
		_dash_pressed = false

func _safe_corner(player_pos: Vector2, centroid: Vector2, count: int) -> Vector2:
	var corners := [Vector2(30, 30), Vector2(610, 30), Vector2(30, 330), Vector2(610, 330)]
	var best := Vector2(30, 30)
	var best_d := -INF
	var ref := centroid / maxi(count, 1)
	for c in corners:
		var d: float = ref.distance_to(c) + player_pos.distance_to(c) * 0.1
		if d > best_d:
			best_d = d
			best = c
	return best
