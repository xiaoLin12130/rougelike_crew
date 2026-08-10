extends Node2D
## 站桩压力探针：按 levels.json L1 波次真实刷怪，假玩家原地不动（无操作），
## 统计 60s 内累计 player_hit 伤害，用于对比小怪加强前后"站桩掉血"差异。
## 运行：godot --headless --path . res://tools/tests/standing_pressure_probe.tscn -- --mode=noattack
##       godot --headless --path . res://tools/tests/standing_pressure_probe.tscn -- --mode=turret
## mode=noattack：玩家完全无输出（最坏情况，测试纯站桩压力）
## mode=turret  ：假玩家按 balance.base_dps(25) 自动攻击最近敌人（近似站桩自动攻击场景）

const PLAYER_POS := Vector2(640, 360)
const DURATION := 60.0

var _mode := "noattack"
var _dmg := 0
var _hits := 0
var _player: CharacterBody2D
var _spawner: Node
var _turret_dps := 25.0
var _last_report := -1
var _first_hit_t := -1.0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode=") or a.begins_with("mode="):
			_mode = a.get_slice("=", 1)
		if a.begins_with("--dps=") or a.begins_with("dps="):
			_turret_dps = float(a.get_slice("=", 1))
	# 独立初始化 run（不依赖 game_root），HP 按 balance.player.hp = 85
	GameState.new_run()
	GameState.run.max_hp = int(GameState.balance().get("player", {}).get("hp", 85))
	GameState.run.hp = GameState.run.max_hp
	GameState.run.time = 0.0
	EventBus.player_hit.connect(_on_player_hit)
	_setup_player()
	_setup_spawner()
	print("[STANDING] mode=%s turret_dps=%.1f max_hp=%d start" % [_mode, _turret_dps, GameState.run.max_hp])

func _setup_player() -> void:
	_player = CharacterBody2D.new()
	_player.name = "StandDummy"
	_player.add_to_group("player")
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	var col := CollisionShape2D.new()
	col.shape = shape
	_player.add_child(col)
	_player.global_position = PLAYER_POS
	add_child(_player)

func _setup_spawner() -> void:
	var levels: Dictionary = GameState.tables.get("levels", {})
	var lv: Dictionary = levels.get("levels", [])[0]
	_spawner = Node.new()
	_spawner.name = "StandSpawner"
	_spawner.set_script(load("res://scripts/enemies/spawner.gd"))
	add_child(_spawner)
	_spawner.setup(lv.get("waves", []))

func _on_player_hit(dmg: int, _pos: Vector2) -> void:
	_dmg += dmg
	_hits += 1
	if _first_hit_t < 0.0:
		_first_hit_t = GameState.run.time

func _physics_process(delta: float) -> void:
	# 独立场景没有 game_root 推进游戏时钟：手动推进 run.time（spawner 依赖它）
	GameState.run.time += delta
	if _mode == "turret":
		_turret_tick(delta)
	var t: float = GameState.run.time
	if t >= DURATION:
		var hp_left: int = maxi(GameState.run.max_hp - _dmg, 0)
		print("[STANDING] mode=%s 60s total_dmg=%d hits=%d first_hit=%.1fs hp_left=%d (max_hp=%d)" % [
			_mode, _dmg, _hits, _first_hit_t, hp_left, GameState.run.max_hp])
		var ok := _dmg >= 30
		print("[STANDING] %s" % ("PRESSURE OK" if ok else "PRESSURE WEAK"))
		get_tree().quit(0 if ok else 1)
		return
	var sec := int(t) / 10 * 10
	if sec != _last_report:
		_last_report = sec
		print("[STANDING] t=%3.0f  dmg=%4d  hits=%3d" % [t, _dmg, _hits])

func _turret_tick(delta: float) -> void:
	## 近似"站桩自动攻击"：对最近敌人持续造成 base_dps 伤害（无吸血/无升级）
	var best: Node = null
	var best_d: float = 1e9
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d: float = e.global_position.distance_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best != null and best.has_method("take_damage"):
		best.take_damage(maxi(int(_turret_dps * delta), 1), "physical", false)
