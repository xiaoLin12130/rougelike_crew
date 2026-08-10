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
const HEALTH_PACK_SCENE := "res://scenes/game/health_pack.tscn"
const WAND_SHOP_SCENE := "res://scenes/ui/wand_shop.tscn"
const SPELL_REPLACE_SCENE := "res://scenes/ui/spell_replace.tscn"
const ITEM_PICKUP_SCENE := "res://scenes/game/item_pickup.tscn"
const JOYSTICK_SCRIPT := "res://scripts/ui/game/virtual_joystick.gd"

var player: Node2D
var camera: Camera2D
var level_node: Node2D
var hud: CanvasLayer
var build_panel: CanvasLayer
var levelup_overlay: CanvasLayer
var loop_choice: CanvasLayer
var game_over: CanvasLayer
var pause_menu: CanvasLayer
var wand_shop: CanvasLayer
var spell_replace: CanvasLayer
var fx_manager: Node
var joystick: CanvasLayer

var _prev_level := 1
var _levelup_queue := 0
var _choice_busy := false  # 替换界面 await 期间的防重入守卫（修复升级满格死锁）
var _replace_choice := -1   # 替换界面选择结果（具名回调写入；lambda 按值捕获不可用）
var _replace_done := false  # 替换选择已完成标志
var _hit_protect := 0.0

func _ready() -> void:
	randomize()
	SynergyRegistry.load_synergy_scripts()  # 流派机制脚本注册（先于战斗）
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
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.boss_died.connect(_on_boss_died)
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
	wand_shop = load(WAND_SHOP_SCENE).instantiate()
	wand_shop.name = "WandShop"
	wand_shop.hide()
	add_child(wand_shop)
	spell_replace = load(SPELL_REPLACE_SCENE).instantiate()
	spell_replace.name = "SpellReplace"
	spell_replace.hide()
	add_child(spell_replace)
	joystick = load(JOYSTICK_SCRIPT).new()
	joystick.name = "VirtualJoystick"
	add_child(joystick)
	move_child(joystick, 0)  # 树序最前 = 绘制在 HUD 之下（HUD 按钮仍可点）

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
		if camera.has_method("snap_to_player"):
			camera.snap_to_player()  # 开局/切关立即对准（跳过 smoothing），避免从角落滑入
		else:
			camera.global_position = player.position
	level_node = load(LEVEL_SCENE).instantiate()
	var levels: Array = GameState.tables.get("levels", {}).get("levels", [])
	var idx: int = clampi(GameState.run.level - 1, 0, levels.size() - 1)
	var level_id: String = str(levels[idx].get("id", "level_1"))
	# 读档恢复（main_menu 继续）时保留波次进度与血量，回到离开时的对局；
	# 新开局/切关才重置（2026-08-10 修复：此前无条件重置导致"继续"从第一波重来）
	var resumed: bool = bool(GameState.run.get("resumed", false))
	if resumed:
		GameState.run["resumed"] = false  # 消费标志，后续切关正常重置
	else:
		GameState.run.level_elapsed = 0.0  # 必须先重置：spawner.setup 依赖它计算波次起点
		GameState.run.hp = GameState.run.max_hp
	level_node.init_level(level_id)
	add_child(level_node)
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
	_reset_joystick()  # 升级弹出前清残留：防止升级瞬间按着的触摸在暂停期残留
	get_tree().paused = true
	var choices: Array = GameState.roll_item_choices(3)
	levelup_overlay.show_choices(choices)
	levelup_overlay.show()
	if not levelup_overlay.choice_made.is_connected(_on_choice_made):
		levelup_overlay.choice_made.connect(_on_choice_made)

func _on_choice_made(item_id: String) -> void:
	if _choice_busy:
		return
	if str(item_id).begins_with("spell_part:"):
		var parts: PackedStringArray = str(item_id).split(":")
		var core_id: String = parts[1] if parts.size() > 1 else ""
		var shell_id: String = parts[2] if parts.size() > 2 else ""
		if GameState.grid_full():
			# 法术栏已满：弹出替换界面（替换某个现有法术或放弃新法术）
			# 先隐藏升级面板并置忙碌标志：await 挂起期间防止重入/autoplay 卡死
			levelup_overlay.hide()
			_choice_busy = true
			get_tree().paused = true
			spell_replace.show_replace(core_id, shell_id, GameState.run.grid)
			# 超时兜底：若 UI 未响应（iOS 触摸异常/失焦），8s 后自动放弃，保证不卡死
			var choice: int = await _wait_replace_choice()
			_choice_busy = false
			get_tree().paused = false
			_reset_joystick_deferred()
			if choice >= 0:
				GameState.replace_spell(choice, core_id, shell_id)
		else:
			GameState.add_spell_part(core_id, shell_id)
	else:
		GameState.add_item(item_id)
	GameState.apply_item_effects_to_stats()
	levelup_overlay.hide()
	_levelup_queue -= 1
	get_tree().paused = false
	_reset_joystick_deferred()
	if _levelup_queue > 0:
		_show_levelup()

func _wait_replace_choice() -> int:
	## 等待替换界面选择（choose_made），带 8s 超时兜底：
	## 用信号竞速——choose_made 或超时先到者胜，超时返回 -1（放弃）。
	## 注意：替换界面弹出时游戏 paused=true，create_timer 必须 process_always=true，
	## 否则 timer 在暂停期不触发 → while 永不退出 → 替换后卡死。
	## 坑（2026-08-10）：不要用 lambda 写回调——GDScript lambda 按值捕获局部变量，
	## 回调里修改 timeout_ok/choice 不生效，导致 while 永远等不到信号（实测卡死）。
	## 必须用成员变量 + 具名方法（_on_replace_choice）。
	_replace_choice = -1
	_replace_done = false
	spell_replace.choose_made.connect(_on_replace_choice)
	var waited := 0.0
	while not _replace_done and waited < 8.0:
		await get_tree().create_timer(0.1, true).timeout  # process_always=true：暂停期也计时
		waited += 0.1
	spell_replace.choose_made.disconnect(_on_replace_choice)
	return _replace_choice


func _on_replace_choice(idx: int) -> void:
	## 替换界面选择回调（具名方法：成员变量跨协程共享，lambda 值捕获不可用）
	if _replace_done:
		return
	_replace_choice = idx
	_replace_done = true

func _reset_joystick() -> void:
	## 恢复游戏时重置摇杆触摸状态（iOS：升级/暂停期间 touch up 被丢弃，
	## 残留 index 导致恢复后摇杆不响应——升级后动不了的根因修复）
	if is_instance_valid(joystick) and joystick.has_method("reset_state"):
		joystick.call("reset_state")

func _reset_joystick_deferred() -> void:
	## 延迟一帧重置：避开 paused 过渡帧（iOS 上恢复瞬间的触摸 press 可能被
	## 摇杆的 paused 检查吞掉，导致"要点多次才动"——延迟到下一帧重置，
	## 让玩家恢复后的第一次触摸能正常建立移动）
	call_deferred("_reset_joystick")

func _on_enemy_died(enemy_id: String, pos: Vector2, xp: int, gold: int, is_elite: bool = false) -> void:
	GameState.run.kills += 1
	var xp_mult := 1.0 + GameState.aggregate_bonus("xp")
	GameState.add_xp(int(xp * xp_mult))
	# 金币改为走击杀掉落判定（kill_drops prob 门控），不再无条件发放（2026-08-10 平衡调整）
	_roll_drop(pos, gold)
	if is_elite:
		# 精英怪必掉血包：恢复最大生命 10%（掉落物形式，可拾取）
		var pct: float = float(GameState.tables.get("drops", {}).get("elite_drops", {}).get("heal_pct", 0.10))
		_spawn_health_pack(pos, pct)
	EventBus.fx_explosion.emit(pos, "blade")

func _on_damage_dealt(dmg: int, _pos: Vector2, _is_crit: bool) -> void:
	## 吸血：所有伤害来源（投射物/召唤物）统一走此通道，全局上限见 GameState
	var lifesteal: float = float(GameState.run.get("lifesteal", 0.0))
	if lifesteal > 0.0:
		GameState.heal(float(dmg) * lifesteal)
	SynergyRegistry.trigger("damage_dealt", {"dmg": dmg, "pos": _pos, "crit": _is_crit})

func _on_boss_died(pos: Vector2) -> void:
	## Boss 击杀必掉大血包：恢复最大生命 30%
	var pct: float = float(GameState.tables.get("drops", {}).get("boss_drops", {}).get("heal_pct", 0.30))
	_spawn_health_pack(pos, pct)

func _spawn_health_pack(pos: Vector2, heal_pct: float) -> void:
	var pack: Node = load(HEALTH_PACK_SCENE).instantiate()
	pack.setup(heal_pct)
	pack.global_position = pos
	add_child(pack)  # 挂在 game_root 下：切关清关卡节点时血包不消失

func _roll_drop(pos: Vector2, gold_value: int = 0) -> void:
	## 击杀掉落：kill_drops 的 prob 是独立命中概率（非表内权重归一，2026-08-10 平衡调整）。
	## - type=gold：发放该敌人的基础金币（enemies.json gold × 全局金币加成），
	##   属于真实掉落并重置保底计数；未命中（概率 miss）时计为空刀。
	## - 保底奖励：连续空刀达到 pity_threshold 后补发 15 金币（不再每 8 杀必发）。
	var drops: Dictionary = GameState.tables.get("drops", {})
	var kill_drops: Array = drops.get("kill_drops", [])
	var pity: int = drops.get("pity_threshold", 8)
	if GameState.run.pity >= pity:
		GameState.run.pity = 0
		GameState.add_gold(15)
		return
	var kind := ""
	for d in kill_drops:
		if randf() < d.get("prob", 0.0):
			kind = str(d.get("type", "gold"))
			break
	if kind == "":
		GameState.run.pity += 1
		return
	match kind:
		"gold":
			var gold_mult := 1.0 + GameState.aggregate_bonus("gold")
			GameState.add_gold(maxi(int(gold_value * gold_mult), 0))
			GameState.run.pity = 0
		"item":
			var item_id := _roll_random_item()
			if item_id != "":
				_spawn_pickup(pos, "item", item_id, str(GameState.item_def(item_id).get("icon", "")))
			GameState.run.pity = 0
		"spell_part":
			var core_id := _roll_core()
			var shell_id := _roll_shell()
			var icon := ""
			for c in GameState.tables.get("spells", {}).get("cores", []):
				if str(c.get("id", "")) == core_id:
					icon = str(c.get("icon", ""))
					break
			_spawn_pickup(pos, "spell_part", "%s:%s" % [core_id, shell_id], icon)
			GameState.run.pity = 0
		"trinket":
			var trinket_id := _roll_trinket()
			_spawn_pickup(pos, "trinket", trinket_id, str(GameState.item_def(trinket_id).get("icon", "")))
			GameState.run.pity = 0
		"heal":
			GameState.run.hp = mini(GameState.run.max_hp, GameState.run.hp + 18)
			EventBus.fx_explosion.emit(pos, "ice")
			GameState.run.pity = 0
		_:
			GameState.run.pity += 1

func _spawn_pickup(pos: Vector2, kind: String, payload: String, icon_path: String) -> void:
	## 掉落物实体化：物品/法术/饰品以掉落物形式出现，玩家触碰拾取（不再自动进包）
	var pickup: Node = load(ITEM_PICKUP_SCENE).instantiate()
	pickup.setup(kind, payload, icon_path)
	pickup.global_position = pos
	add_child(pickup)

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
	# 磐石护甲 / 防御护符：减伤（曲线从数据表读取，避免与 items.json 不一致）
	var stone := GameState.item_value(
		GameState.item_def("stone_armor").get("curve", {"type": "linear", "base": 0.06, "k": 0.06, "cap": 0.35}),
		GameState.total_stacks("stone_armor")
	)
	var amulet := GameState.item_value(
		GameState.item_def("defense_amulet").get("curve", {"type": "linear", "base": 0.03, "k": 0.03, "cap": 0.20}),
		GameState.total_stacks("defense_amulet")
	)
	# 注意：stone_armor 自带 "defense" tag，aggregate_bonus("defense") 会重复计入其曲线值，
	# 层数高时减伤可能 >100% 导致伤害变负（怪物打玩家=加血）。只按 stone 曲线结算，
	# 防御流成型奖励（synergy_bonus.defense）单独附加到反弹比例上。
	# 2026-08-10 平衡调整：防御减伤合计封顶 50%（stone 35% + amulet 15% 已达上限，防御不再叠满免伤）
	taken *= 1.0 - minf(stone + amulet, 0.50)
	taken *= 1.0 + 0.15 * GameState.total_stacks("curse_ring")
	# 移M10 暴走：受击伤害 +20%（run.wind_m10_taken_mult 读取点接线）
	taken *= maxf(float(GameState.run.get("wind_m10_taken_mult", 1.0)), 0.0)
	var taken_int := int(taken)
	# 荆棘甲改造：反弹所受伤害给攻击者（近战敌人直接受伤）
	var reflect_pct: float = GameState.item_value(
		{"curve": {"type": "linear", "base": 0.40, "k": 0.35, "cap": 0.95}},
		GameState.total_stacks("thorn_reflect")
	)
	# 防御流成型奖励：附加到反弹比例（不在减伤上重复叠加）
	reflect_pct += float(GameState.run.get("synergy_bonus", {}).get("defense", 0.0))
	if reflect_pct > 0.0 and taken_int > 0:
		var reflected := int(taken_int * reflect_pct)
		var attacker := _nearest_enemy(pos)
		if attacker != null and is_instance_valid(attacker) and attacker.has_method("take_damage"):
			attacker.take_damage(reflected, "blade", false)
			EventBus.damage_dealt.emit(reflected, attacker.global_position, false)
			# 血棘甲：反弹伤害的 4% 回血（防御流专属吸血）
			var blood: float = GameState.item_value(
				{"curve": {"type": "linear", "base": 0.04, "k": 0.0}},
				GameState.total_stacks("blood_thorn")
			)
			if blood > 0.0:
				GameState.heal(float(reflected) * blood)
	GameState.run.hp = mini(GameState.run.max_hp, int(maxf(GameState.run.hp - taken, 0)))
	SynergyRegistry.trigger("player_hit", {"dmg": taken_int, "pos": pos, "taken": taken, "attacker": null})
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

func _nearest_enemy(pos: Vector2) -> Node:
	var best: Node = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d: float = pos.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

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
	# 法杖商店：Boss 战后用金币购买法杖（关闭后继续关卡流程）
	get_tree().paused = true
	wand_shop.show_shop()
	await wand_shop.shop_closed
	get_tree().paused = false
	_reset_joystick_deferred()
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
	if not get_tree().paused:
		_reset_joystick_deferred()
	pause_menu.visible = get_tree().paused
