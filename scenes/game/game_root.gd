extends Node2D
## 游戏流程中枢：关卡推进 / 掉落 / 升级三选一 / 抉择循环 / 结算

const LEVEL_SCENE := "res://scenes/game/level.tscn"
const PLAYER_SCENE := "res://scenes/game/player.tscn"
const CAMERA_SCENE := "res://scenes/game/camera.tscn"
const HUD_SCENE := "res://scenes/ui/hud.tscn"
const BUILD_PANEL_SCENE := "res://scenes/ui/build_panel.tscn"
const LEVELUP_SCENE := "res://scenes/ui/levelup_overlay.tscn"
const LOOP_CHOICE_SCENE := "res://scenes/ui/loop_choice.tscn"
const GAME_OVER_SCENE := "res://scenes/ui/game_over.tscn"
const PAUSE_SCENE := "res://scenes/ui/pause_menu.tscn"

var player: Node2D
var camera: Camera2D
var level_node: Node2D
var hud: CanvasLayer
var build_panel: CanvasLayer
var levelup_overlay: CanvasLayer
var loop_choice: CanvasLayer
var game_over: CanvasLayer
var pause_menu: CanvasLayer
var fx_manager: Node

var _prev_level := 1
var _levelup_queue := 0
var _hit_protect := 0.0

func _ready() -> void:
	randomize()
	GameState.apply_item_effects_to_stats()
	if "--auto-play" in OS.get_cmdline_user_args():
		var ap: Node = load("res://scripts/tests/auto_play.gd").new()
		ap.name = "AutoPlay"
		add_child(ap)
	_spawn_ui()
	_spawn_camera()
	_start_level()
	EventBus.player_hit.connect(_on_player_hit)
	EventBus.player_died.connect(_on_player_died)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.level_cleared.connect(_on_level_cleared)
	EventBus.loop_choice.connect(_on_loop_choice)
	# 自动存档：每 10 秒 + 切关时（中途退出可在暂停菜单保存后回主菜单）
	var save_timer := Timer.new()
	save_timer.wait_time = 10.0
	save_timer.timeout.connect(_autosave)
	add_child(save_timer)
	save_timer.start()

func _autosave() -> void:
	SaveStore.save_run(GameState.run)

func _process(delta: float) -> void:
	if not get_tree().paused:
		GameState.run.time += delta
		GameState.run.level_elapsed = GameState.run.get("level_elapsed", 0.0) + delta
	_hit_protect = maxf(_hit_protect - delta, 0.0)
	_check_levelup()
	if Input.is_action_just_pressed("pause"):
		_toggle_pause()

func _spawn_ui() -> void:
	fx_manager = load("res://scripts/fx/fx_manager.gd").new()
	fx_manager.name = "FxManager"
	add_child(fx_manager)
	hud = load(HUD_SCENE).instantiate()
	hud.name = "HUD"
	add_child(hud)
	build_panel = load(BUILD_PANEL_SCENE).instantiate()
	build_panel.name = "BuildPanel"
	build_panel.hide()
	add_child(build_panel)
	levelup_overlay = load(LEVELUP_SCENE).instantiate()
	levelup_overlay.name = "LevelUpOverlay"
	levelup_overlay.hide()
	add_child(levelup_overlay)
	loop_choice = load(LOOP_CHOICE_SCENE).instantiate()
	loop_choice.name = "LoopChoice"
	loop_choice.hide()
	add_child(loop_choice)
	game_over = load(GAME_OVER_SCENE).instantiate()
	game_over.name = "GameOver"
	game_over.hide()
	add_child(game_over)
	pause_menu = load(PAUSE_SCENE).instantiate()
	pause_menu.name = "PauseMenu"
	pause_menu.hide()
	add_child(pause_menu)

func _spawn_camera() -> void:
	camera = load(CAMERA_SCENE).instantiate()
	add_child(camera)

func _start_level() -> void:
	if level_node:
		level_node.queue_free()
	if player == null or not is_instance_valid(player):
		player = load(PLAYER_SCENE).instantiate()
		add_child(player)
	player.position = GameState.MAP_SIZE / 2.0  # 复用同一玩家，切关不再产生"第二个玩家"
	if camera:
		camera.global_position = player.position  # 开局瞬间对准，避免从角落滑入
	level_node = load(LEVEL_SCENE).instantiate()
	var levels: Array = GameState.tables.get("levels", {}).get("levels", [])
	var idx: int = clampi(GameState.run.level - 1, 0, levels.size() - 1)
	var level_id: String = str(levels[idx].get("id", "level_1"))
	level_node.init_level(level_id)
	add_child(level_node)
	GameState.run.hp = GameState.run.max_hp
	GameState.run.level_elapsed = 0.0
	EventBus.player_stats_changed.emit()

func _check_levelup() -> void:
	if GameState.run.player_level > _prev_level:
		_levelup_queue += 1
		_prev_level = GameState.run.player_level
		if not levelup_overlay.visible:
			_show_levelup()

func _show_levelup() -> void:
	if _levelup_queue <= 0:
		return
	get_tree().paused = true
	var choices: Array = GameState.roll_item_choices(3)
	levelup_overlay.show_choices(choices)
	levelup_overlay.show()
	if not levelup_overlay.choice_made.is_connected(_on_choice_made):
		levelup_overlay.choice_made.connect(_on_choice_made)

func _on_choice_made(item_id: String) -> void:
	GameState.add_item(item_id)
	GameState.apply_item_effects_to_stats()
	levelup_overlay.hide()
	_levelup_queue -= 1
	get_tree().paused = false
	if _levelup_queue > 0:
		_show_levelup()

func _on_enemy_died(enemy_id: String, pos: Vector2, xp: int, gold: int) -> void:
	GameState.run.kills += 1
	var xp_mult := 1.0 + GameState.aggregate_bonus("xp")
	var gold_mult := 1.0 + GameState.aggregate_bonus("gold")
	GameState.add_xp(int(xp * xp_mult))
	GameState.add_gold(int(gold * gold_mult))
	_roll_drop(pos)
	EventBus.fx_explosion.emit(pos, "blade")

func _roll_drop(pos: Vector2) -> void:
	var drops: Dictionary = GameState.tables.get("drops", {})
	var kill_drops: Array = drops.get("kill_drops", [])
	var total := 0.0
	for d in kill_drops:
		total += d.get("prob", 0.0)
	var roll := randf() * total
	var acc := 0.0
	var kind := "gold"
	for d in kill_drops:
		acc += d.get("prob", 0.0)
		if roll <= acc:
			kind = d.get("type", "gold")
			break
	# 保底：连续无道具则必掉道具
	var pity: int = drops.get("pity_threshold", 8)
	if GameState.run.pity >= pity and kind != "item":
		kind = "item"
		GameState.run.pity = 0
	match kind:
		"item":
			GameState.add_item(_roll_random_item())
			GameState.run.pity = 0
		"spell_part":
			GameState.add_spell_part(_roll_core(), _roll_shell())
			GameState.run.pity = 0
		"trinket":
			GameState.add_trinket(_roll_trinket())
			GameState.run.pity = 0
		"heal":
			GameState.run.hp = mini(GameState.run.max_hp, GameState.run.hp + 18)
			EventBus.fx_explosion.emit(pos, "ice")
			GameState.run.pity = 0
		_:
			GameState.run.pity += 1

func _roll_random_item() -> String:
	var pool: Array = GameState.tables.get("items", {}).get("items", []).filter(
		func(it): return it.get("type", "") == "item"
	)
	return _weighted_pick(pool)

func _roll_trinket() -> String:
	var pool: Array = GameState.tables.get("items", {}).get("items", []).filter(
		func(it): return it.get("type", "") == "trinket"
	)
	return _weighted_pick(pool)

func _weighted_pick(pool: Array) -> String:
	if pool.is_empty():
		return ""
	var weights: Dictionary = GameState.tables.get("drops", {}).get("item_rarity_weights", {})
	var total := 0.0
	for it in pool:
		total += weights.get(it.get("rarity", "common"), 0.2)
	var roll := randf() * total
	var acc := 0.0
	for it in pool:
		acc += weights.get(it.get("rarity", "common"), 0.2)
		if roll <= acc:
			return it.get("id", "")
	return pool[pool.size() - 1].get("id", "")

func _roll_core() -> String:
	var cores: Array = GameState.tables.get("spells", {}).get("cores", [])
	if cores.is_empty():
		return ""
	return cores[randi() % cores.size()].get("id", "")

func _roll_shell() -> String:
	var shells: Array = GameState.tables.get("spells", {}).get("shells", [])
	if shells.is_empty():
		return ""
	return shells[randi() % shells.size()].get("id", "")

func _on_player_hit(dmg: int, pos: Vector2) -> void:
	# 受击保护：0.5s 内不再受伤（防围殴秒杀，类 VS 受击无敌帧）
	if _hit_protect > 0.0:
		return
	_hit_protect = 0.5
	# 免疫判定（荆棘甲/守护护盾独立概率）
	var thorn := GameState.item_value(
		{"curve": {"type": "exp_proc", "base": 0.10, "p": 0.10}},
		GameState.total_stacks("thorn_armor")
	)
	var guard := GameState.item_value(
		{"curve": {"type": "exp_proc", "base": 0.30, "p": 0.30, "cap": 0.90}},
		GameState.total_stacks("guard_shield")
	)
	if randf() < maxf(thorn, guard):
		return
	var taken := float(dmg)
	taken *= 1.0 + 0.15 * GameState.total_stacks("curse_ring")
	GameState.run.hp = int(maxf(GameState.run.hp - taken, 0))
	EventBus.player_stats_changed.emit()
	EventBus.screen_shake.emit(4.0)
	EventBus.fx_hit_flash.emit(player)
	# 受击视觉：玩家短暂闪烁
	if player:
		var tw := create_tween()
		tw.tween_property(player, "modulate", Color(1, 0.4, 0.4, 1), 0.05)
		tw.tween_property(player, "modulate", Color.WHITE, 0.45)
	if GameState.run.hp <= 0:
		EventBus.player_died.emit()

func _on_player_died() -> void:
	get_tree().paused = true
	game_over.show_result(false, GameState.run.duplicate())
	game_over.show()

func _on_level_cleared(_level_id: String) -> void:
	SaveStore.save_run(GameState.run)  # 切关即存档
	if GameState.run.get("final_boss_mode", false):
		get_tree().paused = true
		game_over.show_result(true, GameState.run.duplicate())
		game_over.show()
		return
	# 过关回血 40%（战斗间隙的喘息奖励）
	GameState.run.hp = mini(GameState.run.max_hp, GameState.run.hp + int(GameState.run.max_hp * 0.4))
	EventBus.player_stats_changed.emit()
	var level: int = GameState.run.level
	var max_level: int = GameState.tables.get("levels", {}).get("levels", []).size()
	if level >= max_level:
		loop_choice.show()
	else:
		GameState.run.level += 1
		EventBus.fx_explosion.emit(Vector2(320, 180), "lightning")
		_start_level()

func _on_loop_choice(choice: String) -> void:
	loop_choice.hide()
	if choice == "boss":
		GameState.run.final_boss_mode = true
		GameState.run.level = max_level_index()
		EventBus.fx_explosion.emit(Vector2(320, 180), "fire")
		_start_level()
	else:
		GameState.run.loop += 1
		GameState.run.level = 1
		EventBus.fx_explosion.emit(Vector2(320, 180), "ice")
		_start_level()

func max_level_index() -> int:
	return GameState.tables.get("levels", {}).get("levels", []).size()

func _toggle_pause() -> void:
	if game_over.visible or loop_choice.visible or levelup_overlay.visible:
		return
	get_tree().paused = not get_tree().paused
	pause_menu.visible = get_tree().paused
