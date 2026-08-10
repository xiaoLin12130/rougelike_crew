extends Node2D
## 敌人缓存性能基准（P0）：同一场景跑 300 帧，优化前后各跑一次对比。
## Phase A（微基准，隔离查询动作本身）：
##   同一进程内 2000 次 get_nodes_in_group("enemy") vs 2000 次
##   GameState.get_enemies() 的平均耗时；优化前版本无缓存 API 时自动跳过。
## Phase B（场景基准，对齐真实战斗热点）：
##   - 32 敌人（上限，hp 锁 1e9 无敌消除击杀随机性）燃烧+中毒 → 每帧 enemy_status
##     tick ×2 触发全流派钩子；固定种子使两版负载完全一致；
##   - ice_synergy._scan_freeze 无门控每帧扫描全部敌人（旗舰热路径）；
##   - spawner 每帧 _enemies_alive 存活数查询；melee 常驻索敌（攻速 +500%）；
##   - 周期触发 fire projectile_hit 生成火地 zone（zone tick 查询）；
##   指标：TIME_PROCESS / TIME_PHYSICS_PROCESS 均值（跳过前 30 帧预热）。
## 运行：godot --headless --fixed-fps 60 --path . res://scripts/tests/bench_enemy_cache.tscn

const ENEMY_SCENE := preload("res://scenes/game/enemy.tscn")
const SPAWNER_SCRIPT := preload("res://scripts/enemies/spawner.gd")
const MELEE_SCRIPT := preload("res://scripts/combat/melee_attack.gd")

var _frame := 0
var _sum_p := 0.0
var _sum_ph := 0.0
var _samples := 0
var _t0 := 0
var _enemies: Array = []
var _fire_trigger_cd := 0


func _ready() -> void:
	GameState.new_run()
	seed(12345)  # 固定种子：优化前后两版击杀/暴击序列完全一致，A/B 公平
	GameState.run.crit_chance = 0.0
	GameState.run.attack_speed_bonus = 5.0  # 攻速 +500%：melee 高频索敌
	var items: Dictionary = GameState.run.items
	items["fire_dragon_breath"] = 1  # 火M10：projectile_hit 火地 → zone tick 查询
	items["fire_ash_blast"] = 1      # 火M1：敌人死亡引爆查询
	items["fire_pyromaniac"] = 1     # 火M3：燃烧传染查询
	items["fire_fire_nova"] = 1      # 火M4：新星叠层/引爆查询
	items["poison_m3"] = 1           # 毒M3：毒雾扩散查询
	items["ice_m7"] = 1              # 冰M7：每帧扫描相关
	items["water_marsh"] = 1         # 水M1：水泽区域查询
	items["melee_m1"] = 1            # 近M1：旋风斩溅射查询
	var player := CharacterBody2D.new()
	player.name = "BenchPlayer"
	player.global_position = Vector2(500, 420)
	player.add_to_group("player")
	add_child(player)
	SynergyRegistry.load_synergy_scripts()
	# spawner：不刷怪（超长 wave 时间），但每帧跑 _enemies_alive 存活数查询
	var spawner := SPAWNER_SCRIPT.new()
	spawner.name = "BenchSpawner"
	spawner.setup([{"time": 999999.0, "duration": 999999.0, "interval": 999999.0, "spawn": {}}])
	add_child(spawner)
	# melee：常驻索敌（玩家子节点），每帧迭代敌人
	var melee := MELEE_SCRIPT.new()
	melee.name = "BenchMelee"
	player.add_child(melee)
	# 32 敌人：前 8 只贴近玩家（melee 持续命中挥砍），全部燃烧+中毒+无敌
	for i in 32:
		var e := ENEMY_SCENE.instantiate()
		e.setup("slime", 1, 1)
		e.speed = 0.0
		e.hp = 1.0e9
		e.max_hp = 1.0e9
		if i < 8:
			e.global_position = Vector2(500 + 40.0 * cos(TAU * float(i) / 8.0), 420 + 40.0 * sin(TAU * float(i) / 8.0))
		else:
			e.global_position = Vector2(150 + ((i - 8) % 6) * 180, 120 + ((i - 8) / 6) * 170)
		e._burn_left = 999.0
		e._poison_left = 999.0
		add_child(e)
		_enemies.append(e)
	_run_micro()
	_t0 = Time.get_ticks_msec()


func _run_micro() -> void:
	## 微基准：旧方式（组查询）vs 缓存查询，各 2000 次取平均
	var group: Array = []
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		group = get_tree().get_nodes_in_group("enemy")
	var t1 := Time.get_ticks_usec()
	var group_us := float(t1 - t0) / 2000.0
	if GameState.has_method("get_enemies"):
		var cache: Array = []
		var t2 := Time.get_ticks_usec()
		for i in 2000:
			cache = GameState.get_enemies()
		var t3 := Time.get_ticks_usec()
		var cache_us := float(t3 - t2) / 2000.0
		print("[BENCH-MICRO] group_query=%.3fus cache_query=%.3fus speedup=%.1fx" % [group_us, cache_us, group_us / cache_us])
	else:
		print("[BENCH-MICRO] group_query=%.3fus cache_query=N/A(baseline)" % group_us)


func _physics_process(_delta: float) -> void:
	## 周期生成 fire 火地（模拟火法持续输出 → zone tick 查询）
	_fire_trigger_cd -= 1
	if _fire_trigger_cd <= 0 and not _enemies.is_empty():
		_fire_trigger_cd = 8
		var e = _enemies[randi() % _enemies.size()]
		if is_instance_valid(e):
			SynergyRegistry.trigger("projectile_hit", {
				"enemy": e, "dmg": 10, "element": "fire", "crit": false, "pos": e.global_position})


func _process(_delta: float) -> void:
	_frame += 1
	# 跳过前 30 帧预热（import/加载抖动），统计 30..300 帧
	if _frame > 30 and _frame <= 300:
		_sum_p += Performance.get_monitor(Performance.TIME_PROCESS)
		_sum_ph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		_samples += 1
	if _frame == 300:
		var wall := float(Time.get_ticks_msec() - _t0) / 1000.0
		var fps := float(_samples) / maxf(wall, 0.001)
		var avg_p := _sum_p / float(_samples) * 1000.0
		var avg_ph := _sum_ph / float(_samples) * 1000.0
		var enemies: int = get_tree().get_nodes_in_group("enemy").size()  # 版本无关计数
		print("[BENCH] frames=%d time_process=%.4fms time_physics=%.4fms total=%.4fms fps=%.1f enemies=%d" % [_samples, avg_p, avg_ph, avg_p + avg_ph, fps, enemies])
		get_tree().quit(0)
