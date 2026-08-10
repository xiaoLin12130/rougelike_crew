extends Node
## 波次生成器：按 levels.json 时间线刷怪，全清后通知关卡

const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const ARENA := Rect2(40, 16, 1200, 688)  # 刷怪区=整张地图（草地铺满全屏后 y 16-704 可出怪）
const MAX_CONCURRENT := 32

var _waves: Array = []
var _active_wave := -1
var _wave_elapsed := 0.0
var _spawn_timer := 0.0
var _done := false
var _level_start_time := 0.0
var _waves_done_since := -1.0

func setup(waves: Array) -> void:
	_waves = waves
	# 波次时间基准：支持存档继续（恢复时从存档的关卡内时间续上）
	_level_start_time = GameState.run.time - GameState.run.get("level_elapsed", 0.0)
	print("[SPAWNER] setup at run.time=%.1f waves=%d" % [_level_start_time, _waves.size()])

func _physics_process(delta: float) -> void:
	if _done:
		return
	var t: float = GameState.run.time - _level_start_time
	if _active_wave + 1 < _waves.size() and t >= float(_waves[_active_wave + 1].get("time", 0)):
		_active_wave += 1
		_wave_elapsed = 0.0
		_spawn_timer = 0.0
		EventBus.wave_state_changed.emit("第 %d 波来袭！" % (_active_wave + 1))
		print("[SPAWNER] wave %d active rel=%.1f abs=%.1f level_start=%.1f" % [
			_active_wave + 1, t, GameState.run.time, _level_start_time])
	if _active_wave >= 0:
		_wave_elapsed += delta
		_spawn_timer += delta
		var wave: Dictionary = _waves[_active_wave]
		if _wave_elapsed <= float(wave.get("duration", 30)) and _spawn_timer >= float(wave.get("interval", 2.0)):
			_spawn_timer = 0.0
			_spawn_group(wave)
	if _active_wave >= 0 and _wave_elapsed > float(_waves[_active_wave].get("duration", 30)):
		var all_waves_done: bool = _active_wave + 1 >= _waves.size()
		if all_waves_done:
			if _waves_done_since < 0.0:
				_waves_done_since = GameState.run.time
			# 全波完成且场上清空；或全波完成 15 秒兜底（防分裂/残留怪卡场）
			var timeout_passed: bool = GameState.run.time - _waves_done_since > 15.0
			if _enemies_alive() == 0 or timeout_passed:
				_done = true
				EventBus.wave_state_changed.emit("全清！Boss 降临！")
				EventBus.wave_state_changed.emit("clear")
	else:
		_waves_done_since = -1.0

func _spawn_group(wave: Dictionary) -> void:
	var spawns: Dictionary = wave.get("spawn", {})
	# 精英率 = 波次数据优先；数据缺失时用关卡/波次兜底曲线（防并行数据覆盖后无精英）
	var fallback: float = clampf(
		0.06 + 0.02 * float(GameState.run.level - 1) + 0.04 * float(_active_wave),
		0.0, 0.15)
	var elite_chance: float = float(wave.get("elite_chance", fallback))
	for enemy_id in spawns:
		var count: int = int(spawns[enemy_id])
		for i in count:
			_spawn_one(str(enemy_id), elite_chance)

func _spawn_one(enemy_id: String, elite_chance: float) -> void:
	if _enemies_alive() >= MAX_CONCURRENT:
		return  # 场上敌人上限，防失控
	var e := ENEMY_SCENE.instantiate()
	var affix := ""
	if randf() < elite_chance:
		var conf := _enemy_conf(enemy_id)
		var pool: Array = conf.get("affix_pool", [])
		if not pool.is_empty():
			affix = str(pool[randi() % pool.size()])
	e.setup(enemy_id, GameState.run.level, GameState.run.loop, affix)
	if affix != "":
		e.set_elite()
	e.global_position = _edge_position()
	add_child(e)  # 挂在关卡下：切关时随关卡一起清理

func _enemy_conf(enemy_id: String) -> Dictionary:
	for e in GameState.tables.get("enemies", {}).get("enemies", []):
		if str(e.get("id", "")) == enemy_id:
			return e
	return {}

func _edge_position() -> Vector2:
	var side := randi() % 4
	match side:
		0:
			return Vector2(randf_range(ARENA.position.x, ARENA.end.x), ARENA.position.y)
		1:
			return Vector2(randf_range(ARENA.position.x, ARENA.end.x), ARENA.end.y)
		2:
			return Vector2(ARENA.position.x, randf_range(ARENA.position.y, ARENA.end.y))
		_:
			return Vector2(ARENA.end.x, randf_range(ARENA.position.y, ARENA.end.y))

func _enemies_alive() -> int:
	return get_tree().get_nodes_in_group("enemy").size()
