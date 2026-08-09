extends EnemyBase
## Boss：阶段转换（召唤/狂暴/弹幕）+ 大额掉落

var phase := 0
var _phases: Array = []
var _summon_enemy := "slime"
var _is_final := false

func setup_boss(boss_id: String, level: int, loop: int, final_boss: bool = false) -> void:
	_is_final = final_boss
	enemy_id = boss_id
	conf = _find_boss_conf(boss_id)
	var base_hp: float = conf.get("hp", 600)
	var base_atk: float = conf.get("attack", 18)
	hp = GameState.enemy_hp(base_hp, level, loop)
	if _is_final:
		hp *= 1.6  # 最终 Boss 额外加强
	max_hp = hp
	attack = int(roundi(GameState.enemy_atk(base_atk, level, loop)))
	speed = float(conf.get("speed", 50))
	scale = Vector2.ONE * float(conf.get("size", 1.6))
	_phases = conf.get("phases", [])
	match boss_id:
		"slime_king":
			_summon_enemy = "slime"
		"tree_golem":
			_summon_enemy = "goblin"
		"skeleton_king":
			_summon_enemy = "skeleton"
		"imp_king":
			_summon_enemy = "imp"
		"ancient_guardian":
			_summon_enemy = "goblin_archer"
		_:
			_summon_enemy = "bat"
	EventBus.boss_spawned.emit(str(conf.get("name", boss_id)), int(max_hp))
	queue_redraw()

func _take_raw(dmg: int) -> void:
	if _dead or dmg <= 0:
		return
	hp -= dmg
	_flash()
	EventBus.boss_hp_changed.emit(int(maxf(hp, 0.0)), int(max_hp))
	queue_redraw()
	if hp <= 0.0:
		_die()

func _draw() -> void:
	# Boss 头顶血条（局部坐标，随 Boss 缩放）
	var w := 90.0
	var h := 7.0
	var y := -34.0
	draw_rect(Rect2(-w / 2.0, y, w, h), Color(0.08, 0.05, 0.12, 0.9))
	draw_rect(Rect2(-w / 2.0, y, w, h), Color(0.4, 0.3, 0.55, 1.0), false, 1.5)
	if max_hp > 0.0:
		var ratio := clampf(hp / max_hp, 0.0, 1.0)
		var fill := Color(1.0, 0.32, 0.28) if ratio > 0.33 else Color(1.0, 0.75, 0.2)
		draw_rect(Rect2(-w / 2.0 + 1.0, y + 1.0, (w - 2.0) * ratio, h - 2.0), fill)

func _find_boss_conf(boss_id: String) -> Dictionary:
	for b in GameState.tables.get("enemies", {}).get("bosses", []):
		if str(b.get("id", "")) == boss_id:
			return b
	return {}

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	_tick(delta)
	_check_phase()
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	var spd := speed * (0.5 if _freeze_left > 0.0 else 1.0) * (1.3 if phase >= 2 else 1.0)
	if dist > 40.0:
		velocity = to_player.normalized() * spd
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	if dist <= 26.0 and _atk_cd <= 0.0:
		_atk_cd = 1.2
		EventBus.player_hit.emit(attack, global_position)
	if _shoot_cd <= 0.0 and conf.get("range", 0) > 0:
		_shoot_cd = 2.2
		var shots := 3 if phase >= 2 else 1
		for i in shots:
			var ang := to_player.angle() + deg_to_rad((i - shots / 2.0 + 0.5) * 18.0)
			_fire_bullet(Vector2.from_angle(ang), 180.0)
	global_position = global_position.clamp(ARENA.position, ARENA.end)

func _check_phase() -> void:
	var ratio := hp / max_hp
	while phase < _phases.size() and ratio <= float(_phases[phase]):
		phase += 1
		EventBus.fx_explosion.emit(global_position, "lightning")
		EventBus.screen_shake.emit(8.0)
		_spawn_minions(2)

func _spawn_minions(n: int) -> void:
	var scene := preload("res://scenes/game/enemy.tscn")
	for i in n:
		var e := scene.instantiate()
		e.setup(_summon_enemy, GameState.run.level, GameState.run.loop)
		e.global_position = global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50))
		get_tree().current_scene.add_child(e)

func _die() -> void:
	_dead = true
	EventBus.boss_died.emit()
	var gold: int = int(conf.get("gold", 100))
	var xp: int = GameState.enemy_xp(float(conf.get("xp", 200)), GameState.run.level, GameState.run.loop)
	if _is_final:
		gold *= 3
		xp *= 3
	EventBus.enemy_died.emit(enemy_id, global_position, xp, gold)
	EventBus.fx_explosion.emit(global_position, "fire")
	EventBus.fx_explosion.emit(global_position, "lightning")
	EventBus.screen_shake.emit(12.0)
	queue_free()
